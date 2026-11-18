#!/usr/bin/env bash
# pin.sh: pins what ESLint 10.15.0 + svelte-eslint-parser 1.10.1 + typescript-eslint 8.72.2 give for
# the .svelte files of tests/svelte-lint/fixtures (their project: tsconfig.json, env.d.ts, util.ts), which
# the "Svelte files" section of tests/run.sh compares veslint with:
#   - rules.json: the rules (every rule veslint has when it is pinned), with their default options;
#   - expected.txt: ESLint's problems with those rules and the types of the project service, as
#     `veslint --fixes` lines (sorted);
#   - fixed/<file>.svelte: each file after `eslint --fix`, and fixed/expected.txt what is left.
# Run it after changing the fixtures or the rules, and check the differences: veslint must give the
# same. It needs what tests/svelte-lint/compare.sh needs.
set -uo pipefail
cd "$(dirname "$0")"
DIR=$(pwd)
ROOT=$(cd ../.. && pwd)
ESLINT=$ROOT/build/eval/spider-byte/node_modules/eslint
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
(cd "$ROOT" && python3 - > "$DIR/rules.json") <<'PY'
import json, os
rules = sorted(os.path.relpath(d, 'tests/rules') for d, _, files in os.walk('tests/rules') if 'expected.txt' in files and 'node_modules' not in d and not d.startswith('tests/rules/svelte/'))
print(json.dumps({'rules': {r: 'error' for r in rules}}, indent=1))
PY
export SVELTE_LINT_RULES=$DIR/rules.json
# ESLint runs on copies with `typescript` in their node_modules, as in a project: without it,
# svelte-eslint-parser fails on a file without `lang` (it makes a JavaScript program for it).
for copy in lint fix; do
	mkdir -p "$TMP/$copy/node_modules"
	cp fixtures/*.svelte fixtures/*.ts fixtures/tsconfig.json "$TMP/$copy/"
	ln -s "$ROOT/build/upstream/svelte-deps/node_modules/typescript" "$TMP/$copy/node_modules/typescript"
done
(cd "$TMP/lint" && node "$ROOT/tests/svelte-lint/eslint_each.mjs" "$ESLINT/package.json" "$DIR/eslint.svelte.config.mjs" ./*.svelte ./*.svelte.ts 2> /dev/null |
	python3 "$ROOT/tests/eslint_lines.py" fixes | sed 's|^\./||' | LC_ALL=C sort > "$DIR/expected.txt")
(cd "$TMP/fix" && node "$ESLINT/bin/eslint.js" --config "$DIR/eslint.svelte.config.mjs" --fix --format json ./*.svelte ./*.svelte.ts 2> /dev/null |
	python3 "$ROOT/tests/eslint_lines.py" fixes | LC_ALL=C sort > "$DIR/fixed/expected.txt")
for file in fixtures/*.svelte fixtures/*.svelte.ts; do
	cp "$TMP/fix/${file##*/}" "$DIR/fixed/${file##*/}"
done
echo "$(wc -l < "$DIR/expected.txt") problems, $(wc -l < "$DIR/fixed/expected.txt") after --fix"
