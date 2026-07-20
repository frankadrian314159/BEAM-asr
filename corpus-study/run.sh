#!/usr/bin/env bash
# Runs the corpus-study scanner against the 30-file corpus in manifest.txt.
# Requires a local Erlang/OTP source checkout (see README.md "Corpus
# provenance" for the pinned commit) - pass its lib/ directory as $1, or
# it defaults to the path used when this study was built.
set -euo pipefail
cd "$(dirname "$0")"
OTP_LIB="${1:-C:/Users/frank/Projects/Erlang-OTP/lib}"
OUT="$(mktemp -d)"
erlc -o "$OUT" ../src/asr_transform.erl
erlc -o "$OUT" analyzer/asr_candidate_scanner.erl
erlc -o "$OUT" -pa "$OUT" analyzer/asr_gate_check.erl
erlc -o "$OUT" -pa "$OUT" analyzer/run_corpus_scan.erl
# Erlang runs as a native Windows executable and needs native paths,
# not the MSYS-style /c/... paths bash's pwd/$1 may supply.
MANIFEST_WIN="$(cygpath -w "$(pwd)/manifest.txt" | sed 's/\\/\//g')"
erl -noshell -pa "$OUT" -eval "run_corpus_scan:main([\"$OTP_LIB\", \"$MANIFEST_WIN\"]), init:stop()."
