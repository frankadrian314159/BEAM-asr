%% Aggregate Scalar Replacement for Erlang.
%%
%% Whole-module opt-in: -compile({parse_transform, asr_transform}).
%%
%% Unboxes a tail-recursive record accumulator into scalar arguments,
%% re-boxing only at the base case. v1.1 adds one-level interprocedural
%% inlining of a helper function (try_inline/3); v1.2 adds multi-accumulator
%% support (combine_accum_plans/3) - more than one record threaded through
%% the same recursion simultaneously; branch-shaped reconstruction
%% (cond/if/case in the source language) needs no extra support at all,
%% since it maps onto Erlang's own idiomatic guarded multi-clause dispatch,
%% which per-clause classification already handles. See BEAM-asr design
%% notes and README.md for the full qualification/rewrite spec.
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

%% Every candidate position is qualified independently (each position's
%% own field-read/collision checks are already position-scoped, so a
%% cross-accumulator field read - e.g. accumulator A's reconstruction
%% reading accumulator B's field - is already tolerated for free: it's
%% just a {field_read,...} entry in B's own collect_var_uses scan, not a
%% bare reference). Multiple surviving positions become a multi-accumulator
%% plan (v1.2); exactly one is the ordinary single-accumulator case.
try_qualify(Name, Arity, Clauses, Forms, Records) ->
    Candidates = lists:filtermap(
                   fun(Pos) ->
                           case try_qualify_at(Name, Arity, Pos, Clauses, Forms, Records) of
                               {ok, AccumPlan} -> {true, AccumPlan};
                               decline -> false
                           end
                   end, lists:seq(1, Arity)),
    case Candidates of
        [] -> decline;
        _ -> combine_accum_plans(Name, Arity, Candidates)
    end.

