-module(fixture_hoisted_binding).
-export([run/1]).
-record(pt, {x, y}).

%% Category F (narrow slice): the reconstruction happens in an
%% intermediate binding rather than directly at the tail call's own
%% argument position - mirrors xmerl_scan.erl's `?bump_col(N)` macro,
%% which expands to `S = S0#xmerl_scanner{col = S0#xmerl_scanner.col+N}`
%% ahead of the actual tail call.
run(N) -> loop(#pt{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    P1 = P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0},
    loop(P1, I + 1, N).
