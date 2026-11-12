#!/usr/bin/env bash
# Evaluation of veslint on Spider-Byte (pinned commit), comparing each ported rule with
# typescript-eslint 8.62.0, finding by finding and message by message. Everything stays in
# build/eval/. It is not part of `make test`.
#
# Steps that use the network, each one only when its result is missing:
#   1. download the tarball of the commit (no git repository);
#   2. `bun install --frozen-lockfile --ignore-scripts` (local, without install scripts).
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
COMMIT=62ca1278251ab36d76ed55cd7d9ef2d6a51f19ab
SB=$ROOT/build/eval/spider-byte
MUT=$ROOT/build/eval/spider-byte-mut
MUT_AWAIT=$ROOT/build/eval/spider-byte-mut-await
MUT_NO_AWAIT=$ROOT/build/eval/spider-byte-mut-no-await
MUT_RETURN=$ROOT/build/eval/spider-byte-mut-return-await
MUT_ANY=$ROOT/build/eval/spider-byte-mut-any
MUT_PREFER=$ROOT/build/eval/spider-byte-mut-prefer
RULES=(no-floating-promises await-thenable require-await return-await no-misused-promises
	no-unsafe-argument no-unsafe-assignment no-unsafe-call no-unsafe-member-access no-unsafe-return
	restrict-template-expressions switch-exhaustiveness-check prefer-nullish-coalescing no-unnecessary-condition
	no-for-in-array no-array-delete no-unnecessary-boolean-literal-compare no-unsafe-unary-minus
	no-meaningless-void-operator related-getter-setter-pairs non-nullable-type-assertion-style
	prefer-return-this-type no-duplicate-type-constituents no-unnecessary-template-expression dot-notation
	restrict-plus-operands no-confusing-void-expression no-misused-spread no-redundant-type-constituents
	no-useless-default-assignment no-unnecessary-type-arguments no-unnecessary-qualifier no-implied-eval
	no-unnecessary-type-conversion no-unnecessary-type-assertion no-base-to-string no-unsafe-enum-comparison
	no-mixed-enums unbound-method prefer-reduce-type-parameter prefer-find prefer-regexp-exec prefer-includes
	prefer-string-starts-ends-with prefer-optional-chain no-deprecated
	prefer-promise-reject-errors use-unknown-in-catch-callback-variable only-throw-error
	require-array-sort-compare no-unsafe-type-assertion promise-function-async
	prefer-readonly-parameter-types consistent-type-exports strict-void-return consistent-return
	prefer-destructuring prefer-readonly strict-boolean-expressions no-unnecessary-type-parameters
	naming-convention)
# Comparisons that run at the same time (JOBS=1 for times that can be compared with each other).
JOBS=${JOBS:-$(nproc)}
OUT=$ROOT/build/eval/results
mkdir -p "$OUT"

if [[ ! -d $SB/src ]]; then
	mkdir -p "$SB"
	curl -sL "https://codeload.github.com/FabrizioCoder/Spider-Byte/tar.gz/$COMMIT" | tar xz -C "$SB" --strip-components=1
fi
if [[ ! -d $SB/node_modules ]]; then
	(cd "$SB" && bun install --frozen-lockfile --ignore-scripts)
fi
[[ -x ./veslint ]] || make build

# Minimal ESLint config: only the `rules` of the JSON file in VESLINT_EVAL_CONFIG (entries of the
# real Spider-Byte configuration, with their options), without the repository's own config and
# plugins. With VESLINT_EVAL_TSCONFIG, the project is that tsconfig instead of the closest one.
cat > "$SB/veslint-eval.eslint.config.mjs" << 'CFG'
import fs from 'node:fs';
import tseslint from 'typescript-eslint';
const { rules } = JSON.parse(fs.readFileSync(process.env.VESLINT_EVAL_CONFIG, 'utf8'));
export default [
  {
    files: ['**/*.ts', '**/*.mts'],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: process.env.VESLINT_EVAL_TSCONFIG
        ? { project: [process.env.VESLINT_EVAL_TSCONFIG], tsconfigRootDir: import.meta.dirname }
        : { projectService: true, tsconfigRootDir: import.meta.dirname },
    },
    plugins: { '@typescript-eslint': tseslint.plugin },
    rules,
  },
];
CFG

