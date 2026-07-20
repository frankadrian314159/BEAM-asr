# BEAM-asr

An Erlang/BEAM port of FOL's Aggregate Scalar Replacement (ASR). Built as
the third-language existence-proof referenced in the CGO 2027 paper
*"Objects Without Allocation"*'s Threats to Validity section, which
asserts the mechanism "transfers to other transpiled dynamic languages"
without demonstrating it beyond FOL itself. `cpython-asr` (sibling repo)
is language #2; this is language #3, following the CPython -> BEAM ->
Julia roadmap.

Erlang has no loop construct and no mutation (single-assignment
variables) - iteration is exclusively a function tail-calling itself
with updated arguments, which maps onto FOL's own `loop`/`recur` model
more directly than Python's `while` loop did. But the "loop" *is* the
function's own parameter list, so scalarizing the accumulator changes
that function's own clause patterns - a real safety requirement, not
just a completeness gap. `asr_transform` is a
[`parse_transform`](https://www.erlang.org/doc/apps/erts/absform.html)
(Erlang's compiler-sanctioned, compile-time AST-rewriting hook): given a
tail-recursive helper function that threads a record accumulator through
its own back-edge, it splits the accumulator into one scalar argument per
field, re-boxing only at the base case. Unlike both FOL and cpython-asr,
**no world-guard/hot-reload-safety mechanism is needed at all** - BEAM's
own semantics guarantee a running process only switches code versions at
its next *fully-qualified* (`Mod:F(...)`) call, so a self-recursive
*local* tail call cannot observe a version change mid-recursion. See the
module docstring in `src/asr_transform.erl` and the design notes
referenced from the commit history for the full reasoning.

## Status: v1 + v1.1 (interprocedural inlining) + v1.2 (multi-accumulator) + v1.3 (branch-shaped reconstruction) + v1.4 (record field defaults, base-case continuation handoff) + v1.5 (head-alias patterns, hoisted intermediate bindings)

| Concept | This port |
|---|---|
| Qualification (which functions are safe to scalarize) | `asr_transform:try_qualify/5`, `classify_clauses/5` - per-clause classification into base/recursive/unrelated, requiring the function be unexported with no external call sites other than full-record-construction "entry" calls |
| The classify-and-rewrite walk | `asr_transform:classify_recursive/10` (full reconstruction, partial update via record-update syntax, unchanged pass-through, or one-level-inlined helper call) and `rewrite_clause_multi/2` |
| Record-field-read/collision safety | `collect_var_uses/2` (every non-tail use of the accumulator must be a known-field read), `check_collision/2` (synthesized scalar names checked per clause, since Erlang forbids rebinding a variable within a clause) |
| No FOL/cpython-asr analog - interface preservation | scalarizing changes the function's own arity, so v1 only qualifies a function that is not `-export`ed and has no call sites outside its own recursive self-calls and entry-call wrappers |
| No FOL/cpython-asr analog - world guard | not needed; see above |
| `_try_inline_call` (cpython-asr v1.1) | `asr_transform:try_inline/3` - one-level inlining of a single-clause, unguarded helper whose body is a straight-line sequence of field-read-only intermediate bindings terminating in a full reconstruction; gensym'd temp names collision-checked against the caller clause |
| `_try_branch_reconstruction`/multi-accumulator fixpoint (cpython-asr v1.2) | **branch-shaped reconstruction needs no new code at all** - FOL's `cond`/`if`/`case` maps onto Erlang's own idiomatic guarded multi-clause dispatch, which v1's per-clause classification already handles; **multi-accumulator** is `combine_accum_plans/3` - every candidate position is qualified fully independently (cross-accumulator field reads are already tolerated for free, since `collect_var_uses` doesn't care which argument position it's scanning), then combined with one extra check (`check_cross_scalar_collision/1`) and one shared rewrite pass (`rewrite_recursive_multi/5`, `rewrite_nonrecursive_multi/5`) |
| Record field defaults (v1.4, corpus-study Category A) | `collect_record_defaults/1` resolves every field's declared (or Erlang's own implicit `undefined`) default; `check_full_construction/5` accepts an entry call that omits a field with a default instead of requiring every field named explicitly; `field_expr_or_default/3` supplies it at rewrite time |
| Base-case continuation handoff (v1.4, corpus-study Category B) | `classify_base/7` allows the accumulator's one remaining bare occurrence anywhere in the clause (guard or body, not just trailing position) - `subst_bare_return/5` was already a fully generic tree walk that re-boxes wherever it finds that occurrence, so no rewrite-side change was needed, only the qualification-time restriction was removed |

| Head-alias pattern (v1.5, corpus-study Category D, narrow slice) | `extract_accum_pat/1` also recognizes `Var=#rec{field=SubVar,...}` as a clause's own accumulator pattern, not just a bare variable - every field sub-pattern must be a wildcard or a fresh plain-variable binding (a literal sub-pattern, e.g. an implicit-guard constant match, stays out of scope and still declines); `alias_rename_map/2` renames each alias variable to the same scalar name an ordinary field read would use |
| Hoisted intermediate binding (v1.5, corpus-study Category F, narrow slice) | `try_hoist_single_binding/4` splices a single-use `Vk = VName#rec{...}` statement directly into the tail call's own argument position before the rest of qualification runs, so every later check operates exactly as if that reconstruction had been written at the call site directly - a chain of length exactly one; a helper call anywhere in the chain is out of scope (would need real interprocedural purity analysis, well beyond `try_inline/3`'s own narrow one-hop scope) |

