-module(fixture_indirect_entry_asr).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {x, y}).

wrapper(P, N) -> loop(P, 0, N).

run(N) -> wrapper(#pt{x = 0.0, y = 0.0}, N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    loop(P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0}, I + 1, N).
