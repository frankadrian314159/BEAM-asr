# BEAM-asr benchmarks

Three benchmarks ported from FOL's own `benchmarks/fol-code/asr-*.fol`
(Particle, Counter, Assoc), the same minimal set `cpython-asr` launched
with. Each exists as three modules: `bench_X_plain` (no transform,
baseline), `bench_X_asr` (`-compile({parse_transform, asr_transform})`),
and `bench_X_counted` (plain, but bumps an ETS counter immediately before
every `#record{}` construction - Erlang records have no runtime
constructor to monkey-patch, so this is the exact-count alternative
`../../cpython-asr/harness.py`'s own tracemalloc-avoidance note already
argues for).

## Running

```bash
cd benchmarks
./run.sh
```

Correctness (baseline vs. transformed output, bit-identical) gates any
timing report - `run_all:main/0` halts with a mismatch error before
printing anything if it doesn't hold, mirroring cpython-asr's
`harness.py` ordering.

## Results (mean of 30 trials after 1 warmup call, 500,000 iterations)

```
Benchmark       Base ms       ASR ms  Speedup    Base constr      ASR constr
--------------------------------------------------------------------------
Particle          11.4          9.8    1.16x        500001x  0 (eliminated)
Counter           10.6          9.1    1.16x        500001x  0 (eliminated)
Assoc               9.9          9.4    1.05x        500001x  0 (eliminated)
```

Single machine, Erlang/OTP 29. ASR construction counts of 0 are not
sampled - they are structural: post-transform, the record-construction
and -update syntax is provably absent from the function's forms
entirely (the `-record(...)` declaration itself goes unused, which is
why compiling any `bench_*_asr.erl` module emits an "unused record"
warning - an independent, unplanned confirmation of elimination from
`erl_lint`, not something this benchmark harness asserts itself).

## Why the speedup is smaller than cpython-asr's

cpython-asr's reconstruction-mode benchmarks measured 2-4x from
eliminating one Python object allocation (plus attribute dict/descriptor
overhead) per iteration. Here the *allocation count* delta is identical in
kind (500,001 constructions to 0), but the wall-time win is much smaller
(~1.05-1.16x) because a BEAM record is just a tagged tuple - allocating
and immediately discarding one in a tight, non-escaping recursive loop is
already cheap on this VM relative to CPython's object model. This is a
genuine, honestly-reportable finding for the paper's existence-proof
claim, not a benchmark artifact: the *mechanism* (unbox the recursive
accumulator, re-box only at the base case) transfers cleanly to a third
language with entirely different runtime characteristics, but the
*magnitude* of the win is host-VM-dependent, exactly the kind of nuance a
single-language paper can't surface on its own.

Assoc's smaller win than Particle/Counter echoes cpython-asr's own
"mutation mode" finding: three of Assoc's four fields pass through
untouched every iteration, so even the *baseline* allocates a smaller
effective payload win once ASR is applied (the pass-through fields were
never doing more than copying), which is visible here in the const-count
identical-but-timing-closer pattern.

## Caveats (v1 scope)

Single machine, no statistical significance testing beyond the trial
mean. Whole-module opt-in only (`-compile({parse_transform,...})`), no
intra-clause `case`/`if` branching, no interprocedural inlining, no
multi-accumulator support - see the BEAM-asr design notes for the full
v1 qualification rules and what's explicitly deferred to v1.1+.
