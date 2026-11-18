#!/usr/bin/env bash
# pin.sh: pins expected.txt, what ESLint 10.15.0 + svelte-eslint-parser 1.10.1 + typescript-eslint
# 8.72.2 give for the .svelte files of this directory with each JSON configuration (its rules and
# its parserOptions.svelteFeatures / svelteConfig; svelte.config.js says runes: false): one
# `<config>: <line>` per problem, as `veslint --config <config>.json --fixes` prints it. The "Svelte files"
# section of tests/run.sh compares veslint with it.
set -uo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../../.. && pwd)
for config in config-no-runes config-true features-false features-true none; do
	RUNES_CONFIG=$config.json node "$ROOT/build/eval/spider-byte/node_modules/eslint/bin/eslint.js" \
		--config eslint.runes.config.mjs --format json options.svelte plain.svelte 2> /dev/null |
		python3 "$ROOT/tests/eslint_lines.py" fixes | sed "s|^$PWD/||; s|^|$config: |"
done | LC_ALL=C sort > expected.txt
wc -l < expected.txt
