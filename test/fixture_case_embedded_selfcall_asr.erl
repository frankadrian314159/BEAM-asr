-module(fixture_case_embedded_selfcall_asr).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {x, y}).

run(N) -> loop(#pt{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) when I rem 2 =:= 0 ->
    case I rem 4 of
        0 -> loop(P#pt{x = P#pt.x + 1.0}, I + 1, N);
        _ -> loop(P#pt{x = P#pt.x + 3.0, y = P#pt.y + 4.0}, I + 1, N)
    end;
loop(P, I, N) ->
    loop(P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0}, I + 1, N).
