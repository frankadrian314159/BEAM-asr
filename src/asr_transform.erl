%% Aggregate Scalar Replacement for Erlang.
%%
%% Whole-module opt-in: -compile({parse_transform, asr_transform}).
%%
%% Unboxes a tail-recursive record accumulator into scalar arguments,
%% re-boxing only at the base case. See BEAM-asr design notes for the full
%% qualification/rewrite spec this module implements.
-module(asr_transform).
-export([parse_transform/2]).

%% ---------------------------------------------------------------------
%% Entry point
%% ---------------------------------------------------------------------

parse_transform(Forms, _Options) ->
    Records = collect_records(Forms),
    Exports = collect_exports(Forms),
    Plans = lists:filtermap(
              fun(Form) -> try_qualify_form(Form, Forms, Records, Exports) end,
              Forms),
    apply_plans(Forms, Plans).

try_qualify_form({function, _Anno, Name, Arity, Clauses}, Forms, Records, Exports) ->
    case sets:is_element({Name, Arity}, Exports) of
        true -> false;
        false ->
            case try_qualify(Name, Arity, Clauses, Forms, Records) of
                {ok, Plan} -> {true, Plan};
                decline -> false
            end
    end;
try_qualify_form(_Form, _Forms, _Records, _Exports) ->
    false.

%% ---------------------------------------------------------------------
%% Collecting record definitions and exports
%% ---------------------------------------------------------------------

collect_records(Forms) ->
    lists:foldl(
      fun(Form, Acc) ->
              case Form of
                  {attribute, _Anno, record, {Name, FieldDecls}} ->
                      Fields = [field_name(FD) || FD <- FieldDecls],
                      maps:put(Name, Fields, Acc);
                  _ -> Acc
              end
      end, #{}, Forms).

field_name({record_field, _, {atom, _, FName}}) -> FName;
field_name({record_field, _, {atom, _, FName}, _Default}) -> FName;
field_name({typed_record_field, RF, _Type}) -> field_name(RF).

collect_exports(Forms) ->
    lists:foldl(
      fun(Form, Acc) ->
              case Form of
                  {attribute, _Anno, export, List} ->
                      lists:foldl(fun(NA, A) -> sets:add_element(NA, A) end, Acc, List);
                  _ -> Acc
              end
      end, sets:new(), Forms).

%% ---------------------------------------------------------------------
%% Qualification
%% ---------------------------------------------------------------------

try_qualify(Name, Arity, Clauses, Forms, Records) ->
    try_positions(Name, Arity, Clauses, Forms, Records, 1).

try_positions(_Name, Arity, _Clauses, _Forms, _Records, Pos) when Pos > Arity ->
    decline;
try_positions(Name, Arity, Clauses, Forms, Records, Pos) ->
    case try_qualify_at(Name, Arity, Pos, Clauses, Forms, Records) of
        {ok, Plan} -> {ok, Plan};
        decline -> try_positions(Name, Arity, Clauses, Forms, Records, Pos + 1)
    end.

try_qualify_at(Name, Arity, Pos, Clauses, Forms, Records) ->
    try
        {PlansRev, RecNameAcc} = classify_clauses(Name, Arity, Pos, Clauses),
        ClausePlans = lists:reverse(PlansRev),
        RecName = case RecNameAcc of
                      undefined -> throw(decline);
                      R -> R
                  end,
        Fields = case maps:find(RecName, Records) of
                     {ok, Fs} -> Fs;
                     error -> throw(decline)
                 end,
        HasBase = lists:any(fun(CP) -> maps:get(kind, CP) =:= base end, ClausePlans),
        HasRec = lists:any(fun(CP) -> maps:get(kind, CP) =:= recursive end, ClausePlans),
        (HasBase andalso HasRec) orelse throw(decline),
        lists:foreach(fun(CP) -> check_collision(CP, Fields) end, ClausePlans),
        lists:foreach(fun(CP) -> validate_field_names(CP, Fields) end, ClausePlans),
        AllCalls = find_calls(Name, Arity, Forms),
        TailCalls = [maps:get(tail_call, CP) || CP <- ClausePlans,
                                                 maps:get(kind, CP) =:= recursive],
        EntryCalls = AllCalls -- TailCalls,
        lists:foreach(fun(C) -> check_full_construction(C, Pos, RecName, Fields) end, EntryCalls),
        {ok, #{name => Name, arity => Arity, pos => Pos, rec => RecName,
               fields => Fields, clause_plans => ClausePlans}}
    catch
        throw:decline -> decline
    end.

