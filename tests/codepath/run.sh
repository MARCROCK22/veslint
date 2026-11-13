#!/usr/bin/env bash
# Differential test of codepath/ (the V port of ESLint 10.6.0's code path analysis, on the ESTree
# of estree/) against ESLint itself: for every file of the corpus of tests/estree/run.sh, every
# call ESLint makes to the listeners of a rule (`*`, `*:exit` and the seven code path events, with
# the ids of the code paths and segments and the final state of each segment), in its order,
# must be the same, or both must fail to parse. It also runs codepath's unit tests. The files
# tests/codepath/known.txt lists are expected to differ (the reason is there). Dev-time only: it
# needs the node_modules of tests/eval_spider_byte.sh.
#
# Usage: tests/codepath/run.sh   (V: the v binary, default `v`; JOBS: processes, default nproc)
set -euo pipefail
cd "$(dirname "$0")/../.."
export V_C_ERROR_BUG_REPORT_DISABLED=1 V_MACOS_V3_NO_FALLBACK=1
V=${V:-v}
OUT=build/codepath-oracle
JOBS=${JOBS:-$(nproc)}
mkdir -p "$OUT"
node tests/estree/corpus.mjs "$PWD" "$OUT/corpus" > /dev/null
"$V" -prod -cc gcc -o "$OUT/codepath_dump" tests/codepath/main.v
"$V" test codepath/
for ((i = 0; i < JOBS; i++)); do
	node --max-old-space-size=4096 tests/codepath/oracle.mjs hash "$OUT/corpus/list.txt" "$i/$JOBS" > "$OUT/oracle.$i.tsv" &
	"$OUT/codepath_dump" hash "$OUT/corpus/list.txt" "$i/$JOBS" > "$OUT/v.$i.tsv" &
done
wait
cat "$OUT"/oracle.*.tsv | LC_ALL=C sort > "$OUT/oracle.tsv"
cat "$OUT"/v.*.tsv | LC_ALL=C sort > "$OUT/v.tsv"
python3 tests/estree/compare.py "$OUT/oracle.tsv" "$OUT/v.tsv" "$OUT/corpus" "$OUT/mismatch.txt"
# The differences, as paths relative to the corpus directory, against known.txt.
{ sed -e "s|^$PWD/$OUT/corpus/||" -e "s|^$OUT/corpus/||" -e "s|^$PWD/||" "$OUT/mismatch.txt" | grep -v '^$' || true; } |
	LC_ALL=C sort > "$OUT/mismatch.rel"
grep -v '^#' tests/codepath/known.txt | cut -f1 | LC_ALL=C sort > "$OUT/known.rel"
if diff "$OUT/known.rel" "$OUT/mismatch.rel"; then
	echo "codepath: as ESLint but the $(wc -l < "$OUT/known.rel") known differences"
else
	echo "codepath: unexpected differences (< known, > now)"
	exit 1
fi