Both v1.4 fixes were motivated directly by `corpus-study/README.md`'s
hand-audited false-positive categories against real Erlang/OTP code
(`digraph:set_type/2`, `httpc:header_record/4`); the v1.5 fixes came
from the same report's follow-on analysis - see that report for the
full before/after qualification numbers, including why v1.5 verifiably
works (dedicated fixtures) but didn't move this specific corpus's
qualifying count, since every candidate it was expected to help turned
out to hit a second, independent blocker in some other clause of the
same function.

Explicitly deferred: intra-clause `case`/`if` *guarding* a
reconstruction within a single clause (not "free" the way clause-head
dispatch is - declines cleanly when encountered); mutual tail recursion
between multiple named functions; `lists:foldl`/`foldr` as an
alternative loop shape; two-level (chained) interprocedural inlining;
indirect entry construction (a record built in an earlier statement and
passed by variable, rather than a literal `#rec{...}` at the call site -
corpus-study Category E); an accumulator passed bare into an opaque
helper mid-chain (would need real interprocedural purity verification,
not just one-hop pure-reconstruction inlining).

## Layout

- `src/asr_transform.erl` - the `parse_transform/2` entry point, qualification (phase 1), and rewrite (phase 2)
- `test/asr_transform_tests.erl` - EUnit tests, positive (full reconstruction, partial update, pass-through, guards on both clause kinds, inlining with/without intermediate bindings, symmetric/asymmetric multi-accumulator, omitted-field-with-default entry call, base-case continuation handoff, head-alias pattern, hoisted intermediate binding) and negative/abort-safe (exported helper, bad call site, intra-clause case, name collision, guarded/multi-clause/nested-call/temp-collision inline declines, cross-accumulator scalar collision, two bare accumulator occurrences in one base clause, literal alias sub-pattern, escaping intermediate binding), each against paired fixture modules in `test/fixture_*.erl`
- `corpus-study/` - a shape-recognizing analyzer run against 30 real Erlang/OTP files, measuring ASR candidate-loop density and hand-auditing why most decline; see `corpus-study/README.md`
- `benchmarks/` - all 14 benchmarks from the paper's Table 1, ported from FOL's `benchmarks/fol-code/asr-*.fol`; see `benchmarks/README.md` for results and how to run them

## Running

```bash
rebar3 eunit
cd benchmarks && ./run.sh
```