%% -- per-clause classification ------------------------------------------

classify_clauses(Name, Arity, Pos, Clauses) ->
    lists:foldl(
      fun(Clause, {PlansAcc, RecAcc}) ->
              {CP, RecAcc2} = classify_clause(Name, Arity, Pos, Clause, RecAcc),
              {[CP | PlansAcc], RecAcc2}
      end, {[], undefined}, Clauses).

classify_clause(Name, Arity, Pos, {clause, Anno, Patterns, Guard, Body}, RecAcc) ->
    PatP = lists:nth(Pos, Patterns),
    LastExpr = lists:last(Body),
    IsTailSelfCall = case LastExpr of
                         {call, _, {atom, _, Name}, Args} when length(Args) =:= Arity -> true;
                         _ -> false
                     end,
    case IsTailSelfCall of
        true ->
            classify_recursive(Pos, Anno, Patterns, Guard, Body, PatP, LastExpr, RecAcc);
        false ->
            case PatP of
                {var, _, VName} when VName =/= '_' ->
                    Uses = collect_var_uses(VName, {Guard, Body}),
                    case Uses of
                        [] ->
                            {#{kind => unrelated, anno => Anno, patterns => Patterns,
                               guard => Guard, body => Body}, RecAcc};
                        _ ->
                            classify_base(Anno, Patterns, Guard, Body, VName, Uses, RecAcc)
                    end;
                _ ->
                    {#{kind => unrelated, anno => Anno, patterns => Patterns,
                       guard => Guard, body => Body}, RecAcc}
            end
    end.

classify_base(Anno, Patterns, Guard, Body, VName, Uses, RecAcc) ->
    LastExpr = lists:last(Body),
    IsBareReturn = case LastExpr of
                       {var, _, VName} -> true;
                       _ -> false
                   end,
    BareCount = length([U || U <- Uses, U =:= bare]),
    case IsBareReturn of
        true -> (BareCount =:= 1) orelse throw(decline);
        false -> (BareCount =:= 0) orelse throw(decline)
    end,
    FieldReads = [R || {field_read, R, _F} <- Uses],
    RecAcc2 = unify_recname(RecAcc, FieldReads),
    {#{kind => base, anno => Anno, patterns => Patterns, guard => Guard,
       body => Body, var => VName}, RecAcc2}.

