module treesitter

// The collector's heap is grown before the constants of the modules that import this one are made
// (gcheap/gcheap.v).
import gcheap as _
import os

// Minimal bindings for tree-sitter (v0.27.0) and its TypeScript grammar (v0.23.2), statically
// linked. See PROMPT.md §3.2 and §3.3.
//
// tree-sitter parses; veslint reads the rows of each tree (rows.h): every visible node with its
// kind, field, flags, range and shape, built by one walk of the tree (rows_build.h), after which
// the tree is freed. A node (C.vt_node) is a row of a set of rows. Only the editor keeps trees
// (TreeCache), to parse the next text of a file from the last one.

#flag -I @VMODROOT/vendor/tree-sitter/lib/include
#flag @VMODROOT/build/libtree-sitter-typescript.a

// The library the Makefile builds for link-time optimization; build-windows.ps1 builds its own.
$if windows {
	#flag @VMODROOT/vendor/tree-sitter/libtree-sitter.a
} $else {
	#flag @VMODROOT/treesitter/out/libtree-sitter.a
}

#include "tree_sitter/api.h"
#include "@VMODROOT/treesitter/rows.h"
#include "@VMODROOT/treesitter/rows_build.h"
#include "@VMODROOT/treesitter/field_cache.h"
#include "@VMODROOT/treesitter/incremental.h"
#include "@VMODROOT/treesitter/converter_tables.h"

@[typedef]
struct C.TSParser {}

@[typedef]
struct C.TSTree {}

@[typedef]
struct C.TSLanguage {}

// The rows of a tree (rows.h). They are malloc'd: free them with rows_free.
@[typedef]
pub struct C.vt_rows {
pub:
	count u32
}

// A node: a row of a set of rows (rows.h), 16 bytes passed by value. The null node has no rows.
// Its pointer to the rows is not declared to V (C.vt_node_rows gives it): a struct with one makes
// V ask for an `or {}` at every read of a map of nodes. Compare nodes with C.vt_node_eq.
@[typedef]
pub struct C.vt_node {
pub:
	index u32
}

// A row (rows.h).
@[typedef]
pub struct C.vt_row {
pub:
	start_byte   u32
	end_byte     u32
	start_row    u32
	start_column u32
	end_row      u32
	end_column   u32
	parent       u32
	next         u32
	prev         u32
	last         u32
	symbol       u16
	field        u16
	flags        u8
}

@[typedef]
struct C.vt_point {
	row    u32
	column u32
}

pub const row_named = u8(1) // VT_ROW_NAMED
pub const row_extra = u8(2) // VT_ROW_EXTRA
pub const row_none = u32(0xffffffff) // VT_ROW_NONE

// The grammar header declares `const TSLanguage *`, which would clash with this prototype; so it
// is not included and V emits the declaration thanks to @[c_extern].
@[c_extern]
fn C.tree_sitter_typescript() &C.TSLanguage

// The same grammar in its `tsx` dialect, for files with JSX.
@[c_extern]
fn C.tree_sitter_tsx() &C.TSLanguage

fn C.strncmp(a &char, b &char, n uint) int
fn C.strcmp(a &char, b &char) int
fn C.ts_language_abi_version(self &C.TSLanguage) u32
fn C.ts_language_symbol_for_name(self &C.TSLanguage, name &char, length u32, is_named bool) u16
fn C.ts_parser_new() &C.TSParser
fn C.ts_parser_delete(self &C.TSParser)
fn C.ts_parser_set_language(self &C.TSParser, language &C.TSLanguage) bool
fn C.ts_parser_language(self &C.TSParser) &C.TSLanguage
fn C.ts_parser_parse_string(self &C.TSParser, old_tree &C.TSTree, str &char, length u32) &C.TSTree
fn C.ts_tree_delete(self &C.TSTree)
fn C.ts_tree_language(self &C.TSTree) &C.TSLanguage
fn C.vt_reparse(parser &C.TSParser, old &C.TSTree, old_text &char, old_length u32, new_text &char, new_length u32, outcome &int) &C.TSTree
fn C.vt_trees_differ(a &C.TSTree, b &C.TSTree) i64

