-module(bench_counter_asr).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(ctr, {n}).

run(N) -> loop(#ctr{n = 0.0}, 0, N).

loop(C, I, N) when I >= N -> C#ctr.n;
loop(C, I, N) ->
    loop(#ctr{n = C#ctr.n + 1.0}, I + 1, N).
