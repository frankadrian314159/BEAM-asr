-module(fixture_inline_nested).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {a, b}).

%% Helper's body ends in another call, not a direct reconstruction - v1.1
%% inlines one level only; must decline rather than attempt to chase it.
further(A, B) -> #pt{a = A, b = B}.
step(P) -> further(P#pt.a + 1, P#pt.b + 2).

run(N) -> loop(#pt{a = 0, b = 0}, 0, N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    loop(step(P), I + 1, N).
