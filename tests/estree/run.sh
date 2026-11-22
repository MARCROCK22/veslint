#!/usr/bin/env bash
# Differential test of estree/ (the ESTree of typescript-estree 8.72.2, built from tree-sitter's
# tree) against typescript-estree itself: for every file of the corpus (the fixtures of
# tests/rules and tests/scope, the code of every case of the upstream.json files and the sources
# of the projects of build/eval), the canonical serialization of the tree and the order of its
# traversal must be the same, byte for byte, or both must fail to parse. It also checks that
# estree/tables.v and estree/entities.v are what their generators make, and runs estree's unit
# tests. The trees are built from tree-sitter's rows and from TypeScript's (the converter of
# tsgo/inproc/convert.go, VESLINT_PARSER=typescript): with tree-sitter's, the files
# tests/estree/known.txt lists are expected to differ (the reason is there, all where tree-sitter
# reads the code differently from TypeScript); with TypeScript's, none.
# Dev-time only: it needs the node_modules of tests/eval_spider_byte.sh.
#
# Usage: tests/estree/run.sh   (V: the v binary, default `v`; JOBS: processes, default nproc)
set -euo pipefail
cd "$(dirname "$0")/../.."
export V_C_ERROR_BUG_REPORT_DISABLED=1 V_MACOS_V3_NO_FALLBACK=1
V=${V:-v}
OUT=build/estree-oracle
JOBS=${JOBS:-$(nproc)}
mkdir -p "$OUT"
node tools/gen_estree_tables.mjs "$OUT/tables.v" > /dev/null
"$V" fmt -w "$OUT/tables.v" > /dev/null
cmp "$OUT/tables.v" estree/tables.v
node tools/gen_estree_entities.cjs "$OUT/entities.v" > /dev/null
"$V" fmt -w "$OUT/entities.v" > /dev/null
cmp "$OUT/entities.v" estree/entities.v
node tests/estree/corpus.mjs "$PWD" "$OUT/corpus" > /dev/null
"$V" -prod -cc gcc -o "$OUT/estree_dump" tests/estree/main.v
"$V" test estree/
for ((i = 0; i < JOBS; i++)); do
	node tests/estree/oracle.mjs hash "$OUT/corpus/list.txt" "$i/$JOBS" > "$OUT/oracle.$i.tsv" &
done
wait
cat "$OUT"/oracle.*.tsv | LC_ALL=C sort > "$OUT/oracle.tsv"
{ grep -v '^#' tests/estree/known.txt || true; } | cut -f1 | LC_ALL=C sort > "$OUT/known.tree-sitter.rel"
: > "$OUT/known.typescript.rel"
status=0
for parser in tree-sitter typescript; do
	for ((i = 0; i < JOBS; i++)); do
		VESLINT_PARSER=$parser "$OUT/estree_dump" hash "$OUT/corpus/list.txt" "$i/$JOBS" > "$OUT/shard.$i.tsv" &
	done
	wait
	cat "$OUT"/shard.*.tsv | LC_ALL=C sort > "$OUT/v.$parser.tsv"
	rm -f "$OUT"/shard.*.tsv
	python3 tests/estree/compare.py "$OUT/oracle.tsv" "$OUT/v.$parser.tsv" "$OUT/corpus" "$OUT/mismatch.$parser.txt"
	# The differences, as paths relative to the corpus directory, against the known ones.
	{ sed -e "s|^$PWD/$OUT/corpus/||" -e "s|^$OUT/corpus/||" -e "s|^$PWD/||" "$OUT/mismatch.$parser.txt" | grep -v '^$' || true; } |
		LC_ALL=C sort > "$OUT/mismatch.$parser.rel"
	if diff "$OUT/known.$parser.rel" "$OUT/mismatch.$parser.rel"; then
		echo "estree ($parser's rows): as typescript-estree but the $(wc -l < "$OUT/known.$parser.rel") known differences"
	else
		echo "estree ($parser's rows): unexpected differences (< known, > now)"
		status=1
	fi
done
exit $status
