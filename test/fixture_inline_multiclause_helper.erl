-module(fixture_inline_multiclause_helper).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {a, b}).

%% Two-clause helper - v1.1 only inlines a single-clause helper; multiple
%% clauses (even with disjoint guards) must decline, not pick one.
step(P) when P#pt.a > 1000 -> #pt{a = 0, b = P#pt.b};
step(P) -> #pt{a = P#pt.a + 1, b = P#pt.b + 2}.

run(N) -> loop(#pt{a = 0, b = 0}, 0, N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    loop(step(P), I + 1, N).
