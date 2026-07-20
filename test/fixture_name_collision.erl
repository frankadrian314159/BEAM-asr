-module(fixture_name_collision).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {a, b}).

run(N) -> loop(#pt{a = 0, b = 0}, 0, N).

%% The loop counter is already named P_a, which is exactly the scalar name
%% the transform would synthesize for accumulator P's field `a` - must
%% decline on the collision rather than shadow/misbind it.
loop(P, P_a, N) when P_a >= N -> P;
loop(P, P_a, N) ->
    loop(P#pt{a = P#pt.a + 1, b = P#pt.b + 2}, P_a + 1, N).
