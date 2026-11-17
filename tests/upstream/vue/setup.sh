#!/usr/bin/env bash
# tests/upstream/vue/setup.sh DIR: makes DIR the directory the typed cases of eslint-plugin-vue's
# tests lint in (a copy of tests/upstream/vue/fixtures, which is the clone's
# tests/fixtures/typescript: src/test.vue is the file of every typed case, src/test01.ts the module
# they import types from), with the node_modules their cases import: vue 3.5.45 with its @vue/*
# packages and csstype, from build/upstream/vue-deps (see README.md). Exits with 2, naming what is
# missing, when one of them is not there.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
DIR=$1
DEPS=$ROOT/build/upstream/vue-deps/node_modules
for package in "$DEPS/vue" "$DEPS/@vue/runtime-dom" "$DEPS/csstype"; do
	if [[ ! -e $package ]]; then
		echo "missing $package: see tests/upstream/README.md" >&2
		exit 2
	fi
done
rm -rf "$DIR"
mkdir -p "$DIR/node_modules/@vue"
cp -r "$ROOT/tests/upstream/vue/fixtures/." "$DIR/"
ln -s "$(readlink -f "$DEPS/vue")" "$DIR/node_modules/vue"
ln -s "$(readlink -f "$DEPS/csstype")" "$DIR/node_modules/csstype"
for package in "$DEPS"/@vue/*; do
	ln -s "$(readlink -f "$package")" "$DIR/node_modules/@vue/$(basename "$package")"
done
