#!/usr/bin/env bash
# pin.sh: pins expected.txt, what ESLint 10.15.0 + svelte-eslint-parser 1.10.1 + typescript-eslint
# 8.72.2 give for the .svelte files of this directory with each JSON configuration (its rules and
# its parserOptions.svelteFeatures / svelteConfig; svelte.config.js says runes: false): one
# `<config>: <line>` per problem, as `veslint --config <config>.json --fixes` prints it. The "Svelte files"
# section of tests/run.sh compares veslint with it. And `function: <line>`, what ESLint and
# eslint-plugin-svelte 3.24.1 give with eslint.runes-function.config.mjs, whose svelteConfig has a
# runes function of the file name, for every .svelte file of the directory (run.sh compares the
# eslint.config.mjs resolved through bun with it).
set -uo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../../.. && pwd)
for config in config-no-runes config-true features-false features-true none; do
	RUNES_CONFIG=$config.json node "$ROOT/build/eval/spider-byte/node_modules/eslint/bin/eslint.js" \
		--config eslint.runes.config.mjs --format json options.svelte plain.svelte 2> /dev/null |
		python3 "$ROOT/tests/eslint_lines.py" fixes | sed "s|^$PWD/||; s|^|$config: |"
done > expected.tmp
node "$ROOT/build/eval/spider-byte/node_modules/eslint/bin/eslint.js" --config eslint.runes-function.config.mjs \
	--format json legacy-warn.svelte legacy.svelte options.svelte plain.svelte warn.svelte 2> /dev/null |
	python3 "$ROOT/tests/eslint_lines.py" fixes | sed "s|^$PWD/||; s|^|function: |" >> expected.tmp
LC_ALL=C sort expected.tmp > expected.txt
rm -f expected.tmp
wc -l < expected.txt
