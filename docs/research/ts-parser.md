# TypeScript's parser instead of tree-sitter: measurements (batch PMEASURE)

veslint parses every file with tree-sitter (patched grammar) and builds its flat preorder tree
(`treesitter/flat_tree.h`) from it; in typed runs TypeScript 7.1's Go parser parses the same files
again for the program, and V then receives their AST (`getSourceFile`) to name nodes for the
checker. This report measures what building veslint's tree from TypeScript's parser would give.
Nothing in veslint was changed; the programs used live outside the repository, in the batch's
workspace (`veslint-ws/agents/pmeasure`: `goprog/` the Go program, `tsharness/` the C harness,
`gostart/`, `q1`…`q5/` scripts and raw results).

**Machine and load.** i3-4150T (2 cores / 4 threads), 11 GB, main = 94d36b2b (v0.43.0). Another
agent was building and testing veslint during the whole batch: the load average was 1.8–4.0
(mostly 2.4–3.1). Parser timings are pinned to one CPU (`taskset -c 3`, GOMAXPROCS=1), 7 runs per
measurement, 4 rounds; the figures are the minimum over runs and rounds (medians in the raw files
are 5–25 % higher). veslint's phases (`--bench`, `VESLINT_CPUS=1`) were taken under that load, so
their totals are higher than the brief's (the TypeScript compiler with no-floating-promises: 9.2 s
here, 6.4 s in the brief); the ratios between phases are what to read.

**The files.** Those of `tests/bench/run.sh`: zod 125 files (1.35 MB), recharts 294 (1.74 MB, .ts
and .tsx), the TypeScript compiler 602 (18.1 MB).

## 1. TypeScript's Go parser alone against tree-sitter

`goprog/pmeasure` is built against `build/upstream/typescript-go/tsc` (7.1.0-beta, the commit
veslint links) as `tsgo/inproc/build.sh` builds its archive: a module under the checkout's path
with `replace`, so it may import `internal/parser`; nothing is written into the checkout. It calls
`parser.ParseSourceFile` on each file as the program does (JSDoc included), then, optionally,
`binder.BindSourceFile`. `tsharness/tsparse` links the same `libtree-sitter.a` (-O3 -flto) and
`build/libtree-sitter-typescript.a` that veslint links, and calls `ts_parser_parse_string` (BOM
stripped, tsx grammar for .tsx). Files are read before timing.

| ms, one CPU | zod | recharts | TS compiler |
|---|---|---|---|
| tree-sitter parse | 223 | 227 | 2 665 |
| tree-sitter free (`ts_tree_delete`) | 13 | 10 | 196 |
| TypeScript parse (scanner + parser) | 48–52 | 54–59 | 395–461 |
| TypeScript binder (not needed by the conversion) | 23–26 | 28–29 | 170–214 |
| ratio of the parses | 4.3–4.6× | 3.8–4.2× | 5.8–6.7× |

Memory: tree-sitter keeps one tree at a time (the harness's maximum RSS is 9 / 8 / 76 MiB, with
all the texts loaded). TypeScript's parser allocates 14 / 15 / 125 MiB per pass over a project
(about 7 bytes per byte of source); with each file's AST dropped after it, the Go heap in use peaked
at 7–10 / 6–8 / 60 MiB. In a typed run the program keeps every AST anyway, so a TypeScript-based
tree adds no AST memory there.

The binder is not needed: veslint's scope analysis (`rules/scope.v`) and its rules do not use
TypeScript's symbols for syntax, and in typed runs the checker binds by itself.

## 2. From TypeScript's AST to veslint's flat tree

The prototype (`goprog/src/main.go`, `converter`) walks the AST with `NodeVisitor` hooks
(`VisitEachChild`, so each child has its slot, the field a port would map) and writes rows of the
shape of `vt_flat_node`: kind, field, flags (named, extra), start and end in bytes, parent, next
sibling, last node of the subtree, plus the table of the first node that starts at each byte. What
the AST has no node for is rescanned with TypeScript's scanner (trivia kept) from the gaps between
children: punctuation and keywords become anonymous rows and comments become extra rows, as
typescript-estree's `convertTokens`/`getChildren` do. Each `NodeList` becomes a row (tree-sitter's
`arguments`, `formal_parameters`, `type_arguments`… wrap lists in a node). Identifiers get a
contextual kind from their parent (property and type identifiers). Positions are bytes: the Go AST
is byte-based, so no UTF-16 conversion happens in-process.

