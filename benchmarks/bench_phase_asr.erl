-module(bench_phase_asr).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(phase, {x, y}).

run(N) -> loop(#phase{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> P#phase.x + P#phase.y;
loop(P, I, N) when I rem 3 =:= 0 ->
    loop(#phase{x = P#phase.x + 1.0, y = P#phase.y}, I + 1, N);
loop(P, I, N) when I rem 3 =:= 1 ->
    loop(#phase{x = P#phase.x, y = P#phase.y + 2.0}, I + 1, N);
loop(P, I, N) ->
    loop(#phase{x = P#phase.x + 0.5, y = P#phase.y + 0.5}, I + 1, N).
