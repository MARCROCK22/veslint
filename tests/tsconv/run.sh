#!/usr/bin/env bash
# Differential test of the converter from TypeScript's AST to tree-sitter's tree
# (tsgo/inproc/convert*.go): for every file of the lists given (default: the ESTree corpus,
# build/estree-oracle/corpus/list.txt, which has the fixtures of tests/rules and tests/scope, the
# code of the upstream cases and the sources of build/eval's projects), tree-sitter's rows and the
# converter's must be identical in every value (symbol, field, flags, bytes, points, shape), unless
# TypeScript reports parse diagnostics for the file (ESLint then reports a parsing error and
# nothing else). summary.py sums the results per class of difference and per kind.
#
# Usage: tests/tsconv/run.sh [SET|LIST...]   (JOBS: processes, default 2; OUT: results
# directory, default tsgo/inproc/out/tsconv/results). A SET is corpus (the default), fixtures
# (every .ts and .tsx under tests/), zod, recharts or typescript (the files tests/bench/run.sh
# lints, in build/eval); anything else is a file with one path per line.
set -euo pipefail
cd "$(dirname "$0")/../.."
JOBS=${JOBS:-2}
OUT=${OUT:-tsgo/inproc/out/tsconv/results}
tests/tsconv/build.sh
mkdir -p "$OUT"
sets=("$@")
if ((${#sets[@]} == 0)); then
	sets=(corpus)
fi
: > "$OUT/list.txt"
for set in "${sets[@]}"; do
	case $set in
	corpus) cat build/estree-oracle/corpus/list.txt ;;
	fixtures) find "$PWD/tests" \( -name node_modules -prune \) -o \( -name '*.ts' -o -name '*.tsx' \) -type f -print | LC_ALL=C sort ;;
	zod) (cd build/eval/zod/packages/zod && find src -name '*.ts' -not -name '*.test.ts' -not -path '*/tests/*' -not -path '*/benchmarks/*' | LC_ALL=C sort | sed "s|^|$PWD/|") ;;
	recharts) (cd build/eval/recharts && find src \( -name '*.ts' -o -name '*.tsx' \) -not -name '*.d.ts' | LC_ALL=C sort | sed "s|^|$PWD/|") ;;
	typescript) (cd build/eval/typescript && find src -name '*.ts' -not -path 'src/lib/*' -not -name '*.d.ts' | LC_ALL=C sort | sed "s|^|$PWD/|") ;;
	*) cat "$set" ;;
	esac >> "$OUT/list.txt"
done
for ((i = 0; i < JOBS; i++)); do
	tsgo/inproc/out/tsconv/tsconv diff "$OUT/list.txt" "$i/$JOBS" > "$OUT/diff.$i.tsv" &
done
wait
cat "$OUT"/diff.*.tsv | LC_ALL=C sort > "$OUT/diff.tsv"
rm -f "$OUT"/diff.*.tsv
python3 tests/tsconv/summary.py "$OUT/diff.tsv"