classify_recursive(Pos, Anno, Patterns, Guard, Body, PatP, TailCall, RecAcc) ->
    VName = case PatP of
                {var, _, V} when V =/= '_' -> V;
                _ -> throw(decline)
            end,
    {call, CAnno, CF, Args} = TailCall,
    ArgP = lists:nth(Pos, Args),
    OtherArgs = lists:sublist(Args, 1, Pos - 1) ++ lists:nthtail(Pos, Args),
    NonTailBody = lists:sublist(Body, 1, length(Body) - 1),
    Uses1 = collect_var_uses(VName, {Guard, NonTailBody, OtherArgs}),
    (lists:all(fun(U) -> U =/= bare end, Uses1)) orelse throw(decline),
    RecAcc1 = unify_recname(RecAcc, [R || {field_read, R, _F} <- Uses1]),
    {ArgKind, RecAcc2} =
        case ArgP of
            {record, _, RecName2, FieldList} ->
                InnerUses = collect_var_uses(VName, FieldList),
                (lists:all(fun(U) -> U =/= bare end, InnerUses)) orelse throw(decline),
                RA0 = unify_recname(RecAcc1, [RecName2]),
                RA1 = unify_recname(RA0, [R || {field_read, R, _F} <- InnerUses]),
                {{full, FieldList}, RA1};
            {record, _, {var, _, VName}, RecName2, FieldList} ->
                InnerUses = collect_var_uses(VName, FieldList),
                (lists:all(fun(U) -> U =/= bare end, InnerUses)) orelse throw(decline),
                RA0 = unify_recname(RecAcc1, [RecName2]),
                RA1 = unify_recname(RA0, [R || {field_read, R, _F} <- InnerUses]),
                {{update, FieldList}, RA1};
            {var, _, VName} ->
                {passthrough, RecAcc1};
            _ ->
                throw(decline)
        end,
    CP = #{kind => recursive, anno => Anno, patterns => Patterns, guard => Guard,
           body => Body, var => VName, tail_call => TailCall, tail_anno => CAnno,
           tail_f => CF, arg_kind => ArgKind},
    {CP, RecAcc2}.

unify_recname(Acc, []) -> Acc;
unify_recname(undefined, [R | Rs]) -> unify_recname(R, Rs);
unify_recname(Acc, [R | Rs]) when R =:= Acc -> unify_recname(Acc, Rs);
unify_recname(_Acc, [_R | _Rs]) -> throw(decline).

%% -- collision + field-name validation -----------------------------------

