-module(fixture_alias_pattern_asr).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {x, y, tag}).

finish(P, Tag) -> {P, Tag}.

run(N) -> loop(#pt{x = 0.0, y = 0.0, tag = final}, 0, N).

loop(P = #pt{tag = T}, I, N) when I >= N -> finish(P, T);
loop(P = #pt{x = X}, I, N) ->
    loop(P#pt{x = X + 1.0, y = P#pt.y + 2.0}, I + 1, N).
