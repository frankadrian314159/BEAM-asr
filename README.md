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

## Status: v1

| Concept | This port |
|---|---|
| Qualification (which functions are safe to scalarize) | `asr_transform:try_qualify/5`, `classify_clauses/4` - per-clause classification into base/recursive/unrelated, requiring the function be unexported with no external call sites other than full-record-construction "entry" calls |
| The classify-and-rewrite walk | `asr_transform:classify_recursive/8` (full reconstruction, partial update via record-update syntax, or unchanged pass-through) and `rewrite_clause/2` |
| Record-field-read/collision safety | `collect_var_uses/2` (every non-tail use of the accumulator must be a known-field read), `check_collision/2` (synthesized scalar names checked per clause, since Erlang forbids rebinding a variable within a clause) |
| No FOL/cpython-asr analog - interface preservation | scalarizing changes the function's own arity, so v1 only qualifies a function that is not `-export`ed and has no call sites outside its own recursive self-calls and entry-call wrappers |
| No FOL/cpython-asr analog - world guard | not needed; see above |

Explicitly deferred to v1.1+: intra-clause `case`/`if` expressions
guarding a reconstruction (not "free" the way clause-head dispatch is -
declines cleanly when encountered); interprocedural inlining through a
helper function; mutual tail recursion between multiple named functions;
multi-accumulator (more than one record threaded through the same
recursion); `lists:foldl`/`foldr` as an alternative loop shape.

## Layout

- `src/asr_transform.erl` - the `parse_transform/2` entry point, qualification (phase 1), and rewrite (phase 2)
- `test/asr_transform_tests.erl` - EUnit tests, positive (full reconstruction, partial update, pass-through, guards on both clause kinds) and negative/abort-safe (exported helper, bad call site, intra-clause case, name collision), each against paired fixture modules in `test/fixture_*.erl`
- `benchmarks/` - Particle, Counter, and Assoc, ported from FOL's `benchmarks/fol-code/asr-*.fol`; see `benchmarks/README.md` for results and how to run them

## Running

```bash
rebar3 eunit
cd benchmarks && ./run.sh
```
