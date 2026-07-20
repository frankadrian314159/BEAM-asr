%% ASR Benchmark: minimal single-field counter. Ported from FOL's
%% benchmarks/fol-code/asr-counter.fol - the pass's fixed per-iteration
%% cost, isolated from field count and domain-specific arithmetic.
-module(bench_counter_plain).
-export([run/1]).
-record(ctr, {n}).

run(N) -> loop(#ctr{n = 0.0}, 0, N).

loop(C, I, N) when I >= N -> C#ctr.n;
loop(C, I, N) ->
    loop(#ctr{n = C#ctr.n + 1.0}, I + 1, N).
