#!/usr/bin/env bash
# Validates tests/rules/<rule>/expected.txt (the exact output of veslint) against the reference
# implementation, typescript-eslint 8.62.0 (and @slipher/eslint-plugin 1.1.0 for the `seyfert/*`
# rules): its findings on each cases.ts or cases.tsx (position, rule, messageId and full message
# text) must be the expected ones plus those listed in limitations.txt (cases the reference reports
# and veslint does not, documented in the README). Where a rule has a fixes.txt (the output of
# veslint with --fixes), its lines must be the reference's findings with the fix and the
# suggestions of each one (range in UTF-16 units and text).
# Needs the build/eval dependencies, installed by tests/eval_spider_byte.sh, and build/upstream/seyfert
# (tests/upstream/README.md), which tests/rules/seyfert/setup.sh links next to the seyfert fixtures.
set -uo pipefail
cd "$(dirname "$0")/../.."
NM=build/eval/spider-byte/node_modules
[[ -d $NM/typescript-eslint ]] || { echo "build/eval dependencies are missing: run tests/eval_spider_byte.sh"; exit 2; }
tests/rules/seyfert/setup.sh || exit 2
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
reference_of() { # files...: adds ESLint's lines on the files to reference.txt and reference.fixes.txt
	node "$NM/eslint/bin/eslint.js" --config tests/rules/eslint.reference.config.mjs --format json \
		"$@" > "$TMP/eslint.json" 2> "$TMP/eslint.err"
	if [[ ! -s "$TMP/eslint.json" ]]; then
		echo "FAIL   ESLint produced no results"
		cat "$TMP/eslint.err"
		exit 1
	fi
	python3 tests/eslint_lines.py < "$TMP/eslint.json" >> "$TMP/reference.txt"
	python3 tests/eslint_lines.py fixes < "$TMP/eslint.json" >> "$TMP/reference.fixes.txt"
}
# One ESLint process for the fixtures of the typescript-eslint rules, one for those of ESLint core
# and one for those of the seyfert/* rules. In a single process with more of them, V8 (Node
# 26.13.0) stops matching an alternation in a regexp modifier group with the `u` flag at some point
# of the run: `/^(?i:get|set)\p{Lu}/u` of naming-convention's regex fixture no longer matches
# `SetÉtat`, which it matches in a new process (and in veslint).
mapfile -t cases < <(find tests/rules -name cases.ts -o -name cases.tsx | sort)
mapfile -t seyfert_cases < <(printf '%s\n' "${cases[@]}" | grep '^tests/rules/seyfert/')
mapfile -t ts_cases < <(printf '%s\n' "${cases[@]}" | grep '^tests/rules/@typescript-eslint/')
mapfile -t core_cases < <(printf '%s\n' "${cases[@]}" | grep -v '^tests/rules/seyfert/\|^tests/rules/@typescript-eslint/')
: > "$TMP/reference.txt"
: > "$TMP/reference.fixes.txt"
reference_of "${ts_cases[@]}"
[[ ${#core_cases[@]} -eq 0 ]] || reference_of "${core_cases[@]}"
[[ ${#seyfert_cases[@]} -eq 0 ]] || reference_of "${seyfert_cases[@]}"
fail=0
# A rule's directory is tests/rules/<rule id>, the one with an expected.txt.
mapfile -t rule_dirs < <(find tests/rules -name expected.txt | sed 's|/expected\.txt$||' | sort)
for dir in "${rule_dirs[@]}"; do
	rule=${dir#tests/rules/}
	grep -P "^tests/rules/${rule}/(.+/)?cases\.tsx?:.*\t${rule}\t" "$TMP/reference.txt" | sort > "$TMP/ref.txt"
	cat "$dir/expected.txt" "$dir/limitations.txt" 2> /dev/null | sort > "$TMP/expected.txt"
	known=$(cat "$dir/limitations.txt" 2> /dev/null | wc -l)
	if diff -u "$TMP/ref.txt" "$TMP/expected.txt" > "$TMP/diff.txt"; then
		echo "ok     $rule: $(wc -l < "$TMP/ref.txt") ESLint findings ($known known limitations)"
	else
		echo "FAIL   $rule: expected.txt + limitations.txt do not match ESLint"
		cat "$TMP/diff.txt"
		fail=1
	fi
	if [[ -f $dir/fixes.txt ]]; then
		grep -P "^tests/rules/${rule}/(.+/)?cases\.tsx?:.*\t${rule}\t" "$TMP/reference.fixes.txt" | sort > "$TMP/ref.txt"
		# fixes.known.txt: where veslint fixes on purpose otherwise than the reference, pairs of
		# lines `eslint<TAB><its line>` and `veslint<TAB><veslint's line>` (documented in the README).
		if [[ -f $dir/fixes.known.txt ]]; then
			python3 - "$dir/fixes.known.txt" "$TMP/ref.txt" <<'PY'
import sys
pairs = [line.rstrip('\n') for line in open(sys.argv[1], encoding='utf-8') if line.strip() and not line.startswith('#')]
swap = {}
for eslint, veslint in zip(pairs[0::2], pairs[1::2]):
    assert eslint.startswith('eslint\t') and veslint.startswith('veslint\t'), (eslint, veslint)
    swap[eslint[len('eslint\t'):]] = veslint[len('veslint\t'):]
lines = open(sys.argv[2], encoding='utf-8').read().splitlines()
missing = [k for k in swap if k not in lines]
if missing:
    sys.exit(f'fixes.known.txt: the reference no longer gives {missing}')
open(sys.argv[2], 'w', encoding='utf-8').write(''.join(swap.get(line, line) + '\n' for line in lines))
PY
			sort "$TMP/ref.txt" -o "$TMP/ref.txt"
		fi
		if sort "$dir/fixes.txt" | diff -u "$TMP/ref.txt" - > "$TMP/diff.txt"; then
			echo "ok     $rule: fixes and suggestions of $(grep -cP '\t(fix|suggestion)\t' "$TMP/ref.txt") findings"
		else
			echo "FAIL   $rule: fixes.txt does not match ESLint"
			cat "$TMP/diff.txt"
			fail=1
		fi
	fi
done
# tests/directives: the comments that configure ESLint, with the rules of its rules.json in both
# tools (which directive comments are unused depends on the rules that run).
mapfile -t directive_files < <(find tests/directives -name '*.ts' | sort)
node "$NM/eslint/bin/eslint.js" --config tests/directives/eslint.config.mjs --format json \
	"${directive_files[@]}" > "$TMP/directives.json" 2> "$TMP/directives.err"
if [[ -s "$TMP/directives.json" ]] && python3 tests/eslint_lines.py fixes < "$TMP/directives.json" | sort > "$TMP/ref.txt" &&
	sort tests/directives/expected.txt | diff -u "$TMP/ref.txt" - > "$TMP/diff.txt"; then
	echo "ok     directives: $(wc -l < "$TMP/ref.txt") ESLint messages"
else
	echo "FAIL   tests/directives/expected.txt does not match ESLint"
	cat "$TMP/diff.txt" "$TMP/directives.err"
	fail=1
fi
# tests/fix: the text `eslint --fix` leaves (expected/) and the messages that remain.
node "$NM/eslint/bin/eslint.js" --config tests/fix/eslint.config.mjs --fix-dry-run --format json \
	tests/fix/cases.ts > "$TMP/fix.json" 2> "$TMP/fix.err"
if [[ -s "$TMP/fix.json" ]] && python3 -c '
import json, re, sys
result = json.load(open(sys.argv[1]))[0]
# A surrogate without its pair is U+FFFD in the file Node writes.
output = re.sub("[\ud800-\udfff]", "\ufffd", result.get("output") or "")
sys.exit(0 if output == open(sys.argv[2], encoding="utf-8").read() else 1)
' "$TMP/fix.json" tests/fix/expected/cases.ts &&
	(cd tests/fix && python3 ../eslint_lines.py fixes < "$TMP/fix.json") | sort > "$TMP/ref.txt" &&
	sort tests/fix/expected.txt | diff -u "$TMP/ref.txt" - > "$TMP/diff.txt"; then
	echo "ok     fix: the fixed text and $(wc -l < "$TMP/ref.txt") remaining ESLint messages"
else
	echo "FAIL   tests/fix does not match eslint --fix"
	cat "$TMP/diff.txt" "$TMP/fix.err"
	fail=1
fi
# tests/config: ESLint reading eslint.config.mjs (ignores, rules per folder, linterOptions), from
# that directory.
(cd tests/config && node "../../$NM/eslint/bin/eslint.js" --config eslint.config.mjs --format json \
	$(find . -name '*.ts' | sed 's|^\./||' | sort)) > "$TMP/config.json" 2> "$TMP/config.err"
if [[ -s "$TMP/config.json" ]] && (cd tests/config && python3 ../eslint_lines.py fixes < "$TMP/config.json") | sort > "$TMP/ref.txt" &&
	sort tests/config/expected.txt | diff -u "$TMP/ref.txt" - > "$TMP/diff.txt"; then
	echo "ok     config: $(wc -l < "$TMP/ref.txt") ESLint messages"
else
	echo "FAIL   tests/config/expected.txt does not match ESLint"
	cat "$TMP/diff.txt" "$TMP/config.err"
	fail=1
fi
# The print-config.json of two folders of tests/config is what `eslint --print-config` prints for
# their files, with <tests/config> in the place of the directory.
for folder in unused-inline neighbours; do
	if (cd tests/config && node "../../$NM/eslint/bin/eslint.js" --config eslint.config.mjs --print-config "$folder/a.ts") 2> "$TMP/print-config.err" |
		sed "s|$PWD/tests/config|<tests/config>|" | diff -u - "tests/config/$folder/print-config.json" > "$TMP/diff.txt"; then
		echo "ok     config: the output of --print-config for $folder"
	else
		echo "FAIL   tests/config/$folder/print-config.json is not what eslint --print-config prints"
		cat "$TMP/diff.txt" "$TMP/print-config.err"
		fail=1
	fi
done
# tests/config-errors: configurations ESLint does not take. The eslint command ends with code 2 and
# prints, for the rules of each JSON file, the text of the .txt next to it.
for json in tests/config-errors/*.json; do
	[[ $(basename "$json") == tsconfig.json ]] && continue
	code=0
	RULES=$(basename "$json") node "$NM/eslint/bin/eslint.js" --config tests/config-errors/eslint.config.mjs \
		tests/config-errors/cases.ts > /dev/null 2> "$TMP/config-error.err" || code=$?
	if [[ $code -eq 2 ]] && python3 tests/eslint_error.py < "$TMP/config-error.err" | diff -u - "${json%.json}.txt" > "$TMP/diff.txt"; then
		echo "ok     config-errors: $(basename "$json")"
	else
		echo "FAIL   ${json%.json}.txt is not what ESLint prints (code $code)"
		cat "$TMP/diff.txt"
		fail=1
	fi
done
# Any other message (parse errors, a rule in another rule's file) is a failure.
if grep -vP "^tests/rules/((?:@[^/]+/|seyfert/)?[^/]+)/(?:.+/)?cases\.tsx?:[0-9]+:[0-9]+\t\1\t" "$TMP/reference.txt" > "$TMP/others.txt"; then
	echo "FAIL   unexpected ESLint messages:"
	cat "$TMP/others.txt"
	fail=1
fi
# typescript-eslint's own tests of the ported rules (tests/upstream/README.md): ESLint gives what
# each test expects, but the cases tests/upstream/known.txt lists for it, so the fixtures reproduce
# typescript-eslint's own run; and on every case veslint prints, line for line and in the same
# order, what ESLint gives, but the cases known.txt lists.
# Each plugin with its fixtures: typescript-eslint's (tests/upstream/setup.sh) and
# @slipher/eslint-plugin's (tests/upstream/seyfert/setup.sh).
upstream_tests() { # label setup plugin-directory
	local label=$1 setup=$2 dir=$3 rules
	local fixtures="$TMP/upstream-$dir"
	if ! "$setup" "$fixtures" 2> "$TMP/upstream-setup.err"; then
		echo "FAIL   $label: $(cat "$TMP/upstream-setup.err")"
		fail=1
		return
	fi
	if [[ $dir == core ]]; then
		# ESLint core: tests/rules/<rule>/upstream.json, one level down.
		mapfile -t rules < <(find tests/rules -mindepth 2 -maxdepth 2 -name upstream.json | sed -E 's|^tests/rules/(.*)/upstream\.json$|\1|' | sort)
	else
		mapfile -t rules < <(find "tests/rules/$dir" -name upstream.json | sed -E 's|^tests/rules/(.*)/upstream\.json$|\1|' | sort)
	fi
	[[ ${#rules[@]} -gt 0 ]] || return 0
	if node tests/rules/upstream_eslint.mjs "$fixtures" "$TMP/upstream-eslint-$dir" "${rules[@]}" > "$TMP/upstream-eslint.out" 2>&1; then
		echo "ok     $label: ESLint gives what they expect in the ${#rules[@]} rules (known.txt aside)"
	else
		echo "FAIL   $label: ESLint does not give what they expect"
		grep -v '^ok' "$TMP/upstream-eslint.out"
		fail=1
	fi
	# Its own verdict is the one of tests/run.sh; here only its lines matter.
	python3 tests/upstream_check.py ./veslint "$fixtures" "$TMP/upstream-configs-$dir" --lines "$TMP/upstream-veslint-$dir.txt" \
		"${rules[@]}" > /dev/null 2>&1
	if python3 tests/upstream_compare.py "$TMP/upstream-eslint-$dir" "$TMP/upstream-veslint-$dir.txt" "${rules[@]}" > "$TMP/upstream-compare.out"; then
		echo "ok     $label: $(tail -1 "$TMP/upstream-compare.out")"
	else
		echo "FAIL   $label: veslint does not print what ESLint gives"
		cat "$TMP/upstream-compare.out"
		fail=1
	fi
}
upstream_tests "upstream tests" tests/upstream/setup.sh @typescript-eslint
upstream_tests "@slipher/eslint-plugin's tests" tests/upstream/seyfert/setup.sh seyfert
# ESLint's own tests of its core rules, linted as TypeScript in typescript-eslint's fixtures.
upstream_tests "ESLint's tests" tests/upstream/setup.sh core
exit $fail
