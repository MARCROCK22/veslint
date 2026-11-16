#!/usr/bin/env bash
# eval_eslintcf.sh [PROJECT...]: the whole configuration of @marcrock22/eslintcf, as a project that
# uses it gets it, on the sources of real projects, with ESLint 10.15.0 and with veslint. For each
# project it compares
#   1. what each tool reports (path, line, column, rule, messageId and message);
#   2. the files `eslint --fix` and `veslint --fix` leave;
#   3. what each tool reports on the files its own --fix left: a finding that can still be fixed
#      means that two fixes undo each other, and a rule that reports more than before means that a
#      fix brought a finding of that rule. When ESLint does the same, the cause is the
#      configuration and not veslint.
# The projects are copies (their node_modules are links to the original packages) in
# build/eval/eslintcf/<project>/: `base` with eslintcf's eslint.config.mjs, `eslint-fix` and
# `veslint-fix`. The results are in build/eval/eslintcf/<project>/*.txt and a summary is printed.
#
#   tests/eval_eslintcf.sh                        # every project but typescript
#   tests/eval_eslintcf.sh typescript             # src/services of the TypeScript compiler (slow)
#   ESLINTCF=/path/to/eslintcf tests/eval_eslintcf.sh spider-byte
#   RULES="'curly': 'off'" tests/eval_eslintcf.sh zod   # rules added to the configuration
#
# ESLINTCF is a checkout of MARCROCK22/eslintcf with its dist built and its node_modules installed
# (build/upstream/eslintcf by default): its ESLint, plugins and TypeScript are the ones that run.
# spider-byte comes from tests/eval_spider_byte.sh and zod, recharts and typescript from
# tests/eval_project.sh. seyfert, valibot and ky are downloaded here (a pinned commit, no git
# repository) the first time, with the type packages their sources need in build/eval/<project>.deps.
# It is not part of `make test`.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
ESLINTCF=$(cd "${ESLINTCF:-$ROOT/build/upstream/eslintcf}" && pwd) || exit 2
ESLINT=$ESLINTCF/node_modules/eslint/bin/eslint.js
OUT=$ROOT/build/eval/eslintcf
[[ -f $ESLINTCF/dist/index.js && -f $ESLINT ]] || {
	echo "$ESLINTCF needs dist/index.js (bun run build) and node_modules/eslint" >&2
	exit 2
}
[[ -x ./veslint ]] || make veslint || exit 2
PROJECTS=("$@")
[[ ${#PROJECTS[@]} -gt 0 ]] || PROJECTS=(spider-byte zod recharts seyfert valibot ky eslintcf)
export NODE_OPTIONS=--max-old-space-size=8192

# fetch NAME REPOSITORY COMMIT [PACKAGE@VERSION...]: downloads the commit of the repository to
# build/eval/NAME and installs the packages in build/eval/NAME.deps, its node_modules (only what is
# missing).
fetch() {
	local name=$1 repository=$2 commit=$3 dir=$ROOT/build/eval/$1
	shift 3
	if [[ ! -d $dir ]]; then
		mkdir -p "$dir"
		curl -sfL "https://codeload.github.com/$repository/tar.gz/$commit" | tar xz -C "$dir" --strip-components=1 ||
			{ rm -r "$dir"; echo "cannot download $repository" >&2; return 1; }
	fi
	[[ $# -gt 0 && ! -d $dir.deps/node_modules ]] || return 0
	mkdir -p "$dir.deps"
	python3 -I -c 'import json, sys
json.dump({"private": True, "dependencies": dict(p.rsplit("@", 1) for p in sys.argv[2:])}, open(sys.argv[1], "w"), indent=2)' \
		"$dir.deps/package.json" "$@" || return 1
	(cd "$dir.deps" && npm install --ignore-scripts --no-audit --no-fund > /dev/null) || return 1
	[[ -e $dir/node_modules ]] || ln -s "../$name.deps/node_modules" "$dir/node_modules"
}

# project NAME: SOURCE (the directory copied), TARGETS (what is linted, relative to it), IGNORES
# (files the tsconfig.json leaves out, as eslint.config globs) and TSCONFIG (the tsconfig.json of the
# copy; empty keeps the project's).
project() {
	TSCONFIG='' IGNORES=''
	case $1 in
	spider-byte)
		SOURCE=$ROOT/build/eval/spider-byte TARGETS=(src seyfert.config.mts) ;;
	zod)
		SOURCE=$ROOT/build/eval/zod/packages/zod TARGETS=(src)
		IGNORES="'src/**/*.test.ts', 'src/**/tests/**', 'src/**/benchmarks/**'"
		TSCONFIG=$(sed "s|\"\.\./\.\./|\"$ROOT/build/eval/zod/|" "$SOURCE/tsconfig.veslint.json") ;;
	recharts)
		SOURCE=$ROOT/build/eval/recharts TARGETS=(src)
		TSCONFIG=$(cat "$SOURCE/tsconfig.veslint.json") ;;
	typescript)
		SOURCE=$ROOT/build/eval/typescript TARGETS=(src/services)
		TSCONFIG=$(cat "$SOURCE/tsconfig.veslint.json") ;;
	seyfert)
		# A Discord framework (classes, decorators), with its own tsconfig.json.
		fetch seyfert tiramisulabs/seyfert 1cf6d5c22e68d64bccbdb57c25f37bead3d6cdd8 @types/node@26.6.6 || return 1
		SOURCE=$ROOT/build/eval/seyfert TARGETS=(src) ;;
	valibot)
		# A schema library like zod, made of hundreds of small modules. Its tsconfig.json without the
		# tests (they import vitest) and with moduleResolution bundler (TypeScript 7 has no node10).
		fetch valibot open-circle/valibot d72f76fcf70ccfa0a5ca341b80da1d440ac60b11 || return 1
		SOURCE=$ROOT/build/eval/valibot/library TARGETS=(src)
		IGNORES="'src/**/*.test.ts', 'src/**/*.test-d.ts'"
		TSCONFIG='{
  "compilerOptions": {
    "allowImportingTsExtensions": true,
    "declaration": true,
    "exactOptionalPropertyTypes": true,
    "isolatedDeclarations": true,
    "lib": ["ESNext", "DOM"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "noEmit": true,
    "skipLibCheck": true,
    "strict": true,
    "target": "ES2020"
  },
  "include": ["src"],
  "exclude": ["src/**/*.test.ts", "src/**/*.test-d.ts"]
}' ;;
	ky)
		# An HTTP client on fetch, with its own tsconfig.json (on @sindresorhus/tsconfig).
		fetch ky sindresorhus/ky 3541888878c4d303a8bc2ad61815f4e048f55a5d @types/node@25.9.9 @sindresorhus/tsconfig@8.1.0 || return 1
		SOURCE=$ROOT/build/eval/ky TARGETS=(source) ;;
	eslintcf)
		SOURCE=$ESLINTCF TARGETS=(src) IGNORES="'src/rules/__test__/**'" ;;
	*)
		echo "unknown project $1" >&2
		return 1 ;;
	esac
	[[ -d $SOURCE ]] || { echo "missing $SOURCE (tests/eval_spider_byte.sh, tests/eval_project.sh)" >&2; return 1; }
}

