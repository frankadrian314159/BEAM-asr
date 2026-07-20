-module(bench_counter_counted).
-export([run/1]).
-record(ctr, {n}).

run(N) ->
    bench_util:reset_counter(ctr),
    bench_util:bump(ctr),
    loop(#ctr{n = 0.0}, 0, N).

loop(C, I, N) when I >= N -> C#ctr.n;
loop(C, I, N) ->
    bench_util:bump(ctr),
    loop(#ctr{n = C#ctr.n + 1.0}, I + 1, N).
