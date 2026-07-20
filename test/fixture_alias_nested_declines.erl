-module(fixture_alias_nested_declines).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {x, y, env}).

%% A nested sub-pattern containing a wildcard (not a ground pattern -
%% `=:=` can't express "any value in this position") - mirrors
%% xmerl_scan.erl's `environment={external,{entity,_}}}`. Out of scope
%% for the v1.6 guard-conversion slice, which only handles sub-patterns
%% with no wildcards or variable bindings anywhere inside them; must
%% still decline.
loop(P, I, N) when I >= N -> P;
loop(P = #pt{env = {external, {entity, _}}}, I, N) ->
    loop(P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0}, I + 1, N).

run(N) -> loop(#pt{x = 0.0, y = 0.0, env = {external, {entity, foo}}}, 0, N).
