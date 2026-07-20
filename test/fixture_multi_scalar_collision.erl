-module(fixture_multi_scalar_collision).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(r1, {y}).
-record(r2, {x_y}).

%% Accumulator A_x's field y synthesizes scalar 'A_x_y'; accumulator A's
%% field x_y synthesizes the SAME atom 'A_x_y' - a genuine cross-accumulator
%% collision (distinct from BEAM-asr's existing per-clause same-accumulator
%% collision check). Must decline the whole function, not just one of them.
run(N) -> loop(#r1{y = 0}, #r2{x_y = 0}, 0, N).

loop(A_x, A, I, N) when I >= N -> A_x#r1.y + A#r2.x_y;
loop(A_x, A, I, N) ->
    loop(#r1{y = A_x#r1.y + 1}, #r2{x_y = A#r2.x_y + 1}, I + 1, N).
