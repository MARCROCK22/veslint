#!/usr/bin/env bash
# Differential test of regexpp/ (the V port of @eslint-community/regexpp 4.12.2) against the
# package itself: for every input (the patterns and flags of the tests of ESLint's nine rules about
# regular expressions, and three seeded sets of generated patterns, each under ecmaVersion 5 to
# 2025, the flags none/u/v/uv, `strict`, offsets inside a larger source and literals), the result
# of validatePattern (or its message and index), the validator's onCharacter/onPatternEnter
# events and the whole AST of parsePattern must be the same, byte for byte. It also checks that
# regexpp/tables.v is what tools/gen_regexpp_tables.mjs makes, and runs regexpp's unit tests.
# Dev-time only (about 2.5 minutes): it needs the node_modules of tests/eval_spider_byte.sh and
# the sparse clone of ESLint in build/upstream/eslint (tests/upstream/README.md).
#
# Usage: tests/regexpp/run.sh   (V: the v binary, default `v`)
set -euo pipefail
cd "$(dirname "$0")/../.."
export V_C_ERROR_BUG_REPORT_DISABLED=1 V_MACOS_V3_NO_FALLBACK=1
V=${V:-v}
REGEXPP=build/eval/spider-byte/node_modules/@eslint-community/regexpp/index.js
OUT=build/regexpp-oracle
mkdir -p "$OUT"
node tools/gen_regexpp_tables.mjs "$REGEXPP" "$OUT/tables.v"
"$V" fmt -w "$OUT/tables.v" > /dev/null
cmp "$OUT/tables.v" regexpp/tables.v
node tests/regexpp/extract.cjs "$OUT/corpus.json"
echo '{"patterns":[],"flags":[]}' > "$OUT/empty.json"
node tests/regexpp/cases.mjs "$OUT/corpus.json" 6000 12345 "$OUT/cases1.txt"
node tests/regexpp/cases.mjs "$OUT/empty.json" 12000 777 "$OUT/cases2.txt"
node tests/regexpp/cases.mjs "$OUT/empty.json" 12000 4242 "$OUT/cases3.txt" classes
"$V" -W -prod -o "$OUT/difftest" tests/regexpp/main.v
"$V" test regexpp/
status=0
for i in 1 2 3; do
	node tests/regexpp/oracle.cjs "$OUT/cases$i.txt" "$OUT/node$i.txt" &
	"$OUT/difftest" "$OUT/cases$i.txt" "$OUT/v$i.txt" &
	wait
	n=$(wc -l < "$OUT/cases$i.txt")
	if cmp -s "$OUT/node$i.txt" "$OUT/v$i.txt"; then
		echo "set $i: $n inputs, 100% identical"
	else
		echo "set $i: MISMATCH"
		cmp "$OUT/node$i.txt" "$OUT/v$i.txt" || true
		status=1
	fi
	rm -f "$OUT/node$i.txt" "$OUT/v$i.txt"
done
exit $status
