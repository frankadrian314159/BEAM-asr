-module(bench_lorenz_asr).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(lvec3, {x, y, z}).

lorenz_step(P) ->
    X = P#lvec3.x,
    Y = P#lvec3.y,
    Z = P#lvec3.z,
    Dx = 10.0 * (Y - X),
    Dy = (X * (28.0 - Z)) - Y,
    Dz = (X * Y) - (2.6666667 * Z),
    #lvec3{x = X + (Dx * 0.01), y = Y + (Dy * 0.01), z = Z + (Dz * 0.01)}.

run(N) -> loop(#lvec3{x = 1.0, y = 1.0, z = 1.0}, 0, N).

loop(P, I, N) when I >= N -> P#lvec3.x + P#lvec3.y + P#lvec3.z;
loop(P, I, N) ->
    loop(lorenz_step(P), I + 1, N).
