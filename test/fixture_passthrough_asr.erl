-module(fixture_passthrough_asr).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {a, b}).

run(N) -> loop(#pt{a = 0, b = 42}, 0, N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    loop(P#pt{a = P#pt.a + 1}, I + 1, N).
