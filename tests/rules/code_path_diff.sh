#!/usr/bin/env bash
# Compares veslint's code path analysis (rules/code_path.v) with ESLint 10.6.0's on generated
# functions (tools/gen_code_path_cases.py): `consistent-return` reports a function whose end is
# reachable, so both tools must report the same functions. The cases are every small nesting of
# `try` statements, `try` statements inside loops and labeled blocks, and random functions.
# Like reference.sh, it needs the dependencies tests/eval_spider_byte.sh installs.
set -uo pipefail
cd "$(dirname "$0")/../.."
NM=build/eval/spider-byte/node_modules
[[ -d $NM/typescript-eslint ]] || { echo "build/eval dependencies are missing: run tests/eval_spider_byte.sh"; exit 2; }
# The reference config enables the rule on **/@typescript-eslint/consistent-return/**/cases.ts.
DIR=build/code-path-diff/@typescript-eslint/consistent-return
mkdir -p "$DIR"
cp tests/rules/@typescript-eslint/consistent-return/tsconfig.json "$DIR/"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail=0
check() { # label, generator arguments...
	local label=$1
	shift
	python3 -I tools/gen_code_path_cases.py "$@" > "$DIR/cases.ts"
	node "$NM/eslint/bin/eslint.js" --config tests/rules/eslint.reference.config.mjs --format json \
		"$DIR/cases.ts" 2> "$TMP/eslint.err" | python3 tests/eslint_lines.py | sort > "$TMP/eslint.txt"
	./veslint --rule @typescript-eslint/consistent-return "$DIR/cases.ts" 2> /dev/null | sort > "$TMP/veslint.txt"
	local functions
	functions=$(grep -c '^export function' "$DIR/cases.ts")
	if [[ ! -s $TMP/eslint.txt ]]; then
		echo "FAIL   $label: ESLint gave no findings"
		head -5 "$TMP/eslint.err"
		fail=1
	elif diff -u "$TMP/eslint.txt" "$TMP/veslint.txt" > "$TMP/diff.txt"; then
		echo "ok     $label: $functions functions, $(wc -l < "$TMP/eslint.txt") with a reachable end in both"
	else
		echo "FAIL   $label: $(grep -c '^[-+]tests\|^[-+]build' "$TMP/diff.txt") differences"
		head -20 "$TMP/diff.txt"
		fail=1
	fi
}
for part in 0 1 2; do
	check "two try statements, the inner one in block $part of the outer" try "$part"
done
for kind in while whiletrue label; do
	check "a try statement in $kind" loop "$kind"
done
for seed in 1 2 3; do
	check "random functions, seed $seed" random "$seed" 400 0
	check "random functions that end their blocks, seed $seed" random "$seed" 400 0.8
done
exit $fail
