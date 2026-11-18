module svelte

import estree
import jsregexp
import treesitter

// Document is a parsed .svelte file: svelte-eslint-parser 1.10.1's result for it, as ESLint 10
// gets it with `parserOptions.parser` set to typescript-eslint's parser 8.72.2 (an object, so
// every file is TypeScript: the script, its template expressions and the virtual code). Call
// free() when done (it holds tree-sitter trees).
//
// How it is built (see .claude/svelte-parser-spec.md):
//   1. split_document (blocks.v): the template code (block contents blanked) and the script code
//      (everything but <script> contents blanked), byte for byte the length of the file;
//   2. compile_parse (compiler.v): the Svelte compiler's template AST;
//   3. Conv (convert*.v): the Svelte* nodes, the HTML tokens, and the "script lets": the code of
//      every template expression appended to the script code (the pre-virtual code, `pre`);
//   4. script_let.v: `pre` parsed once by tree-sitter (the script part is at file offsets), its
//      ESTree (Document.es) and tokens, and the template nodes put back in the Svelte AST with
//      file offsets (restore);
//   5. the tokens merged, the gaps filled (one-character tokens), the statements given to the
//      script elements.
@[heap]
pub struct Document {
pub mut:
	src      string
	index    TextIndex
	lc       LinesAndColumns
	nodes    []SNode // nodes[0] is the Program
	tokens   []Token
	comments []Token
	// es is the ESTree of `pre` (script statements and template expressions, with file offsets
	// once restored; their tree-sitter nodes keep `pre` offsets: see pre_to_file).
	es   estree.EsTree
	tree &C.TSTree = unsafe { nil }
	// extra_trees: other trees nodes of `es` come from (the `generics` attribute's parse).
	extra_trees []&C.TSTree
	// es_parent: the Svelte parent of an ESTree node grafted into the template (its ESTree
	// parent is a wrapper of `pre` that is not in the AST).
	es_parent map[int]int
	// pre: the pre-virtual code in bytes (blanks per byte: its script part is at file offsets);
	// pre_u16: the same code as svelte-eslint-parser builds it (what typescript-eslint parses).
	pre       string
	pre_u16   string
	separator int // `\n;` at [separator, separator+2) of pre (-1: no template expression)
	// lets_index: the UTF-16 index of pre after the script part (the template expressions).
	lets_index TextIndex
	// segments map the pieces of pre copied from the file (template expressions) back to it.
	segments []Segment
	// template: the code handed to the compiler.
	template string
	error    ?ParseError
	// The <script> lang (merged over the script blocks), and the generics attribute.
	lang string
	// reactive: the top-level `$:` statements of the script, whose type is
	// SvelteReactiveStatement (es_type_name).
	reactive map[int]bool
	// virtual_code: the code svelte-eslint-parser hands typescript-eslint (the one a type checker
	// must see as the .svelte file's content, see virtual.v); virtual_offsets and
	// virtual_fragments map it to pre_u16 (UTF-16 offsets, RestoreContext's tables).
	virtual_code      string
	virtual_offsets   []VOffset
	virtual_fragments []VRange
	// scope: the scope manager (see scope_info.v).
	scope ScopeInfo
	// runes: svelteParseContext.runes while parsing (parserOptions.svelteFeatures.runes, else
	// `<svelte:options runes={…}>`, else the svelteConfig's compilerOptions.runes: see
	// ParseOptions).
	runes RunesMode
	// options: what the document was parsed with (a text derived from it is parsed the same way).
	options ParseOptions
	// generics_code: the code `void function<…>(){}` handed to the script parser for the
	// `generics` attribute ('' without one).
	generics_code string
	// lint_code: the code veslint's rules parse (lint.v), lint_start: where its template part
	// starts, lint_segments: the template text in it (pre_start: lint code offset).
	lint_code     string
	lint_start    int
	lint_segments []Segment
	// lint_generics_start: where the type aliases of the `generics` attribute are in the lint
	// code (-1 without them).
	lint_generics_start int = -1
	// cast: the Svelte compiler's template AST (compile_parse), what svelte_compiler analyzes.
	cast CAst
	// lint_parents: the Svelte node (index of nodes) of the template expression that starts at
	// that offset of the lint code.
	lint_parents map[int]int
}

// Parsers are the tree-sitter parsers parse_svelte_with reuses from file to file.
@[heap]
pub struct Parsers {
	ts &C.TSParser = unsafe { nil }
}

pub fn new_parsers() !&Parsers {
	ts := C.ts_parser_new()
	if !C.ts_parser_set_language(ts, C.tree_sitter_typescript()) {
		C.ts_parser_delete(ts)
		return error('the TypeScript grammar uses an ABI this tree-sitter runtime does not support')
	}
	return &Parsers{
		ts: ts
	}
}

pub fn (p &Parsers) close() {
	C.ts_parser_delete(p.ts)
}

// token_ends are the ends of the tokens of TypeScript code (bytes, sorted): veslint gets where
// TypeScript's nodes of the virtual code start (they include the trivia before them) from them.
pub fn (p &Parsers) token_ends(code string) ![]int {
	tree := parse_ts(p.ts, code)!
	defer {
		treesitter.tree_delete(tree)
	}
	return treesitter.token_ends(treesitter.root_node(tree)).ends
}

