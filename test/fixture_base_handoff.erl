-module(fixture_base_handoff).
-export([run/1]).
-record(pt, {x, y}).

%% Category B from the corpus study: the base case hands the accumulator
%% to a continuation function instead of returning it bare or reading
%% only its fields - found via inets/httpc.erl's header_record/4 and
%% throughout xmerl_scan.erl's continuation-passing scanner.
finish(P) -> P.

run(N) -> loop(#pt{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> finish(P);
loop(P, I, N) ->
    loop(P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0}, I + 1, N).
