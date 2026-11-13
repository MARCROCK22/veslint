#!/usr/bin/env bash
# veslint integration tests (PROMPT.md §5, §7 and §9). Run with `make test`.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
V=${V:-v}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0
# On Windows (Git Bash or MSYS2) the binary is veslint.exe and some tests run another way or are
# skipped; see internals.md, "Windows".
windows=0
case $(uname -s) in MINGW* | MSYS* | CYGWIN*) windows=1 ;; esac
exe=''
[[ $windows -eq 0 ]] || exe=.exe
# Lists of files go in the byte order of their names, the same everywhere (the expected outputs
# follow it).
sorted() {
	LC_ALL=C sort "$@"
}

ok() {
	echo "ok     $1"
	pass=$((pass + 1))
}

ko() {
	echo "FAIL   $1"
	fail=$((fail + 1))
}

# The slow checks (each rule on its fixtures, each rule on every fixture, the upstream tests) run
# JOBS at a time (the CPUs by default), each with its veslint and its tsgo; their lines are printed
# in the order of a serial run.
JOBS=${JOBS:-$(nproc 2> /dev/null || echo 2)}
[[ $JOBS -ge 1 ]] || JOBS=1
# throttle waits until fewer than JOBS background jobs run.
throttle() {
	while [[ $(jobs -rp | wc -l) -ge $JOBS ]]; do
		wait -n
	done
}
# report prints the lines a job wrote to its log and counts its `ok` and `FAIL` lines.
report() { # log
	cat "$1"
	pass=$((pass + $(grep -c '^ok     ' "$1")))
	fail=$((fail + $(grep -c '^FAIL   ' "$1")))
}

# 1. Exact outputs: app.ts (§5), each fixture (§7) and the --all-identifiers and
#    --per-identifier modes; the latter must give exactly the same output as the batch.
expect_output() { # expected file [options...]
	local name=$1 file=$2
	shift 2
	local label="$file${*:+ $*}"
	if ./veslint "$@" "$file" > "$TMP/$name.out" 2> "$TMP/$name.err" &&
		diff -u "tests/expected/$name.txt" "$TMP/$name.out"; then
		ok "output of $label"
	else
		ko "output of $label"
		cat "$TMP/$name.err"
	fi
}

expect_output app app.ts
expect_output app app.ts --per-identifier
expect_output app_all app.ts --all-identifiers
expect_output app_all app.ts --all-identifiers --per-identifier
for f in tests/fixtures/*.ts; do
	expect_output "$(basename "$f" .ts)" "$f"
done
# A line also ends at U+2028, at U+2029 and at a lone CR, as tsc counts them: for every identifier.
expect_output line_breaks_all tests/fixtures/line_breaks.ts --all-identifiers
if grep -q 'syntax errors' "$TMP/syntax_error.err"; then
	ok "syntax error warning in syntax_error.ts"
else
	ko "syntax error warning in syntax_error.ts"
fi

# --version gives the version of the release, which is also the extension's.
extension_version=$(sed -n 's/^  "version": "\(.*\)",$/\1/p' editors/vscode/package.json)
if [[ $(./veslint --version) == "veslint $extension_version" ]]; then
	ok "--version: veslint $extension_version, as the extension"
else
	ko "--version: $(./veslint --version), the extension is $extension_version"
fi

# The README lists every rule veslint has (the list `--rule` gives with an unknown rule).
mapfile -t ported < <(./veslint --rule no-such-rule app.ts 2>&1 | sed -n 's/.*(available: \(.*\))$/\1/p' | tr ',' '\n' | sed 's/^ *//')
unlisted=()
for rule in "${ported[@]}"; do
	grep -qF "\`$rule\`" README.md || unlisted+=("$rule")
