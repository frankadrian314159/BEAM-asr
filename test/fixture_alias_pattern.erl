-module(fixture_alias_pattern).
-export([run/1]).
-record(pt, {x, y, tag}).

finish(P, Tag) -> {P, Tag}.

run(N) -> loop(#pt{x = 0.0, y = 0.0, tag = final}, 0, N).

%% Category D: head-alias pattern `P=#pt{tag=T}` binds the whole
%% accumulator AND destructures a field, right in the clause head -
%% mirrors xmerl_scan.erl's own `S=#xmerl_scanner{col=C}` idiom, and
%% httpc.erl's `RequestHeaders=#http_request_h{te=TE,connection=Conn}`.
loop(P = #pt{tag = T}, I, N) when I >= N -> finish(P, T);
loop(P = #pt{x = X}, I, N) ->
    loop(P#pt{x = X + 1.0, y = P#pt.y + 2.0}, I + 1, N).
