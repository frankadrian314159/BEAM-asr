# BEAM-asr benchmarks

All 14 benchmarks ported from FOL's own `benchmarks/fol-code/asr-*.fol`,
the paper's full Table 1 set - the same benchmarks `cpython-asr` ported.
Each exists as three modules: `bench_X_plain` (no transform, baseline),
`bench_X_asr` (`-compile({parse_transform, asr_transform})`), and
`bench_X_counted` (plain, but bumps an ETS counter immediately before
every `#record{}` construction - Erlang records have no runtime
constructor to monkey-patch, so this is the exact-count alternative
`../../cpython-asr/harness.py`'s own tracemalloc-avoidance note already
argues for).

Grouped by which BEAM-asr feature tier each one exercises:

- **v1 (single accumulator, direct reconstruction)**: Particle, Counter, Assoc
- **v1.1 (interprocedural inlining)**: Rotation, Biquad, Comoments, Lorenz, Mandelbrot, Projectile - each routes its reconstruction through a separate one-level-inlinable helper function rather than reconstructing directly in the recursive tail call
- **v1.2 (multi-accumulator)**: Kalman (two record types, asymmetric field counts, cross-coupled), Twobody (two accumulators of the *same* record type, symmetric coupling - checks parallel-update simultaneity survives double unboxing)
- **v1.3 (branch-shaped reconstruction)**: Bounce (`cond`, 3-way), Clamp (`if`, 2-way), Phase (`case` on `I rem 3`, 3-way) - ported as idiomatic Erlang guarded multi-clause dispatch rather than an embedded `case`/`if` expression, which BEAM-asr's v1 already qualifies with **zero new transform code**: each guard's own clause reconstructs independently, exactly the same shape as any other recursive clause

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
Benchmark        Base ms       ASR ms  Speedup    Base constr      ASR constr
----------------------------------------------------------------------------
Particle           12.57        10.48    1.20x        500001x  0 (eliminated)
Counter            10.32         8.94    1.16x        500001x  0 (eliminated)
Assoc               9.58         9.38    1.02x        500001x  0 (eliminated)
Rotation           26.48        15.16    1.75x        500001x  0 (eliminated)
Biquad             29.98        22.77    1.32x        500001x  0 (eliminated)
Comoments          43.50        39.36    1.11x        500001x  0 (eliminated)
Lorenz             37.64        26.62    1.41x        500001x  0 (eliminated)
Mandelbrot         29.48        17.61    1.67x        500001x  0 (eliminated)
Projectile         23.58        20.32    1.16x        500001x  0 (eliminated)
Bounce             15.91        12.58    1.26x        500001x  0 (eliminated)
Clamp              12.24        10.07    1.22x        500001x  0 (eliminated)
Phase              10.32         7.40    1.39x        500001x  0 (eliminated)
Kalman             54.71        40.69    1.34x       1000002x  0 (eliminated)
Twobody            38.59        25.42    1.52x       1000002x  0 (eliminated)
```

Single machine, Erlang/OTP 29. Kalman and Twobody's construction counts
are ~2x the others because each iterates two accumulator constructions
per loop step (2 records for Kalman, 2 for Twobody), all correctly
eliminated to 0. ASR construction counts of 0 are not sampled - they are
structural: post-transform, the record-construction and -update syntax
is provably absent from the function's forms entirely (the `-record(...)`
declaration itself goes unused, and for v1.1 benchmarks the helper
function itself goes unused too, since it's fully inlined away - both of
which are why compiling any `bench_*_asr.erl` module emits "unused
record"/"unused function" warnings, an independent, unplanned
confirmation of elimination from `erl_lint`, not something this
benchmark harness asserts itself).

## Why the speedup is smaller than cpython-asr's

cpython-asr's reconstruction-mode benchmarks measured 2-4x from
eliminating one Python object allocation (plus attribute dict/descriptor
overhead) per iteration. Here the *allocation count* delta is identical in
kind (500,001+ constructions to 0 across all 14), but the wall-time win is
consistently smaller (~1.02-1.75x) because a BEAM record is just a tagged
tuple - allocating and immediately discarding one in a tight, non-escaping
recursive loop is already cheap on this VM relative to CPython's object
model. This is a genuine, honestly-reportable finding for the paper's
existence-proof claim, not a benchmark artifact: the *mechanism* (unbox
the recursive accumulator, re-box only at the base case, extended to
inlined helpers, multiple simultaneous accumulators, and branch-shaped
reconstruction) transfers cleanly to a third language with entirely
different runtime characteristics, but the *magnitude* of the win is
host-VM-dependent, exactly the kind of nuance a single-language paper
can't surface on its own.

Assoc's smaller win than Particle/Counter echoes cpython-asr's own
"mutation mode" finding: three of Assoc's four fields pass through
untouched every iteration, so even the *baseline* allocates a smaller
effective payload win once ASR is applied (the pass-through fields were
never doing more than copying), which is visible here in the const-count
identical-but-timing-closer pattern. The heavier arithmetic kernels
(Comoments' divisions, Kalman's ~13 intermediate bindings per step) show
smaller relative wins too, for the same reason: allocation elimination is
a fixed per-iteration saving, so it matters less as a fraction of total
work when that work is itself larger.

## Caveats (v1-v1.3 scope)

Single machine, no statistical significance testing beyond the trial
mean. Whole-module opt-in only (`-compile({parse_transform,...})`).
Still out of scope, deferred to v1.4+: intra-clause `case`/`if`
*guarding* a reconstruction within a single clause (as opposed to
clause-head dispatch, which v1.3 already covers for free); mutual tail
recursion between multiple named functions; `lists:foldl`/`foldr` as an
alternative loop shape; two-level (chained) interprocedural inlining -
see `src/asr_transform.erl`'s module docstring and commit history for
the full qualification rules.
