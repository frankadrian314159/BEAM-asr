%% Both accumulators share the vec2 record type, so this counter tallies
%% BOTH constructions together (2 per iteration, not 1).
-module(bench_twobody_counted).
-export([run/1]).
-record(vec2, {x, y}).

run(N) ->
    bench_util:reset_counter(vec2),
    bench_util:bump(vec2),
    bench_util:bump(vec2),
    loop(#vec2{x = 0.0, y = 0.0}, #vec2{x = 1.0, y = 1.0}, 0, N).

loop(A, B, I, N) when I >= N -> A#vec2.x + A#vec2.y;
loop(A, B, I, N) ->
    bench_util:bump(vec2),
    bench_util:bump(vec2),
    loop(#vec2{x = A#vec2.x + 0.01 * (B#vec2.x - A#vec2.x),
               y = A#vec2.y + 0.01 * (B#vec2.y - A#vec2.y)},
         #vec2{x = B#vec2.x + 0.01 * (A#vec2.x - B#vec2.x),
               y = B#vec2.y + 0.01 * (A#vec2.y - B#vec2.y)},
         I + 1, N).
