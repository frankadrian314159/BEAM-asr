-module(fixture_inline_temp_collision).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {a, b}).

%% Helper's intermediate binding X1 would gensym to P_inl_X1 at the call
%% site - which the caller clause already binds itself. Must decline
%% rather than let the gensym'd name silently shadow/collide.
step(P) ->
    X1 = P#pt.a + 1,
    #pt{a = X1, b = P#pt.b}.

run(N) -> loop(#pt{a = 0, b = 0}, 0, N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    P_inl_X1 = 0,
    loop(step(P), I + 1 + P_inl_X1, N).
