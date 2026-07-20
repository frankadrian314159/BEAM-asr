-module(fixture_alias_pattern_literal_declines).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {x, y, tag}).

%% A literal sub-pattern in the alias (not a wildcard or a fresh plain
%% variable binding) acts as an implicit guard - mirrors httpc.erl's
%% `RequestHeaders = #http_request_h{host = undefined}`. Out of scope
%% for the narrow Category D slice, which only handles wildcard/plain-var
%% field sub-patterns; must still decline.
loop(P, I, N) when I >= N -> P;
loop(P = #pt{tag = fixed}, I, N) ->
    loop(P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0}, I + 1, N).

run(N) -> loop(#pt{x = 0.0, y = 0.0, tag = fixed}, 0, N).