combine_accum_plans(Name, Arity, Candidates) ->
    try
        check_cross_scalar_collision(Candidates),
        {ok, #{name => Name, arity => Arity, accums => Candidates}}
    catch
        throw:decline -> decline
    end.

%% A scalar name is only a real collision if two DIFFERENT accumulators
%% would ever synthesize it; the same accumulator reusing its own name
%% across its own clauses is expected and fine.
check_cross_scalar_collision(Candidates) ->
    Indexed = lists:zip(lists:seq(1, length(Candidates)), Candidates),
    IndexedNames = lists:append(
                     [[{scalar_name(maps:get(var, CP), F), AccumIdx}
                       || CP <- maps:get(clause_plans, AP), maps:get(kind, CP) =/= unrelated,
                          F <- maps:get(fields, AP)]
                      || {AccumIdx, AP} <- Indexed]),
    ByName = lists:foldl(
               fun({SN, Idx}, Acc) ->
                       maps:update_with(SN, fun(Idxs) -> lists:usort([Idx | Idxs]) end, [Idx], Acc)
               end, #{}, IndexedNames),
    lists:foreach(fun(Idxs) -> (length(Idxs) =:= 1) orelse throw(decline) end,
                  maps:values(ByName)).

try_qualify_at(Name, Arity, Pos, Clauses, Forms, Records) ->
    try
        {PlansRev, RecNameAcc} = classify_clauses(Name, Arity, Pos, Clauses, Forms),
        ClausePlans = lists:reverse(PlansRev),
        RecName = case RecNameAcc of
                      undefined -> throw(decline);
                      R -> R
                  end,
        Fields = case maps:find(RecName, Records) of
                     {ok, Fs} -> Fs;
                     error -> throw(decline)
                 end,
        %% A genuine terminal clause must exist somewhere in the function
        %% (else it's not really a loop), but it need not be one where
        %% THIS accumulator is read - a secondary accumulator can be
        %% legitimately "unrelated" at the clause that terminates a
        %% different, primary accumulator (e.g. kalman's covariance
        %% matrix is discarded, not returned, once the loop ends).
        HasNonRecursive = lists:any(fun(CP) -> maps:get(kind, CP) =/= recursive end, ClausePlans),
        HasRec = lists:any(fun(CP) -> maps:get(kind, CP) =:= recursive end, ClausePlans),
        (HasNonRecursive andalso HasRec) orelse throw(decline),
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

classify_clauses(Name, Arity, Pos, Clauses, Forms) ->
    lists:foldl(
      fun(Clause, {PlansAcc, RecAcc}) ->
              {CP, RecAcc2} = classify_clause(Name, Arity, Pos, Clause, RecAcc, Forms),
              {[CP | PlansAcc], RecAcc2}
      end, {[], undefined}, Clauses).

classify_clause(Name, Arity, Pos, {clause, Anno, Patterns, Guard, Body}, RecAcc, Forms) ->
    PatP = lists:nth(Pos, Patterns),
    LastExpr = lists:last(Body),
    IsTailSelfCall = case LastExpr of
                         {call, _, {atom, _, Name}, Args} when length(Args) =:= Arity -> true;
                         _ -> false
                     end,
    case IsTailSelfCall of
        true ->
            classify_recursive(Pos, Anno, Patterns, Guard, Body, PatP, LastExpr, RecAcc, Name, Forms);
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

classify_recursive(Pos, Anno, Patterns, Guard, Body, PatP, TailCall, RecAcc, Name, Forms) ->
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
            {call, _, {atom, _, HelperName}, [{var, _, VName}]} when HelperName =/= Name ->
                {InlinePlan, RA1} = try_inline(HelperName, Forms, RecAcc1),
                IntNames = maps:get(int_names, InlinePlan),
                GensymNames = [gensym_name(VName, IN) || IN <- IntNames],
                ClauseNames = sets:to_list(collect_var_names({Patterns, Guard, Body})),
                lists:foreach(fun(GN) -> (not lists:member(GN, ClauseNames)) orelse throw(decline) end,
                              GensymNames),
                {{inline, InlinePlan}, RA1};
            _ ->
                throw(decline)
        end,
    CP = #{kind => recursive, anno => Anno, patterns => Patterns, guard => Guard,
           body => Body, var => VName, tail_call => TailCall, tail_anno => CAnno,
           tail_f => CF, arg_kind => ArgKind},
    {CP, RecAcc2}.

%% -- interprocedural inlining (one level) --------------------------------

%% Validates that HelperName/1 is a single-clause, unguarded, non-recursive
%% function in the same module whose body is a straight-line sequence of
%% intermediate bindings (each `Var = Expr`, Expr's uses of the helper's
%% own parameter restricted to field reads) terminating in a full record
%% reconstruction - the Erlang analog of "a helper whose body reduces to a
%% single reconstruction," one level deep only (the final expression must
%% be a literal {record,...}, never another inlinable call).
try_inline(HelperName, Forms, RecAcc) ->
    HClause = case [C || {function, _, HN, 1, [C]} <- Forms, HN =:= HelperName] of
                  [C] -> C;
                  _ -> throw(decline)
              end,
    {clause, _HAnno, [QPat], HGuard, HBody} = HClause,
    QName = case QPat of
                {var, _, Q} when Q =/= '_' -> Q;
                _ -> throw(decline)
            end,
    (HGuard =:= []) orelse throw(decline),
    {IntermediateStmts, FinalExpr} =
        case lists:reverse(HBody) of
            [Last | RevRest] -> {lists:reverse(RevRest), Last};
            [] -> throw(decline)
        end,
    {RecName2, FieldList} = case FinalExpr of
                                 {record, _, RN, FL} -> {RN, FL};
                                 _ -> throw(decline)
                             end,
    {IntNamesRev, RecAcc1} =
        lists:foldl(
          fun(Stmt, {NamesAcc, RA}) ->
                  case Stmt of
                      {match, _, {var, _, NewVar}, ValExpr} when NewVar =/= '_' ->
                          Uses = collect_var_uses(QName, ValExpr),
                          (lists:all(fun(U) -> U =/= bare end, Uses)) orelse throw(decline),
                          RA1 = unify_recname(RA, [R || {field_read, R, _F} <- Uses]),
                          {[NewVar | NamesAcc], RA1};
                      _ ->
                          throw(decline)
                  end
          end, {[], RecAcc}, IntermediateStmts),
    FinalUses = collect_var_uses(QName, FieldList),
    (lists:all(fun(U) -> U =/= bare end, FinalUses)) orelse throw(decline),
    RA2 = unify_recname(RecAcc1, [RecName2]),
    RA3 = unify_recname(RA2, [R || {field_read, R, _F} <- FinalUses]),
    {#{q => QName, intermediate => IntermediateStmts, int_names => lists:reverse(IntNamesRev),
       rec => RecName2, field_list => FieldList},
     RA3}.

