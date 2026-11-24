# veslint: TypeScript linter PoC with V + tree-sitter + tsgo (tsc --api).
# Pinned versions (PROMPT.md §2); never "latest".
TS_TAG   := v0.27.0
TSTS_TAG := v0.23.2
TSJS_TAG := v0.23.1
# The platform as Node names it (`<process.platform>-<process.arch>`): TypeScript's native compiler
# is the one of its npm package, and macOS builds with its own toolchain (clang, ar, shasum).
ifeq ($(shell uname -s),Darwin)
PLATFORM := darwin-$(if $(filter arm64,$(shell uname -m)),arm64,x64)
CC_V     := clang
# Apple's clang has no -ffat-lto-objects: the archive is only bitcode, which ld64 links with LTO.
TS_LTO   := -flto
AR_LTO   := ar
SHA256   := shasum -a 256
else
PLATFORM := linux-x64
CC_V     := gcc
TS_LTO   := -flto -ffat-lto-objects
AR_LTO   := gcc-ar
SHA256   := sha256sum
endif
TSGO     := node_modules/@typescript/typescript-$(PLATFORM)/lib/tsc
TS_CLI   := node_modules/.bin/tree-sitter
# The TypeScript grammar with the patch from patches/ is generated in build/; vendor/ stays as
# cloned.
GRAMMAR  := build/tree-sitter-typescript
TSTS_SRC := $(GRAMMAR)/typescript/src
# The same grammar in its `tsx` dialect (JSX), for .tsx files.
TSX_SRC  := $(GRAMMAR)/tsx/src
GRAMMAR_PATCH  := patches/tree-sitter-typescript.patch
GRAMMAR_CFLAGS := -O2 -std=c11 -fPIC -I$(TSTS_SRC)
V ?= v
# The V binary is a prerequisite of veslint: updating V rebuilds it.
V_BIN := $(shell command -v $(V))
# A V built from its C sources (as the release workflow builds it) has no tcc libgc.a: `v test` and
# the V programs tests/run.sh runs then build the bundled collector. The binary's real path: `v
# symlink` puts a link to it in the PATH, away from its thirdparty/.
TEST_VFLAGS := $(if $(wildcard $(dir $(realpath $(V_BIN)))thirdparty/tcc/lib/libgc.a),,-d use_bundled_libgc)