fn C.vt_rows_from_tree(tree &C.TSTree) &C.vt_rows
fn C.vt_rows_check(rows &C.vt_rows, tree &C.TSTree) u64
fn C.vt_rows_free(rows &C.vt_rows)
fn C.vt_rows_adopt(language voidptr, buffer voidptr, count u32) &C.vt_rows
fn C.vt_converter_symbol_fn() voidptr
fn C.vt_converter_field_fn() voidptr
fn C.vt_rows_dump(rows &C.vt_rows, path &char) bool
fn C.vt_rows_load(path &char, language voidptr) &C.vt_rows
fn C.vt_rows_root(rows &C.vt_rows) C.vt_node
fn C.vt_rows_language(rows &C.vt_rows) &C.TSLanguage
fn C.vt_rows_has_error(rows &C.vt_rows) bool
fn C.vt_node_at(rows &C.vt_rows, index u32) C.vt_node
fn C.vt_node_rows(n C.vt_node) &C.vt_rows
fn C.vt_node_row(n C.vt_node) &C.vt_row
fn C.vt_node_type(n C.vt_node) &char
fn C.vt_node_language(n C.vt_node) &C.TSLanguage
fn C.vt_node_is_null(n C.vt_node) bool
fn C.vt_node_eq(a C.vt_node, b C.vt_node) bool
fn C.vt_node_symbol(n C.vt_node) u16
fn C.vt_node_field(n C.vt_node) u16
fn C.vt_node_is_named(n C.vt_node) bool
fn C.vt_node_is_extra(n C.vt_node) bool
fn C.vt_node_is_missing(n C.vt_node) bool
fn C.vt_node_is_error(n C.vt_node) bool
fn C.vt_node_has_error(n C.vt_node) bool
fn C.vt_node_start_byte(n C.vt_node) u32
fn C.vt_node_end_byte(n C.vt_node) u32
fn C.vt_node_start_point(n C.vt_node) C.vt_point
fn C.vt_node_last(n C.vt_node) u32
fn C.vt_node_parent(n C.vt_node) C.vt_node
fn C.vt_node_next(n C.vt_node) C.vt_node
fn C.vt_node_next_sibling(n C.vt_node) C.vt_node
fn C.vt_node_prev_sibling(n C.vt_node) C.vt_node
fn C.vt_node_next_named_sibling(n C.vt_node) C.vt_node
fn C.vt_node_prev_named_sibling(n C.vt_node) C.vt_node
fn C.vt_node_first_child(n C.vt_node) C.vt_node
fn C.vt_node_child_count(n C.vt_node) u32
fn C.vt_node_child(n C.vt_node, i u32) C.vt_node
fn C.vt_node_named_child_count(n C.vt_node) u32
fn C.vt_node_named_child(n C.vt_node, i u32) C.vt_node
fn C.vt_node_child_by_field_name(n C.vt_node, name &char, length u32) C.vt_node
fn C.vt_field_id(language &C.TSLanguage, name &char, length u32) u16
fn C.vt_node_descendant_count(n C.vt_node) u32

// What the rows of each parse go through: VESLINT_ROWS_CHECK=1 compares them with the tree they
// were built from (rows_build.h: every node, with what tree-sitter's functions answer), and writes
// the differences to stderr (or to the file VESLINT_ROWS_CHECK_LOG); VESLINT_ROWS_STUB=<directory>
// writes them to a file there, frees them and the tree, and reads them back into new rows, which
// are filled as another parser would fill them (rows.h): a lint that gives the same with it reads
// nothing of tree-sitter's tree.
const rows_check = os.getenv('VESLINT_ROWS_CHECK') == '1'
const rows_stub = os.getenv('VESLINT_ROWS_STUB')

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
	tsx    bool
}

// new_ts_parser prepares the TypeScript parser.
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
	return Parser{
		parser: parser
		lang:   lang
		tsx:    tsx
	}
}

// ConverterTables are what the converter from TypeScript's AST needs of a language of the grammar
// to write its rows (tsgo.convert_language): the language and its symbol and field lookups.
pub struct ConverterTables {
pub:
	language voidptr
	symbol   voidptr
	field    voidptr
}

