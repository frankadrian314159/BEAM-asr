%% ASR Benchmark: particle simulation (the motivating example).
%% Full reconstruction every iteration - #particle{x,y}, both fields
%% advanced independently. Ported from FOL's benchmarks/fol-code/asr-particle.fol.
-module(bench_particle_plain).
-export([run/1]).
-record(particle, {x, y}).

run(N) -> loop(#particle{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> P#particle.x + P#particle.y;
loop(P, I, N) ->
    loop(#particle{x = P#particle.x + 0.1, y = P#particle.y + 0.2}, I + 1, N).
