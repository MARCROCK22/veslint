# veslint

A TypeScript linter PoC written in V:

- it parses with **tree-sitter**, statically linked, with its own patch of the TypeScript grammar (see "Grammar");
- it gets inferred types from **native TypeScript 7** (`tsc --api`, formerly "tsgo") by speaking its IPC protocol directly, **without Node at runtime**;
- it applies typescript-eslint rules ported to V, with messages, fixes and suggestions identical to the original ones (see "Rules");
- it honors ESLint's directive comments (`eslint-disable`, `/* eslint rule: … */`) and reads ESLint configurations, also `eslint.config.mjs`.

## Requirements

- Linux x86-64 and Windows x64 are the platforms veslint is built and tested on: Linux with the Makefile, Windows with `build-windows.ps1` (see "Windows" below). The TypeScript compiler it runs is the one of the machine (`@typescript/typescript-<platform>-<arch>`, chosen as the `typescript` package does).
- V at the commit the project is built with, `841595141fbb` of github.com/vlang/v (`make V=<its v>`); the release workflow and `build-windows.ps1` bootstrap it from the vlang/vc commit generated from it (`45add16eb714`).
- GCC (`cc`).
- `make`, `git`, `patch` and `npm`. npm is only used to download two pinned binaries: TypeScript 7.1.0-beta and the tree-sitter 0.24.4 CLI, which regenerates the patched grammar at build time.
- Optional: `bun`, only to read an ESLint configuration file (`--config eslint.config.mjs`). That file is JavaScript, so the project's own ESLint resolves it; a resolved copy (`--print-config`) needs no JavaScript runtime.
- Only for the scripts that compare with typescript-eslint (`tests/rules/reference.sh` and `tests/eval_spider_byte.sh`): `node`, `python3`, `bun`, `curl` and `bc`.

## Windows

veslint also runs on Windows x64, from Git Bash or the command prompt and with the VS Code extension, and reports what it reports on Linux.

**Requirements:** PowerShell 7, Git for Windows, MSYS2's UCRT64 gcc in PATH (`pacman -S mingw-w64-ucrt-x86_64-gcc`) and Node.js with npm. Optional, as on Linux: `bun`, for `--config eslint.config.mjs`.

