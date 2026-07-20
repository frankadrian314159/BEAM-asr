%% Pass 2 (gate-faithful) of the corpus study: for every record_strong /
%% record_weak candidate asr_candidate_scanner finds, runs the REAL
%% asr_transform:parse_transform/2 directly on the file's own Forms (as
%% a black-box oracle - never re-implemented, so this can't drift from
%% the actual v1-v1.3 qualification rules) and checks whether the
%% candidate function's arity changed, the same signal
%% asr_transform_tests.erl's own assert_qualified/assert_declined
%% helpers use.
-module(asr_gate_check).
-export([qualifies/2]).

qualifies(Forms, #{name := Name, arity := Arity}) ->
    try
        NewForms = asr_transform:parse_transform(Forms, []),
        case has_function(NewForms, Name, Arity) of
            true -> false;   % old arity still present -> declined, unchanged
            false -> true    % old arity gone -> rewritten to a new arity
        end
    catch
        _:_ -> unknown
    end.

has_function(Forms, Name, Arity) ->
    lists:any(fun({function, _, N, A, _}) -> N =:= Name andalso A =:= Arity;
                 (_) -> false
              end, Forms).
