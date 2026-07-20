-module(bench_assoc_asr).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(particle, {x, y, vx, vy}).

run(N) -> loop(#particle{x = 0.0, y = 0.0, vx = 0.0, vy = 0.0}, 0, N).

loop(P, I, N) when I >= N ->
    P#particle.x + P#particle.y + P#particle.vx + P#particle.vy;
loop(P, I, N) ->
    loop(P#particle{vx = P#particle.vx + 0.1}, I + 1, N).