| | zod | recharts | TS compiler |
|---|---|---|---|
| conversion, ms one CPU | 32–34 | 35–38 | 349–354 |
| tree-sitter cursor walk alone (the floor of `vt_flat_build`) | 28 | 28 | 322 |
| rows of the prototype / nodes of tree-sitter's tree | 359 802 / 385 095 | 347 470 / 349 918 | 3 230 375 / 3 263 076 |
| comments (prototype = tree-sitter extras) | 3 624 | 2 428 | 36 659 |
| tokens rescanned from the gaps | 132 118 | 127 265 | 1 204 668 |
| files out of preorder | 0 | 1 | 0 |

So the conversion costs about what walking tree-sitter's tree with a cursor costs. It gives the
same number of rows within 1–7 % and exactly the same comments. What it leaves out, which a real
port must add (estimate +20–50 % on the conversion):

- tree-sitter's real symbols and field ids (here TypeScript's numbers; a table);
- the nodes tree-sitter has in another shape: `export_statement` and `ambient_declaration` around
  declarations, `type_annotation` around `: T`, `class_heritage`, `string_fragment` and
  `escape_sequence` inside strings, template pieces, `else_clause`…;
- tree-sitter's token granularity where it differs;
- its exact placement of comments (an extra goes where tree-sitter's parser was);
- `has_error` and `is_missing`;
- the per-kind node index of `node_index.v` and the token ends, which V builds after the walk today;
- writing into C memory (the prototype fills Go slices).

One .tsx file still emits an empty attribute list out of preorder (a detail of the prototype).

## 3. What a typed and an untyped run would save

veslint today, `--bench`, `VESLINT_CPUS=1`, under load (fastest of 2 runs; ms; sums of the
workers'):

| project / set | total | tree-sitter parse | index (flat tree + kind index + token ends) | free | getSourceFile (calls) | createSnapshot | max RSS |
|---|---|---|---|---|---|---|---|
| zod syntactic | 735 | 243 | 64 | 17 | — | — | 107 MiB |
| zod floating | 848 | 241 | 64 | 19 | 37 (27) | 151 | 192 MiB |
| zod typed | 3 314 | 269 | 74 | 20 | 123 (92) | 155 | 433 MiB |
| recharts syntactic | 1 154 | 356 | 97 | 26 | — | — | 71 MiB |
| recharts floating | 1 446 | 321 | 97 | 20 | 100 (61) | 451 | 240 MiB |
| recharts typed | 9 686 | 375 | 106 | 26 | 301 (122) | 583 | 757 MiB |
| TS syntactic | 10 024 | 3 691 | 866 | 265 | — | — | 326 MiB |
| TS floating | 9 221 | 3 176 | 798 | 275 | 491 (1 082) | 1 448 | 792 MiB |
| TS typed | 30 395 | 3 533 | 885 | 275 | 558 (783) | 1 458 | 1 565 MiB |

`rule_unmatched` (nodes tree-sitter and TypeScript read differently) was 0 in all nine.

`perf record` of the TS floating run (1 CPU, 10 246 samples, self time by function):

| Self time in | Share |
|---|---|
| tree-sitter's parse and release | 33.2 % |
| Go runtime (GC, maps) | 17.1 % |
| flat tree + node index (`ts_tree_cursor_*`, `ts_node_*`, `treesitter__*`) | 8.9 % |
| kernel | 8.7 % |
| checker | 7.9 % |
| TypeScript's parser + scanner (inside createSnapshot) | 4.3 % |
| the getSourceFile encoder (Go) | 2.3 % |
| binder | 2.2 % |
| V's `tsgo` module (decoding the AST, handles) | 1.1 % |
| `offsets` (UTF-16) | 0.6 % |

The snapshot is made before the workers parse (`lint_workers.v`), so nothing overlaps tree-sitter's
parse today. With N workers the wall-clock gain is roughly the CPU gain divided by N.

**Typed run** (the program has already parsed every linted file):

- Goes away: tree-sitter's parse and free; the cursor walk of the flat tree; getSourceFile (the
  encode in Go, the transfer, the decode in V); the range matching of tree-sitter nodes to
  TypeScript nodes. A row can carry its TypeScript node, so the handle is known and no `first` or
  range index is needed.
- Is added: the conversion (the prototype × 1.0–1.5).
- Stays: the kind index and the token ends, unless the converter builds them too.

**Untyped run**: the same savings minus getSourceFile, plus TypeScript's parse of each file. The Go
runtime is already in every veslint process, because the archive is linked, and even an untyped run
starts the in-process session to read the tsconfigs. `gostart/` measures 3.3 ms and 7 MiB to load
the archive, and 9.2 ms and 15 MiB to the first call into it, against 0.6 ms and 1.4 MiB for a plain
C program. So the runtime adds nothing new. One cgo call per file (text in, row buffer out) is
negligible. Memory: up to ~60 MiB more Go heap on the TS compiler (transient ASTs under the default
GOGC).

**Editor** (`q3/edit.py`: `veslint --server` on the benchmark's file, a comment appended at the end
ten times, as `tests/bench/server.py` does; the server's profile fields):

| file | first open: parse + index | each edit: parse + index | TypeScript parse + conversion of the file |
|---|---|---|---|
| zod schemas.ts (177 kB) | 33 + 10 | 0.0 + 8 | 4.6 + 4.1 |
| recharts axisSelectors.ts (79 kB) | 13 + 4 | 0.0 + 3 | 1.8 + 1.5 |
| TS parser.ts (540 kB) | 77 + 35 | 0.1 + 16 | 8.6 + 8.9 |

tree-sitter's incremental reparse makes an edit's parse free (this edit, at the end of the file, is
its best case), and the index is rebuilt. TypeScript 7.1's Go parser has no incremental parsing
(`internal/parser/parser.go`: "!!! incremental parsing"), so an untyped edit would cost a full parse
plus the conversion. That is about the same as today's index (17 vs 16 ms on parser.ts), and better
on the first open (17 vs 112 ms). In a typed editor session the new snapshot parses the edited file
anyway, so only the conversion is added, and the index and getSourceFile go.

## 4. How much of veslint depends on tree-sitter's shape

Counts by file (`q4/scan.py`: string literals that are tree-sitter kind, token or field names, on
lines that look at kinds, fields or children). The counts are approximate in both directions:
`'object'`, `'string'`, `'type'` and `'undefined'` are also `typeof` strings or type names, and a
helper that receives kinds as parameters is counted where the literal is.

| group | files | use tree-sitter's API | use ESTree (estree/) | read kinds | read tokens | read fields | read `comment` | read errors |
|---|---|---|---|---|---|---|---|---|
| rules: typescript-eslint, eslint core and others | 330 | 300 | 34 | 271 | 217 | 209 | 78 | 3 |
| rules: vue | 232 | 215 | 88 | 27 | 75 | 5 | 0 | 1 |
| rules: unicorn | 107 | 106 | 83 | 25 | 68 | 0 | 0 | 1 |
| rules: svelte | 101 | 88 | 26 | 25 | 36 | 5 | 2 | 1 |
| rules: stylistic | 58 | 56 | 48 | 6 | 43 | 0 | 0 | 0 |
| rules: regexp | 29 | 27 | 10 | 2 | 7 | 0 | 0 | 0 |
| rules: perfectionist | 22 | 17 | 9 | 8 | 5 | 0 | 0 | 0 |
| rules: promise | 19 | 18 | 9 | 4 | 7 | 1 | 0 | 0 |
| rules: seyfert / marcrock | 19 | 19 | 2 | 15 | 6 | 8 | 2 | 0 |
| estree/ (the ESTree converter, 6 027 lines) | 13 | 7 | — | 7 | 6 | 6 | 0 | 1 |
| vue/, svelte/, svelte_compiler/ | 56 | 9 | 14 | 25 | 32 | 1 | 2 | 5 |

In all, the sources read 191 distinct tree-sitter kinds, 128 anonymous tokens (`function`, `const`,
`,`, `(`, `never`, `;`, `=`…) and 41 fields. By how TypeScript has them (`q4/classify.py`):

| Category | Kinds | File references | Examples |
|---|---|---|---|
| direct: one TypeScript kind | 73 | 1 524 | `arrow_function`, `binary_expression`, `new_expression`, `subscript_expression` |
| context: TypeScript has one kind where tree-sitter has several, or the reverse | 40 | 1 446 | the identifier family, `call_expression` vs `new`, function forms, `class` vs `class_declaration`, `member_expression`, `lexical_declaration`/`variable_declaration`, `augmented_assignment_expression`, `required_parameter`/`optional_parameter` |
| wrapper: a node around a list, clause or keyword; TypeScript has a NodeList or nothing | 36 | 452 | `arguments`, `statement_block`, `class_body`, `type_arguments`, `type_annotation`, `accessibility_modifier` |
| structure: nested differently | 37 | 740 | `string` with its fragments, `comment`, `template_string`, `regex`, `export_statement` and `ambient_declaration` around declarations (TypeScript has modifiers), `parenthesized_expression` also around the condition of `if`/`while`, patterns that are expressions in TypeScript |

veslint calls tree-sitter's C API directly in only 23 files, with 47 functions: `ts_node_*`,
`ts_tree_cursor_*`, `ts_parser_*`, and 7 `ts_query_*`/`ts_language_*` for the declarations query.
The rules go through `treesitter/` (`node_kind`, `node_field`, `children`, `named_children`,
`nodes_of_kind`…). Other places hold tree-sitter's shape:

- `estree/`, the ESTree converter built from tree-sitter's tree (309 rule files use it);
- `rules/scope.v`, the scope analysis;
- the source tokens (`rules/fix_tokens.v`, `vue/tokens.v`);
- the grammar patch: 2 007 lines, 100 commented changes that make tree-sitter read code as
  TypeScript does;
- `treesitter/incremental.h`, the editor's incremental reparse, checked against a fresh parse;
- Vue (script blocks masked to the file's length, template expressions parsed as snippets) and
  Svelte (`lint_code` with its own offsets);
- the positions: bytes everywhere in veslint, UTF-16 only for tsgo's API. The in-process Go AST is
  in bytes too.

Classification of the work, if the tree changed source:

- **Mechanical**:
  - a C shim implementing those 47 functions over the flat buffer, so that `C.TSNode` stays the
    type of 840 files;
  - the declarations query as a walk;
  - byte positions, unchanged;
  - the typed path taking TypeScript node handles from the rows instead of getSourceFile.
- **Per kind, in one converter** (the way to keep the rules as they are): emulate tree-sitter's
  tree from TypeScript's AST: the 40 context kinds, the 36 wrappers, the 37 structural kinds, the
  token granularity and the fields. Test it against tree-sitter's own tree on the 62 601 files of
  the ESTree corpus (identical wherever tree-sitter is right). Example: `export default class {}`
  is one ClassDeclaration with two modifier tokens in TypeScript, and `export_statement(class)` with
  the field `declaration` in tree-sitter.
- **Hard**:
  - comment placement: tree-sitter's extras sit in the node its parser was in, and rules that walk
    `children` see that (82 files read `comment`);
  - ERROR and MISSING nodes: TypeScript recovers differently, and some rules and the "results may
    be partial" path read them;
  - Vue template snippets and Svelte's offsets (one parse per snippet through cgo);
  - the editor without incremental parsing;
  - the places where the rules were adjusted to the patched grammar's choices: the known
    differences below would change behavior (for the better), and their tests with them.
- **Not recommended**: rules reading TypeScript's shape directly (rewriting ~840 files, and
  `estree/` as a port of typescript-estree's converter). It is more faithful in the end, but
  several times the work.

## 5. Exactness: where the two parsers disagree, and which matches typescript-eslint

typescript-eslint 8.72.2 (veslint's oracle) parses with TypeScript **6.0.3**'s JavaScript parser;
veslint's TypeScript is 7.1.0-beta's Go port. Three comparisons follow.

**60 tricky constructs** (`q5/cases/`), taken from the grammar patch's comments,
tests/estree/known.txt and the upstream cases:

- ASI after `let`, `type`, `async`, `return` and `yield`;
- `a < b > (c)`, instantiation expressions, arrow functions in conditionals, `<T,>` in .tsx,
  `<T>x!`;
- decorators before and after `export`, JSX with type arguments and namespaces;
- regex vs division after `)` and `}`;
- `export import`, `import x = require`, `accessor`, `get`/`set` as names, `satisfies`, enums,
  `declare global` / `declare module`, overloads;
- `a?.b!`, `using`, abstract constructor types, template literal types, variance and `const` type
  parameters, `#x in o`, import attributes;
- `new new C()()`, `new X!.y()`, a leading `|` in unions, `typeof import()`, named tuple members;
- `\r` and U+2028 line terminators, HTML comments, mapped types, unicode escapes, BigInt…

Results:

- TypeScript 7.1 (Go) vs 6.0.3: **59 of 60** identical (same parse diagnostics, same tree of kinds).
  The exception is `x < 0 as any ** 2`, which 7.1 rejects and 6.0.3 parses.
- veslint's tree-sitter → ESTree vs typescript-estree (`tests/estree/oracle.mjs dump`): **55 of
  60** identical. The other 5:
  - `yield` in a template outside a generator, and `new new C()(⏎)`: two entries of
    tests/estree/known.txt;
  - `async⏎(x) => x` and `x = 1 <!-- y`: typescript-estree throws a parsing error but tree-sitter
    parses them, so veslint lints them without ESLint's "Parsing error";
  - `await:` as a label with `async⏎function`: tree-sitter has an error, TypeScript none.

**The whole ESTree corpus**: 62 601 files (rule fixtures, upstream cases, the projects of
build/eval), read only from `build/estree-oracle/corpus`.

- TypeScript 7.1 vs 6.0.3 (`q5/ts6dump.mjs` vs `pmeasure -sexp`): **62 589 identical, 12 differ**.
  This is after normalizing five changes of representation in 7.1 that do not change how code is
  read: interface `extends` and `implements` as TypeReference, binding-pattern holes as empty
  BindingElements, `A.B` there as QualifiedName, the implicit `export` of the inner module of
  `namespace A.B`, and a `Token` suffix on some kind names. All 12 differ because 7.1 adds parse
  errors: 7 files with `import … assert { … }` (error 2880, "Use 'with' instead of 'assert'") and
  5 with `as` before `**` (error 1005).
- tree-sitter → ESTree vs typescript-estree (`estree_dump hash` vs `oracle.mjs hash`):

| Result | Files |
|---|---|
| identical | 61 906 |
| both fail | 446 |
| different trees (the six of known.txt) | 6 |
| only typescript-estree rejects | 205 |
| only tree-sitter rejects (veslint then lints with a warning) | 38 |

Of the 205 that only typescript-estree rejects, 203 have TypeScript parse diagnostics that
tree-sitter accepts, mostly legacy octal literals or escapes and JSON fragments of the upstream
cases. veslint reports no "Parsing error" for them, typed or not.

So veslint is already almost exact on syntax through tree-sitter: 6 different trees out of 62 601,
plus the files ESLint rejects as unparsable. A TypeScript-parser route would:

- get the parse errors exactly, because ESLint's fatal problems come from the same diagnostics, and
  fix the six different trees;
- but bring a newer parser than the oracle's: in 12 files 7.1 rejects what 6.0.3 accepts (they
  would need those diagnostics ignored and, for `as … **`, a different tree), and the converter
  would have to absorb the representation changes.

Whether the converted tree equals tree-sitter's in every other respect (comment placement,
wrappers, tokens) is the converter's to prove, against the same corpus.

## 6. Estimate

Gain in CPU time on one CPU, from the measurements above: tree-sitter's parse and free, plus the
cursor-walk part of the index, plus getSourceFile and its decoding in the typed sets; minus
TypeScript's parse in the untyped sets and the conversion at 1.0–1.5× the prototype. The totals
were measured under load, so the shares are more reliable than the milliseconds.

| set | zod | recharts | TS compiler | confidence |
|---|---|---|---|---|
| syntactic (CLI) | −185…210 ms of 735 (25–28 %) | −295…320 ms of 1 154 (25–28 %) | −3.3…3.5 s of 10.0 (33–35 %) | medium: the parse ratio is measured; the converter's fidelity cost is guessed |
| floating (CLI) | −275…290 ms of 848 (32–34 %) | −415…435 ms of 1 446 (29–30 %) | −3.9…4.1 s of 9.2 (42–45 %) | medium |
| typed (CLI) | −390…410 ms of 3 314 (12 %) | −680…700 ms of 9 686 (7 %) | −4.4…4.5 s of 30.4 (14–15 %) | medium: the rules and the types dominate |
| editor, untyped | first open −90 ms on parser.ts; edits about the same (±2 ms) | | | medium |
| editor, typed | edits −10…20 ms (the index and getSourceFile go, the conversion is added) | | | low-medium |

On several CPUs, the wall clock gains about these shares of the lint phase, divided among the
workers (nothing overlaps it today). Against oxlint (syntactic zod 0.46 / 0.09 s in the README
benchmark) this closes about a quarter to a third of the gap, not all of it: the rules are the
other half of veslint's time.

Work, in batches like the recent ones (one agent, a few hours of building and verifying each):

| Step | Batches |
|---|---|
| 1. A Go converter that emulates tree-sitter's flat tree (kinds, fields, wrappers, tokens, comment placement, error flags), plus a differential test against tree-sitter's tree on the corpus. Low confidence: the long tail of the 140 kinds and of the extras placement. | 4–6 |
| 2. A C shim of the 47 functions over the buffer, the declarations query as a walk, the kind index and token ends built in the converter. | 1 |
| 3. Typed path: node handles from the rows, no getSourceFile or range matching. To coordinate with AST2's work on that path. | 1 |
| 4. Parse errors from TypeScript's diagnostics, with the 7.1-vs-6.0.3 exceptions; the users of ERROR/MISSING; the "results may be partial" path. | 1 |
| 5. Vue (masked script, template snippets) and Svelte (lint code, offsets) through the new parse. | 1–2 |
| 6. Editor: a full parse per edit (no incremental), checking the server's caches. | ½–1 |
| 7. Rules and tests adjusted where tree-sitter's choices were relied on; a full battery pass. | 1–2 |

Total **9–13 batches**, with low-medium confidence; the risk is in step 1.

## Risks and what speaks against it

- The oracle is TypeScript 6.0.3 and the parser would be 7.1.0-beta's. The 12 corpus files and the
  representation changes already differ, and each TypeScript upgrade can change the AST: it is an
  internal package of a beta (veslint already pins and patches it for the API session).
- The tree-sitter route is already exact on 61 906 of 62 601 files, and every rule is verified
  against ESLint on it. Replacing the tree re-opens the verification of ~800 rules.
- TypeScript 7.1 has no incremental parsing, so the editor loses tree-sitter's free reparse of
  small edits. That is neutral at today's file sizes. For edits in the middle of very large files it
  costs only the full parse (~9 ms for 540 kB).
- During a migration there are two trees (or forever, if only typed runs used TypeScript's), and
  every rule has to give the same results on both. A typed-only route is not recommended for that
  reason.
- More Go heap in untyped runs (tens of MiB on the TS compiler), and Go's GC in the parse path
  (17 % of the floating run's samples are already Go runtime).
- What speaks for it:
  - TypeScript's parse is 4–7× faster than tree-sitter's;
  - the typed path loses getSourceFile and the range matching (and the "nodes not analyzed"
    warnings);
  - parse errors become exactly ESLint's;
  - the grammar patch (2 007 lines) and its maintenance go;
  - the trees are TypeScript's by construction.

## What could not be measured

- The cost of the real converter (with tree-sitter's exact shape) and of the V side after it. Only
  the prototype's walk was timed, with a +20–50 % allowance.
- Timings on a quiet machine: another agent loaded the machine throughout (load 1.8–4.0), so the
  minimum of several runs and rounds is reported.
- The multi-CPU wall clock of a TypeScript-based run, and edits in the middle of a file in the
  editor (the benchmark's edit, at the end of the file, is tree-sitter's best case).
- Whether TypeScript 6.0.3 and 7.1 agree on what typescript-estree's own checks reject: only the
  parse diagnostics were compared.
