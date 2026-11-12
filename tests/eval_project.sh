#!/usr/bin/env bash
# Evaluation of veslint on the sources of a real project (pinned commit): the ported rules with their
# default options, against typescript-eslint 8.62.0 (and @slipher/eslint-plugin 1.1.0 for the
# `seyfert/*` rules) run by ESLint 10.6.0, both through the same eslint.config, message by message.
# Everything stays in build/eval/. It is not part of `make test`.
#
#   tests/eval_project.sh zod               # a library with heavy types (.ts)
#   tests/eval_project.sh recharts          # React components (.ts and .tsx)
#   tests/eval_project.sh typescript        # the TypeScript 6.0.3 compiler: 381,000 lines, for scale
#   STABLE=1 tests/eval_project.sh zod      # plus `stableTypeOrdering` (TypeScript 6 orders types like 7)
#
# It prints the wall time of each tool and the peak resident memory of its processes.
#
# It needs bun, the ESLint that tests/eval_spider_byte.sh installs in build/eval/spider-byte and
# @slipher/eslint-plugin in build/upstream/seyfert (tests/upstream/README.md).
# Steps that use the network, each one only when its result is missing:
#   1. download the tarball of the commit (no git repository); of TypeScript, only its sources;
#   2. for recharts and TypeScript, `npm install --ignore-scripts` of what the sources import and
#      of the type packages, at the versions of the lock file (not the development tools). zod has
#      no dependencies at run time, so nothing is installed for it.
# Nothing of the projects is run: the table of diagnostics that TypeScript's build generates is
# written here from its JSON, as its script does.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
PROJECT=${1:-}
ESLINT_DIR=$ROOT/build/eval/spider-byte
OUT=$ROOT/build/eval/results
NAME=$PROJECT${STABLE:+-stable}
STABLE_OPTION=${STABLE:+, \"stableTypeOrdering\": true}

# What is taken from the tarball (everything by default) and which development dependencies
# are installed besides the type packages.
MEMBERS=()
KEPT=''
case $PROJECT in
zod)
	REPOSITORY=colinhacks/zod
	COMMIT=284243fb0d6532665afdc9239188773bb624f73c
	PACKAGE=$ROOT/build/eval/zod/packages/zod
	GLOBS="'**/*.ts'"
	# zod's base options, without the types of its test tools.
	TSCONFIG='{
  "extends": "../../.configs/tsconfig.base.json",
  "compilerOptions": { "noEmit": true, "types": [], "customConditions": ["@zod/source"]'$STABLE_OPTION' },
  "include": ["src/**/*.ts"],
  "exclude": ["src/**/*.test.ts", "src/**/tests/**", "src/**/benchmarks/**"]
}'
	sources() { find src -name '*.ts' -not -name '*.test.ts' -not -path '*/tests/*' -not -path '*/benchmarks/*' | sort; }
	;;
recharts)
	REPOSITORY=recharts/recharts
	COMMIT=a4a1f994091b1df26704ad8535038e81b7173d7b
	PACKAGE=$ROOT/build/eval/recharts
	GLOBS="'**/*.ts', '**/*.tsx'"
	# recharts' options for its sources, without emitting and without the types of its test tools.
	TSCONFIG='{
  "extends": "./tsconfig.base.json",
  "compilerOptions": {
    "noEmit": true,
    "incremental": false,
    "lib": ["DOM", "DOM.Iterable", "ES2023"],
    "preserveConstEnums": true,
    "target": "es6",
    "types": ["node"]'$STABLE_OPTION'
  },
  "include": ["./src/**/*", "types.d.ts"]
}'
	sources() { find src \( -name '*.ts' -o -name '*.tsx' \) -not -name '*.d.ts' | sort; }
	KEPT='react react-dom react-is'
	;;
