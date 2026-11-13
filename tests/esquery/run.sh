#!/usr/bin/env bash
# Differential test of esquery/ (the V port of esquery 1.7.0 and of ESLint 10.6.0's dispatch of
# selectors) against esquery and ESLint themselves, on the ESTree of a code corpus (a third of the
# fixtures of tests/rules and some sources of build/eval):
# - match: for every selector (the strings of ESLint's tests of no-restricted-syntax, esquery and
#   the traverser, selectors generated at random over the node types, attributes and values of the
#   corpus, and mutations of those), whether esquery.parse accepts it and every node
#   esquery.matches matches, with the ancestry ESLint gives;
# - run: for 600 groups of selectors (the option lists of no-restricted-syntax's tests and random
#   ones, some with :exit), every listener call ESLint makes, in its order.
# It also runs esquery's unit tests. Dev-time only: it needs the node_modules of
# tests/eval_spider_byte.sh and the sparse clone of ESLint in build/upstream/eslint
# (tests/upstream/README.md).
#
# Usage: tests/esquery/run.sh   (V: the v binary, default `v`; JOBS: processes, default nproc)
set -euo pipefail
cd "$(dirname "$0")/../.."
export V_C_ERROR_BUG_REPORT_DISABLED=1 V_MACOS_V3_NO_FALLBACK=1
V=${V:-v}
OUT=build/esquery-oracle
JOBS=${JOBS:-$(nproc)}
mkdir -p "$OUT"
{
	find tests/rules -name 'cases.ts' -o -name 'cases.tsx' | LC_ALL=C sort | awk 'NR % 3 == 1'
	find build/eval/*/src -name '*.ts' -o -name '*.tsx' 2> /dev/null | LC_ALL=C sort | awk 'NR % 400 == 1'
} > "$OUT/files.txt"
node tests/esquery/selectors.mjs "$OUT"
"$V" -prod -cc gcc -o "$OUT/esq_dump" tests/esquery/main.v
"$V" test esquery/
for mode in match run; do
	input=$OUT/selectors.txt
	[[ $mode == run ]] && input=$OUT/groups.txt
	for ((i = 0; i < JOBS; i++)); do
		node tests/esquery/oracle.mjs "$mode" "$input" "$OUT/files.txt" "$i/$JOBS" > "$OUT/$mode.oracle.$i.tsv" &
		"$OUT/esq_dump" "$mode" "$input" "$OUT/files.txt" "$i/$JOBS" > "$OUT/$mode.v.$i.tsv" &
	done
	wait
	cat "$OUT"/$mode.oracle.*.tsv | grep -v '^$' | LC_ALL=C sort > "$OUT/$mode.oracle.tsv"
	cat "$OUT"/$mode.v.*.tsv | grep -v '^$' | LC_ALL=C sort > "$OUT/$mode.v.tsv"
done
status=0
for mode in match run; do
	if cmp -s "$OUT/$mode.oracle.tsv" "$OUT/$mode.v.tsv"; then
		echo "esquery $mode: $(wc -l < "$OUT/$mode.v.tsv") inputs as esquery and ESLint"
	else
		echo "esquery $mode: differences (< esquery and ESLint, > veslint)"
		diff "$OUT/$mode.oracle.tsv" "$OUT/$mode.v.tsv" | head -20
		status=1
	fi
done
exit $status
