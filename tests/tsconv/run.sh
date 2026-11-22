#!/usr/bin/env bash
# Differential test of the converter from TypeScript's AST to tree-sitter's tree
# (tsgo/inproc/convert*.go): for every file of the lists given (default: the ESTree corpus,
# build/estree-oracle/corpus/list.txt, which has the fixtures of tests/rules and tests/scope, the
# code of the upstream cases and the sources of build/eval's projects), tree-sitter's rows and the
# converter's must be identical in every value (symbol, field, flags, bytes, points, shape), unless
# TypeScript reports parse diagnostics for the file (ESLint then reports a parsing error and
# nothing else). summary.py sums the results per class of difference and per kind.
#
# Usage: tests/tsconv/run.sh [LIST...]   (JOBS: processes, default 2; OUT: results directory,
# default tsgo/inproc/out/tsconv/results)
set -euo pipefail
cd "$(dirname "$0")/../.."
JOBS=${JOBS:-2}
OUT=${OUT:-tsgo/inproc/out/tsconv/results}
tests/tsconv/build.sh
mkdir -p "$OUT"
lists=("$@")
if ((${#lists[@]} == 0)); then
	lists=(build/estree-oracle/corpus/list.txt)
fi
cat "${lists[@]}" > "$OUT/list.txt"
for ((i = 0; i < JOBS; i++)); do
	tsgo/inproc/out/tsconv/tsconv diff "$OUT/list.txt" "$i/$JOBS" > "$OUT/diff.$i.tsv" &
done
wait
cat "$OUT"/diff.*.tsv | LC_ALL=C sort > "$OUT/diff.tsv"
rm -f "$OUT"/diff.*.tsv
python3 tests/tsconv/summary.py "$OUT/diff.tsv"
