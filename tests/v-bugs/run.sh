#!/usr/bin/env bash
# Runs every V bug repro of tests/v-bugs/ and tells, per repro, whether the bug is FIXED or still
# there (BUG). See docs/v-bugs.md.
#
# Usage: tests/v-bugs/run.sh [path/to/v]   (default: $V, then `v`)
#
# Each NN-slug/ has a main.v whose `// expected: <line>` comments are the output of a fixed V (whole
# lines, in order) and whose `// expected-error: <text>` comments must appear in the output (for
# repros that must fail to compile or panic), a CMD file (`run`, `gcc` or `globals`) and, optionally,
# a prep.sh that creates other files. Each repro runs in a temporary copy, so nothing is written
# here. V_C_ERROR_BUG_REPORT_DISABLED=1 keeps V from sending reports to bugs.vlang.io, and
# V_MACOS_V3_NO_FALLBACK=1 keeps the stable compiler from retrying, and hiding, a V3 failure.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
vbin=${1:-${V:-v}}
fixed=0
bugs=0
for dir in "$here"/*/; do
	[[ -f "$dir/main.v" ]] || continue
	name=$(basename "$dir")
	tmp=$(mktemp -d)
	cp -r "$dir/." "$tmp/"
	if [[ -f "$tmp/prep.sh" ]]; then
		(cd "$tmp" && sh prep.sh) > /dev/null 2>&1
	fi
	flags=()
	case $(tr -d '[:space:]' < "$dir/CMD") in
	gcc) flags=(-cc gcc) ;;
	globals) flags=(-enable-globals) ;;
	esac
	out=$(cd "$tmp" && env V_C_ERROR_BUG_REPORT_DISABLED=1 V_MACOS_V3_NO_FALLBACK=1 LANG=C LC_ALL=C \
		timeout 300 "$vbin" "${flags[@]}" run main.v 2>&1)
	rm -rf "$tmp"
	# Without the source lines V quotes around a diagnostic (`  12 | ...`, `     | ^~~`): they can
	# contain the `// expected` comments themselves.
	out=$(grep -vE '^[[:space:]]*([0-9]+ )?\|' <<< "$out")
	ok=1
	while IFS= read -r want; do
		grep -qF -- "$want" <<< "$out" || ok=0
	done < <(sed -n 's|^// expected-error: ||p' "$dir/main.v")
	want_lines=$(sed -n 's|^// expected: ||p' "$dir/main.v")
	if [[ -n "$want_lines" ]]; then
		got_lines=$(grep -Fx -f <(printf '%s\n' "$want_lines") <<< "$out")
		[[ "$got_lines" == "$want_lines" ]] || ok=0
	fi
	if [[ $ok -eq 1 ]]; then
		fixed=$((fixed + 1))
		echo "FIXED  $name"
	else
		bugs=$((bugs + 1))
		echo "BUG    $name: $(grep -v '^\s*$' <<< "$out" | head -2 | tr '\n' ' ' | cut -c1-200)"
	fi
done
echo "$fixed fixed, $bugs still failing ($("$vbin" version 2>/dev/null))"
