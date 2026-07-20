-module(fixture_case_embedded_selfcall).
-export([run/1]).
-record(pt, {x, y}).

%% v1.6 fix: a base clause (its own trailing form is a case expression,
%% not a literal tail call) whose branches each embed an actual
%% recursive call to loop/3 - mirrors xmerl_scan.erl's xml_vsn/4 exactly
%% (its last clause: `case ... of true -> xml_vsn(...); false ->
%% ?fatal(...) end`). Exercises two things together: subst_bare_return/5
%% must reconstruct an update expression's own accumulator base directly
%% (not wastefully, via generic bare-occurrence replacement) so the
%% result is a proper full construction; and that reconstruction, once
%% embedded in the self-call's own argument position, must still get its
%% accumulator argument spliced like a genuine external entry call. One
%% branch partially updates (exercises the scalar-fallback path for the
%% untouched field), the other fully updates (no fallback needed).
run(N) -> loop(#pt{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) when I rem 2 =:= 0 ->
    case I rem 4 of
        0 -> loop(P#pt{x = P#pt.x + 1.0}, I + 1, N);
        _ -> loop(P#pt{x = P#pt.x + 3.0, y = P#pt.y + 4.0}, I + 1, N)
    end;
loop(P, I, N) ->
    loop(P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0}, I + 1, N).
