-module(fixture_hoisted_binding_asr).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {x, y}).

run(N) -> loop(#pt{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    P1 = P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0},
    loop(P1, I + 1, N).
