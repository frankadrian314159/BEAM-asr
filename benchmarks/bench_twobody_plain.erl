%% ASR Benchmark D: coupled two-accumulator relaxation. Ported from
%% benchmarks/fol-code/asr-twobody.fol. Two <vec2> accumulators of the
%% SAME record type, each reading the other's old value (a reads b, b
%% reads a) - checks parallel-update simultaneity after double unboxing.
-module(bench_twobody_plain).
-export([run/1]).
-record(vec2, {x, y}).

run(N) -> loop(#vec2{x = 0.0, y = 0.0}, #vec2{x = 1.0, y = 1.0}, 0, N).

loop(A, B, I, N) when I >= N -> A#vec2.x + A#vec2.y;
loop(A, B, I, N) ->
    loop(#vec2{x = A#vec2.x + 0.01 * (B#vec2.x - A#vec2.x),
               y = A#vec2.y + 0.01 * (B#vec2.y - A#vec2.y)},
         #vec2{x = B#vec2.x + 0.01 * (A#vec2.x - B#vec2.x),
               y = B#vec2.y + 0.01 * (A#vec2.y - B#vec2.y)},
         I + 1, N).
