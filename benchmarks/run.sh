#!/usr/bin/env bash
# Compiles and runs the three ported benchmarks (Particle/Counter/Assoc).
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
  run_all.erl
erl -noshell -pa "$OUT" -eval "run_all:main(), init:stop()."
