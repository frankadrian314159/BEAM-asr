%% ASR Benchmark B: three-field ballistic integrator. Ported from
%% benchmarks/fol-code/asr-projectile.fol. `nvy` is bound once and reused
%% in two field expressions, exercising ASR's peeling of a single-form
%% intermediate-binding layer around the reconstruction.
-module(bench_projectile_plain).
-export([run/1]).
-record(state3, {x, y, vy}).

advance(S) ->
    Nvy = S#state3.vy - 0.098,
    #state3{x = S#state3.x + 1.0, y = S#state3.y + Nvy, vy = Nvy}.

run(N) -> loop(#state3{x = 0.0, y = 0.0, vy = 20.0}, 0, N).

loop(S, I, N) when I >= N -> S#state3.x + S#state3.y + S#state3.vy;
loop(S, I, N) ->
    loop(advance(S), I + 1, N).