gensym_name(VName, IN) ->
    list_to_atom(atom_to_list(VName) ++ "_inl_" ++ atom_to_list(IN)).

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

%% Renames every {var, Anno, OldName} occurrence where OldName is a key in
%% RenameMap to {var, Anno, NewName}. Generic otherwise - used to splice an
%% inlined helper's body into a caller clause under a fresh name mapping.
rename_vars({var, Anno, VName}, RenameMap) ->
    case maps:find(VName, RenameMap) of
        {ok, NewName} -> {var, Anno, NewName};
        error -> {var, Anno, VName}
    end;
rename_vars(Term, RenameMap) when is_tuple(Term) ->
    list_to_tuple([rename_vars(E, RenameMap) || E <- tuple_to_list(Term)]);
rename_vars(Term, RenameMap) when is_list(Term) ->
    [rename_vars(E, RenameMap) || E <- Term];
rename_vars(Term, _RenameMap) ->
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
    Accums = maps:get(accums, Plan),
    ZippedClausePlans = transpose([maps:get(clause_plans, AP) || AP <- Accums]),
    NewClauses = [rewrite_clause_multi(CPGroup, Accums) || CPGroup <- ZippedClausePlans],
    {function, Anno, Name, new_arity(Plan), NewClauses};
rewrite_top_function(Form, _PlanMap) ->
    Form.

new_arity(Plan) ->
    Accums = maps:get(accums, Plan),
    FieldsTotal = lists:sum([length(maps:get(fields, AP)) || AP <- Accums]),
    maps:get(arity, Plan) - length(Accums) + FieldsTotal.

%% Transposes a list of N equal-length lists (one per accumulator, each
%% holding one clause-plan per original clause) into a list of N-tuples
%% grouped by original clause index instead - i.e. for clause K, one
%% clause-plan per accumulator, so a single clause's rewrite can consider
%% every accumulator touching it at once.
transpose(ListOfLists) -> transpose(ListOfLists, []).

transpose(ListOfLists, Acc) ->
    case lists:any(fun(L) -> L =:= [] end, ListOfLists) of
        true -> lists:reverse(Acc);
        false ->
            Heads = [hd(L) || L <- ListOfLists],
            Tails = [tl(L) || L <- ListOfLists],
            transpose(Tails, [Heads | Acc])
    end.

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

%% Splices every accumulator's field values in at its own original
%% position, in one pass over Args, so unrelated positions and multiple
%% accumulator positions in the same call are all handled uniformly.
splice_entry_args(Args, Plan) ->
    PosMap = maps:from_list([{maps:get(pos, AP), AP} || AP <- maps:get(accums, Plan)]),
    splice_entry_args(Args, 1, PosMap).

