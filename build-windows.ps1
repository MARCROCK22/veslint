# Builds veslint.exe on Windows x64 with MSYS2's UCRT64 gcc (PowerShell 7); the Makefile is
# Linux-only. See README, "Windows". The patched grammar in build/tree-sitter-typescript is copied
# from a Linux checkout that ran `make deps` (regenerating it needs the tree-sitter CLI), and it must
# be the one of patches/tree-sitter-typescript.patch. Delete a .a, or vendor/v, to rebuild it.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-Location $PSScriptRoot

# V at a commit of github.com/vlang/v (an older V does not parse the project), bootstrapped as its
# GNUmakefile does on Windows, from the C of the vlang/vc commit generated from that commit (its
# paths made portable by vc_compat_uint.ps1): no other V is needed.
$vCommit = '841595141fbb045527fd0ac986e8b6cb8aee5bcb'
$vcCommit = '45add16eb714cb4bd00acff989cd40b28185fc1f'
$v = 'vendor/v/v.exe'
if (-not (Test-Path $v)) {
	git init --quiet vendor/v
	git -C vendor/v fetch --quiet --depth 1 https://github.com/vlang/v $vCommit
	git -C vendor/v checkout --quiet FETCH_HEAD
	git init --quiet vendor/v/vc
	git -C vendor/v/vc fetch --quiet --depth 1 https://github.com/vlang/vc $vcCommit
	git -C vendor/v/vc checkout --quiet FETCH_HEAD
	Push-Location vendor/v
	try {
		powershell -NoProfile -ExecutionPolicy Bypass -File cmd/tools/vc_compat_uint.ps1 -Source vc/v_win.c -Destination vc/v_win_compat.c
		gcc -DCUSTOM_DEFINE_v1_fallback -std=c99 -municode -w -o v1.exe vc/v_win_compat.c -lws2_32 -lbcrypt
		# gcc in every stage: without -cc, V on Windows looks for a C compiler of its own choosing.
		./v1.exe -no-parallel -cc gcc -o v2.exe -gc none cmd/v
		./v2.exe -nocache -cc gcc -o v.exe -gc none cmd/v
		Remove-Item v1.exe, v2.exe, vc/v_win_compat.c
	} finally {
		Pop-Location
	}
}

# The grammar copied from Linux has to be the one of the patch: `make` writes the SHA-256 of the
# patch it generated it from next to it (with LF line endings, as in the repository).
$stamp = 'build/tree-sitter-typescript/patch.sha256'
if (-not (Test-Path $stamp)) {
	throw "missing ${stamp}: copy build/tree-sitter-typescript from a Linux checkout that ran ``make deps``"
}
$patch = [IO.File]::ReadAllBytes("$PSScriptRoot/patches/tree-sitter-typescript.patch")
$patch = [Text.Encoding]::UTF8.GetBytes([Text.Encoding]::UTF8.GetString($patch).Replace("`r`n", "`n"))
$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($patch)).ToLower()
if ((Get-Content $stamp -Raw).Trim() -ne $hash) {
	throw "build/tree-sitter-typescript was generated from another patches/tree-sitter-typescript.patch: copy it again from a Linux checkout of this commit that ran ``make deps``"
}

if (-not (Test-Path node_modules/@typescript/typescript-win32-x64/lib/tsc.exe)) { npm ci --omit=dev }

# tree-sitter at the tag of the Makefile (vendor/ is not in the repository).
$ts = 'vendor/tree-sitter'
if (-not (Test-Path $ts)) {
	$tsTag = (Select-String -Path Makefile -Pattern '^TS_TAG\s*:?=\s*(\S+)').Matches[0].Groups[1].Value
	git clone --quiet --depth 1 --branch $tsTag https://github.com/tree-sitter/tree-sitter $ts
}
if (-not (Test-Path "$ts/libtree-sitter.a")) {
	# Same flags as vendor/tree-sitter/Makefile, on its single-file build (lib.c includes the rest).
	gcc -O3 -std=c11 -fvisibility=hidden -D_POSIX_C_SOURCE=200112L -D_DEFAULT_SOURCE -D_BSD_SOURCE `
		"-I$ts/lib/src" "-I$ts/lib/src/wasm" "-I$ts/lib/include" -c "$ts/lib/src/lib.c" -o build/tree-sitter-lib.o
	ar rcs "$ts/libtree-sitter.a" build/tree-sitter-lib.o
}

# The library of the grammar, rebuilt when the grammar comes from another patch.
$built = 'build/libtree-sitter-typescript.sha256'
if (-not (Test-Path build/libtree-sitter-typescript.a) -or -not (Test-Path $built) -or
	(Get-Content $built -Raw).Trim() -ne $hash) {
	$objs = foreach ($dialect in 'typescript', 'tsx') {
		$src = "build/tree-sitter-typescript/$dialect/src"
		foreach ($file in 'parser', 'scanner') {
			gcc -O2 -std=c11 "-I$src" -c "$src/$file.c" -o "build/$dialect-$file.o"
			"build/$dialect-$file.o"
		}
	}
	Remove-Item -ErrorAction SilentlyContinue build/libtree-sitter-typescript.a
	ar rcs build/libtree-sitter-typescript.a @objs
	Set-Content -NoNewline $built $hash
}

# Not -prod: with MSYS2's gcc 14.2 every optimized build breaks some rule, a different one each
# (-O3 -flto: consistent-type-assertions crashes; -O2 -flto: it gives wrong findings; -O3 without
# LTO: no-unnecessary-type-parameters crashes). Unoptimized, every rule gives exactly its expected
# output, and a run takes the same time: tsgo is most of it.
& $v -cc gcc -o veslint.exe .
