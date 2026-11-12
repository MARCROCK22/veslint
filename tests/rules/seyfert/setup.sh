#!/usr/bin/env bash
# tests/rules/seyfert/setup.sh: links into tests/rules/seyfert/node_modules (which git ignores) the
# packages the fixtures of the seyfert/* rules import: seyfert 5.2.0 from build/upstream/seyfert and
# @types/node (with undici-types) from build/upstream/types, the ones of @slipher/eslint-plugin's own
# tests (see tests/upstream/README.md). Exits with 2, naming what is missing, when one of them is
# not there.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SEYFERT=$ROOT/build/upstream/seyfert/node_modules/seyfert
TYPES=$ROOT/build/upstream/types/node_modules
for package in "$SEYFERT" "$TYPES/@types/node" "$TYPES/undici-types"; do
	if [[ ! -e $package ]]; then
		echo "missing $package: see tests/upstream/README.md" >&2
		exit 2
	fi
done
NM=$ROOT/tests/rules/seyfert/node_modules
mkdir -p "$NM/@types"
# link TARGET NAME: NAME points to TARGET. Where `ln -s` copies instead (Git Bash on Windows without
# native symbolic links), a copy left by an earlier run is replaced, not linked into.
link() {
	[[ -L $2 || ! -e $2 ]] || rm -rf "$2"
	ln -sfn "$(readlink -f "$1")" "$2"
}
link "$SEYFERT" "$NM/seyfert"
link "$TYPES/@types/node" "$NM/@types/node"
link "$TYPES/undici-types" "$NM/undici-types"