// converter_tables are the ConverterTables of the TypeScript (or, `tsx`, TSX) language.
pub fn converter_tables(tsx bool) ConverterTables {
	return ConverterTables{
		language: voidptr(if tsx { C.tree_sitter_tsx() } else { C.tree_sitter_typescript() })
		symbol:   C.vt_converter_symbol_fn()
		field:    C.vt_converter_field_fn()
	}
}

// is_tsx: the parser reads the TSX dialect (new_tsx_parser).
pub fn (p &Parser) is_tsx() bool {
	return p.tsx
}

// ts_parser is the parser's tree-sitter parser, for what takes a bare one (tsparse.convert).
pub fn (p &Parser) ts_parser() &C.TSParser {
	return p.parser
}

// adopt_rows gives rows of this parser's language from `count` rows another parser filled in
// `buffer`, a malloc'd array of vt_row (tsgo.convert's rows) that the rows take: they are freed with
// rows_free, the buffer with them.
pub fn (p &Parser) adopt_rows(buffer voidptr, count int) !&C.vt_rows {
	return adopt_rows_of(p.parser, buffer, count)
}

// adopt_rows_of is Parser.adopt_rows for the language of a bare tree-sitter parser (the parsers of
// .vue and .svelte files).
pub fn adopt_rows_of(parser &C.TSParser, buffer voidptr, count int) !&C.vt_rows {
	if count <= 0 {
		unsafe { C.free(buffer) }
		return error('the converter gave no rows')
	}
	rows := C.vt_rows_adopt(voidptr(C.ts_parser_language(parser)), buffer, u32(count))
	if isnil(rows) {
		return error('out of memory for the rows of a tree')
	}
	return rows
}

// parser_is_tsx: a bare tree-sitter parser reads the TSX dialect of the grammar.
pub fn parser_is_tsx(parser &C.TSParser) bool {
	return voidptr(C.ts_parser_language(parser)) == voidptr(C.tree_sitter_tsx())
}

pub fn (p &Parser) close() {
	C.ts_parser_delete(p.parser)
}

// parse returns the rows of `src` (BOM already stripped). They must be freed with rows_free.
pub fn (p &Parser) parse(src string) !&C.vt_rows {
	return parse_with(p.parser, src, 'the file')
}

// parse_with parses `src` with a parser of tree-sitter into rows; `what` names the text in the
// errors.
pub fn parse_with(parser &C.TSParser, src string, what string) !&C.vt_rows {
	tree := parse_tree(parser, src, what)!
	rows := rows_of(tree) or {
		C.ts_tree_delete(tree)
		return err
	}
	C.ts_tree_delete(tree)
	return stub_rows(rows)
}

fn parse_tree(parser &C.TSParser, src string, what string) !&C.TSTree {
	if i64(src.len) > i64(max_u32) {
		return error('${what} is too large for tree-sitter (${src.len} bytes)')
	}
	tree := C.ts_parser_parse_string(parser, unsafe { nil }, &char(src.str), u32(src.len))
	if isnil(tree) {
		return error('tree-sitter could not parse ${what}')
	}
	return tree
}

// rows_of gives the rows of a tree, which stays the caller's.
pub fn rows_of(tree &C.TSTree) !&C.vt_rows {
	rows := C.vt_rows_from_tree(tree)
	if isnil(rows) {
		return error('out of memory for the rows of a tree')
	}
	if rows_check {
		C.vt_rows_check(rows, tree)
	}
	return rows
}

// stub_rows (VESLINT_ROWS_STUB) gives rows read back from a file the rows were written to (they
// are freed), or the rows themselves without it.
fn stub_rows(rows &C.vt_rows) !&C.vt_rows {
	if rows_stub == '' {
		return rows
	}
	language := C.vt_rows_language(rows)
	path := os.join_path(rows_stub, 'rows-${os.getpid()}-${voidptr(rows)}.bin')
	if !C.vt_rows_dump(rows, &char(path.str)) {
		C.vt_rows_free(rows)
		return error('cannot write the rows to ${path}')
	}
	C.vt_rows_free(rows)
	loaded := C.vt_rows_load(&char(path.str), voidptr(language))
	os.rm(path) or {}
	if isnil(loaded) {
		return error('cannot read the rows back from ${path}')
	}
	return loaded
}

// rows_free frees rows: their nodes must not be used after.
pub fn rows_free(rows &C.vt_rows) {
	C.vt_rows_free(rows)
}