now() { date +%s.%N; }
secs() { echo "$2 - $1" | bc; }
ts_files() { find . -path ./node_modules -prune -o \( -name '*.ts' -o -name '*.mts' \) -print | sed 's|^\./||' | sort; }

# fresh_copy DIR: a copy of Spider-Byte to mutate, with src/, the configuration, the JSON that src/
# imports (assets/json) and the dependencies linked.
fresh_copy() {
	rm -rf "$1"
	mkdir -p "$1/assets"
	cp -r "$SB/src" "$SB/tsconfig.json" "$SB/package.json" "$SB/seyfert.config.mts" "$SB/veslint-eval.eslint.config.mjs" "$1/"
	cp -r "$SB/assets/json" "$1/assets/"
	ln -s "$SB/node_modules" "$1/node_modules"
}

# rule_config FILE RULES...: writes FILE with the entries of RULES in the real Spider-Byte
# configuration (severity "error" and its options).
rule_config() {
	local file=$1
	shift
	python3 - "$OUT/spider-byte.config.json" "$file" "$@" << 'PY'
import json, sys
real = json.load(open(sys.argv[1]))["rules"]
rules = {}
for name in sys.argv[3:]:
    entry = real.get(f"@typescript-eslint/{name}", [2])
    options = entry[1:] if isinstance(entry, list) else []
    rules[f"@typescript-eslint/{name}"] = ["error", *options]
json.dump({"rules": rules}, open(sys.argv[2], "w"))
PY
}

# compare_findings DIR ESLINT_JSON VESLINT_TXT: prints how many findings of each tool match
# (position, rule, messageId and message) and the ones only one of them has.
compare_findings() {
	python3 - "$1" "$2" "$3" << 'PY'
import json, os, re, sys
root, eslint_json, veslint_txt = sys.argv[1:4]
# Files ESLint cannot parse (fatal errors) count for neither side.
ref, fatal = set(), set()
for f in json.load(open(eslint_json)):
    path = os.path.relpath(f["filePath"], root)
    for m in f["messages"]:
        rule = m.get("ruleId") or ""
        if m.get("fatal"):
            fatal.add(path)
        elif (m.get("ruleId") or "").startswith("@typescript-eslint/"):
            ref.add((path, m["line"], m["column"], rule, m["messageId"], m["message"]))
unescape = lambda s: re.sub(r"\\(.)", lambda m: {"n": "\n", "r": "\r", "t": "\t"}.get(m.group(1), m.group(1)), s)
mine, skipped = set(), 0
for line in open(veslint_txt):
    loc, rule, message_id, msg = line.rstrip("\n").split("\t", 3)
    path, l, c = loc.rsplit(":", 2)
    if path in fatal:
        skipped += 1
    else:
        mine.add((path, int(l), int(c), rule, message_id, unescape(msg)))
print(f"  typescript-eslint: {len(ref)}  veslint: {len(mine)}  matching: {len(ref & mine)}"
      f"  only typescript-eslint: {len(ref - mine)}  only veslint: {len(mine - ref)}"
      f"  files ESLint cannot parse: {len(fatal)} (veslint findings in them: {skipped})")
for t in sorted(ref - mine): print("  only typescript-eslint:", t)
for t in sorted(mine - ref): print("  only veslint:", t)
PY
}

# compare DIR NAME: veslint against typescript-eslint in DIR, finding by finding (position, rule,
# messageId and message): each rule on its own and, at the end, all of them together ("all"), both
# with the entries of the real Spider-Byte configuration.
compare() {
	local dir=$1 name=$2 rule
	cd "$dir"
	mapfile -t FILES < <(ts_files)
	# Up to JOBS comparisons at a time; the output of each one is printed in order at the end.
	for rule in "${RULES[@]}" all; do
		while (($(jobs -rp | wc -l) >= JOBS)); do
			wait -n
		done
		compare_rule "$dir" "$name" "$rule" > "$OUT/$name.$rule.log" 2>&1 &
	done
	wait
	for rule in "${RULES[@]}" all; do
		cat "$OUT/$name.$rule.log"
	done
	cd "$ROOT"
}

