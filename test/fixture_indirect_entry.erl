-module(fixture_indirect_entry).
-export([run/1]).
-record(pt, {x, y}).

%% v1.6, Category E: the entry call's accumulator argument is a bare
%% variable - here wrapper/2's own parameter, forwarded straight
%% through - rather than a literal construction at the call site.
%% Mirrors xmerl_scan.erl's `strip(Str,S) -> strip(Str,S,all)` and
%% `scan_system_literal("\""++T,S) -> scan_system_literal(T,S,$",[])`.
wrapper(P, N) -> loop(P, 0, N).

run(N) -> wrapper(#pt{x = 0.0, y = 0.0}, N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    loop(P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0}, I + 1, N).