check_collision(#{kind := unrelated}, _Fields) -> ok;
check_collision(#{var := VName, patterns := Patterns, guard := Guard, body := Body}, Fields) ->
    ScalarNames = [scalar_name(VName, F) || F <- Fields],
    AllNames = sets:to_list(collect_var_names({Patterns, Guard, Body})),
    lists:foreach(fun(SN) -> (not lists:member(SN, AllNames)) orelse throw(decline) end,
                  ScalarNames).

validate_field_names(#{kind := unrelated}, _Fields) -> ok;
validate_field_names(#{kind := base, var := VName, guard := Guard, body := Body}, Fields) ->
    Uses = collect_var_uses(VName, {Guard, Body}),
    FieldAtoms = [F || {field_read, _R, F} <- Uses],
    lists:foreach(fun(F) -> lists:member(F, Fields) orelse throw(decline) end, FieldAtoms);
validate_field_names(#{kind := recursive, var := VName, guard := Guard, body := Body,
                        tail_call := TailCall}, Fields) ->
    Uses = collect_var_uses(VName, {Guard, Body, TailCall}),
    FieldAtoms = [F || {field_read, _R, F} <- Uses],
    lists:foreach(fun(F) -> lists:member(F, Fields) orelse throw(decline) end, FieldAtoms).

check_full_construction(CallTerm, Pos, RecName, Fields) ->
    {call, _Anno, _F, Args} = CallTerm,
    ArgP = lists:nth(Pos, Args),
    case ArgP of
        {record, _, RecName2, FieldList} when RecName2 =:= RecName ->
            FieldNames = [FN || {record_field, _, {atom, _, FN}, _} <- FieldList],
            (lists:sort(FieldNames) =:= lists:sort(Fields)) orelse throw(decline);
        _ ->
            throw(decline)
    end.

%% ---------------------------------------------------------------------
%% Generic AST helpers
%% ---------------------------------------------------------------------

%% Finds every {call, Anno, {atom, _, Name}, Args} of the given Arity
%% anywhere in Term (functions, guards, nested expressions - everything).
find_calls(Name, Arity, Term) ->
    find_calls(Name, Arity, Term, []).

find_calls(Name, Arity, Term, Acc) when is_tuple(Term) ->
    Acc1 = case Term of
               {call, _Anno, {atom, _, Name}, Args} when length(Args) =:= Arity ->
                   [Term | Acc];
               _ -> Acc
           end,
    lists:foldl(fun(E, A) -> find_calls(Name, Arity, E, A) end, Acc1, tuple_to_list(Term));
find_calls(Name, Arity, Term, Acc) when is_list(Term) ->
    lists:foldl(fun(E, A) -> find_calls(Name, Arity, E, A) end, Acc, Term);
find_calls(_Name, _Arity, _Term, Acc) ->
    Acc.

%% Collects every use of VarName in Term: {field_read, RecName, FieldAtom}
%% for a record-field read of VarName, or `bare` for any other occurrence.
%% A record_field read is a leaf - we do not recurse further into it once
%% matched, so its own {var, _, VarName} sub-term is not double-counted.
collect_var_uses(VarName, Term) ->
    collect_var_uses(VarName, Term, []).

collect_var_uses(VarName, {record_field, _, {var, _, VarName}, RecName, {atom, _, FieldAtom}}, Acc) ->
    [{field_read, RecName, FieldAtom} | Acc];
collect_var_uses(VarName, {var, _, VarName}, Acc) ->
    [bare | Acc];
collect_var_uses(VarName, Term, Acc) when is_tuple(Term) ->
    lists:foldl(fun(E, A) -> collect_var_uses(VarName, E, A) end, Acc, tuple_to_list(Term));
collect_var_uses(VarName, Term, Acc) when is_list(Term) ->
    lists:foldl(fun(E, A) -> collect_var_uses(VarName, E, A) end, Acc, Term);
collect_var_uses(_VarName, _Term, Acc) ->
    Acc.

collect_var_names(Term) ->
    collect_var_names(Term, sets:new()).

collect_var_names({var, _, VName}, Acc) when VName =/= '_' ->
    sets:add_element(VName, Acc);
collect_var_names(Term, Acc) when is_tuple(Term) ->
    lists:foldl(fun collect_var_names/2, Acc, tuple_to_list(Term));
collect_var_names(Term, Acc) when is_list(Term) ->
    lists:foldl(fun collect_var_names/2, Acc, Term);
collect_var_names(_Term, Acc) ->
    Acc.

scalar_name(VName, F) ->
    list_to_atom(atom_to_list(VName) ++ "_" ++ atom_to_list(F)).

find_field_expr(FieldList, F) ->
    case [E || {record_field, _, {atom, _, FN}, E} <- FieldList, FN =:= F] of
        [E | _] -> {ok, E};
        [] -> error
    end.

%% Replaces every {record_field, Anno, {var,_,VarName}, _RecName, {atom,_,F}}
%% occurrence in Term with the scalar variable for F. Generic otherwise.
subst_field_reads({record_field, Anno, {var, _, VName}, _RecName, {atom, _, F}}, VName, ScalarMap) ->
    {var, Anno, maps:get(F, ScalarMap)};
subst_field_reads(Term, VName, ScalarMap) when is_tuple(Term) ->
    list_to_tuple([subst_field_reads(E, VName, ScalarMap) || E <- tuple_to_list(Term)]);
subst_field_reads(Term, VName, ScalarMap) when is_list(Term) ->
    [subst_field_reads(E, VName, ScalarMap) || E <- Term];
subst_field_reads(Term, _VName, _ScalarMap) ->
    Term.

%% Replaces a bare {var, Anno, VName} occurrence with a full re-boxing
%% record construction built from the scalar variables. Classification
%% already guarantees the only surviving bare occurrence (after
%% subst_field_reads has consumed all field reads) is the intended return.
subst_bare_return(Term, VName, RecName, Fields, ScalarMap) when is_tuple(Term) ->
    case Term of
        {var, VAnno, VName} ->
            {record, VAnno, RecName,
             [{record_field, VAnno, {atom, VAnno, F}, {var, VAnno, maps:get(F, ScalarMap)}}
              || F <- Fields]};
        _ ->
            list_to_tuple([subst_bare_return(E, VName, RecName, Fields, ScalarMap)
                            || E <- tuple_to_list(Term)])
    end;
subst_bare_return(Term, VName, RecName, Fields, ScalarMap) when is_list(Term) ->
    [subst_bare_return(E, VName, RecName, Fields, ScalarMap) || E <- Term];
subst_bare_return(Term, _VName, _RecName, _Fields, _ScalarMap) ->
    Term.

%% ---------------------------------------------------------------------
%% Rewrite (Phase 2)
%% ---------------------------------------------------------------------

apply_plans(Forms, []) -> Forms;
apply_plans(Forms, Plans) ->
    PlanMap = maps:from_list([{{maps:get(name, P), maps:get(arity, P)}, P} || P <- Plans]),
    %% Pass 1: rewrite entry-call sites everywhere EXCEPT inside a
    %% qualifying function's own body (that body is rewritten wholesale in
    %% Pass 2, using the clause plans captured during qualification).
    %% Known v1 limitation: an entry call to a DIFFERENT qualifying
    %% function nested inside a qualifying function's own clause bodies is
    %% not rewritten by this pass; such a shape is rare in practice and
    %% surfaces as a loud compile error (undefined function), never silent
    %% miscompilation, since the old arity no longer exists post-rewrite.
    Forms1 = [rewrite_top_entry_calls(F, PlanMap) || F <- Forms],
    [rewrite_top_function(F, PlanMap) || F <- Forms1].

rewrite_top_entry_calls({function, _Anno, Name, Arity, _Clauses} = Form, PlanMap) ->
    case maps:is_key({Name, Arity}, PlanMap) of
        true -> Form;
        false -> rewrite_entry_calls(Form, PlanMap)
    end;
rewrite_top_entry_calls(Form, PlanMap) ->
    rewrite_entry_calls(Form, PlanMap).

rewrite_top_function({function, Anno, Name, Arity, _Clauses}, PlanMap)
  when is_map_key({Name, Arity}, PlanMap) ->
    Plan = maps:get({Name, Arity}, PlanMap),
    NewClauses = [rewrite_clause(CP, Plan) || CP <- maps:get(clause_plans, Plan)],
    {function, Anno, Name, new_arity(Plan), NewClauses};
rewrite_top_function(Form, _PlanMap) ->
    Form.

new_arity(Plan) ->
    maps:get(arity, Plan) - 1 + length(maps:get(fields, Plan)).

rewrite_entry_calls(Term, PlanMap) when is_tuple(Term) ->
    case Term of
        {call, Anno, {atom, AA, Name}, Args} ->
            NewArgs0 = [rewrite_entry_calls(A, PlanMap) || A <- Args],
            case maps:find({Name, length(Args)}, PlanMap) of
                {ok, Plan} -> {call, Anno, {atom, AA, Name}, splice_entry_args(NewArgs0, Plan)};
                error -> {call, Anno, {atom, AA, Name}, NewArgs0}
            end;
        _ ->
            list_to_tuple([rewrite_entry_calls(E, PlanMap) || E <- tuple_to_list(Term)])
    end;
rewrite_entry_calls(Term, PlanMap) when is_list(Term) ->
    [rewrite_entry_calls(E, PlanMap) || E <- Term];
rewrite_entry_calls(Term, _PlanMap) ->
    Term.

splice_entry_args(Args, Plan) ->
    Pos = maps:get(pos, Plan),
    Fields = maps:get(fields, Plan),
    Before = lists:sublist(Args, 1, Pos - 1),
    ArgP = lists:nth(Pos, Args),
    After = lists:nthtail(Pos, Args),
    {record, _, _RecName, FieldList} = ArgP,
    FieldExprs = [begin {ok, E} = find_field_expr(FieldList, F), E end || F <- Fields],
    Before ++ FieldExprs ++ After.

rewrite_clause(#{kind := unrelated, anno := Anno, patterns := Patterns, guard := Guard,
                  body := Body}, Plan) ->
    Pos = maps:get(pos, Plan),
    N = length(maps:get(fields, Plan)),
    NewPatterns = splice_wildcards(Patterns, Pos, N),
    {clause, Anno, NewPatterns, Guard, Body};
rewrite_clause(#{kind := base, anno := Anno, patterns := Patterns, guard := Guard,
                  body := Body, var := VName}, Plan) ->
    Pos = maps:get(pos, Plan),
    Fields = maps:get(fields, Plan),
    RecName = maps:get(rec, Plan),
    ScalarMap = scalar_map(VName, Fields),
    NewGuard = subst_field_reads(Guard, VName, ScalarMap),
    NewBody0 = subst_field_reads(Body, VName, ScalarMap),
    NewBody = subst_bare_return(NewBody0, VName, RecName, Fields, ScalarMap),
    NewPatterns = splice_scalar_patterns(Patterns, Pos, Fields, ScalarMap),
    {clause, Anno, NewPatterns, NewGuard, NewBody};
