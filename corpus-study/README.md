# BEAM-asr corpus study

A shape-recognizing analyzer for ASR candidate loops in Erlang, run
against 30 real files from Erlang/OTP, reporting candidate-loop density
and a categorized, hand-audited breakdown of why most candidates don't
qualify under the real transform. Methodology mirrors FOL's own corpus
study (`../../FOL/fol/docs/cgo2027/corpus-study/`) and cpython-asr's
(`../../cpython-asr/corpus-study/`): a syntactic-shape Pass 1 (an
upper-bound proxy) followed by a gate-faithful Pass 2 that runs the
*real* `asr_transform.erl` as a black-box oracle, never a
re-implementation that could drift from the actual v1–v1.6 rules.

**Update (v1.4)**: this study's own Category A and Category B findings
(below) were fed back into `asr_transform.erl` as two targeted fixes —
record-declared-default support for omitted entry-call fields (Category
A), and relaxing the base-case gate to allow the accumulator's one
remaining bare occurrence anywhere in the clause, not just as its
trailing return (Category B). Re-running this exact study against the
updated transform now shows 2 of 41 candidates qualifying:
`digraph:set_type/2` (Category A) and `httpc:header_record/4` (Category
B). The numbers below reflect that re-run; the original 0-of-41 result
is what motivated the fixes in the first place, not an error corrected
after the fact.

