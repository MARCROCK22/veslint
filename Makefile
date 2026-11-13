# veslint: TypeScript linter PoC with V + tree-sitter + tsgo (tsc --api).
# Pinned versions (PROMPT.md §2); never "latest".
TS_TAG   := v0.27.0
TSTS_TAG := v0.23.2
TSJS_TAG := v0.23.1
TSGO     := node_modules/@typescript/typescript-linux-x64/lib/tsc
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

LIBS    := vendor/tree-sitter/libtree-sitter.a build/libtree-sitter-typescript.a
SOURCES := $(filter-out %_test.v,$(wildcard *.v tsgo/*.v treesitter/*.v offsets/*.v rules/*.v jsregexp/*.v regexpp/*.v estree/*.v esquery/*.v codepath/*.v))

.PHONY: deps build run test bench clean

deps: $(LIBS) $(TSGO)

vendor/tree-sitter:
	git clone --depth 1 --branch $(TS_TAG) https://github.com/tree-sitter/tree-sitter $@

vendor/tree-sitter-typescript:
	git clone --depth 1 --branch $(TSTS_TAG) https://github.com/tree-sitter/tree-sitter-typescript $@

# The JavaScript grammar the TypeScript one inherits from (version pinned in its package-lock).
vendor/tree-sitter-javascript:
	git clone --depth 1 --branch $(TSJS_TAG) https://github.com/tree-sitter/tree-sitter-javascript $@

vendor/tree-sitter/libtree-sitter.a: | vendor/tree-sitter
	$(MAKE) -C vendor/tree-sitter libtree-sitter.a

# Copies the grammar, applies the patch and regenerates parser.c with the pinned CLI (0.24.4, the one
# upstream generated v0.23.2's with: without the patch it comes out identical). See internals.md, "Grammar".
$(TSTS_SRC)/parser.c: $(GRAMMAR_PATCH) $(TS_CLI) | vendor/tree-sitter-typescript vendor/tree-sitter-javascript
	rm -rf $(GRAMMAR)
	mkdir -p $(GRAMMAR)
	cp -r vendor/tree-sitter-typescript/common vendor/tree-sitter-typescript/typescript $(GRAMMAR)/
	patch -d $(GRAMMAR) -p1 < $(GRAMMAR_PATCH)
	cd $(GRAMMAR)/typescript && NODE_PATH=$(abspath vendor) $(abspath $(TS_CLI)) generate
	sha256sum $(GRAMMAR_PATCH) | cut -d' ' -f1 > $(GRAMMAR)/patch.sha256

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
veslint: $(LIBS) $(TSGO) $(SOURCES) $(V_BIN)
	$(V) -prod -cc gcc -cflags -DLARGE_CONFIG=1 -o veslint .

run: veslint
	./veslint app.ts

test: veslint
	$(V) test .
	V=$(V) tests/run.sh

bench: veslint
	$(V) run tests/gen_bench.vsh build/bench
	@echo "== one batch per file =="
	./veslint --bench --all-identifiers build/bench/src/*.ts > /dev/null
	@echo "== one request per identifier =="
	./veslint --bench --all-identifiers --per-identifier build/bench/src/*.ts > /dev/null

clean:
	rm -rf build veslint