rewrite_clause(#{kind := recursive} = CP, Plan) ->
    #{anno := Anno, patterns := Patterns, guard := Guard, body := Body,
      var := VName, tail_call := TailCall} = CP,
    Pos = maps:get(pos, Plan),
    Fields = maps:get(fields, Plan),
    ScalarMap = scalar_map(VName, Fields),
    {call, CAnno, CF, Args} = TailCall,
    Before = lists:sublist(Args, 1, Pos - 1),
    ArgP = lists:nth(Pos, Args),
    After = lists:nthtail(Pos, Args),
    Before1 = subst_field_reads(Before, VName, ScalarMap),
    After1 = subst_field_reads(After, VName, ScalarMap),
    FieldExprs = expand_field_exprs(ArgP, VName, Fields, ScalarMap),
    NewArgs = Before1 ++ FieldExprs ++ After1,
    NewTailCall = {call, CAnno, CF, NewArgs},
    NonLast = lists:sublist(Body, 1, length(Body) - 1),
    NonLast1 = subst_field_reads(NonLast, VName, ScalarMap),
    NewBody = NonLast1 ++ [NewTailCall],
    NewGuard = subst_field_reads(Guard, VName, ScalarMap),
    NewPatterns = splice_scalar_patterns(Patterns, Pos, Fields, ScalarMap),
    {clause, Anno, NewPatterns, NewGuard, NewBody}.

