-module(fixture_default_field).
-export([run/1]).
%% cyclic has a declared default; vy has none (Erlang implicitly
%% defaults it to `undefined`). Both kinds of omission are exercised.
-record(pt, {x, y, cyclic = true, vy}).

run(N) -> loop(#pt{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    loop(P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0}, I + 1, N).
