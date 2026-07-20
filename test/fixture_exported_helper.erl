-module(fixture_exported_helper).
-compile({parse_transform, asr_transform}).
-export([run/1, loop/3]).
-record(pt, {a, b}).

run(N) -> loop(#pt{a = 0, b = 0}, 0, N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    loop(P#pt{a = P#pt.a + 1, b = P#pt.b + 2}, I + 1, N).
