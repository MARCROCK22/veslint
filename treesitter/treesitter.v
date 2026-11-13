module treesitter

// Minimal bindings for tree-sitter (v0.27.0) and its TypeScript grammar (v0.23.2), statically
// linked. See PROMPT.md §3.2 and §3.3.

#flag -I @VMODROOT/vendor/tree-sitter/lib/include
#flag @VMODROOT/build/libtree-sitter-typescript.a
#flag @VMODROOT/vendor/tree-sitter/libtree-sitter.a
#include "tree_sitter/api.h"

@[typedef]
struct C.TSParser {}

@[typedef]
struct C.TSTree {}

@[typedef]
struct C.TSLanguage {}

@[typedef]
struct C.TSQuery {}

@[typedef]
struct C.TSQueryCursor {}

// Passed by value (32 bytes); api.h defines the real layout.
@[typedef]
struct C.TSNode {}

// Created by value and used by pointer; api.h defines the real layout.
@[typedef]
struct C.TSTreeCursor {}

@[typedef]
struct C.TSPoint {
	row    u32
	column u32
}

@[typedef]
struct C.TSQueryCapture {
	node  C.TSNode
	index u32
}

@[typedef]
struct C.TSQueryMatch {
	id            u32
	pattern_index u16
	capture_count u16
	captures      &C.TSQueryCapture
}

// The grammar header declares `const TSLanguage *`, which would clash with this prototype; so it
// is not included and V emits the declaration thanks to @[c_extern].
@[c_extern]
fn C.tree_sitter_typescript() &C.TSLanguage

// The same grammar in its `tsx` dialect, for files with JSX.
@[c_extern]
fn C.tree_sitter_tsx() &C.TSLanguage

fn C.strncmp(a &char, b &char, n uint) int
fn C.ts_language_abi_version(self &C.TSLanguage) u32
fn C.ts_parser_new() &C.TSParser
fn C.ts_parser_delete(self &C.TSParser)
fn C.ts_parser_set_language(self &C.TSParser, language &C.TSLanguage) bool
fn C.ts_parser_parse_string(self &C.TSParser, old_tree &C.TSTree, str &char, length u32) &C.TSTree
fn C.ts_tree_delete(self &C.TSTree)
fn C.ts_tree_root_node(self &C.TSTree) C.TSNode
fn C.ts_node_type(self C.TSNode) &char
fn C.ts_node_symbol(self C.TSNode) u16
fn C.ts_node_is_named(self C.TSNode) bool
fn C.ts_node_has_error(self C.TSNode) bool
fn C.ts_node_start_byte(self C.TSNode) u32
fn C.ts_node_end_byte(self C.TSNode) u32
fn C.ts_node_start_point(self C.TSNode) C.TSPoint
fn C.ts_node_is_null(self C.TSNode) bool
fn C.ts_node_child(self C.TSNode, child_index u32) C.TSNode
fn C.ts_node_child_count(self C.TSNode) u32
fn C.ts_node_named_child(self C.TSNode, child_index u32) C.TSNode
fn C.ts_node_named_child_count(self C.TSNode) u32
fn C.ts_node_child_by_field_name(self C.TSNode, name &char, name_length u32) C.TSNode
fn C.ts_node_parent(self C.TSNode) C.TSNode
fn C.ts_node_prev_sibling(self C.TSNode) C.TSNode
fn C.ts_node_prev_named_sibling(self C.TSNode) C.TSNode
fn C.ts_node_next_sibling(self C.TSNode) C.TSNode
fn C.ts_node_is_extra(self C.TSNode) bool

// error_type is `TSQueryError *` in C; passed as voidptr to avoid declaring the enum.
fn C.ts_query_new(language &C.TSLanguage, source &char, source_len u32, error_offset &u32, error_type voidptr) &C.TSQuery
fn C.ts_query_delete(self &C.TSQuery)
fn C.ts_query_cursor_new() &C.TSQueryCursor
fn C.ts_query_cursor_delete(self &C.TSQueryCursor)
fn C.ts_query_cursor_exec(self &C.TSQueryCursor, query &C.TSQuery, node C.TSNode)
fn C.ts_query_cursor_next_match(self &C.TSQueryCursor, match &C.TSQueryMatch) bool
fn C.ts_tree_cursor_new(node C.TSNode) C.TSTreeCursor
fn C.ts_tree_cursor_delete(self &C.TSTreeCursor)
fn C.ts_tree_cursor_current_node(self &C.TSTreeCursor) C.TSNode
fn C.ts_tree_cursor_goto_first_child(self &C.TSTreeCursor) bool
fn C.ts_tree_cursor_goto_next_sibling(self &C.TSTreeCursor) bool
fn C.ts_tree_cursor_goto_parent(self &C.TSTreeCursor) bool
fn C.strcmp(a &char, b &char) int

