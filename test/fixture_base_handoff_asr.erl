-module(fixture_base_handoff_asr).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {x, y}).

finish(P) -> P.

run(N) -> loop(#pt{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> finish(P);
loop(P, I, N) ->
    loop(P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0}, I + 1, N).
