-module(fixture_inline_direct_asr).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(rot, {re, im}).

rotate(Z) ->
    #rot{re = Z#rot.re * 0.9950041652780258 - Z#rot.im * 0.09983341664682815,
         im = Z#rot.re * 0.09983341664682815 + Z#rot.im * 0.9950041652780258}.

run(N) -> loop(#rot{re = 1.0, im = 0.0}, 0, N).

loop(Z, I, N) when I >= N -> Z#rot.re + Z#rot.im;
loop(Z, I, N) ->
    loop(rotate(Z), I + 1, N).
