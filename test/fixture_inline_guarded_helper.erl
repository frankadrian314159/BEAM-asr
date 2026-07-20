-module(fixture_inline_guarded_helper).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {a, b}).

%% Guarded helper - v1.1 only inlines a single unguarded clause; a guard
%% here must decline the whole loop function, not silently ignore it.
step(P) when P#pt.a >= 0 -> #pt{a = P#pt.a + 1, b = P#pt.b + 2}.

run(N) -> loop(#pt{a = 0, b = 0}, 0, N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    loop(step(P), I + 1, N).
