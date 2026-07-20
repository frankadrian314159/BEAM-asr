-module(bench_bounce_counted).
-export([run/1]).
-record(bounce, {x, y}).

run(N) ->
    bench_util:reset_counter(bounce),
    bench_util:bump(bounce),
    loop(#bounce{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> P#bounce.x + P#bounce.y;
loop(P, I, N) when P#bounce.x > 100.0 ->
    bench_util:bump(bounce),
    loop(#bounce{x = 0.0, y = P#bounce.y}, I + 1, N);
loop(P, I, N) when P#bounce.x < -100.0 ->
    bench_util:bump(bounce),
    loop(#bounce{x = 0.0, y = P#bounce.y}, I + 1, N);
loop(P, I, N) ->
    bench_util:bump(bounce),
    loop(#bounce{x = P#bounce.x + 1.0, y = P#bounce.y + 0.5}, I + 1, N).