typescript)
	REPOSITORY=microsoft/TypeScript
	COMMIT=050880ce59e30b356b686bd3144efe24f875ebc8
	PACKAGE=$ROOT/build/eval/typescript
	GLOBS="'**/*.ts'"
	# The sources without the tests of the compiler (most of the repository) and what they need.
	MEMBERS=(--wildcards --no-wildcards-match-slash '*/src' '*/package.json' '*/package-lock.json'
		'*/LICENSE.txt' '*/scripts/failed-tests.cjs' '*/scripts/failed-tests.d.cts')
	KEPT='chai diff ms source-map-support which mocha @esfx/canceltoken'
	# One project for what the repository builds as several, with the options of its base.
	TSCONFIG='{
  "extends": "./src/tsconfig-base.json",
  "compilerOptions": {
    "noEmit": true,
    "composite": false,
    "declaration": false,
    "declarationMap": false,
    "sourceMap": false,
    "emitDeclarationOnly": false,
    "isolatedDeclarations": false,
    "rootDir": "./src",
    "types": ["node", "mocha", "chai"]'$STABLE_OPTION'
  },
  "include": ["src/compiler", "src/services", "src/server", "src/harness", "src/testRunner", "src/jsTyping", "src/typingsInstaller", "src/typingsInstallerCore", "src/deprecatedCompat", "src/tsc", "src/tsserver", "src/typescript", "src/watchGuard"]
}'
	sources() { find src -name '*.ts' -not -path 'src/lib/*' -not -name '*.d.ts' | sort; }
	;;
*)
	echo "usage: tests/eval_project.sh zod|recharts|typescript" >&2
	exit 2
	;;
esac
PROJECT_DIR=$ROOT/build/eval/$PROJECT
mkdir -p "$OUT"

[[ -x ./veslint ]] || make build
if [[ ! -d $ESLINT_DIR/node_modules/eslint ]]; then
	echo "tests/eval_project.sh: run tests/eval_spider_byte.sh first (it installs ESLint in build/eval/spider-byte)" >&2
	exit 2
fi
SEYFERT_PLUGIN=$ROOT/build/upstream/seyfert/node_modules/@slipher/eslint-plugin
if [[ ! -d $SEYFERT_PLUGIN ]]; then
	echo "tests/eval_project.sh: missing $SEYFERT_PLUGIN: see tests/upstream/README.md" >&2
	exit 2
fi
if [[ ! -d $PACKAGE/src ]]; then
	mkdir -p "$PROJECT_DIR"
	curl -sL "https://codeload.github.com/$REPOSITORY/tar.gz/$COMMIT" | tar xz -C "$PROJECT_DIR" --strip-components=1 "${MEMBERS[@]}"
fi
if [[ -n $KEPT && ! -d $PACKAGE/node_modules ]]; then
	# What the sources import: the dependencies, the type packages and the packages in KEPT.
	[[ -f $PACKAGE/package.json.orig ]] || cp "$PACKAGE/package.json" "$PACKAGE/package.json.orig"
	python3 -I - "$PACKAGE/package.json.orig" "$PACKAGE/package.json" $KEPT << 'PY'
import json, sys
original = json.load(open(sys.argv[1]))
development = {name: version for name, version in original["devDependencies"].items()
               if name.startswith("@types/") or name in sys.argv[3:]}
json.dump({"name": "veslint-eval", "private": True, "dependencies": original.get("dependencies", {}),
           "devDependencies": development}, open(sys.argv[2], "w"), indent=2)
PY
	(cd "$PACKAGE" && npm install --ignore-scripts --no-audit --no-fund)
fi
if [[ $PROJECT == typescript && ! -f $PACKAGE/src/compiler/diagnosticInformationMap.generated.ts ]]; then
	# The table of diagnostics, as scripts/processDiagnosticMessages.mjs of the repository writes it.
	node - "$PACKAGE/src/compiler/diagnosticMessages.json" "$PACKAGE/src/compiler/diagnosticInformationMap.generated.ts" << 'JS'
const fs = require('node:fs');
const [input, output] = process.argv.slice(2);
const messages = JSON.parse(fs.readFileSync(input, 'utf8'));
const propertyName = name => name.split('').map(char => char === '*' ? '_Asterisk' : char === '/' ? '_Slash' : char === ':' ? '_Colon' : /\w/.test(char) ? char : '_').join('')
  .replace(/_+/g, '_').replace(/^_(\D)/, '$1').replace(/_$/, '');