// Reparse tells how Parser.reparse parsed a text.
pub enum Reparse {
	same        // the texts are equal: the old tree
	incremental // from the old tree
	fresh       // from scratch: the old tree could not be trusted for this edit (incremental.h)
}

// reparse returns the tree of `src` from `old`, the tree this parser gave for `old_src`, which it
// takes: tree-sitter reuses the subtrees the change from `old_src` to `src` leaves as they were
// (the bytes both texts have in common at the start and at the end), and the tree is checked to be
// the one a parse from scratch gives, or parsed from scratch (incremental.h, vt_reparse). For equal
// texts it is `old` itself. `old` is freed otherwise, also when the parse fails.
pub fn (p &Parser) reparse(old &C.TSTree, old_src string, src string) !(&C.TSTree, Reparse) {
	if i64(src.len) > i64(max_u32) {
		C.ts_tree_delete(old)
		return error('file too large for tree-sitter (${src.len} bytes)')
	}
	mut outcome := 0
	tree := C.vt_reparse(p.parser, old, &char(old_src.str), u32(old_src.len), &char(src.str),
		u32(src.len), &outcome)
	if isnil(tree) {
		return error('tree-sitter could not parse the file')
	}
	return tree, unsafe { Reparse(outcome) }
}

// parse_tree is the tree of `src`, for a TreeCache. It must be freed with tree_delete.
pub fn (p &Parser) parse_tree(src string) !&C.TSTree {
	return parse_tree(p.parser, src, 'the file')
}

// tree_delete frees a tree of tree-sitter.
pub fn tree_delete(tree &C.TSTree) {
	C.ts_tree_delete(tree)
}

// trees_differ is the start byte of the first node in which two trees differ (kind, range,
// flags, field or number of children, in preorder), or -1 when they are the same tree.
pub fn trees_differ(a &C.TSTree, b &C.TSTree) i64 {
	return C.vt_trees_differ(a, b)
}

// TreeCache keeps the last tree of a few files with the text it was parsed from, so that the next
// parse of a new text of the same file (an edit in an editor: veslint --server) is an incremental
// parse from it (Parser.reparse). Its trees are its own: one is freed when a file is parsed again,
// forgotten or pushed out by others. A parse gives new rows of the tree, which are the caller's.
//
// A file TypeScript's parser read first has no tree: seed parses its text in a thread of its own,
// whose tree the cache takes when it is done (has, parse), so that the next text is parsed from
// it without the first lint waiting for tree-sitter.
//
// VESLINT_INCREMENTAL=0 turns it off (every parse from scratch; veslint --server then reuses no
// answer either); VESLINT_INCREMENTAL_CHECK=1
// parses each new text from scratch too and compares both trees: a difference is written to
// stderr and the tree from scratch is used.
@[heap]
pub struct TreeCache {
mut:
	entries map[string]CachedTree
	order   []string // the keys, the most recently parsed last
	off     bool
	check   bool
	// seeding: the keys whose seed has not come back; seeded: the trees of the seeds.
	seeding map[string]bool
	seeded  chan SeededTree = chan SeededTree{cap: max_seeds}
pub mut:
	// how many parses of a new text of a file were Reparse.same, .incremental and .fresh
	reparses [3]int
}

struct CachedTree {
	text string
	tree &C.TSTree
	lang &C.TSLanguage
}

// tree_cache_size is how many trees a TreeCache keeps: the files being edited.
const tree_cache_size = 8

// max_seeds is how many seeds may be on their way at once (TreeCache.seed): a seed's thread never
// waits to give its tree.
const max_seeds = 16

// SeededTree is the tree a seed's thread parsed for `key` from `text` (nil when it failed).
struct SeededTree {
	key  string
	text string
	tree &C.TSTree     = unsafe { nil }
	lang &C.TSLanguage = unsafe { nil }
}

pub fn new_tree_cache() &TreeCache {
	return &TreeCache{
		off:   os.getenv('VESLINT_INCREMENTAL') == '0'
		check: os.getenv('VESLINT_INCREMENTAL_CHECK') == '1'
	}
}

