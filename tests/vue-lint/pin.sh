#!/usr/bin/env bash
# pin.sh: pins what ESLint 10.15.0 + vue-eslint-parser 10.4.2 + typescript-eslint 8.72.2 give for
# the .vue files of tests/vue-lint/fixtures (their project: tsconfig.json, env.d.ts, util.ts), which
# the "Vue files" section of tests/run.sh compares veslint with:
#   - rules.json: the rules (every rule veslint has when it is pinned), with their default options;
#   - expected.txt: ESLint's problems with those rules and the types of the project service, as
#     `veslint --fixes` lines (sorted);
#   - fixed/<file>.vue: each file after `eslint --fix`, and fixed/expected.txt what is left.
# Run it after changing the fixtures or the rules, and check the differences: veslint must give the
# same. It needs what tests/vue-lint/compare.sh needs.
set -uo pipefail
cd "$(dirname "$0")"
DIR=$(pwd)
ROOT=$(cd ../.. && pwd)
ESLINT=$ROOT/build/eval/spider-byte/node_modules/eslint
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
(cd "$ROOT" && python3 - > "$DIR/rules.json") <<'PY'
import json, os
rules = sorted(os.path.relpath(d, 'tests/rules') for d, _, files in os.walk('tests/rules') if 'expected.txt' in files and 'node_modules' not in d
         # The svelte/* rules belong to another plugin, which the Vue configuration of ESLint does not load.
         and not os.path.relpath(d, 'tests/rules').startswith('svelte/'))
required = json.load(open('tests/rules/required_options.json', encoding='utf-8'))
print(json.dumps({'rules': {r: ['error', *required[r]] if r in required else 'error' for r in rules}}, indent=1))
PY
export VUE_LINT_RULES=$DIR/rules.json
cd fixtures
node "$ROOT/tests/vue-lint/eslint_each.mjs" "$ESLINT/package.json" "$DIR/eslint.vue.config.mjs" *.vue 2> /dev/null |
	python3 "$ROOT/tests/eslint_lines.py" fixes | LC_ALL=C sort > "$DIR/expected.txt"
cp ./*.vue ./*.ts tsconfig.json "$TMP/"
(cd "$TMP" && node "$ESLINT/bin/eslint.js" --config "$DIR/eslint.vue.config.mjs" --fix --format json ./*.vue 2> /dev/null |
	python3 "$ROOT/tests/eslint_lines.py" fixes | LC_ALL=C sort > "$DIR/fixed/expected.txt")
for file in *.vue; do
	cp "$TMP/$file" "$DIR/fixed/$file"
done
echo "$(wc -l < "$DIR/expected.txt") problems, $(wc -l < "$DIR/fixed/expected.txt") after --fix"
