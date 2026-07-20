-module(bench_mandelbrot_asr).
-compile({parse_transform, asr_transform}).
-export([run/1]).
-record(cplx, {re, im}).

mandel_step(Z) ->
    Zr = Z#cplx.re,
    Zi = Z#cplx.im,
    #cplx{re = ((Zr * Zr) - (Zi * Zi)) + (-0.123), im = (2.0 * (Zr * Zi)) + 0.745}.

run(N) -> loop(#cplx{re = 0.0, im = 0.0}, 0, N).

loop(Z, I, N) when I >= N -> Z#cplx.re + Z#cplx.im;
loop(Z, I, N) ->
    loop(mandel_step(Z), I + 1, N).
