-module(fixture_hoisted_binding_escapes_declines).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {x, y}).

log(P) -> P.

%% The intermediate binding is used a second time (passed to log/1)
%% before reaching the tail call, not just at the tail call's own
%% accumulator position - the narrow Category F slice only hoists a
%% single-use rename; a second use means hoisting could silently drop
%% or duplicate a real use, so this must still decline.
run(N) -> loop(#pt{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    P1 = P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0},
    _ = log(P1),
    loop(P1, I + 1, N).
