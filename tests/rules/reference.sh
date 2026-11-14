#!/usr/bin/env bash
# Validates tests/rules/<rule>/expected.txt (the exact output of veslint) against the reference
# implementation, typescript-eslint 8.62.0 (and @slipher/eslint-plugin 1.1.0 for the `seyfert/*`
# rules): its findings on each cases.ts or cases.tsx (position, rule, messageId and full message
# text) must be the expected ones plus those listed in limitations.txt (cases the reference reports
# and veslint does not, documented in internals.md). Where a rule has a fixes.txt (the output of
# veslint with --fixes), its lines must be the reference's findings with the fix and the
# suggestions of each one (range in UTF-16 units and text) and where it ends (endLine, endColumn).
# Needs the build/eval dependencies, installed by tests/eval_spider_byte.sh, and build/upstream/seyfert
# (tests/upstream/README.md), which tests/rules/seyfert/setup.sh links next to the seyfert fixtures.
# ESLint and veslint run JOBS processes at a time (the CPUs by default), as in tests/run.sh.
set -uo pipefail
cd "$(dirname "$0")/../.."
NM=build/eval/spider-byte/node_modules
[[ -d $NM/typescript-eslint ]] || { echo "build/eval dependencies are missing: run tests/eval_spider_byte.sh"; exit 2; }
tests/rules/seyfert/setup.sh || exit 2
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
JOBS=${JOBS:-$(nproc 2> /dev/null || echo 2)}
[[ $JOBS -ge 1 ]] || JOBS=1
# throttle waits until fewer than JOBS background jobs run.
throttle() {
	while [[ $(jobs -rp | wc -l) -ge $JOBS ]]; do
		wait -n
	done
}
reference_of() { # tag files...: ESLint's lines on the files, in reference.<tag>.txt and reference.<tag>.fixes.txt
	local tag=$1
	shift
	node "$NM/eslint/bin/eslint.js" --config tests/rules/eslint.reference.config.mjs --format json \
		"$@" > "$TMP/eslint.$tag.json" 2> "$TMP/eslint.$tag.err"
	if [[ ! -s "$TMP/eslint.$tag.json" ]]; then
		{ echo "FAIL   ESLint produced no results"; cat "$TMP/eslint.$tag.err"; } > "$TMP/eslint.$tag.failed"
		return
	fi
	python3 tests/eslint_lines.py < "$TMP/eslint.$tag.json" > "$TMP/reference.$tag.txt"
	python3 tests/eslint_lines.py fixes < "$TMP/eslint.$tag.json" > "$TMP/reference.$tag.fixes.txt"
}
reference_in_groups() { # tag files...: reference_of on JOBS groups of consecutive files, in the background
	local tag=$1
	shift
	local files=("$@") size k
	[[ ${#files[@]} -gt 0 ]] || return 0
	size=$(((${#files[@]} + JOBS - 1) / JOBS))
	for ((k = 0; k * size < ${#files[@]}; k++)); do
		throttle
		reference_of "$tag.$k" "${files[@]:k*size:size}" &
	done
}
# ESLint processes for the fixtures of the typescript-eslint rules, others for those of ESLint core
# and others for those of the seyfert/* rules, each with a group of consecutive files (the fixtures
# of a rule, with their tsconfig.json, stay together). In a single process with more of them, V8 (Node
# 26.13.0) stops matching an alternation in a regexp modifier group with the `u` flag at some point
# of the run: `/^(?i:get|set)\p{Lu}/u` of naming-convention's regex fixture no longer matches
# `SetÉtat`, which it matches in a new process (and in veslint).
mapfile -t cases < <(find tests/rules -name cases.ts -o -name cases.tsx | sort)
mapfile -t seyfert_cases < <(printf '%s\n' "${cases[@]}" | grep '^tests/rules/seyfert/')
mapfile -t ts_cases < <(printf '%s\n' "${cases[@]}" | grep '^tests/rules/@typescript-eslint/')
mapfile -t core_cases < <(printf '%s\n' "${cases[@]}" | grep -v '^tests/rules/seyfert/\|^tests/rules/@typescript-eslint/')
reference_in_groups ts "${ts_cases[@]}"
reference_in_groups core "${core_cases[@]}"
reference_in_groups seyfert "${seyfert_cases[@]}"
wait
if compgen -G "$TMP/eslint.*.failed" > /dev/null; then
	cat "$TMP"/eslint.*.failed
	exit 1
fi
find "$TMP" -maxdepth 1 -name 'reference.*.txt' ! -name '*.fixes.txt' -exec cat {} + > "$TMP/reference.all"
find "$TMP" -maxdepth 1 -name 'reference.*.fixes.txt' -exec cat {} + > "$TMP/reference.fixes.all"
mv "$TMP/reference.all" "$TMP/reference.txt"
mv "$TMP/reference.fixes.all" "$TMP/reference.fixes.txt"
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
		# lines `eslint<TAB><its line>` and `veslint<TAB><veslint's line>` (documented in internals.md).
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
if grep -vP "^tests/rules/((?:@[^/]+/|seyfert/|unicorn/)?[^/]+)/(?:.+/)?cases\.tsx?:[0-9]+:[0-9]+\t\1\t" "$TMP/reference.txt" > "$TMP/others.txt"; then
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
	local label=$1 setup=$2 dir=$3 rules group
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
	# JOBS groups of rules, the rules dealt in turn (the big ones fall in different groups).
	local groups=$JOBS k index pids=() codes=0
	[[ $groups -le ${#rules[@]} ]] || groups=${#rules[@]}
	local -a group_of
	for ((k = 0; k < groups; k++)); do
		group_of[k]=''
		for index in "${!rules[@]}"; do
			[[ $((index % groups)) -eq $k ]] && group_of[k]+="${rules[index]}"$'\n'
		done
	done
	for ((k = 0; k < groups; k++)); do
		mapfile -t group <<< "${group_of[k]%$'\n'}"
		node tests/rules/upstream_eslint.mjs "$fixtures" "$TMP/upstream-eslint-$dir" "${group[@]}" > "$TMP/upstream-eslint.$k.out" 2>&1 &
		pids+=($!)
	done
	for k in "${!pids[@]}"; do
		wait "${pids[k]}" || codes=1
	done
	if [[ $codes -eq 0 ]]; then
		echo "ok     $label: ESLint gives what they expect in the ${#rules[@]} rules (known.txt aside)"
	else
		echo "FAIL   $label: ESLint does not give what they expect"
		for ((k = 0; k < groups; k++)); do
			grep -v '^ok' "$TMP/upstream-eslint.$k.out"
		done
		fail=1
	fi
	# Its own verdict is the one of tests/run.sh; here only its lines matter.
	pids=()
	for ((k = 0; k < groups; k++)); do
		mapfile -t group <<< "${group_of[k]%$'\n'}"
		python3 tests/upstream_check.py ./veslint "$fixtures" "$TMP/upstream-configs-$dir.$k" \
			--lines "$TMP/upstream-veslint-$dir.$k.txt" "${group[@]}" > /dev/null 2>&1 &
		pids+=($!)
	done
	for k in "${!pids[@]}"; do
		wait "${pids[k]}"
	done
	for ((k = 0; k < groups; k++)); do
		cat "$TMP/upstream-veslint-$dir.$k.txt"
	done > "$TMP/upstream-veslint-$dir.txt"
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
# eslint-plugin-unicorn's tests, the same way.
upstream_tests "eslint-plugin-unicorn's tests" tests/upstream/setup.sh unicorn
exit $fail
