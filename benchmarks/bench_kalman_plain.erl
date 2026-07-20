%% ASR Benchmark: 1D constant-velocity Kalman filter (state estimation).
%% Ported from benchmarks/fol-code/asr-kalman.fol. Two coupled record
%% accumulators - state <kstate>{x,v} and covariance <kcov>{p00,p01,p11}
%% (asymmetric field counts) - each step's predict+update reads both and
%% rebuilds both: the multi-accumulator case (v1.2).
-module(bench_kalman_plain).
-export([run/1]).
-record(kstate, {x, v}).
-record(kcov, {p00, p01, p11}).

run(N) -> loop(#kstate{x = 0.0, v = 0.0}, #kcov{p00 = 1.0, p01 = 0.0, p11 = 1.0}, 0, N).

loop(S, C, I, N) when I >= N -> S#kstate.x;
loop(S, C, I, N) ->
    X = S#kstate.x, V = S#kstate.v,
    P00 = C#kcov.p00, P01 = C#kcov.p01, P11 = C#kcov.p11,
    Xp = X + V,
    Pp00 = (P00 + 2.0 * P01) + (P11 + 0.001),
    Pp01 = P01 + P11,
    Pp11 = P11 + 0.001,
    Y = 10.0 - Xp,
    Sden = Pp00 + 0.1,
    K0 = Pp00 / Sden,
    K1 = Pp01 / Sden,
    loop(#kstate{x = Xp + K0 * Y, v = V + K1 * Y},
         #kcov{p00 = (1.0 - K0) * Pp00, p01 = (1.0 - K0) * Pp01, p11 = Pp11 - K1 * Pp01},
         I + 1, N).