**Build:** `pwsh ./build-windows.ps1` (the Makefile is Linux's). It:
- clones V at the commit the project is built with (`841595141fbb` of github.com/vlang/v) and the vlang/vc commit generated from it into `vendor/v`, and bootstraps it with gcc as V's own GNUmakefile does;
- runs `npm ci --omit=dev`, which brings the compiler of Windows (`@typescript/typescript-win32-x64`);
- clones tree-sitter at the tag of the Makefile and builds it with the flags of its Makefile;
- builds the library of the grammar in `build/tree-sitter-typescript`, which is copied from a Linux checkout of the same commit that ran `make deps` (regenerating it needs the tree-sitter CLI): `make` writes the SHA-256 of `patches/tree-sitter-typescript.patch` next to it, and the script refuses a grammar generated from another patch;
- builds `veslint.exe`, without `-prod` (below).

The repository keeps its files byte for byte (`.gitattributes`): the fixtures and their expected outputs depend on their line endings, which Git for Windows converts by default.

**Releases:** a tag `v*` runs `.github/workflows/release.yml`, which builds veslint for Linux x64 (`.tar.gz`) and Windows x64 (`.zip`, its grammar from the Linux job), each with the TypeScript 7 compiler it runs under `node_modules`, and the VS Code extension (`.vsix`), and publishes them as the GitHub release of the tag.

**What changes on Windows:**
- tsgo's pipes are read and written with Win32 calls (`tsgo/client_windows.c.v`; the POSIX ones are in `tsgo/client_nix.c.v`).
- TypeScript on Windows writes paths with `/` and the ids of its projects in lower case, so veslint compares a path of its own with one of tsgo through `tsgo.path_key` (lower case and `/` on Windows, the path itself elsewhere). New code that compares a path with a project id, a `configFileName`, the `fileNames` of a project, the path of a callback or of a declaration, or the files of a program must go through it.
- `VESLINT_CPUS` is checked and ignored: veslint restricts its CPUs on Linux only.
- `--print-config` writes relative paths with `/`, as on Linux.

**Not optimized:** with MSYS2's gcc 14.2, every optimized build breaks some rule: with `-O3 -flto` (`-prod`) consistent-type-assertions crashes copying a string whose length is a pointer, with `-O2 -flto` it gives wrong findings, and with `-O3` without LTO no-unnecessary-type-parameters crashes in a map. On Linux, the same V with the gcc 14.2 and 14.4 of the Docker images `gcc:14.2` and `gcc:14` builds the three, and all 120 rules give their expected output (182 checks with their fixes and the directives): it depends on the Windows target, not on gcc 14 alone, and it is not reduced yet. Unoptimized, a lint takes about the same: tsgo is most of it.

**Tests:** `V=vendor/v/v.exe tests/run.sh` in Git Bash, with Python 3 as `python3`. On Windows the robustness tests use `tests/fake_tsgo.v` compiled to `tsc.exe`, the tests of the CPUs are skipped, long lists of files go in batches under Windows' 32,767 characters, `ps -W` and PowerShell take the place of `pgrep`, and lists of files are sorted in byte order (`LC_ALL=C`) everywhere. The V tests run with `vendor/v/v.exe test .`: the tests of tsgo's processes (`tsgo/client_nix_test.v`) and of the CPUs (`cpu_limit_linux_test.v`) are POSIX and Linux ones. The extension: `npm test` in `editors/vscode`.

## Usage

```sh
make deps    # npm ci; clones tree-sitter v0.27.0, tree-sitter-typescript v0.23.2 and tree-sitter-javascript v0.23.1; patches and regenerates the grammar; builds the libs
make build   # v -prod -cc gcc -cflags -DLARGE_CONFIG=1 -o veslint .
make run     # ./veslint app.ts
make test    # V unit tests + tests/run.sh
make bench   # synthetic 200-file project and metrics
```

```
veslint <file.ts>... [--project <tsconfig.json>] [--all-identifiers] [--bench] [--per-identifier] [--rule <rule> | --config <eslint.config.mjs | rules.json> [--print-config]] [--fix] [--fixes]
```

- **`--rule <rule>`:** instead of listing types, applies one rule with its default options (see "Rules" below). It takes a single rule per run, named by its full ESLint id: `--rule @typescript-eslint/await-thenable`.
- **`--config <file>`:** applies several rules in a single pass. The file is an ESLint configuration (`eslint.config.mjs` and the like, resolved by ESLint itself through `bun`), the resolved JSON `--print-config` prints, or a JSON with the `rules` section of a configuration (the output of `eslint --print-config` works as is). See "Configuration" in "Rules". It cannot be combined with `--rule`. Neither `--rule` nor `--config` can be combined with `--all-identifiers` or `--per-identifier`.
- **`--fix`:** applies the fixes and rewrites the files, like `eslint --fix`; the problems that remain are printed.
- **`--fixes`:** prints, after each problem, its fix and its suggestions (see "Fixes and suggestions").
- **Files:** `.ts`, `.mts`, `.cts` and `.tsx` (with the grammar's tsx dialect). A JavaScript file (`.js`, `.jsx`, `.mjs`, `.cjs`) is a usage error: veslint only reads TypeScript.
- **`--server`:** a process for editors that stays alive between lints: it keeps tsgo, the project it has open and the parsers, and is given the text of files that are not saved (see "Server mode").

- **Output (type mode):** one line per identifier, with TAB-separated fields: `path:line:col`, `name`, `type` and, if the type is a literal, `(base: X)`.
  - The line and the column are the ones tsc and ESLint show: a line ends at CRLF, LF, a lone CR, U+2028 or U+2029, and the column is counted from there in UTF-16 units, plus 1. They come from the byte offset of the identifier, not from tree-sitter's rows, which only count LF.
- **`--project`:** uses that tsconfig. Without it, veslint takes the tsconfig files the configuration of a file names in `parserOptions.project` (the first one whose files include it, as typescript-eslint picks the program), or else looks for the closest `tsconfig.json` going up from the file.
- **`--all-identifiers`:** queries every `identifier` node, not only declared names.
- **`--bench`:** writes a JSON with the time of each phase to stderr.
- **`--per-identifier`:** sends one request per identifier instead of one batch per file. Useful for comparison in the benchmark.
- **Several files:** they are accepted in a single run, with a single tsgo process and one batch per file.
- **`VESLINT_TIMEOUT_MS`:** timeout of each request to tsgo, and of the `--version` check before them. The default is 30000; the tests lower it to exercise the timeout.
- **`VESLINT_CPUS`:** how many CPUs veslint and the tsgo it starts run on: 2 by default (the CPU veslint started on and one of another core, among those it may use), 0 for all of them. veslint and tsgo answer each other hundreds of times in a lint, one waiting while the other works, and on more CPUs each wait lets a CPU fall into a deep sleep state that empties its caches (see "Speed" in "Server mode"). It does nothing outside Linux (it is still checked); a command line resolves its `eslint.config.*` (with `bun`) before, on every CPU.
- **Exit codes:**
  - 0: all good;
  - 1: a tsgo, protocol or position-mismatch error, or the rules found problems (those of a rule set to "warn" do not count, as in ESLint);
  - 2: incorrect usage.

Output of `./veslint app.ts`, the acceptance case:

```
app.ts:2:7	saludo	"Hola Vlang"	(base: string)
app.ts:3:5	mensaje	string
app.ts:4:7	año	2026	(base: number)
app.ts:4:25	fiesta	"🎉"	(base: string)
app.ts:4:46	x	1	(base: number)
app.ts:5:7	nada	null
app.ts:6:10	suma	(a: number, b?: number | undefined) => number
app.ts:6:15	a	number
app.ts:6:26	b	number | undefined
app.ts:9:7	resultado	number
```

## VS Code

`editors/vscode/` is an extension that shows what veslint reports for the TypeScript files you open, save and type: the problems, their fixes and suggestions as quick fixes, a comment that disables a rule for a line, and a fix-all action (`source.fixAll.veslint`). Each workspace folder has a `veslint --server`, which is given the text of a file with unsaved changes as it is typed (after `veslint.typingDelay` milliseconds, 0 by default), and is told which files changed on disk; with a veslint without the server mode, each lint runs veslint again and only saved text is linted. It asks ESLint for the configuration of each file once and keeps it until a configuration file changes. It is plain JavaScript without dependencies, so there is nothing to compile: `vsce package` builds the `.vsix` (the command is in its README, with its settings and its limits). Its tests (`npm test` in that directory) are the parser of the output, the runner and the server client with the real binary on `tests/config` and `tests/server`, and the extension itself against a stub of the editor's API; it has not been driven inside a running editor.

## Server mode

`veslint --server` (`server.v`) reads one JSON request per line on stdin and writes one JSON answer per line on stdout, in order, until stdin ends. It runs in the directory a command line would run in.

- **A request:** `{"id": 1, "config": "rules.json", "project": "", "files": ["/abs/a.ts"], "texts": {"/abs/a.ts": "…"}, "fixes": true, "changed": [], "created": [], "deleted": [], "forget": [], "reset": false}`. `files` are linted with `config` as `veslint --config <config> [--fixes] <files>` would lint them, and printed as they are given (relative ones are relative to the directory of the server); `project` is `--project`. A request without files only records the texts and the changes it carries.
- **The answer:** `{"id": 1, "code": 1, "stdout": "…", "stderr": "…"}`: exactly what that command line prints on each stream, and its exit code; only the usage text the command line prints after an error in what it is given (code 2: the configuration, a JavaScript file) is left out. After such an error the server goes on; after an error of tsgo (code 1) the next request starts tsgo again. A line that is not a JSON object is answered with `id` -1 and code 2.
- **Requests sent together:** a client may send a request before the answer to the previous one: a thread reads them as they come. A request whose files a later request lints too is given up, before it starts or between two rules, and answered `{"id": 1, "code": 0, "stdout": "", "stderr": "", "cancelled": true}`; the texts and changes it carries count all the same. An editor sends one for each change of a file, so only the last one is linted in full: deleting the `await` of `await Bun.sleep(1000)` in Spider-Byte's `src/index.ts` with backspace, a key every 60 ms, with all the rules, its finding comes about 130 ms after the last key instead of about 155 ms (on the minipc, 2026-11-12). A lint is not given up within a request to tsgo: the first rule that needs types waits for tsgo to compute them again in the new snapshot, which is most of a lint after a change.
- **Unsaved text:** each text of `texts` is what tsgo reads for its file (its `readFile` callback), whether the request lints that file or not, and so what the files that import it see, until a later request lints the file without its text or names it in `forget` (saved, reverted or closed).
- **What it keeps:** tsgo and the project it has open, and the snapshot of the last request with its checkers, while nothing changed; after a change, the syntax trees of the files whose declarations the rules look at (`DeclarationAsts`), except those of the files tsgo reads again: without them, every lint after a keystroke asked tsgo again for the trees of the 57 declaration files of Spider-Byte's `src/index.ts`, half of its time. A file that changed on disk is read again only when a request names it in `changed`, `created` or `deleted` (the server does not watch the disk); `reset` makes tsgo forget every file it read, for a `tsconfig.json` or a package that changed. Each new snapshot releases the previous one.
- **Speed** (one core, median of five runs, through the client of the VS Code extension; on 2026-10-14, on the main PC, a Ryzen 7 5800XT, with TypeScript 7.0.2): on `src/index.ts` of Spider-Byte (177 lines, the 61 rules with their configuration already resolved), a run of the command line takes 0.54 s; the server takes 0.56 s for its first request, 53 ms for a lint after a save, 54 ms with unsaved text, and 16 ms for a file that did not change. Of those 54 ms, about 26 are tsgo computing the types again in the new snapshot, 15 the other requests to tsgo, and 10 the work of the rules; tsgo answers one request at a time, so running the rules in parallel threads would gain little. On the TypeScript compiler, `src/compiler/program.ts` (5,201 lines, 901 findings) takes 2.01 s with the command line; with the server, 1.16 s after a save, 1.06 s with unsaved text and 0.46 s unchanged: there the rules themselves are most of the time, since a new snapshot starts their type caches again. On the minipc (an i3-4150T from 2014, one core, `build/testdata/tools/bench_speed.mjs`, TypeScript 7.1.0-beta, 2026-11-11), with the same 61 rules, `src/index.ts` takes 1.15 s with the command line, and the server 1.22 s for its first request, 35 ms for a file that did not change and about 115 ms with unsaved text or after a save; about half of those lints take about 200 ms instead, so the median of five or eleven runs lands on either. Those slow ones are collections of Go's garbage collector in tsgo: with `GOGC=400` fewer than one in ten were slow on one core, but tsgo took 640 MB instead of 290, and on all four CPUs it did not help, so veslint leaves the collector as it is. `program.ts` (891 findings with TypeScript 7.1) takes 4.0 s with the command line, and the server 4.0 s, 1.17 s unchanged, 2.58 s with unsaved text and 2.59 s after a save. With the 105 rules (the 61 and the 44 without types, with `someday.ts`'s options for those it configures: `build/testdata/bench/config-105.json`), the command line takes the same on both files; the server takes 4 to 10 ms more on `src/index.ts` and 0.1 to 0.15 s more on `program.ts` (926 findings).
- **CPUs** (on the minipc without `taskset`, 2026-11-11; 60 lints of `src/index.ts` with unsaved text through the client of the extension): a lint makes 475 requests to tsgo, and at each one veslint and tsgo wait for each other. On all four CPUs those lints took 182 to 267 ms in the median and up to about 360 ms, because each wait let a CPU fall into its deepest sleep state (C7s, which empties its caches and takes 0.17 ms to leave): the kernel counted about 530 entries into it per lint (`/sys/devices/system/cpu/cpu*/cpuidle/`), and about 57 on the two CPUs veslint and tsgo were kept on. So veslint keeps itself and tsgo on two CPUs (`VESLINT_CPUS`, `cpus.v`): a lint takes 106 ms in the median and 154 ms at the 90th percentile, instead of 192 to 220 and 311 to 324 ms on all four; the first request 0.81 s instead of 0.74 s, since tsgo loads the project with two CPUs; a run of the command line on that file 0.79 s instead of 0.73 s; and the 125 files of zod with the 105 rules 10.9 s instead of 13.4 to 24.9 s (that much did it vary on all four), with the same 7,678 lines. The main PC was not measured.
- **Memory:** over 400 lints of Spider-Byte's `src/index.ts`, each with another unsaved text, the server stayed at 68 MB and tsgo between 340 and 348 MB, without growing.
- **The configuration:** each request reads it again, which costs nothing for a JSON; an `eslint.config.*` would run ESLint through `bun` on every request, so an editor should give the server the resolved copy (`--print-config`), as the extension does.

## How it works

| File | What it does |
|---|---|
| `treesitter/` | Minimal tree-sitter bindings. Collects identifiers with their byte offset, through the declarations query or a `TSTreeCursor`, and provides helpers to walk nodes. `node_index.v` holds the nodes of a file by kind, from a single walk, for the rules to ask. `dialect.v` tells the dialect of a file by its extension, and the JavaScript files, which are rejected. |
| `offsets/` | Strips the BOM and converts UTF-8 byte offsets to UTF-16 units in a single pass. tsgo counts in UTF-16 and without the BOM. It also finds the lines of a file as TypeScript and ESLint count them, for every position that is printed, and decodes a file that is not valid UTF-8 as Node does (`decode.v`). |
| `tsgo/` | Client of `tsc --api`. `framing.v` has the MessagePack tuples `[type, method, JSON payload]`; `client.v`, the process, the thread that reads messages, the one that drains stderr, the timeout and the orderly shutdown; `api.v`, the methods and types of the API; `ast.v`, the binary AST of `getSourceFile`, used to name nodes; `ast_tree.v`, the navigation of that AST in any file of the program (parents, children by property, JSDoc), used to read the declarations of symbols; `platform.v`, the path of the compiler of the machine; `api_members.v`, the members and exports of a symbol and the type of a parameter. |
| `rules/` | The rules ported to V, one per file. They share `rules.v` (the `Checker` and running the rules over a file), `type_queries.v` (types per node, with caches), `options.v` (rule options), `specifiers.v` (type specifiers of the options), `promises.v` (promise and builtin-symbol helpers), `unsafe.v` (`any` helpers of the `no-unsafe-*` family), `estree.v` (ESTree shapes on tree-sitter nodes), `literals.v` and `js_values.v` (the values of JavaScript literals and the semantics of its operators), `scope.v` (lexical scopes, like typescript-eslint's scope manager), `static_value.v` (eslint-utils' `getStaticValue`), `unicode_case.v` (`toUpperCase` and `toLowerCase` as V8 does them, for the names typescript-eslint and ESLint compare one UTF-16 unit at a time and for the constants), `static_builtins.v`, `unicode_normalization.v` and `js_math.v` (more functions `getStaticValue` calls: the URI functions, `String.fromCodePoint`, `Number.prototype.toString` with a radix, `normalize`, V8's fdlibm for `Math`…), `regexp_syntax.v` (which regular expressions V8 accepts, and their structure), `regexp_match.v` (a matcher of JavaScript's `u` mode, for the options that are patterns), `directives.v` (ESLint's directive comments and inline configuration), `code_path.v` (whether the end of a function is reachable, as in ESLint's code path analysis), `type_readonly.v` (typescript-eslint's `isTypeReadonly`), `unused_variables.v` (the unused variables of typescript-eslint's `no-unused-vars` analysis, for `naming-convention`), `fixes.v` (fixes and suggestions) with `fix_tokens.v`, `fix_precedence.v` and `fix_wrapping.v` (ESLint's tokens and typescript-eslint's fixer utilities), `type_origins.v`, `type_sources.v`, `conditional_roots.v` and `mapped_parts.v` (where a type comes from and the declarations of the conditional and mapped types it leads to, for the parts of a type the API does not give), `checker_calls.v` (`getTypeOfSymbolAtLocation` and the contextual type of an argument), `awaited_type.v` (the checker's `getAwaitedType`, asked to tsgo), `await_identifier.v` (an `await` that TypeScript reads as a name), `json_schema.v` with `rule_schemas.v` (ESLint's validation of the options against the schema of each rule), `levn.v` (the parser of ESLint's configuration comments), `regexp_annex_b.v` (a regular expression without flags as V8 runs it, for the `package` of a type specifier), and `json_errors.v` (the messages of V8's `JSON.parse`). |
| `tools/` | Development-time generators, run with Node only when a pinned version changes: the child properties of the tsgo AST (`tsgo/ast_properties.v`), ESLint's globals and the ones typescript-eslint's libs declare (`rules/scope_globals.v`), V8's Unicode tables for regular expressions (`rules/regexp_unicode.v` to validate them, `rules/regexp_property_data.v` to match them), the natively bound members of `unbound-method` (`rules/unbound_method_natives.v`), the rule names of ESLint and typescript-eslint (`rules/eslint_rule_names.v`), the schemas and default options of the rules (`rules/rule_schemas.v`) the case conversions and the normalization of V8's strings (`rules/unicode_case_data.v`, `rules/unicode_normalization_data.v`) and the expected values of the unit tests that have them (`tests/*_cases.json`). veslint itself never runs Node. |
| `config.v` | Reads the `rules` section of a configuration and merges each rule's options with its defaults. |
| `cpus.v` | Keeps veslint, and so the tsgo it starts, on two of the CPUs it may use (`VESLINT_CPUS`), where they wait for each other without the CPUs falling asleep in between. |
| `eslint_config.v` | `--config`: runs `bun` with the script that asks the project's ESLint for the configuration of each file, and reads the resolved JSON. |
| `main.v` | CLI. Sends one `getSymbolsAtPositions` and one `getTypesAtPositions` request per file. Checks that every resolved symbol has the same name as the tree-sitter identifier. Requests `typeToString` and `getBaseTypeOfLiteralType` with a cache by id. |
| `server.v` | `--server`: the loop of requests and answers, the texts served to tsgo, and the snapshot kept between requests. |

**The name check** catches any mismatch between tree-sitter and tsgo. For example, if byte offsets were sent, it would fail at the `x` of `app.ts`. Before comparing, it undoes the escaping TypeScript applies to symbol names: `__filename` arrives as `___filename`. It allows two exceptions, checked with 7.0.2:

- `export default function foo` resolves to the `default` symbol;
- an identifier written with escapes (`abc`) resolves to its decoded name.

**Paths:** tsgo gets them absolute but without resolving symlinks, because tsgo knows each file by its path inside the project.

**Shutting tsgo down:**
- With stdin open, tsgo ignores SIGTERM. So veslint closes its stdin, waits up to 2 s and, if it is still alive, sends SIGKILL. Then it reaps the process, leaving no zombies.
- Writing each request also honors the timeout, even if tsgo stops reading.
- If tsgo sends messages nobody asked for, the shutdown drains the reader channel and does not hang.
- The `--version` check has the same timeout: a binary that does not answer and exit in time is killed and reaped.

## Grammar

veslint uses the tree-sitter-typescript v0.23.2 grammar with a patch, `patches/tree-sitter-typescript.patch`, that brings it closer to how TypeScript reads the code. `make deps` copies the grammar from `vendor/` to `build/`, applies the patch and regenerates its `parser.c` with the tree-sitter 0.24.4 CLI, the same one upstream generated v0.23.2's with. `vendor/` stays as cloned.

**What it fixes:**
- **The postfix `!`** goes at the level of `.` and `[…]`. Before, `c && p!`, `x + y!`, `-p!` or `<T>x!` were read as `(c && p)!`, etc.
- **`as` and `satisfies`** go at the level of relational operators and below `await`. Before, `c && p as T`, `x == y as T` or `await p as T` were read as `(c && p) as T`, `(x == y) as T` and `await (p as T)`.
- **Blocks:** a statement that starts with `{` is a block, also the body of an arrow, so `{ cb: f() }` is a label and a call, not an object.
- **`accessor`:** accepts `static`, `abstract` and `override` before it (`static accessor x = 1`) and works as a name (`accessor = 1`, `accessor()`). Before, it gave `ERROR` nodes.
- **Qualified types:** a qualified name takes every `.` that follows it, so `x as A.B.C` and `x satisfies A.B.C` are read as in TypeScript. Before, with three or more levels they were read as `(x as A.B).C`.
- **Constructor types:** like a function type, a constructor type takes the union, intersection or conditional that follows, so `new () => A | B` is `new () => (A | B)`. Before, it was read as `(new () => A) | B`.
- **`readonly`** binds tighter than a union, an intersection or a conditional, so `readonly A[] | B` is `(readonly A[]) | B`. Before, it was read as `readonly (A[] | B)`. `keyof readonly T[]` is accepted.
- **Import types** take type arguments (`import('./x').Y<T>`) and are primary types like any other name: `import('./x').Y[]`, `import('./x').Y['key']` and `(import('./x').Y | undefined)[]`. Before, an import type could only be a whole type, so the three gave `ERROR` or `MISSING` nodes: declaration files written by the compiler are full of them.
- **`new X!()`** is `new (X!)()`. Before, it was read as `(new X)!()`.
- **`<` after a line break:** outside an expression it starts a new member, so a generic call signature can follow a member without `;` (`{ a: number⏎ <T>(x: T): T }`). Before, it gave `ERROR` nodes; code written without semicolons had most of them.
- **`a < (-2)`** is a comparison. Before, it was read as an instantiation expression with a missing `>`.
- **`using` and `await using`** are declarations (`lexical_declaration` with that kind), also in `for (using x of y)`. Before, the grammar read `using x = y` as an assignment.
- **Tagged templates** take type arguments: ``tag<T>`x` ``. Before, it was read as two comparisons.
- **`a < (b) || c > (d)`** is two comparisons. Before, it was read as a call with the type arguments `<(b) || c>`: a union that starts with `|` now loses when the code can be read in another way.
- **A `global { }` block nested in a `declare module`** is read. Before, the word `global` gave an `ERROR` node.
- **Variance annotations** (`<in out T>`) and **escapes in template literal types** are accepted. Before, both gave `ERROR` nodes.
- **`export type * from 'm'`** and **`export type * as ns from 'm'`** are export statements. Before, they gave an `ERROR` node.
- **After the block of an arrow function**, a next line that starts with `(`, `[` or `<` is another statement, as in JavaScript (nothing continues an arrow function). Before, it was read as a call of the arrow, an access to it or a comparison. A function expression is still called.
- **`abstract` and `out` are names** where the code uses them as one: `interface X { abstract: boolean }`, `class C { abstract = 1 }`, `type O<out> = out`. Before, they gave `ERROR` or `MISSING` nodes.
- **An optional destructured parameter in a function type**: `({ a }?: T) => void`. Before, the automatic semicolon that the scanner gives before a `}` made it an object type.
- **The signature of a default export** has no name: `export default function (a: string): void;`. Before, it gave an `ERROR` node.
- **The target of a rest element** may be in parentheses: `[...(x as T)] = list`. Before, it gave a `MISSING` node.
- **A call with type arguments** has a member expression as its callee, as in TypeScript: `await f<T>(x)` is `await (f<T>(x))`, and the same after `!`, `-`, `typeof` or `+`. Before, the callee was the whole `await f`, with no error in the tree, so the call and the `await` were left unanalyzed. Whether the `<` opens type arguments or compares is tried both ways, and the type arguments win when both can be read: `f<A, B>(true)` and `f<Record<string, string>>(x)` are calls, which some contexts read as comparisons before.
- **`a < b && c > (d)`** is two comparisons joined by `&&`, like `a < (b) || c > (d)`: an intersection that starts with `&` loses too when the code can be read in another way.
- **The name of a tuple member** may be a word that is also a type or a modifier: `[symbol: Symbol, type?: string]`. Before, it gave an `ERROR` node.
- **A lone `&` in JSX** is text, in the string of an attribute (`href="x?a=1&b=2"`) and between tags (`R&D`), unless it starts a character reference. Before, it gave an `ERROR` node.
- **An import type** used as a type has a node of its own, `import_type`, around the `import('./x').A.B` that the grammar reads as a call and member accesses. The rules skip it where they look for real ones.
- **JSX element names** (tsx dialect) are `jsx_identifier` and `jsx_member_expression` nodes, like ESTree's, so no rule takes `<Ns.Button />` for a member access.
- **A union or an intersection that starts with `|` or `&`** is one node with that token, as in TypeScript: `| A | B` is a union of `A` and `B`, `| A | B | C` nests to the left like `A | B | C`, and `| A` is a union of one member. Before, the first member was a union of its own inside the other.
- **Type arguments without a call** (an instantiation expression, `f<T>`) belong to the member expression before them: `!f<T>` is `!(f<T>)` and `await f<T>` is `await (f<T>)`, and the same after `-`, `+`, `~`, `typeof`, `void` and `delete` and on the right of a binary operator. Before, they were read as `(!f)<T>`.
- **Type arguments or comparisons** is decided as TypeScript does (`canFollowTypeArgumentsInExpression`), by what follows the `>`: never type arguments before `<`, `>`, `+` or `-`; a call before `(` or a template; otherwise type arguments after a line break, before a binary operator or before what cannot start an expression. The scanner decides it, with an empty token after the type arguments. So `a < b > -c` and `foo(a < b, c > -1)` are comparisons, and `const make = f<T>⏎foo()` is an instantiation expression and another statement. Before, each was read one way or the other by chance.
- **A `<` comparison loses** when the code can be read with type arguments, which TypeScript tries first: `f<A<B> | null>(x)` and `f<() => { a: { b: number } }>(x)` are calls.
- **`typeof import('./x').y`** in a type is a type query whose name is an import type, the `import_type` node, as in ESTree; with type arguments it is the function of its instantiation expression. Before, it was the type query of a call, and in parentheses with a qualifier (`(typeof import('./x').y)[]`) it gave `ERROR` nodes.
- **An import type with type arguments** (`import('./x').Y<T>`) has the `import_type` node as the name of its `generic_type`. Before, its call and member accesses were bare and the rules took them for expressions.
- **A comment in several lines** counts as a line break for the automatic semicolon, as ECMAScript says: `return /* …⏎… */ x` is `return;` and `x`, and the same after `break`, `continue` and `yield`, before `++` and between statements or members without `;`.
- **Every line terminator** ends a statement without `;`: a lone carriage return, U+2028 and U+2029 like a line feed, also after a line comment. The white space the scanner skips is all of the grammar's (a no-break space, U+3000…), which the C library only knows in ASCII. The `#!` line ends at any of them, and white space with CRLF between two JSX elements is not text, as with LF. Before, those statements gave `ERROR` nodes.
- **A name that starts with `in` or `instanceof`** at the start of a line (`in_range(x)`, `in2`) is a name. Before, when a character that is not a letter followed, it was taken for the operator and the statement before did not end.
- **A comment before the `?` of a conditional** stays in the tree. Before, a block comment there was skipped as white space.
- **The targets of a destructuring assignment** may be a reference in parentheses or with a type assertion, as TypeScript's `checkReferenceExpression` takes them: `[x as T, (y), <T>z] = list`, `({ k: (x) } = o)`, `[(x) = 1, ...y as T] = list`, `for ([x as T] of list)`, `for (x as T of list)`. The pattern has them as the expression nodes they are elsewhere. Before, they were read through error recovery: an array with a missing `!`, or an `ERROR` node that could take the rest of the file.
- **`abstract async m(): T`** is an abstract method signature that is `async`, and **an accessibility modifier after `static`** (`static protected [k]() {}`) is a modifier: TypeScript parses both and then reports them. Before, the `async` and the `protected` were `ERROR` nodes, and the method was not async or had no modifier.
- **A literal on the left of a compound assignment** (`'' += x`, `` `a` += 1 ``, `1 += 2`) is an assignment, as TypeScript parses it before reporting the target. Before, it gave an `ERROR` node.
- **`export import x = require('m')`** (also with `type`) is an export statement whose declaration is the `import_statement` with an `import_require_clause` that `import x = require('m')` is, as ESTree has an ExportNamedDeclaration of the TSImportEqualsDeclaration. Before, it was read as an import alias of `require` with a missing `;` and then the statement `('m')`: `no-require-imports` did not see it and `no-unused-expressions` reported the statement. The name `require` is also the value of an alias (`import x = require;`, `import x = require.y;`), as TypeScript reads it; before, both gave `ERROR` nodes.

**How it was validated:**
- Without the patch, the CLI regenerates v0.23.2's `parser.c` byte for byte, so the only difference is the patch.
- The tree-sitter trees were compared with TypeScript's (node by node, by range and kind) on 1,407 files: the fixtures, Spider-Byte and the TypeScript code of its dependencies (effect, rxjs, typia…).
  - On the 1,212 files both grammars read without errors, the patched grammar has 127 discrepancies with TypeScript against 478 for the original one, and no new ones.
  - No file that was read without errors has them with the patch.
- The fix of qualified types came later, so those numbers do not include it. It was validated by comparing the trees before and after it on 5,962 files (the same sources plus the declaration files of the dependencies):
  - 23 files change. In 22 of them, the only changes are `as` and `satisfies` expressions with those types (56 places);
  - the other one is a file neither grammar can read, from its first line;
  - no file that was read without errors has them with the fix.
- The six fixes after it were validated the same way, on the same 5,962 files:
  - 359 files change, and the files with `ERROR` or `MISSING` nodes go from 498 to 290;
  - no file has more of those nodes than before, and no change adds one;
  - the changes in places that were read without errors are the constructs listed above (`new () => A | B`, `readonly A[] | B`, `import('…').X<T>`, `new X!()`).
- The next six, again on those files: the files with `ERROR` or `MISSING` nodes go from 290 to 28 (variance annotations account for most of it). One file that was already full of errors has one more, and no file that was read without errors has any. The JSX names only change the tsx dialect: the TypeScript parser it generates is byte for byte the same.
- The last seven (import types as primary types, the line after an arrow block, `abstract`, `out`, the optional destructured parameter, the default export signature and the rest target) on 6,254 files, the same sources as they are now: the files with `ERROR` or `MISSING` nodes go from 34 to 1, which is the fixture with a syntax error, and those nodes from 15,150 to 1. 33 trees change, all of them files that had errors; no file that was read without errors changes.
- The next five (the callee of a call with type arguments, `&&` between comparisons, the names of tuple members, `&` in JSX and the node of an import type) on 11,518 files, with the sources of zod, recharts and the TypeScript compiler added: the files with `ERROR` or `MISSING` nodes go from 7 to 1, the fixture with a syntax error. 445 trees change and none has more of those nodes: about 400 only gain the `import_type` node, and in the others the same nodes are put together in another way (the call inside the `await`) or a chain of comparisons becomes the call it is.
- The last eleven, on the same 11,518 files: the files with `ERROR` or `MISSING` nodes stay at 1, the fixture with a syntax error. 638 trees change and none has more of those nodes: 629 are exactly three rewrites of the old tree, checked by applying them to it and comparing with the new one (1,597 unions and intersections with a leading `|` or `&`, 614 type queries of import types and 7,102 import types with type arguments); 8 are `.tsx` files with CRLF, which now have the tree they have with LF, as the 1,061 files with a carriage return do; one has three calls with type arguments that were read as comparisons. Against TypeScript's own parser, in the 6,050 files that have them: 5,791 calls with type arguments, 790 `new` with them, 9 instantiation expressions, 2,134 `<` comparisons, 79,818 unions and intersections with their number of members, 614 type queries of import types and 47,223 `return`, `break` and `continue` with or without operand are read the same. What the corpus lacks was checked on probes, also against TypeScript: 264 instantiation expressions and 109 comparisons wherever something may follow type arguments (two differences, below); 39 statement shapes with each line terminator and 15 with eight kinds of white space, all with the tree of the line feed and of the plain space; 82 destructuring targets TypeScript accepts, all read, and the ones it rejects not read.
- The last three (`abstract async`, the modifier after `static` and the literal on the left of a compound assignment, found by typescript-eslint's own tests), on the same 11,518 files: no tree changes, and the files with `ERROR` or `MISSING` nodes stay at 1. Probes show that `abstract async(): void`, `static protected() {}` and `static async() {}` are still methods with those names.
- The last one (`export import x = require('m')` and the name `require` as the value of an alias), on the same 11,518 files: no tree changes, and the files with `ERROR` or `MISSING` nodes stay at 1. 17 probes of the forms (with `type`, in a `declare module`, with a space or a line break before `(`, `= require;`, `= require.x` and `= require.x.y`, a line after the alias that starts with `(`, exported or not) give the reading of typescript-estree, and the ones that were read without errors before keep their trees, but for the alias of `require` without a `;` (below).

**Remaining discrepancies** (when a rule needs one of those nodes, it is left unanalyzed and veslint warns):
- after `new X` without arguments, a `<` is always the start of its type arguments: `new X < y` has a `MISSING` node, and `new X<T> + 1` is read as `(new X<T>) + 1` where TypeScript reads two comparisons;
- `f<<T>(x: T) => U>(y)`: `<<` is one token, so the call is read as a shift and a comparison;
- a call with type arguments whose type argument is a function type that returns an object type with three or more property names in a row, `f<() => { a: { b: { c: number } } }>(x)`, is read as two comparisons (each name is a label of the other reading and weighs for it);
- a binding pattern takes what only an assignment target may be (`const [a.b] = x`, `const [(x)] = a`): TypeScript reports a syntax error and the grammar does not;
- a `new` followed by a line break is read as the identifier `new` and an automatic `;` (`const a = new⏎Foo()` is `const a = new;` and `Foo()`), with no syntax error;
- `<T>x++` is read as `(<T>x)++`, where TypeScript reads `<T>(x++)`;
- the alias of a namespace named `require` takes a written `;` (`import x = require;`): without one, it has a `MISSING` node, so that a `(` on the next line is the `require('m')` it is for TypeScript (`import x = require⏎('m')`);
- these give `ERROR` nodes although TypeScript reads them: a static index signature (`static [key: string]: T`), a mapped type without a type (`{ [k in string]; }`), an export with import attributes (`export { a } from 'n' with { type: 'json' }`), `import { type as }`, `import { type as as as }` and `import type = require('m')` (an import named `type`), and, in code that TypeScript reports as invalid, a decorated method overload, an abstract method with a body, `let d!: T = v` and a parameter with both `?` and a default value;
- syntax `ERROR` nodes for syntax the grammar does not know.

## Rules

`veslint --rule <rule> <files>...` prints one line per problem: `path:line:col<TAB>rule<TAB>messageId<TAB>message`, where the rule is its ESLint id (`@typescript-eslint/await-thenable`), as ESLint's `ruleId`. The message is exactly typescript-eslint's (its `meta.messages` template with the same data). Since it may carry source text, line breaks, tabs and backslashes in it are written as `\n`, `\r`, `\t` and `\\`. The position is that of the node typescript-eslint reports, with the same convention as ESLint (except on lines with U+2028 or a lone `\r`; see "Known limits" at the end). The exit code is 1 if there are problems.

It warns on stderr, per file, if tree-sitter found syntax errors or if nodes were left unanalyzed (see "How it gets the types"); in both cases some finding may be missing.

They are V ports of 105 rules of typescript-eslint 8.62.0 (out of its 127 rules that are not deprecated): its 61 type-aware rules (the 49 that Spider-Byte's configuration enables and the other 12) and 44 that need no types (with them veslint has every typescript-eslint rule that `someday.ts` turns on); veslint has no rule of its own. They report the same cases, with the same `messageId` and the same message:

**The rules of ESLint core** (batches C1 to C5, 2026-11-12/13) are V ports of 62 rules of ESLint 10.6.0, named without a plugin as in ESLint: `no-irregular-whitespace` (all its `skip*` options), `no-loss-of-precision`, `no-multi-str`, `no-nonoctal-decimal-escape` (with its suggestions), `no-octal`, `no-octal-escape`, `no-sparse-arrays`, `no-template-curly-in-string`, `no-useless-concat`, `prefer-numeric-literals` (with its fix), `prefer-template` (with its fix), `unicode-bom` (`"always"`, `"never"`, with its fix; veslint reads a file without its BOM, as ESLint does, and `--fix` writes it back or drops it), `eqeqeq` (`"always"` with `null`, `"smart"`, `"allow-null"`, with its fix and suggestion), `logical-assignment-operators` (`"always"` with `enforceForIfStatements`, `"never"`, with its fixes and suggestions), `no-eq-null`, `no-extra-boolean-cast` (`enforceForLogicalOperands`, `enforceForInnerExpressions`, with its fixes), `no-implicit-coercion` (all its options, with its fix and suggestions), `no-return-assign` (`"except-parens"`, `"always"`), `no-sequences` (`allowInParentheses`), `no-unexpected-multiline`, `operator-assignment` (`"always"`, `"never"`, with its fixes), `prefer-exponentiation-operator` (with its fix; eslint-utils' ReferenceTracker is ported for it), `yoda` (`"always"`, `"never"`, `exceptRange`, `onlyEquality`, with its fix), `arrow-body-style` (`"always"`, `"as-needed"` with `requireReturnForObjectLiteral`, `"never"`, with its fixes), `func-name-matching` (`"always"`, `"never"`, `considerPropertyDescriptor`, `includeCommonJSModuleExports`), `func-names` (`"always"`, `"as-needed"`, `"never"`, `generators`), `grouped-accessor-pairs` (`"anyOrder"`, `"getBeforeSet"`, `"setBeforeGet"`, `enforceForTSTypes`), `no-dupe-args`, `no-dupe-keys`, `no-empty-pattern` (`allowObjectPatternsAsParameters`), `no-setter-return`, `no-useless-computed-key` (`enforceForClassMembers`, with its fix), `no-useless-rename` (`ignoreDestructuring`, `ignoreImport`, `ignoreExport`, with its fix), `object-shorthand` (all its modes and options, with its fixes), `prefer-arrow-callback` (`allowNamedFunctions`, `allowUnboundThis`, with its fix), `require-yield`, `curly` (`"all"`, `"multi"`, `"multi-line"`, `"multi-or-nest"` and `"consistent"`, with its fixes), `default-case-last`, `no-case-declarations` (with its suggestion), `no-debugger`, `no-else-return` (`allowElseIf`, with its fix), `no-empty` (`allowEmptyCatch`, with its suggestion), `no-empty-static-block` (with its suggestion), `no-extra-label` (with its fix), `no-labels` (`allowLoop`, `allowSwitch`), `no-unsafe-finally`, `no-unused-labels` (with its fix), `no-useless-catch`, `no-with`, `for-direction`, `no-compare-neg-zero`, `no-cond-assign` (`"except-parens"` or `"always"`), `no-constant-binary-expression` (`checkRelationalComparisons`), `no-constant-condition` (`checkLoops`), `no-dupe-else-if`, `no-duplicate-case`, `no-self-assign` (`props`), `no-self-compare`, `no-unsafe-negation` (`enforceForOrderingRelations`, with its suggestions), `no-unsafe-optional-chaining` (`disallowArithmeticOperators`), `use-isnan` (`enforceForSwitchCase`, `enforceForIndexOf`, with its suggestions) and `valid-typeof` (`requireStringLiterals`, with its suggestion), with all their options. The helpers of ESLint's `lib/rules/utils/ast-utils.js` they share (`isSameReference`, `equalTokens`, `isConstant`, `isReferenceToGlobalVariable`…) are in `rules/eslint_utils.v` and `rules/eslint_constant.v`. Besides fixtures of their own, they pass all the cases of ESLint's own tests, linted as TypeScript (below).

**The `seyfert/*` rules** (batch SY1, 2026-11-12) are V ports of the 15 rules of @slipher/eslint-plugin 1.1.0 (tiramisulabs/extra 221401c7c2, `packages/eslint-plugin`), registered as the plugin `seyfert` like its recommended configuration does: `require-declare`, `no-deep-imports` (with its fix), `options-use-builders`, `no-hanging-middleware`, `decorator-target`, `required-options-order`, `declare-description`, `context-menu-declare`, `autocomplete-respond`, `decorator-on-command`, `config-default-export`, `i18n-resolve-with-get`, `group-exists`, `no-method-destructure` and `prefer-typed-group`. None has options. What they share (`src/utils.ts`: a seyfert symbol is one declared in a file under `seyfert/lib/`, after an alias; the command bases through the base types and the generic declarations; the decorators; the `createXOption` builders; the values followed through `const` bindings and imports) is in `rules/seyfert.v`, on tsgo's AST of every file of the program (`tsgo/ast_tree.v`); `no-deep-imports` resolves `seyfert` with the options of the project and reads the exports of its root, in a program of its own when the project does not have it (`tsgo/modules.v`); `no-hanging-middleware` follows the paths of the middleware like ESLint's code path analysis; `group-exists` lists the directory of an `@AutoLoad` command as Node's `readdirSync` with `recursive` does. Only the plugin's namespace `seyfert` is recognized. Besides the plugin's own tests (below), each rule has fixtures of its own in `tests/rules/seyfert/<rule>/`, which import the seyfert 5.2.0 of those tests: `tests/rules/seyfert/setup.sh` links it, with `@types/node`, into `tests/rules/seyfert/node_modules` (which git ignores), and without it `make test` skips them and says so.

| Rule | Options | `messageId` |
|---|---|---|
| `no-floating-promises` | all: `allowForKnownSafeCalls`, `allowForKnownSafePromises`, `checkThenables`, `ignoreIIFE`, `ignoreVoid` | `floating`, `floatingPromiseArray`, `floatingUselessRejectionHandler` and their `*Void` variants (with `ignoreVoid`) |
| `await-thenable` | none | `await`, `awaitUsingOfNonAsyncDisposable`, `forAwaitOfNonAsyncIterable`, `invalidPromiseAggregatorInput` |
| `require-await` | none | `missingAwait` |
| `return-await` | all: `'always'`, `'error-handling-correctness-only'`, `'in-try-catch'`, `'never'` | `disallowedPromiseAwait`, `nonPromiseAwait`, `requiredPromiseAwait` |
| `no-misused-promises` | all: `checksConditionals`, `checksSpreads`, `checksVoidReturn` (also as an object: `arguments`, `attributes`, `inheritedMethods`, `properties`, `returns`, `variables`) | `conditional`, `predicate`, `spread`, `voidReturnArgument`, `voidReturnInheritedMethod`, `voidReturnProperty`, `voidReturnReturnValue`, `voidReturnVariable` |
| `no-unsafe-call` | none | `unsafeCall`, `unsafeCallThis`, `unsafeNew`, `unsafeTemplateTag` and their `error*` variants |
| `no-unsafe-member-access` | all: `allowOptionalChaining` | `unsafeMemberExpression`, `unsafeThisMemberExpression`, `unsafeComputedMemberAccess` and their `error*` variants |
| `no-unsafe-return` | none | `unsafeReturn`, `unsafeReturnAssignment`, `unsafeReturnThis` |
| `no-unsafe-assignment` | none | `anyAssignment`, `anyAssignmentThis`, `unsafeArrayPattern`, `unsafeArrayPatternFromTuple`, `unsafeArraySpread`, `unsafeAssignment`, `unsafeObjectPattern` |
| `no-unsafe-argument` | none | `unsafeArgument`, `unsafeArraySpread`, `unsafeSpread`, `unsafeTupleSpread` |
| `restrict-template-expressions` | all: `allowAny`, `allowArray`, `allowBoolean`, `allowNever`, `allowNullish`, `allowNumber`, `allowRegExp` and `allow` | `invalidType` |
| `switch-exhaustiveness-check` | all: `allowDefaultCaseForExhaustiveSwitch`, `considerDefaultExhaustiveForUnions`, `defaultCaseCommentPattern`, `requireDefaultForNonUnion` | `dangerousDefaultCase`, `switchIsNotExhaustive` |
| `prefer-nullish-coalescing` | all: `ignoreBooleanCoercion`, `ignoreConditionalTests`, `ignoreIfStatements`, `ignoreMixedLogicalExpressions`, `ignorePrimitives`, `ignoreTernaryTests`, `allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing` | `noStrictNullCheck`, `preferNullishOverAssignment`, `preferNullishOverOr`, `preferNullishOverTernary` |
| `no-unnecessary-condition` | all: `allowConstantLoopConditions`, `checkTypePredicates`, `allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing` | `alwaysFalsy`, `alwaysFalsyFunc`, `alwaysNullish`, `alwaysTruthy`, `alwaysTruthyFunc`, `comparisonBetweenLiteralTypes`, `never`, `neverNullish`, `neverOptionalChain`, `noOverlapBooleanExpression`, `noStrictNullCheck`, `typeGuardAlreadyIsType` |
| `no-for-in-array` | none | `forInViolation` |
| `no-array-delete` | none | `noArrayDelete` |
| `no-unnecessary-boolean-literal-compare` | all: `allowComparingNullableBooleansToFalse`, `allowComparingNullableBooleansToTrue`, `allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing` | `comparingNullableToFalse`, `comparingNullableToTrueDirect`, `comparingNullableToTrueNegated`, `direct`, `negated`, `noStrictNullCheck` |
| `no-unsafe-unary-minus` | none | `unaryMinus` |
| `no-meaningless-void-operator` | all: `checkNever` | `meaninglessVoidOperator` |
| `related-getter-setter-pairs` | none | `mismatch` |
| `non-nullable-type-assertion-style` | none | `preferNonNullAssertion` |
| `prefer-return-this-type` | none | `useThisType` |
| `no-duplicate-type-constituents` | all: `ignoreIntersections`, `ignoreUnions` | `duplicate`, `unnecessary` |
| `no-unnecessary-template-expression` | none | `noUnnecessaryTemplateExpression` |
| `dot-notation` | all: `allowKeywords`, `allowPattern`, `allowIndexSignaturePropertyAccess`, `allowPrivateClassPropertyAccess`, `allowProtectedClassPropertyAccess` | `useDot`, `useBrackets` |
| `restrict-plus-operands` | all: `allowAny`, `allowBoolean`, `allowNullish`, `allowNumberAndString`, `allowRegExp`, `skipCompoundAssignments` | `bigintAndNumber`, `invalid`, `mismatched` |
| `no-confusing-void-expression` | all: `ignoreArrowShorthand`, `ignoreVoidOperator`, `ignoreVoidReturningFunctions` | `invalidVoidExpr`, `invalidVoidExprArrow`, `invalidVoidExprArrowWrapVoid`, `invalidVoidExprReturn`, `invalidVoidExprReturnLast`, `invalidVoidExprReturnWrapVoid`, `invalidVoidExprWrapVoid` |
| `no-misused-spread` | all: `allow` | `noArraySpreadInObject`, `noClassDeclarationSpreadInObject`, `noClassInstanceSpreadInObject`, `noFunctionSpreadInObject`, `noIterableSpreadInObject`, `noMapSpreadInObject`, `noPromiseSpreadInObject`, `noStringSpread` |
| `no-redundant-type-constituents` | none | `errorTypeOverrides`, `literalOverridden`, `overridden`, `overrides`, `primitiveOverridden` |
| `no-useless-default-assignment` | all: `allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing` | `noStrictNullCheck`, `preferOptionalSyntax`, `uselessDefaultAssignment`, `uselessUndefined` |
| `no-unnecessary-type-arguments` | none | `unnecessaryTypeParameter` |
| `no-unnecessary-qualifier` | none | `unnecessaryQualifier` |
| `no-implied-eval` | none | `noFunctionConstructor`, `noImpliedEvalError` |
| `no-unnecessary-type-conversion` | none | `unnecessaryTypeConversion` |
| `no-unnecessary-type-assertion` | all: `checkLiteralConstAssertions`, `typesToIgnore` | `contextuallyUnnecessary`, `unnecessaryAssertion` |
| `no-base-to-string` | all: `checkUnknown`, `ignoredTypeNames` | `baseArrayJoin`, `baseToString` |
| `no-unsafe-enum-comparison` | none | `mismatchedCase`, `mismatchedCondition` |
| `no-mixed-enums` | none | `mixed` |
| `unbound-method` | all: `ignoreStatic` | `unbound`, `unboundWithoutThisAnnotation` |
| `prefer-reduce-type-parameter` | none | `preferTypeParameter` |
| `prefer-find` | none | `preferFind` |
| `prefer-regexp-exec` | none | `regExpExecOverStringMatch` |
| `prefer-includes` | none | `preferIncludes`, `preferStringIncludes` |
| `prefer-string-starts-ends-with` | all: `allowSingleElementEquality` | `preferEndsWith`, `preferStartsWith` |
| `prefer-optional-chain` | all: `checkAny`, `checkBigInt`, `checkBoolean`, `checkNumber`, `checkString`, `checkUnknown`, `requireNullish` (`allowPotentiallyUnsafeFixesThatModifyTheReturnTypeIKnowWhatImDoing` is accepted; it only affects fixes) | `preferOptionalChain` |
| `no-deprecated` | all: `allow` | `deprecated`, `deprecatedWithReason` |
| `prefer-promise-reject-errors` | all: `allow`, `allowEmptyReject`, `allowThrowingAny`, `allowThrowingUnknown` | `rejectAnError` |
| `use-unknown-in-catch-callback-variable` | none | `useUnknown`, `useUnknownArrayDestructuringPattern`, `useUnknownObjectDestructuringPattern` |
| `only-throw-error` | all: `allow`, `allowRethrowing`, `allowThrowingAny`, `allowThrowingUnknown` | `object`, `undef` |
| `require-array-sort-compare` | all: `ignoreStringArrays` | `requireCompare` |
| `no-unsafe-type-assertion` | none | `unsafeOfAnyTypeAssertion`, `unsafeToAnyTypeAssertion`, `unsafeToUnconstrainedTypeAssertion`, `unsafeTypeAssertion`, `unsafeTypeAssertionAssignableToConstraint` |
| `promise-function-async` | all: `allowAny`, `allowedPromiseNames`, `checkArrowFunctions`, `checkFunctionDeclarations`, `checkFunctionExpressions`, `checkMethodDeclarations` | `missingAsync`, `missingAsyncHybridReturn` |
| `prefer-readonly-parameter-types` | all: `allow`, `checkParameterProperties`, `ignoreInferredTypes`, `treatMethodsAsReadonly` | `shouldBeReadonly` |
| `consistent-type-exports` | all: `fixMixedExportsWithInlineTypeSpecifier` | `multipleExportsAreTypes`, `singleExportIsType`, `typeOverValue` |
| `strict-void-return` | all: `allowReturnAny` | `asyncFunc`, `nonVoidFunc`, `nonVoidReturn` |
| `consistent-return` | all: `treatUndefinedAsUnspecified` | `missingReturn`, `missingReturnValue`, `unexpectedReturnValue` |
| `prefer-destructuring` | all: `array` and `object` (for all, or per `VariableDeclarator` and `AssignmentExpression`), `enforceForDeclarationWithTypeAnnotation`, `enforceForRenamedProperties` | `preferDestructuring` |
| `prefer-readonly` | all: `onlyInlineLambdas` | `preferReadonly` |
| `strict-boolean-expressions` | all: `allowAny`, `allowNullableBoolean`, `allowNullableEnum`, `allowNullableNumber`, `allowNullableObject`, `allowNullableString`, `allowNumber`, `allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing`, `allowString` | `conditionErrorAny`, `conditionErrorNullableBoolean`, `conditionErrorNullableEnum`, `conditionErrorNullableNumber`, `conditionErrorNullableObject`, `conditionErrorNullableString`, `conditionErrorNullish`, `conditionErrorNumber`, `conditionErrorObject`, `conditionErrorOther`, `conditionErrorString`, `conditionFixCastBoolean`, `conditionFixCompareArrayLengthNonzero`, `conditionFixCompareArrayLengthZero`, `conditionFixCompareEmptyString`, `conditionFixCompareFalse`, `conditionFixCompareNaN`, `conditionFixCompareNullish`, `conditionFixCompareStringLength`, `conditionFixCompareTrue`, `conditionFixCompareZero`, `conditionFixDefaultEmptyString`, `conditionFixDefaultFalse`, `conditionFixDefaultZero`, `explicitBooleanReturnType`, `noStrictNullCheck`, `predicateCannotBeAsync` |
| `no-unnecessary-type-parameters` | none | `replaceUsagesWithConstraint`, `sole` |
| `naming-convention` | all: the list of selectors, each with `selector`, `format`, `custom`, `filter`, `leadingUnderscore`, `trailingUnderscore`, `prefix`, `suffix`, `modifiers` (also `unused`) and `types` | `doesNotMatchFormat`, `doesNotMatchFormatTrimmed`, `missingAffix`, `missingUnderscore`, `satisfyCustom`, `unexpectedUnderscore` |
| `no-duplicate-enum-values` | none | `duplicateValue` |
| `no-extra-non-null-assertion` | none | `noExtraNonNullAssertion` |
| `no-non-null-asserted-optional-chain` | none | `noNonNullOptionalChain` |
| `no-unsafe-function-type` | none | `bannedFunctionType` |
| `no-wrapper-object-types` | none | `bannedClassType` |
| `prefer-enum-initializers` | none | `defineInitializer` |
| `no-dynamic-delete` | none | `dynamicDelete` |
| `no-namespace` | all: `allowDeclarations`, `allowDefinitionFiles` | `moduleSyntaxIsPreferred` |
| `no-unnecessary-type-constraint` | none | `unnecessaryConstraint` |
| `prefer-as-const` | none | `preferConstAssertion`, `variableConstAssertion` |
| `no-invalid-void-type` | all: `allowAsThisParameter`, `allowInGenericTypeArguments` (true, false or a list of type names) | `invalidVoidForGeneric`, `invalidVoidNotReturn`, `invalidVoidNotReturnOrGeneric`, `invalidVoidNotReturnOrThisParam`, `invalidVoidNotReturnOrThisParamOrGeneric`, `invalidVoidUnionConstituent` |
| `adjacent-overload-signatures` | none | `adjacentSignature` |
| `class-literal-property-style` | all: `'fields'`, `'getters'` | `preferFieldStyle`, `preferGetterStyle` |
| `no-dupe-class-members` | none | `unexpected` |
| `no-empty-function` | all: `allow` (its 14 kinds, `private-constructors` and `protected-constructors` included) | `unexpected` |
| `no-extraneous-class` | all: `allowConstructorOnly`, `allowEmpty`, `allowStaticOnly`, `allowWithDecorator` | `empty`, `onlyConstructor`, `onlyStatic` |
| `no-misused-new` | none | `errorMessageClass`, `errorMessageInterface` |
| `no-this-alias` | all: `allowDestructuring`, `allowedNames` | `thisAssignment`, `thisDestructure` |
| `no-unused-expressions` | all: `allowShortCircuit`, `allowTaggedTemplates`, `allowTernary`, `enforceForJSX`, `ignoreDirectives` | `unusedExpression` |
| `no-useless-constructor` | none | `noUselessConstructor` |
| `no-useless-empty-export` | none | `uselessExport` |
| `consistent-generic-constructors` | all: `'constructor'`, `'type-annotation'` (and the parser option `isolatedDeclarations`) | `preferConstructor`, `preferTypeAnnotation` |
| `consistent-type-assertions` | all: `assertionStyle` (`'as'`, `'angle-bracket'`, `'never'`), `arrayLiteralTypeAssertions`, `objectLiteralTypeAssertions` | `angle-bracket`, `as`, `never`, `unexpectedArrayTypeAssertion`, `unexpectedObjectTypeAssertion` |
| `consistent-type-definitions` | all: `'interface'`, `'type'` | `interfaceOverType`, `typeOverInterface` |
| `no-array-constructor` | none | `useLiteral` |
| `no-confusing-non-null-assertion` | none | `confusingAssign`, `confusingEqual`, `confusingOperator` |
| `no-import-type-side-effects` | none | `useTopLevelQualifier` |
| `no-inferrable-types` | all: `ignoreParameters`, `ignoreProperties` | `noInferrableType` |
| `prefer-function-type` | none | `functionTypeOverCallableType`, `unexpectedThisOnFunctionOnlyInterface` |
| `prefer-namespace-keyword` | none | `useNamespace` |
| `triple-slash-reference` | all: `lib`, `path`, `types` | `tripleSlashReference` |
| `unified-signatures` | all: `ignoreDifferentlyNamedParameters`, `ignoreOverloadsWithDifferentJSDoc` | `omittingRestParameter`, `omittingSingleParameter`, `singleParameterDifference` |
| `array-type` | all: `default` and `readonly` (`'array'`, `'array-simple'`, `'generic'`) | `errorStringArray`, `errorStringArrayReadonly`, `errorStringArraySimple`, `errorStringArraySimpleReadonly`, `errorStringGeneric`, `errorStringGenericSimple` |
| `consistent-indexed-object-style` | all: `'record'`, `'index-signature'` | `preferIndexSignature`, `preferRecord` |
| `no-non-null-asserted-nullish-coalescing` | none | `noNonNullAssertedNullishCoalescing` |
| `no-require-imports` | all: `allow`, `allowAsImport` | `noRequireImports` |
| `no-unnecessary-parameter-property-assignment` | none | `unnecessaryAssign` |
| `no-unsafe-declaration-merging` | none | `unsafeMerging` |
| `no-unused-private-class-members` | none | `unusedPrivateClassMember` |
| `prefer-for-of` | none | `preferForOf` |
| `consistent-type-imports` | all: `disallowTypeAnnotations`, `fixStyle`, `prefer` | `avoidImportType`, `noImportTypeAnnotations`, `someImportsAreOnlyTypes`, `typeOverValue` |
| `no-shadow` | all: `allow`, `builtinGlobals`, `hoist`, `ignoreFunctionTypeParameterNameValueShadow`, `ignoreOnInitialization`, `ignoreTypeValueShadow` | `noShadow`, `noShadowGlobal` |
| `no-unused-vars` | all: `'all'`, `'local'`, or `args`, `argsIgnorePattern`, `caughtErrors`, `caughtErrorsIgnorePattern`, `destructuredArrayIgnorePattern`, `enableAutofixRemoval`, `ignoreClassWithStaticInitBlock`, `ignoreRestSiblings`, `ignoreUsingDeclarations`, `reportUsedIgnorePattern`, `vars`, `varsIgnorePattern` | `unusedVar`, `usedIgnoredVar`, `usedOnlyAsType` |
| `no-use-before-define` | all: `'nofunc'`, or `allowNamedExports`, `classes`, `enums`, `functions`, `ignoreTypeReferences`, `typedefs`, `variables` | `noUseBeforeDefine` |

### Fixes and suggestions

The 60 rules that have a fixer or suggestions in typescript-eslint have them in veslint too (38 with fixes, 30 with suggestions), ported branch by branch with ESLint's token and comment lists and typescript-eslint's fixer utilities.

- **`--fixes`** adds to each line its fix, `<TAB>fix<TAB>start<TAB>end<TAB>text`, and one `<TAB>suggestion<TAB>messageId<TAB>message<TAB>start<TAB>end<TAB>text` per suggestion. The ranges are in UTF-16 units, like ESLint's, and the several edits of one report are merged into one as ESLint does. In a text, as in a message, a backslash, a newline, a carriage return and a tab are written `\\`, `\n`, `\r` and `\t`. A surrogate without its pair is U+FFFD in the fix text and in the fixed file, as Node writes it.
- **`--fix`** ports ESLint's `verifyAndFix`: it lints, applies the fixes that do not overlap, and lints the result again, up to 10 passes; then it prints what remains. The fixes of directive comments without use are applied too. tsgo only reads files, so veslint writes each pass to disk and asks for a new snapshot; ESLint writes once at the end, so only an interrupted run can tell them apart. A file in which tree-sitter finds syntax errors is not fixed.

"It is a Promise" means the same as in typescript-eslint. `isBuiltinSymbolLike` (the global `Promise` symbol, or a class or interface that extends it), `isThenableType` and `needsToBeAwaited` are ported, with unions, intersections and constraints of generics.

In the `no-unsafe-*` family, "it is `any`" is also typescript-eslint's: an `any` in some part of a union. The `error*` variants of the messages are for the `any` TypeScript gives what it cannot resolve, and the `*This` ones for a `this` of type `any`. The latter depend on `noImplicitThis`, resolved like ts-api-utils' `isStrictCompilerOptionEnabled`: the option if set, else `strict`, and else enabled (TypeScript ≥ 6). `isUnsafeAssignment` (with its exception for `new Map()`), `discriminateAnyType`, `getThisExpression` and type-utils' `getContextualType` are ported.

### Configuration (`--config`)

`veslint --config <file> <files>...` applies several rules in a single pass per file: a single parse and a single tsgo AST shared by all of them, and the types one rule requested are reused by the next ones. The file can be:

- **An ESLint configuration** (`eslint.config.js`, `.mjs`, `.cjs`, `.ts`, `.mts`, `.cts`). It is JavaScript, so ESLint itself resolves it: veslint runs `bun` once with a script that asks the project's ESLint (`isPathIgnored`, `calculateConfigForFile`) for the configuration of each file. So `files`, `ignores`, rules and options per folder, `linterOptions` (`noInlineConfig`, `reportUnusedDisableDirectives`, `reportUnusedInlineConfigs`) and, of `languageOptions`, the `ecmaVersion`, the `sourceType`, the `globals` and the parser options the scopes depend on (`sourceType`, `lib`, `jsxPragma`, `jsxFragmentName`, `ecmaFeatures.globalReturn`) are ESLint's own answer. A file ESLint does not lint gets ESLint's warning for it (`File ignored because of a matching ignore pattern…`) and is skipped. As with `eslint -c`, the patterns are relative to the directory veslint runs in. `eslint` is resolved from the directory of the configuration (`VESLINT_ESLINT_DIR` overrides it). On Spider-Byte's configuration this takes about 1.4 s.
- **The resolved configuration**, the JSON `--print-config` prints for the files of the run (`configs`, each with its `rules`, `linterOptions` and `languageOptions`, and for each file its configuration or ESLint's message). Saved next to the configuration, it gives the same result without any JavaScript runtime; a file that is not in it is an error. Its keys are in ESLint's order.
- **A JSON with ESLint's `rules` section**, which is for every file; the output of `eslint --print-config <file>` also works as is: its `linterOptions` and its `languageOptions` (the `ecmaVersion`, the `sourceType`, the `globals`, those parser options and how the parser gets the types) are read too, and its `plugins` tell which plugins exist. No ESLint reads such a file, so veslint normalizes its rules as ESLint normalizes a configuration object, with the default options of the rules of ESLint and typescript-eslint from a generated table:

```json
{"rules": {"@typescript-eslint/no-floating-promises": "error", "@typescript-eslint/restrict-template-expressions": ["warn", {"allowNullish": false}], "no-unsafe-call": [2]}}
```

- **Severity:** `"off"`/`"warn"`/`"error"` or `0`/`1`/`2`, alone or as the first element of an array whose rest are the options. Findings of a rule set to `"warn"` are printed but do not make veslint exit with code 1, as in ESLint.
- **Names:**
  - a rule is named by its full ESLint id, as in ESLint: `@typescript-eslint/await-thenable` is the rule of typescript-eslint;
  - a name without a plugin is a rule of ESLint core: `await-thenable` or `dot-notation` alone are not veslint's ports, while `no-cond-assign` is veslint's port of ESLint's rule (the same in `--rule` and in directive comments).
- **Rules veslint does not have:** active ones are ignored with a warning.
- **Options:** they are validated against the schema of the rule as ESLint validates them (`rules/json_schema.v`): what does not fit is an error with ESLint's text, in ESLint's order, and exit code 2, as is a severity that is not one. Then they are merged with the defaults as typescript-eslint does (`applyDefault`). Rules that read options (see the table) apply them; for the other rules, only options equivalent to the defaults are accepted (`["error", "in-try-catch"]` in `return-await`), and anything else is a usage error.
- **Output:** the same, one line per finding with its rule, ordered by file, position and rule. The unanalyzed-nodes warning adds up those of all the rules.

### Directive comments

veslint applies the comments that configure ESLint as ESLint 10.6.0 does:

- **`eslint-disable`, `eslint-enable`, `eslint-disable-line` and `eslint-disable-next-line`**, with or without rules and with a `-- reason`, suppress findings. The ones that suppress nothing are reported (`Unused eslint-disable directive (no problems were reported from '…').`, a warning by default), with the fix that removes them. A rule that does not exist gets `Definition for rule '…' was not found.`
- **`/* eslint rule: value */`** changes the rules of the file: it turns a ported rule on or off and sets its options (with only a severity, the options are those of the configuration). Its errors are ESLint's: a rule configured twice, a severity that is not one, and a comment that cannot be read, with the text V8's `JSON.parse` gives.
- **`/* global name: value */`** gives the file a global or, with `off`, takes one away; an invalid value is ESLint's error. See "Globals" below.
- **`/* exported name */`** marks a variable of the global scope as used.
- **`/* eslint-env */`** gets ESLint's error (it is no longer supported).
- Those problems are printed with the rule `eslint` (ESLint's `ruleId: null`) and `fatal`, `error` or `warning` in the place of the `messageId`.
- With `noInlineConfig`, every such comment gets ESLint's warning and none is applied.
- The lines a directive applies to are ESLint's: they also end at a lone CR, U+2028 and U+2029.

### Globals

Which globals a file has decides which constants the rules evaluate (`list.filter(f)[parseInt('0')]` is `[0]` only while `parseInt` is the global) and which calls `no-implied-eval` takes for the global ones. veslint follows ESLint and typescript-eslint:

- typescript-eslint gives the global scope an implicit variable for every name its libs declare, as a type, a value or both. The libs are those of `parserOptions.lib` or, without it, of `lib` in the tsconfig or the default ones of its `target`, with the libs each one includes (`rules/scope_globals.v`, generated from both tools);
- ESLint then declares the globals of the configuration's `ecmaVersion`, those of CommonJS when the `sourceType` is `"commonjs"`, and those of `languageOptions.globals`. A `/* global */` comment changes the value of a name for the whole file, and a name that ends up `off` is not declared. An `/* exported */` comment marks a variable of the global scope as used.

So `/* global parseInt: off */` stops `parseInt('0')` from being a constant, and `/* global Number: off */` changes nothing unless the tsconfig has no lib that declares `Number`. For `naming-convention`, a class expression named like a global that ESLint declares and nothing references is unused. With a `sourceType` other than `"module"` the file is a script: its top-level declarations are variables of the global scope.

### How it gets the types

Every rule requests the exact type of each expression **per node**, like `checker.getTypeAtLocation` in typescript-eslint:

- **How a node is named:**
  - `getSourceFile` returns the tsgo AST in binary; `tsgo/ast.v` reads its node table (SyntaxKind, `pos` and `end`, in UTF-16).
  - A tree-sitter node is named by the tsgo node with the same range. `pos` is the end of the previous token, because TypeScript includes the leading trivia, and `end` is the end of the last token of the node.
  - Token ends come from an index built by walking the tree once (`treesitter.token_ends`). It does not count comments, the leading `#!` or zero-width tokens; in code without `;`, tree-sitter puts the trailing comment inside the node and TypeScript does not.
  - Some TypeScript nodes start earlier than tree-sitter's, and the rules that request them take it into account: the decorators of a class member are siblings of the member in tree-sitter, and `export`/`export default` are modifiers of a function declaration in TypeScript.
- **Only when a rule needs them:** when no rule of the configuration needs types (the 44 rules without types), the command line builds no program: tsgo only parses each tsconfig (`parseConfigFile`) for the compiler options the rules read (the libs and JSX factories of the scope manager, the decorator options of `consistent-type-imports`). A file gets a snapshot only when a comment turns on a rule that needs types, or when TypeScript may read one of its `await` as a name. On the 65 files of Spider-Byte, `no-this-alias` alone takes 0.11 s instead of 0.83 s (the minipc, one core). `--fix`, which tells tsgo of every file it writes, and the server always build the program.
- **One request per file and rule:** the types a rule needs in a file are requested with a single `getTypeAtLocations`, and those another rule already requested are not requested again. So overloads, generics and immediately invoked functions resolve as in TypeScript.
- **Declarations:** where typescript-eslint reads `symbol.declarations` (`dot-notation`, `unbound-method`, `no-deprecated`…), veslint reads the tsgo AST of the file that declares the symbol, which may be a library file. `tsgo/ast_tree.v` navigates that binary AST (parent, children by property name, JSDoc) and gives handles tsgo accepts as locations. Those ASTs are kept for the whole run, so memory grows with the files the rules reach, like the program TypeScript itself holds.
- **Names in scope:** where typescript-eslint looks a name up in `getSymbolsInScope` (`no-unnecessary-qualifier`), veslint asks `resolveName` and corrects the four places where the two differ: the locals of a function seen from its parameters, return type and decorators, the `arguments` object, import aliases, and names given by an export specifier in a namespace. TypeScript 7.1 has `getSymbolsInScope` too, but it answers every symbol in scope, those of the libraries included: with the DOM library, about 1,000 symbols for a value (0.7 MB) and 2,000 for a type (1.3 MB), 15 to 75 ms per request, against one name for `resolveName`. With `resolveName` and those corrections veslint gives typescript-eslint's findings on the rule's fixtures and on the 17 cases of its own test.
- **The type of a symbol at a place:** where typescript-eslint asks `getTypeOfSymbolAtLocation`, veslint asks it at the same node (`rules/checker_calls.v`). tsgo is only asked when the answer can differ from the type of the symbol: the node is an identifier with the name of the symbol, or the symbol is optional under `exactOptionalPropertyTypes`.
- **Scopes and constant values:** `rules/scope.v` builds the lexical scopes of a file like typescript-eslint's scope manager, for ESLint's `getScope`, `findVariable` and `getDeclaredVariables`. `rules/static_value.v` ports eslint-utils' `getStaticValue` on top of it, so a name such as `x[key]` with a constant `key` resolves as in ESLint. The global scope has ESLint's variables (see "Globals"), references resolve when their scope closes, and in a `.tsx` file an element references the JSX pragma: `jsxPragma` of the parser options, else the first name of the compiler's `jsxFactory`, else `React`; and the same with `jsxFragmentName` and `jsxFragmentFactory` for a fragment.
- **Unanalyzed nodes:** they get no type, the rule reports nothing with them and veslint warns per file. `--bench` counts them in `rule_unmatched`. On Spider-Byte with every rule it is 0. There are four cases:
  - a node without a tsgo counterpart, because the two parsers disagree or the code does not compile;
  - an expression with more than 1,000 nesting levels (conditionals, logical operators, commas or member accesses), where the recursion is cut;
  - a call for tree-sitter where TypeScript has another kind of node with the same range (code the two read differently). Its signature is not asked: tsgo panics when asked to resolve a node that is not a call, a `new`, a tagged template, a decorator or a JSX element, and veslint used to stop there, on the whole run;
  - a node tsgo fails on. tsgo 7.0.2 panicked when asked for the type of an empty array literal whose type is the empty tuple (`[] as const`, `const t: [] = []`) and rejected the whole request (microsoft/TypeScript#63869); 7.1.0-beta answers those nodes, and the members of a union with such a tuple. If a request is still rejected, veslint splits it in halves until the nodes tsgo fails on are alone, and gets the types of all the others.
- **History:** `no-floating-promises`, the first ported rule, used to request types by position (those of the identifiers and properties of each statement) and approximated the type of calls with the signatures of the callee. That gave 6 false negatives (overloads, generics, non-async IIFEs, `as`, spreads in arrays and union-typed handlers) and a false positive (`x ?? promise` with an `x` that is never `null` or `undefined`), which went away when it moved to types per node. The fixture keeps those cases.
- **Checked with 7.0.2, and again with 7.1.0-beta where it says so:**
  - the `objectFlags` of a type also carry what the checker has computed about it so far (bits 19 and up: whether its members are resolved, whether it could contain type variables…), so the same type may answer other flags later. veslint only reads the bits that say what the type is (class, reference, tuple, anonymous, mapped, instantiated, object literal);
  - 7.1.0-beta: a symbol is named by a reference to the file or the snapshot that owns it: the descriptor of the file and an id for the symbols of a binder, and the snapshot, the project and an id for those the checker makes (the properties of a union, of a mapped type), ids that do not fit in 32 bits. Other responses (the symbol of a type, the parent of a symbol, the parameters of a signature) only carry the id and the node id of the file, and a request needs the whole reference. veslint keeps an int per symbol, the same for both forms, and sends the reference back (`tsgo/symbols.v`). The `[Symbol.iterator]` property is called `__@iterator@<id>`, with the id of the reference of `SymbolConstructor.iterator`;
  - 7.1.0-beta: the parameters of a signature can only be named in a request once `getParametersOfSignature` sent them whole;
  - `getParametersOfSignature` includes the declarations of each parameter. Those of the signatures TypeScript synthesizes when calling a union of different functions have none, and `no-unsafe-argument` does not take them as rest, like typescript-eslint;
  - `getPropertiesOfType` returns escaped names, like `getSymbolsAtPositions`: `__a` arrives as `___a`;
  - `typeToString` takes TypeScript's `TypeFormatFlags`; `getSourceFileMetadata` tells whether a file is a default library (`lib.*.d.ts`);
  - `getSignatureFromDeclaration` fails on a node that is not function-like (the connection survives), and a declared optional parameter (`a?`) has no `SymbolFlags.Optional`;
  - the API does not expose the `modifiersType` of a mapped type, 7.1.0-beta included. 7.0.2 had no `getSymbolsInScope`, `getAwaitedType`, batch request or parts of a mapped type (type parameter, constraint, name type, template); 7.1.0-beta has them all, and a conditional type still has no declaration;
  - 7.1.0-beta, against 7.0.2: a snapshot is made with `createSnapshot` and changed with `updateSnapshot`, which answers only the projects it added or replaced; a project that a change touches stays `dirty`, and answers with its previous program, unless the request asks for `ensurePrograms`. `isTupleType` is a field of a type and not a request; four requests on a type or a signature (`getApparentType`, `getConstraintOfTypeParameter`, `getNonNullableType`, `getReturnTypeOfSignature`) take it as `objectId`; the answer to the `readFile` callback is `{kind: "value", value}` or `{kind: "useOS"}`. The numbers of `SyntaxKind` moved by one from `QualifiedName` on (a new keyword, `SourceKeyword`), and the types of `implements` and of an interface's `extends` are `TypeReference` nodes (only a class's `extends` is an `ExpressionWithTypeArguments`);
  - `getJsDocTags` is not TypeScript 6's `symbol.getJsDocTags`: it leaves out the JSDoc of an initializer and the `@param`/`@template` tags, does not inherit the tags of an overridden member, and renders links as their source. The AST has no `JSDocMemberName` either (`{@link A#b}` is a `QualifiedName`). `no-deprecated` computes the tags from the declarations instead;
  - a top-level expando assignment (`f.x = …`) is not a declaration of `f`, as it is for TypeScript 6's binder. `no-deprecated` adds those declarations itself;
  - the response of a conditional type has the ids of its check and extends types, and that of an index signature its declaration;
  - `getTargetOfType` answers for any object type (for an instance, the type its declaration declares); the type arguments of the instance are in no request;
  - `getTypeArguments` of the target of a class or interface reference gives its type parameters, whose `symbol` is the symbol `getSymbolsAtLocations` gives for their names;
  - a conditional type has the alias of its root, not the one of the reference it was asked through, unless that reference is imported or is the body of another alias; one reached after a decided condition has none;
  - the properties of a mapped type have the declarations of the property of the type it maps over;
  - `typeToString` takes an enclosing declaration (`location`); with `GenerateNamesForShadowedTypeParams` a hidden type parameter is written `T_1`.

### Known limits

Almost all of them give false negatives. None shows up in the fixtures today, and one does in the Spider-Byte evaluation (the order of the members of a union, below).

- **All:**
  - every option of the ported rules is applied. The ones that are regular expressions (`allowPattern` of `dot-notation`, `defaultCaseCommentPattern` of `switch-exhaustiveness-check`, and `custom` and `filter` of `naming-convention`) run on veslint's own matcher of JavaScript's `u` mode (`rules/regexp_match.v`), with Unicode property escapes (`\p{…}`) and modifiers (`(?i:…)`); a search that takes more than two million steps is rejected. V8 14.6 does not always answer a pattern with the `i` flag in a modifier as the specification says. Where its answer is always the same, veslint gives it: after a group is closed, `\w`, `\W` and the classes in brackets still follow the `i` flag that group had (`/(?i:x)|\w/u` matches U+017F, and `/(?i:(?-i:x)|[a])/u` does not match `A`). Where its answer depends on whether V8 optimized the pattern, which it stops doing once the process has generated much regexp code, veslint follows the specification: `/(?i:\p{Lu}S)/u` on `sſ` (false when optimized), `/(?m:(?im:s+))+?/u` on `S` (false when not);
  - a directive comment that names an active rule veslint does not have is never reported as unused, because only that rule knows whether it found something there; the same for a directive without rules when such rules are active. ESLint reports them when that rule found nothing. A configuration comment that turns such a rule off, or on, counts for the directives of that file;
  - the options of a configuration comment and of a configuration file are validated as ESLint validates them, against the schema of each ported rule, with ESLint's own text (`rules/json_schema.v`). Two things stay apart: options a comment gives a rule veslint does not have are not validated; and a pattern option that is not a regular expression fits the schema, so ESLint's rule throws and the run stops, while veslint reports it at the comment or as a usage error. ESLint's first parser of a comment (levn) also reads `undefined`, a `#…#` date and a quoted `"__proto__"` with an object value as JavaScript does; veslint reads the first as null in a list and as no property in an object, the second as that text, and leaves the third out;
  - `reportUnusedInlineConfigs` compares a configuration comment with the configuration as ESLint normalized it, and for that the resolver also brings the default options (`meta.defaultOptions`) of every rule of ESLint and of the plugins. A JSON with a `rules` section is read as ESLint reads a configuration object: veslint normalizes it with the default options of the rules of ESLint 10.6.0 and typescript-eslint 8.62.0 from a generated table, so `eslint --print-config` output gives what ESLint gives. Only the defaults of other plugins' rules are unknown without ESLint;
  - a message that prints a type prints TypeScript 7's text, and its `typeToString` may order the members of a union differently from TypeScript 6, which ESLint uses: `string | Request | URL` against `string | URL | Request`. The position and the `messageId` are the same. For the same reason, the cases the suggestion of `switch-exhaustiveness-check` adds may come in another order. With `"stableTypeOrdering": true` in the tsconfig, TypeScript 6 orders them as TypeScript 7 does and the texts are the same (see the evaluation below);
  - outside an async function, TypeScript reads `await` as an identifier unless a name, a keyword or a literal follows it on its line: `await (x)` is a call, `await [a, b]` an element access, `` await `…` `` a tagged template, and what follows belongs to that expression (`await (x).y`). tree-sitter always reads the operator; veslint asks tsgo how it read each such `await` that is not in the body of an async function (where TypeScript always reads the operator) and, when one is a name, parses the file again with it as an identifier, so every rule sees TypeScript's tree (`rules/await_identifier.v`). It only happens in code that does not compile or in a script that declares an `await` function;
  - an expression with hundreds of nesting levels is slow: veslint requests the types of all its subnodes at once and tsgo takes a while to type them, since each one makes its checker type what the subnode holds again. With 800 chained `&&` operands of different kinds (`v && o.p && o.f() && (v || o.p) && …`), ESLint stops with "Maximum call stack size exceeded" and veslint, with the 61 rules, takes about 7 s, 6.9 s of them in 17 requests to tsgo (TypeScript 7.1.0-beta, measured on 2026-11-11 on an i3-4150T); with plain names as operands it takes 0.5 s.
- **Options with type specifiers** (`allow` in `restrict-template-expressions`, `no-misused-spread`, `no-deprecated`, `prefer-promise-reject-errors` and `only-throw-error`, and the two lists of `no-floating-promises`): bare names and the three origins are applied. Two of them read ESLint's program, and veslint rebuilds what they read:
  - `from: "file"` is relative to the current directory of ESLint's program: the directory of the tsconfig with `parserOptions.projectService`, and the directory ESLint runs in with `parserOptions.project`. veslint takes the one each file's configuration asks for; without one, the tsconfig's directory. With `project` naming tsconfig files (resolved by the project's own typescript-estree: globs, `tsconfigRootDir` or the one typescript-eslint infers), the program of a file is the first of them whose root files include it, as typescript-estree picks it; a file none of them includes is linted with its closest tsconfig, where typescript-eslint stops with a parsing error;
  - `from: "package"` compares with the name TypeScript 6 gives each file it resolved inside a package of `node_modules`: the `name` of its `package.json`, if it also has a `version`, followed by the path of the file inside the package. veslint rebuilds it from the path of the file and that `package.json`. TypeScript gives no name to a file the package brings in with `/// <reference path>`, and veslint does: in `@types/node` 25, where `fs.d.ts` is such a file and declares `exists` in `declare module "node:fs"`, `{from: "package", package: "fs", name: "exists"}` allows `exists` in veslint and not in typescript-eslint (the tsgo API, 7.1.0-beta included, does not say how a file came into the program, and finding it out would take resolving every import of every file of the program);
  - typescript-eslint makes a regular expression of the `package` name, without flags or anchors (`ake-pk` matches `fake-pkg`; `x+y` does not match the package `x+y`). veslint runs it as V8 does (`rules/regexp_annex_b.v`). For a name V8 rejects, both stop when a type gets that far, veslint with its own words. A backreference inside a group with the `i` modifier is an error.
- **`no-misused-promises`:**
  - for a `return` with a value at the top level of a file, typescript-eslint throws (`Non-null Assertion Failed: Expected node to have a parent`) and lints nothing; veslint has no function to compare it with and reports nothing there.
- **Rules that evaluate constants** (`prefer-find`, `prefer-includes`, `prefer-regexp-exec`, `prefer-string-starts-ends-with`, `prefer-reduce-type-parameter`, `prefer-promise-reject-errors`, `use-unknown-in-catch-callback-variable`, `only-throw-error`, and for the name of a method `no-floating-promises`, `no-misused-promises`, `await-thenable`, `no-unnecessary-condition` and the messages of `require-await`, through `rules/static_value.v`): veslint gives the values of eslint-utils' `getStaticValue`. `tests/static_value_cases.json` holds 19,188 expressions answered by eslint-utils itself (`tools/gen_static_value_cases.mjs`), and `rules/static_value_test.v` requires the same value for each one. An exception anywhere in an evaluation makes the whole expression not static, as in eslint-utils, and so do constants that refer to each other. Every function of eslint-utils' `callAllowed` is evaluated but `Date` and `Date.parse`, among them:
  - the 21 transcendental `Math` functions (`acos`, `acosh`, `asin`, `asinh`, `atan`, `atanh`, `atan2`, `cbrt`, `cos`, `cosh`, `exp`, `expm1`, `hypot`, `log`, `log1p`, `log2`, `log10`, `sin`, `sinh`, `tan`, `tanh`), a port of V8's own (its fdlibm, which Node builds without the glibc `sin` and `cos`, and its `Math.hypot`) in `rules/js_math.v`, operation by operation, so their values are V8's to the last bit. `Math.pow` and `**` are evaluated as V8 does: the cases ECMAScript sets apart, `x * x` for an exponent of 2, the square root for 0.5 and the C library's `pow` for the rest, so a veslint linked with another C library than Node's could differ in the last bit there;
  - `String.prototype.normalize`, on tables taken from V8's ICU (`rules/unicode_normalization.v`); `Number.prototype.toString` with a radix other than 10, with V8's digits (its `DoubleToRadixCString`: fraction digits only as far as the precision of the double); `Math.f16round`, rounded to the nearest binary16 directly, not through binary32; the URI functions, `escape`, `unescape`, `String.fromCodePoint`, `String.raw` called as a function, `isPrototypeOf` and `Array.prototype.flat` (`rules/static_builtins.v`); `Symbol.for` and `Symbol.keyFor`, with one symbol per key;
  - `every`, `filter`, `find`, `findIndex` and `some`, when veslint tells the truth of what the callback returns: for the functions it evaluates, for those whose result is always truthy (`Object`, `Date`, `Array`, `Symbol`) and for `Number.isInteger` and `Number.isSafeInteger`.

  The values are modelled with what they inherit: the objects of primitives (`new String('a')`, `Object(1)`), the prototype a `__proto__` key gives an object literal (or the own property it is once the object no longer inherits the setter), an object converted to a primitive by its own `toString` or `valueOf` (OrdinaryToPrimitive, with the hint of each operation, and the default one for the parts of a template literal, which eslint-utils joins with `+`), the methods of `String.prototype` and `Array.prototype` called on a value of another type through a property (they are generic: `({ f: [].join, length: 2, 0: 'x' }).f()`), the methods of iterators, and the shift and bitwise operators on BigInts (infinite two's complement). veslint answers "not static" where eslint-utils computes a value for
  - `Date` and `Date.parse`: most of their values depend on the time zone, the locale or the clock;
  - a builtin function outside `callAllowed` that a builtin calls, whose result veslint does not model: a callback of the array methods (`[x].some(JSON.stringify)`), the `join` that `Array.prototype.toString` calls, the `toString` or `valueOf` of an object being converted (`({ toString: JSON.stringify }) + ''`). The methods that convert their receiver (those of `String.prototype`, and `Array.prototype.toString`) are not called there either: as the `toString` of the object being converted, most of them convert it again without end (a RangeError in V8);
  - properties read or defined with a symbol key (`list[Symbol.iterator]`, `({ [Symbol.toPrimitive]: f })`), and the builtin objects veslint does not model: the prototype objects (`String.prototype`, and `__proto__` read from a primitive) and the properties of builtin functions other than `length`, `name` and their static members (`'a'.slice.length`, and the `length` of `String.raw` that `String.raw(String)` reads). Both would take the object graph of the standard library (every builtin object with each property and its descriptor, about 1,600 of them, and every protocol a well-known symbol drives), for expressions only unusual code writes;
  - a BigInt of more than 2^16 bits made by `**` or `<<` (V8 goes up to 2^30 bits): veslint keeps BigInts as decimal digits, and writing them takes a time that grows with the square of their length (3.6 s for 2^20 bits);
  - a string of more than 2^20 units made by `padStart`, `padEnd` or `String.raw`, or an array-like object of more than 2^20 elements as the receiver of an array method, which bound the memory and the time of an evaluation;
  - expressions nested more than 100 levels deep, which bound the stack (eslint-utils overflows thousands of levels deeper);
  - a constant on which a method is called with a computed name that veslint cannot evaluate for one of the reasons above (`k[Symbol.iterator]()`): eslint-utils evaluates the name to see whether the call mutates the constant.

  eslint-utils does not evaluate `toLocaleUpperCase`, `toLocaleLowerCase`, `map`, `reduce`, `split`, `replace`, `JSON.*`, `Symbol()`, `Object.assign` and the like either, so those are no difference. Constants that use another constant twice at each of many levels (`const a1 = [a0, a0]; const a2 = [a1, a1];` and so on) are evaluated again at every use in both tools, so the work doubles with each level, and veslint is slower at it. Whole runs of `@typescript-eslint/prefer-find` on `list.filter(ok)[aN.length - 2]` take, with 18 levels, 1.6 s in ESLint and 1.6 s in veslint; with 20 levels, 2.1 s and 13 s; with 22 levels, 4.3 s and 2.9 minutes (and 1 GB and 4.2 GB of memory). Most of it is the garbage collector: the values only grow (veslint's representation of a value takes 392 bytes), and libgc grows its heap 16 MiB at a time (veslint builds it with LARGE_CONFIG; 8 MiB without it) and walks every live value after each growth, so its time grows with the square of their size. With collection off (`GC_DONT_GC=1`), 20 levels take 4.9 s and 3.5 GB instead of 13 s and 1.1 GB.
- **Rules that use scopes** (`no-implied-eval`, `no-unnecessary-type-conversion`, `no-mixed-enums`, `no-base-to-string`, `no-unnecessary-type-assertion`, `prefer-optional-chain`, `prefer-promise-reject-errors`, `only-throw-error` and the constant evaluation above, through `rules/scope.v`):
  - the implicit variables of a script that assigns to an undeclared name and the strictness of a scope are not kept (no ported rule reads them);
  - where typescript-eslint fails, veslint goes on: a lib it does not know is left out, a JSX pragma that names a variable without identifiers (a lib variable, a quoted enum member) references nothing, and an import in a script is read.
- **`no-unnecessary-type-assertion`:** whether a property of a mapped type without a `readonly` token is readonly depends on the type it maps over (its `modifiersType`), which the tsgo API does not expose, 7.1.0-beta included. veslint reads it from the declaration of the mapped type and the type arguments of the alias of the type (`Partial<T>`, `Pick<T, K>`, `Omit<T, K>`, an alias of the project), and matches typescript-eslint. For an instance without an alias that comes from an expression (what a generic function returns), whose type arguments nothing tells, it takes the type that the template of the instance indexes with its type parameter (`T[K]`, `Promise<T[K]>`…), since tsgo gives both since 7.1. When the template of the declaration does not index that type (`{ [K in keyof T]: string }`), veslint reads the readonly flag TypeScript gives the property, which is unset, where typescript-eslint answers readonly, for a property that is readonly in only some parts of an intersection or that is a namespace, and set, where it answers not readonly, for the `length` of a readonly tuple.
- **`no-mixed-enums`:** for an enum merged through namespaces whose first declaration has no members, typescript-eslint throws (`TypeError: Cannot read properties of undefined (reading 'initializer')`); veslint takes it as a number enum.
- **`unbound-method`:** the natively bound members (`Math.max`, `JSON.parse`…) are those of the Node that generated `rules/unbound_method_natives.v` (26.8.2; 26.13.0, which runs the reference ESLint now, has the same 147). typescript-eslint computes the list when it loads, so there it depends on the Node version.
- **`use-unknown-in-catch-callback-variable`:** for a handler whose only parameter is a rest of the empty tuple (`promise.catch((...args: []) => args)`), typescript-eslint throws (`TypeError: Cannot read properties of undefined (reading 'flags')`) and lints nothing; veslint reports the handler.
- **`only-throw-error`:** for a thrown identifier that has no variable in the scopes of the file (a global declared in another file), typescript-eslint throws (`Non-null Assertion Failed: Variable … should exist in scope manager`) and lints nothing; veslint takes it as not rethrown and checks its type.
- **`prefer-readonly-parameter-types`:** for a conditional type, typescript-eslint looks at the two branches as written in its declaration (`type.root.node` in TypeScript 6), which the tsgo API does not give, 7.1 included: requested in microsoft/TypeScript#64740. veslint finds the declaration from the alias of the type or from where the type comes from: the annotation of the parameter, the declaration of the member of a class, interface or object type it is the type of, an element of an array or tuple, a property of a mapped type, the type arguments of the use; and then answers the same. It does not find it for the type of a parameter without an annotation, nor through what an `infer` gives, a `typeof`, an import type, `this`, an indexed access that is not `T['name']`, a tuple with a rest element or a member inherited through an alias: there it looks at the branches with the type arguments applied, which differ when a branch is a type parameter that the use replaces with an object type, or when a branch names the type the condition checks and that type is not a type parameter (in `string extends keyof T ? string : …` that `string` is then `keyof T & string`, which has the methods of `String`).
- **`no-unnecessary-type-parameters`:** for an instance of a generic mapped type without properties (the inferred return type of a call, without an alias) typescript-eslint looks at its keys, which tsgo gives since 7.1 (`getConstraintTypeOfMappedType`; with 7.0.2 veslint read them in the text TypeScript writes for the type). It looks at the template instead when TypeScript had already computed it, because the instance was compared with another mapped type (the two branches of `flag ? f(a) : g(a)`): that depends on what TypeScript 6 did before, which veslint cannot know, and it looks at the keys.
- **`consistent-type-imports`:** it takes `emitDecoratorMetadata` and `experimentalDecorators` from the tsconfig of the project, as typescript-eslint does when it has a program. typescript-eslint takes them from `parserOptions` only when it has no program, which veslint always has: the 10 cases of its test that run without one are in `tests/upstream/known.txt`.
- **`no-use-before-define`:** for `export { X }` of a global that the file does not declare (a name of a lib, such as `Array`) with `allowNamedExports: false`, typescript-eslint throws (it reads `identifiers[0].range` of a variable without identifiers) and ESLint does not lint the file; veslint reports the name.
- **`no-unused-vars`:** when `naming-convention` runs on the same file, typescript-eslint computes the result of `collectVariables` they share as `naming-convention` is created, before `no-unused-vars` marks the declarations of declared namespaces and modules (and those of definition files) as used; veslint computes it as `no-unused-vars` alone does. The two differ only with `reportUsedIgnorePattern` and an ignore pattern that names such a declaration: ESLint reports `usedIgnoredVar` without `naming-convention` and not with it.

### How it is validated

- **Fixtures:**
  - each rule has `tests/rules/<rule id>/cases.ts` (`tests/rules/@typescript-eslint/await-thenable/`) and `expected.txt`, which is veslint's exact output; the rules with JSX cases have a `cases.tsx` in a subdirectory;
  - also, `no-semicolons/cases.ts` (with its own tsconfig) tests code without `;` and with end-of-line comments; the `no-floating-promises` one and those of the `no-unsafe-*` family also have a BOM, CRLF and emoji;
  - `line-breaks/cases.ts` in six rules (`no-floating-promises`, `no-array-delete`, `switch-exhaustiveness-check`, `no-unnecessary-template-expression`, `prefer-optional-chain`, `no-unnecessary-type-conversion`) and `tests/directives/line-breaks.ts` really contain U+2028, U+2029, lone CRs and CRLF, in comments, code, strings and template literals: the positions, the indentation of the fixes and the lines of the directives are ESLint's;
  - `invalid-utf8/` in `no-floating-promises` and `no-unsafe-member-access` has a file that is not valid UTF-8 (lone bytes, truncated and overlong sequences, surrogates and code points above U+10FFFF);
  - other subdirectories test different configurations or origins: `this/` (with `noImplicitThis: false`, for the `*This` variants), `no-unsafe-assignment/optional/` (with `exactOptionalPropertyTypes`), `no-unsafe-return/exported/` (exported functions and decorated methods), `no-unsafe-assignment/empty-tuple/` (nodes tsgo panics on), `no-floating-promises/optional-call/` (optional calls), `no-floating-promises/allow-lists/` (the three origins of type specifiers, with packages in a `node_modules` of its own), `no-unnecessary-type-assertion/qualified/` (`x as A.B.C`), `prefer-nullish-coalescing/boolean-coercion/` (with `ignoreBooleanCoercion`), `await-outside-async/` (`await` outside an async function in a module) and `await-script/` (a script that declares an `await` function);
  - `checker-calls/` in seven rules asks for the type of a symbol at the node typescript-eslint asks it at; `no-unsafe-return/awaited/` has overloaded, generic, recursive and `this`-typed `then` methods, among them the cases the port of `getAwaitedType` could not decide before 7.1; `no-unsafe-assignment/regexp-keys/`, regular expressions as computed keys; `no-unnecessary-qualifier/scopes/` and `scopes-module/`, the names `resolveName` and `getSymbolsInScope` see differently; and the `await-outside-async/` and `await-script/` directories, an `await` that TypeScript reads as a name, also with more accesses after it;
  - a subdirectory with an `options.json` (the list of ESLint options of the rule) runs its cases with those options: for example, `spider-byte/` has the options of Spider-Byte's configuration;
  - the fixtures of the `seyfert/*` rules have what the plugin's tests do not: values, base classes and options in other modules of the program, re-exports, namespace imports and declaration files; the wrappers some rules look through and others do not (parentheses, `as`, `satisfies`, `!`, `<T>`) and optional chains; decorators before and after `export default`, on class expressions and on members; descriptions counted in code points (emoji, combining marks, escapes); positions after characters of two UTF-16 units; a `.tsx` file; and, for `group-exists`, a directory loaded by `@AutoLoad` with nested folders, a declaration file, a file the tsconfig excludes and anonymous default exports. They found two differences in `no-hanging-middleware`, now fixed: after a `?.`, the rest of the chain, the arguments of its calls too, may not run; and a generator function is a middleware too;
  - `tests/run.sh` (part of `make test`) requires them to match.
- **Comparison with ESLint:**
  - `tests/rules/reference.sh` runs ESLint 10.6.0 with typescript-eslint 8.62.0 (and @slipher/eslint-plugin 1.1.0 for the `seyfert/*` rules), each rule only on its fixtures and with their options, in one process for the fixtures of the `seyfert/*` rules and another for the rest: in a single process with all of them, V8 (Node 26.13.0) stops matching an alternation in a regexp modifier group with the `u` flag at some point of the run (`/^(?i:get|set)\p{Lu}/u`, of the fixtures of `naming-convention`, no longer matches `SetÉtat`), which a new process matches, like veslint;
  - it checks that its findings (position, rule, `messageId` and the full message text) are those of `expected.txt` plus those of `limitations.txt`, the documented cases veslint does not report;
  - today all 120 rules match: 13,158 typescript-eslint findings and 271 of @slipher/eslint-plugin, with no listed limitation;
  - a rule with fixes or suggestions also has a `fixes.txt`, veslint's exact output with `--fixes`: for the 61 rules, 7,230 findings are compared with the fix and the suggestions ESLint gives them (range and text);
  - four more directories are compared with ESLint with the same rules in both tools: `tests/directives/` (directive comments and inline configuration, also with options that do not fit the schema of the rule and with every line break, 103 messages with their fixes), `tests/config/` (an `eslint.config.mjs` with ignores, rules per folder, `linterOptions` with `reportUnusedInlineConfigs`, an `ecmaVersion`, `globals`, scripts and CommonJS, `parserOptions.lib`, the two ways the parser gets the types and rules veslint does not have, 87 messages; and two JSON files that are what `eslint --print-config` prints), `tests/config-errors/` (seven configurations ESLint does not take, with the text the `eslint` command prints for each) and `tests/fix/` (the text `eslint --fix` leaves for 19 rules together, byte for byte, and the messages that remain);
  - it needs the dependencies `tests/eval_spider_byte.sh` installs.
- **@slipher/eslint-plugin's own tests:** the 15 `seyfert/*` rules run every case of the plugin's tests at 221401c7c2 (`test/<rule>.test.mts`, vitest with `@typescript-eslint/rule-tester`, the project service with its default project, and seyfert 5.2.0): 459 cases and the 11 projects its tests write to disk (`lintProject` of `test/_disk.ts`), in `tests/rules/seyfert/<rule>/upstream.json` (`tools/gen_upstream_cases.mjs`), in the fixtures `tests/upstream/seyfert/setup.sh` makes. `tests/rules/reference.sh` checks that ESLint with the npm plugin gives what each test expects and that veslint prints what ESLint gives; `tests/run.sh` checks veslint as RuleTester does: all 470 pass.
- **ESLint's own tests of its core rules:** the 62 rules of ESLint core run every case of their tests in ESLint v10.6.0 (`tests/lib/rules/<rule>.js`): 5,944 cases in `tests/rules/<rule>/upstream.json` (`tools/gen_upstream_cases.mjs`). The cases are JavaScript and veslint lints only TypeScript, so each one is linted as TypeScript in the `file.ts` (`react.tsx` with JSX) of typescript-eslint's fixtures, with the `languageOptions` of its test; `tests/rules/reference.sh` checks that ESLint 10.6.0 with typescript-eslint's parser gives what each test expects there (with one pass of fixes, as ESLint's RuleTester makes; typescript-eslint's makes up to 10) (all but the cases listed in `tests/upstream/known.txt`: typescript-eslint's lib declares `Boolean`, `Object` and `Reflect`, which a `globals` setting of `"off"` does not remove, and its parser rejects octal literals and escapes, `\8` and `\9` and decimals with leading zeros, which TypeScript does not allow) and that veslint prints what ESLint gives; `tests/run.sh` checks veslint as RuleTester does: all pass, but the same six cases of the lib's globals, one where veslint resolves `Math` after `/* globals Math:off */` and ESLint does not, and one of tree-sitter's grammar (`static get` before a line break).
- **typescript-eslint's own tests:** each of the 105 rules also runs every case of its own test in typescript-eslint v8.62.0, in the fixtures and with the `@types` packages of that test (26,825 cases in `tests/rules/<rule>/upstream.json`, 16,112 of them `naming-convention`'s; see `tests/upstream/README.md`):
  - `tests/run.sh` checks veslint on each case as RuleTester does: the messageId, the message, the line and the column of each problem, its suggestions and the text each one leaves, and the output of the fixes, pass after pass. It does not check where a problem ends, which veslint does not print;
  - `tests/rules/reference.sh` checks that ESLint gives what each test expects, and that veslint prints, case by case and in the same order, the lines ESLint gives, with the fixes and the suggestions;
  - 26,823 cases run (upstream skips 2) and give what their test expects, but the 22 listed in `tests/upstream/known.txt`: five where TypeScript 7 orders the members of a union in another way (with TypeScript 6's `stableTypeOrdering`, ESLint gives what veslint gives), three that the grammar reads in another way (a `new` followed by a line break and a mapped type without a type; see "Grammar"), ten of `consistent-type-imports` that its test runs without a program (see the known limits), and four of `no-unused-vars` that turn on rules their test file defines, which neither tool has (ESLint does not give what five of them expect either);
  - they found eleven differences, now fixed: a stack overflow of `no-deprecated` with a class that implements itself; `never` in the return type of a construct signature (`no-redundant-type-constituents`); a method named `''` in the message of `require-await`; the type arguments of a JSX element (`no-unnecessary-type-arguments`); the contextual type of a JSX expression (`no-unnecessary-type-assertion`); `array.length` in the body of an arrow predicate (`strict-boolean-expressions`); private properties under `exactOptionalPropertyTypes` (`no-unnecessary-condition`: tsgo names their symbols `__#<id>@#x`); three gaps of the grammar (see "Grammar"); and the order of two problems at one position, which is now the order in which the rule reports them, as in ESLint.
- **Every rule on every fixture:** the reference runs each rule on its own fixtures only. `tests/rules/cross.sh` runs the 120 rules together, with their default options, on all the fixture files, in both tools (ESLint lints each file on its own, because a rule of typescript-eslint that throws stops a whole run). Of 33,335 findings of ESLint, 33,334 are identical; the differences are the ones listed in `tests/rules/cross.known.txt`: one finding with the members of a union in another order, and one file that is not compared because `no-misused-promises` of typescript-eslint throws on it. This check found eight differences that the fixtures of each rule did not have, now fixed and with fixtures of their own: the spread of a JSX attribute in `no-misused-promises`, an optional chain in parentheses as a callee (`(p?.catch)(f)`) in `no-floating-promises` and as an object (`(x?.a).b`) in `no-unsafe-member-access`, members whose name starts with `__` in `strict-void-return`, a `!` that ends an optional chain in parentheses (`(a?.b!)!`, inside a ChainExpression in ESTree) in `no-extra-non-null-assertion`, import attributes (`with { type: 'json' }`, which are not an object literal in ESTree) in `no-unsafe-assignment`, the reference the JSX pragma makes (with the declared identifier itself, whose range takes its type annotation) in `no-use-before-define`, and the names inside the parameters of signatures and setters (a type annotation, a default value), which typescript-eslint's `collectVariables` marks as used, in `no-unused-vars` and the `unused` modifier of `naming-convention`.
- **Code paths:** whether the end of a function is reachable follows ESLint 10.6.0's code path analysis for statements (`rules/code_path.v`): a `catch` block is entered from the first node of the `try` block that may throw (a call, a `new`, a member access, a `yield` or an identifier that is not a declaration), and in a `catch` block with a `finally`, that node makes a path to the `finally` block. `tests/rules/code_path_diff.sh` compares the two analyses through `consistent-return`, which reports the functions whose end is reachable, on 55,785 generated functions (`tools/gen_code_path_cases.py`): every small nesting of two `try` statements, a `try` statement in a loop or a labeled block, and random ones; both report the same. It found the `finally` path of a `catch` block, now followed (`consistent-return/catch-finally/`).
- **Scopes:** `tools/gen_scope_cases.mjs` runs typescript-eslint's parser and scope manager inside ESLint on the 45 programs of `tests/scope/` and writes every scope, variable and reference to `tests/scope_cases.json`; `rules/scope_oracle_test.v` requires the same from `rules/scope.v`: 1,544 references, and every variable of the global scope.
- **Constant values:** `tools/gen_static_value_cases.mjs` runs a probe rule inside ESLint that calls the real `getStaticValue` of eslint-utils on 19,188 expressions, three times with different time zones and locales, and `rules/static_value_test.v` compares (see "Rules that evaluate constants" in the known limits).
- `typeToString` of TypeScript 7 may order the members of a union differently from TypeScript 6, which ESLint uses. It does not happen in the fixtures; it does in 5 findings of the Spider-Byte evaluation (see below).

### Evaluation on Spider-Byte

`tests/eval_spider_byte.sh` reproduces this evaluation on [Spider-Byte](https://github.com/FabrizioCoder/Spider-Byte), a Discord bot built with seyfert. It uses commit `62ca127`, with 65 TypeScript files. It was run with TypeScript 7.0.2; with 7.1.0-beta, veslint gives the same output in the 434 runs of the comparison (each rule alone and all together, in the seven scenarios), so its findings stand, while its times were not measured again.

- **Setup:** downloads the code and its dependencies into `build/eval/`, only if missing. The dependencies are installed with `bun install --ignore-scripts`.
- **Comparison:** each veslint rule against typescript-eslint 8.62.0's, run with ESLint 10.6.0, finding by finding (file, line, column, `messageId` and message), both with the rule's entry in the real Spider-Byte configuration (exported with `eslint --print-config`); then all of them together.
- **Mutations:** since the original code has almost no problems, copies with real errors and the seyfert types are generated:
  - `mutation`: 48 leading `await`/`void` removed;
  - `mutation-await`: 157 `await x` turned into `await await x`;
  - `mutation-no-await`: 157 `await` removed;
  - `mutation-return-await`: 158 `return x` turned into `return await x`;
  - `mutation-any`: 465 `: string`, `: number` or `: boolean` annotations turned into `: any`;
  - `mutation-prefer`: 748 expressions rewritten into the forms the `prefer-*` rules and `dot-notation` report (`a?.b` into `(a && a.b)`, `x.includes(y)` into `(x.indexOf(y) !== -1)`, `ctx.name` into `ctx["name"]`…).

Results of 2026-10-10 for the 61 rules. typescript-eslint findings, which are also veslint's except where noted below; the 31 rules that are not listed report nothing in any scenario:

| Rule | Original | `mutation` | `mutation-await` | `mutation-no-await` | `mutation-return-await` | `mutation-any` | `mutation-prefer` |
|---|---|---|---|---|---|---|---|
| `no-floating-promises` | 0 | 39 | 0 | 33 | 0 | 0 | 0 |
| `await-thenable` | 0 | 0 | 146 | 0 | 75 | 0 | 0 |
| `require-await` | 0 | 6 | 0 | 29 | 0 | 0 | 0 |
| `return-await` | 0 | 0 | 0 | 0 | 73 | 0 | 0 |
| `no-misused-promises` | 0 | 0 | 0 | 21 | 0 | 0 | 0 |
| `no-unsafe-argument` | 6 | 6 | 6 | 47 | 9 | 143 | 7 |
| `no-unsafe-assignment` | 7 | 7 | 7 | 45 | 9 | 174 | 8 |
| `no-unsafe-call` | 10 | 10 | 10 | 67 | 17 | 83 | 10 |
| `no-unsafe-member-access` | 14 | 14 | 14 | 113 | 15 | 117 | 18 |
| `no-unsafe-return` | 1 | 1 | 1 | 9 | 8 | 11 | 1 |
| `restrict-template-expressions` | 1 | 1 | 1 | 25 | 2 | 129 | 1 |
| `no-unnecessary-condition` | 0 | 0 | 0 | 23 | 0 | 0 | 5 |
| `dot-notation` | 0 | 0 | 0 | 0 | 0 | 0 | 714 |
| `no-confusing-void-expression` | 0 | 0 | 24 | 0 | 47 | 0 | 0 |
| `no-misused-spread` | 0 | 0 | 0 | 1 | 0 | 0 | 0 |
| `no-redundant-type-constituents` | 0 | 0 | 0 | 0 | 0 | 36 | 0 |
| `no-unsafe-enum-comparison` | 0 | 4 | 4 | 4 | 4 | 4 | 4 |
| `prefer-find` | 0 | 0 | 0 | 0 | 0 | 0 | 7 |
| `prefer-regexp-exec` | 0 | 0 | 0 | 0 | 0 | 0 | 1 |
| `prefer-includes` | 0 | 0 | 0 | 0 | 0 | 0 | 3 |
| `prefer-string-starts-ends-with` | 0 | 0 | 0 | 0 | 0 | 0 | 1 |
| `prefer-optional-chain` | 0 | 0 | 0 | 0 | 0 | 0 | 20 |
| `naming-convention` | 270 | 270 | 270 | 270 | 256 | 270 | 270 |
| `prefer-readonly-parameter-types` | 160 | 160 | 160 | 134 | 128 | 160 | 160 |
| `strict-boolean-expressions` | 60 | 60 | 60 | 92 | 55 | 82 | 59 |
| `promise-function-async` | 24 | 24 | 24 | 21 | 3 | 24 | 24 |
| `no-unsafe-type-assertion` | 10 | 10 | 10 | 10 | 9 | 10 | 10 |
| `consistent-return` | 7 | 7 | 7 | 7 | 6 | 7 | 7 |
| `prefer-destructuring` | 6 | 6 | 6 | 6 | 6 | 6 | 9 |
| `no-unnecessary-type-parameters` | 1 | 1 | 1 | 1 | 0 | 1 | 1 |
| **All together** | **577** | **626** | **751** | **958** | **722** | **1,257** | **1,340** |

- **Match:** 434 comparisons (61 rules × 7 scenarios, and all the rules together in each scenario), up to `JOBS` of them at a time (all the cores by default; about 5 minutes with 12). The per-rule runs add up to 6,231 typescript-eslint findings, and veslint gives the same ones, with the same message, except for 5.
- **The 5 that differ** are `no-unsafe-argument` findings (3 in `mutation-no-await` and 2 in `mutation-any`) at the same position and with the same `messageId`, whose message prints a union with its members in another order: TypeScript 7 orders them differently from TypeScript 6 (see "Known limits", in "All").
- **With `stableTypeOrdering`**, the TypeScript 6 option that orders types as TypeScript 7 does, nothing differs: the script runs all the rules together once more in each scenario, with a tsconfig that extends the scenario's and turns the option on, and the 6,231 findings match with their messages.
- **`await` outside an async function:** in `mutation-return-await`, 7 of the findings come from `return await` in functions that are not async (`` return await `…` ``, `return await [a, b]`), which TypeScript reads as a tagged template or an element access; veslint follows that reading (see "Known limits", in "All").
- **In the original**, the `no-unsafe-*` findings are uses of the Prisma client, which is not generated (see below), or values coming from it: their types are the error `any` and the `error*` variants are reported.
- **Excluded files:** in `mutation-return-await`, ESLint cannot parse 5 files (`return await` in functions that are not async), and those files are left out of the comparison.
- **Mutated copies:** they carry `src/`, the configuration and `assets/json` (the JSON `src/` imports), with the dependencies linked.

Times on the original code (the 65 files), one run at a time, measured on 2026-10-10 while other work kept the machine busy (a load average of about 5):

| Run | veslint | ESLint + typescript-eslint |
|---|---|---|
| One rule per run, each of the 61 | 0.14 s to 0.61 s | 1.73 s to 3.26 s |
| The 61 runs added up | 14.4 s | 132.2 s |
| The 61 rules in a single run (the best of four) | 1.83 s | 3.42 s |

**Each rule on its own, with the code of 2026-11-11** (all 105 rules; on the minipc, an i3-4150T from 2014, with TypeScript 7.1.0-beta): on one core (`taskset`), one process at a time, 3 runs of veslint and 1 of ESLint alternated, and the best of each kept. Both tools get the options of the real configuration, and the last column is the number of findings, which is the same in both unless it says otherwise. The time of a run includes starting the tool: tsgo for veslint (and its first snapshot, for a rule that needs types), and Node, ESLint and the TypeScript program for ESLint.

| Rule | veslint | ESLint + typescript-eslint | Times faster | Findings |
|---|---|---|---|---|
| `adjacent-overload-signatures` | 0.10 s | 7.10 s | 67.6 | 0 |
| `array-type` | 0.11 s | 8.00 s | 70.1 | 0 |
| `await-thenable` | 0.99 s | 8.64 s | 8.7 | 0 |
| `class-literal-property-style` | 0.11 s | 7.52 s | 69.0 | 0 |
| `consistent-generic-constructors` | 0.11 s | 7.44 s | 68.3 | 0 |
| `consistent-indexed-object-style` | 0.11 s | 6.90 s | 65.1 | 0 |
| `consistent-return` | 0.91 s | 8.76 s | 9.6 | 7 |
| `consistent-type-assertions` | 0.10 s | 6.72 s | 64.6 | 0 |
| `consistent-type-definitions` | 0.10 s | 6.74 s | 64.2 | 0 |
| `consistent-type-exports` | 0.82 s | 6.81 s | 8.3 | 0 |
| `consistent-type-imports` | 0.15 s | 10.46 s | 71.2 | 0 |
| `dot-notation` | 0.82 s | 6.82 s | 8.3 | 0 |
| `naming-convention` | 0.95 s | 8.64 s | 9.1 | 270 |
| `no-array-constructor` | 0.11 s | 6.73 s | 63.5 | 0 |
| `no-array-delete` | 0.91 s | 7.87 s | 8.6 | 0 |
| `no-base-to-string` | 1.21 s | 8.86 s | 7.3 | 0 |
| `no-confusing-non-null-assertion` | 0.13 s | 7.79 s | 61.8 | 0 |
| `no-confusing-void-expression` | 1.05 s | 8.95 s | 8.5 | 0 |
| `no-deprecated` | 2.02 s | 10.21 s | 5.1 | 0 |
| `no-dupe-class-members` | 0.10 s | 6.81 s | 65.5 | 0 |
| `no-duplicate-enum-values` | 0.11 s | 7.21 s | 65.5 | 0 |
| `no-duplicate-type-constituents` | 0.83 s | 6.86 s | 8.2 | 0 |
| `no-dynamic-delete` | 0.11 s | 7.19 s | 66.5 | 0 |
| `no-empty-function` | 0.11 s | 6.80 s | 63.5 | 0 |
| `no-extraneous-class` | 0.11 s | 7.30 s | 65.2 | 0 |
| `no-extra-non-null-assertion` | 0.11 s | 6.81 s | 63.6 | 0 |
| `no-floating-promises` | 1.01 s | 9.23 s | 9.2 | 0 |
| `no-for-in-array` | 0.85 s | 7.49 s | 8.8 | 0 |
| `no-implied-eval` | 0.90 s | 7.34 s | 8.2 | 0 |
| `no-import-type-side-effects` | 0.10 s | 6.80 s | 66.0 | 0 |
| `no-inferrable-types` | 0.11 s | 7.53 s | 66.0 | 0 |
| `no-invalid-void-type` | 0.11 s | 6.79 s | 64.0 | 0 |
| `no-meaningless-void-operator` | 0.94 s | 8.24 s | 8.8 | 0 |
| `no-misused-new` | 0.10 s | 6.78 s | 64.6 | 0 |
| `no-misused-promises` | 1.37 s | 10.19 s | 7.4 | 0 |
| `no-misused-spread` | 0.86 s | 6.97 s | 8.1 | 0 |
| `no-mixed-enums` | 0.92 s | 7.50 s | 8.1 | 0 |
| `no-namespace` | 0.10 s | 6.71 s | 64.5 | 0 |
| `non-nullable-type-assertion-style` | 0.90 s | 7.72 s | 8.6 | 0 |
| `no-non-null-asserted-nullish-coalescing` | 0.10 s | 6.77 s | 65.1 | 0 |
| `no-non-null-asserted-optional-chain` | 0.11 s | 7.06 s | 64.8 | 0 |
| `no-redundant-type-constituents` | 0.86 s | 6.92 s | 8.1 | 0 |
| `no-require-imports` | 0.11 s | 7.33 s | 64.9 | 0 |
| `no-shadow` | 0.14 s | 6.80 s | 48.2 | 0 |
| `no-this-alias` | 0.11 s | 7.39 s | 67.8 | 0 |
| `no-unnecessary-boolean-literal-compare` | 0.82 s | 6.84 s | 8.4 | 0 |
| `no-unnecessary-condition` | 1.51 s | 10.02 s | 6.6 | 0 |
| `no-unnecessary-parameter-property-assignment` | 0.10 s | 6.76 s | 64.4 | 0 |
| `no-unnecessary-qualifier` | 1.30 s | 8.95 s | 6.9 | 0 |
| `no-unnecessary-template-expression` | 0.81 s | 7.16 s | 8.9 | 0 |
| `no-unnecessary-type-arguments` | 0.96 s | 8.07 s | 8.4 | 0 |
| `no-unnecessary-type-assertion` | 0.99 s | 8.04 s | 8.1 | 0 |
| `no-unnecessary-type-constraint` | 0.11 s | 6.85 s | 64.7 | 0 |
| `no-unnecessary-type-conversion` | 0.99 s | 8.07 s | 8.2 | 0 |
| `no-unnecessary-type-parameters` | 0.87 s | 6.89 s | 8.0 | 1 |
| `no-unsafe-argument` | 1.12 s | 9.70 s | 8.7 | 6 |
| `no-unsafe-assignment` | 1.10 s | 9.00 s | 8.2 | 7 |
| `no-unsafe-call` | 1.17 s | 8.66 s | 7.4 | 10 |
| `no-unsafe-declaration-merging` | 0.14 s | 6.98 s | 49.5 | 0 |
| `no-unsafe-enum-comparison` | 0.94 s | 8.12 s | 8.6 | 0 |
| `no-unsafe-function-type` | 0.14 s | 6.84 s | 47.2 | 0 |
| `no-unsafe-member-access` | 1.02 s | 8.82 s | 8.7 | 14 |
| `no-unsafe-return` | 1.04 s | 8.71 s | 8.4 | 1 |
| `no-unsafe-type-assertion` | 0.88 s | 7.86 s | 8.9 | 10 |
| `no-unsafe-unary-minus` | 0.86 s | 6.86 s | 8.0 | 0 |
| `no-unused-expressions` | 0.11 s | 6.83 s | 61.5 | 0 |
| `no-unused-private-class-members` | 0.17 s | 6.83 s | 40.4 | 0 |
| `no-unused-vars` | 0.18 s | 7.00 s | 39.5 | 0 |
| `no-use-before-define` | 0.16 s | 6.86 s | 42.9 | 0 |
| `no-useless-constructor` | 0.10 s | 6.74 s | 64.8 | 0 |
| `no-useless-default-assignment` | 0.83 s | 6.79 s | 8.2 | 0 |
| `no-useless-empty-export` | 0.10 s | 6.77 s | 65.7 | 0 |
| `no-wrapper-object-types` | 0.14 s | 6.78 s | 47.4 | 0 |
| `only-throw-error` | 0.86 s | 6.85 s | 8.0 | 0 |
| `prefer-as-const` | 0.10 s | 6.74 s | 64.8 | 0 |
| `prefer-destructuring` | 0.84 s | 7.35 s | 8.8 | 6 |
| `prefer-enum-initializers` | 0.10 s | 6.75 s | 64.9 | 0 |
| `prefer-find` | 0.81 s | 6.75 s | 8.3 | 0 |
| `prefer-for-of` | 0.11 s | 6.83 s | 60.4 | 0 |
| `prefer-function-type` | 0.10 s | 6.82 s | 65.6 | 0 |
| `prefer-includes` | 0.82 s | 6.75 s | 8.2 | 0 |
| `prefer-namespace-keyword` | 0.10 s | 6.74 s | 64.8 | 0 |
| `prefer-nullish-coalescing` | 0.87 s | 7.77 s | 8.9 | 0 |
| `prefer-optional-chain` | 0.97 s | 8.38 s | 8.7 | 0 |
| `prefer-promise-reject-errors` | 0.83 s | 6.85 s | 8.3 | 0 |
| `prefer-readonly` | 0.82 s | 6.89 s | 8.4 | 0 |
| `prefer-readonly-parameter-types` | 1.37 s | 8.54 s | 6.2 | 160 |
| `prefer-reduce-type-parameter` | 0.78 s | 6.82 s | 8.7 | 0 |
| `prefer-regexp-exec` | 0.80 s | 6.83 s | 8.6 | 0 |
| `prefer-return-this-type` | 0.82 s | 6.86 s | 8.3 | 0 |
| `prefer-string-starts-ends-with` | 0.81 s | 7.62 s | 9.4 | 0 |
| `promise-function-async` | 0.99 s | 8.91 s | 9.0 | 24 |
| `related-getter-setter-pairs` | 0.82 s | 6.81 s | 8.3 | 0 |
| `require-array-sort-compare` | 0.79 s | 6.78 s | 8.6 | 0 |
| `require-await` | 0.89 s | 8.30 s | 9.3 | 0 |
| `restrict-plus-operands` | 0.93 s | 11.43 s | 12.3 | 0 |
| `restrict-template-expressions` | 1.00 s | 8.26 s | 8.2 | 1 |
| `return-await` | 0.96 s | 9.90 s | 10.3 | 0 |
| `strict-boolean-expressions` | 1.48 s | 9.13 s | 6.2 | 60 |
| `strict-void-return` | 1.27 s | 9.29 s | 7.3 | 0 |
| `switch-exhaustiveness-check` | 0.86 s | 7.34 s | 8.5 | 0 |
| `triple-slash-reference` | 0.12 s | 6.80 s | 56.6 | 0 |
| `unbound-method` | 1.25 s | 9.13 s | 7.3 | 0 |
| `unified-signatures` | 0.10 s | 6.81 s | 64.9 | 0 |
| `use-unknown-in-catch-callback-variable` | 1.00 s | 9.58 s | 9.6 | 0 |
| The 105 added up | 65.0 s | 801.9 s | 12.3 | |

A rule on its own is mostly the cost of starting each tool. The 44 rules without types take 0.10 to 0.18 s in veslint, which builds no program for them (see "How it gets the types"), against 6.71 to 10.46 s in ESLint, whose configuration builds the TypeScript program anyway: 40 to 71 times less. The 61 that need types take 0.78 to 2.02 s in veslint and 6.75 to 11.43 s in ESLint, 5 to 12 times less (8.2 added up). All 105 added up, 65.0 s against 801.9 s, are 12.3 times less, with the same 577 findings in every rule (the 44 without types find nothing in this code). The slowest in veslint are `no-deprecated` (2.02 s), `no-unnecessary-condition` (1.51 s), `strict-boolean-expressions` (1.48 s), `no-misused-promises` and `prefer-readonly-parameter-types` (1.37 s) and `no-unnecessary-qualifier` (1.30 s). All the rules in a single run, measured the same way: the 61 that need types take 2.94 s in veslint and 11.54 s in ESLint, and the 105 take 3.16 s and 11.70 s. ESLint runs once per rule because its runs differ by about 1% (6.83, 6.78 and 6.77 s for `array-type`); two rules at a time, each on its own physical core, made ESLint about 16% slower (the two share the cache and the memory), so the table is measured one rule at a time. The table of 2026-10-13, on the main PC (a Ryzen 7 5800XT) with TypeScript 7.0.2 and the 61 rules, gave 0.39 to 0.89 s and 3.30 to 4.63 s, 7.8 times less added up (`build/eval/results/bench-rules-2026-10-13-mainpc.tsv`); the table before this one is older and was not pinned to one core, where both tools are faster, since tsgo and Node use more than one.

- **One rule per run:** the slowest in veslint are `no-deprecated` (0.61 s), which reads the declarations of every symbol, `strict-void-return` (0.52 s, with 7,731 requests to tsgo and no finding; see below), `prefer-readonly-parameter-types` (0.46 s), `no-misused-promises` (0.44 s), `no-unnecessary-condition` (0.41 s) and `strict-boolean-expressions` (0.39 s). Starting veslint and tsgo on these files takes 0.14 s of each.
- **All the rules together:** between 1.65 and 2.01 s in veslint over the seven scenarios, and between 3.15 and 5.40 s in ESLint (one run each); about 1.9 times less. With the first 49 rules, on a quiet machine, they were 1.23 to 1.35 s and 2.77 to 3.14 s: the twelve other rules add about 0.5 s to veslint, 23,084 requests to tsgo in all.
- **Since then veslint asks tsgo less** (2026-10-11). On these files the 61 rules make 9,520 requests instead of 23,084, with the same findings:
  - what the flags of a type already tell is not asked: its apparent type, its base constraint, whether it is an array or a tuple, its symbol, and the signatures of a primitive or of the type of an object literal (`rules/type_queries.v`, checked against `checker.go` of TypeScript 7.0.2);
  - the resolved signature of a call and the type predicate of a signature are asked once, whichever rules need them;
  - `strict-void-return` asks for a contextual type only where the value has call signatures (1,396 requests instead of 7,731), and `no-unsafe-assignment` for the type of the receiver only where the value is `any` or a generic reference (287 instead of 1,309);
  - the kind of a tree-sitter node is no longer copied into a new string for every node each rule visits.
  With veslint and tsgo on a single core (`taskset -c 0`), the 61 rules together took 1.87 s before these changes (the best of five runs). After the first of them, eleven runs of each binary, alternated, give 1.83 s at best and 1.90 s in the median without the rest and 1.53 s and 1.67 s with them; about 0.4 s of it is starting veslint and tsgo. A rule alone hardly changes: most of its time is that start and tsgo checking the files.
- **Then the nodes of a file by kind** (2026-10-12). Timers in a build of veslint showed where its own time went on these files: not in decoding JSON (46 ms for 9.9 MB of answers), but in walking the tree, about a hundred times for each file, once or twice for each rule (256 ms). On zod they were 0.29 s and 1.6 s.
  - `treesitter/node_index.v` walks the tree of a file once and keeps its nodes by kind, in the order the walks gave them. In 49,365 lookups over the fixtures, Spider-Byte and zod, it gives the same nodes as the walks.
  - Five runs of each binary, alternated, on one core: 1.69 s before and 1.30 s after at best on these files, and 7.05 s and 5.48 s on zod.
  - The symbol an alias stands for, the index signatures of a type and whether a type is assignable to another are asked once (8,392 repeated answers were the same as fresh ones). It spares 200 of the 9,520 requests here and 7,254 of the 69,972 on zod, about 4 % of its time there.
  - An instance of a generic class, interface or tuple (`Array<X>`, `Promise<X>`) has as many signatures as any other instance of it, so it is not asked once one of them had none. And `strict-boolean-expressions`, which resolved every call with arguments to know whether it asserts one, looks first at the signatures of the callee: when none is declared with `asserts`, the call cannot assert. tsgo gave the same answer for the 25,008 and the 11,792 requests spared over the fixtures and the three projects. The requests go from 62,718 to 56,841 on zod and from 75,163 to 69,979 on recharts.
  - What is left is the round trip of each request. tsgo answers requests written together, in order: 20,000 `getVoidType` take 17 µs each one by one and 6 µs each in groups of sixteen, on one core. veslint does not use it: a rule would have to know its next requests before the answers to the previous ones, as it already does for the types of the nodes of a file. TypeScript 7.1's `batchRequests` sends such a group as one message, and would not gain much more: on a lint of Spider-Byte's `src/index.ts` through the server (475 requests, on one CPU of the minipc, 2026-11-11), the round trips add up to about 9 ms of 105. An `echo` takes 20 µs there, most small requests 45 to 95 µs, and the 26 `getTypeAtLocations` (one per rule with types), in which tsgo computes the types again in the new snapshot, about 62 ms.
- **Baselines** (full type check with `tsc --noEmit`): 0.19 s with TS 7 and 1.67 s with TS 6.
- **Type mode on the same code** (measured on 2026-10-04):
  - 1,012 declarations in 0.28 s;
  - 5,544 identifiers with `--all-identifiers` in 0.39 s.
- **Prisma:** the client is not generated (`prisma generate` is not run), so its types exist for neither tool. The comparison is still fair.

### Evaluation on zod, recharts and the TypeScript compiler

`tests/eval_project.sh` runs the ported rules (each directory of `tests/rules` with an `expected.txt`; the `seyfert/*` ones with @slipher/eslint-plugin 1.1.0 of `build/upstream/seyfert`), with their default options, on the sources of three more projects, with both tools reading the same `eslint.config`. ESLint is the one of the Spider-Byte evaluation. It prints the wall time of each tool and the peak resident memory of its processes. The numbers of this section were measured with TypeScript 7.0.2 and the 61 rules of then, before veslint moved to 7.1.0-beta; 7.1.0-beta also answers the empty array literals they list as not analyzed. On 2026-11-11, with 7.1.0-beta and the 72 rules, zod gives 6,878 messages in both tools: 6,858 identical and the same 20 with a type printed in another order; the 23 more are those of `no-namespace` (9), `no-unsafe-function-type` (7) and `no-dynamic-delete` (7). With the 105 rules it gives 7,678 messages in both tools, 7,658 identical and the same 20; 802 come from 16 of the 33 rules of batches T2 to T5 (`no-use-before-define` 287, `consistent-indexed-object-style` 145, `no-shadow` 135, `no-unused-vars` 73, `consistent-type-definitions` 48, `no-inferrable-types` 43, `array-type` 31 and nine more).

**zod.** `tests/eval_project.sh zod` takes the sources of [zod](https://github.com/colinhacks/zod): commit `284243f`, 125 files and 37,778 lines without its tests and benchmarks. It is a library whose types are much heavier than an application's. Nothing of zod is installed, since it has no dependencies at run time.

- **Findings:** ESLint gives 6,855 messages, 6,847 of them from 41 typescript-eslint rules and 8 of its own (three unused directives and five directives that name a rule of a plugin that is not there). veslint gives the same 6,855:
  - 6,835 are identical;
  - 20 are the same finding at the same place with a type printed in another order (TypeScript 6 against 7);
  - none is missing and none is extra.
- **With `stableTypeOrdering`** (`STABLE=1`), 6,854 are identical and one is only in veslint, because TypeScript itself differs. In `(a || b || {}) as Record<string, T>`, where `b` is `unknown`, the type of the expression is `{}` for all of them; but TypeScript 6 with that option keeps the one of the object literal, which is assignable to the record, and TypeScript 6 without it and TypeScript 7 keep the empty object type, which is not (their `tsc` rejects the same assignment with TS2322). So `no-unsafe-type-assertion` reports it with TypeScript 7, and with TypeScript 6 as zod configures it. TypeScript's team calls this working as intended (microsoft/TypeScript#64807): TypeScript 7 prefers an implicit `{}` to one written in the code when it reduces subtypes (microsoft/typescript-go#1603), and the change was not brought to TypeScript 6, nor is it expected to be.
- **Nodes not analyzed:** three, in two files. They are empty array literals whose type is the empty tuple, on which tsgo 7.0.2 panics (see "How it gets the types"). No finding is lost to them.
- **A rule of a plugin that is not there:** with the `eslint.config`, veslint knows which plugins exist and answers like ESLint (`Definition for rule 'ban/ban' was not found.`). With a plain JSON of rules it cannot know, and takes the directive for an unused one.
- **Time,** with veslint and tsgo on one core: 5.5 s in veslint and 11.5 s in ESLint (the best of five and of three runs; the machine was busy with other work). veslint makes 56,841 requests to tsgo here, against 9,183 on Spider-Byte. Waiting for their answers is more than half of its time: about 1 s is tsgo checking the files, when the types of the nodes are asked, and most of the rest is some 58,000 small requests at 20 to 45 µs each, which only a batch request (TypeScript 7.1 has one) would spare.

**recharts.** `tests/eval_project.sh recharts` takes the sources of [recharts](https://github.com/recharts/recharts), React components: commit `a4a1f99`, 294 files (112 of them `.tsx`) and 51,054 lines. What the sources import is installed with `npm install --ignore-scripts`: its dependencies, React and the type packages, at the versions of its lock file, without its development tools. TypeScript 6 and 7 both compile it without errors.

- **Findings:** ESLint gives 3,898 messages, 3,884 of them from 32 typescript-eslint rules and 14 of its own (ten unused directives and four that name a rule of a plugin that is not there). veslint gives the same 3,898: 3,891 are identical and 7 are the same finding with a type printed in another order. With `stableTypeOrdering` the 3,898 are identical.
- **What it found:** four findings of `prefer-readonly-parameter-types` that ESLint does not give, now fixed. A conditional type asked through an alias that only names another one (`type DataKey<P, V> = TypedDataKey<P, V>`) takes the alias `DataKey` when that alias is imported from another file, and the alias of the declaration when it is used in its own file. veslint looked for the declaration only in the body of the alias the type has; now it follows the alias that body names (`conditional/imported.ts` in the fixtures of the rule).
- **Nodes not analyzed:** twelve, in two files, all of them the empty array literals tsgo 7.0.2 panics on. No finding is lost to them.
- **Time,** on one core: 9.4 s in veslint and 19.0 s in ESLint, one run each (zod took 6.0 s and 12.2 s at the same moment). veslint makes 69,979 requests to tsgo.

**The TypeScript compiler.** `tests/eval_project.sh typescript` takes the sources of TypeScript 6.0.3 itself (commit `050880c`): 602 files and 381,174 lines, with files of tens of thousands of lines. It is there for scale. Only the sources are taken from the tarball; the type packages they import are installed without scripts, and the table of diagnostics that the build of the repository generates is written from its JSON. TypeScript 6 and 7 both compile it without errors.

- **Findings:** ESLint gives 56,006 messages, 55,733 of them from 50 typescript-eslint rules. veslint gives the same 56,006: 55,839 are identical and 167 are the same finding with a type printed in another order (in some runs on a busy machine, three of those texts came out identical: 55,842 and 164; which of the two tools printed them differently was not determined). None is missing and none is extra.
- **Time and memory,** one run on one core: 58 s in veslint, with 1.3 GB in veslint and 1.4 GB in tsgo at their peaks; 70 s and 4.2 GB in ESLint. veslint makes about half a million requests to tsgo (544,000 when it was counted), and waiting for them is half of its time: at this size it is 1.2 times faster, against 2 times on the smaller projects (zod: 7.2 s and 14.2 s, with 0.2 GB in veslint, 0.5 GB in tsgo and 1.0 GB in ESLint).
- **What it found,** all fixed:
  - veslint stopped, on the whole run, when tsgo panicked resolving the signature of a node that is not a call. Two nodes did it: the type `import("…")`, which the grammar reads as a call, and `!!forEach<A | B, boolean>(…)`, which the grammar read as `(!!forEach)<…>(…)`;
  - the grammar gaps of the last round of "Grammar": the callee of a call with type arguments, the names of tuple members, and the others the larger corpus showed;
  - 775 false findings of `no-unsafe-member-access`: in a qualified name with four parts or more (`ts.server.protocol.Message`) the grammar has a `member_expression` node for the first two, which is not a member access. Four rules that look for member accesses skip the names now (`type_name_kinds`).
- **Nodes not analyzed:** three, the empty array literals tsgo 7.0.2 panics on.

**With the configuration of the project itself.** The runs above give both tools the same rules with their default options. Two projects were also linted with their own `eslint.config`, which veslint asks the project's ESLint to resolve:

- **recharts** (ESLint 9.39.4, typescript-eslint 8.69.0 and its other plugins, installed without scripts): the configuration has 257 active rules and none of the 61, since it does not lint with types, and veslint says so. It showed a bug, fixed: the configuration enables `prefer-destructuring` and `consistent-return` of ESLint core, and veslint took them for its own rules of the same name (see "Configuration").
- **TypeScript** (its `eslint.config.mjs` and its nine local rules, with ESLint 10.6.0, typescript-eslint 8.62.0 and TypeScript 6.0.3): 149 active rules, two of them of the 61, `naming-convention` with the nine selectors of the repository and `no-unnecessary-type-assertion`. ESLint gives 118 messages and veslint the same 118. It takes 10 s, with 0.4 GB in veslint and 0.8 GB in tsgo, against 36 s and 3.9 GB.

## Tests

- **`offsets/offsets_test.v`:**
  - the offset table of §5;
  - cases with emoji, BOM, CRLF and U+2028;
  - the line table with every line break, and the position without a place.
- **`offsets/decode_test.v`:** 24,379 byte sequences, with the text Node decodes from each (`tests/utf8_decode_cases.json`).
- **`main_test.v`:**
  - escaped symbol names (`___x`);
  - with a real tsgo: sending bytes instead of UTF-16 trips the name check at `x`;
  - the escaping of `--rule` messages (line breaks, tabs and backslashes);
  - the `rules` section of `--config`: full ids, names without a plugin that are not veslint's rules, severities and options equivalent or not to the defaults, and 37 rule values with ESLint's error for each.
- **`tsgo/framing_test.v`:** real `initialize` bytes, `bin8`/`bin16`/`bin32`, fixint message type, split and concatenated messages, and malformed input.
- **`tsgo/client_test.v`:**
  - `null` inside arrays of responses;
  - a tsgo that ignores stdin being closed is killed and reaped without leaving a zombie;
  - a version check that never answers, or answers and never exits, is killed and reaped.
- **`tsgo/platform_test.v`:** the package of the compiler for 21 hosts, and that the list is the one of the installed `typescript` package.
- **`tsgo/overlay_test.v`:** with a real tsgo, a file served through the `readFile` callback is the text tsgo types.
- **`tsgo/ast_test.v`:**
  - with a real tsgo, the binary AST of `tests/fixtures/emoji.ts`: the path, UTF-16 ranges with emoji before them and that `getTypeAtLocations` accepts the handles;
  - malformed binaries, with another format version or with the file path out of range give a protocol error, not a panic;
  - the navigation of the AST (`ast_tree.v`) gives the same children, in the same properties, as walking it with TypeScript's own client, plus JSDoc nodes with their text and the keyword of a heritage clause.
- **`tsgo/api_test.v`:** with a real tsgo, the API requests the rules use beyond types: symbols and signatures of declarations, type details (alias type arguments, readonly index signatures), the `exactOptionalPropertyTypes` option, the `lib` and `target` of a project and the libs typescript-eslint takes from them, a tsconfig parsed without a snapshot (`parseConfigFile`, the same as the project of a snapshot), alias chains and shorthand property symbols, including what tsgo answers `null` to.
- **`treesitter/treesitter_test.v`:** the token-end index leaves out trailing comments, the `#!` and automatic `;`; the node index gives what the tree walks give, for every pair of kinds with every skipped kind.
- **`treesitter/dialect_test.v`:** the dialect of each extension, and which extensions are JavaScript.
- **`treesitter/grammar_test.v`:** the shape of the tree for what the patch of the grammar fixes last: unions with a leading `|`, instantiation expressions and where type arguments end, type queries of import types, destructuring targets with assertions, and the automatic semicolon at a comment with a line break and at every line terminator.
- **`rules/literals_test.v`:** `String(value)` of numeric literals (bases, separators, exponents, BigInt, the ties-to-even of `9007199254740993`) and the value of strings with escapes, compared with what Node gives.
- **`rules/scope_test.v`:** the scopes, variables, definitions and references of sample code, as ESLint's scope manager gives them; the globals of each `ecmaVersion`, the ones a set of libs declares and the names of a `/* global */` comment.
- **`rules/scope_oracle_test.v`:** the 45 programs of `tests/scope/` against typescript-eslint's scope manager (see "How it is validated").
- **`rules/static_value_test.v`:** the 19,188 expressions of `tests/static_value_cases.json`, with what eslint-utils itself answers for each (a value, not static, or a value that depends on the time zone or the locale): a value that differs is never accepted, an evaluation that does not end fails, and each documented limit must still have an expression veslint does not evaluate. Also that the functions veslint takes as callable are eslint-utils' own lists, and the static names of members and properties.
- **`rules/static_value_math_test.v`:** `Math.abs` of the zeros, the constants of `Math` and `**`/`Math.pow` (the exponents 2 and 0.5 and the special cases), as the bits of the doubles Node gives.
- **`rules/regexp_syntax_test.v`:** 276 patterns: whether V8 accepts each one, and the structure regexpp gives the valid ones.
- **`rules/regexp_match_test.v`:** 5,522 pattern and text pairs, 2,400 of them from 600 patterns made at random out of the atoms that case and Unicode properties affect: whether V8 accepts the pattern in `u` mode, and whether it matches. Only the pairs that V8 answers the same with and without its optimizations are kept.
- **`rules/unicode_case_test.v`:** 660 strings: what `toUpperCase` and `toLowerCase` give in V8, with the final sigma, the letters that become several and the halves of surrogate pairs.
- **`rules/js_math_test.v`:** the bits of what V8's transcendental `Math` functions, `atan2` and `hypot` give for 1,586 chosen arguments (the special values and the thresholds of each function) and, as digests, for 6.4 million arguments of eight kinds built from a seed (any double, the ranges each function reduces to, next to multiples of pi/2, next to 1) (`tools/gen_math_cases.mjs`).
- **`rules/unicode_normalization_test.v`:** what `normalize` gives in V8 in its four forms for every code point alone (the lone surrogates too), for each of the 961 compositions with marks that block it or not between its two code points, for 20,000 random strings of code points that interact and for 71 chosen strings; all but the chosen ones as digests of V8's results (`tools/gen_unicode_normalization.mjs`, which also checks its own copy of the algorithm against V8 on all of them).
- **`rules/json_errors_test.v`:** 79 texts, with the message of V8's `JSON.parse` for each.
- **`rules/json_schema_test.v`:** 10,037 option lists (7,580 of the 120 rules and 2,457 of 25 other schemas), each as a configuration and as a comment, with the text ESLint's validator gives.
- **`rules/directives_test.v`:** 102 odd texts of a configuration comment, with what ESLint's own parser (levn) reads.
- **`rules/regexp_annex_b_test.v`:** 620 package names (125 that V8 rejects) on 85 texts: V8's 42,072 answers.
- **`rules/fix_tokens_test.v`:** 788 nodes of sample code and ten functions (the tokens before and after, `isParenthesized`, the text with parentheses, `needsPrecedingSemicolon`…), with what the originals give inside ESLint.
- **`rules/fix_precedence_test.v`** and **`rules/requires_quoting_test.v`:** the operator precedences of typescript-eslint and its `requiresQuoting`.
- **`tests/run.sh`:**
  - exact output of `app.ts` (also with `--all-identifiers` and `--per-identifier`) and of the fixtures of `tests/fixtures/` (`line_breaks.ts` also with `--all-identifiers`);
  - a symlinked file;
  - the errors veslint must survive (tsgo missing, dying, hanging or answering wrong), using a fake tsgo (`tests/fake_tsgo.sh`) and the real tsgo, and a `--version` that never answers or never exits;
  - a request over 64 KiB to a tsgo that does not read;
  - a tsgo that floods messages;
  - killing tsgo in the middle of a run;
  - each rule on its `tests/rules/<rule id>/**/cases.ts` and `cases.tsx`, with the exact output of `expected.txt`, and with `--fixes` that of `fixes.txt`;
  - directive comments (`tests/directives/`), `--fix` on a copy (`tests/fix/`), and `--config` with a resolved ESLint configuration and, when `bun` and the ESLint of `build/eval` exist, with `eslint.config.mjs` itself and `--print-config` (`tests/config/`); a configuration ESLint does not take, with the text the `eslint` command prints (`tests/config-errors/`), and a JSON as written or as `eslint --print-config` prints it;
  - `--config` with every rule, shaped like `eslint --print-config`: the same findings as each separate `--rule` and the warning about ignored rules; a rule set to `"warn"` exits with code 0; the unprefixed names ESLint core also has are not taken as veslint's rules;
  - rules without types (`tests/lazy-snapshot/`): the output of a run with a snapshot, also when a comment turns on a rule that needs types or an `await` is a name, and no snapshot when nothing needs one;
  - the `--rule` warnings (syntax errors, and unanalyzed nodes with a chain of 1,002 member accesses), and the usage errors: `--server` with files, a JavaScript file (`.jsx`, `.js`, `.mjs`, `.cjs`), a repeated `--rule` or one combined with `--all-identifiers` or `--config`, and in `--config` unsupported, unknown or ill-typed options, a configuration without veslint rules or broken JSON.
  - `--server`: the scenario of `tests/server` (unsaved text, a file closed without saving, files changed on disk and told or not, a reset, errors, a line that is not JSON, and a declaration in another file whose syntax tree the server keeps between snapshots and must read again when it changes) answers what `tests/server/expected.jsonl` has, and on the configuration fixture the answer is byte for byte what the command line prints; `tests/server_client.py` drives the server. `tests/server_pipeline.py` sends requests together: they are answered in order, the requests for a file a later request lints too may be given up (and at least one is), and the others are answered as each alone.
  - typescript-eslint's own tests of the ported rules, and ESLint's own tests of its core rules (`tests/upstream_check.py`), when the packages `tests/upstream/setup.sh` links exist; without them the line says they were skipped.
- **`tests/rules/reference.sh`** (outside `make test`): compares the `expected.txt` files with typescript-eslint, and runs typescript-eslint's own tests in ESLint and in veslint (see "How it is validated").
- **`tests/rules/cross.sh`** (outside `make test`): every rule on every fixture, compared with typescript-eslint; the differences must be those of `tests/rules/cross.known.txt` (see "How it is validated").
- **`tests/rules/code_path_diff.sh`** (outside `make test`): veslint's code path analysis against ESLint's on 55,785 generated functions (see "How it is validated").

The expected results of the type mode were checked against an independent oracle: positions were computed with the TypeScript 6 parser and types with the official TypeScript 7 JS client. All 8 files matched. The script for that check was throwaway and is not part of the repository.

## Benchmark

`make bench`: 200 files, 61,373 identifiers with `--all-identifiers`. First of two runs, from 2026-10-02, on the development machine.

| Phase | One batch per file | One request per identifier |
|---|---|---|
| Read and parse (tree-sitter) | 137 ms | 137 ms |
| Collect identifiers | 24 ms | 27 ms |
| Convert offsets | 6 ms | 6 ms |
| Start tsgo, check the version, `initialize` | 5 ms | 6 ms |
| `updateSnapshot` | 24 ms | 24 ms |
| Symbols + types | 932 ms (400 requests) | 2900 ms (122,746 requests, ~23.6 µs each) |
| Type text (91% cache hits) | 248 ms | 220 ms |
| **Total** | **1.39 s** | **3.34 s** |

In the second run the totals were 1.41 s and 3.27 s. `--bench` also includes the time of each batch (`symbol_batches_ms` and `type_batches_ms`).

On the minipc (an i3-4150T from 2014, one core, TypeScript 7.1.0-beta, 2026-11-11), the totals are 5.18 s and 14.20 s (5.20 s and 14.06 s in the second run): read and parse 319 ms, collect identifiers 65 ms, offsets 12 ms, start tsgo 11 ms, the snapshot 197 ms, symbols and types 3,588 ms in 400 requests and 12,681 ms in 122,746 (about 103 µs each), type text 946 ms and 866 ms (95% cache hits). Both the machine and the TypeScript version differ from the table, so the two are not comparable: these are the baseline of the minipc.

It is a synthetic project; the numbers do not replace a measurement on a real repository.

## Known limits

- **The protocol is unstable** (`typescript/unstable/*`) and has no version. Any TypeScript update requires running `make test` again.
- **The tree-sitter grammar is from November 2024,** with its own patch (see "Grammar"). The newest syntax may produce `ERROR` nodes.
- **There are two different parsers** (tree-sitter and TypeScript) that may disagree. In type mode the name check catches it on the queried identifiers; with rules, the unanalyzed-nodes warning.
- **There is a single tsgo process and it is serial.**
- **A file that is not valid UTF-8** is linted as ESLint lints it: the text Node decodes, with U+FFFD for each ill-formed sequence. tsgo is given that text through its `readFile` callback. A file that starts with U+FFFD is a parse error for ESLint (`File appears to be binary`) and a syntax warning here, like any other syntax error.
- **Only TypeScript files are analyzed** (`.ts`, `.mts`, `.cts`, `.tsx`). A JavaScript file is rejected, also in a project with `allowJs`, where typescript-eslint would lint it.
- **Only Linux x86-64 and Windows x64 are tested** (Windows: see "Windows").
- **A path with `\` in a directory or file name is not supported, because TypeScript does not support it:** TypeScript 6 and 7 turn every `\` into `/`, so `tsc -p` answers `TS5058: The specified path does not exist`, the API opens no project, and ESLint with typescript-eslint gives a parsing error for the file. V's `os.join_path` does the same on Unix.
