-module(bench_particle_asr).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(particle, {x, y}).

run(N) -> loop(#particle{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> P#particle.x + P#particle.y;
loop(P, I, N) ->
    loop(#particle{x = P#particle.x + 0.1, y = P#particle.y + 0.2}, I + 1, N).