# eslint_run DIR OUTPUT [--fix]: ESLint's findings on DIR, with their fixes, as veslint --fixes writes
# them (sorted).
eslint_run() {
	local dir=$1 out=$2
	shift 2
	(cd "$dir" && node "$ESLINT" -f json --no-warn-ignored "$@" "${TARGETS[@]}" > "$out.json" 2> "$out.err"
		python3 "$ROOT/tests/eslint_lines.py" fixes < "$out.json" | LC_ALL=C sort > "$out")
	rm -f "$out.json"
}

# veslint_run DIR OUTPUT [--fix]: the same with veslint.
veslint_run() {
	local dir=$1 out=$2
	shift 2
	(cd "$dir" && "$ROOT/veslint" --fixes "$@" "${TARGETS[@]}" 2> "$out.err" | LC_ALL=C sort > "$out")
}

# findings FILE: the lines without fixes, suggestions and end (path:line:col, rule, messageId, message).
findings() { cut -f1-4 "$1"; }
# by_rule FILE: the number of findings of each rule.
by_rule() { cut -f2 "$1" | LC_ALL=C sort | uniq -c | awk '{ print $2 "\t" $1 }' | LC_ALL=C sort; }

for name in "${PROJECTS[@]}"; do
	project "$name" || exit 2
	dir=$OUT/$name
	rm -rf "$dir"
	mkdir -p "$dir"
	rsync -a --exclude node_modules --exclude .git --exclude dist "$SOURCE/" "$dir/base/"
	# node_modules: links to the packages of the project, plus ESLint and typescript-eslint when it does
	# not have them (veslint resolves the configuration with the project's ESLint, which a project
	# that uses eslintcf has installed).
	mkdir "$dir/base/node_modules"
	for package in "$SOURCE"/node_modules/* "$SOURCE"/node_modules/.bin; do
		[[ -e $package ]] && ln -s "$package" "$dir/base/node_modules/"
	done
	for package in eslint typescript-eslint; do
		[[ -e $dir/base/node_modules/$package ]] || ln -s "$ESLINTCF/node_modules/$package" "$dir/base/node_modules/"
	done
	[[ -z $TSCONFIG ]] || printf '%s\n' "$TSCONFIG" > "$dir/base/tsconfig.json"
	rm -f "$dir"/base/eslint.config.* "$dir"/base/veslint-eval.eslint.config.mjs
	cat > "$dir/base/eslint.config.mjs" <<-EOF
		import config from '$ESLINTCF/dist/index.js';

		export default [...config, { ignores: [$IGNORES] }, { rules: { ${RULES:-} } }];
	EOF
	cp -a "$dir/base" "$dir/eslint-fix"
	cp -a "$dir/base" "$dir/veslint-fix"
	files=$(cd "$dir/base" && find "${TARGETS[@]}" \( -name '*.ts' -o -name '*.tsx' -o -name '*.mts' -o -name '*.cts' \) | wc -l)
	echo "== $name ($files files)"

	t0=$(date +%s.%N)
	eslint_run "$dir/base" "$dir/eslint.txt"
	t1=$(date +%s.%N)
	veslint_run "$dir/base" "$dir/veslint.txt"
	t2=$(date +%s.%N)
	printf 'time   ESLint %.1f s, veslint %.1f s\n' "$(echo "$t1 - $t0" | bc)" "$(echo "$t2 - $t1" | bc)"
	for tool in eslint veslint; do
		[[ -s $dir/$tool.txt.err ]] && { echo "$tool stderr:"; head -5 "$dir/$tool.txt.err"; }
	done
	diff <(findings "$dir/eslint.txt") <(findings "$dir/veslint.txt") > "$dir/findings.diff"
	echo "findings: ESLint $(wc -l < "$dir/eslint.txt"), veslint $(wc -l < "$dir/veslint.txt"), only ESLint $(grep -c '^<' "$dir/findings.diff"), only veslint $(grep -c '^>' "$dir/findings.diff")"
	grep -E '^[<>]' "$dir/findings.diff" | cut -f2 | LC_ALL=C sort | uniq -c | sort -rn | head -20 | sed 's/^/  differs /'
	# The fixes and suggestions of the findings both report.
	diff "$dir/eslint.txt" "$dir/veslint.txt" | grep -E '^[<>]' | cut -c3- | cut -f1-4 | LC_ALL=C sort | uniq -d > "$dir/fixes-differ.txt"
	[[ -s $dir/fixes-differ.txt ]] && echo "fixes or suggestions differ: $(wc -l < "$dir/fixes-differ.txt") findings ($dir/fixes-differ.txt)"

	eslint_run "$dir/eslint-fix" "$dir/eslint-fix.txt" --fix
	veslint_run "$dir/veslint-fix" "$dir/veslint-fix.txt" --fix
	diff -ru --no-dereference --exclude node_modules "$dir/eslint-fix" "$dir/veslint-fix" > "$dir/fix.diff"
	echo "--fix: $(grep -c '^diff -ru' "$dir/fix.diff") files differ ($dir/fix.diff)"

	for tool in eslint veslint; do
		"${tool}_run" "$dir/$tool-fix" "$dir/$tool.after.txt"
		grep -P '\tfix\t' "$dir/$tool.after.txt" > "$dir/$tool.after-fixable.txt"
		echo "$tool after its --fix: $(wc -l < "$dir/$tool.after.txt") findings, $(wc -l < "$dir/$tool.after-fixable.txt") still fixable"
		cut -f2 "$dir/$tool.after-fixable.txt" | LC_ALL=C sort | uniq -c | sort -rn | sed 's/^/  fixable /'
		LC_ALL=C join -t $'\t' -a 2 -e 0 -o 0,1.2,2.2 <(by_rule "$dir/$tool.txt") <(by_rule "$dir/$tool.after.txt") |
			awk -F'\t' '$3 > $2 { print "  more " $1 ": " $2 " -> " $3 }'
	done
done
