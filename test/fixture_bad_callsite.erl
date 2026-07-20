-module(fixture_bad_callsite).
-compile({parse_transform, asr_transform}).
-export([run/1, weird/0]).
-record(pt, {a, b}).

run(N) -> loop(#pt{a = 0, b = 0}, 0, N).

%% Call site passing a non-record argument at the accumulator position -
%% this alone must make the whole function decline.
weird() -> loop(undefined, 0, 0).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    loop(P#pt{a = P#pt.a + 1, b = P#pt.b + 2}, I + 1, N).
