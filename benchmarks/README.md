# BEAM-asr benchmarks

18 benchmarks: 14 ported from FOL's own `benchmarks/fol-code/asr-*.fol`
(the paper's full Table 1 set - the same benchmarks `cpython-asr`
ported), plus 4 real functions extracted **verbatim** from Erlang/OTP
28.5 - the corpus study's own "unlocked loops" (v1.6). Each exists as
three modules: `bench_X_plain` (no transform, baseline), `bench_X_asr`
(`-compile({parse_transform, asr_transform})`), and `bench_X_counted`
(plain, but bumps an ETS counter immediately before every `#record{}`
construction - Erlang records have no runtime constructor to
monkey-patch, so this is the exact-count alternative
`../../cpython-asr/harness.py`'s own tracemalloc-avoidance note already
argues for).

Grouped by which BEAM-asr feature tier each one exercises:

- **v1 (single accumulator, direct reconstruction)**: Particle, Counter, Assoc
- **v1.1 (interprocedural inlining)**: Rotation, Biquad, Comoments, Lorenz, Mandelbrot, Projectile - each routes its reconstruction through a separate one-level-inlinable helper function rather than reconstructing directly in the recursive tail call
- **v1.2 (multi-accumulator)**: Kalman (two record types, asymmetric field counts, cross-coupled), Twobody (two accumulators of the *same* record type, symmetric coupling - checks parallel-update simultaneity survives double unboxing)
- **v1.3 (branch-shaped reconstruction)**: Bounce (`cond`, 3-way), Clamp (`if`, 2-way), Phase (`case` on `I rem 3`, 3-way) - ported as idiomatic Erlang guarded multi-clause dispatch rather than an embedded `case`/`if` expression, which BEAM-asr's v1 already qualifies with **zero new transform code**: each guard's own clause reconstructs independently, exactly the same shape as any other recursive clause
- **v1.6 (real corpus-study loops, extracted verbatim)**: XmlVsn (`xmerl_scan:xml_vsn/4` + `scan_xml_vsn/2`, xmerl_scan.erl:1164-1193), ScanSysLit (`xmerl_scan:scan_system_literal/4` + `/2`, xmerl_scan.erl:3208-3233), Strip (`xmerl_scan:strip/3` + `/2`, xmerl_scan.erl:4027-4050) - all three share the real, full 40-field `#xmerl_scanner{}` record (xmerl.hrl:146-194); ValidateHdr (`httpc:validate_headers/3`, httpc.erl:1974-1993) uses the real, full 39-field `#http_request_h{}` record (http_internal.hrl:74-117). Each file's header comment cites the exact upstream line range; `?dbg`/`?fatal`/helper functions on dead (out-of-input or error) paths are minimal stand-ins, since this benchmark's finite, valid input never reaches them - documented per-file. See "Real functions" below for why ValidateHdr's result is a genuine regression, not a bug.

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
Particle            5.34         4.37    1.22x        500001x  0 (eliminated)
Counter             4.64         4.03    1.15x        500001x  0 (eliminated)
Assoc               4.32         4.26    1.01x        500001x  0 (eliminated)
Rotation           11.36         6.31    1.80x        500001x  0 (eliminated)
Biquad             13.37        10.20    1.31x        500001x  0 (eliminated)
Comoments          19.12        17.46    1.09x        500001x  0 (eliminated)
Lorenz             16.56        12.06    1.37x        500001x  0 (eliminated)
Mandelbrot         13.23         7.92    1.67x        500001x  0 (eliminated)
Projectile         10.08         9.09    1.11x        500001x  0 (eliminated)
Bounce              6.94         5.69    1.22x        500001x  0 (eliminated)
Clamp               5.56         4.59    1.21x        500001x  0 (eliminated)
Phase               4.78         3.40    1.41x        500001x  0 (eliminated)
Kalman             24.21        17.31    1.40x       1000002x  0 (eliminated)
Twobody            17.35        11.40    1.52x       1000002x  0 (eliminated)
XmlVsn             25.93        22.87    1.13x        500002x  0 (eliminated)
ScanSysLit         87.32        45.39    1.92x        500001x  0 (eliminated)
Strip              47.76        12.25    3.90x        500000x  0 (eliminated)
ValidateHdr        10.74        27.00    0.40x        500000x  0 (eliminated)
```

Single machine, one coherent run of all 18 together (numbers for the
original 14 shift run-to-run with machine load, same as any wall-clock
benchmark - this table reflects one consistent session, not a mix of
old and new runs). Kalman and Twobody's construction counts are ~2x the
others because each iterates two accumulator constructions per loop
step (2 records for Kalman, 2 for Twobody). XmlVsn/ScanSysLit/Strip's
counts (N+2/N+1/N) reflect exactly which of their clauses reconstruct:
XmlVsn's entry wrapper *and* its final delimiter-match clause both
reconstruct once each in addition to the N per-character steps;
ScanSysLit's entry wrapper passes its accumulator through bare (no
reconstruction) but its final clause does; Strip's entry and final
clauses are both bare, so its count is exactly N. All eliminated to 0.
ASR construction counts of 0 are not sampled - they are structural:
post-transform, the record-construction and -update syntax is provably
absent from the function's forms entirely (the `-record(...)`
declaration itself goes unused, and for v1.1 benchmarks the helper
function itself goes unused too, since it's fully inlined away - both of
which are why compiling any `bench_*_asr.erl` module emits "unused
record"/"unused function" warnings, an independent, unplanned
confirmation of elimination from `erl_lint`, not something this
benchmark harness asserts itself).

## Real functions: three wins, one honest regression

The three string-scanning loops (XmlVsn, ScanSysLit, Strip) each run
their reconstruction once per character of a long input, exactly the
shape ASR targets - and Strip's 3.90x is the largest win in this whole
suite, on the *real*, unmodified 40-field `#xmerl_scanner{}` record,
not a synthetic 2-3 field one.

