-module(fixture_alias_guard).
-export([run/1]).
-record(pt, {x, y, tag}).

%% v1.6: a ground literal sub-pattern in the alias (no wildcards or
%% variable bindings anywhere inside it) converts to an ordinary scalar
%% pattern var plus an added `=:=` guard - mirrors httpc.erl's
%% `RequestHeaders = #http_request_h{host = undefined}`.
loop(P, I, N) when I >= N -> P;
loop(P = #pt{tag = fixed}, I, N) ->
    loop(P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0}, I + 1, N).

run(N) -> loop(#pt{x = 0.0, y = 0.0, tag = fixed}, 0, N).