// parse is the rows of `src` for the file `key`, from the tree of its last text when it has one
// of this parser's language. The rows are the caller's; the tree stays the cache's until the next
// parse of `key`, forget(key) or clear().
pub fn (mut c TreeCache) parse(p &Parser, key string, src string) !&C.vt_rows {
	tree := c.parse_tree(p, key, src)!
	return stub_rows(rows_of(tree)!)
}

// parse_tree is the tree parse gives the rows of.
pub fn (mut c TreeCache) parse_tree(p &Parser, key string, src string) !&C.TSTree {
	c.take_seeds()
	mut tree := &C.TSTree(unsafe { nil })
	if entry := c.entries[key] {
		c.entries.delete(key)
		c.order = c.order.filter(it != key)
		if c.off || voidptr(entry.lang) != voidptr(p.lang) {
			C.ts_tree_delete(entry.tree)
			tree = p.parse_tree(src)!
		} else {
			again, how := p.reparse(entry.tree, entry.text, src)!
			tree = again
			c.reparses[int(how)]++
			if c.check && how == .incremental {
				fresh := p.parse_tree(src) or {
					C.ts_tree_delete(tree)
					return err
				}
				at := C.vt_trees_differ(tree, fresh)
				if at >= 0 {
					eprintln('veslint: the incremental parse of ${key} differs from a parse from scratch at byte ${at}')
					C.ts_tree_delete(tree)
					tree = fresh
				} else {
					C.ts_tree_delete(fresh)
				}
			}
		}
	} else {
		tree = p.parse_tree(src)!
	}
	c.keep(key, src, tree, p.lang)
	return tree
}

// keep makes `tree`, parsed from `src`, the tree of `key`.
fn (mut c TreeCache) keep(key string, src string, tree &C.TSTree, lang &C.TSLanguage) {
	// The tree and the language are tree-sitter's (C memory), not V values on the stack.
	c.entries[key] = unsafe {
		CachedTree{
			text: src
			tree: tree
			lang: lang
		}
	}
	c.order << key
	for c.order.len > tree_cache_size {
		c.forget(c.order[0])
	}
}

// has: the cache has a tree of `key` of the language of `p`, for a parse of its next text.
pub fn (mut c TreeCache) has(p &Parser, key string) bool {
	c.take_seeds()
	entry := c.entries[key] or { return false }
	return voidptr(entry.lang) == voidptr(p.lang)
}

// seed parses `src`, the text of `key`, with tree-sitter in a thread of its own (the dialect of
// `p`), unless a seed of `key` is on its way: the cache takes its tree at its next has or parse
// that finds it done, while it has no newer tree of `key`.
pub fn (mut c TreeCache) seed(p &Parser, key string, src string) {
	if c.off || c.seeding[key] || c.seeding.len >= max_seeds {
		return
	}
	c.seeding[key] = true
	spawn seed_tree(c.seeded, p.tsx, key, src)
}

// seed_tree is a seed's thread: its own parser (tree-sitter's are not shared between threads).
fn seed_tree(out chan SeededTree, tsx bool, key string, src string) {
	p := new_parser_for(tsx) or {
		out <- SeededTree{
			key: key
		}
		return
	}
	tree := p.parse_tree(src) or { unsafe { nil } }
	out <- SeededTree{
		key:  key
		text: src
		tree: tree
		lang: p.lang
	}
	p.close()
}

// take_seeds keeps the trees of the seeds that are done, but for files the cache has a newer tree
// of (a parse of theirs came first).
fn (mut c TreeCache) take_seeds() {
	for c.seeding.len > 0 {
		mut seeded := SeededTree{}
		if c.seeded.try_pop(mut seeded) != .success {
			return
		}
		c.seeding.delete(seeded.key)
		if isnil(seeded.tree) {
			continue
		}
		if seeded.key in c.entries {
			C.ts_tree_delete(seeded.tree)
			continue
		}
		c.keep(seeded.key, seeded.text, seeded.tree, seeded.lang)
	}
}

// enabled: the cache keeps trees (not VESLINT_INCREMENTAL=0).
pub fn (c &TreeCache) enabled() bool {
	return !c.off
}

// owns: `tree` is one of the cache's.
pub fn (c &TreeCache) owns(tree &C.TSTree) bool {
	for _, entry in c.entries {
		if voidptr(entry.tree) == voidptr(tree) {
			return true
		}
	}
	return false
}

