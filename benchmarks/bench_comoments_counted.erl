-module(bench_comoments_counted).
-export([run/1]).
-record(comoments, {n, mx, my, cxy}).

comoment_step(St) ->
    bench_util:bump(comoments),
    N = St#comoments.n,
    Mx = St#comoments.mx,
    My = St#comoments.my,
    Cxy = St#comoments.cxy,
    N1 = N + 1.0,
    Dx = 1.0 - Mx,
    Mx1 = Mx + (Dx / N1),
    Dy = 2.0 - My,
    My1 = My + (Dy / N1),
    Dy2 = 2.0 - My1,
    #comoments{n = N1, mx = Mx1, my = My1, cxy = Cxy + (Dx * Dy2)}.

run(N) ->
    bench_util:reset_counter(comoments),
    bench_util:bump(comoments),
    loop(#comoments{n = 0.0, mx = 0.0, my = 0.0, cxy = 0.0}, 0, N).

loop(St, I, N) when I >= N -> St#comoments.cxy;
loop(St, I, N) ->
    loop(comoment_step(St), I + 1, N).