splice_wildcards(Patterns, Pos, N) ->
    Before = lists:sublist(Patterns, 1, Pos - 1),
    After = lists:nthtail(Pos, Patterns),
    PAnno = element(2, lists:nth(Pos, Patterns)),
    Before ++ [{var, PAnno, '_'} || _ <- lists:seq(1, N)] ++ After.

splice_scalar_patterns(Patterns, Pos, Fields, ScalarMap) ->
    Before = lists:sublist(Patterns, 1, Pos - 1),
    After = lists:nthtail(Pos, Patterns),
    PAnno = element(2, lists:nth(Pos, Patterns)),
    NewPats = [{var, PAnno, maps:get(F, ScalarMap)} || F <- Fields],
    Before ++ NewPats ++ After.

scalar_map(VName, Fields) ->
    maps:from_list([{F, scalar_name(VName, F)} || F <- Fields]).

expand_field_exprs({record, _, _RecName2, FieldList}, VName, Fields, ScalarMap) ->
    [begin
         {ok, Expr} = find_field_expr(FieldList, F),
         subst_field_reads(Expr, VName, ScalarMap)
     end || F <- Fields];
expand_field_exprs({record, Anno, {var, _, _}, _RecName2, FieldList}, VName, Fields, ScalarMap) ->
    [case find_field_expr(FieldList, F) of
         {ok, Expr} -> subst_field_reads(Expr, VName, ScalarMap);
         error -> {var, Anno, maps:get(F, ScalarMap)}
     end || F <- Fields];
expand_field_exprs({var, Anno, _}, _VName, Fields, ScalarMap) ->
    [{var, Anno, maps:get(F, ScalarMap)} || F <- Fields].
