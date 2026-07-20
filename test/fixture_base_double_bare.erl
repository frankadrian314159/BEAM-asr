-module(fixture_base_double_bare).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {x, y}).

%% Two bare occurrences of the accumulator in the base case - the
%% Category B relaxation only ever allows exactly one bare occurrence
%% anywhere in the clause, same as before; this must still decline.
pair(A, B) -> {A, B}.

run(N) -> loop(#pt{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> pair(P, P);
loop(P, I, N) ->
    loop(P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0}, I + 1, N).