# TypeScript's API session linked into veslint (tsgo/inproc.c.v): a C archive built with Go from the
# checkout of the pinned commit (tsgo/inproc/build.sh fetches it when it is missing).
GO      ?= go
INPROC  := tsgo/inproc/out/libveslint_tsgo.a
# tree-sitter's library, compiled for link-time optimization (with the regular code too, for a
# build without it): the -prod link inlines veslint's calls into it (the nodes, the tree cursor),
# which made a lint without types about a tenth faster. build-windows.ps1 builds its own.
TS_LIB  := treesitter/out/libtree-sitter.a
LIBS    := $(TS_LIB) build/libtree-sitter-typescript.a $(INPROC)
SOURCES := $(filter-out %_test.v,$(wildcard *.v gcheap/*.v tsgo/*.v treesitter/*.v offsets/*.v rules/*.v jsregexp/*.v regexpp/*.v estree/*.v esquery/*.v codepath/*.v collation/*.v vue/*.v svelte/*.v svelte_compiler/*.v postcss/*.v))

.PHONY: deps build run test bench clean

deps: $(LIBS) $(TSGO)

vendor/tree-sitter:
	git clone --depth 1 --branch $(TS_TAG) https://github.com/tree-sitter/tree-sitter $@

vendor/tree-sitter-typescript:
	git clone --depth 1 --branch $(TSTS_TAG) https://github.com/tree-sitter/tree-sitter-typescript $@

# The JavaScript grammar the TypeScript one inherits from (version pinned in its package-lock).
vendor/tree-sitter-javascript:
	git clone --depth 1 --branch $(TSJS_TAG) https://github.com/tree-sitter/tree-sitter-javascript $@

# The flags of vendor/tree-sitter/Makefile, on its single-file build (lib.c includes the rest).
$(TS_LIB): | vendor/tree-sitter
	mkdir -p $(dir $@)
	$(CC_V) -O3 $(TS_LTO) -std=c11 -fPIC -fvisibility=hidden -D_POSIX_C_SOURCE=200112L \
		-D_DEFAULT_SOURCE -D_BSD_SOURCE -D_DARWIN_C_SOURCE -Ivendor/tree-sitter/lib/src \
		-Ivendor/tree-sitter/lib/src/wasm -Ivendor/tree-sitter/lib/include \
		-c vendor/tree-sitter/lib/src/lib.c -o $(dir $@)lib.o
	rm -f $@
	$(AR_LTO) rcs $@ $(dir $@)lib.o

# Copies the grammar, applies the patch and regenerates parser.c with the pinned CLI (0.24.4, the one
# upstream generated v0.23.2's with: without the patch it comes out identical). See internals.md, "Grammar".
$(TSTS_SRC)/parser.c: $(GRAMMAR_PATCH) $(TS_CLI) | vendor/tree-sitter-typescript vendor/tree-sitter-javascript
	rm -rf $(GRAMMAR)
	mkdir -p $(GRAMMAR)
	cp -r vendor/tree-sitter-typescript/common vendor/tree-sitter-typescript/typescript $(GRAMMAR)/
	patch -d $(GRAMMAR) -p1 < $(GRAMMAR_PATCH)
	cd $(GRAMMAR)/typescript && NODE_PATH=$(abspath vendor) $(abspath $(TS_CLI)) generate
	$(SHA256) $(GRAMMAR_PATCH) | cut -d' ' -f1 > $(GRAMMAR)/patch.sha256

build/ts-parser.o: $(TSTS_SRC)/parser.c
	cc $(GRAMMAR_CFLAGS) -c $< -o $@

build/ts-scanner.o: $(TSTS_SRC)/parser.c
	cc $(GRAMMAR_CFLAGS) -c $(TSTS_SRC)/scanner.c -o $@

# The tsx dialect is generated from the same patched common/ once the TypeScript one exists.
$(TSX_SRC)/parser.c: $(TSTS_SRC)/parser.c
	rm -rf $(GRAMMAR)/tsx
	cp -r vendor/tree-sitter-typescript/tsx $(GRAMMAR)/
	cd $(GRAMMAR)/tsx && NODE_PATH=$(abspath vendor) $(abspath $(TS_CLI)) generate

build/tsx-parser.o: $(TSX_SRC)/parser.c
	cc -O2 -std=c11 -fPIC -I$(TSX_SRC) -c $< -o $@

build/tsx-scanner.o: $(TSX_SRC)/parser.c
	cc -O2 -std=c11 -fPIC -I$(TSX_SRC) -c $(TSX_SRC)/scanner.c -o $@

$(INPROC): tsgo/inproc/build.sh tsgo/inproc/main.go tsgo/inproc/api_inprocess.go tsgo/inproc/api_fastjson.go tsgo/inproc/api_rules.go tsgo/inproc/session.patch tsgo/inproc/parser.patch tsgo/inproc/convert.go tsgo/inproc/convert_kinds.go
	GO=$(GO) tsgo/inproc/build.sh

build/libtree-sitter-typescript.a: build/ts-parser.o build/ts-scanner.o build/tsx-parser.o build/tsx-scanner.o
	ar rcs $@ $^

# npm only downloads the pinned binaries (tsgo and the tree-sitter CLI); `touch` avoids
# reinstalling them on every make.
$(TSGO): package.json package-lock.json
	npm ci
	@touch $@ $(TS_CLI)

$(TS_CLI): $(TSGO)

build: veslint

# LARGE_CONFIG builds libgc to grow its heap up to 16 MiB at a time instead of 8: it collects fully
# after each growth, so a live heap that only grows (the doubling constants of internals.md) is walked
# half as often. It costs about 0.5 MB of larger black-list tables (two of 256 KB instead of 32 KB),
# and up to 16 MiB more heap from the larger steps (Spider-Byte with every rule: 96 MiB instead of
# 86). V caches gc.o by its flags.
# gc_parallel_mark: libgc marks with a thread per CPU. Its collections stop every lint worker, and
# a typed lint of the TypeScript compiler collected 44 times for 2.2 s (1.7 s with it): 16.5 ->
# 16.1 s, recharts 4.39 -> 4.31 s, zod 2.41 -> 2.38 s (median of 3 alternated runs, minipc, the
# same memory). V's flag does nothing outside Linux and macOS.
veslint: $(LIBS) $(TSGO) $(SOURCES) tsgo/inproc/veslint_tsgo.h $(V_BIN)
	$(V) -prod -d gc_parallel_mark -cc $(CC_V) -cflags -DLARGE_CONFIG=1 -o veslint .

run: veslint
	./veslint app.ts

test: veslint
	@start=$$(date +%s); VFLAGS="$$VFLAGS $(TEST_VFLAGS)" $(V) test . && echo "time   v test: $$(( $$(date +%s) - start )) s"
	VFLAGS="$$VFLAGS $(TEST_VFLAGS)" V=$(V) tests/run.sh

bench: veslint
	$(V) run tests/gen_bench.vsh build/bench
	@echo "== one batch per file =="
	./veslint --bench --all-identifiers build/bench/src/*.ts > /dev/null
	@echo "== one request per identifier =="
	./veslint --bench --all-identifiers --per-identifier build/bench/src/*.ts > /dev/null

clean:
	rm -rf build veslint treesitter/out