splice_entry_args([], _Idx, _PosMap) -> [];
splice_entry_args([Arg | Rest], Idx, PosMap) ->
    Tail = splice_entry_args(Rest, Idx + 1, PosMap),
    case maps:find(Idx, PosMap) of
        {ok, AP} ->
            Fields = maps:get(fields, AP),
            {record, _, _RecName, FieldList} = Arg,
            FieldExprs = [begin {ok, E} = find_field_expr(FieldList, F), E end || F <- Fields],
            FieldExprs ++ Tail;
        error ->
            [Arg | Tail]
    end.

%% Groups one clause-plan per accumulator (same original clause, per
%% `transpose/1`) into a single combined rewrite. A clause is "recursive"
%% overall iff any accumulator sees it that way - which every accumulator
%% touching a genuinely recursive clause always does (classify_recursive
%% either succeeds for that clause or that accumulator's own candidacy is
%% declined entirely), so kind never actually conflicts across
%% accumulators for a recursive clause; only base/unrelated can differ
%% per accumulator within one non-recursive clause (e.g. one accumulator
%% is read in the base case, a second is untouched there).
rewrite_clause_multi(CPGroup, Accums) ->
    CP1 = hd(CPGroup),
    Anno = maps:get(anno, CP1),
    Patterns = maps:get(patterns, CP1),
    Guard0 = maps:get(guard, CP1),
    Body0 = maps:get(body, CP1),
    Pairs = lists:zip(CPGroup, Accums),
    case lists:any(fun(CP) -> maps:get(kind, CP) =:= recursive end, CPGroup) of
        true -> rewrite_recursive_multi(Pairs, Anno, Patterns, Guard0, Body0);
        false -> rewrite_nonrecursive_multi(Pairs, Anno, Patterns, Guard0, Body0)
    end.

rewrite_nonrecursive_multi(Pairs, Anno, Patterns, Guard0, Body0) ->
    {NewGuard, NewBody} =
        lists:foldl(
          fun({CP, AP}, {G, B}) ->
                  case maps:get(kind, CP) of
                      unrelated -> {G, B};
                      base ->
                          VName = maps:get(var, CP),
                          Fields = maps:get(fields, AP),
                          RecName = maps:get(rec, AP),
                          ScalarMap = scalar_map(VName, Fields),
                          G1 = subst_field_reads(G, VName, ScalarMap),
                          B1 = subst_field_reads(B, VName, ScalarMap),
                          B2 = subst_bare_return(B1, VName, RecName, Fields, ScalarMap),
                          {G1, B2}
                  end
          end, {Guard0, Body0}, Pairs),
    NewPatterns = splice_patterns_multi(Patterns, Pairs),
    {clause, Anno, NewPatterns, NewGuard, NewBody}.

rewrite_recursive_multi(Pairs, Anno, Patterns, Guard0, Body0) ->
    AllSubs = [{maps:get(var, CP), scalar_map(maps:get(var, CP), maps:get(fields, AP))}
               || {CP, AP} <- Pairs],
    {CP1, _} = hd(Pairs),
    TailCall = maps:get(tail_call, CP1),
    {call, CAnno, CF, Args} = TailCall,
    {AllPrelude, NewArgs} = build_args_multi(Args, Pairs, AllSubs, CAnno),
    NewTailCall = {call, CAnno, CF, NewArgs},
    NonLast = lists:sublist(Body0, 1, length(Body0) - 1),
    NonLast1 = subst_all(NonLast, AllSubs),
    NewBody = NonLast1 ++ AllPrelude ++ [NewTailCall],
    NewGuard = subst_all(Guard0, AllSubs),
    NewPatterns = splice_patterns_multi(Patterns, Pairs),
    {clause, Anno, NewPatterns, NewGuard, NewBody}.

subst_all(Term, AllSubs) ->
    lists:foldl(fun({VName, ScalarMap}, T) -> subst_field_reads(T, VName, ScalarMap) end,
                Term, AllSubs).

