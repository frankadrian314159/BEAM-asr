-module(bench_assoc_counted).
-export([run/1]).
-record(particle, {x, y, vx, vy}).

run(N) ->
    bench_util:reset_counter(particle),
    bench_util:bump(particle),
    loop(#particle{x = 0.0, y = 0.0, vx = 0.0, vy = 0.0}, 0, N).

loop(P, I, N) when I >= N ->
    P#particle.x + P#particle.y + P#particle.vx + P#particle.vy;
loop(P, I, N) ->
    bench_util:bump(particle),
    loop(P#particle{vx = P#particle.vx + 0.1}, I + 1, N).
