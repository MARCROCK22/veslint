#!/usr/bin/env bash
# tests/upstream/setup.sh DIR: makes DIR the fixtures directory of typescript-eslint's own tests (a
# copy of tests/upstream/fixtures), with the node_modules its cases import: @types/node and
# @types/react with their dependencies, from build/upstream/types/node_modules (see README.md), and
# typescript and @typescript-eslint/{types,utils} of build/eval (TypeScript 6.0.3, typescript-eslint
# 8.62.0). Exits with 2, naming what is missing, when one of them is not there.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DIR=$1
TYPES=$ROOT/build/upstream/types/node_modules
EVAL=$ROOT/build/eval/spider-byte/node_modules
for package in "$TYPES/@types/node" "$TYPES/@types/react" "$EVAL/typescript" "$EVAL/@typescript-eslint/types" \
	"$EVAL/@typescript-eslint/utils"; do
	if [[ ! -e $package ]]; then
		echo "missing $package: see tests/upstream/README.md" >&2
		exit 2
	fi
done
rm -rf "$DIR"
mkdir -p "$DIR"
cp -r "$ROOT/tests/upstream/fixtures/." "$DIR/"
mkdir -p "$DIR/node_modules/@typescript-eslint"
for entry in "$TYPES"/*; do
	if [[ $(basename "$entry") == @* ]]; then
		mkdir -p "$DIR/node_modules/$(basename "$entry")"
		for package in "$entry"/*; do
			ln -s "$(readlink -f "$package")" "$DIR/node_modules/$(basename "$entry")/$(basename "$package")"
		done
	else
		ln -s "$(readlink -f "$entry")" "$DIR/node_modules/$(basename "$entry")"
	fi
done
ln -s "$EVAL/typescript" "$DIR/node_modules/typescript"
for package in types utils; do
	ln -s "$EVAL/@typescript-eslint/$package" "$DIR/node_modules/@typescript-eslint/$package"
done
