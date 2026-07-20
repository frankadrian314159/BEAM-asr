-module(bench_clamp_asr).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(point, {x, y}).

run(N) -> loop(#point{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> P#point.x + P#point.y;
loop(P, I, N) when P#point.x > 100.0 ->
    loop(#point{x = 0.0, y = P#point.y}, I + 1, N);
loop(P, I, N) ->
    loop(#point{x = P#point.x + 1.0, y = P#point.y + 0.5}, I + 1, N).
