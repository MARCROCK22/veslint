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
	// es_parent: the Svelte parent of an ESTree node grafted into the template (its ESTree
	// parent is a wrapper of `pre` that is not in the AST).
	es_parent map[int]int
	// pre: the pre-virtual code in bytes (blanks per byte: its script part is at file offsets);
	// pre_u16: the same code as svelte-eslint-parser builds it (what typescript-eslint parses).
	pre       string
	pre_u16   string
	separator int // `\n;` at [separator, separator+2) of pre (-1: no template expression)
	// segments map the pieces of pre copied from the file (template expressions) back to it.
	segments []Segment
	// template: the code handed to the compiler.
	template string
	error    ?ParseError
	// The <script> lang (merged over the script blocks), and the generics attribute.
	lang string
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

// free deletes the tree-sitter tree.
pub fn (mut d Document) free() {
	if d.tree != unsafe { nil } {
		treesitter.tree_delete(d.tree)
		d.tree = unsafe { nil }
	}
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

// parse_svelte_with parses a .svelte file with parsers kept from file to file. A file
// svelte-eslint-parser rejects gives a Document with `error` set (and what was built so far).
pub fn parse_svelte_with(src string, parsers &Parsers) !&Document {
	index := new_text_index(src)
	mut doc := &Document{
		src:       src
		index:     index
		lc:        new_lines_and_columns(src, &index)
		separator: -1
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
	mut c := &Conv{
		code:    src
		doc:     doc
		ca:      ca
		sc:      sc
		parsers: parsers
	}
	c.convert_root()
	if e := c.err {
		doc.error = e
		return doc
	}
	c.restore()!
	return doc
}
