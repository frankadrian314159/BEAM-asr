-module(fixture_intra_clause_case).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {a, b}).

run(N) -> loop(#pt{a = 0, b = 0}, 0, N).

%% Intra-clause case/if guarding a reconstruction: not "free" the way
%% clause-head dispatch is (v1.1 scope) - must decline cleanly.
loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    case I rem 2 of
        0 -> loop(P#pt{a = P#pt.a + 1, b = P#pt.b + 2}, I + 1, N);
        1 -> loop(P#pt{a = P#pt.a + 3, b = P#pt.b + 4}, I + 1, N)
    end.
