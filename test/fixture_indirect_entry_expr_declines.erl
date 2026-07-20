-module(fixture_indirect_entry_expr_declines).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(pt, {x, y}).

%% The entry call's accumulator argument is neither a bare variable nor
%% a literal construction - it's a function call's own result, spliced
%% in directly. Nothing to read fields off of statically (there's no
%% variable name at that position at all); must still decline.
make_pt() -> #pt{x = 0.0, y = 0.0}.

wrapper(N) -> loop(make_pt(), 0, N).

run(N) -> wrapper(N).

loop(P, I, N) when I >= N -> P;
loop(P, I, N) ->
    loop(P#pt{x = P#pt.x + 1.0, y = P#pt.y + 2.0}, I + 1, N).
