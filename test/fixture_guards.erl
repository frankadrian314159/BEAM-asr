-module(fixture_guards).
-export([run/1]).
-record(pt, {a, b}).

run(N) -> loop(#pt{a = 0, b = 0}, 0, N).

loop(P, I, N) when I >= N, P#pt.a >= 0 -> P;
loop(P, I, N) when P#pt.a < 1000000 ->
    loop(P#pt{a = P#pt.a + 1, b = P#pt.b + I}, I + 1, N).
