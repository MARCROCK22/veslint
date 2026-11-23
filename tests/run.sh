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
# Every configuration is resolved by ESLint through bun, but in the tests of the cache of resolved
# configurations, which turn it on.
export VESLINT_CONFIG_CACHE=0
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

# The slow checks (each rule on its fixtures, each rule on every fixture with VESLINT_MATRIX=1, the
# upstream tests) run
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
# phase prints how long the checks since the last phase took (`time   <phase>: <seconds> s`), to see
# where the time of `make test` goes.
phase_start=$SECONDS
phase() { # label
	echo "time   $1: $((SECONDS - phase_start)) s"
	phase_start=$SECONDS
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

phase "exact outputs of the identifier modes"
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
		# The fixtures of the rules of @eslint-community/eslint-plugin-eslint-comments are linted
		# without the reports of unused directives, as tests/rules/eslint.reference.config.mjs lints them.
		if [[ -n $group_key || $rule == @eslint-community/eslint-comments/* ]]; then
			local options=']' linter=''
			[[ -n $group_key ]] && options=", $(< "$group_key")" && options=", ${options#, \[}"
			[[ $rule == @eslint-community/eslint-comments/* ]] && linter='"linterOptions": {"reportUnusedDisableDirectives": 0}, '
			printf '{%s"rules": {"%s": ["error"%s}}' "$linter" "$rule" "$options" > "$TMP/$out.config.json"
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
	mapfile -t cases < <(find "$dir" -name cases.ts -o -name cases.tsx -o -name cases.vue -o -name cases.svelte | sorted)
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
phase "each rule on its own fixtures"
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
# A write that fails for a while, as on Windows when another process (an antivirus, the indexer)
# has the file open (VESLINT_DEBUG_WRITE_FAILURES fails the first attempts as a sharing violation
# does): --fix tries it again and gives the same as without failures.
mkdir -p "$TMP/fix-retry"
cp tests/fix/*.ts tests/fix/tsconfig.json tests/fix/rules.json "$TMP/fix-retry/"
code=0
(cd "$TMP/fix-retry" && VESLINT_DEBUG_WRITE_FAILURES=4 "$OLDPWD/veslint" --config rules.json --fix --fixes cases.ts) > "$TMP/fix-retry.out" 2> "$TMP/fix-retry.err" || code=$?
if [[ $code -eq 1 ]] && cmp -s "$TMP/fix.out" "$TMP/fix-retry.out" && cmp -s "$TMP/fix.err" "$TMP/fix-retry.err" &&
	diff -u tests/fix/expected/cases.ts "$TMP/fix-retry/cases.ts"; then
	ok "--fix tries a write again while it fails as a file another process has open"
else
	ko "--fix with writes that fail for a while (code $code)"
	cat "$TMP/fix-retry.err"
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
# A resolved configuration saved by veslint 0.38 or older (resolved-0.38.json: no `typescriptEslint`
# key) still has typescript-eslint's rules.
code=0
(cd tests/config && ../../veslint --config resolved-0.38.json --fixes "${config_files[@]}") > "$TMP/config-0.38.out" 2> "$TMP/config-0.38.err" || code=$?
if [[ $code -eq 1 ]] && diff -u tests/config/expected.txt "$TMP/config-0.38.out"; then
	ok "--config with a resolved configuration of veslint 0.38"
else
	ko "--config with a resolved configuration of veslint 0.38 (code $code)"
	cat "$TMP/config-0.38.err"
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
# Files in none of the projects typescript-eslint takes the types from (tests/projects): each is
# ESLint's fatal parsing error at 0:0, with typescript-estree's message (the project service's, with
# allowDefaultProject's patterns, or that of `parserOptions.project`, which is another one when the
# run is not a single one, as with --fix), and the other files are linted and fixed. A file in the
# tsconfig of a directory above the closest one, or in a project the closest one references, has
# the types of that project. expected.txt and expected-fix.txt (`<tests/projects>` in the place of
# the directory) are checked against ESLint by tests/rules/reference.sh. d-out.ts, which only the
# default project of allowDefaultProject has, is linted with a program of its own, and d-out2.ts is
# one file more than that project may have.
projects_files=(default-project/d-in.ts default-project/d-out.ts default-project/d-out2.ts default-project/in.ts default-project/out.ts
	project/a.ts project/b.ts service/.generated/g.d.ts service/a.ts service/b.ts service/c.ts
	service/nested/x.ts service/nested/y.ts service/solution/s.ts)
if [[ $windows -eq 0 ]]; then
	code=0
	(cd tests/projects && ../../veslint --config resolved.json --fixes "${projects_files[@]}") > "$TMP/projects.out" 2> "$TMP/projects.err" || code=$?
	if [[ $code -eq 1 ]] && diff -u tests/projects/expected.txt <(sed "s|$ROOT/tests/projects|<tests/projects>|g" "$TMP/projects.out") &&
		grep -qx "$(wc -l < tests/projects/expected.txt) problems in ${#projects_files[@]} files" "$TMP/projects.err"; then
		ok "files in no project: ESLint's parsing error for each, the others linted ($(grep -c $'\tfatal\t' tests/projects/expected.txt) errors)"
	else
		ko "files in no project (code $code)"
		cat "$TMP/projects.err"
	fi
	cp -r tests/projects "$TMP/projects"
	code=0
	(cd "$TMP/projects" && "$ROOT/veslint" --config resolved.json --fixes --fix "${projects_files[@]}") > "$TMP/projects-fix.out" 2> "$TMP/projects-fix.err" || code=$?
	fixed_ok=1
	for file in "${projects_files[@]}"; do
		if grep -qP "^\\Q$file\\E:0:0\t" tests/projects/expected-fix.txt; then
			cmp -s "tests/projects/$file" "$TMP/projects/$file" || fixed_ok=0
		else
			cmp -s <(sed 's/^let /const /' "tests/projects/$file") "$TMP/projects/$file" || fixed_ok=0
		fi
	done
	if [[ $code -eq 1 && $fixed_ok -eq 1 ]] && diff -u tests/projects/expected-fix.txt <(sed "s|$TMP/projects|<tests/projects>|g" "$TMP/projects-fix.out") &&
		grep -qx "$(wc -l < tests/projects/expected-fix.txt) problems in ${#projects_files[@]} files; 8 files fixed" "$TMP/projects-fix.err"; then
		ok "--fix with files in no project: their parsing errors, and the other files fixed"
	else
		ko "--fix with files in no project (code $code, files as expected: $fixed_ok)"
		cat "$TMP/projects-fix.err"
	fi
	# A file --fix cannot write even when it tries again for a while (VESLINT_DEBUG_WRITE_LIMIT_MS
	# shortens the minute it tries for): an error says so, the file keeps its text and its problems
	# are reported, the other files are still fixed, and the run ends with code 1. A read-only file
	# is not tried again (which only root can write).
	for case in locked read-only; do
		rm -rf "$TMP/projects-locked"
		cp -r tests/projects "$TMP/projects-locked"
		env=(VESLINT_DEBUG_WRITE_FAILURES=1000@c.ts VESLINT_DEBUG_WRITE_LIMIT_MS=200)
		if [[ $case == read-only ]]; then
			[[ $(id -u) -eq 0 ]] && continue
			env=(VESLINT_DEBUG_WRITE_LIMIT_MS=60000)
			chmod a-w "$TMP/projects-locked/service/c.ts"
		fi
		code=0
		(cd "$TMP/projects-locked" && env "${env[@]}" "$ROOT/veslint" --config resolved.json --fixes --fix "${projects_files[@]}") > "$TMP/projects-locked.out" 2> "$TMP/projects-locked.err" || code=$?
		# Tried again for a while, or (read-only) once.
		tried=' (VESLINT_DEBUG_WRITE_FAILURES), [0-9]* attempts in 0\.[0-9] s'
		[[ $case == read-only ]] && tried=''
		attempts=$(grep -c "^error: service/c\\.ts: not fixed: failed to open file \"service/c\\.ts\"$tried; its problems are those of the text it has\$" "$TMP/projects-locked.err")
		if [[ $code -eq 1 && $attempts -eq 1 ]] && cmp -s tests/projects/service/c.ts "$TMP/projects-locked/service/c.ts" &&
			cmp -s <(sed 's/^let /const /' tests/projects/service/a.ts) "$TMP/projects-locked/service/a.ts" &&
			diff -u <({ grep -v '^service/c\.ts:' tests/projects/expected-fix.txt; grep '^service/c\.ts:' tests/projects/expected.txt; } | sort) <(sed "s|$TMP/projects-locked|<tests/projects>|g" "$TMP/projects-locked.out" | sort) &&
			grep -qx "$(($(wc -l < tests/projects/expected-fix.txt) + 1)) problems in ${#projects_files[@]} files; 7 files fixed" "$TMP/projects-locked.err"; then
			ok "--fix with a file it cannot write ($case): an error for it, and the other files fixed"
		else
			ko "--fix with a file it cannot write ($case, code $code)"
			cat "$TMP/projects-locked.err"
		fi
	done
	# The server answers as the command line, and so does a JSON with a `rules` section (veslint
	# gets the types of its files as the project service does).
	python3 -c 'import json, sys; print(json.dumps({"id": 1, "config": "resolved.json", "files": sys.argv[1:]}))' "${projects_files[@]/#/$ROOT/tests/projects/}" > "$TMP/server-projects.jsonl"
	code=0
	(cd tests/projects && ../../veslint --config resolved.json --fixes "${projects_files[@]/#/$ROOT/tests/projects/}") > "$TMP/cli-projects.out" 2> "$TMP/cli-projects.err" || code=$?
	if [[ $code -eq 1 ]] && diff -u tests/projects/expected.txt <(sed -e "s|^$ROOT/tests/projects/||" -e "s|$ROOT/tests/projects|<tests/projects>|g" "$TMP/cli-projects.out") &&
		python3 tests/server_client.py ./veslint tests/projects "$TMP/server-projects.jsonl" > "$TMP/server-projects.out" 2> "$TMP/server-projects.err" &&
		python3 - "$TMP/server-projects.out" "$TMP/cli-projects.out" "$TMP/cli-projects.err" "$code" "$PWD/tests/projects" << 'PY'
import json, sys
answer = json.loads(open(sys.argv[1]).readline())
cwd = sys.argv[5]
got = (answer['stdout'].replace('<cwd>', cwd), answer['stderr'].replace('<cwd>', cwd), answer['code'])
sys.exit(0 if got == (open(sys.argv[2]).read(), open(sys.argv[3]).read(), int(sys.argv[4])) else 1)
PY
	then
		ok "--server: files in no project as on the command line"
	else
		ko "--server: files in no project"
		cat "$TMP/server-projects.err"
	fi
	code=0
	(cd tests/projects && ../../veslint --config rules.json --fixes $(printf '%s\n' "${projects_files[@]}" | grep '^service/')) > "$TMP/projects-rules.out" 2> "$TMP/projects-rules.err" || code=$?
	if [[ $code -eq 1 ]] && diff -u <(grep '^service/' tests/projects/expected.txt | sed 's|\\nallowDefaultProject is set to .*||') <(sed "s|$ROOT/tests/projects|<tests/projects>|g" "$TMP/projects-rules.out"); then
		ok "--config rules.json: files in no project as with the project service"
	else
		ko "--config rules.json with files in no project (code $code)"
		cat "$TMP/projects-rules.err"
	fi
	# veslint's own configuration without a rule that needs types, or with `projectService: false`,
	# stands for one ESLint lints without a program: a file in no project is linted (as the upstream
	# tests lint their files outside the fixtures' tsconfig).
	printf '{"rules": {"prefer-const": "error"}, "languageOptions": {"parserOptions": {"projectService": false}}}' > "$TMP/no-service.json"
	b_line=$'service/b.ts:2:5\tprefer-const\tuseConst\t\'b1\' is never reassigned. Use \'const\' instead.\tfix\t44\t55\tconst b1 = 1;\tend\t2\t7'
	untyped_ok=1
	for config in "--rule prefer-const --no-config-lookup" "--config $TMP/no-service.json"; do
		code=0
		(cd tests/projects && ../../veslint $config --fixes service/b.ts) > "$TMP/untyped.out" 2> "$TMP/untyped.err" || code=$?
		[[ $code -eq 1 && $(cat "$TMP/untyped.out") == "$b_line" ]] || untyped_ok=0
	done
	if [[ $untyped_ok -eq 1 ]]; then
		ok "a file in no project with no rule that needs types, or without the project service: linted"
	else
		ko "a file in no project with no rule that needs types, or without the project service"
		cat "$TMP/untyped.out" "$TMP/untyped.err"
	fi
	# Without a tsconfig.json at all: the parsing error, and the run goes on.
	mkdir -p "$TMP/no-tsconfig/src"
	cp tests/projects/service/b.ts "$TMP/no-tsconfig/src/"
	cp tests/projects/rules.json "$TMP/no-tsconfig/"
	code=0
	(cd "$TMP/no-tsconfig" && "$ROOT/veslint" --config rules.json src) > "$TMP/no-tsconfig.out" 2> "$TMP/no-tsconfig.err" || code=$?
	if [[ $code -eq 1 ]] && [[ $(cat "$TMP/no-tsconfig.out") == "src/b.ts:0:0"$'\t'"eslint"$'\t'"fatal"$'\t'"Parsing error: $TMP/no-tsconfig/src/b.ts was not found by the project service. Consider either including it in the tsconfig.json or including it in allowDefaultProject." ]] &&
		grep -qx '1 problems in 1 files' "$TMP/no-tsconfig.err"; then
		ok "a file without a tsconfig.json: ESLint's parsing error"
	else
		ko "a file without a tsconfig.json (code $code)"
		cat "$TMP/no-tsconfig.out" "$TMP/no-tsconfig.err"
	fi
	if command -v bun > /dev/null && [[ -d build/eval/spider-byte/node_modules/eslint ]]; then
		code=0
		(cd tests/projects && VESLINT_ESLINT_DIR=../../build/eval/spider-byte ../../veslint --config eslint.config.mjs --fixes "${projects_files[@]}") > "$TMP/projects-bun.out" 2> "$TMP/projects-bun.err" || code=$?
		if [[ $code -eq 1 ]] && diff -u tests/projects/expected.txt <(sed "s|$ROOT/tests/projects|<tests/projects>|g" "$TMP/projects-bun.out") &&
			(cd tests/projects && VESLINT_ESLINT_DIR=../../build/eval/spider-byte ../../veslint --config eslint.config.mjs --print-config "${projects_files[@]}") | diff -u tests/projects/resolved.json -; then
			ok "files in no project with tests/projects/eslint.config.mjs through bun, and --print-config"
		else
			ko "files in no project through bun (code $code)"
			cat "$TMP/projects-bun.err"
		fi
	fi
else
	echo "skip   files in no project: the messages have the paths as Node writes them on Windows"
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

# A file TypeScript's parser rejects is ESLint's fatal problem, its first syntactic diagnostic at
# its line and 0-based column, and nothing else; one only tree-sitter's grammar does not read
# (`new new Foo()`) is linted on, with a warning when tree-sitter parses it (VESLINT_PARSER=
# tree-sitter) and without one when TypeScript's parser does. Then the --rule warning about nodes
# the rule could not analyze (a chain of 1,002 member accesses goes beyond the limit of 1,000
# nesting levels).
code=0
./veslint --rule no-debugger tests/fixtures/syntax_error.ts > "$TMP/fatal.out" 2> "$TMP/fatal.err" || code=$?
if [[ $code -eq 1 && "$(head -1 "$TMP/fatal.out")" == $'tests/fixtures/syntax_error.ts:2:6\teslint\tfatal\tParsing error: Variable declaration expected.' && "$(wc -l < "$TMP/fatal.out")" -eq 1 ]] && ! grep -q 'syntax errors' "$TMP/fatal.err"; then
	ok "--rule: a syntax error TypeScript reports is ESLint's fatal problem"
else
	ko "--rule: a syntax error TypeScript reports is not ESLint's fatal problem (code $code)"
	cat "$TMP/fatal.out" "$TMP/fatal.err"
fi
mkdir -p "$TMP/grammar-gap"
printf '{"compilerOptions":{"strict":true,"noEmit":true}}\n' > "$TMP/grammar-gap/tsconfig.json"
printf 'new new Foo();\ndebugger;\n' > "$TMP/grammar-gap/gap.ts"
VESLINT_PARSER=tree-sitter ./veslint --rule no-debugger "$TMP/grammar-gap/gap.ts" > "$TMP/warning.out" 2> "$TMP/warning.err"
if grep -q 'syntax errors' "$TMP/warning.err" && grep -q $'\tno-debugger\t' "$TMP/warning.out"; then
	ok "--rule warns about syntax only tree-sitter rejects, and lints on"
else
	ko "--rule: syntax only tree-sitter rejects"
	cat "$TMP/warning.out" "$TMP/warning.err"
fi
VESLINT_PARSER=typescript ./veslint --rule no-debugger "$TMP/grammar-gap/gap.ts" > "$TMP/warning.out" 2> "$TMP/warning.err"
if ! grep -q 'syntax errors' "$TMP/warning.err" && grep -q $'\tno-debugger\t' "$TMP/warning.out"; then
	ok "--rule with TypeScript's parser: syntax tree-sitter rejects, linted without a warning"
else
	ko "--rule with TypeScript's parser: syntax tree-sitter rejects"
	cat "$TMP/warning.out" "$TMP/warning.err"
fi
# A fix that gives code TypeScript cannot parse (without `jsx`, @stylistic/comma-dangle removes the
# comma of `<T,>` in a .tsx file, which makes it a JSX element): like ESLint, --fix writes it, stops
# and reports the parsing error.
mkdir -p "$TMP/broken-fix"
printf '{"compilerOptions":{"strict":true,"noEmit":true,"jsx":"preserve"}}\n' > "$TMP/broken-fix/tsconfig.json"
printf 'export const f = <T,>(x: T) => x;\n' > "$TMP/broken-fix/generic.tsx"
./veslint --fix --rule @stylistic/comma-dangle --no-config-lookup "$TMP/broken-fix/generic.tsx" > "$TMP/broken-fix.out" 2> /dev/null
if [[ $(< "$TMP/broken-fix/generic.tsx") == 'export const f = <T>(x: T) => x;' ]] &&
	grep -qP ':1:28\teslint\tfatal\tParsing error: Unexpected token' "$TMP/broken-fix.out"; then
	ok "--fix stops at a fix TypeScript cannot parse"
else
	ko "--fix stops at a fix TypeScript cannot parse"
	cat "$TMP/broken-fix/generic.tsx" "$TMP/broken-fix.out"
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
# turns on a rule that needs them or (tree-sitter's rows) an `await` may be a name: the output is
# the one of a run with a snapshot from the start (one rule with types more, which reports nothing
# there). With tree-sitter's rows, the program (which reads await-script.ts as a script, having
# no import or export) tells that `await (1)` calls the function `await`; with TypeScript's, the
# file is the module ESLint's default sourceType makes it and `await (1)` an await expression, so
# no-use-before-define reports nothing there, as ESLint (with sourceType "script" it reports it).
printf '{"rules": {"@typescript-eslint/no-this-alias": ["error"], "@typescript-eslint/no-use-before-define": ["error"]}}' > "$TMP/untyped.json"
printf '{"rules": {"@typescript-eslint/no-this-alias": ["error"], "@typescript-eslint/no-use-before-define": ["error"], "@typescript-eslint/no-array-delete": ["error"]}}' > "$TMP/typed.json"
lazy_files=(tests/lazy-snapshot/plain.ts tests/lazy-snapshot/inline.ts tests/lazy-snapshot/await-script.ts)
for parser in tree-sitter typescript; do
	VESLINT_PARSER=$parser ./veslint --config "$TMP/untyped.json" "${lazy_files[@]}" > "$TMP/lazy.out" 2> /dev/null
	VESLINT_PARSER=$parser ./veslint --config "$TMP/typed.json" "${lazy_files[@]}" > "$TMP/eager.out" 2> /dev/null
	await_name=0
	grep -q $'await-script.ts:3:1\t@typescript-eslint/no-use-before-define' "$TMP/lazy.out" && await_name=1
	if cmp -s "$TMP/lazy.out" "$TMP/eager.out" \
		&& grep -q $'inline.ts:4:1\t@typescript-eslint/no-floating-promises' "$TMP/lazy.out" \
		&& [[ $await_name -eq $([[ $parser == tree-sitter ]] && echo 1 || echo 0) ]]; then
		ok "rules without types ($parser's rows): the output of a run with a snapshot"
	else
		ko "rules without types ($parser's rows): the output of a run with a snapshot"
		diff "$TMP/eager.out" "$TMP/lazy.out"
	fi
done
./veslint --bench --config "$TMP/untyped.json" tests/lazy-snapshot/plain.ts > /dev/null 2> "$TMP/lazy.bench"
if grep -q '"tsgo_requests":2[,}]' "$TMP/lazy.bench"; then
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
for javascript_file in component.jsx script.js module.mjs common.cjs styles.css notes.md; do
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
	# --rule takes the options of the rule from the closest eslint.config.mjs (eqeqeq "smart" lets
	# `== null` be), and only its own directive comments can be unused: --fix leaves the others.
	mkdir -p "$TMP/rule-config"
	cat > "$TMP/rule-config/eslint.config.mjs" <<-EOF
		import tseslint from '$PWD/build/eval/spider-byte/node_modules/typescript-eslint/dist/index.js';
		export default [{
		  files: ['**/*.ts'],
		  languageOptions: { parser: tseslint.parser },
		  plugins: { '@typescript-eslint': tseslint.plugin },
		  rules: { 'prefer-const': 'error', 'no-var': 'error', eqeqeq: ['error', 'smart'], '@typescript-eslint/no-explicit-any': 'error' },
		}];
	EOF
	cat > "$TMP/rule-config/a.ts" <<-'EOF'
		// eslint-disable-next-line @typescript-eslint/no-explicit-any
		export const x: any = 1;
		let y = 2; // eslint-disable-line prefer-const
		var z = 3; // eslint-disable-line no-var
		let w = 4;
		export const q = y == null ? w : z;
		export const r = y == 2;
		export const k = 1; // eslint-disable-line no-var
	EOF
	echo '{ "compilerOptions": { "strict": true, "target": "es2022", "module": "esnext" } }' > "$TMP/rule-config/tsconfig.json"
	cp "$TMP/rule-config/a.ts" "$TMP/rule-config/a.orig"
	rule_config() { (cd "$TMP/rule-config" && VESLINT_ESLINT_DIR="$OLDPWD/build/eval/spider-byte" "$OLDPWD/veslint" "$@" 2>&1); }
	if [[ "$(rule_config --rule eqeqeq a.ts)" == $'a.ts:7:20\teqeqeq\tunexpected\tExpected \'===\' and instead saw \'==\'.\n1 problems in 1 files' ]] &&
		[[ "$(rule_config --rule eqeqeq --no-config-lookup a.ts | grep -c eqeqeq)" == 2 ]] &&
		[[ "$(rule_config --rule no-var a.ts)" == *"a.ts:8:21"*"Unused eslint-disable directive (no problems were reported from 'no-var')."* ]] &&
		[[ "$(rule_config --rule prefer-const --fix a.ts)" == '0 problems in 1 files; 1 files fixed' ]] &&
		diff -u <(sed 's/^let w/const w/' "$TMP/rule-config/a.orig") "$TMP/rule-config/a.ts"; then
		ok "--rule: the options of the closest eslint.config.mjs, and --fix keeps the directives of other rules"
	else
		ko "--rule with the closest eslint.config.mjs"
		rule_config --rule eqeqeq a.ts
		rule_config --rule no-var a.ts
	fi
	# A directive comment that names a rule of a plugin the configuration does not load, typescript-eslint
	# included, is ESLint's "Definition for rule … was not found" (not an unused directive).
	mkdir -p "$TMP/no-plugin"
	cat > "$TMP/no-plugin/eslint.config.mjs" <<-EOF
		import tseslint from '$PWD/build/eval/spider-byte/node_modules/typescript-eslint/dist/index.js';
		export default [{ files: ['**/*.ts'], languageOptions: { parser: tseslint.parser }, rules: { 'no-var': 'error' } }];
	EOF
	cat > "$TMP/no-plugin/a.ts" <<-'EOF'
		// eslint-disable-next-line @typescript-eslint/no-explicit-any
		export const x: any = 1;
		// eslint-disable-next-line no-var, @typescript-eslint/no-unused-vars
		var y = 2;
		/* eslint @typescript-eslint/no-explicit-any: "error" */
		export { y };
	EOF
	echo '{ "compilerOptions": { "strict": true, "target": "es2022", "module": "esnext" } }' > "$TMP/no-plugin/tsconfig.json"
	if [[ "$(cd "$TMP/no-plugin" && VESLINT_ESLINT_DIR="$OLDPWD/build/eval/spider-byte" "$OLDPWD/veslint" --config eslint.config.mjs a.ts 2> /dev/null)" == $'a.ts:1:1\t@typescript-eslint/no-explicit-any\terror\tDefinition for rule \'@typescript-eslint/no-explicit-any\' was not found.\na.ts:3:1\t@typescript-eslint/no-unused-vars\terror\tDefinition for rule \'@typescript-eslint/no-unused-vars\' was not found.\na.ts:5:1\t@typescript-eslint/no-explicit-any\terror\tDefinition for rule \'@typescript-eslint/no-explicit-any\' was not found.' ]]; then
		ok "a directive for a rule of a plugin the eslint.config.mjs does not load: the rule is not found"
	else
		ko "a directive for a rule of a plugin the eslint.config.mjs does not load"
		(cd "$TMP/no-plugin" && VESLINT_ESLINT_DIR="$OLDPWD/build/eval/spider-byte" "$OLDPWD/veslint" --config eslint.config.mjs a.ts)
	fi
	# The cache of resolved configurations (config_cache.v), in node_modules/.cache/veslint of the
	# project: a resolution is used again, without bun (a `bun` that fails comes first in PATH), until
	# what it came from changes: a module the configuration imports, a file it reads, an environment
	# variable it reads, or (looking the configuration up) the closest eslint.config.* of a directory.
	# VESLINT_CONFIG_CACHE=0 turns it off.
	cache_project="$TMP/cache-project"
	mkdir -p "$cache_project/node_modules" "$cache_project/src" "$TMP/failing-bun"
	printf '#!/bin/sh\necho "the bun of the test ran" >&2\nexit 3\n' > "$TMP/failing-bun/bun"
	chmod +x "$TMP/failing-bun/bun"
	cat > "$cache_project/eslint.config.mjs" <<-'EOF'
		import fs from 'node:fs';
		import severity from './severity.mjs';
		const extra = JSON.parse(fs.readFileSync(new URL('./extra.json', import.meta.url), 'utf8'));
		export default [{ files: ['**/*.ts'], rules: { 'no-debugger': severity, eqeqeq: process.env.VESLINT_TEST_EQEQEQ ?? 'off', ...extra } }];
	EOF
	echo "export default 'error';" > "$cache_project/severity.mjs"
	echo '{ "no-var": "warn" }' > "$cache_project/extra.json"
	echo 'debugger;' > "$cache_project/src/a.ts"
	# resolved [bun|cached|uncached] ARGS...: --print-config in the project, with the cache, with the
	# failing bun first in PATH, or without the cache; the rules of src/a.ts, or the error.
	resolved() {
		local mode=$1 path=$PATH cache=1
		shift
		[[ $mode == bun ]] || path="$TMP/failing-bun:$PATH"
		[[ $mode != uncached ]] || cache=0
		(cd "$cache_project" && PATH="$path" VESLINT_CONFIG_CACHE=$cache VESLINT_ESLINT_DIR="$ROOT/build/eval/spider-byte" \
			"$ROOT/veslint" --print-config "$@" 2>&1) | python3 -I -c '
import json, sys
text = sys.stdin.read()
try:
	resolved = json.loads(text)
except ValueError:
	print(text.strip().splitlines()[0] if text.strip() else "(nothing)")
	sys.exit()
entry = next(f for f in resolved["files"] if f["path"] == "src/a.ts")
print(json.dumps(resolved["configs"][entry["config"]]["rules"], sort_keys=True))'
	}
	config_mode=(--config eslint.config.mjs src/a.ts)
	first=$(resolved bun "${config_mode[@]}")
	again=$(resolved cached "${config_mode[@]}")
	off=$(resolved uncached "${config_mode[@]}")
	echo "export default 'warn';" > "$cache_project/severity.mjs"
	module=$(resolved cached "${config_mode[@]}")
	module_bun=$(resolved bun "${config_mode[@]}")
	echo '{ "no-var": "error" }' > "$cache_project/extra.json"
	read_file=$(resolved cached "${config_mode[@]}")
	resolved bun "${config_mode[@]}" > /dev/null
	env_cached=$(VESLINT_TEST_EQEQEQ=error resolved cached "${config_mode[@]}")
	env_bun=$(VESLINT_TEST_EQEQEQ=error resolved bun "${config_mode[@]}")
	resolved bun . > /dev/null
	lookup_again=$(resolved cached .)
	echo 'export default [];' > "$cache_project/src/eslint.config.mjs"
	lookup_new=$(resolved cached .)
	rm "$cache_project/src/eslint.config.mjs"
	# What the failing bun gives.
	failed='(bun exited with code 3)'
	if [[ $first == *'"no-debugger": [2]'* && $first == *'"no-var": [1]'* && $again == "$first" &&
		$off == *"$failed"* && $module == *"$failed"* && $module_bun == *'"no-debugger": [1]'* &&
		$read_file == *"$failed"* && $env_cached == *"$failed"* && $env_bun == *'"eqeqeq": [2'* &&
		$lookup_again == *'"no-debugger": [1]'* && $lookup_new == *"$failed"* &&
		-n $(ls "$cache_project/node_modules/.cache/veslint"/config-*.json) ]]; then
		ok "the cache of resolved configurations, and what makes it resolve again"
	else
		ko "the cache of resolved configurations"
		printf '%s\n' "first $first" "again $again" "off $off" "module $module" "module_bun $module_bun" \
			"read_file $read_file" "env_cached $env_cached" "env_bun $env_bun" "lookup_again $lookup_again" "lookup_new $lookup_new"
	fi
	# A request of the server takes the resolution of its files out of the entry of a run on more
	# files (a bun that fails comes first in PATH); a file that no entry has needs bun.
	printf 'var b = 1;\ndebugger;\n' > "$cache_project/src/b.ts"
	echo '{"include": ["src"]}' > "$cache_project/tsconfig.json"
	echo 'debugger;' > "$cache_project/src/c.ts"
	(cd "$cache_project" && VESLINT_CONFIG_CACHE=1 VESLINT_ESLINT_DIR="$ROOT/build/eval/spider-byte" "$ROOT/veslint" --config eslint.config.mjs src/a.ts src/b.ts > /dev/null 2>&1)
	printf '%s\n' '{"id": 1, "config": "eslint.config.mjs", "files": ["src/b.ts"]}' \
		'{"id": 2, "config": "eslint.config.mjs", "files": ["src/b.ts", "src/a.ts"]}' \
		'{"id": 3, "config": "eslint.config.mjs", "files": ["src/c.ts"]}' > "$TMP/cache-server.jsonl"
	(cd "$cache_project" && PATH="$TMP/failing-bun:$PATH" VESLINT_CONFIG_CACHE=1 VESLINT_ESLINT_DIR="$ROOT/build/eval/spider-byte" \
		python3 "$ROOT/tests/server_client.py" "$ROOT/veslint" . "$TMP/cache-server.jsonl") > "$TMP/cache-server.out" 2>&1
	subset_cli() { (cd "$cache_project" && VESLINT_CONFIG_CACHE=0 VESLINT_ESLINT_DIR="$ROOT/build/eval/spider-byte" "$ROOT/veslint" --config eslint.config.mjs --fixes "$@" 2>&1); }
	subset_answer() { python3 -I -c 'import json, sys; a = json.loads(open(sys.argv[1]).readlines()[int(sys.argv[2])]); print(a["stdout"] + a["stderr"], end="")' "$TMP/cache-server.out" "$1"; }
	if [[ $(subset_answer 0) == "$(subset_cli src/b.ts)" && $(subset_answer 1) == "$(subset_cli src/b.ts src/a.ts)" &&
		$(subset_answer 2) == *"$failed"* ]]; then
		ok "the server takes the resolution of its files out of a cached resolution of more files"
	else
		ko "the server takes the resolution of its files out of a cached resolution of more files"
		cat "$TMP/cache-server.out"
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
# A resolved configuration saved outside the project: its paths, relative to its folder, lead nowhere.
mkdir -p "$TMP/elsewhere"
cp tests/config/resolved.json "$TMP/elsewhere/"
expect_usage_error "a resolved configuration saved outside the project names where its paths start" \
	"tests/config/base.ts is not in the resolved configuration (its relative paths start at $TMP/elsewhere)" \
	--config "$TMP/elsewhere/resolved.json" tests/config/base.ts
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

# Vue files (vue_files.v, rules/vue_file.v): the TypeScript scripts of tests/vue-lint/fixtures, with
# every rule of tests/vue-lint/rules.json and the types of their project, give what ESLint gives
# with vue-eslint-parser and typescript-eslint's parser: the problems with their fixes and
# suggestions (tests/vue-lint/expected.txt), and --fix the files and the problems of
# tests/vue-lint/fixed (both pinned from ESLint by tests/vue-lint/pin.sh; tests/vue-lint/compare.sh
# compares thousands of SFCs). The server answers what the command line prints for them, the
# identifier mode reads their scripts, and a .vue file whose script is JavaScript is not linted.
code=0
(cd tests/vue-lint/fixtures && ../../../veslint --config ../rules.json --fixes ./*.vue) > "$TMP/vue.out" 2> "$TMP/vue.err" || code=$?
if [[ $code -eq 1 ]] && diff -u tests/vue-lint/expected.txt <(sed 's|^\./||' "$TMP/vue.out" | sorted); then
	ok "Vue files: ESLint's problems, fixes and suggestions ($(wc -l < tests/vue-lint/expected.txt) lines)"
else
	ko "Vue files: not ESLint's problems (code $code)"
	cat "$TMP/vue.err"
fi
mkdir -p "$TMP/vue-fix"
cp tests/vue-lint/fixtures/*.vue tests/vue-lint/fixtures/*.ts tests/vue-lint/fixtures/tsconfig.json "$TMP/vue-fix/"
code=0
(cd "$TMP/vue-fix" && "$ROOT/veslint" --config "$ROOT/tests/vue-lint/rules.json" --fix --fixes ./*.vue) > "$TMP/vue-fix.out" 2> "$TMP/vue-fix.err" || code=$?
vue_fixed=1
for file in tests/vue-lint/fixtures/*.vue; do
	cmp -s "tests/vue-lint/fixed/${file##*/}" "$TMP/vue-fix/${file##*/}" || { vue_fixed=0; diff -u "tests/vue-lint/fixed/${file##*/}" "$TMP/vue-fix/${file##*/}"; }
done
if [[ $code -eq 1 && $vue_fixed -eq 1 ]] && diff -u tests/vue-lint/fixed/expected.txt <(sed 's|^\./||' "$TMP/vue-fix.out" | sorted); then
	ok "Vue files: --fix leaves the files and the problems eslint --fix leaves"
else
	ko "Vue files: --fix (code $code)"
	cat "$TMP/vue-fix.err"
fi
python3 -c 'import json, sys; print(json.dumps({"id": 1, "config": "../rules.json", "files": sys.argv[1:]}))' tests/vue-lint/fixtures/*.vue |
	sed 's|tests/vue-lint/fixtures/|<cwd>/|g' > "$TMP/vue-server.jsonl"
code=0
(cd tests/vue-lint/fixtures && ../../../veslint --config ../rules.json --fixes "$PWD"/*.vue) > "$TMP/vue-cli.out" 2> "$TMP/vue-cli.err" || code=$?
if python3 tests/server_client.py ./veslint tests/vue-lint/fixtures "$TMP/vue-server.jsonl" > "$TMP/vue-server.out" 2> "$TMP/vue-server.err" &&
	python3 - "$TMP/vue-server.out" "$TMP/vue-cli.out" "$TMP/vue-cli.err" "$code" "$PWD/tests/vue-lint/fixtures" << 'PY'
import json, sys
answer = json.loads(open(sys.argv[1]).readline())
cwd = sys.argv[5]
got = (answer['stdout'].replace('<cwd>', cwd), answer['stderr'].replace('<cwd>', cwd), answer['code'])
sys.exit(0 if got == (open(sys.argv[2]).read(), open(sys.argv[3]).read(), int(sys.argv[4])) else 1)
PY
then
	ok "Vue files: --server answers what the command line prints"
else
	ko "Vue files: --server does not answer what the command line prints"
	cat "$TMP/vue-server.err"
fi
if (cd tests/vue-lint/fixtures && ../../../veslint both-scripts.vue) > "$TMP/vue-types.out" 2> "$TMP/vue-types.err" &&
	grep -qP '^both-scripts\.vue:9:5\tcount\tnumber$' "$TMP/vue-types.out"; then
	ok "Vue files: the identifiers of a script and their types"
else
	ko "Vue files: the identifiers of a script and their types"
	cat "$TMP/vue-types.err"
fi
mkdir -p "$TMP/vue-javascript"
printf '<script>\nvar a = 1\n</script>\n' > "$TMP/vue-javascript/App.vue"
cp tests/vue-lint/fixtures/tsconfig.json "$TMP/vue-javascript/"
code=0
(cd "$TMP/vue-javascript" && "$ROOT/veslint" --rule no-var App.vue) > "$TMP/vue-javascript.out" 2> "$TMP/vue-javascript.err" || code=$?
if [[ $code -eq 0 && ! -s "$TMP/vue-javascript.out" ]] && grep -qF 'warning: App.vue: not linted: its <script> is JavaScript' "$TMP/vue-javascript.err"; then
	ok "Vue files: a JavaScript script is not linted, with a warning"
else
	ko "Vue files: a JavaScript script (code $code)"
	cat "$TMP/vue-javascript.out" "$TMP/vue-javascript.err"
fi
# parserOptions.vueFeatures (filter, interpolationAsNonHTML, styleCSSVariableInjection, customMacros,
# each read as vue-eslint-parser reads it), as ESLint gives it for each configuration of
# tests/vue-lint/features (pinned by its pin.sh); and through an eslint.config.mjs, whose resolution
# by ESLint keeps them (and svelteFeatures and svelteConfig: the runes of tests/svelte-lint/runes).
features_configs=(css-off falsy filter-off interpolation-off jsx jsx-no-program macros none)
features_files=(filters.vue interpolation.vue jsx.vue jsx-both.vue macros.vue style.vue)
for config in "${features_configs[@]}"; do
	(cd tests/vue-lint/features && ../../../veslint --config "$config.json" --fixes "${features_files[@]}" 2> /dev/null) |
		sed "s|^|$config: |"
done | sorted > "$TMP/vue-features.out"
if diff -u tests/vue-lint/features/expected.txt "$TMP/vue-features.out"; then
	ok "Vue files: the vueFeatures of parserOptions"
else
	ko "Vue files: the vueFeatures of parserOptions"
fi
if command -v bun > /dev/null && [[ -d build/eval/spider-byte/node_modules/eslint ]]; then
	(cd tests/vue-lint/features && FEATURES_CONFIG=$PWD/falsy.json VESLINT_ESLINT_DIR=../../../build/eval/spider-byte \
		../../../veslint --config eslint.features.config.mjs --fixes "${features_files[@]}" 2> "$TMP/vue-features-bun.err") |
		sed 's|^|falsy: |' | sorted > "$TMP/vue-features-bun.out"
	for config in config-true features-false; do
		(cd tests/svelte-lint/runes && RUNES_CONFIG=$PWD/$config.json VESLINT_ESLINT_DIR=../../../build/eval/spider-byte \
			../../../veslint --config eslint.runes.config.mjs --fixes jsx-assertion.svelte jsx-script.svelte jsx-template.svelte options.svelte plain.svelte 2>> "$TMP/vue-features-bun.err") |
			sed "s|^|$config: |"
	done | sorted > "$TMP/svelte-features-bun.out"
	if diff -u <(grep '^falsy: ' tests/vue-lint/features/expected.txt) "$TMP/vue-features-bun.out" &&
		diff -u <(grep -E '^(config-true|features-false): ' tests/svelte-lint/runes/expected.txt) "$TMP/svelte-features-bun.out"; then
		ok "vueFeatures, svelteFeatures and svelteConfig of an eslint.config.mjs resolved through bun"
	else
		ko "vueFeatures, svelteFeatures and svelteConfig of an eslint.config.mjs resolved through bun"
		cat "$TMP/vue-features-bun.err"
	fi
	# A runes function of the file name in the svelteConfig of an eslint.config.mjs: the resolver
	# calls it for each .svelte file as svelte-eslint-parser and eslint-plugin-svelte do, from the
	# command line and from --server.
	runes_function_files='"legacy-warn.svelte", "legacy.svelte", "options.svelte", "plain.svelte", "warn.svelte"'
	(cd tests/svelte-lint/runes && VESLINT_ESLINT_DIR=../../../build/eval/spider-byte \
		../../../veslint --config eslint.runes-function.config.mjs --fixes legacy-warn.svelte legacy.svelte options.svelte plain.svelte warn.svelte 2> "$TMP/svelte-runes-function.err") |
		sed 's|^|function: |' | sorted > "$TMP/svelte-runes-function.out"
	printf '{"id": 1, "config": "eslint.runes-function.config.mjs", "files": [%s]}\n' "$runes_function_files" > "$TMP/svelte-runes-function.jsonl"
	if diff -u <(grep '^function: ' tests/svelte-lint/runes/expected.txt) "$TMP/svelte-runes-function.out" &&
		VESLINT_ESLINT_DIR=$PWD/build/eval/spider-byte python3 tests/server_client.py ./veslint tests/svelte-lint/runes "$TMP/svelte-runes-function.jsonl" > "$TMP/svelte-runes-function-server.out" 2>> "$TMP/svelte-runes-function.err" &&
		diff -u <(grep '^function: ' tests/svelte-lint/runes/expected.txt) <(python3 -c '
import json, sys
for out in json.loads(open(sys.argv[1], encoding="utf-8").readline())["stdout"].splitlines():
    print(f"function: {out}")
' "$TMP/svelte-runes-function-server.out" | sorted); then
		ok "Svelte files: a runes function of the svelteConfig of an eslint.config.mjs, called for each file"
	else
		ko "Svelte files: a runes function of the svelteConfig of an eslint.config.mjs"
		cat "$TMP/svelte-runes-function.err"
	fi
fi

# Svelte files (svelte_files.v, rules/svelte_file.v): the scripts and the template expressions of
# tests/svelte-lint/fixtures, with every rule of tests/svelte-lint/rules.json and the types of their
# project, give what ESLint gives with svelte-eslint-parser and typescript-eslint's parser: the
# problems with their fixes and suggestions (tests/svelte-lint/expected.txt), and --fix the files and
# the problems of tests/svelte-lint/fixed (both pinned from ESLint by tests/svelte-lint/pin.sh;
# tests/svelte-lint/compare.sh compares thousands of files). The server answers what the command line
# prints for them, the identifier mode reads them, an import of a component is the `*.svelte`
# module, and a .svelte file whose script is JavaScript is not linted. A `.svelte.ts` module is
# linted as svelte-eslint-parser reads one (the runes are declared for typescript-eslint).
code=0
(cd tests/svelte-lint/fixtures && ../../../veslint --config ../rules.json --fixes ./*.svelte ./*.svelte.ts) > "$TMP/svelte.out" 2> "$TMP/svelte.err" || code=$?
if [[ $code -eq 1 ]] && diff -u tests/svelte-lint/expected.txt <(sed 's|^\./||' "$TMP/svelte.out" | sorted); then
	ok "Svelte files: ESLint's problems, fixes and suggestions ($(wc -l < tests/svelte-lint/expected.txt) lines)"
else
	ko "Svelte files: not ESLint's problems (code $code)"
	cat "$TMP/svelte.err"
fi
mkdir -p "$TMP/svelte-fix"
cp tests/svelte-lint/fixtures/*.svelte tests/svelte-lint/fixtures/*.ts tests/svelte-lint/fixtures/tsconfig.json "$TMP/svelte-fix/"
code=0
(cd "$TMP/svelte-fix" && "$ROOT/veslint" --config "$ROOT/tests/svelte-lint/rules.json" --fix --fixes ./*.svelte ./*.svelte.ts) > "$TMP/svelte-fix.out" 2> "$TMP/svelte-fix.err" || code=$?
svelte_fixed=1
for file in tests/svelte-lint/fixtures/*.svelte tests/svelte-lint/fixtures/*.svelte.ts; do
	cmp -s "tests/svelte-lint/fixed/${file##*/}" "$TMP/svelte-fix/${file##*/}" || { svelte_fixed=0; diff -u "tests/svelte-lint/fixed/${file##*/}" "$TMP/svelte-fix/${file##*/}"; }
done
if [[ $code -eq 1 && $svelte_fixed -eq 1 ]] && diff -u tests/svelte-lint/fixed/expected.txt <(sed 's|^\./||' "$TMP/svelte-fix.out" | sorted); then
	ok "Svelte files: --fix leaves the files and the problems eslint --fix leaves"
else
	ko "Svelte files: --fix (code $code)"
	cat "$TMP/svelte-fix.err"
fi
python3 -c 'import json, sys; print(json.dumps({"id": 1, "config": "../rules.json", "files": sys.argv[1:]}))' tests/svelte-lint/fixtures/*.svelte tests/svelte-lint/fixtures/*.svelte.ts |
	sed 's|tests/svelte-lint/fixtures/|<cwd>/|g' > "$TMP/svelte-server.jsonl"
code=0
(cd tests/svelte-lint/fixtures && ../../../veslint --config ../rules.json --fixes "$PWD"/*.svelte "$PWD"/*.svelte.ts) > "$TMP/svelte-cli.out" 2> "$TMP/svelte-cli.err" || code=$?
if python3 tests/server_client.py ./veslint tests/svelte-lint/fixtures "$TMP/svelte-server.jsonl" > "$TMP/svelte-server.out" 2> "$TMP/svelte-server.err" &&
	python3 - "$TMP/svelte-server.out" "$TMP/svelte-cli.out" "$TMP/svelte-cli.err" "$code" "$PWD/tests/svelte-lint/fixtures" << 'PY'
import json, sys
answer = json.loads(open(sys.argv[1]).readline())
cwd = sys.argv[5]
got = (answer['stdout'].replace('<cwd>', cwd), answer['stderr'].replace('<cwd>', cwd), answer['code'])
sys.exit(0 if got == (open(sys.argv[2]).read(), open(sys.argv[3]).read(), int(sys.argv[4])) else 1)
PY
then
	ok "Svelte files: --server answers what the command line prints"
else
	ko "Svelte files: --server does not answer what the command line prints"
	cat "$TMP/svelte-server.err"
fi
if (cd tests/svelte-lint/fixtures && ../../../veslint runes.svelte util.ts) > "$TMP/svelte-types.out" 2> "$TMP/svelte-types.err" &&
	grep -qP '^runes\.svelte:34:17\titem\tstring$' "$TMP/svelte-types.out" &&
	grep -qP '^util\.ts:5:14\tcomponent\tComponent<Record<string, unknown>, Record<string, never>>$' "$TMP/svelte-types.out"; then
	ok "Svelte files: the identifiers of a component and their types; an import of one is the *.svelte module"
else
	ko "Svelte files: the identifiers of a component and their types"
	cat "$TMP/svelte-types.err"
fi
mkdir -p "$TMP/svelte-javascript"
printf '<script>\nvar a = 1\n</script>\n<p>{a}</p>\n' > "$TMP/svelte-javascript/App.svelte"
cp tests/svelte-lint/fixtures/tsconfig.json "$TMP/svelte-javascript/"
code=0
(cd "$TMP/svelte-javascript" && "$ROOT/veslint" --rule no-var App.svelte) > "$TMP/svelte-javascript.out" 2> "$TMP/svelte-javascript.err" || code=$?
if [[ $code -eq 0 && ! -s "$TMP/svelte-javascript.out" ]] && grep -qF 'warning: App.svelte: not linted: its <script> is JavaScript' "$TMP/svelte-javascript.err"; then
	ok "Svelte files: a JavaScript script is not linted, with a warning"
else
	ko "Svelte files: a JavaScript script (code $code)"
	cat "$TMP/svelte-javascript.out" "$TMP/svelte-javascript.err"
fi
# svelte/system: the rules settings.svelte.ignoreWarnings names (exactly, or by a `/regexp/`) are
# disabled outside the scripts, and an ignoreWarnings that is not an array of strings is reported,
# as ESLint gives them with eslint-plugin-svelte's processor (tests/rules/svelte/system/settings:
# a configuration of each kind and what ESLint gave, pinned).
: > "$TMP/svelte-system.out"
for config in ok bad num; do
	(cd tests/rules/svelte/system/settings && ../../../../../veslint --config "$config.json" sys.svelte 2> /dev/null) |
		sed "s|^|$config: |" >> "$TMP/svelte-system.out"
done
if diff -u tests/rules/svelte/system/settings/ignore-warnings.txt "$TMP/svelte-system.out"; then
	ok "svelte/system: settings.svelte.ignoreWarnings"
else
	ko "svelte/system: settings.svelte.ignoreWarnings"
fi
# Runes mode while parsing (svelteParseContext.runes: rune declarations in the virtual code, rune
# globals, the $props scope): parserOptions.svelteFeatures.runes, else <svelte:options runes>, else
# the svelteConfig's compilerOptions.runes (parserOptions.svelteConfig, else svelte.config.js, which
# says false there), as ESLint gives it for each configuration of tests/svelte-lint/runes (pinned
# by its pin.sh), from the command line and from one --server that lints with each in turn; and
# where parserOptions.ecmaFeatures.jsx makes svelte-eslint-parser's parses read JSX (the jsx-*
# files: the first parse with JSX, the virtual code's too without a program, the compiler's
# template expressions never).
: > "$TMP/svelte-runes.out"
: > "$TMP/svelte-runes-server.jsonl"
runes_configs=(config-no-runes config-true features-false features-true jsx jsx-no-program none)
for config in "${runes_configs[@]}"; do
	(cd tests/svelte-lint/runes && ../../../veslint --config "$config.json" --fixes jsx-assertion.svelte jsx-script.svelte jsx-template.svelte options.svelte plain.svelte 2> /dev/null) |
		sed "s|^|$config: |" >> "$TMP/svelte-runes.out"
	printf '{"id": 1, "config": "%s.json", "files": ["jsx-assertion.svelte", "jsx-script.svelte", "jsx-template.svelte", "options.svelte", "plain.svelte"]}\n' "$config" >> "$TMP/svelte-runes-server.jsonl"
done
if diff -u <(grep -v '^function: ' tests/svelte-lint/runes/expected.txt) <(sorted "$TMP/svelte-runes.out"); then
	ok "Svelte files: runes mode from svelteFeatures.runes, <svelte:options>, svelteConfig and svelte.config.js"
else
	ko "Svelte files: runes mode from svelteFeatures.runes, <svelte:options>, svelteConfig and svelte.config.js"
fi
if python3 tests/server_client.py ./veslint tests/svelte-lint/runes "$TMP/svelte-runes-server.jsonl" > "$TMP/svelte-runes-server.out" 2> "$TMP/svelte-runes-server.err" &&
	python3 -c '
import json, sys
for config, line in zip(sys.argv[2:], open(sys.argv[1], encoding="utf-8")):
    for out in json.loads(line)["stdout"].splitlines():
        print(f"{config}: {out}")
' "$TMP/svelte-runes-server.out" "${runes_configs[@]}" | sorted > "$TMP/svelte-runes-server.lines" &&
	diff -u <(grep -v '^function: ' tests/svelte-lint/runes/expected.txt) "$TMP/svelte-runes-server.lines"; then
	ok "Svelte files: --server parses with the runes mode of each configuration"
else
	ko "Svelte files: --server and the runes mode of each configuration"
	cat "$TMP/svelte-runes-server.err"
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

phase "directives, --fix, configurations and the command line"
# `eslint --print-config`: numeric severities, the core require-await rule turned off and rules of
# other plugins), with every rule of tests/rules and its default options.
mapfile -t all_cases < <(find tests/rules -name cases.ts -o -name cases.tsx -o -name cases.vue -o -name cases.svelte | sorted)
[[ $seyfert_skipped -eq 0 ]] || mapfile -t all_cases < <(printf '%s\n' "${all_cases[@]}" | grep -v '^tests/rules/seyfert/')
cat > "$TMP/all.json" << 'JSON'
{"rules": {
  "@typescript-eslint/no-floating-promises": [2], "@typescript-eslint/await-thenable": [2],
  "require-await": [0], "@typescript-eslint/require-await": [2],
  "@typescript-eslint/return-await": [2, "in-try-catch"], "@typescript-eslint/no-misused-promises": [2],
  "@typescript-eslint/no-unsafe-argument": [2], "@typescript-eslint/no-unsafe-assignment": [2],
  "@typescript-eslint/no-unsafe-call": [2], "@typescript-eslint/no-unsafe-member-access": [2, {"allowOptionalChaining": false}],
  "@typescript-eslint/no-unsafe-return": [2], "semi": [2, "always"], "@stylistic/indent-binary-ops": [1, 2]
JSON
# A rule whose schema needs options (tests/rules/required_options.json) gets those.
python3 -c 'import json; [print(f", \"{r}\": {json.dumps([2, *o])}") for r, o in json.load(open("tests/rules/required_options.json")).items()]' >> "$TMP/all.json"
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
# Each rule alone on every fixture (458 runs over 1,529 fixtures, most of the time of `make test`) only
# with VESLINT_MATRIX=1, which the battery of a release sets; without it, every rule at once.
matrix_dirs=()
[[ ${VESLINT_MATRIX:-0} != 1 ]] || matrix_dirs=("${rule_dirs[@]}")
# alone_args rule n: the arguments that run one rule alone: `--rule`, or, for a rule whose schema
# needs options, a configuration with the options all.json gives it.
alone_args() {
	if grep -q "\"$1\"" tests/rules/required_options.json; then
		python3 -c 'import json, sys; o = json.load(open("tests/rules/required_options.json"))[sys.argv[1]]; print(json.dumps({"rules": {sys.argv[1]: [2, *o]}}))' "$1" > "$TMP/alone.$2.json"
		echo --config "$TMP/alone.$2.json"
	else
		echo --rule "$1" --no-config-lookup
	fi
}
jobs_started=0
for dir in "${matrix_dirs[@]}"; do
	throttle
	: > "$TMP/per-rule.$jobs_started.out"
	: > "$TMP/per-rule.$jobs_started.err"
	(
		code=0
		veslint_batched "$TMP/per-rule.$jobs_started.out" "$TMP/per-rule.$jobs_started.err" $(alone_args "${dir#tests/rules/}" $jobs_started) -- "${all_cases[@]}" || code=$?
		echo "$code" > "$TMP/per-rule.$jobs_started.code"
	) &
	jobs_started=$((jobs_started + 1))
done
wait
# A run that failed (a timeout of tsgo, or tsgo dying, under the load of the runs side by side:
# veslint reports it, goes on with the other files and exits with 1 when it found problems) runs
# again alone, so that its findings are not missing from the comparison; a second failure is
# reported.
run_failed() { # code err
	[[ $1 -gt 1 ]] || grep -qE ': timeout: |tsgo exited unexpectedly' "$2"
}
rerun_failed=0
code=$(< "$TMP/all.code")
if run_failed "$code" "$TMP/all.err"; then
	: > "$TMP/all.out"
	: > "$TMP/all.err"
	code=0
	veslint_batched "$TMP/all.out" "$TMP/all.err" --config "$TMP/all.json" -- "${all_cases[@]}" || code=$?
	if run_failed "$code" "$TMP/all.err"; then
		rerun_failed=1
		echo "--config with every rule failed twice (code $code)"
	fi
fi
for ((n = 0; n < jobs_started; n++)); do
	run_failed "$(< "$TMP/per-rule.$n.code")" "$TMP/per-rule.$n.err" || continue
	dir=${rule_dirs[$n]}
	: > "$TMP/per-rule.$n.out"
	: > "$TMP/per-rule.$n.err"
	c=0
	veslint_batched "$TMP/per-rule.$n.out" "$TMP/per-rule.$n.err" $(alone_args "${dir#tests/rules/}" $n) -- "${all_cases[@]}" || c=$?
	if run_failed "$c" "$TMP/per-rule.$n.err"; then
		rerun_failed=1
		echo "--rule ${dir#tests/rules/} failed twice (code $c):"
		cat "$TMP/per-rule.$n.err"
	fi
done
if [[ $jobs_started -eq 0 ]]; then
	if [[ $code -eq 1 && $rerun_failed -eq 0 && -s "$TMP/all.out" ]] && grep -q 'ignores them: semi, @stylistic/indent-binary-ops$' "$TMP/all.err"; then
		ok "--config with every rule on every fixture ($(wc -l < "$TMP/all.out") findings; each rule alone on them with VESLINT_MATRIX=1)"
	else
		ko "--config with every rule on every fixture (code $code)"
		grep -v 'nodes not analyzed' "$TMP/all.err"
	fi
fi
[[ $jobs_started -eq 0 ]] || cat "$TMP"/per-rule.*.out > "$TMP/per-rule.out"
# tests/rules/every.known.txt: findings of a rule alone that the run with every rule does not give
# (one rule sees what another did to the scope manager, as in ESLint).
if [[ $jobs_started -eq 0 ]]; then
	:
elif [[ $code -eq 1 && $rerun_failed -eq 0 ]] && diff <(sort "$TMP/all.out") <(grep -vxF -f <(grep -v '^#' tests/rules/every.known.txt) "$TMP/per-rule.out" | sort) > /dev/null &&
	grep -q 'ignores them: semi, @stylistic/indent-binary-ops$' "$TMP/all.err"; then
	ok "--config with every rule: the same findings as each --rule ($(wc -l < "$TMP/all.out"))"
else
	ko "--config with every rule (code $code)"
	grep -v 'nodes not analyzed' "$TMP/all.err"
	diff <(sort "$TMP/all.out") <(grep -vxF -f <(grep -v '^#' tests/rules/every.known.txt) "$TMP/per-rule.out" | sort) | head -40
fi
phase "each rule alone on every fixture, and every rule at once"
printf '{"rules": {"@typescript-eslint/no-floating-promises": "warn"}}' > "$TMP/warn.json"
code=0
./veslint --config "$TMP/warn.json" tests/rules/@typescript-eslint/no-floating-promises/cases.ts > "$TMP/warn.out" 2> "$TMP/warn-config.err" || code=$?
# Each line of a warning is the line of the error (expected.txt, pinned with the rule set to error)
# with the field `warning` at the end.
if [[ $code -eq 0 && -s "$TMP/warn.out" ]] && grep -q 'of them warnings' "$TMP/warn-config.err" &&
	diff -u <(grep '^tests/rules/@typescript-eslint/no-floating-promises/cases\.ts:' tests/rules/@typescript-eslint/no-floating-promises/expected.txt | sed 's/$/\twarning/') "$TMP/warn.out"; then
	ok "--config: a rule set to warn reports, its lines end with the field warning, and it exits with code 0"
else
	ko "--config: a rule set to warn (code $code)"
	cat "$TMP/warn-config.err"
fi
# A warn rule and an error rule in the same file, without --fixes: each line is that of --fixes
# (tests/config/expected.txt) without the fix, the suggestions and the end, and keeps its `warning`.
code=0
(cd tests/config && ../../veslint --config resolved.json base.ts) > "$TMP/levels.out" 2> "$TMP/levels.err" || code=$?
if [[ $code -eq 1 ]] && grep -q $'^base\\.ts:[0-9:]*\t@typescript-eslint/await-thenable\t.*\twarning$' "$TMP/levels.out" &&
	grep -q $'^base\\.ts:[0-9:]*\t@typescript-eslint/no-floating-promises\t' "$TMP/levels.out" &&
	diff -u <(grep '^base\.ts:' tests/config/expected.txt | awk -F'\t' -v OFS='\t' '{ print $1, $2, $3, $4 ($NF == "warning" ? "\twarning" : "") }') "$TMP/levels.out"; then
	ok "an error and a warning in the same file: only the warning ends with the field warning"
else
	ko "an error and a warning in the same file (code $code)"
	cat "$TMP/levels.err"
fi
printf '{"rules": {"@typescript-eslint/no-for-in-array": ["error", {"anything": true}]}}' > "$TMP/options.json"
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
# slowest_rules has every rule that ran (not one turned off), slowest first.
printf '%s\n' '{"rules": {"no-debugger": [2], "eqeqeq": [2], "curly": [0], "@typescript-eslint/no-floating-promises": [2],' \
	'"@stylistic/semi": [2], "unicorn/no-lonely-if": [1]}}' > "$TMP/bench-rules.json"
./veslint --bench --config "$TMP/bench-rules.json" app.ts 2> "$TMP/bench-rules.out" > /dev/null
listed=$(python3 -I - "$TMP/bench-rules.out" << 'PY'
import json, sys
bench = next(json.loads(line) for line in open(sys.argv[1]) if line.startswith("{"))
entries = [entry.rsplit(" ", 1) for entry in bench["slowest_rules"]]
names = sorted(name for name, _ in entries)
times = [float(ms) for _, ms in entries]
expected = sorted(["no-debugger", "eqeqeq", "@typescript-eslint/no-floating-promises", "@stylistic/semi",
                   "unicorn/no-lonely-if"])
print("ok" if names == expected and times == sorted(times, reverse=True) else " ".join(names))
PY
)
if [[ $listed == ok ]]; then
	ok "--bench lists the time of every rule that ran, slowest first"
else
	ko "--bench lists the time of every rule that ran, slowest first (it lists: $listed)"
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

# The tests up to the end of section 4 are of the process transport (`tsc --api` over a pipe), so
# they run with VESLINT_TSGO=process; with the default, TypeScript is linked into veslint and no
# binary is needed (the tests after them).
export VESLINT_TSGO=process
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
# The npm packages (npm/stage.sh): their versions are the release's and their compiler the one of
# package.json; laid out as npm installs them, the `veslint` command of @marcrock22/veslint runs the
# binary of @marcrock22/veslint-<platform>, which finds the compiler hoisted to the project's
# node_modules, and ends with its exit code.
npm_versions=$(python3 -I - "$extension_version" << 'PY'
import json, sys
version = sys.argv[1]
typescript = json.load(open('package.json'))['dependencies']['typescript']
wrong = []
main = json.load(open('npm/veslint/package.json'))
for name, got in [('version', main['version']), *main['optionalDependencies'].items()]:
	if got != version:
		wrong.append(f'npm/veslint {name} {got}')
for platform in ['linux-x64', 'win32-x64']:
	package = json.load(open(f'npm/{platform}/package.json'))
	if package['version'] != version:
		wrong.append(f'npm/{platform} {package["version"]}')
	if package['dependencies'] != {f'@typescript/typescript-{platform}': typescript}:
		wrong.append(f'npm/{platform} dependencies {package["dependencies"]}')
print(' '.join(wrong) or 'ok')
PY
)
if [[ $npm_versions == ok ]]; then
	ok "npm packages: version $extension_version, the compiler of package.json"
else
	ko "npm packages: $npm_versions"
fi
if [[ $windows -eq 0 && $(platform_package) == typescript-linux-x64 ]] && command -v node > /dev/null; then
	npm_project="$TMP/npm-project"
	mkdir -p "$npm_project/node_modules/@marcrock22" "$npm_project/node_modules/@typescript"
	npm/stage.sh "$TMP/npm" linux-x64=veslint
	mv "$TMP/npm/veslint" "$npm_project/node_modules/@marcrock22/veslint"
	mv "$TMP/npm/linux-x64" "$npm_project/node_modules/@marcrock22/veslint-linux-x64"
	ln -s "$ROOT/node_modules/@typescript/typescript-linux-x64" "$npm_project/node_modules/@typescript/"
	npm_veslint="$npm_project/node_modules/@marcrock22/veslint/bin/veslint.js"
	code=0
	node "$npm_veslint" --rule no-debugger --no-config-lookup tests/rules/no-debugger/cases.ts > "$TMP/npm.out" 2>&1 ||
		code=$?
	if [[ $code -eq 1 ]] && grep -q 'no-debugger' "$TMP/npm.out" &&
		node "$npm_veslint" app.ts | diff -q - tests/expected/app.txt > /dev/null; then
		ok "npm: the veslint command, with the compiler in the project's node_modules"
	else
		ko "npm: the veslint command (code $code)"
		cat "$TMP/npm.out"
	fi
fi
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

unset VESLINT_TSGO
# TypeScript in veslint's process (tsgo/inproc.c.v, the default): no binary is needed, the libs are
# the ones embedded in it; a request TypeScript rejects is an error as over the pipe.
veslint_out=$("$(sandbox missing)" app.ts 2>&1 || true)
if [[ $veslint_out == "$(cat tests/expected/app.txt)" ]]; then
	ok "in process: no TypeScript binary needed"
else
	ko "in process: no TypeScript binary needed"
	echo "$veslint_out" | head -20
fi
expect_error "in process: message type 5" "source file not found" ./veslint --project tsconfig.json tests/fixtures/emoji.ts
expect_error "VESLINT_TSGO with an unknown value" "VESLINT_TSGO must be" env VESLINT_TSGO=pipe ./veslint app.ts
# Workers (lint_workers.v): the files of 127 projects linted on one CPU and on all of them (a worker
# per CPU; in this process they share TypeScript's session, with a checker each) print exactly the
# same, with either transport.
printf '{"rules": {"@typescript-eslint/no-floating-promises": "error", "@typescript-eslint/no-misused-promises": "error", "@typescript-eslint/no-unnecessary-type-assertion": "error", "@typescript-eslint/unbound-method": "error", "@typescript-eslint/strict-boolean-expressions": "error", "@typescript-eslint/no-unsafe-assignment": "warn", "@typescript-eslint/no-deprecated": "error", "@typescript-eslint/naming-convention": "error"}}' > "$TMP/workers.json"
mapfile -t worker_files < <(find tests/rules/@typescript-eslint -mindepth 2 -maxdepth 2 -name cases.ts | sorted)
for transport in inproc process; do
	for cpus in 1 0; do
		code=0
		VESLINT_TSGO=$transport VESLINT_CPUS=$cpus ./veslint --config "$TMP/workers.json" "${worker_files[@]}" > "$TMP/workers-$cpus.out" 2> "$TMP/workers-$cpus.err" || code=$?
		echo "$code" >> "$TMP/workers-$cpus.err"
	done
	[[ $transport == process ]] || cp "$TMP/workers-1.out" "$TMP/workers-inproc.out"
	if [[ $(tail -1 "$TMP/workers-1.err") -eq 1 && -s $TMP/workers-1.out ]] && cmp -s "$TMP/workers-1.out" "$TMP/workers-0.out" &&
		cmp -s "$TMP/workers-1.err" "$TMP/workers-0.err"; then
		ok "workers ($transport): $(wc -l < "$TMP/workers-1.out") lines of ${#worker_files[@]} files, the same on one CPU and on all"
	else
		ko "workers ($transport): one CPU and all of them differ"
		diff "$TMP/workers-1.out" "$TMP/workers-0.out" | head -20
		diff "$TMP/workers-1.err" "$TMP/workers-0.err" | head -20
	fi
done
# With TypeScript in this process some rules have it run their type walks (the `veslint/…` methods
# of tsgo/inproc/api_rules.go); VESLINT_TSGO_HELPERS=0 makes them walk the types themselves through
# TypeScript's API, as with the process transport: the output is the same.
code=0
VESLINT_TSGO_HELPERS=0 ./veslint --config "$TMP/workers.json" "${worker_files[@]}" > "$TMP/workers-walked.out" 2> /dev/null || code=$?
if [[ $code -eq 1 ]] && cmp -s "$TMP/workers-inproc.out" "$TMP/workers-walked.out"; then
	ok "type walks in TypeScript's process: the same as the rules' own"
else
	ko "type walks in TypeScript's process (code $code)"
	diff "$TMP/workers-inproc.out" "$TMP/workers-walked.out" | head -20
fi
# The answers about types, symbols and signatures are written (tsgo/inproc/api_fastjson.go) and read
# (tsgo/fast_decode.v) by hand: on the same files, VESLINT_TSGO_CHECK_JSON compares each one written
# with what json.Marshal writes, and VESLINT_CHECK_DECODE each one read with what json2 reads (a
# difference panics), and the output does not change.
code=0
VESLINT_TSGO_CHECK_JSON=1 VESLINT_CHECK_DECODE=1 ./veslint --config "$TMP/workers.json" "${worker_files[@]}" > "$TMP/workers-checked.out" 2> "$TMP/workers-checked.err" || code=$?
if [[ $code -eq 1 ]] && cmp -s "$TMP/workers-inproc.out" "$TMP/workers-checked.out"; then
	ok "answers written and read by hand: the same as json.Marshal's and json2's"
else
	ko "answers written and read by hand (code $code)"
	diff "$TMP/workers-inproc.out" "$TMP/workers-checked.out" | head -20
	head -c 2000 "$TMP/workers-checked.err"
fi
# In a lint with types, the converter converts the program's AST of a file instead of parsing its
# text again (tsgo.convert_in); VESLINT_CHECK_PROGRAM_AST also converts the text of each such file
# and reports where the two differ (`veslint_tsgo: checked <path>` where they do not): most files
# are converted from their program's AST (not those without import or export whose text has an
# `await` or a `\u` escape), none differently, and the output does not change.
# Only TypeScript's parser converts a program's AST, so the test sets it.
code=0
VESLINT_PARSER=typescript VESLINT_CHECK_PROGRAM_AST=1 ./veslint --config "$TMP/workers.json" "${worker_files[@]}" > "$TMP/workers-program.out" 2> "$TMP/workers-program.err" || code=$?
if [[ $code -eq 1 ]] && cmp -s "$TMP/workers-inproc.out" "$TMP/workers-program.out" &&
	[[ $(grep -c '^veslint_tsgo: checked ' "$TMP/workers-program.err") -gt 0 ]] &&
	! grep '^veslint_tsgo: ' "$TMP/workers-program.err" | grep -qv '^veslint_tsgo: checked '; then
	ok "the program's ASTs converted: the rows of a parse of each file's text"
else
	ko "the program's ASTs converted (code $code)"
	diff "$TMP/workers-inproc.out" "$TMP/workers-program.out" | head -20
	grep '^veslint_tsgo: ' "$TMP/workers-program.err" | grep -v '^veslint_tsgo: checked ' | head -20
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
# Random edits of files linted as unsaved text, one after the other (tests/server_edits.py): a
# server that keeps its last tree and answer answers what one that parses every text from scratch
# and lints every request answers: the TypeScript files of tests/config, the Vue and the Svelte
# fixtures. TypeScript's parser parses each text whole; with VESLINT_PARSER=tree-sitter the first
# parses each edit from the tree of the text before, and the trees are the same
# (VESLINT_INCREMENTAL_CHECK).
mapfile -t edited_config < <(cd tests/config && find . -name '*.ts' | sed 's|^\./||' | sorted)
for parser in typescript tree-sitter; do
	if (cd tests/config && VESLINT_PARSER=$parser python3 ../server_edits.py ../../veslint 1 8 . resolved.json "${edited_config[@]}") > "$TMP/server-edits.out" 2>&1 &&
		(cd tests/vue-lint/fixtures && VESLINT_PARSER=$parser python3 ../../server_edits.py ../../../veslint 2 6 . ../rules.json ./*.vue) >> "$TMP/server-edits.out" 2>&1 &&
		(cd tests/svelte-lint/fixtures && VESLINT_PARSER=$parser python3 ../../server_edits.py ../../../veslint 3 6 . ../rules.json ./*.svelte ./*.svelte.ts) >> "$TMP/server-edits.out" 2>&1; then
		ok "--server ($parser's parser): random edits answer as parsed from scratch ($(grep -o '^[0-9]* requests' "$TMP/server-edits.out" | awk '{n += $1} END {print n}') requests)"
	else
		ko "--server ($parser's parser): random edits (tests/server_edits.py)"
		cat "$TMP/server-edits.out"
	fi
done
# A server keeps every thread of its own and of its tsgo on two CPUs as well (cpus.v): looked at
# after its first lint, while both are alive (on Linux only); with TypeScript in its process, the
# threads of the Go runtime are its own.
for transport in process inproc; do
	if [[ $windows -eq 1 ]]; then
		echo "skip   --server on two CPUs ($transport): veslint restricts its CPUs on Linux only"
	elif VESLINT_TSGO=$transport python3 - ./veslint tests/config "${config_abs[0]}" 2> "$TMP/server-cpus.err" << 'PY'
import json, os, subprocess, sys
veslint, cwd, file = os.path.abspath(sys.argv[1]), sys.argv[2], sys.argv[3]
want = min(2, len(os.sched_getaffinity(0)))
in_process = os.environ['VESLINT_TSGO'] == 'inproc'
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
if answer.get('code') not in (0, 1) or code != 0 or bool(children) == in_process or len(sets) != 1 or len(next(iter(sets))) != want:
    sys.exit(f'answer code {answer.get("code")}, exit {code}, children {children}, threads on {sets} (want {want} CPUs)')
print(f'{len(seen)} threads in {1 + len(children)} processes on {sorted(sets)[0]}', file=sys.stderr)
PY
	then
		ok "--server ($transport): veslint and tsgo on two CPUs ($(tail -1 "$TMP/server-cpus.err"))"
	else
		ko "--server ($transport): veslint and tsgo not on two CPUs"
		cat "$TMP/server-cpus.err"
	fi
done

phase "options, --bench, tsgo and --server"
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
# ESLint 10.15.0): their JavaScript cases are linted as TypeScript in typescript-eslint's fixtures.
mapfile -t core_upstream < <(find tests/rules -mindepth 2 -maxdepth 2 -name upstream.json | sed -E 's|^tests/rules/(.*)/upstream\.json$|\1|' | sorted)
# The rules of eslint-plugin-unicorn (tests/rules/unicorn/<rule>/upstream.json, from test/<rule>.js
# of v79.0.0), the same way.
mapfile -t unicorn_upstream < <(upstream_rules_of unicorn)
# The rules of @stylistic/eslint-plugin (tests/rules/@stylistic/<rule>/upstream.json, from
# rules/<rule>/*.test.ts of eslint-stylistic v6.0.1), the same way.
mapfile -t stylistic_upstream < <([[ -d tests/rules/@stylistic ]] && upstream_rules_of @stylistic)
# The rules of eslint-plugin-perfectionist (tests/rules/perfectionist/<rule>/upstream.json, from
# test/rules/<rule>.test.ts of v5.13.0), the same way.
mapfile -t perfectionist_upstream < <([[ -d tests/rules/perfectionist ]] && upstream_rules_of perfectionist)
# The rules of @marcrock22/eslintcf (tests/rules/marcrock/<rule>/upstream.json, from
# src/rules/__test__/<rule>.test.ts of MARCROCK22/eslintcf at 0c25278), the same way.
mapfile -t marcrock_upstream < <([[ -d tests/rules/marcrock ]] && upstream_rules_of marcrock)
# The rules of @eslint-community/eslint-plugin-eslint-comments
# (tests/rules/@eslint-community/eslint-comments/<rule>/upstream.json, from tests/lib/rules/<rule>.js of
# v4.8.1), the same way.
mapfile -t eslint_comments_upstream < <([[ -d tests/rules/@eslint-community/eslint-comments ]] && upstream_rules_of @eslint-community/eslint-comments)
# The rules of eslint-plugin-promise (tests/rules/promise/<rule>/upstream.json, from
# __tests__/<rule>.js of v7.3.0), the same way.
mapfile -t promise_upstream < <([[ -d tests/rules/promise ]] && upstream_rules_of promise)
# The rules of eslint-plugin-regexp (tests/rules/regexp/<rule>/upstream.json, from
# tests/lib/rules/<rule>.ts of v3.3.3 and its snapshots), the same way.
mapfile -t regexp_upstream < <([[ -d tests/rules/regexp ]] && upstream_rules_of regexp)
if tests/upstream/setup.sh "$TMP/upstream" 2> "$TMP/upstream-setup.err"; then
	upstream_check "typescript-eslint's own tests" "$TMP/upstream" "$TMP/upstream-configs" "${typescript_eslint_upstream[@]}"
	[[ ${#core_upstream[@]} -eq 0 ]] ||
		upstream_check "ESLint's own tests of its core rules" "$TMP/upstream" "$TMP/upstream-core-configs" "${core_upstream[@]}"
	[[ ${#unicorn_upstream[@]} -eq 0 ]] ||
		upstream_check "eslint-plugin-unicorn's own tests" "$TMP/upstream" "$TMP/upstream-unicorn-configs" "${unicorn_upstream[@]}"
	[[ ${#stylistic_upstream[@]} -eq 0 ]] ||
		upstream_check "@stylistic/eslint-plugin's own tests" "$TMP/upstream" "$TMP/upstream-stylistic-configs" "${stylistic_upstream[@]}"
	[[ ${#perfectionist_upstream[@]} -eq 0 ]] ||
		upstream_check "eslint-plugin-perfectionist's own tests" "$TMP/upstream" "$TMP/upstream-perfectionist-configs" "${perfectionist_upstream[@]}"
	[[ ${#marcrock_upstream[@]} -eq 0 ]] ||
		upstream_check "@marcrock22/eslintcf's own tests" "$TMP/upstream" "$TMP/upstream-marcrock-configs" "${marcrock_upstream[@]}"
	[[ ${#eslint_comments_upstream[@]} -eq 0 ]] ||
		upstream_check "@eslint-community/eslint-plugin-eslint-comments' own tests" "$TMP/upstream" "$TMP/upstream-eslint-comments-configs" "${eslint_comments_upstream[@]}"
	[[ ${#promise_upstream[@]} -eq 0 ]] ||
		upstream_check "eslint-plugin-promise's own tests" "$TMP/upstream" "$TMP/upstream-promise-configs" "${promise_upstream[@]}"
	[[ ${#regexp_upstream[@]} -eq 0 ]] ||
		upstream_check "eslint-plugin-regexp's own tests" "$TMP/upstream" "$TMP/upstream-regexp-configs" "${regexp_upstream[@]}"
else
	echo "skip   typescript-eslint's own tests: $(cat "$TMP/upstream-setup.err")"
fi
if tests/upstream/seyfert/setup.sh "$TMP/upstream-seyfert" 2> "$TMP/upstream-seyfert-setup.err"; then
	upstream_check "@slipher/eslint-plugin's own tests" "$TMP/upstream-seyfert" "$TMP/upstream-seyfert-configs" "${seyfert_upstream[@]}"
else
	echo "skip   @slipher/eslint-plugin's own tests: $(cat "$TMP/upstream-seyfert-setup.err")"
fi
# eslint-plugin-vue's own tests of the vue/* rules veslint has (the directories of tests/rules/vue
# with an expected.txt): their cases converted to TypeScript, with the expectations of
# upstream.ts.json (tests/rules/vue/upstream_ts.mjs), in the fixtures of tests/upstream/vue/setup.sh,
# and the lints of comment-directive whole.
mapfile -t vue_upstream < <(find tests/rules/vue -name expected.txt | sed -E 's|^tests/rules/(.*)/expected\.txt$|\1|' | sorted)
if [[ ${#vue_upstream[@]} -gt 0 ]]; then
	if tests/upstream/vue/setup.sh "$TMP/upstream-vue" 2> "$TMP/upstream-vue-setup.err"; then
		upstream_check "eslint-plugin-vue's own tests" "$TMP/upstream-vue" "$TMP/upstream-vue-configs" "${vue_upstream[@]}"
	else
		echo "skip   eslint-plugin-vue's own tests: $(cat "$TMP/upstream-vue-setup.err")"
	fi
fi
# eslint-plugin-svelte's own tests of the svelte/* rules veslint has (the directories of
# tests/rules/svelte with an expected.txt): their cases converted to TypeScript, with the
# expectations of upstream.ts.json (tests/rules/svelte/upstream_ts.mjs), in place in the clone's
# tests/fixtures/rules (the typed ones with the program of its tsconfig.json), and the lints of
# comment-directive whole.
mapfile -t svelte_upstream < <(find tests/rules/svelte -name expected.txt | sed -E 's|^tests/rules/(.*)/expected\.txt$|\1|' | sorted)
if [[ ${#svelte_upstream[@]} -gt 0 ]]; then
	svelte_fixtures=build/upstream/svelte/packages/eslint-plugin-svelte/tests/fixtures/rules
	if [[ -f $svelte_fixtures/tsconfig.json ]]; then
		upstream_check "eslint-plugin-svelte's own tests" "$svelte_fixtures" "$TMP/upstream-svelte-configs" "${svelte_upstream[@]}"
	else
		echo "skip   eslint-plugin-svelte's own tests: missing $svelte_fixtures (see tests/upstream/README.md)"
	fi
fi
phase "the upstream tests of each plugin"

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
