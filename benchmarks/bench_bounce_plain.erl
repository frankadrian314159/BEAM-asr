%% ASR Benchmark: cond-branched reconstruction (bounce off two walls).
%% Ported from benchmarks/fol-code/asr-bounce.fol. FOL's `cond`-branched
%% reconstruction maps directly onto Erlang's own idiomatic guarded
%% multi-clause dispatch (each guard tried in order, first match wins -
%% the same semantics as `cond`), which BEAM-asr's v1 already qualifies
%% with no additional transform code: each clause's own reconstruction is
%% just an ordinary recursive-clause case.
-module(bench_bounce_plain).
-export([run/1]).
-record(bounce, {x, y}).

run(N) -> loop(#bounce{x = 0.0, y = 0.0}, 0, N).

loop(P, I, N) when I >= N -> P#bounce.x + P#bounce.y;
loop(P, I, N) when P#bounce.x > 100.0 ->
    loop(#bounce{x = 0.0, y = P#bounce.y}, I + 1, N);
loop(P, I, N) when P#bounce.x < -100.0 ->
    loop(#bounce{x = 0.0, y = P#bounce.y}, I + 1, N);
loop(P, I, N) ->
    loop(#bounce{x = P#bounce.x + 1.0, y = P#bounce.y + 0.5}, I + 1, N).
