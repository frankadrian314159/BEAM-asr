%% ASR Benchmark: Biquad IIR filter (audio DSP). Ported from
%% benchmarks/fol-code/asr-biquad.fol. Four-field record rebuilt every
%% sample by an inlinable helper with intermediate bindings.
-module(bench_biquad_plain).
-export([run/1]).
-record(biquad, {x1, x2, y1, y2}).

biquad_step(St) ->
    X1 = St#biquad.x1,
    X2 = St#biquad.x2,
    Y1 = St#biquad.y1,
    Y2 = St#biquad.y2,
    Xin = 1.0,
    Y = (((0.1 * Xin) + (0.2 * X1)) + (0.1 * X2) + (0.9 * Y1)) - (0.2 * Y2),
    #biquad{x1 = Xin, x2 = X1, y1 = Y, y2 = Y1}.

run(N) -> loop(#biquad{x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0}, 0, N).

loop(St, I, N) when I >= N -> St#biquad.y1;
loop(St, I, N) ->
    loop(biquad_step(St), I + 1, N).