# compare_rule DIR NAME RULE: one comparison of `compare`, in the directory DIR, with FILES.
compare_rule() {
	local dir=$1 name=$2 rule=$3 t0 t1
	# Each scenario has its own configuration files: the scenarios do not run at the same time,
	# but the rules of one do.
	local config="$OUT/config.$rule.json"
	if [[ $rule == all ]]; then
		rule_config "$config" "${RULES[@]}"
	else
		rule_config "$config" "$rule"
	fi
	t0=$(now)
	"$ROOT/veslint" --config "$config" "${FILES[@]}" > "$OUT/$name.$rule.veslint.txt" 2> /dev/null
	t1=$(now)
	echo "$name, $rule: veslint $(secs "$t0" "$t1") s"
	t0=$(now)
	VESLINT_EVAL_CONFIG=$config node node_modules/eslint/bin/eslint.js --config veslint-eval.eslint.config.mjs \
		--format json "${FILES[@]}" > "$OUT/$name.$rule.eslint.json" 2> /dev/null
	t1=$(now)
	echo "$name, $rule: eslint + typescript-eslint $(secs "$t0" "$t1") s"
	compare_findings "$dir" "$OUT/$name.$rule.eslint.json" "$OUT/$name.$rule.veslint.txt"
}

cd "$SB"
# The real Spider-Byte configuration (veslint takes the rules it has).
node node_modules/eslint/bin/eslint.js --print-config src/index.ts > "$OUT/spider-byte.config.json"
t0=$(now)
"$ROOT/node_modules/@typescript/typescript-linux-x64/lib/tsc" --noEmit -p . > /dev/null 2>&1
t1=$(now)
echo "baseline: tsc --noEmit with TS 7.1.0-beta $(secs "$t0" "$t1") s"
t0=$(now)
node node_modules/typescript/bin/tsc --noEmit -p . > /dev/null 2>&1
t1=$(now)
echo "baseline: tsc --noEmit with TS 6.0.3 $(secs "$t0" "$t1") s"
cd "$ROOT"
compare "$SB" original

# Mutation: a copy of src/ without the leading `await`/`void` of each statement, to get real
# floating promises (with the seyfert types) to compare.
fresh_copy "$MUT"
mutated=$(grep -rEc '^[[:space:]]*(await|void) ' "$MUT/src" | awk -F: '{s += $2} END {print s}')
find "$MUT/src" -name '*.ts' -exec sed -E -i 's/^([[:space:]]*)(await|void) /\1/' {} +
echo "mutation: ${mutated} statements without await/void"
compare "$MUT" mutation

# Mutation for await-thenable: each `await x` becomes `await await x` (except `for await`); the
# outer `await` waits for the already resolved value, which is almost never a Promise.
fresh_copy "$MUT_AWAIT"
doubled=$(grep -rEo '\bawait ' "$MUT_AWAIT/src" | grep -c .)
for_await=$(grep -rEo '\bfor await ' "$MUT_AWAIT/src" | grep -c .)
find "$MUT_AWAIT/src" -name '*.ts' -exec sed -E -i 's/\bfor await /for __FOR_AWAIT__ /g; s/\bawait /await await /g; s/for __FOR_AWAIT__ /for await /g' {} +
echo "await mutation: $((doubled - for_await)) doubled awaits"
compare "$MUT_AWAIT" mutation-await

# Mutation for require-await: no `await` at all (except `for await`); async functions that return
# a Promise are still not reported.
fresh_copy "$MUT_NO_AWAIT"
find "$MUT_NO_AWAIT/src" -name '*.ts' -exec sed -E -i 's/\bfor await /for __FOR_AWAIT__ /g; s/\bawait //g; s/for __FOR_AWAIT__ /for await /g' {} +
echo "no-await mutation: $((doubled - for_await)) awaits removed"
compare "$MUT_NO_AWAIT" mutation-no-await

# Mutation for return-await: each `return x` becomes `return await x`. In functions that are not
# async the `await` parses the same and the rule does not look at them.
fresh_copy "$MUT_RETURN"
returns=$(grep -rEo '\breturn [^; ]' "$MUT_RETURN/src" | grep -c .)
find "$MUT_RETURN/src" -name '*.ts' -exec sed -E -i 's/\breturn ([^; ])/return await \1/g' {} +
echo "return-await mutation: ${returns} returns with await"
compare "$MUT_RETURN" mutation-return-await