// forget frees the tree of `key`.
pub fn (mut c TreeCache) forget(key string) {
	entry := c.entries[key] or { return }
	C.ts_tree_delete(entry.tree)
	c.entries.delete(key)
	c.order = c.order.filter(it != key)
}

// clear frees every tree.
pub fn (mut c TreeCache) clear() {
	for _, entry in c.entries {
		C.ts_tree_delete(entry.tree)
	}
	c.entries = map[string]CachedTree{}
	c.order = []
}

// tree_has_error: the rows have an ERROR or a MISSING node.
pub fn tree_has_error(rows &C.vt_rows) bool {
	return C.vt_rows_has_error(rows)
}

// identifiers returns, in order of appearance, the identifiers of the rows: the declared names
// (declared_names) or, with `all`, every `identifier` node.
pub fn (p &Parser) identifiers(rows &C.vt_rows, src string, all bool) ![]Ident {
	root := C.vt_rows_root(rows)
	mut idents := if all { all_identifiers(root, src) } else { declared_names(root, src) }
	idents.sort(a.start_byte < b.start_byte)
	return idents
}

// The declared names of PROMPT.md §3.2: the identifier that is the field of each of these parents
// (what the query `(variable_declarator name: (identifier) @name) (function_declaration name:
// (identifier) @name) (required_parameter pattern: (identifier) @name) (optional_parameter
// pattern: (identifier) @name)` captures).
const declared_name_parents = {
	'variable_declarator':  'name'
	'function_declaration': 'name'
	'required_parameter':   'pattern'
	'optional_parameter':   'pattern'
}

// declared_names gives, in preorder, the identifiers the declarations query captures.
fn declared_names(root C.vt_node, src string) []Ident {
	mut idents := []Ident{}
	language := C.vt_node_language(root)
	for node in nodes_of_kind(root, c'identifier') {
		parent := C.vt_node_parent(node)
		if C.vt_node_is_null(parent) {
			continue
		}
		field := declared_name_parents[node_kind(parent)] or { continue }
		id := C.vt_field_id(language, &char(field.str), u32(field.len))
		if C.vt_node_field(node) == id {
			idents << ident_from_node(node, src)
		}
	}
	return idents
}

fn all_identifiers(root C.vt_node, src string) []Ident {
	return nodes_of_kind(root, c'identifier').map(ident_from_node(it, src))
}

// What nodes_of_kind and nodes_of_kinds know of a symbol of the grammar, by its number (the
// grammars have fewer than symbol_states).
const symbol_states = 1024
const symbol_seen = u8(1)
const symbol_wanted = u8(2)
const symbol_skipped = u8(4)

// nodes_of_kind returns, in preorder (order of appearance), the named nodes of that kind under
// `root` (and `root` itself).
pub fn nodes_of_kind(root C.vt_node, kind &char) []C.vt_node {
	mut nodes := []C.vt_node{}
	rows := C.vt_node_rows(root)
	flat := C.vt_node_row(C.vt_node_at(rows, 0))
	last := int(C.vt_node_last(root))
	// What the kind of each symbol is, asked once per symbol.
	mut symbols := [symbol_states]u8{}
	for i in int(root.index) .. last + 1 {
		row := unsafe { &flat[i] }
		if row.flags & row_named == 0 {
			continue
		}
		symbol := int(row.symbol)
		mut state := if symbol < symbol_states { symbols[symbol] } else { u8(0) }
		if state == 0 {
			state = symbol_seen
			if unsafe { C.strcmp(C.vt_node_type(C.vt_node_at(rows, u32(i))), kind) } == 0 {
				state |= symbol_wanted
			}
			if symbol < symbol_states {
				symbols[symbol] = state
			}
		}
		if state & symbol_wanted != 0 {
			nodes << C.vt_node_at(rows, u32(i))
		}
	}
	return nodes
}

