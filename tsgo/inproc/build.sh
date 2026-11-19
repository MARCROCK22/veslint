#!/usr/bin/env bash
# build.sh builds tsgo/inproc/out/libveslint_tsgo.a: TypeScript's API session as a C archive that
# veslint links (tsgo/inproc.c.v). It compiles the Go module `tsc` of the TypeScript checkout at the
# commit of the npm package veslint uses, with this directory's two files added by `-overlay`
# (api_inprocess.go into internal/api, main.go as cmd/veslint_tsgo) and internal/api/session.go
# replaced by a copy with session.patch applied: the checkout is only read.
#
# TYPESCRIPT_GO is the checkout (default build/upstream/typescript-go, the one tools/ uses), GO the
# Go toolchain (default `go`; 1.27.x, as go.mod asks). GOBUILDFLAGS are added to `go build`.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd -P)
root=$(cd "$here/../.." && pwd -P)
checkout=${TYPESCRIPT_GO:-$root/build/upstream/typescript-go}
go=${GO:-go}
want=3e9236361fa97a9e6c685f4833ac457ae2d8c50a
# Without a checkout (a fresh clone, CI), only the module `tsc` at that commit is fetched, without
# its tests' data (357 MB) and the test-only package fourslash.
if [[ ! -d $checkout/tsc ]]; then
	mkdir -p "$checkout"
	git -C "$checkout" init -q
	git -C "$checkout" remote add origin https://github.com/microsoft/TypeScript
	git -C "$checkout" sparse-checkout set --no-cone '/tsc/' '!/tsc/testdata/' '!/tsc/internal/fourslash/'
	git -C "$checkout" fetch -q --depth 1 --filter=blob:none origin "$want"
	git -C "$checkout" -c advice.detachedHead=false checkout -q FETCH_HEAD
fi
module=$(cd "$checkout/tsc" && pwd -P)
got=$(git -C "$module" rev-parse HEAD)
if [[ $got != "$want" ]]; then
	echo "build.sh: $module is at $got; veslint uses TypeScript 7.1.0-beta ($want)" >&2
	exit 1
fi
out=$here/out
mkdir -p "$out/mod"
# cgo runs in the directory of the package, so the command is a module of its own in out/mod (a
# copy of main.go) that uses the checkout's module through `replace`. Its path is under the
# checkout's (…/tsc/veslint_tsgo), so it may import the checkout's internal packages; api_inprocess.go
# is added to internal/api with an overlay, so the checkout is only read.
cp "$here/main.go" "$out/mod/main.go"
cp "$module/go.sum" "$out/mod/go.sum"
cat > "$out/mod/go.mod" <<MOD
module github.com/microsoft/TypeScript/tsc/veslint_tsgo

go 1.27

require github.com/microsoft/TypeScript/tsc v0.0.0

replace github.com/microsoft/TypeScript/tsc => $module
MOD
# session.patch gives the lint workers a checker each in the programs they share (api_inprocess.go).
# git applies it as `patch` would, outside any repository (GIT_CEILING_DIRECTORIES).
rm -f "$out/session.go"
cp "$module/internal/api/session.go" "$out/session.go"
chmod u+w "$out/session.go"
(cd "$out" && GIT_CEILING_DIRECTORIES=$out git apply "$here/session.patch")
# The overlay's paths are absolute, so it is written per machine.
cat > "$out/overlay.json" <<JSON
{"Replace": {"$module/internal/api/veslint_inprocess.go": "$here/api_inprocess.go",
"$module/internal/api/veslint_fastjson.go": "$here/api_fastjson.go",
"$module/internal/api/session.go": "$out/session.go"}}
JSON
cd "$out/mod"
# The requirements of the checkout's go.mod, as `go mod tidy` would list them (without the network).
"$go" mod edit $(sed -n 's/^\t\([^ ]*\) \(v[^ ]*\).*/-require=\1@\2/p' "$module/go.mod" | tr '\n' ' ')
CGO_ENABLED=1 "$go" build -buildmode=c-archive -trimpath -buildvcs=false -overlay "$out/overlay.json" \
	${GOBUILDFLAGS:-} -o "$out/libveslint_tsgo.a" .
