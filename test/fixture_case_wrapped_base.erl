-module(fixture_case_wrapped_base).
-export([run/1]).
-record(pt, {x, y}).

finish(P) -> P.

%% v1.6: a base clause whose whole body is a case expression, with the
%% accumulator used bare in one branch (a hand-off, already supported)
%% and as the base of an update expression in another - before this
%% fix, collect_var_uses miscounted the update expression's own base
%% object as a second bare occurrence, exceeding the one-bare budget.
%% Mirrors xmerl_scan.erl's xml_vsn/4 and httpc.erl's validate_headers/3.
run(N) -> loop(#pt{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N ->
    case N of
        0 -> finish(P);
        _ -> P#pt{y = P#pt.y + 100.0}
    end;
loop(P, I, N) ->
    loop(P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0}, I + 1, N).
