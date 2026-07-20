-module(fixture_indirect_entry_update).
-export([run/1]).
-record(pt, {x, y}).

%% v1.6, Category E: the entry call's accumulator argument is an update
%% expression (`P#pt{x=...}`), not a bare variable or a literal full
%% construction - the overridden field (x) is known statically, and the
%% other field (y) is read directly off the base variable, since update
%% syntax leaves it unchanged. Mirrors xmerl_scan.erl's
%% `scan_xml_vsn/2 -> xml_vsn(T, S#xmerl_scanner{col=S#xmerl_scanner.col+1}, H, [])`.
wrapper(P, N) -> loop(P#pt{x = P#pt.x + 10.0}, 0, N).

run(N) -> wrapper(#pt{x = 0.0, y = 0.0}, N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    loop(P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0}, I + 1, N).