// Verified query from PROMPT.md §3.2: names of variables, functions and parameters.
const declarations_query = '(variable_declarator name: (identifier) @name)
(function_declaration name: (identifier) @name)
(required_parameter pattern: (identifier) @name)
(optional_parameter pattern: (identifier) @name)'

// Ident is an identifier found by tree-sitter, with its position in bytes. The line and the column
// veslint prints come from start_byte (offsets.utf16_positions), not from the row and the column
// of tree-sitter: its rows only count `\n`, and TypeScript and ESLint also break a line at a lone
// `\r`, U+2028 and U+2029.
pub struct Ident {
pub:
	text       string
	start_byte int
	row        int // tree-sitter's 0-based row; negative for a report without a place in the file
	col_bytes  int // tree-sitter's 0-based column, in bytes from the last `\n`
	// end_byte is where a reported range ends (the end of ESLint's `loc`), -1 when only its start
	// is known.
	end_byte int = -1
	// node_end: end_byte is the end of a tree-sitter node, which may hold the comments that
	// follow it (the rules end the report at its last token).
	node_end bool
}

pub struct Parser {
	parser &C.TSParser
	lang   &C.TSLanguage
	query  &C.TSQuery
}

// new_ts_parser prepares the TypeScript parser and compiles the declarations query.
pub fn new_parser() !Parser {
	return new_parser_for(false)
}

// new_tsx_parser is the parser of .tsx files: the same grammar with JSX (and without `<T>x`
// assertions).
pub fn new_tsx_parser() !Parser {
	return new_parser_for(true)
}

fn new_parser_for(tsx bool) !Parser {
	lang := if tsx { C.tree_sitter_tsx() } else { C.tree_sitter_typescript() }
	parser := C.ts_parser_new()
	if !C.ts_parser_set_language(parser, lang) {
		C.ts_parser_delete(parser)
		return error('the grammar uses ABI ${C.ts_language_abi_version(lang)}, which this tree-sitter runtime does not support')
	}
	mut err_offset := u32(0)
	mut err_type := u32(0)
	query := C.ts_query_new(lang, &char(declarations_query.str), u32(declarations_query.len),
		&err_offset, voidptr(&err_type))
	if isnil(query) {
		C.ts_parser_delete(parser)
		return error('the declarations query does not compile (error ${err_type} at offset ${err_offset})')
	}
	return Parser{
		parser: parser
		lang:   lang
		query:  query
	}
}

pub fn (p &Parser) close() {
	C.ts_query_delete(p.query)
	C.ts_parser_delete(p.parser)
}

// parse returns the tree of `src` (BOM already stripped). It must be freed with `C.ts_tree_delete`.
pub fn (p &Parser) parse(src string) !&C.TSTree {
	if i64(src.len) > i64(max_u32) {
		return error('file too large for tree-sitter (${src.len} bytes)')
	}
	tree := C.ts_parser_parse_string(p.parser, unsafe { nil }, &char(src.str), u32(src.len))
	if isnil(tree) {
		return error('tree-sitter could not parse the file')
	}
	return tree
}

pub fn tree_has_error(tree &C.TSTree) bool {
	return C.ts_node_has_error(C.ts_tree_root_node(tree))
}

// identifiers returns, in order of appearance, the identifiers of `tree`: the declared names (query
// of §3.2) or, with `all`, every `identifier` node.
pub fn (p &Parser) identifiers(tree &C.TSTree, src string, all bool) []Ident {
	root := C.ts_tree_root_node(tree)
	mut idents := if all { all_identifiers(root, src) } else { p.declared_names(root, src) }
	idents.sort(a.start_byte < b.start_byte)
	return idents
}

fn (p &Parser) declared_names(root C.TSNode, src string) []Ident {
	cursor := C.ts_query_cursor_new()
	defer {
		C.ts_query_cursor_delete(cursor)
	}
	C.ts_query_cursor_exec(cursor, p.query, root)
	mut idents := []Ident{}
	mut m := C.TSQueryMatch{}
	for C.ts_query_cursor_next_match(cursor, &m) {
		for i in 0 .. int(m.capture_count) {
			idents << ident_from_node(unsafe { m.captures[i].node }, src)
		}
	}
	return idents
}

