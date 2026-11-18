#!/usr/bin/env bash
# pin.sh: pins expected.txt, what ESLint 10.15.0 + vue-eslint-parser 10.4.2 + typescript-eslint
# 8.72.2 give for the .vue files of this directory with each JSON configuration (its rules and its
# parserOptions.vueFeatures): one `<config>: <line>` per problem, as `veslint --config <config>.json
# --fixes` prints it. The "Vue files" section of tests/run.sh compares veslint with it.
set -uo pipefail
cd "$(dirname "$0")"
ROOT=$(cd ../../.. && pwd)
for config in css-off falsy filter-off interpolation-off macros none; do
	FEATURES_CONFIG=$config.json node "$ROOT/build/eval/spider-byte/node_modules/eslint/bin/eslint.js" \
		--config eslint.features.config.mjs --format json filters.vue interpolation.vue macros.vue style.vue 2> /dev/null |
		python3 "$ROOT/tests/eslint_lines.py" fixes | sed "s|^$PWD/||; s|^|$config: |"
done | LC_ALL=C sort > expected.txt
wc -l < expected.txt