**Update (v1.5)**: a further analysis pass, instrumenting the real
transform to report *why* each remaining candidate declines (not just
true/false), surfaced two more fixable shapes in the still-declining
`record_strong` sites — a clause pattern that binds the whole
accumulator *and* destructures a field right in the head (`Category D`,
e.g. `S=#xmerl_scanner{col=C}`), and a reconstruction that happens in an
intermediate binding rather than directly at the tail call's own
argument position (`Category F` narrow slice, e.g. xmerl's own
`?bump_col(N)` macro). Both were implemented, with clean fixtures and
EUnit coverage proving the mechanisms correct in isolation (see
`README.md`'s Status table). **Re-running this study against the v1.5
transform still shows 2 of 41 qualifying — unchanged.** This is not a
bug: every site Category D/F were expected to help (`strip/3`,
`xml_vsn/4`, `fetch_DTD/2`, `scan_comment1/5`, `initial_state/2`,
`scan_entity_value/7`, `validate_headers/3`, `get_options/2`) turned out
to hit a *second, independent* blocker in some other clause of the same
function once the first one was cleared — see "Two new categories,
implemented but not yet reflected in this corpus" below for exactly
which blocker each site actually hit. The fixes are real and the
mechanisms are verified; this corpus's specific 8 candidate functions
just each needed more than one fix simultaneously to fully qualify.

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
Gate-faithful qualification: qualified=6  declined=35  unknown=0
```

**Headline density**: 41 record-shaped candidate positions across 345
loop sites (11.9% of loop sites have at least one record-shaped
position) and 83.46 KLOC (0.49 candidate positions per KLOC).
Under the original v1–v1.3 transform, **0 of 41 (0%) qualified**; v1.4's
Category A/B fixes brought that to **2 of 41 (4.9%)**; v1.6's three
further fixes (below) bring it to **6 of 41 (14.6%)** —
`digraph:set_type/2`, `httpc:header_record/4`, `httpc:validate_headers/3`,
`xmerl_scan:xml_vsn/4`, `xmerl_scan:scan_system_literal/4`, and
`xmerl_scan:strip/3`. The honest bracket, mirroring FOL/cpython-asr's
own framing: *at most* 11.9% of loop sites are record-accumulator-shaped
by syntax; *at least* 14.6% (measured, not estimated) are actually
ASR-addressable in this corpus as written, up from 0% before v1.4.

### Per-file / per-domain breakdown

| File | Domain | KLOC | Loop sites | RecStrong | RecWeak | Qualified |
|---|---|---:|---:|---:|---:|---:|
| kernel/src/file.erl | kernel-io | 3.06 | 6 | 0 | 2 | 0 |
| stdlib/src/lists.erl | stdlib-lists | 4.37 | 58 | 0 | 2 | 0 |
| stdlib/src/string.erl | stdlib-strings | 3.17 | 25 | 0 | 3 | 0 |
| stdlib/src/gen_server.erl | stdlib-otp-behavior | 3.12 | 5 | 0 | 1 | 0 |
| stdlib/src/maps.erl | stdlib-maps | 1.34 | 6 | 0 | 3 | 0 |
| stdlib/src/digraph.erl | stdlib-graphs | 0.88 | 6 | 1 | 0 | 1 |
| compiler/src/v3_core.erl | compiler | 4.64 | 26 | 0 | 4 | 0 |
| crypto/src/crypto.erl | crypto | 4.30 | 13 | 0 | 0 | 0 |
| ssl/src/ssl.erl | ssl-tls | 3.94 | 3 | 0 | 0 | 0 |
| public_key/src/public_key.erl | public-key-crypto | 3.34 | 20 | 0 | 4 | 0 |
| ssh/src/ssh.erl | ssh-protocol | 1.39 | 2 | 0 | 1 | 0 |
| mnesia/src/mnesia.erl | database | 5.31 | 15 | 0 | 5 | 0 |
| xmerl/src/xmerl_scan.erl | xml-parsing | 4.38 | 39 | 7 | 2 | 3 |
| inets/src/http_client/httpc.erl | http-client | 2.04 | 7 | 2 | 1 | 2 |
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

## Why (almost) none qualified: three categories, hand-audited, two now fixed

Every `record_strong` hit and a representative sample of `record_weak`
hits were read directly (not inferred from the tool's own decline path,
which carries no reason string by design — see BEAM-asr's "clean
decline" discipline) and re-run against a minimal reproduction to
confirm the actual cause. Three distinct categories emerged, mirroring
FOL/cpython-asr's own structurally-unfixable / analysis-gap / scanner-noise
split. This analysis is preserved historically below (it's what
motivated the v1.4 fixes); the "Now" column reflects the current,
post-fix status of each category's representative site.

| Category | Site | File | Reason | Now |
|---|---|---|---|---|
| **A — analysis gap** | `set_type/2` | stdlib/digraph.erl | Entry call `set_type(Ts, #digraph{vtab=V, etab=E, ntab=N})` omits the `cyclic` field, relying on the record's own declared default (`cyclic = true`). `check_full_construction` required every field named explicitly; it didn't know about record-declared defaults. **Confirmed by direct repro**: the identical function qualified the instant `cyclic` was spelled out at the call site. Directly analogous to cpython-asr's own v1.7 fix for Python's live-reflection-only defaults. | **Fixed in v1.4** — `collect_record_defaults/1` now resolves every declared (or Erlang's own implicit `undefined`) default; `set_type/2` qualifies. |
| **B — scope boundary (base case hands off, doesn't return)** | `header_record/4` | inets/httpc.erl | Base case is `header_record([], H, ...) -> validate_headers(H, ...)` — it *pipes* the accumulator into another function rather than returning it bare or reading only its fields. v1's rule only re-boxed a literal tail-position `return`-equivalent (the bare accumulator itself); a "hand off to a continuation" was a different, unsupported shape. **Confirmed by direct repro.** Same root pattern accounts for 7 of the 8 xmerl_scan.erl hits, which use a continuation-passing scanner design (`F(fun(...) -> scan(...) end, ...)`) throughout — an idiom this whole file is built around. | **Fixed in v1.4** — `classify_base/7` now allows the accumulator's one remaining bare occurrence anywhere in the clause, not just in trailing position; `header_record/4` qualifies. The 7 xmerl_scan.erl siblings still decline — the handoff shape wasn't their only gate failure (not re-audited individually; see caveats). |
| **C — Pass-1 over-approximation (scanner noise, not a real ASR limitation)** | `do_flatten/2`, `init_it/6`, `foreach_1/3`, `pkix_dist_points/1`, `uguard/4`, `sleep/1` | lists/gen_server/maps/public_key/v3_core/ct | The flagged "helper call" is unrelated to records entirely: a nested list-building self-call (`do_flatten`), a BIF (`self()`), an opaque-iterator advance (`try_next`), a cert-decoding call, a compiler-internal list helper, and a units-normalization redirect (`sleep({hours,H}) -> sleep(...)`) respectively. `record_weak` is deliberately loose (any call at that position, unverified) — Pass 2 correctly rejects all of these, and by direct inspection none was ever a record-accumulator loop at all. **This is the dominant category by volume**: every `record_weak` hit sampled (6 of 31, spanning 6 different files) fell into it. | Unaffected by v1.4 — these were never record-accumulator loops, so no analysis-gap fix applies. |

No example of the fourth, FOL/cpython-asr-named "structurally unfixable"
category (their "aliased-reference"/quicksort-swap shape) turned up in
this corpus — plausibly because that shape is specific to in-place
swap/rotate algorithms operating on a mutable collection, which is rare
in idiomatic Erlang (no in-place mutation at all) rather than because
BEAM-asr's qualification is somehow immune to it.

**Why only 1 of 8 Category B sites actually flipped to qualifying**:
the base-case-handoff fix removes exactly one gate constraint. A site
still declines if it fails a *different* constraint — e.g. more than
one bare occurrence of the accumulator in the clause, a field-name
mismatch, or (for `xmerl_scan.erl` specifically) many of its 7 sibling
hits sit in functions with 15–31 clauses total, only a handful of which
are the recursive/base pair this scanner's Pass 1 flagged position
against; the actual gate runs the whole real transform across every
clause, and OTP's scanner functions are large enough that a second,
independent decline reason is plausible in several of them. This wasn't
re-audited clause-by-clause for this update (would require the same
manual-repro discipline as the original category read); the honest
claim is narrower than "Category B is fixed" — it's "the base-handoff
*shape itself* no longer blocks qualification," which is exactly what
`fixture_base_handoff.erl`'s EUnit coverage verifies in isolation.

## Two new categories (v1.5): implemented, but not reflected in this corpus's numbers

Following the "why only 1 of 8" thread above, the still-declining
`record_strong` sites were re-audited using an instrumented copy of the
real transform that reports *why* each candidate declines (not just
true/false) instead of relying on a re-implementation. This surfaced
two more fixable shapes, both implemented in v1.5:

| Category | Shape | Example | Fix |
|---|---|---|---|
| **D — head-alias pattern** | The clause's own pattern binds the whole accumulator *and* destructures a field, right in the head, instead of a bare variable — `S=#xmerl_scanner{col=C}`. `classify_recursive`'s `VName` extraction only accepted a bare `{var,_,V}`. | `xml_vsn/4`, `fetch_DTD/2`, `scan_comment1/5`, `strip/3` (xmerl_scan.erl); `validate_headers/3`, `get_options/2` (httpc.erl) | `extract_accum_pat/1` now also recognizes the alias shape when every field sub-pattern is a wildcard or a fresh plain-variable binding (narrow slice — a literal sub-pattern like `#http_request_h{host=undefined}` is an implicit guard and stays out of scope, correctly still declining). |
| **F — hoisted intermediate binding (narrow slice)** | The reconstruction happens in an intermediate statement, not directly at the tail call's own argument position — the shape behind xmerl's own `?bump_col(N)` macro (`S = S0#xmerl_scanner{col = S0#xmerl_scanner.col+N}` ahead of the tail call). | `initial_state/2`, `scan_entity_value/7` (xmerl_scan.erl) | `try_hoist_single_binding/4` splices a single-use `Vk = VName#rec{...}` statement directly into the tail call's own argument position before the rest of qualification runs — a chain of length exactly one; a helper call anywhere in the chain (see below) stays out of scope. |

Both are verified correct in isolation: `fixture_alias_pattern.erl`/
`fixture_hoisted_binding.erl` (positive, arity-change + runtime-equality
checked) and `fixture_alias_nested_declines.erl`/
`fixture_hoisted_binding_escapes_declines.erl` (negative boundary
cases) in `../test/`. (The literal-sub-pattern boundary fixture from
this era was later repurposed into `fixture_alias_guard.erl` once v1.6
made that shape qualify - see below.)

**Re-running this study against v1.5 still showed 2 of 41 qualifying —
the same 2 as v1.4.** Re-diagnosing each of the 8 sites above against
the real (fixed) transform showed why: every one hit a *second*,
independent blocker in some other clause of the same function, once
the alias-pattern or hoisting blocker was cleared:

| Site | Second blocker (at v1.5) | Detail |
|---|---|---|
| `xml_vsn/4` | Intra-clause `case` counted the update-expr's own base as a false bare use | Its last clause's body is a bare `case ... end`, not a literal tail call, so it's classified as a base clause; inside that case, `collect_var_uses` didn't yet recognize `S#xmerl_scanner{...}` as a safe touch of S wherever it appeared, so it was double-counted as bare alongside the untaken branch's `?fatal(...,S)` — 2 bare uses, over budget. **Resolved in v1.6, see below.** |
| `strip/3` | Category E — indirect entry construction (not yet implemented) | `strip/2`'s own body is `strip(Str,S,all)` — an entry call to `strip/3` where the record arrives as an already-bound variable, not a literal `#rec{...}` at the call site. **Resolved in v1.6, see below.** |
| `fetch_DTD/2` | A separate clause with genuinely multiple bare accumulator uses | `fetch_DTD/2`'s third clause passes the accumulator bare into `fetch_and_parse/3` inside a `case`, more than once across its branches — unrelated to the alias-pattern clause Category D fixed. **Still declines** — a real multi-bare-use, not any of the shapes v1.6 targeted. |
| `scan_comment1/5`, `initial_state/2`, `scan_entity_value/7` | Accumulator passed bare to an opaque helper (interprocedural, out of scope) | E.g. `initial_state/2`: `S1 = event_state(ES, S#xmerl_scanner{event_fun=F}), initial_state(T, S1)` — `event_state/2` receives the accumulator as an extra argument alongside other data; verifying it doesn't leak/misuse it would need real interprocedural purity analysis, well beyond the "one pure reconstruction, one hop" scope Category F's narrow slice deliberately kept to. **Still declines** — deliberately out of scope for v1.6 too. |
| `validate_headers/3` | Category D's own literal-sub-pattern boundary (by design) | Its recursive clause pattern is `RequestHeaders=#http_request_h{host=undefined}` — a literal, not a plain-var binding, so it was correctly outside the narrow D slice. **Resolved in v1.6, see below.** |
| `get_options/2` | Not actually a record loop at all | Re-checked directly: its only "record_weak" clause is `get_options(all=_Options, Profile) -> get_options(get_options(), Profile)` — a special-atom-to-real-value redirect, structurally identical to `sleep({hours,H}) -> sleep(...)`. This was Category C scanner noise misfiled among the record_strong-adjacent group, not a genuine Category D/F candidate — no fix applies or should. |

None of this was a defect in the v1.5 implementation — each mechanism
did exactly what it was designed to do, confirmed by dedicated
fixtures. It was a genuine finding about this corpus: real OTP functions
this size (7–40 clauses) tend to accumulate more than one
qualification-blocking idiom at once, so a single targeted fix rarely
flips a whole function on its own. Three of the sites above were
resolved by the v1.6 fixes below; two remain out of scope by design.

## v1.6: three more fixes, six of eight sites resolved

Following the "second blocker" table above, three targeted fixes closed
every remaining gap except the two genuinely out-of-scope ones
(`fetch_DTD/2`'s real multi-bare-use, and the interprocedural
opaque-helper cases):

| Fix | Shape | Change |
|---|---|---|
| **Update-expression transparency** | `collect_var_uses` didn't recognize `Var#rec{field=Expr}` as a safe touch of `Var` anywhere except when `classify_recursive` manually destructured it at the exact tail-call position - everywhere else (a `case` branch, a base-clause return) its own base object was miscounted as bare. | `collect_var_uses/3` now recognizes the update-expression shape directly and recurses only into its field-value expressions, wherever it appears. |
| **Category D full slice: guard-conversion** | A ground literal/nested alias sub-pattern with no wildcards or variable bindings inside it (e.g. `#http_request_h{host=undefined}`) acts as an implicit guard - the narrow v1.5 slice declined on anything beyond a wildcard or plain-var binding. | The field still gets its ordinary scalar pattern var (unchanged pattern-splicing); a guard `ScalarVar =:= Literal` is appended instead. `=:=` performs deep structural equality, so this covers any ground nested pattern, not just flat atoms. |
| **Category E: indirect entry construction** | An entry call's accumulator argument is a bare variable (e.g. a wrapper function's own parameter, forwarded through) or an update expression - neither is a literal `#rec{...}` at the call site, which `check_full_construction` required. | Accepts both shapes: a bare variable gets one field-read expression spliced in per field (`Var#rec.field`); an update expression uses its own explicit overrides and reads every other field the same way. Both rely on the same guarantee the original program already needed - if the value isn't actually shaped like the record at runtime, it's a loud `badrecord`, not silent miscompilation. |

Verified in isolation via 7 new fixtures in `../test/`: positive/negative
pairs for each shape, plus a base-clause-vs-recursive-clause split for
the update-expression fix and a bare-var-vs-update-expression split for
Category E.

**Re-running this study against v1.6 now shows 6 of 41 qualifying** —
`digraph:set_type/2`, `httpc:header_record/4` (from v1.4), plus
`httpc:validate_headers/3`, `xmerl_scan:xml_vsn/4`,
`xmerl_scan:scan_system_literal/4`, and `xmerl_scan:strip/3` (new in
v1.6). All three v1.6 fixes were needed together, not any single one
alone: `xml_vsn/4` needed the update-expression fix; `validate_headers/3`
needed both the update-expression fix (its second clause) *and*
guard-conversion (its first clause); `strip/3` and `scan_system_literal/4`
needed Category E's bare-variable shape, and `xml_vsn/4` additionally
needed Category E's update-expression shape at its own entry call
(`scan_xml_vsn/2`'s `xml_vsn(T, S#xmerl_scanner{col=S#xmerl_scanner.col+1}, H, [])`) -
discovered only once the update-expression-transparency fix got far
enough to expose it as the *next* blocker.

## A methodology gap this study's own oracle had: qualifying isn't compiling

`analyzer/asr_gate_check.erl`'s "qualifies" signal only ever checked
whether the target function's *arity changed* after running the real
transform - never whether the resulting Forms actually *compile*. This
was a real gap, not a hypothetical one: building `xml_vsn/4` into a
standalone benchmark (`../benchmarks/README.md`) - the full real
function, extracted verbatim rather than just gate-checked in place -
surfaced a genuine rewrite bug undetected by "qualifies=true" alone.
`xml_vsn/4`'s last clause is a `case` expression with one branch that
recurses (`xml_vsn(T, S#xmerl_scanner{col=...}, Delim, [H|Acc])`); since
that clause's own trailing form is the `case`, not a literal tail call,
it's classified as a base clause, and nothing in the rewrite pass
updated that *embedded* self-call to the function's new arity - a
`function xml_vsn/4 undefined` compile error, not a wrong-answer bug,
but a real failure `asr_gate_check.erl`'s arity-only check couldn't see
(the top-level function's own arity had already changed correctly by
the time this embedded call was reached). Fixed alongside a second,
related gap the same investigation uncovered: `subst_bare_return/5`
didn't share `collect_var_uses/3`'s own update-expression awareness, so
it would replace an update expression's accumulator base with a
redundant full reconstruction instead of reconstructing the update
directly - technically correct in isolation, but it turned the
embedded self-call's own argument into an opaque expression the splice
logic couldn't read fields back off of efficiently. Both fixes are in
`asr_transform.erl` (see its module docstring) with a dedicated
regression fixture (`fixture_case_embedded_selfcall.erl`) in `../test/`.
All four of this study's v1.6-unlocked real functions
(`validate_headers/3`, `xml_vsn/4`, `scan_system_literal/4`, `strip/3`)
are now verified to a stronger bar than "qualifies": each one compiles,
runs, and produces bit-identical output to its untransformed original
inside a dedicated benchmark module extracted verbatim from Erlang/OTP.
`asr_gate_check.erl` itself is unchanged (still arity-only) - this gap
is noted here for anyone relying on its "qualifies" column as a
stronger guarantee than it actually provides.

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
- **14.6% qualifying in this specific corpus (up from 0% pre-v1.4)
  should not be read as "ASR now handles most real Erlang code"** — the
  benchmarks (`../benchmarks/`) demonstrate ASR provides genuine
  1.0x-1.79x wins on the exact reconstruct-a-fresh-record-each-iteration
  shape it targets. This study's finding is narrower and more useful
  than that: real OTP library code's record-accumulator loops were
  overwhelmingly *not* shaped like FOL's own motivating benchmark
  pattern (an accumulator freshly constructed right at the loop's own
  entry point) - they were threaded in from a caller that constructed
  the value elsewhere (category A / Category E, now fixed), piped into a
  continuation rather than returned (category B, now fixed as a shape),
  destructured via a head-alias pattern or a ground-literal guard
  (category D, now fixed), reconstructed through an intermediate
  binding or an update expression the analysis couldn't see through yet
  (category F / the v1.6 transparency fix, now fixed), passed bare into
  a genuinely opaque helper (still out of scope - would need real
  interprocedural purity analysis), or not record loops at all once you
  look past the syntax (category C, unfixable because unrelated). Six
  fixes across three releases (v1.4-v1.6) moved this corpus from 0% to
  14.6% qualifying; each fix closed a real, distinct gap, but real OTP
  functions this size routinely stack more than one such gap in the same
  function, so progress here is incremental by nature, not a single
  "solve applicability" moment.