fn all_identifiers(root C.TSNode, src string) []Ident {
	return nodes_of_kind(root, c'identifier').map(ident_from_node(it, src))
}

// nodes_of_kind returns, in preorder (order of appearance), the named nodes of that kind. It walks
// the tree with a TSTreeCursor.
pub fn nodes_of_kind(root C.TSNode, kind &char) []C.TSNode {
	mut nodes := []C.TSNode{}
	mut cursor := C.ts_tree_cursor_new(root)
	defer {
		C.ts_tree_cursor_delete(&cursor)
	}
	for {
		node := C.ts_tree_cursor_current_node(&cursor)
		if C.ts_node_is_named(node) && unsafe { C.strcmp(C.ts_node_type(node), kind) } == 0 {
			nodes << node
		}
		if C.ts_tree_cursor_goto_first_child(&cursor) {
			continue
		}
		for !C.ts_tree_cursor_goto_next_sibling(&cursor) {
			if !C.ts_tree_cursor_goto_parent(&cursor) {
				return nodes
			}
		}
	}
	return nodes
}

// What nodes_of_kinds knows of a symbol of the grammar, by its number (the grammars have fewer
// than symbol_states).
const symbol_states = 1024
const symbol_seen = u8(1)
const symbol_wanted = u8(2)
const symbol_skipped = u8(4)

// nodes_of_kinds returns, in preorder, the named nodes of any of the `kinds`, without entering the
// subtrees of the `skip` kinds.
pub fn nodes_of_kinds(root C.TSNode, kinds []string, skip []string) []C.TSNode {
	mut nodes := []C.TSNode{}
	mut cursor := C.ts_tree_cursor_new(root)
	defer {
		C.ts_tree_cursor_delete(&cursor)
	}
	// The kind of a node is the name of its symbol in the grammar, so what a kind is in the two
	// lists is asked once for each symbol of the tree: most of the nodes of a file are visited
	// by every rule.
	mut symbols := [symbol_states]u8{}
	for {
		node := C.ts_tree_cursor_current_node(&cursor)
		symbol := int(C.ts_node_symbol(node))
		mut state := if symbol < symbol_states { symbols[symbol] } else { u8(0) }
		if state == 0 {
			kind := node_kind(node)
			state = symbol_seen
			if kind in kinds {
				state |= symbol_wanted
			}
			if kind in skip {
				state |= symbol_skipped
			}
			if symbol < symbol_states {
				symbols[symbol] = state
			}
		}
		if state & symbol_wanted != 0 && C.ts_node_is_named(node) {
			nodes << node
		}
		if state & symbol_skipped == 0 && C.ts_tree_cursor_goto_first_child(&cursor) {
			continue
		}
		for !C.ts_tree_cursor_goto_next_sibling(&cursor) {
			if !C.ts_tree_cursor_goto_parent(&cursor) {
				return nodes
			}
		}
	}
	return nodes
}

// node_kind returns the tree-sitter node kind (`call_expression`, `&&`, `async`…). The string is
// the grammar's own, which lives as long as the program: it is not copied.
pub fn node_kind(n C.TSNode) string {
	return unsafe { tos2(&u8(C.ts_node_type(n))) }
}

pub fn node_start(n C.TSNode) int {
	return int(C.ts_node_start_byte(n))
}

pub fn node_end(n C.TSNode) int {
	return int(C.ts_node_end_byte(n))
}

// node_field returns the child with that field name, if any.
pub fn node_field(n C.TSNode, name string) ?C.TSNode {
	child := C.ts_node_child_by_field_name(n, &char(name.str), u32(name.len))
	if C.ts_node_is_null(child) {
		return none
	}
	return child
}

// named_children returns the named children, without comments.
pub fn named_children(n C.TSNode) []C.TSNode {
	count := int(C.ts_node_named_child_count(n))
	mut named := []C.TSNode{cap: count}
	for i in 0 .. count {
		child := C.ts_node_named_child(n, u32(i))
		if node_kind(child) != 'comment' {
			named << child
		}
	}
	return named
}

// children returns all the children, also the anonymous ones (`=>`, `async`…) and comments.
pub fn children(n C.TSNode) []C.TSNode {
	count := int(C.ts_node_child_count(n))
	mut out := []C.TSNode{cap: count}
	for i in 0 .. count {
		out << C.ts_node_child(n, u32(i))
	}
	return out
}

