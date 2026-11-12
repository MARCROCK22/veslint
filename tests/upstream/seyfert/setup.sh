#!/usr/bin/env bash
# tests/upstream/seyfert/setup.sh DIR: makes DIR the directory the tests of @slipher/eslint-plugin
# 1.1.0 lint in (their `test/`: its tsconfig.json and fixtures/), with the node_modules their cases
# import: seyfert 5.2.0 from build/upstream/seyfert and @types/node (with undici-types) from
# build/upstream/types (see tests/upstream/README.md). Exits with 2, naming what is missing, when one
# of them is not there.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
DIR=$1
SEYFERT=$ROOT/build/upstream/seyfert/node_modules/seyfert
TYPES=$ROOT/build/upstream/types/node_modules
for package in "$SEYFERT" "$TYPES/@types/node" "$TYPES/undici-types"; do
	if [[ ! -e $package ]]; then
		echo "missing $package: see tests/upstream/README.md" >&2
		exit 2
	fi
done
rm -rf "$DIR"
mkdir -p "$DIR/node_modules/@types"
cp "$ROOT/tests/upstream/seyfert/tsconfig.json" "$DIR/"
cp -r "$ROOT/tests/upstream/seyfert/fixtures" "$DIR/"
# The file of most cases (RuleTester's default name), outside the tsconfig.json (an
# `allowDefaultProject` file): veslint gives tsgo a tsconfig with only it, which needs it on disk;
# its text comes from each case.
: > "$DIR/file.ts"
ln -s "$(readlink -f "$SEYFERT")" "$DIR/node_modules/seyfert"
ln -s "$(readlink -f "$TYPES/@types/node")" "$DIR/node_modules/@types/node"
ln -s "$(readlink -f "$TYPES/undici-types")" "$DIR/node_modules/undici-types"
