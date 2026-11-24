#!/usr/bin/env bash
# Writes the npm packages of veslint to OUT, ready for `npm publish OUT/<package>`:
#
#   npm/stage.sh OUT linux-x64=<veslint> darwin-arm64=<veslint> darwin-x64=<veslint> win32-x64=<veslint.exe>
#
# OUT/veslint is @marcrock22/veslint (the `veslint` command, which runs the binary of the platform,
# and the README); OUT/<platform> is @marcrock22/veslint-<platform>, with the binary given for it.
# Each platform package depends on the TypeScript 7 compiler of its platform, which veslint finds
# in the closest node_modules (tsgo.binary_path_from).
set -euo pipefail
if [[ $# -lt 2 ]]; then
	echo "usage: npm/stage.sh OUT <platform>=<binary>..." >&2
	exit 2
fi
here=$(cd "$(dirname "$0")" && pwd)
out=$1
shift
mkdir -p "$out"
rm -rf "$out/veslint"
cp -r "$here/veslint" "$out/veslint"
cp "$here/../README.md" "$out/veslint/README.md"
chmod +x "$out/veslint/bin/veslint.js"
for pair in "$@"; do
	platform=${pair%%=*}
	binary=${pair#*=}
	if [[ ! -f $here/$platform/package.json || ! -f $binary ]]; then
		echo "npm/stage.sh: no package for $platform or no binary at $binary" >&2
		exit 2
	fi
	rm -rf "$out/$platform"
	cp -r "$here/$platform" "$out/$platform"
	exe=veslint
	[[ $platform != win32-* ]] || exe=veslint.exe
	cp "$binary" "$out/$platform/$exe"
	chmod +x "$out/$platform/$exe"
done
