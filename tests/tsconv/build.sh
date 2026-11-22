#!/usr/bin/env bash
# build.sh builds tsgo/inproc/out/tsconv/tsconv (tests/tsconv/main.go): the converter's
# differential test. It is a module under the TypeScript module's path, as tsgo/inproc/build.sh
# makes the archive, with the converter's files added to internal/parser by the same overlay, and
# it links veslint's tree-sitter (treesitter/out/libtree-sitter.a and the grammar's archive).
#
# TYPESCRIPT_GO is the checkout (default build/upstream/typescript-go), GO the Go toolchain.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd -P)
root=$(cd "$here/../.." && pwd -P)
checkout=${TYPESCRIPT_GO:-$root/build/upstream/typescript-go}
go=${GO:-go}
module=$(cd "$checkout/tsc" && pwd -P)
out=$root/tsgo/inproc/out/tsconv
mkdir -p "$out/mod"
cp "$here/main.go" "$out/mod/main.go"
cp "$module/go.sum" "$out/mod/go.sum"
cat > "$out/mod/go.mod" <<MOD
module github.com/microsoft/TypeScript/tsc/veslint_tsconv

go 1.27

require github.com/microsoft/TypeScript/tsc v0.0.0

replace github.com/microsoft/TypeScript/tsc => $module
MOD
# The converter's files, as tsgo/inproc/build.sh adds them to the archive.
cat > "$out/overlay.json" <<JSON
{"Replace": {"$module/internal/parser/veslint_convert.go": "$root/tsgo/inproc/convert.go",
"$module/internal/parser/veslint_convert_kinds.go": "$root/tsgo/inproc/convert_kinds.go"}}
JSON
cd "$out/mod"
"$go" mod edit $(sed -n 's/^\t\([^ ]*\) \(v[^ ]*\).*/-require=\1@\2/p' "$module/go.mod" | tr '\n' ' ')
CGO_ENABLED=1 CGO_CFLAGS="-O2 -I$root/vendor/tree-sitter/lib/include" \
	CGO_LDFLAGS="$root/treesitter/out/libtree-sitter.a $root/build/libtree-sitter-typescript.a" \
	GOMAXPROCS=${GOMAXPROCS:-2} "$go" build -p 2 -trimpath -buildvcs=false -overlay "$out/overlay.json" \
	${GOBUILDFLAGS:-} -o "$out/tsconv" .