pub fn first_named_child(n C.TSNode) ?C.TSNode {
	named := named_children(n)
	if named.len == 0 {
		return none
	}
	return named[0]
}

// has_child_kind tells whether some child, also anonymous ones like `async`, is of that kind.
pub fn has_child_kind(n C.TSNode, kind string) bool {
	for i in 0 .. int(C.ts_node_child_count(n)) {
		if node_kind(C.ts_node_child(n, u32(i))) == kind {
			return true
		}
	}
	return false
}

fn ident_from_node(node C.TSNode, src string) Ident {
	start := int(C.ts_node_start_byte(node))
	end := int(C.ts_node_end_byte(node))
	point := C.ts_node_start_point(node)
	return Ident{
		text:       src[start..end]
		start_byte: start
		row:        int(point.row)
		col_bytes:  int(point.column)
	}
}

pub fn tree_delete(tree &C.TSTree) {
	C.ts_tree_delete(tree)
}

pub fn root_node(tree &C.TSTree) C.TSNode {
	return C.ts_tree_root_node(tree)
}

pub fn next_sibling(n C.TSNode) ?C.TSNode {
	next := C.ts_node_next_sibling(n)
	if C.ts_node_is_null(next) {
		return none
	}
	return next
}

pub fn prev_sibling(n C.TSNode) ?C.TSNode {
	prev := C.ts_node_prev_sibling(n)
	if C.ts_node_is_null(prev) {
		return none
	}
	return prev
}

pub fn node_parent(n C.TSNode) ?C.TSNode {
	parent := C.ts_node_parent(n)
	if C.ts_node_is_null(parent) {
		return none
	}
	return parent
}

// TokenEnds are, in order, the ends of the tokens of a tree: the leaves that are not comments
// (extras), nor the leading `#!`, nor zero-width (automatic `;`, MISSING nodes). For TypeScript all
// of that is trivia; this index gives the bounds of a node as TypeScript sees them, even when
// tree-sitter puts a trailing comment in the node (it happens without `;`).
pub struct TokenEnds {
	ends []int
}

// token_ends walks the tree once with a TSTreeCursor.
pub fn token_ends(root C.TSNode) TokenEnds {
	mut ends := []int{}
	mut cursor := C.ts_tree_cursor_new(root)
	defer {
		C.ts_tree_cursor_delete(&cursor)
	}
	for {
		node := C.ts_tree_cursor_current_node(&cursor)
		extra := C.ts_node_is_extra(node)
		// The children of a JSX element have no leading trivia for TypeScript: the white space
		// between them is JsxText, also the one with line breaks, which tree-sitter skips. So the
		// start of each child counts as the end of a token.
		if !extra && unsafe { C.strncmp(C.ts_node_type(node), c'jsx_', 4) } == 0 {
			parent := C.ts_node_parent(node)
			if !C.ts_node_is_null(parent)
				&& unsafe { C.strcmp(C.ts_node_type(parent), c'jsx_element') } == 0
				&& C.ts_node_start_byte(node) > C.ts_node_start_byte(parent) {
				ends << int(C.ts_node_start_byte(node))
			}
		}
		if !extra && C.ts_node_child_count(node) == 0 {
			start := int(C.ts_node_start_byte(node))
			end := int(C.ts_node_end_byte(node))
			if end > start && unsafe { C.strcmp(C.ts_node_type(node), c'hash_bang_line') } != 0 {
				ends << end
			}
		}
		if !extra && C.ts_tree_cursor_goto_first_child(&cursor) {
			continue
		}
		for !C.ts_tree_cursor_goto_next_sibling(&cursor) {
			if !C.ts_tree_cursor_goto_parent(&cursor) {
				return TokenEnds{
					ends: ends
				}
			}
		}
	}
	return TokenEnds{
		ends: ends
	}
}

// last_end gives the end of the last token that ends at `offset` or before, or 0 if there is none.
// With the start of a node it is the `pos` tsgo gives the node (the end of the previous token);
// with its end, the end of its last token.
pub fn (t &TokenEnds) last_end(offset int) int {
	mut lo := 0
	mut hi := t.ends.len
	for lo < hi {
		mid := (lo + hi) / 2
		if t.ends[mid] <= offset {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return if lo == 0 { 0 } else { t.ends[lo - 1] }
}

pub fn position_of(node C.TSNode) Ident {
	point := C.ts_node_start_point(node)
	return Ident{
		start_byte: node_start(node)
		row:        int(point.row)
		col_bytes:  int(point.column)
		end_byte:   node_end(node)
		node_end:   true
	}
}