// nodes_of_kinds returns, in preorder, the named nodes of any of the `kinds`, without entering the
// subtrees of the `skip` kinds.
pub fn nodes_of_kinds(root C.vt_node, kinds []string, skip []string) []C.vt_node {
	mut nodes := []C.vt_node{}
	// The kind of a node is the name of its symbol in the grammar, so what a kind is in the two
	// lists is asked once for each symbol of the tree: most of the nodes of a file are visited
	// by every rule.
	mut symbols := [symbol_states]u8{}
	rows := C.vt_node_rows(root)
	flat := C.vt_node_row(C.vt_node_at(rows, 0))
	last := int(C.vt_node_last(root))
	// The subtree in preorder: a skipped node's subtree is jumped over.
	mut i := int(root.index)
	for i <= last {
		entry := unsafe { &flat[i] }
		symbol := int(entry.symbol)
		mut state := if symbol < symbol_states { symbols[symbol] } else { u8(0) }
		if state == 0 {
			kind := node_kind(C.vt_node_at(rows, u32(i)))
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
		if state & symbol_wanted != 0 && entry.flags & row_named != 0 {
			nodes << C.vt_node_at(rows, u32(i))
		}
		i = if state & symbol_skipped == 0 { i + 1 } else { int(entry.last) + 1 }
	}
	return nodes
}

// first_error_offset is where the first ERROR or MISSING node of the tree starts.
pub fn first_error_offset(root C.vt_node) int {
	first, last := flat_range(root)
	mut i := first
	for i <= last {
		node := flat_node(root, i)
		if C.vt_node_is_error(node) || C.vt_node_is_missing(node) {
			return node_start(node)
		}
		// Only the subtrees with an error are entered.
		i = if C.vt_node_has_error(node) { i + 1 } else { flat_last(root, i) + 1 }
	}
	return node_start(root)
}

// flat_range gives the places in its rows of `n` and of the last node of its subtree: its subtree
// is the rows between them, in preorder.
@[inline]
pub fn flat_range(n C.vt_node) (int, int) {
	return int(n.index), int(C.vt_node_last(n))
}

// flat_node is the node at a place of the rows of `of` (see flat_range).
@[inline]
pub fn flat_node(of C.vt_node, i int) C.vt_node {
	return C.vt_node_at(C.vt_node_rows(of), u32(i))
}

// flat_last is the place of the last node of the subtree of the node at place `i` of the rows of
// `of`.
@[inline]
pub fn flat_last(of C.vt_node, i int) int {
	return int(C.vt_node_last(C.vt_node_at(C.vt_node_rows(of), u32(i))))
}

// node_kind returns the tree-sitter node kind (`call_expression`, `&&`, `async`…). The string is
// the grammar's own, which lives as long as the program: it is not copied.
pub fn node_kind(n C.vt_node) string {
	return unsafe { tos2(&u8(C.vt_node_type(n))) }
}

pub fn node_start(n C.vt_node) int {
	return int(C.vt_node_start_byte(n))
}

pub fn node_end(n C.vt_node) int {
	return int(C.vt_node_end_byte(n))
}

// node_field returns the child with that field name, if any (field_cache.h: the id of the name is
// looked up once).
pub fn node_field(n C.vt_node, name string) ?C.vt_node {
	child := C.vt_node_child_by_field_name(n, &char(name.str), u32(name.len))
	if C.vt_node_is_null(child) {
		return none
	}
	return child
}

// named_children returns the named children, without comments.
pub fn named_children(n C.vt_node) []C.vt_node {
	count := int(C.vt_node_named_child_count(n))
	mut named := []C.vt_node{cap: count}
	if count == 0 {
		return named
	}
	rows := C.vt_node_rows(n)
	flat := C.vt_node_row(C.vt_node_at(rows, 0))
	mut child := n.index + 1
	for child != row_none {
		row := unsafe { &flat[child] }
		if row.flags & row_named != 0 {
			named << C.vt_node_at(rows, child)
		} else if row.last != child && C.vt_node_named_child_count(C.vt_node_at(rows, child)) > 0 {
			// An anonymous child with named children: ts_node_named_child counts those in its
			// place (vt_node_named_child), and the rules saw what it gives.
			named.clear()
			for i in 0 .. count {
				named << C.vt_node_named_child(n, u32(i))
			}
			break
		}
		child = row.next
	}
	mut kept := 0
	for i in 0 .. named.len {
		if node_kind(named[i]) != 'comment' {
			named[kept] = named[i]
			kept++
		}
	}
	named.trim(kept)
	return named
}

// children returns all the children, also the anonymous ones (`=>`, `async`…) and comments.
pub fn children(n C.vt_node) []C.vt_node {
	mut out := []C.vt_node{}
	mut child := C.vt_node_first_child(n)
	if C.vt_node_is_null(child) {
		return out
	}
	rows := C.vt_node_rows(n)
	flat := C.vt_node_row(C.vt_node_at(rows, 0))
	mut at := child.index
	for at != row_none {
		out << C.vt_node_at(rows, at)
		at = unsafe { flat[at].next }
	}
	return out
}

pub fn first_named_child(n C.vt_node) ?C.vt_node {
	named := named_children(n)
	if named.len == 0 {
		return none
	}
	return named[0]
}

// has_child_kind tells whether some child, also anonymous ones like `async`, is of that kind.
pub fn has_child_kind(n C.vt_node, kind string) bool {
	mut child := C.vt_node_first_child(n)
	for !C.vt_node_is_null(child) {
		if node_kind(child) == kind {
			return true
		}
		child = C.vt_node_next(child)
	}
	return false
}

fn ident_from_node(node C.vt_node, src string) Ident {
	start := int(C.vt_node_start_byte(node))
	end := int(C.vt_node_end_byte(node))
	point := C.vt_node_start_point(node)
	return Ident{
		text:       src[start..end]
		start_byte: start
		row:        int(point.row)
		col_bytes:  int(point.column)
	}
}

pub fn root_node(rows &C.vt_rows) C.vt_node {
	return C.vt_rows_root(rows)
}

pub fn next_sibling(n C.vt_node) ?C.vt_node {
	next := C.vt_node_next_sibling(n)
	if C.vt_node_is_null(next) {
		return none
	}
	return next
}

pub fn prev_sibling(n C.vt_node) ?C.vt_node {
	prev := C.vt_node_prev_sibling(n)
	if C.vt_node_is_null(prev) {
		return none
	}
	return prev
}

pub fn node_parent(n C.vt_node) ?C.vt_node {
	parent := C.vt_node_parent(n)
	if C.vt_node_is_null(parent) {
		return none
	}
	return parent
}

// TokenEnds are, in order, the ends of the tokens of a tree: the leaves that are not comments
// (extras), nor the leading `#!`, nor zero-width (automatic `;`, MISSING nodes). For TypeScript all
// of that is trivia; this index gives the bounds of a node as TypeScript sees them, even when
// tree-sitter puts a trailing comment in the node (it happens without `;`).
pub struct TokenEnds {
pub:
	ends []int
}

// token_ends walks the subtree of `root` once.
pub fn token_ends(root C.vt_node) TokenEnds {
	mut ends := []int{}
	rows := C.vt_node_rows(root)
	flat := C.vt_node_row(C.vt_node_at(rows, 0))
	last := int(C.vt_node_last(root))
	mut i := int(root.index)
	for i <= last {
		row := unsafe { &flat[i] }
		node := C.vt_node_at(rows, u32(i))
		if row.flags & row_extra != 0 {
			// A comment: neither a token nor entered.
			i = int(row.last) + 1
			continue
		}
		// The children of a JSX element have no leading trivia for TypeScript: the white space
		// between them is JsxText, also the one with line breaks, which tree-sitter skips. So the
		// start of each child counts as the end of a token.
		if unsafe { C.strncmp(C.vt_node_type(node), c'jsx_', 4) } == 0 && row.parent != row_none {
			parent := C.vt_node_at(rows, row.parent)
			if unsafe { C.strcmp(C.vt_node_type(parent), c'jsx_element') } == 0
				&& row.start_byte > unsafe { flat[row.parent].start_byte } {
				ends << int(row.start_byte)
			}
		}
		if int(row.last) == i && row.end_byte > row.start_byte
			&& unsafe { C.strcmp(C.vt_node_type(node), c'hash_bang_line') } != 0 {
			ends << int(row.end_byte)
		}
		i++
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

pub fn position_of(node C.vt_node) Ident {
	point := C.vt_node_start_point(node)
	return Ident{
		start_byte: node_start(node)
		row:        int(point.row)
		col_bytes:  int(point.column)
		end_byte:   node_end(node)
		node_end:   true
	}
}