const lines = [
  '// <auto-generated />',
  "// generated from 'src/compiler/diagnosticMessages.json'",
  '',
  'import { DiagnosticCategory, DiagnosticMessage } from "./types.js";',
  '',
  'function diag(code: number, category: DiagnosticCategory, key: string, message: string, reportsUnnecessary?: {}, elidedInCompatabilityPyramid?: boolean, reportsDeprecated?: {}): DiagnosticMessage {',
  '    return { code, category, key, message, reportsUnnecessary, elidedInCompatabilityPyramid, reportsDeprecated };',
  '}',
  '',
  '/* eslint-disable @typescript-eslint/no-unnecessary-type-assertion*/',
  '/** @internal */',
  'export const Diagnostics = {',
];
for (const [name, { code, category, reportsUnnecessary, elidedInCompatabilityPyramid, reportsDeprecated }] of Object.entries(messages)) {
  const property = propertyName(name);
  const unnecessary = reportsUnnecessary ? `, /*reportsUnnecessary*/ ${reportsUnnecessary}` : '';
  const elided = elidedInCompatabilityPyramid ? `${!reportsUnnecessary ? ', /*reportsUnnecessary*/ undefined' : ''}, /*elidedInCompatabilityPyramid*/ ${elidedInCompatabilityPyramid}` : '';
  const deprecated = reportsDeprecated ? `${!elided ? ', /*reportsUnnecessary*/ undefined, /*elidedInCompatabilityPyramid*/ undefined' : ''}, /*reportsDeprecated*/ ${reportsDeprecated}` : '';
  lines.push(`    ${property}: diag(${code}, DiagnosticCategory.${category}, "${property.slice(0, 100)}_${code}", ${JSON.stringify(name)}${unnecessary}${elided}${deprecated}) as DiagnosticMessage,`);
}
lines.push('};');
fs.writeFileSync(output, lines.join('\r\n'));
JS
fi

printf '%s\n' "$TSCONFIG" > "$PACKAGE/tsconfig.veslint.json"
cat > "$PACKAGE/veslint-eval.eslint.config.mjs" << CFG
import fs from 'node:fs';
import { createRequire } from 'node:module';
import tseslint from '$ESLINT_DIR/node_modules/typescript-eslint/dist/index.js';
const { plugin: seyfert } = createRequire(import.meta.url)('$SEYFERT_PLUGIN');
const { rules } = JSON.parse(fs.readFileSync(process.env.VESLINT_EVAL_CONFIG, 'utf8'));
export default [
  {
    files: [$GLOBS],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: { project: ['tsconfig.veslint.json'], tsconfigRootDir: import.meta.dirname },
    },
    plugins: { '@typescript-eslint': tseslint.plugin, seyfert },
    rules,
  },
];
CFG
python3 -I - "$OUT/$NAME.rules.json" tests/rules << 'PY'
import json, os, sys
# The directory of a rule is the one with an expected.txt, and its path is the rule's id.
rules = sorted(os.path.relpath(d, sys.argv[2]) for d, _, files in os.walk(sys.argv[2]) if 'expected.txt' in files)
json.dump({"rules": {rule: "error" for rule in rules}}, open(sys.argv[1], "w"))
print(f"rules: {len(rules)}")
PY
export VESLINT_EVAL_CONFIG=$OUT/$NAME.rules.json

# measure COMMAND...: runs the command and leaves in MEASURED its wall time and the peak resident
# memory of the process and of each of its children, by name (sampled from /proc).
measure() {
	local t0 pid p name peak key
	declare -A peaks=()
	t0=$(date +%s.%N)
	"$@" &
	pid=$!
	while kill -0 "$pid" 2> /dev/null; do
		for p in "$pid" $(pgrep -P "$pid" 2> /dev/null); do
			name=$(tr -d '\0' < "/proc/$p/comm" 2> /dev/null) || continue
			peak=$(awk '/^VmHWM:/ {print $2}' "/proc/$p/status" 2> /dev/null)
			[[ -n ${name:-} && -n ${peak:-} ]] || continue
			[[ -z ${peaks[$name]:-} || $peak -gt ${peaks[$name]} ]] && peaks[$name]=$peak
		done
		sleep 0.1
	done
	wait "$pid"
	MEASURED=$(printf '%.1f s' "$(echo "$(date +%s.%N) - $t0" | bc)")
	for key in "${!peaks[@]}"; do MEASURED+=", $key $((peaks[$key] / 1024)) MB"; done
}