# Mutation for the no-unsafe-* family: the `: string`, `: number` and `: boolean` annotations
# become `: any`, and those values get called, indexed, passed, assigned and returned.
fresh_copy "$MUT_ANY"
anys=$(grep -rEo ':[[:space:]]*(string|number|boolean)\b' "$MUT_ANY/src" | grep -c .)
find "$MUT_ANY/src" -name '*.ts' -exec sed -E -i 's/:([[:space:]]*)(string|number|boolean)\b/:\1any/g' {} +
echo "any mutation: ${anys} annotations turned into any"
compare "$MUT_ANY" mutation-any

# Mutation for prefer-optional-chain, prefer-includes, prefer-string-starts-ends-with,
# prefer-find, prefer-regexp-exec and dot-notation: Spider-Byte's own expressions rewritten into
# the forms they report. `a?.b` becomes `(a && a.b)`, `x.includes(y)` becomes
# `(x.indexOf(y) !== -1)`, `x.startsWith(y)` becomes `(x.indexOf(y) === 0)`,
# `.find((v) => …)` becomes `.filter((v) => …)[0]`, `/re/.exec(s)` becomes `s.match(/re/)` and
# `ctx.name` becomes `ctx["name"]`. Each rewrite applies to the result of the previous ones; the
# count is of the sites each one rewrites.
fresh_copy "$MUT_PREFER"
prefer_patterns=(
	'(^|[^.A-Za-z0-9_$])([A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)*)\?\.([A-Za-z_$][A-Za-z0-9_$]*)'
	'(^|[^.A-Za-z0-9_$])([A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)*)\.includes\(([^()]*)\)'
	'(^|[^.A-Za-z0-9_$])([A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)*)\.startsWith\(([^()]*)\)'
	'\.find\(\(([A-Za-z_$][A-Za-z0-9_$]*)\) => ([^()]*)\)'
	'(/[^/ ]+/[a-z]*)\.exec\(([A-Za-z_$][A-Za-z0-9_$]*)\)'
	'\bctx\.([A-Za-z_$][A-Za-z0-9_$]*)'
)
prefer_replacements=(
	'\1(\2 \&\& \2.\4)'
	'\1(\2.indexOf(\4) !== -1)'
	'\1(\2.indexOf(\4) === 0)'
	'.filter((\1) => \2)[0]'
	'\2.match(\1)'
	'ctx["\1"]'
)
rewritten=0
for i in "${!prefer_patterns[@]}"; do
	rewritten=$((rewritten + $(grep -rEo --include='*.ts' "${prefer_patterns[i]}" "$MUT_PREFER/src" | grep -c .)))
	find "$MUT_PREFER/src" -name '*.ts' -exec sed -E -i "s#${prefer_patterns[i]}#${prefer_replacements[i]}#g" {} +
done
echo "prefer mutation: ${rewritten} rewritten sites"
compare "$MUT_PREFER" mutation-prefer

# stable_compare DIR NAME: all the rules together in DIR with `stableTypeOrdering`, which makes
# TypeScript 6 order the members of a union as TypeScript 7 does: the messages that print a union
# are then the same in both tools. The option goes in a tsconfig that extends the one of DIR.
stable_compare() {
	local dir=$1 name=$2
	cd "$dir"
	mapfile -t FILES < <(ts_files)
	printf '%s\n' '{"extends": "./tsconfig.json", "compilerOptions": {"stableTypeOrdering": true}}' > tsconfig.stable.json
	"$ROOT/veslint" --project tsconfig.stable.json --config "$OUT/config.all.json" "${FILES[@]}" > "$OUT/$name.stable.veslint.txt" 2> /dev/null
	VESLINT_EVAL_CONFIG=$OUT/config.all.json VESLINT_EVAL_TSCONFIG=tsconfig.stable.json node node_modules/eslint/bin/eslint.js \
		--config veslint-eval.eslint.config.mjs --format json "${FILES[@]}" > "$OUT/$name.stable.eslint.json" 2> /dev/null
	echo "$name, all, with stableTypeOrdering:"
	compare_findings "$dir" "$OUT/$name.stable.eslint.json" "$OUT/$name.stable.veslint.txt"
	rm tsconfig.stable.json
	cd "$ROOT"
}

stable_compare "$SB" original
stable_compare "$MUT" mutation
stable_compare "$MUT_AWAIT" mutation-await
stable_compare "$MUT_NO_AWAIT" mutation-no-await
stable_compare "$MUT_RETURN" mutation-return-await
stable_compare "$MUT_ANY" mutation-any
stable_compare "$MUT_PREFER" mutation-prefer
