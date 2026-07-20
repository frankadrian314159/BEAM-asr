%% Same as bench_particle_plain, but bumps an ETS counter immediately
%% before every #particle{} construction, giving an exact per-run
%% construction count (records have no runtime constructor to monkey-patch).
-module(bench_particle_counted).
-export([run/1]).
-record(particle, {x, y}).

run(N) ->
    bench_util:reset_counter(particle),
    bench_util:bump(particle),
    loop(#particle{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> P#particle.x + P#particle.y;
loop(P, I, N) ->
    bench_util:bump(particle),
    loop(#particle{x = P#particle.x + 0.1, y = P#particle.y + 0.2}, I + 1, N).