%% Walks the original Args/Patterns list once (by position), splicing
%% each accumulator's own N-wide expansion in at its own position and
%% leaving every other position untouched but still cross-substituted
%% (e.g. accumulator A's field expression referencing accumulator B's
%% fields, or an unrelated argument that happens to read a field of one).
build_args_multi(Args, Pairs, AllSubs, CAnno) ->
    PosMap = maps:from_list([{maps:get(pos, AP), {CP, AP}} || {CP, AP} <- Pairs]),
    build_args_multi(Args, 1, PosMap, AllSubs, CAnno).

build_args_multi([], _Idx, _PosMap, _AllSubs, _CAnno) ->
    {[], []};
build_args_multi([Arg | Rest], Idx, PosMap, AllSubs, CAnno) ->
    {RestPrelude, RestArgs} = build_args_multi(Rest, Idx + 1, PosMap, AllSubs, CAnno),
    case maps:find(Idx, PosMap) of
        {ok, {CP, AP}} ->
            Fields = maps:get(fields, AP),
            VName = maps:get(var, CP),
            ArgKind = maps:get(arg_kind, CP),
            ScalarMap = scalar_map(VName, Fields),
            {Prelude, FieldExprs} =
                case ArgKind of
                    {inline, InlinePlan} -> expand_inline(InlinePlan, VName, Fields, ScalarMap, CAnno);
                    _ -> {[], expand_field_exprs(Arg, VName, Fields, ScalarMap)}
                end,
            FieldExprs1 = [subst_all(E, AllSubs) || E <- FieldExprs],
            Prelude1 = [subst_all(S, AllSubs) || S <- Prelude],
            {Prelude1 ++ RestPrelude, FieldExprs1 ++ RestArgs};
        error ->
            {RestPrelude, [subst_all(Arg, AllSubs) | RestArgs]}
    end.

splice_patterns_multi(Patterns, Pairs) ->
    PosMap = maps:from_list([{maps:get(pos, AP), {CP, AP}} || {CP, AP} <- Pairs]),
    splice_patterns_multi(Patterns, 1, PosMap).

splice_patterns_multi([], _Idx, _PosMap) -> [];
splice_patterns_multi([Pat | Rest], Idx, PosMap) ->
    Tail = splice_patterns_multi(Rest, Idx + 1, PosMap),
    case maps:find(Idx, PosMap) of
        {ok, {CP, AP}} ->
            Fields = maps:get(fields, AP),
            PAnno = element(2, Pat),
            NewPats = case maps:get(kind, CP) of
                          unrelated -> [{var, PAnno, '_'} || _ <- Fields];
                          _ ->
                              VName = maps:get(var, CP),
                              ScalarMap = scalar_map(VName, Fields),
                              [{var, PAnno, maps:get(F, ScalarMap)} || F <- Fields]
                      end,
            NewPats ++ Tail;
        error ->
            [Pat | Tail]
    end.

%% Splices an inlined helper's body into the caller clause: renames the
%% helper's own parameter to the caller's accumulator variable and every
%% intermediate binding to a gensym'd name (collision-checked already at
%% qualification time), then re-uses the ordinary field-read substitution
%% machinery on the renamed statements exactly as if they'd been written
%% directly in the caller.
expand_inline(#{q := QName, intermediate := IntStmts, int_names := IntNames,
                field_list := FieldList}, VName, Fields, ScalarMap, _CAnno) ->
    GensymMap = maps:from_list([{IN, gensym_name(VName, IN)} || IN <- IntNames]),
    RenameMap = maps:put(QName, VName, GensymMap),
    RenamedIntStmts = rename_vars(IntStmts, RenameMap),
    RenamedFieldList = rename_vars(FieldList, RenameMap),
    Prelude = [subst_field_reads(S, VName, ScalarMap) || S <- RenamedIntStmts],
    FieldExprs = [begin
                      {ok, Expr} = find_field_expr(RenamedFieldList, F),
                      subst_field_reads(Expr, VName, ScalarMap)
                  end || F <- Fields],
    {Prelude, FieldExprs}.

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