fn parse_ts(parser &C.TSParser, code string) !&C.TSTree {
	tree := C.ts_parser_parse_string(parser, unsafe { nil }, &char(code.str), u32(code.len))
	if isnil(tree) {
		return error('tree-sitter could not parse the code')
	}
	return tree
}

fn convert_es(root C.TSNode, code string) !estree.EsTree {
	return estree.convert_with(root, code, false, estree.Options{
		module:       true
		regexp_valid: fn (pattern string, flags string) bool {
			return jsregexp.regexp_new(estree.utf16_units(pattern), flags) != none
		}
	})
}

// es_type_name is the `type` of an ESTree node of the document (SvelteReactiveStatement for a
// top-level `$:` statement).
pub fn (d &Document) es_type_name(i int) string {
	if i in d.reactive {
		return 'SvelteReactiveStatement'
	}
	return d.es.nodes[i].typ.type_name()
}

// loc is svelte-eslint-parser's location of a byte offset of the file.
pub fn (d &Document) loc(offset int) Loc {
	return d.lc.loc_u16(d.index.to_u16(offset))
}

// utf16 converts a byte offset of the file to UTF-16 (ESLint's `range`).
pub fn (d &Document) utf16(offset int) int {
	return d.index.to_u16(offset)
}

// byte_offset converts a UTF-16 offset of the file to bytes.
pub fn (d &Document) byte_offset(u int) int {
	return d.index.to_byte(u)
}

// offset_of_loc is the byte offset of a line (from 1) and a UTF-16 column (from 0) of
// svelte-eslint-parser's lines (clamped to the text).
pub fn (d &Document) offset_of_loc(line int, column int) int {
	if line < 1 {
		return 0
	}
	if line > d.lc.line_starts.len {
		return d.src.len
	}
	return d.index.to_byte(d.lc.line_starts[line - 1] + column)
}

// free deletes the tree-sitter tree.
pub fn (mut d Document) free() {
	if d.tree != unsafe { nil } {
		treesitter.tree_delete(d.tree)
		d.tree = unsafe { nil }
	}
	for t in d.extra_trees {
		treesitter.tree_delete(t)
	}
	d.extra_trees = []
}

// ParseOptions are the configuration's say in svelteParseContext.runes while parsing
// (isRunesAsParseContext of svelte-eslint-parser's svelte-parse-context.ts): `features` is
// parserOptions.svelteFeatures.runes when `features_set` (`!= null`: it wins over everything, even
// when it is neither true nor false, `.unknown`), `config` the compilerOptions.runes of the
// svelteConfig (parserOptions.svelteConfig, else svelte.config.js), which
// `<svelte:options runes={…}>` overrides (`.unknown`: not set).
pub struct ParseOptions {
pub:
	features_set bool
	features     RunesMode
	config       RunesMode
}

// runes_mode is a boolean option as a RunesMode.
pub fn runes_mode(on bool) RunesMode {
	return if on { RunesMode.on } else { RunesMode.off }
}

// parse_svelte parses a .svelte file (UTF-8, without BOM). To parse many files, make the
// Parsers once and use parse_svelte_with.
pub fn parse_svelte(src string) !&Document {
	parsers := new_parsers()!
	defer {
		parsers.close()
	}
	return parse_svelte_with(src, parsers)
}

// parse_svelte_with parses a .svelte file with parsers kept from file to file, without runes
// options (see parse_svelte_options). A file svelte-eslint-parser rejects gives a Document with
// `error` set (and what was built so far).
pub fn parse_svelte_with(src string, parsers &Parsers) !&Document {
	return parse_svelte_options(src, parsers, ParseOptions{})
}

// parse_svelte_options is parse_svelte_with with the configuration's runes options.
pub fn parse_svelte_options(src string, parsers &Parsers, options ParseOptions) !&Document {
	index := new_text_index(src)
	mut doc := &Document{
		src:       src
		index:     index
		lc:        new_lines_and_columns(src, &index)
		separator: -1
		options:   options
	}
	sc := split_document(src)
	doc.template = sc.template
	doc.lang = sc.script_attrs['lang'] or { '' }
	ca := compile_parse(sc.template) or {
		if err is CompileError {
			doc.error = ParseError{
				message: err.message
				index:   err.pos
				code:    err.code
			}
			return doc
		}
		return err
	}
	doc.cast = ca
	mut c := &Conv{
		code:    src
		doc:     doc
		ca:      ca
		sc:      sc
		parsers: parsers
	}
	c.runes = if options.features_set {
		options.features
	} else if ca.options >= 0 && ca.nodes[ca.options].has_runes {
		runes_mode(ca.nodes[ca.options].runes)
	} else {
		options.config
	}
	doc.runes = c.runes
	c.convert_root()
	if e := c.err {
		doc.error = e
		return doc
	}
	c.restore()!
	doc.generics_code = c.generics_code
	return doc
}
