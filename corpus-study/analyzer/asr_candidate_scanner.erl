%% Corpus-study candidate-loop scanner for BEAM-asr.
%%
%% Two-pass methodology mirroring FOL's own corpus study
%% (docs/cgo2027/corpus-study) and cpython-asr's (corpus-study/):
%%
%% Pass 1 (this module, syntactic-shape proxy, upper bound): finds every
%% tail-self-recursive function ("loop site" - Erlang's analog of a
%% loop/recur or while-loop site) and classifies each parameter position
%% threaded through the recursive call by accumulator KIND:
%%   - record_strong : rebuilt via a literal #rec{...} construction or
%%     update at the tail call itself (ASR's own target shape, v1)
%%   - record_weak    : threaded through a helper function call instead
%%     (POSSIBLE ASR target via v1.1 inlining - not verified here,
%%     mirrors FOL/cpython-asr's own "weak/possible" hits, which are
%%     flagged, not confirmed, by the syntactic pass)
%%   - map            : rebuilt via a #{...} map construction/update
%%     (map accumulator - not ASR-addressable, the closest analogue to
%%     FOL's "transient territory" (b) category)
%%   - collection     : grown via cons/list-building ((c) category)
%%   - scalar         : a bare variable or simple arithmetic expression
%%     (the already-hand-optimized (d) form - a suppression signal)
%%   - other          : none of the above cleanly
%%
%% Pass 2 (see asr_gate_check.erl) runs the REAL asr_transform.erl
%% qualification on every record_strong/record_weak candidate as a
%% black-box oracle (never re-implemented, so it can't drift from the
%% actual transform) to separate true positives from false positives.
-module(asr_candidate_scanner).
-export([scan_file/1, scan_file/2]).

scan_file(Path) -> scan_file(Path, [filename:dirname(Path)]).

scan_file(Path, IncludeDirs) ->
    case epp:parse_file(Path, [{includes, IncludeDirs}]) of
        {ok, Forms} ->
            Functions = [F || F = {function, _, _, _, _} <- Forms],
            Candidates = lists:flatmap(fun(F) -> analyze_function(F) end, Functions),
            {ok, Forms, Candidates};
        {error, Reason} ->
            {error, Reason}
    end.

analyze_function({function, _Anno, Name, Arity, Clauses}) ->
    RecClauses = [C || C <- Clauses, is_tail_self_recursive(C, Name, Arity)],
    case RecClauses of
        [] ->
            [];
        _ ->
            Positions = lists:seq(1, Arity),
            lists:filtermap(
              fun(Pos) -> classify_position(Name, Arity, Pos, RecClauses, length(Clauses)) end,
              Positions)
    end.

is_tail_self_recursive({clause, _, Patterns, _, Body}, Name, Arity) ->
    length(Patterns) =:= Arity andalso Body =/= [] andalso
        case lists:last(Body) of
            {call, _, {atom, _, Name}, Args} -> length(Args) =:= Arity;
            _ -> false
        end.

classify_position(Name, Arity, Pos, RecClauses, TotalClauseCount) ->
    ArgKinds = [classify_arg(tail_call_arg(C, Name, Arity, Pos)) || C <- RecClauses],
    case aggregate_kind(ArgKinds) of
        unrelated ->
            false;
        Kind ->
            {true, #{name => Name, arity => Arity, pos => Pos, kind => Kind,
                     recursive_clauses => length(RecClauses), total_clauses => TotalClauseCount}}
    end.

tail_call_arg({clause, _, _, _, Body}, Name, Arity, Pos) ->
    {call, _, {atom, _, Name}, Args} = lists:last(Body),
    Arity = length(Args),
    lists:nth(Pos, Args).

classify_arg({record, _, _RecName, _FieldList}) -> record_strong;
classify_arg({record, _, _Base, _RecName, _FieldList}) -> record_strong;
classify_arg({map, _, _FieldList}) -> map_kind;
classify_arg({map, _, _Base, _FieldList}) -> map_kind;
classify_arg({cons, _, _, _}) -> collection_kind;
classify_arg({nil, _}) -> collection_kind;
classify_arg({call, _, {atom, _, _HelperName}, _CallArgs}) -> helper_call;
classify_arg({var, _, _}) -> scalar_kind;
classify_arg({integer, _, _}) -> scalar_kind;
classify_arg({float, _, _}) -> scalar_kind;
classify_arg({atom, _, _}) -> scalar_kind;
classify_arg({op, _, _, _, _}) -> scalar_kind;
classify_arg({op, _, _, _}) -> scalar_kind;
classify_arg(_) -> other_kind.

%% "unrelated" is not currently produced (every clause's tail-call
%% argument always classifies as something), reserved for a future
%% refinement that excludes positions never touched by ANY clause.
aggregate_kind(Kinds) ->
    HasRecordStrong = lists:member(record_strong, Kinds),
    HasHelper = lists:member(helper_call, Kinds),
    HasMap = lists:member(map_kind, Kinds),
    HasCollection = lists:member(collection_kind, Kinds),
    AllScalarish = lists:all(fun(K) -> K =:= scalar_kind end, Kinds),
    if
        HasRecordStrong -> record_strong;
        HasHelper -> record_weak;
        HasMap -> map;
        HasCollection -> collection;
        AllScalarish -> scalar;
        true -> other
    end.
