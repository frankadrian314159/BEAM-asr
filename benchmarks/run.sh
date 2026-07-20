#!/usr/bin/env bash
# Compiles and runs all 14 ported benchmarks.
# asr_transform.beam must be built first since the _asr modules load it
# as a parse_transform at their own compile time.
set -euo pipefail
cd "$(dirname "$0")"
OUT="$(mktemp -d)"
erlc -o "$OUT" ../src/asr_transform.erl
erlc -o "$OUT" bench_util.erl
erlc -o "$OUT" -pa "$OUT" \
  bench_particle_plain.erl bench_particle_asr.erl bench_particle_counted.erl \
  bench_counter_plain.erl bench_counter_asr.erl bench_counter_counted.erl \
  bench_assoc_plain.erl bench_assoc_asr.erl bench_assoc_counted.erl \
  bench_rotation_plain.erl bench_rotation_asr.erl bench_rotation_counted.erl \
  bench_biquad_plain.erl bench_biquad_asr.erl bench_biquad_counted.erl \
  bench_comoments_plain.erl bench_comoments_asr.erl bench_comoments_counted.erl \
  bench_lorenz_plain.erl bench_lorenz_asr.erl bench_lorenz_counted.erl \
  bench_mandelbrot_plain.erl bench_mandelbrot_asr.erl bench_mandelbrot_counted.erl \
  bench_projectile_plain.erl bench_projectile_asr.erl bench_projectile_counted.erl \
  bench_bounce_plain.erl bench_bounce_asr.erl bench_bounce_counted.erl \
  bench_clamp_plain.erl bench_clamp_asr.erl bench_clamp_counted.erl \
  bench_phase_plain.erl bench_phase_asr.erl bench_phase_counted.erl \
  bench_kalman_plain.erl bench_kalman_asr.erl bench_kalman_counted.erl \
  bench_twobody_plain.erl bench_twobody_asr.erl bench_twobody_counted.erl \
  run_all.erl
erl -noshell -pa "$OUT" -eval "run_all:main(), init:stop()."