done
if [[ ${#ported[@]} -gt 0 && ${#unlisted[@]} -eq 0 ]]; then
	ok "README.md lists the ${#ported[@]} rules"
else
	ko "README.md does not list: ${unlisted[*]:-(no rules read)}"
fi

# A symlinked file is analyzed by the path it is given, not by its target (which here is outside
# any project).
mkdir -p "$TMP/symlink" "$TMP/outside"
cp tests/fixtures/tsconfig.json "$TMP/symlink/"
cp tests/fixtures/emoji.ts "$TMP/outside/real.ts"
ln -s ../outside/real.ts "$TMP/symlink/link.ts"
# A Windows program gets the path as Windows writes it (MSYS converts it on the way).
link=$TMP/symlink/link.ts
[[ $windows -eq 0 ]] || link=$(cygpath -m "$link")
sed "s|^tests/fixtures/emoji.ts|$link|" tests/expected/emoji.txt > "$TMP/symlink.expected"
if ./veslint "$link" > "$TMP/symlink.out" 2> "$TMP/symlink.err" &&
	diff -u "$TMP/symlink.expected" "$TMP/symlink.out"; then
	ok "symlinked file"
else
	ko "symlinked file"
	cat "$TMP/symlink.err"
fi

# Rules: for each tests/rules/<rule id>/ (the directory with an expected.txt, such as
# tests/rules/@typescript-eslint/await-thenable), veslint gives on its cases.ts (there may be more in
# subdirectories, each with its own tsconfig and, if its cases use other options, with an
# options.json holding the list of ESLint options) exactly expected.txt, whose lines are validated
# against typescript-eslint by tests/rules/reference.sh, and exits with code 1. Files go in order,
# grouped by options: the output is that of a single run. A rule with findings also has a
# fixes.txt: its exact output with --fixes (each line with the fix, the suggestions and the end).
extra_args=()
lint_cases() { # rule files...
	local rule=$1 key group_key='' status=0 f
	local out=${rule//\//__} # a file name for the rule
	shift
	local group=()
	run_group() {
		[[ ${#group[@]} -eq 0 ]] && return
		local args=(--rule "$rule")
		if [[ -n $group_key ]]; then
			local options
			options=$(< "$group_key")
			options=${options#\[}
			printf '{"rules": {"%s": ["error", %s}}' "$rule" "$options" > "$TMP/$out.config.json"
			args=(--config "$TMP/$out.config.json")
		fi
		local c=0
		./veslint "${args[@]}" "${extra_args[@]}" "${group[@]}" >> "$TMP/$out.out" 2>> "$TMP/$out.err" || c=$?
		if [[ $c -gt 1 ]]; then status=$c; elif [[ $c -eq 1 && $status -eq 0 ]]; then status=1; fi
		group=()
	}
	: > "$TMP/$out.out"
	: > "$TMP/$out.err"
	for f in "$@"; do
		key=$(dirname "$f")/options.json
		[[ -f $key ]] || key=''
		if [[ $key != "$group_key" ]]; then
			run_group
			group_key=$key
		fi
		group+=("$f")
	done
	run_group
	return $status
}
mapfile -t rule_dirs < <(find tests/rules -name expected.txt | sed 's|/expected\.txt$||' | sorted)
# The fixtures of the seyfert/* rules import seyfert, which tests/rules/seyfert/setup.sh links next
# to them from build/upstream; without it they are skipped (here and in the tests below that lint
# every fixture), and the line says so.
seyfert_skipped=0
if ! tests/rules/seyfert/setup.sh 2> "$TMP/seyfert-setup.err"; then
	seyfert_skipped=1
	mapfile -t rule_dirs < <(printf '%s\n' "${rule_dirs[@]}" | grep -v '^tests/rules/seyfert/')
	echo "skip   the fixtures of the seyfert/* rules: $(cat "$TMP/seyfert-setup.err")"
fi
check_rule() { # directory of the rule
	local dir=$1 rule out code cases
	rule=${dir#tests/rules/}
	out=${rule//\//__}
	mapfile -t cases < <(find "$dir" -name cases.ts -o -name cases.tsx | sorted)
	code=0
	lint_cases "$rule" "${cases[@]}" || code=$?
	# A rule whose findings TypeScript does not allow in a file (no-octal) has none: code 0.
	if { [[ $code -eq 1 ]] || [[ $code -eq 0 && ! -s $dir/expected.txt ]]; } &&
		diff -u "$dir/expected.txt" "$TMP/$out.out"; then
		ok "rule $rule: $(wc -l < "$dir/expected.txt") expected findings"
	else
		ko "rule $rule (code $code)"
		cat "$TMP/$out.err"
	fi
	if [[ -f $dir/fixes.txt ]]; then
		code=0
		extra_args=(--fixes)
		lint_cases "$rule" "${cases[@]}" || code=$?
		extra_args=()
		if [[ $code -eq 1 ]] && diff -u "$dir/fixes.txt" "$TMP/$out.out"; then
			ok "rule $rule: fixes and suggestions"
		else
			ko "rule $rule with --fixes (code $code)"
			cat "$TMP/$out.err"
		fi
	fi
}
jobs_started=0
for dir in "${rule_dirs[@]}"; do
	throttle
	check_rule "$dir" > "$TMP/check-rule.$jobs_started.log" 2>&1 &
	jobs_started=$((jobs_started + 1))
done
wait
for ((i = 0; i < jobs_started; i++)); do
	report "$TMP/check-rule.$i.log"
done
# The comments that configure ESLint (tests/directives): disable directives, the ones without use
# and inline configuration, with the fixes; validated against ESLint by tests/rules/reference.sh.
mapfile -t directive_files < <(find tests/directives -name '*.ts' | sorted)
code=0
./veslint --config tests/directives/rules.json --fixes "${directive_files[@]}" > "$TMP/directives.out" 2> "$TMP/directives.err" || code=$?
if [[ $code -eq 1 ]] && diff -u tests/directives/expected.txt "$TMP/directives.out"; then
	ok "directive comments: $(wc -l < tests/directives/expected.txt) expected lines"
else
	ko "directive comments (code $code)"
	cat "$TMP/directives.err"
fi
# --fix (tests/fix): on a copy, the files are rewritten like `eslint --fix` does (expected/, checked
# against ESLint by tests/rules/reference.sh) and the messages that remain are expected.txt.
mkdir -p "$TMP/fix"
cp tests/fix/*.ts tests/fix/tsconfig.json tests/fix/rules.json "$TMP/fix/"
code=0
(cd "$TMP/fix" && "$OLDPWD/veslint" --config rules.json --fix --fixes cases.ts) > "$TMP/fix.out" 2> "$TMP/fix.err" || code=$?
if [[ $code -eq 1 ]] && diff -u tests/fix/expected.txt "$TMP/fix.out" && diff -u tests/fix/expected/cases.ts "$TMP/fix/cases.ts" &&
	grep -q '1 files fixed' "$TMP/fix.err"; then
	ok "--fix rewrites the file like eslint --fix, in several passes"
else
	ko "--fix (code $code)"
	cat "$TMP/fix.err"
fi
# An ESLint configuration with ignores, rules per folder, linterOptions and the two ways the parser
# gets the types (tests/config). Its
# resolved form (resolved.json, what --print-config prints) needs no JavaScript runtime; reading
# eslint.config.mjs itself needs bun and the ESLint of build/eval, and is checked when they exist.
config_files=(base.ts globals/a.ts ignored/a.ts locked/a.ts named-project/a.ts neighbours/a.ts neighbours/b.ts
	neighbours/c.ts other/a.ts program-dir/project/a.ts program-dir/project/types.ts
	program-dir/service/a.ts program-dir/service/types.ts program-dir/shared.ts quiet/a.ts
	scopes/commonjs.ts scopes/globals.ts scopes/lib.ts scopes/script.ts skipped.gen.ts strict/a.ts
	unused-error/a.ts unused-inline/a.ts unused-inline/b.ts unused-inline/c.ts unused-inline/warned.ts)
code=0
(cd tests/config && ../../veslint --config resolved.json --fixes "${config_files[@]}") > "$TMP/config.out" 2> "$TMP/config.err" || code=$?
if [[ $code -eq 1 ]] && diff -u tests/config/expected.txt "$TMP/config.out"; then
	ok "--config with a resolved ESLint configuration: $(wc -l < tests/config/expected.txt) expected lines"
else
	ko "--config with a resolved ESLint configuration (code $code)"
	cat "$TMP/config.err"
fi
if command -v bun > /dev/null && [[ -d build/eval/spider-byte/node_modules/eslint ]]; then
	code=0
	(cd tests/config && VESLINT_ESLINT_DIR=../../build/eval/spider-byte ../../veslint --config eslint.config.mjs --fixes "${config_files[@]}") > "$TMP/config-bun.out" 2> "$TMP/config-bun.err" || code=$?
	if [[ $code -eq 1 ]] && diff -u tests/config/expected.txt "$TMP/config-bun.out" &&
		(cd tests/config && VESLINT_ESLINT_DIR=../../build/eval/spider-byte ../../veslint --config eslint.config.mjs --print-config "${config_files[@]}") | diff -u tests/config/resolved.json -; then
		ok "--config eslint.config.mjs resolved by ESLint through bun, and --print-config"
	else
		ko "--config eslint.config.mjs through bun (code $code)"
		cat "$TMP/config-bun.err"
	fi
fi
# A JSON with a `rules` section is read as ESLint reads a configuration object: veslint gives with
# it what ESLint gives with the configuration itself (the lines of tests/config/expected.txt).
# - unused-inline, with reportUnusedInlineConfigs: the rules of the configuration as written
#   (rules.json), and what `eslint --print-config` prints for those files (print-config.json, with
#   <tests/config> in the place of the directory; checked by tests/rules/reference.sh);
# - neighbours, with rules veslint does not have and a rule of a plugin the configuration does not
#   have, which the plugins listed by `eslint --print-config` tell.
json_config() { # folder file.json
	local code=0
	sed "s|<tests/config>|$ROOT/tests/config|" "tests/config/$1/$2" > "$TMP/$1-$2"
	(cd tests/config && ../../veslint --config "$TMP/$1-$2" --fixes "$1/a.ts" "$1/b.ts" "$1/c.ts") > "$TMP/json-config.out" 2> "$TMP/json-config.err" || code=$?
	if [[ $code -eq 1 ]] && diff -u <(grep -P "^$1/[abc]\\.ts:" tests/config/expected.txt) "$TMP/json-config.out"; then
		ok "--config $1/$2: as with the ESLint configuration"
	else
		ko "--config $1/$2 (code $code)"
		cat "$TMP/json-config.err"
	fi
}
json_config unused-inline rules.json
json_config unused-inline print-config.json
json_config neighbours print-config.json
code=0
./veslint --rule @typescript-eslint/no-floating-promises app.ts > "$TMP/nfp_app.out" 2> /dev/null || code=$?
if [[ $code -eq 0 && ! -s "$TMP/nfp_app.out" ]]; then
	ok "rule without problems: code 0 and no output"
else
	ko "rule without problems (code $code)"
fi

# --rule warnings: syntax errors, and nodes the rule could not analyze (a chain of 1,002 member
# accesses goes beyond the limit of 1,000 nesting levels).
./veslint --rule @typescript-eslint/no-floating-promises tests/fixtures/syntax_error.ts > /dev/null 2> "$TMP/warning.err"
if grep -q 'syntax errors' "$TMP/warning.err"; then
	ok "--rule warns about syntax errors"
else
	ko "--rule warns about syntax errors"
	cat "$TMP/warning.err"
fi
mkdir -p "$TMP/deep"
cp tests/fixtures/tsconfig.json "$TMP/deep/"
{
	printf 'declare const anyValue: any;\nanyValue'
	for _ in $(seq 1002); do printf '.a'; done
	printf ';\n'
} > "$TMP/deep/chain.ts"
./veslint --rule @typescript-eslint/no-unsafe-member-access "$TMP/deep/chain.ts" > /dev/null 2> "$TMP/deep.err"
if grep -q ' 1 nodes not analyzed' "$TMP/deep.err"; then
	ok "--rule warns about unanalyzed nodes"
else
	ko "--rule warns about unanalyzed nodes"
	cat "$TMP/deep.err"
fi
# tsgo 7.0.2 panicked on the empty array literals whose type is the empty tuple; 7.1.0-beta answers
# them, so their fixtures are analyzed whole.
: > "$TMP/empty-tuple.err"
./veslint --rule @typescript-eslint/no-unsafe-assignment \
	tests/rules/@typescript-eslint/no-unsafe-assignment/empty-tuple/cases.ts > /dev/null 2>> "$TMP/empty-tuple.err"
./veslint --rule @typescript-eslint/no-floating-promises \
	tests/rules/@typescript-eslint/no-floating-promises/empty-tuple/cases.ts > /dev/null 2>> "$TMP/empty-tuple.err"
if ! grep -q 'nodes not analyzed' "$TMP/empty-tuple.err"; then
	ok "the empty tuple: every node analyzed"
else
	ko "the empty tuple: every node analyzed"
	cat "$TMP/empty-tuple.err"
fi
# When no rule needs types, tsgo only parses the tsconfig, and a file gets a snapshot when a comment
# turns on a rule that needs them or an `await` may be a name: the output is the one of a run with
# a snapshot from the start (one rule with types more, which reports nothing there).
printf '{"rules": {"@typescript-eslint/no-this-alias": ["error"], "@typescript-eslint/no-use-before-define": ["error"]}}' > "$TMP/untyped.json"
printf '{"rules": {"@typescript-eslint/no-this-alias": ["error"], "@typescript-eslint/no-use-before-define": ["error"], "@typescript-eslint/no-array-delete": ["error"]}}' > "$TMP/typed.json"
lazy_files=(tests/lazy-snapshot/plain.ts tests/lazy-snapshot/inline.ts tests/lazy-snapshot/await-script.ts)
./veslint --config "$TMP/untyped.json" "${lazy_files[@]}" > "$TMP/lazy.out" 2> /dev/null
./veslint --config "$TMP/typed.json" "${lazy_files[@]}" > "$TMP/eager.out" 2> /dev/null
if cmp -s "$TMP/lazy.out" "$TMP/eager.out" \
	&& grep -q $'inline.ts:4:1\t@typescript-eslint/no-floating-promises' "$TMP/lazy.out" \
	&& grep -q $'await-script.ts:3:1\t@typescript-eslint/no-use-before-define' "$TMP/lazy.out"; then
	ok "rules without types: the output of a run with a snapshot"
else
	ko "rules without types: the output of a run with a snapshot"
	diff "$TMP/eager.out" "$TMP/lazy.out"
fi
./veslint --bench --config "$TMP/untyped.json" tests/lazy-snapshot/plain.ts > /dev/null 2> "$TMP/lazy.bench"
if grep -q '"tsgo_requests":2}' "$TMP/lazy.bench"; then
	ok "rules without types: no snapshot when nothing needs one"
else
	ko "rules without types: no snapshot when nothing needs one"
	tail -1 "$TMP/lazy.bench"
fi

# Usage errors: code 2 and a clear message.
expect_usage_error() { # description expected_text arguments...
	local desc=$1 needle=$2
	shift 2
	local code=0
	./veslint "$@" > /dev/null 2> "$TMP/usage.err" || code=$?
	if [[ $code -eq 2 ]] && grep -qF -- "$needle" "$TMP/usage.err"; then
		ok "$desc"
	else
		ko "$desc (code $code)"
		cat "$TMP/usage.err"
	fi
}
for javascript_file in component.jsx script.js module.mjs common.cjs; do
	expect_usage_error "a ${javascript_file##*.} file is rejected" "only reads TypeScript" "$javascript_file"
done
expect_usage_error "--server takes no files" "takes no files" --server app.ts
code=0
VESLINT_CPUS=two ./veslint app.ts > /dev/null 2> "$TMP/cpus.err" || code=$?
if [[ $code -eq 2 ]] && grep -qF "VESLINT_CPUS must be a number of CPUs" "$TMP/cpus.err"; then
	ok "a VESLINT_CPUS that is not a number of CPUs"
else
	ko "a VESLINT_CPUS that is not a number of CPUs (code $code)"
	cat "$TMP/cpus.err"
fi
# Directories (directories.v): `veslint .` lints the TypeScript files under the directory, as
# `eslint .` walks it, without the ones ESLint's configuration does not lint (tests/config ignores
# ignored/** and **/*.gen.ts, which a file given by name reports): with --config, and with bun
# finding eslint.config.mjs as the eslint command does. --summary prints the table of the rules
# that report problems (tests/config/summary.txt).
grep -v '^ignored/a\.ts:\|^skipped\.gen\.ts:' tests/config/expected.txt > "$TMP/dir-expected.txt"
code=0
(cd tests/config && ../../veslint --config resolved.json --fixes .) > "$TMP/dir.out" 2> "$TMP/dir.err" || code=$?
if [[ $code -eq 1 ]] && diff -u "$TMP/dir-expected.txt" "$TMP/dir.out"; then
	ok "a directory with --config: the files the configuration lints ($(wc -l < "$TMP/dir-expected.txt") lines)"
else
	ko "a directory with --config (code $code)"
	cat "$TMP/dir.err"
fi
if command -v bun > /dev/null && [[ -d build/eval/spider-byte/node_modules/eslint ]]; then
	code=0
	(cd tests/config && VESLINT_ESLINT_DIR=../../build/eval/spider-byte ../../veslint --fixes .) > "$TMP/dir-bun.out" 2> "$TMP/dir-bun.err" || code=$?
	if [[ $code -eq 1 ]] && diff -u "$TMP/dir-expected.txt" "$TMP/dir-bun.out"; then
		ok "a directory without --config: the closest eslint.config.mjs, through bun"
	else
		ko "a directory without --config, through bun (code $code)"
		cat "$TMP/dir-bun.err"
	fi
fi
code=0
(cd tests/config && ../../veslint --config resolved.json --summary .) > "$TMP/summary.out" 2> "$TMP/summary.err" || code=$?
if [[ $code -eq 1 ]] && diff -u tests/config/summary.txt "$TMP/summary.out" &&
	[[ $(tail -1 "$TMP/summary.err") == "$(tail -1 "$TMP/dir.err")" ]]; then
	ok "--summary: the table of the rules that report problems"
else
	ko "--summary (code $code)"
	cat "$TMP/summary.err"
fi
mkdir -p "$TMP/no-ts/sub" "$TMP/no-config"
echo 'let x = 1;' > "$TMP/no-config/a.ts"
expect_usage_error "a directory whose files are all ignored" 'all of the files matching the glob pattern "tests/config/ignored" are ignored' \
	--config tests/config/resolved.json tests/config/ignored
expect_usage_error "a directory without TypeScript files" "No files matching the pattern" "$TMP/no-ts"
expect_usage_error "a directory without --config and no eslint.config.* above it" "no ESLint configuration" "$TMP/no-config"
expect_usage_error "--summary cannot be combined with --fixes" "cannot be combined" --summary --fixes --rule no-var app.ts
expect_usage_error "--summary needs rules" "--summary needs rules" --summary app.ts
expect_usage_error "--rule takes a single rule" "a single rule" \
	--rule @typescript-eslint/no-floating-promises --rule @typescript-eslint/await-thenable app.ts
expect_usage_error "--rule cannot be combined with --all-identifiers" "cannot be combined" \
	--rule @typescript-eslint/no-floating-promises --all-identifiers app.ts

# --config: the `rules` section of an ESLint configuration (here, shaped like the output of
# The `languageOptions` of a JSON with a `rules` section (the output of `eslint --print-config` has
# them): the ecmaVersion and the globals decide which globals a file has, and with them which
# constants are evaluated. With the options of tests/config's `globals` folder, the same findings.
code=0
printf '%s' '{"rules": {"@typescript-eslint/prefer-find": "error"}, "languageOptions": {"ecmaVersion": 2019, "globals": {"parseInt": "off", "parseFloat": "off", "Number": "off", "isNaN": false}}}' > "$TMP/globals.json"
./veslint --config "$TMP/globals.json" tests/config/globals/a.ts > "$TMP/globals.out" 2> "$TMP/globals.err" || code=$?
if [[ $code -eq 1 ]] && diff -u <(grep -P '^globals/a\.ts:.*\t@typescript-eslint/prefer-find\t' tests/config/expected.txt | cut -f1-4) <(sed 's|^tests/config/||' "$TMP/globals.out"); then
	ok "--config with languageOptions: ecmaVersion and globals"
else
	ko "--config with languageOptions (code $code)"
	cat "$TMP/globals.err"
fi

# veslint_batched OUT ERR ARGUMENTS... -- FILES...: ./veslint with the arguments and the files,
# appending to OUT and ERR; the files go in batches that fit in a Windows command line (32,767
# characters), all at once elsewhere. Returns the highest exit code.
veslint_batched() {
	local out=$1 err=$2 code=0 c size=0 file limit=0
	shift 2
	local args=() batch=()
	while [[ $1 != -- ]]; do
		args+=("$1")
		shift
	done
	shift
	[[ $windows -eq 0 ]] || limit=24000
	for file in "$@"; do
		if [[ $limit -gt 0 && ${#batch[@]} -gt 0 && $((size + ${#file} + 1)) -gt $limit ]]; then
			c=0
			./veslint "${args[@]}" "${batch[@]}" >> "$out" 2>> "$err" || c=$?
			[[ $c -le $code ]] || code=$c
			batch=()
			size=0
		fi
		batch+=("$file")
		size=$((size + ${#file} + 1))
	done
	if [[ ${#batch[@]} -gt 0 ]]; then
		c=0
		./veslint "${args[@]}" "${batch[@]}" >> "$out" 2>> "$err" || c=$?
		[[ $c -le $code ]] || code=$c
	fi
	return $code
}

# `eslint --print-config`: numeric severities, the core require-await rule turned off and rules of
# other plugins), with every rule of tests/rules and its default options.
mapfile -t all_cases < <(find tests/rules -name cases.ts -o -name cases.tsx | sorted)
[[ $seyfert_skipped -eq 0 ]] || mapfile -t all_cases < <(printf '%s\n' "${all_cases[@]}" | grep -v '^tests/rules/seyfert/')
cat > "$TMP/all.json" << 'JSON'
{"rules": {
  "@typescript-eslint/no-floating-promises": [2], "@typescript-eslint/await-thenable": [2],
  "require-await": [0], "@typescript-eslint/require-await": [2],
  "@typescript-eslint/return-await": [2, "in-try-catch"], "@typescript-eslint/no-misused-promises": [2],
  "@typescript-eslint/no-unsafe-argument": [2], "@typescript-eslint/no-unsafe-assignment": [2],
  "@typescript-eslint/no-unsafe-call": [2], "@typescript-eslint/no-unsafe-member-access": [2, {"allowOptionalChaining": false}],
  "@typescript-eslint/no-unsafe-return": [2], "semi": [2, "always"], "@stylistic/indent": [1, 2]
JSON
for dir in "${rule_dirs[@]}"; do
	r=${dir#tests/rules/}
	grep -q "\"$r\"" "$TMP/all.json" || printf ', "%s": [2]\n' "$r" >> "$TMP/all.json"
done
echo '}}' >> "$TMP/all.json"
# Every rule alone on every fixture (in any order: the findings are compared sorted), and every rule
# at once, side by side.
: > "$TMP/all.out"
: > "$TMP/all.err"
(
	code=0
	veslint_batched "$TMP/all.out" "$TMP/all.err" --config "$TMP/all.json" -- "${all_cases[@]}" || code=$?
	echo "$code" > "$TMP/all.code"
) &
jobs_started=0
for dir in "${rule_dirs[@]}"; do
	throttle
	: > "$TMP/per-rule.$jobs_started.out"
	veslint_batched "$TMP/per-rule.$jobs_started.out" /dev/null --rule "${dir#tests/rules/}" -- "${all_cases[@]}" &
	jobs_started=$((jobs_started + 1))
done
wait
cat "$TMP"/per-rule.*.out > "$TMP/per-rule.out"
code=$(< "$TMP/all.code")
# tests/rules/every.known.txt: findings of a rule alone that the run with every rule does not give
# (one rule sees what another did to the scope manager, as in ESLint).
if [[ $code -eq 1 ]] && diff <(sort "$TMP/all.out") <(grep -vxF -f <(grep -v '^#' tests/rules/every.known.txt) "$TMP/per-rule.out" | sort) > /dev/null &&
	grep -q 'ignores them: semi, @stylistic/indent$' "$TMP/all.err"; then
	ok "--config with every rule: the same findings as each --rule ($(wc -l < "$TMP/all.out"))"
else
	ko "--config with every rule (code $code)"
	cat "$TMP/all.err"
fi
printf '{"rules": {"@typescript-eslint/no-floating-promises": "warn"}}' > "$TMP/warn.json"
code=0
./veslint --config "$TMP/warn.json" tests/rules/@typescript-eslint/no-floating-promises/cases.ts > "$TMP/warn.out" 2> "$TMP/warn-config.err" || code=$?
if [[ $code -eq 0 && -s "$TMP/warn.out" ]] && grep -q 'of them warnings' "$TMP/warn-config.err"; then
	ok "--config: a rule set to warn reports and exits with code 0"
else
	ko "--config: a rule set to warn (code $code)"
	cat "$TMP/warn-config.err"
fi
printf '{"rules": {"@typescript-eslint/await-thenable": ["error", {"anything": true}]}}' > "$TMP/options.json"
# Options that do not fit the schema of the rule are rejected with ESLint's own words (see also
# tests/config-errors below).
expect_usage_error "--config rejects options for a rule that has none" \
	'Value [{"anything":true}] should NOT have more than 0 items.' --config "$TMP/options.json" app.ts
printf '{"rules": {"@typescript-eslint/restrict-template-expressions": ["error", {"allow": [{"from": "package", "name": "x"}]}]}}' > "$TMP/package.json"
expect_usage_error "--config rejects a package type specifier without its package" \
	"Value {\"from\":\"package\",\"name\":\"x\"} should have required property 'package'." --config "$TMP/package.json" app.ts
printf '{"rules": {"@typescript-eslint/restrict-template-expressions": ["error", {"allowStrings": true}]}}' > "$TMP/unknown.json"
expect_usage_error "--config rejects unknown options" \
	'Unexpected property "allowStrings". Expected properties: "allowAny", "allowArray", "allowBoolean", "allowNullish", "allowNumber", "allowRegExp", "allowNever", "allow".' --config "$TMP/unknown.json" app.ts
printf '{"rules": {"@typescript-eslint/restrict-template-expressions": ["error", {"allowAny": "yes"}]}}' > "$TMP/type.json"
expect_usage_error "--config rejects an option of the wrong type" \
	'Value "yes" should be boolean.' --config "$TMP/type.json" app.ts
printf '{"rules": {"require-await": "error", "semi": ["error", "always"], "quotes": "error", "await-thenable": "error", "no-floating-promises": "error"}}' > "$TMP/core.json"
expect_usage_error "--config: a name without its plugin is a rule of ESLint core, not one of veslint" \
	"does not enable any veslint rule" --config "$TMP/core.json" app.ts
# What ESLint does not take in a configuration (tests/config-errors): the error is
# `veslint: <file>: ` and the text the eslint command prints for those rules (the .txt of each file,
# checked against ESLint by tests/rules/reference.sh), then the usage line; and the code is 2, as
# ESLint's.
for json in tests/config-errors/*.json; do
	[[ $(basename "$json") == tsconfig.json ]] && continue
	code=0
	./veslint --config "$json" tests/config-errors/cases.ts > /dev/null 2> "$TMP/config-error.err" || code=$?
	if [[ $code -eq 2 ]] && diff -u <(printf 'veslint: %s: ' "$json"; cat "${json%.json}.txt") <(head -n -1 "$TMP/config-error.err"); then
		ok "--config $json: ESLint's error"
	else
		ko "--config $json (code $code)"
		cat "$TMP/config-error.err"
	fi
done
# The same with the ESLint configuration of that directory, which ESLint itself resolves (through
# bun): the error is ESLint's own.
if command -v bun > /dev/null && [[ -d build/eval/spider-byte/node_modules/eslint ]]; then
	same=0
	for json in tests/config-errors/*.json; do
		[[ $(basename "$json") == tsconfig.json ]] && continue
		code=0
		RULES=$(basename "$json") VESLINT_ESLINT_DIR=build/eval/spider-byte ./veslint --config tests/config-errors/eslint.config.mjs \
			tests/config-errors/cases.ts > /dev/null 2> "$TMP/config-error.err" || code=$?
		if [[ $code -ne 2 ]] || ! diff -u <(printf 'veslint: tests/config-errors/eslint.config.mjs: '; cat "${json%.json}.txt") <(head -n -1 "$TMP/config-error.err"); then
			same=1
			echo "$json (code $code)"
		fi
	done
	if [[ $same -eq 0 ]]; then
		ok "--config eslint.config.mjs that ESLint does not take: ESLint's error"
	else
		ko "--config eslint.config.mjs that ESLint does not take"
	fi
fi
printf '{"rules": ' > "$TMP/broken.json"
expect_usage_error "--config with broken JSON" "not valid JSON" --config "$TMP/broken.json" app.ts
expect_usage_error "--rule cannot be combined with --config" "cannot be combined" \
	--rule @typescript-eslint/no-floating-promises --config "$TMP/all.json" app.ts

# 2. --bench writes a JSON with the timings to stderr, including each batch.
./veslint --bench app.ts 2> "$TMP/bench.json" > /dev/null
if grep -q '"total_ms"' "$TMP/bench.json" && grep -q '"symbol_batches_ms":\[' "$TMP/bench.json"; then
	ok "--bench writes the timings"
else
	ko "--bench writes the timings"
	cat "$TMP/bench.json"
fi

# 3. Errors of §9: each one ends with code 1 and a clear message, without hanging.
expect_error() { # description expected_text command...
	local desc=$1 needle=$2
	shift 2
	local code=0
	timeout 20 "$@" > "$TMP/error.out" 2> "$TMP/error.err" || code=$?
	if [[ $code -eq 124 ]]; then
		ko "$desc: it hung"
	elif [[ $code -eq 1 ]] && grep -qF -- "$needle" "$TMP/error.err"; then
		ok "$desc"
	else
		ko "$desc (code $code)"
		cat "$TMP/error.err"
	fi
}

# platform_package is the package with the native compiler of this machine, as veslint names it
# (tsgo/platform.v): typescript-<process.platform>-<process.arch>.
platform_package() {
	local os arch
	case $(uname -s) in
		Linux) os=linux ;; Darwin) os=darwin ;; FreeBSD) os=freebsd ;; OpenBSD) os=openbsd ;;
		NetBSD) os=netbsd ;; SunOS) os=sunos ;; AIX) os=aix ;; *) os=win32 ;;
	esac
	case $(uname -m) in
		x86_64 | amd64 | i86pc) arch=x64 ;; aarch64 | arm64 | evbarm) arch=arm64 ;; arm*) arch=arm ;;
		ppc64*) arch=ppc64 ;; loongarch64) arch=loong64 ;; mips64) arch=mips64el ;; *) arch=$(uname -m) ;;
	esac
	[[ $os == aix ]] && arch=ppc64
	echo "typescript-$os-$arch"
}

# sandbox MODE: copies veslint to a directory whose tsgo is tests/fake_tsgo.sh MODE; on Windows,
# tests/fake_tsgo.v compiled to tsc.exe, with the mode in a file next to it.
# Fake tsgo processes left waiting are named `fake-tsgo-<tag>-*`, with a tag of this run (on
# Windows, they are the tsc.exe under its directory): other runs of the suite (other copies of the
# project) may have theirs at the same time.
fake_tag=$(basename "$TMP")
if [[ $windows -eq 1 ]]; then
	mkdir -p "$TMP/fake-tsgo"
	"$V" -o "$TMP/fake-tsgo/tsc.exe" tests/fake_tsgo.v > /dev/null
fi
sandbox() {
	local mode=$1 dir="$TMP/sandbox-$1"
	mkdir -p "$dir"
	cp "veslint$exe" "$dir/"
	if [[ $mode != missing ]]; then
		local lib="$dir/node_modules/@typescript/$(platform_package)/lib"
		mkdir -p "$lib"
		if [[ $windows -eq 1 ]]; then
			cp "$TMP/fake-tsgo/tsc.exe" "$lib/"
			printf '%s\n' "$mode" > "$lib/fake_tsgo_mode"
		else
			printf '#!/usr/bin/env bash\nFAKE_TSGO_TAG=%s exec "%s/tests/fake_tsgo.sh" %s "$@"\n' "$fake_tag" "$ROOT" "$mode" > "$lib/tsc"
			chmod +x "$lib/tsc"
		fi
	fi
	echo "$dir/veslint"
}

expect_error "missing binary" "make deps" "$(sandbox missing)" app.ts
expect_error "different version" "\`Version 7.1.0-beta\` was expected" "$(sandbox version-mismatch)" app.ts
# The version check has the timeout of a request: a binary that never answers `--version`, or that
# answers and does not exit, is killed (the check for fake tsgo processes below finds it otherwise).
expect_error "timeout of a --version that never answers" "--version\` did not finish within" \
	env VESLINT_TIMEOUT_MS=300 "$(sandbox version-hang)" app.ts
expect_error "timeout of a --version that answers and does not exit" "--version\` did not finish within" \
	env VESLINT_TIMEOUT_MS=300 "$(sandbox version-linger)" app.ts
expect_error "tsgo dies (EOF), with the stderr tail" "simulated failure" "$(sandbox die-on-start)" app.ts
# veslint keeps itself and the tsgo it starts on two of the CPUs it may use (cpus.v), on
# VESLINT_CPUS of them, and on all of them with VESLINT_CPUS=0; on Linux only.
if [[ $windows -eq 0 ]]; then
	allowed_cpus=$(env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)
	expect_error "tsgo runs on two CPUs" "simulated failure on CPUs: $((allowed_cpus < 2 ? allowed_cpus : 2))." \
		env -u VESLINT_CPUS "$(sandbox cpus)" app.ts
	expect_error "VESLINT_CPUS=1: tsgo runs on one CPU" "simulated failure on CPUs: 1." \
		env VESLINT_CPUS=1 "$(sandbox cpus)" app.ts
	expect_error "VESLINT_CPUS=0: tsgo runs on every CPU" "simulated failure on CPUs: $allowed_cpus." \
		env VESLINT_CPUS=0 "$(sandbox cpus)" app.ts
else
	echo "skip   tsgo on two CPUs: veslint restricts its CPUs on Linux only"
fi
expect_error "timeout (and SIGKILL of a tsgo that ignores stdin being closed)" "timeout" \
	env VESLINT_TIMEOUT_MS=300 "$(sandbox silent)" app.ts
expect_error "message type 5" "source file not found" ./veslint --project tsconfig.json tests/fixtures/emoji.ts
expect_error "different method name in the response" "got \`bogus\`" "$(sandbox wrong-method)" app.ts
expect_error "tsconfig not in the snapshot" "is not in the tsgo snapshot" "$(sandbox no-projects)" app.ts
expect_error "unsupported callback (type 6)" "\`readFile\` callback" "$(sandbox callback)" app.ts
expect_error "a tsgo that floods messages does not hang the shutdown" "got \`bogus\`" "$(sandbox flood)" app.ts
# A request larger than the pipe buffer (64 KiB) to a tsgo that does not read stdin: the write
# must honor the timeout too.
mkdir -p "$TMP/big"
printf '{"compilerOptions":{"strict":true},"include":["*.ts"]}\n' > "$TMP/big/tsconfig.json"
for i in $(seq 1 12000); do
	echo "const v$i = $i;"
done > "$TMP/big/large.ts"
expect_error "request over 64 KiB to a tsgo that does not read stdin" "timeout" \
	env VESLINT_TIMEOUT_MS=500 "$(sandbox no-read)" "$TMP/big/large.ts"
# fake_tsgo_left: a fake tsgo of this run is still running (Git Bash has no pgrep: `ps -W` lists
# the Windows processes with their paths).
fake_tsgo_left() {
	if [[ $windows -eq 1 ]]; then
		ps -W | grep -iF "$fake_tag" | grep -i 'sandbox-' | grep -iq 'tsc\.exe'
	else
		pgrep -f "^fake-tsgo-$fake_tag-" > /dev/null
	fi
}
if fake_tsgo_left; then
	ko "fake tsgo processes were left behind"
else
	ok "no fake tsgo processes left behind"
fi

# 4. Killing tsgo in the middle of a run (§10, M4): veslint ends with an error, without hanging.
if [[ ! -d build/bench/src ]]; then
	"$V" run tests/gen_bench.vsh build/bench > /dev/null
fi
# On Windows (no pgrep) veslint runs from a sandbox with a copy of the real compiler, whose tsc.exe
# is found by its path and stopped with taskkill.
kill_veslint=./veslint
if [[ $windows -eq 1 ]]; then
	kill_dir=$TMP/sandbox-kill
	mkdir -p "$kill_dir/node_modules/@typescript"
	cp "veslint$exe" "$kill_dir/"
	cp -r "node_modules/@typescript/$(platform_package)" "$kill_dir/node_modules/@typescript/"
	kill_veslint=$kill_dir/veslint
fi
# tsgo_of PID: the tsgo veslint (PID) started, or nothing yet: the `tsc --api` one, not the
# `tsc --version` of the check before it, which ends at once.
tsgo_of() {
	if [[ $windows -eq 1 ]]; then
		powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"Name = 'tsc.exe'\" | Where-Object { \$_.ExecutablePath -like '*$fake_tag*sandbox-kill*' -and \$_.CommandLine -like '*--api*' }).ProcessId" | tr -d '\r'
	else
		pgrep -P "$1" -f -- '--api' || true
	fi
}
"$kill_veslint" --all-identifiers --per-identifier build/bench/src/*.ts > /dev/null 2> "$TMP/kill.err" &
pid=$!
tsgo_pid=""
for _ in $(seq 1 200); do
	tsgo_pid=$(tsgo_of "$pid")
	[[ -n $tsgo_pid ]] && break
	sleep 0.02
done
if [[ -z $tsgo_pid ]]; then
	ko "killing tsgo midway: the tsgo process was not found"
	wait "$pid"
else
	sleep 0.3
	if [[ $windows -eq 1 ]]; then
		taskkill //F //PID "$tsgo_pid" > /dev/null
	else
		kill -9 "$tsgo_pid"
	fi
	for _ in $(seq 1 100); do
		kill -0 "$pid" 2> /dev/null || break
		sleep 0.1
	done
	if kill -0 "$pid" 2> /dev/null; then
		kill -9 "$pid"
		ko "killing tsgo midway: veslint hung"
	else
		code=0
		wait "$pid" || code=$?
		if [[ $code -eq 1 ]] && grep -q 'EOF' "$TMP/kill.err"; then
			ok "killing tsgo midway: veslint ends with an EOF error"
		else
			ko "killing tsgo midway (code $code)"
			cat "$TMP/kill.err"
		fi
	fi
fi

# --server (server.v): a scenario with unsaved text, a file closed without saving, files changed on
# disk, a reset, errors, and a declaration the server keeps between snapshots that changes
# (tests/server, run on a copy, since it writes files); and on the configuration fixture, the
# answer is what the command line prints for the same files.
cp -r tests/server/project "$TMP/server"
if python3 tests/server_client.py ./veslint "$TMP/server" tests/server/requests.jsonl > "$TMP/server.out" 2> "$TMP/server.err" &&
	diff -u tests/server/expected.jsonl "$TMP/server.out"; then
	ok "--server: unsaved text, changes on disk and errors (tests/server)"
else
	ko "--server (tests/server)"
	cat "$TMP/server.err"
fi
config_abs=()
for file in "${config_files[@]}"; do
	config_abs+=("$PWD/tests/config/$file")
done
python3 -c 'import json, sys; print(json.dumps({"id": 1, "config": "resolved.json", "files": sys.argv[1:]}))' "${config_abs[@]}" > "$TMP/server-config.jsonl"
code=0
(cd tests/config && ../../veslint --config resolved.json --fixes "${config_abs[@]}") > "$TMP/cli-config.out" 2> "$TMP/cli-config.err" || code=$?
if python3 tests/server_client.py ./veslint tests/config "$TMP/server-config.jsonl" > "$TMP/server-config.out" 2> "$TMP/server-config.err" &&
	python3 - "$TMP/server-config.out" "$TMP/cli-config.out" "$TMP/cli-config.err" "$code" "$PWD/tests/config" << 'PY'
import json, sys
answer = json.loads(open(sys.argv[1]).readline())
cwd = sys.argv[5]
got = (answer['stdout'].replace('<cwd>', cwd), answer['stderr'].replace('<cwd>', cwd), answer['code'])
sys.exit(0 if got == (open(sys.argv[2]).read(), open(sys.argv[3]).read(), int(sys.argv[4])) else 1)
PY
then
	ok "--server: the same output as the command line for tests/config ($(wc -l < "$TMP/cli-config.out") lines)"
else
	ko "--server: not the output of the command line for tests/config"
	cat "$TMP/server-config.err"
fi
# Requests written before the answers to the previous ones, as an editor sends them while a file
# is typed (tests/server_pipeline.py): answered in order, and given up when a later one lints the
# same file.
if python3 tests/server_pipeline.py ./veslint > "$TMP/server-pipeline.out" 2>&1; then
	ok "--server: requests sent together are answered in order, and given up for a later one of the same file"
else
	ko "--server: requests sent together (tests/server_pipeline.py)"
	cat "$TMP/server-pipeline.out"
fi
# A server keeps every thread of its own and of its tsgo on two CPUs as well (cpus.v): looked at
# after its first lint, while both are alive (on Linux only).
if [[ $windows -eq 1 ]]; then
	echo "skip   --server on two CPUs: veslint restricts its CPUs on Linux only"
elif python3 - ./veslint tests/config "${config_abs[0]}" 2> "$TMP/server-cpus.err" << 'PY'
import json, os, subprocess, sys
veslint, cwd, file = os.path.abspath(sys.argv[1]), sys.argv[2], sys.argv[3]
want = min(2, len(os.sched_getaffinity(0)))
env = {k: v for k, v in os.environ.items() if k != 'VESLINT_CPUS'}
server = subprocess.Popen([veslint, '--server'], cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True, env=env)
server.stdin.write(json.dumps({'id': 1, 'config': 'resolved.json', 'files': [file]}) + '\n')
server.stdin.flush()
answer = json.loads(server.stdout.readline())


def parent(pid):
    try:
        return open(f'/proc/{pid}/stat').read().rsplit(')', 1)[1].split()[1]
    except OSError:
        return None


children = [int(p) for p in os.listdir('/proc') if p.isdigit() and parent(p) == str(server.pid)]
seen = {}
for pid in [server.pid] + children:
    for tid in os.listdir(f'/proc/{pid}/task'):
        try:
            seen[f'{pid}/{tid}'] = sorted(os.sched_getaffinity(int(tid)))
        except OSError:
            pass
server.stdin.close()
code = server.wait(timeout=30)
sets = {tuple(cpus) for cpus in seen.values()}
if answer.get('code') not in (0, 1) or code != 0 or not children or len(sets) != 1 or len(next(iter(sets))) != want:
    sys.exit(f'answer code {answer.get("code")}, exit {code}, children {children}, threads on {sets} (want {want} CPUs)')
print(f'{len(seen)} threads in {1 + len(children)} processes on {sorted(sets)[0]}', file=sys.stderr)
PY
then
	ok "--server: veslint and tsgo on two CPUs ($(tail -1 "$TMP/server-cpus.err"))"
else
	ko "--server: veslint and tsgo not on two CPUs"
	cat "$TMP/server-cpus.err"
fi

# typescript-eslint's own tests of the ported rules (tests/upstream/README.md): every case of each
# tests/rules/<rule>/upstream.json gives what its upstream test expects, but the ones
# tests/upstream/known.txt lists. They need the packages tests/upstream/setup.sh links into the
# fixtures; without them they are skipped, and the line says so.
# The tests of each plugin run in their own fixtures: those of @slipher/eslint-plugin (the
# `seyfert/*` rules) in the ones tests/upstream/seyfert/setup.sh makes.
# upstream_check LABEL FIXTURES CONFIGS RULES...: tests/upstream_check.py on the rules, split in JOBS
# groups that run at once (each with its veslint --server), and one line for all of them.
upstream_check() {
	local label=$1 fixtures=$2 configs=$3
	shift 3
	local groups=$JOBS k rule index pids=() codes=0 cases=0 unexpected=0 known=0 summary
	[[ $groups -le $# ]] || groups=$#
	for ((k = 0; k < groups; k++)); do
		local group=()
		index=0
		for rule in "$@"; do
			[[ $((index % groups)) -eq $k ]] && group+=("$rule")
			index=$((index + 1))
		done
		python3 tests/upstream_check.py ./veslint "$fixtures" "$configs.$k" "${group[@]}" > "$configs.$k.out" 2>&1 &
		pids+=($!)
	done
	for k in "${!pids[@]}"; do
		wait "${pids[$k]}" || codes=1
		summary=$(tail -1 "$configs.$k.out")
		if [[ $summary =~ ^([0-9]+)\ cases\;\ ([0-9]+)\ unexpected.*\;\ ([0-9]+)\ known ]]; then
			cases=$((cases + BASH_REMATCH[1]))
			unexpected=$((unexpected + BASH_REMATCH[2]))
			known=$((known + BASH_REMATCH[3]))
		else
			codes=1
		fi
	done
	if [[ $codes -eq 0 ]]; then
		ok "$label: $cases cases; $unexpected unexpected failure(s); $known known difference(s) (tests/upstream/known.txt)"
	else
		ko "$label"
		for k in "${!pids[@]}"; do
			grep -v '^ok' "$configs.$k.out"
		done
	fi
}
upstream_rules_of() { # plugin directory of tests/rules
	find "tests/rules/$1" -name upstream.json | sed -E 's|^tests/rules/(.*)/upstream\.json$|\1|' | sorted
}
mapfile -t typescript_eslint_upstream < <(upstream_rules_of @typescript-eslint)
mapfile -t seyfert_upstream < <(upstream_rules_of seyfert)
# The rules of ESLint core (tests/rules/<rule>/upstream.json, from tests/lib/rules/<rule>.js of
# ESLint 10.6.0): their JavaScript cases are linted as TypeScript in typescript-eslint's fixtures.
mapfile -t core_upstream < <(find tests/rules -mindepth 2 -maxdepth 2 -name upstream.json | sed -E 's|^tests/rules/(.*)/upstream\.json$|\1|' | sorted)
# The rules of eslint-plugin-unicorn (tests/rules/unicorn/<rule>/upstream.json, from test/<rule>.js
# of v64.0.0), the same way.
mapfile -t unicorn_upstream < <(upstream_rules_of unicorn)
if tests/upstream/setup.sh "$TMP/upstream" 2> "$TMP/upstream-setup.err"; then
	upstream_check "typescript-eslint's own tests" "$TMP/upstream" "$TMP/upstream-configs" "${typescript_eslint_upstream[@]}"
	[[ ${#core_upstream[@]} -eq 0 ]] ||
		upstream_check "ESLint's own tests of its core rules" "$TMP/upstream" "$TMP/upstream-core-configs" "${core_upstream[@]}"
	[[ ${#unicorn_upstream[@]} -eq 0 ]] ||
		upstream_check "eslint-plugin-unicorn's own tests" "$TMP/upstream" "$TMP/upstream-unicorn-configs" "${unicorn_upstream[@]}"
else
	echo "skip   typescript-eslint's own tests: $(cat "$TMP/upstream-setup.err")"
fi
if tests/upstream/seyfert/setup.sh "$TMP/upstream-seyfert" 2> "$TMP/upstream-seyfert-setup.err"; then
	upstream_check "@slipher/eslint-plugin's own tests" "$TMP/upstream-seyfert" "$TMP/upstream-seyfert-configs" "${seyfert_upstream[@]}"
else
	echo "skip   @slipher/eslint-plugin's own tests: $(cat "$TMP/upstream-seyfert-setup.err")"
fi

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
