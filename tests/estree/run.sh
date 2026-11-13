#!/usr/bin/env bash
# Differential test of estree/ (the ESTree of typescript-estree 8.62.0, built from tree-sitter's
# tree) against typescript-estree itself: for every file of the corpus (the fixtures of
# tests/rules and tests/scope, the code of every case of the upstream.json files and the sources
# of the projects of build/eval), the canonical serialization of the tree and the order of its
# traversal must be the same, byte for byte, or both must fail to parse. It also checks that
# estree/tables.v and estree/entities.v are what their generators make, and runs estree's unit
# tests. The files tests/estree/known.txt lists are expected to differ (the reason is there).
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
	"$OUT/estree_dump" hash "$OUT/corpus/list.txt" "$i/$JOBS" > "$OUT/v.$i.tsv" &
done
wait
cat "$OUT"/oracle.*.tsv | LC_ALL=C sort > "$OUT/oracle.tsv"
cat "$OUT"/v.*.tsv | LC_ALL=C sort > "$OUT/v.tsv"
python3 tests/estree/compare.py "$OUT/oracle.tsv" "$OUT/v.tsv" "$OUT/corpus" "$OUT/mismatch.txt"
# The differences, as paths relative to the corpus directory, against known.txt.
{ sed -e "s|^$PWD/$OUT/corpus/||" -e "s|^$OUT/corpus/||" -e "s|^$PWD/||" "$OUT/mismatch.txt" | grep -v '^$' || true; } |
	LC_ALL=C sort > "$OUT/mismatch.rel"
grep -v '^#' tests/estree/known.txt | cut -f1 | LC_ALL=C sort > "$OUT/known.rel"
if diff "$OUT/known.rel" "$OUT/mismatch.rel"; then
	echo "estree: as typescript-estree but the $(wc -l < "$OUT/known.rel") known differences"
else
	echo "estree: unexpected differences (< known, > now)"
	exit 1
fi