**ValidateHdr's 0.40x is a genuine, reproducible regression - not a
bug, and worth understanding precisely because it's real.**
`validate_headers/3` is not a long scan; it's a short, bounded
normalization (at most 2 recursive hops, regardless of input) called
repeatedly from outside. That shape inverts ASR's usual cost model:

- **Baseline**, per call: one `#http_request_h{host=Host}` update (a
  39-element tuple copy) in the first hop; the second hop returns the
  *same* tuple reference bare, no further allocation. One allocation,
  total.
- **ASR**, per call: the *entry call* must splice in one field-read
  expression per field - all 39, unconditionally, since the current
  Category E implementation has no "which fields does this function
  actually touch" liveness analysis and conservatively reads every one.
  Internally the two hops thread 39 scalars through cheaply (no
  allocation - just passing already-bound values). But the *return*
  value is a real record the caller needs back, so `subst_bare_return/5`
  reboxes all 39 fields into a fresh tuple at the exit - the same
  allocation the baseline already paid once, PLUS the 39 entry-side
  reads the baseline never paid at all, for zero amortization benefit
  (there was only ever one allocation to eliminate, and reboxing at
  the return means ASR never actually eliminates it here).

The general principle: **ASR's payoff scales with how many internal
iterations amortize the one-time unbox/rebox cost.** A tight loop with
thousands of steps (Strip, ScanSysLit, every synthetic benchmark above)
amortizes that cost across every step it skips reconstructing. A
short, bounded function called frequently from outside pays the
unbox/rebox cost on nearly every call with almost nothing to amortize
it against - and if the record is wide (39-40 fields, real-world scale,
not the toy records above), the entry-side splice-all-fields cost alone
can outweigh the one allocation being saved. This is a real, useful
boundary finding for the paper: BEAM-asr does not just target "loops
over records," it specifically targets loops with enough *iterations*
per invocation, and a corpus's own record-accumulator functions can be
qualifying-but-not-worth-it as easily as they can be non-qualifying.

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

## Two ways to go negative: Julia's phantom allocation vs. BEAM's unamortized unboxing

All 14 *synthetic, long-loop* benchmarks measure a real speedup,
including Kalman (1.40x here) and Twobody (1.52x) - the two largest,
most complex ones, each with a second accumulator and (for Kalman) 13
intermediate bindings per iteration. This was specifically re-checked
across three independent runs of Kalman alone (1.37x/1.39x/1.50x) after
`Julia-asr`'s own Kalman benchmark turned up a reproducible **0.87x
regression** on the same shape - `@allocated` there confirmed both the
baseline and `@asr`'d Julia versions were already zero-allocation (Julia's
own JIT eliminates the struct via escape analysis before the transform
ever runs), so the regression was ASR's own parallel temp-then-assign
staging adding real copy-through overhead with no allocation win left to
offset it.

BEAM never hits *that* failure mode, for a structural reason: an Erlang
record is a genuine heap-allocated tagged tuple, not a value type a
JIT's escape analysis can unbox away - so the allocation ASR eliminates
in a long loop is real and present in every one of these 14 baselines,
never already optimized away by the BEAM VM itself.

But BEAM-asr *does* go negative here too, for a completely different,
BEAM-specific reason: ValidateHdr (0.40x, above). Julia's regression is
about the host compiler already having done ASR's job for free, for a
loop shape ASR is otherwise well-suited to. BEAM's regression is about
applying ASR to a shape it's poorly suited to in the first place - a
short, bounded, frequently-called function on a wide record, where
there's no long inner loop to amortize the unbox/rebox cost against.
Put together, the two ports' negative results make a broader point than
either alone: ASR's payoff isn't just *smaller* or *larger* depending on
the host, and it isn't just about whether the host already did the
work - a real transform applied to a real, qualifying loop can still
lose, for reasons specific to that loop's own shape, not just its
language's runtime. That's exactly why gating deployment on
measurement (per the corpus study's own qualifying-but-untested
candidates) matters as much as gating it on qualification.

## Caveats (v1-v1.6 scope)

Single machine, no statistical significance testing beyond the trial
mean. Whole-module opt-in only (`-compile({parse_transform,...})`).
Still out of scope: intra-clause `case`/`if` *guarding* a reconstruction
within a single clause when the same clause's own trailing form isn't a
literal tail call and no other clause of the function satisfies it
either (as opposed to clause-head dispatch, covered for free since v1,
or a case-embedded self-call inside an otherwise-qualifying function,
handled since v1.6 - see `src/asr_transform.erl`'s module docstring);
mutual tail recursion between multiple named functions;
`lists:foldl`/`foldr` as an alternative loop shape; two-level (chained)
interprocedural inlining; an accumulator passed bare into a genuinely
opaque helper (would need real interprocedural purity analysis) - see
`src/asr_transform.erl`'s module docstring and commit history for the
full qualification rules.