cd "$PACKAGE"
mapfile -t FILES < <(sources)
export VESLINT_ESLINT_DIR=$ESLINT_DIR
measure "$ROOT/veslint" --config veslint-eval.eslint.config.mjs --project tsconfig.veslint.json "${FILES[@]}" > "$OUT/$NAME.veslint.txt" 2> "$OUT/$NAME.veslint.err"
veslint_measured=$MEASURED
measure node --max-old-space-size=8192 "$ESLINT_DIR/node_modules/eslint/bin/eslint.js" --config veslint-eval.eslint.config.mjs --format json "${FILES[@]}" > "$OUT/$NAME.eslint.json" 2> "$OUT/$NAME.eslint.err"
cd "$ROOT"
echo "$PROJECT: ${#FILES[@]} files${STABLE:+, with stableTypeOrdering}"
echo "  veslint: $veslint_measured"
echo "  eslint: $MEASURED"
grep '^warning' "$OUT/$NAME.veslint.err"
head -c 400 "$OUT/$NAME.eslint.err"

# Every message of ESLint (those of the rules and its own: directives, rules that are not defined)
# against every line of veslint, as multisets. A finding both have at the same place with another
# text is counted apart: the text prints a type, whose members TypeScript 6 and 7 may order
# differently.
python3 -I - "$PACKAGE" "$OUT/$NAME.eslint.json" "$OUT/$NAME.veslint.txt" << 'PY'
import collections, json, os, re, sys
root, eslint_json, veslint_txt = sys.argv[1:4]
prefixes = ("@typescript-eslint/", "seyfert/")
ref, fatal = collections.Counter(), set()
for f in json.load(open(eslint_json)):
    path = os.path.relpath(f["filePath"], root)
    for m in f["messages"]:
        rule_id = m.get("ruleId") or ""
        if m.get("fatal"):
            fatal.add(path)
        elif "messageId" in m and rule_id.startswith(prefixes):
            ref[(path, m["line"], m["column"], rule_id, m["messageId"], m["message"])] += 1
        else:
            severity = "error" if m["severity"] == 2 else "warning"
            ref[(path, m["line"], m["column"], rule_id or "eslint", severity, m["message"])] += 1
unescape = lambda s: re.sub(r"\\(.)", lambda m: {"n": "\n", "r": "\r", "t": "\t"}.get(m.group(1), m.group(1)), s)
mine = collections.Counter()
for line in open(veslint_txt):
    loc, rule, message_id, msg = line.rstrip("\n").split("\t", 3)
    path, l, c = loc.rsplit(":", 2)
    if path not in fatal:
        mine[(path, int(l), int(c), rule, message_id, unescape(msg))] += 1
only_ref, only_mine = ref - mine, mine - ref
place = lambda t: t[:5]
other_text = collections.Counter(map(place, only_ref.elements())) & collections.Counter(map(place, only_mine.elements()))
print(f"  eslint: {sum(ref.values())}  veslint: {sum(mine.values())}  identical: {sum((ref & mine).values())}"
      f"  same finding with another text: {sum(other_text.values())}"
      f"  only eslint: {sum(only_ref.values()) - sum(other_text.values())}"
      f"  only veslint: {sum(only_mine.values()) - sum(other_text.values())}"
      f"  files ESLint cannot parse: {len(fatal)}")
for t in sorted(only_ref.elements()):
    if place(t) not in other_text: print("  only eslint:", t)
for t in sorted(only_mine.elements()):
    if place(t) not in other_text: print("  only veslint:", t)
PY
