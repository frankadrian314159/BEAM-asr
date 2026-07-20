# BEAM-asr corpus study

A shape-recognizing analyzer for ASR candidate loops in Erlang, run
against 30 real files from Erlang/OTP, reporting candidate-loop density
and — since none of the candidates found actually qualify under the
real transform — a categorized, hand-audited breakdown of why.
Methodology mirrors FOL's own corpus study
(`../../FOL/fol/docs/cgo2027/corpus-study/`) and cpython-asr's
(`../../cpython-asr/corpus-study/`): a syntactic-shape Pass 1 (an
upper-bound proxy) followed by a gate-faithful Pass 2 that runs the
*real* `asr_transform.erl` as a black-box oracle, never a
re-implementation that could drift from the actual v1–v1.3 rules.

## The analyzer

`analyzer/asr_candidate_scanner.erl` finds every **loop site** — a
tail-self-recursive Erlang function, the language's only iteration
construct and BEAM-asr's whole target shape — and classifies each
parameter position threaded through the recursive call by accumulator
**kind**, based on what the tail call's argument at that position looks
like across every recursive clause:

| Kind | Shape | ASR-addressable? |
|---|---|---|
| `record_strong` | a literal `#rec{...}` construction or `#rec{...}` update at the tail call itself | yes (v1's own target shape) |
| `record_weak` | threaded through a function call instead (`Pos = helper(...)`) | *possibly* (v1.1 inlining) — **not verified by Pass 1**, flagged only because *some* call appears there; see Results |
| `map` | a `#{...}` map construction/update | no (the closest analogue to FOL/cpython-asr's map/"transient territory" category) |
| `collection` | cons/list-building (`[H\|T]`) | no |
| `scalar` | a bare variable or simple arithmetic expression in every recursive clause | no — the already-hand-optimized form |
| `other` | none of the above | no |

This is deliberately a **syntactic upper-bound proxy**, exactly like
FOL's `analyze.clj` and cpython-asr's `analyze.py`: it answers "does
this position look record-shaped," not "would BEAM-asr actually
transform it." `record_weak` in particular is intentionally
over-inclusive — any function call at that position is flagged, the
same design FOL's own `weak_hits.clj` uses, on the assumption that Pass
2 filters the noise out.

`analyzer/asr_gate_check.erl` is Pass 2: for every `record_strong`/
`record_weak` candidate, it runs `asr_transform:parse_transform/2` — the
actual, tested, shipped transform — directly on the file's own parsed
forms and checks whether the candidate function's arity changed (the
same signal `asr_transform_tests.erl`'s own
`assert_qualified`/`assert_declined` helpers use). This can never drift
from the real qualification rules, because it *is* the real qualification
rules — no separate "explain" logic was written into `asr_transform.erl`
itself, keeping this study's oracle and the production transform
identical by construction.

## Corpus

30 files, one per Erlang/OTP application, each the canonical/most-central
module of that application (`lists.erl` for stdlib, `crypto.erl` for
crypto, `ssl.erl` for TLS, etc.) — chosen for domain representativeness,
**not** cherry-picked for expected hits. Full list with domain tags in
`manifest.txt`. Spans ~20 distinct domains: OS/file I/O, core data
structures (lists/maps/graphs/strings), OTP process behaviors, compiler
internals, cryptography (x2), network protocols (TLS/SSH/HTTP/SNMP/
Diameter/Megaco), database (Mnesia), XML parsing, ASN.1 encoding, static
analysis (Dialyzer), AST tooling, code coverage, monitoring, tracing,
release management (x2), parser generation, testing frameworks (x2), an
interpreter/debugger, and documentation generation.

**Corpus provenance**: `C:\Users\frank\Projects\Erlang-OTP`, a shallow
clone of `OTP-28.5` (`git clone --branch OTP-28.5 --depth 1`), used
read-only throughout this project as reference material (see BEAM-asr's
own design-grounding history). Not re-fetched or re-pinned separately
for this study since it was already a fixed, unmodified local checkout.

## Running

```bash
cd corpus-study
./run.sh   # optionally: ./run.sh /path/to/Erlang-OTP/lib
```

Raw output from the run this report is based on is saved at
`results-raw.txt`.

## Results

```
Files scanned OK: 30 / 30 (zero parse failures)
Total LOC: 83,457 (83.46 KLOC)
Tail-self-recursive functions (loop sites, unique): 345
Candidate positions by kind: record_strong=10  record_weak=31  map=0  collection=0  scalar=0  other=0
Record-shaped (strong+weak) positions: 41
Gate-faithful qualification: qualified=0  declined=41  unknown=0
```

**Headline density**: 41 record-shaped candidate positions across 345
loop sites (11.9% of loop sites have at least one record-shaped
position) and 83.46 KLOC (0.49 candidate positions per KLOC) — but
**0 of 41 (0%) actually qualify** under the real v1–v1.3 transform.
The honest bracket, mirroring FOL/cpython-asr's own framing: *at most*
11.9% of loop sites are record-accumulator-shaped by syntax; *at least*
0% (measured, not estimated) are actually ASR-addressable in this
corpus as written.

### Per-file / per-domain breakdown

| File | Domain | KLOC | Loop sites | RecStrong | RecWeak | Qualified |
|---|---|---:|---:|---:|---:|---:|
| kernel/src/file.erl | kernel-io | 3.06 | 6 | 0 | 2 | 0 |
| stdlib/src/lists.erl | stdlib-lists | 4.37 | 58 | 0 | 2 | 0 |
| stdlib/src/string.erl | stdlib-strings | 3.17 | 25 | 0 | 3 | 0 |
| stdlib/src/gen_server.erl | stdlib-otp-behavior | 3.12 | 5 | 0 | 1 | 0 |
| stdlib/src/maps.erl | stdlib-maps | 1.34 | 6 | 0 | 3 | 0 |
| stdlib/src/digraph.erl | stdlib-graphs | 0.88 | 6 | 1 | 0 | 0 |
| compiler/src/v3_core.erl | compiler | 4.64 | 26 | 0 | 4 | 0 |
| crypto/src/crypto.erl | crypto | 4.30 | 13 | 0 | 0 | 0 |
| ssl/src/ssl.erl | ssl-tls | 3.94 | 3 | 0 | 0 | 0 |
| public_key/src/public_key.erl | public-key-crypto | 3.34 | 20 | 0 | 4 | 0 |
| ssh/src/ssh.erl | ssh-protocol | 1.39 | 2 | 0 | 1 | 0 |
| mnesia/src/mnesia.erl | database | 5.31 | 15 | 0 | 5 | 0 |
| xmerl/src/xmerl_scan.erl | xml-parsing | 4.38 | 39 | 7 | 2 | 0 |
| inets/src/http_client/httpc.erl | http-client | 2.04 | 7 | 2 | 1 | 0 |
| asn1/src/asn1ct.erl | asn1-encoding | 2.33 | 17 | 0 | 0 | — |
| diameter/src/base/diameter.erl | telecom-protocol | 2.08 | 0 | 0 | 0 | — |
| megaco/src/engine/megaco_config.erl | telecom-protocol | 2.19 | 4 | 0 | 0 | — |
| snmp/src/agent/snmpa.erl | network-management | 2.78 | 3 | 0 | 0 | — |
| dialyzer/src/dialyzer.erl | static-analysis | 1.28 | 2 | 0 | 0 | — |
| syntax_tools/src/erl_syntax.erl | ast-tooling | 8.54 | 2 | 0 | 1 | 0 |
| tools/src/cover.erl | code-coverage | 3.12 | 31 | 0 | 0 | — |
| observer/src/etop.erl | monitoring | 0.55 | 2 | 0 | 0 | — |
| runtime_tools/src/dbg.erl | tracing | 3.20 | 18 | 0 | 0 | — |
| sasl/src/release_handler.erl | release-management | 3.09 | 9 | 0 | 0 | — |
| parsetools/src/yecc.erl | parser-generator | 3.32 | 12 | 0 | 0 | — |
| eunit/src/eunit.erl | testing-framework | 0.36 | 1 | 0 | 0 | — |
| common_test/src/ct.erl | testing-framework | 1.68 | 1 | 0 | 1 | 0 |
| debugger/src/dbg_ieval.erl | interpreter | 2.28 | 11 | 0 | 1 | 0 |
| edoc/src/edoc.erl | documentation-generator | 0.88 | 1 | 0 | 0 | — |
| reltool/src/reltool.erl | release-management | 0.53 | 0 | 0 | 0 | — |

`—` = no record-shaped candidates in that file, so no gate check ran.
xmerl_scan.erl (a streaming XML scanner) and httpc.erl (an HTTP client)
account for over a third of all record-shaped hits — both are exactly
the kind of "structured protocol state" code the shape-recognizer is
designed to catch, and the corpus's clearest domain-level concentration.

## Why zero qualify: three categories, hand-audited

Every `record_strong` hit and a representative sample of `record_weak`
hits were read directly (not inferred from the tool's own decline path,
which carries no reason string by design — see BEAM-asr's "clean
decline" discipline) and re-run against a minimal reproduction to
confirm the actual cause. Three distinct categories emerged, mirroring
FOL/cpython-asr's own structurally-unfixable / analysis-gap / scanner-noise
split:

| Category | Site | File | Reason |
|---|---|---|---|
| **A — analysis gap (fixable)** | `set_type/2` | stdlib/digraph.erl | Entry call `set_type(Ts, #digraph{vtab=V, etab=E, ntab=N})` omits the `cyclic` field, relying on the record's own declared default (`cyclic = true`). `check_full_construction` requires every field named explicitly; it doesn't know about record-declared defaults. **Confirmed by direct repro**: the identical function qualifies the instant `cyclic` is spelled out at the call site. Directly analogous to cpython-asr's own v1.7 fix for Python's live-reflection-only defaults. |
| **B — scope boundary (base case hands off, doesn't return)** | `header_record/4` | inets/httpc.erl | Base case is `header_record([], H, ...) -> validate_headers(H, ...)` — it *pipes* the accumulator into another function rather than returning it bare or reading only its fields. v1's rule only re-boxes a literal tail-position `return`-equivalent (the bare accumulator itself); a "hand off to a continuation" is a different, unsupported shape. **Confirmed by direct repro.** Same root pattern accounts for 7 of the 8 xmerl_scan.erl hits, which use a continuation-passing scanner design (`F(fun(...) -> scan(...) end, ...)`) throughout — an idiom this whole file is built around. |
| **C — Pass-1 over-approximation (scanner noise, not a real ASR limitation)** | `do_flatten/2`, `init_it/6`, `foreach_1/3`, `pkix_dist_points/1`, `uguard/4`, `sleep/1` | lists/gen_server/maps/public_key/v3_core/ct | The flagged "helper call" is unrelated to records entirely: a nested list-building self-call (`do_flatten`), a BIF (`self()`), an opaque-iterator advance (`try_next`), a cert-decoding call, a compiler-internal list helper, and a units-normalization redirect (`sleep({hours,H}) -> sleep(...)`) respectively. `record_weak` is deliberately loose (any call at that position, unverified) — Pass 2 correctly rejects all of these, and by direct inspection none was ever a record-accumulator loop at all. **This is the dominant category by volume**: every `record_weak` hit sampled (6 of 31, spanning 6 different files) fell into it. |

No example of the fourth, FOL/cpython-asr-named "structurally unfixable"
category (their "aliased-reference"/quicksort-swap shape) turned up in
this corpus — plausibly because that shape is specific to in-place
swap/rotate algorithms operating on a mutable collection, which is rare
in idiomatic Erlang (no in-place mutation at all) rather than because
BEAM-asr's qualification is somehow immune to it.

## Honest caveats

- **Small corpus, real code, not cherry-picked for hits** — 30 files
  across ~20 domains, not thousands across dozens of projects the way
  FOL's (2,905 files/29 projects) and cpython-asr's (10,074 files/27
  projects) studies were. This measures *this* corpus, not "Erlang
  in general"; treat the 11.9%-shaped / 0%-qualifying numbers as a
  single, honest data point, not a population estimate.
  Single-project-family bias: all 30 files are OTP itself (one
  organization's house style), not independently-authored community
  code the way the sibling studies pulled from many separate authors/
  organizations - OTP's own coding conventions (e.g. the
  continuation-passing style dominating category B) may be
  over-represented relative to Erlang code generally.
- **Category C's count is a lower bound on scanner noise, not an exact
  measurement** — only 6 of 31 `record_weak` hits were individually
  read; the other 25 were not hand-verified (though every one sampled,
  across 6 different files, fell into category C, giving reasonable
  confidence it's the dominant pattern rather than a coincidence).
- **The gate-faithful Pass 2 oracle is exactly the shipped
  `asr_transform.erl`**, so its own known scope boundaries apply
  unchanged: no `for`-equivalent construct exists in Erlang to worry
  about, but multi-accumulator, inlining, and branch-shaped
  reconstruction are all exercised by the real transform during Pass 2
  exactly as they'd run in production — a candidate declining here is a
  genuine decline under the current shipped rules, not an artifact of a
  simplified study-only checker.
- **0% qualifying in this specific corpus should not be read as "ASR
  is useless for real Erlang code"** — the benchmarks (`../benchmarks/`)
  demonstrate ASR provides genuine 1.0x-1.79x wins on the exact
  reconstruct-a-fresh-record-each-iteration shape it targets. This study's
  finding is narrower and more useful than that: real OTP library code's
  record-accumulator loops are overwhelmingly *not* shaped like FOL's own
  motivating benchmark pattern (an accumulator freshly constructed right
  at the loop's own entry point) - they're either threaded in from a
  caller that constructed the value elsewhere (category A), piped into a
  continuation rather than returned (category B), or not record loops at
  all once you look past the syntax (category C). That's a real,
  actionable finding about where the mechanism's applicability boundary
  currently sits, not a verdict on its usefulness.
