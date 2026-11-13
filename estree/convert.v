module estree

import treesitter { node_end, node_kind, node_start }

fn C.ts_tree_cursor_reset(self &C.TSTreeCursor, node C.TSNode)
fn C.ts_tree_cursor_current_field_id(self &C.TSTreeCursor) u16
fn C.ts_node_language(self C.TSNode) &C.TSLanguage
fn C.ts_language_symbol_count(self &C.TSLanguage) u32
fn C.ts_language_field_count(self &C.TSLanguage) u32
fn C.ts_language_field_name_for_id(self &C.TSLanguage, id u16) &char

// Options of a conversion.
pub struct Options {
pub:
	// regexp_valid tells whether V8 accepts a regular expression (`new RegExp(pattern, flags)`
	// does not throw): the value of the Literal is then a RegExp, else null. The pattern is the
	// source text between the slashes. Without it every regular expression is taken as valid.
	regexp_valid ?fn (pattern string, flags string) bool
	// module makes the file a module whatever it contains, as typescript-estree does with
	// `sourceType: 'module'` (what ESLint passes by default) or for a .mts file: the Program's
	// sourceType is then `module`, and `await` at the top level is always an await expression.
	// Without it, the file is a module when TypeScript finds an import or an export at the top
	// level, or `import.meta`.
	module bool
	// allow_errors converts a tree with ERROR or MISSING nodes as well as it can (the result is
	// then no typescript-estree tree).
	allow_errors bool
}

// convert builds the ESTree of a file from its tree-sitter tree: `src` is the parsed text (without
// BOM), `tsx` tells that it was parsed with the tsx dialect (the tree already reflects it). A tree
// with ERROR or MISSING nodes is an error (Options.allow_errors converts it anyway). The strings
// of the result may point into `src`.
pub fn convert(root C.TSNode, src string, tsx bool) !EsTree {
	return convert_with(root, src, tsx, Options{})
}

// convert_with is convert with options.
pub fn convert_with(root C.TSNode, src string, tsx bool, opts Options) !EsTree {
	if !opts.allow_errors && C.ts_node_has_error(root) {
		return error('the tree has syntax errors (ERROR or MISSING nodes)')
	}
	lang := C.ts_node_language(root)
	mut c := Converter{
		src:         src
		tsx:         tsx
		opts:        opts
		cursor:      C.ts_tree_cursor_new(root)
		kind_names:  []string{len: int(C.ts_language_symbol_count(lang))}
		field_names: []string{len: int(C.ts_language_field_count(lang)) + 1}
	}
	for id in 1 .. c.field_names.len {
		name := C.ts_language_field_name_for_id(lang, u16(id))
		if !isnil(name) {
			c.field_names[id] = unsafe { tos2(&u8(name)) }
		}
	}
	c.comment_ends = line_comment_ends(src)
	defer {
		C.ts_tree_cursor_delete(&c.cursor)
	}
	c.t.root = c.program(root)
	c.t.src = src
	c.t.line_starts, c.t.line_units = line_index(src)
	return c.t
}

struct Converter {
	src  string
	tsx  bool // unused: the dialect only matters to tree-sitter
	opts Options
mut:
	t      EsTree
	cursor C.TSTreeCursor
	// The kind of each symbol of the grammar (filled when first seen) and the name of each
	// field.
	kind_names  []string
	field_names []string
	// comment_ends are, in order, where the `//` comments (or HTML-like ones) of the text may
	// end (see line_comment_ends).
	comment_ends []int
	// await_ctx: `await` starts an await expression (TypeScript's AwaitContext): in an async
	// function, a class static block or at the top level of a module.
	await_ctx bool
	// The node that an `await` used as an identifier applies to (see await_identifier).
	sub_start int = -1
	sub_kind  string
	sub_await C.TSNode
}

// Kid is a child of a tree-sitter node (comments and other extras left out).
struct Kid {
	n     C.TSNode
	kind  string
	field string
	named bool
}

fn (k Kid) is_tok(tok string) bool {
	return !k.named && k.kind == tok && node_end(k.n) > node_start(k.n)
}

fn (mut c Converter) kids(n C.TSNode) []Kid {
	C.ts_tree_cursor_reset(&c.cursor, n)
	mut out := []Kid{cap: int(C.ts_node_child_count(n))}
	if !C.ts_tree_cursor_goto_first_child(&c.cursor) {
		return out
	}
	for {
		k := C.ts_tree_cursor_current_node(&c.cursor)
		if !C.ts_node_is_extra(k) {
			out << Kid{
				n:     k
				kind:  c.kind_name(k)
				field: c.field_names[C.ts_tree_cursor_current_field_id(&c.cursor)]
				named: C.ts_node_is_named(k)
			}
		}
		if !C.ts_tree_cursor_goto_next_sibling(&c.cursor) {
			break
		}
	}
	return out
}

// kind_name is node_kind with a cache per symbol.
fn (mut c Converter) kind_name(n C.TSNode) string {
	symbol := int(C.ts_node_symbol(n))
	if symbol < c.kind_names.len {
		name := c.kind_names[symbol]
		if name.len > 0 {
			return name
		}
		kind := node_kind(n)
		c.kind_names[symbol] = kind
		return kind
	}
	return node_kind(n)
}

// named are the named children (no comments).
fn (mut c Converter) named(n C.TSNode) []Kid {
	return c.kids(n).filter(it.named)
}

fn (mut c Converter) field(n C.TSNode, name string) ?Kid {
	for k in c.kids(n) {
		if k.field == name {
			return k
		}
	}
	return none
}

fn field_of(kids []Kid, name string) ?Kid {
	for k in kids {
		if k.field == name {
			return k
		}
	}
	return none
}

fn fields_of(kids []Kid, name string) []Kid {
	return kids.filter(it.field == name)
}

fn has_tok(kids []Kid, tok string) bool {
	for k in kids {
		if k.is_tok(tok) {
			return true
		}
	}
	return false
}

fn tok_of(kids []Kid, tok string) ?Kid {
	for k in kids {
		if k.is_tok(tok) {
			return k
		}
	}
	return none
}

fn first_named(kids []Kid) ?Kid {
	for k in kids {
		if k.named {
			return k
		}
	}
	return none
}

fn kind_of(n C.TSNode) string {
	return node_kind(n)
}

fn (c &Converter) start(n C.TSNode) int {
	return node_start(n)
}

// end is the end of the last token of the node: tree-sitter may end a node after a comment (when
// its last child is an automatic `;`, which has no width).
fn (c &Converter) end(n C.TSNode) int {
	e := node_end(n)
	if c.may_end_in_comment(e) {
		return c.last_token_end(n)
	}
	return e
}

// may_end_in_comment: the text before `e` may be a comment: it ends with `*/`, or a `//` (or
// `-->`, `<!--`) comment may end at `e`. It is a quick filter for end.
fn (c &Converter) may_end_in_comment(e int) bool {
	if e >= 2 && unsafe { c.src.str[e - 1] } == `/` && unsafe { c.src.str[e - 2] } == `*` {
		return true
	}
	// Binary search in comment_ends.
	mut lo := 0
	mut hi := c.comment_ends.len
	for lo < hi {
		mid := (lo + hi) / 2
		if c.comment_ends[mid] < e {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo < c.comment_ends.len && c.comment_ends[lo] == e
}

// line_comment_ends finds, from the text alone, where a comment that runs to the end of its line
// may end: after each `//`, `<!--` or `-->`, the next line terminator (or the end of the text). A
// `//` in a string or a regular expression adds a place that is not one, which only makes end
// look at the tree.
fn line_comment_ends(src string) []int {
	mut out := []int{}
	mut i := 0
	for i + 1 < src.len {
		ch := unsafe { src.str[i] }
		next := unsafe { src.str[i + 1] }
		if (ch == `/` && next == `/`) || (ch == `-` && next == `-` && i + 2 < src.len
			&& unsafe { src.str[i + 2] } == `>`) || (ch == `<` && next == `!`) {
			mut j := i + 2
			for j < src.len {
				b := unsafe { src.str[j] }
				if b == `\n` || b == `\r` {
					break
				}
				// U+2028 and U+2029 end a line too.
				if b == 0xe2 && j + 2 < src.len && unsafe { src.str[j + 1] } == 0x80
					&& (unsafe { src.str[j + 2] } == 0xa8 || unsafe { src.str[j + 2] } == 0xa9) {
					break
				}
				j++
			}
			if out.len == 0 || out.last() != j {
				out << j
			}
			i = j
			continue
		}
		i++
	}
	return out
}

// last_token_end is the end of the last child that is neither an extra (a comment) nor without
// width, down to a leaf.
fn (c &Converter) last_token_end(n C.TSNode) int {
	count := int(C.ts_node_child_count(n))
	if count == 0 {
		return node_end(n)
	}
	for k := count - 1; k >= 0; k-- {
		child := C.ts_node_child(n, u32(k))
		if C.ts_node_is_extra(child) || node_end(child) == node_start(child) {
			continue
		}
		return c.last_token_end(child)
	}
	return node_start(n)
}

fn (c &Converter) text(n C.TSNode) string {
	return c.slice(node_start(n), node_end(n))
}

fn (c &Converter) slice(start int, end int) string {
	return c.src.substr_unsafe(start, end)
}

// --- Node building ---

fn (mut c Converter) mk(typ NodeType, n C.TSNode, start int, end int) int {
	c.t.nodes << EsNode{
		typ:    typ
		start:  start
		end:    end
		ts:     n
		has_ts: true
		props:  []Prop{cap: int(prop_caps[int(typ)])}
	}
	return c.t.nodes.len - 1
}

fn (mut c Converter) mkn(typ NodeType, n C.TSNode) int {
	return c.mk(typ, n, c.start(n), c.end(n))
}

fn (mut c Converter) pbool(i int, key Key, b bool) {
	c.t.nodes[i].props << Prop{
		key:  key
		kind: .bool
		b:    b
	}
}

fn (mut c Converter) pstr(i int, key Key, s string) {
	c.t.nodes[i].props << Prop{
		key:  key
		kind: .string
		str:  s
	}
}

fn (mut c Converter) pnull(i int, key Key) {
	c.t.nodes[i].props << Prop{
		key:  key
		kind: .null
	}
}

// pnode sets a node property (null when child < 0).
fn (mut c Converter) pnode(i int, key Key, child int) {
	if child < 0 {
		c.pnull(i, key)
		return
	}
	c.t.nodes[child].parent = i
	c.t.nodes[i].props << Prop{
		key:  key
		kind: .node
		idx:  child
	}
}

// popt sets a node property only when there is a node (`undefined` otherwise).
fn (mut c Converter) popt(i int, key Key, child int) {
	if child >= 0 {
		c.pnode(i, key, child)
	}
}

fn (mut c Converter) plist(i int, key Key, items []int) {
	for item in items {
		if item >= 0 {
			c.t.nodes[item].parent = i
		}
	}
	c.t.lists << items
	c.t.nodes[i].props << Prop{
		key:  key
		kind: .list
		idx:  c.t.lists.len - 1
	}
}

fn (mut c Converter) set_bool_prop(i int, key Key, b bool) {
	for k, p in c.t.nodes[i].props {
		if p.key == key {
			c.t.nodes[i].props[k] = Prop{
				key:  key
				kind: .bool
				b:    b
			}
			return
		}
	}
	c.pbool(i, key, b)
}

fn (mut c Converter) set_list_prop(i int, key Key, items []int) {
	for k, p in c.t.nodes[i].props {
		if p.key == key {
			for item in items {
				if item >= 0 {
					c.t.nodes[item].parent = i
				}
			}
			c.t.lists << items
			c.t.nodes[i].props[k] = Prop{
				key:  key
				kind: .list
				idx:  c.t.lists.len - 1
			}
			return
		}
	}
	c.plist(i, key, items)
}

fn (c &Converter) prop_bool(i int, key Key) bool {
	for p in c.t.nodes[i].props {
		if p.key == key && p.kind == .bool {
			return p.b
		}
	}
	return false
}

// extend_end makes the node end at `end` when that is later (fixParentLocation).
fn (mut c Converter) extend(i int, start int, end int) {
	if start < c.t.nodes[i].start {
		c.t.nodes[i].start = start
	}
	if end > c.t.nodes[i].end {
		c.t.nodes[i].end = end
	}
}

// ident creates an Identifier.
fn (mut c Converter) ident_at(n C.TSNode, start int, end int, name string) int {
	i := c.mk(.identifier, n, start, end)
	c.plist(i, .decorators, [])
	c.pstr(i, .name, name)
	c.pbool(i, .optional, false)
	return i
}

fn (mut c Converter) ident(n C.TSNode) int {
	return c.ident_at(n, c.start(n), c.end(n), identifier_name(c.text(n)))
}

// --- Program and statements ---

fn (mut c Converter) program(root C.TSNode) int {
	kids := c.kids(root)
	mut stmts := []C.TSNode{}
	for k in kids {
		if k.named && k.kind != 'hash_bang_line' {
			stmts << k.n
		}
	}
	start := if stmts.len > 0 { c.start(stmts[0]) } else { c.src.len }
	i := c.mk(.program, root, start, c.src.len)
	is_module := c.opts.module || c.is_module(root, stmts)
	c.await_ctx = is_module
	body := c.body(stmts, true)
	c.plist(i, .body, body)
	c.pstr(i, .source_type, if is_module { 'module' } else { 'script' })
	return i
}

// is_module ports TypeScript's isFileProbablyExternalModule: an import or export at the top
// level, or `import.meta` anywhere.
fn (mut c Converter) is_module(root C.TSNode, stmts []C.TSNode) bool {
	for s in stmts {
		match kind_of(s) {
			'export_statement', 'import_statement' {
				return true
			}
			else {}
		}
	}
	// `import.meta` anywhere (the text filter spares a walk of the tree).
	if !c.src.contains('meta') {
		return false
	}
	return treesitter.nodes_of_kind(root, c'meta_property').any(c.text(it).starts_with('import'))
}

// body converts a list of statements; with `directives`, the leading string expression
// statements are directives.
fn (mut c Converter) body(stmts []C.TSNode, directives bool) []int {
	mut out := []int{cap: stmts.len}
	mut allow := directives
	// The previous statement is kept in a variable, not read as stmts[k - 1]: with -prod, gcc
	// may then keep only a pointer before the array's data, which the collector does not see
	// as a reference to it (v-bugs/README.md).
	mut prev := ?C.TSNode(none)
	for s in stmts {
		before := out.len
		// `declare module 'x';`: the `;` is part of the declaration, not an empty statement.
		mut absorbed := false
		if p := prev {
			absorbed = kind_of(s) == 'empty_statement' && c.absorbs_semicolon(p)
		}
		prev = s
		if absorbed {
			if before > 0 {
				last := out[before - 1]
				c.t.nodes[last].end = c.end(s)
				c.absorb_into_inner(last, c.end(s))
			}
			continue
		}
		c.statement(s, mut out)
		if allow {
			for idx in out[before..] {
				if c.t.nodes[idx].typ == .expression_statement && c.is_directive(s) {
					raw := c.text(c.named(s)[0].n)
					c.pstr(idx, .directive, raw[1..raw.len - 1])
				} else {
					allow = false
				}
			}
		}
	}
	return out
}

fn (mut c Converter) is_directive(s C.TSNode) bool {
	if kind_of(s) != 'expression_statement' {
		return false
	}
	named := c.named(s)
	return named.len == 1 && named[0].kind == 'string'
}

// absorbs_semicolon: a module declaration without body, after which tree-sitter puts the `;` in an
// empty statement while TypeScript ends the declaration with it.
fn (mut c Converter) absorbs_semicolon(prev C.TSNode) bool {
	mut n := prev
	for {
		match kind_of(n) {
			'ambient_declaration', 'export_statement' {
				kids := c.kids(n)
				if has_tok(kids, ';') {
					return false
				}
				inner := c.last_named(kids) or { return false }
				n = inner.n
			}
			'module', 'internal_module' {
				kids := c.kids(n)
				return field_of(kids, 'body') == none && c.end(n) == node_end(n)
			}
			else {
				return false
			}
		}
	}
	return false
}

fn (mut c Converter) last_named(kids []Kid) ?Kid {
	for k := kids.len - 1; k >= 0; k-- {
		if kids[k].named {
			return kids[k]
		}
	}
	return none
}

// absorb_into_inner extends the declaration that an ExportNamedDeclaration wraps.
fn (mut c Converter) absorb_into_inner(i int, end int) {
	if c.t.nodes[i].typ == .export_named_declaration {
		if decl := c.t.node(i, .declaration) {
			c.t.nodes[decl].end = end
		}
	}
}

fn (mut c Converter) statement(s C.TSNode, mut out []int) {
	kind := kind_of(s)
	match kind {
		'expression_statement' {
			kids := c.kids(s)
			inner := first_named(kids) or { return }
			if inner.kind == 'internal_module' {
				out << c.module_decl(inner.n, Ctx{})
				if semi := tok_of(kids, ';') {
					out << c.mkn(.empty_statement, semi.n)
				}
				return
			}
			i := c.mkn(.expression_statement, s)
			c.pnode(i, .expression, c.expr(inner.n))
			out << i
		}
		'hash_bang_line' {}
		'export_statement' {
			c.export_stmt(s, mut out)
		}
		else {
			out << c.stmt(s)
		}
	}
}

// stmt converts a statement that is one ESTree node.
fn (mut c Converter) stmt(s C.TSNode) int {
	kind := kind_of(s)
	match kind {
		'expression_statement' {
			mut out := []int{}
			c.statement(s, mut out)
			return if out.len > 0 { out[0] } else { -1 }
		}
		'empty_statement' {
			return c.mkn(.empty_statement, s)
		}
		'debugger_statement' {
			return c.mkn(.debugger_statement, s)
		}
		'statement_block' {
			return c.block(s, false)
		}
		'lexical_declaration', 'variable_declaration' {
			return c.var_decl(s, Ctx{})
		}
		'if_statement' {
			kids := c.kids(s)
			i := c.mkn(.if_statement, s)
			mut alt := -1
			if e := field_of(kids, 'alternative') {
				if inner := first_named(c.kids(e.n)) {
					alt = c.stmt(inner.n)
				}
			}
			c.pnode(i, .alternate, alt)
			c.pnode(i, .consequent, c.stmt(field_of(kids, 'consequence') or { return i }.n))
			c.pnode(i, .test, c.expr(field_of(kids, 'condition') or { return i }.n))
			return i
		}
		'switch_statement' {
			kids := c.kids(s)
			i := c.mkn(.switch_statement, s)
			mut cases := []int{}
			if body := field_of(kids, 'body') {
				for k in c.named(body.n) {
					cases << c.switch_case(k.n)
				}
			}
			c.plist(i, .cases, cases)
			c.pnode(i, .discriminant, c.expr(field_of(kids, 'value') or { return i }.n))
			return i
		}
		'for_statement' {
			return c.for_stmt(s)
		}
		'for_in_statement' {
			return c.for_in(s)
		}
		'while_statement' {
			kids := c.kids(s)
			i := c.mkn(.while_statement, s)
			c.pnode(i, .body, c.stmt(field_of(kids, 'body') or { return i }.n))
			c.pnode(i, .test, c.expr(field_of(kids, 'condition') or { return i }.n))
			return i
		}
		'do_statement' {
			kids := c.kids(s)
			i := c.mkn(.do_while_statement, s)
			c.pnode(i, .body, c.stmt(field_of(kids, 'body') or { return i }.n))
			c.pnode(i, .test, c.expr(field_of(kids, 'condition') or { return i }.n))
			return i
		}
		'with_statement' {
			kids := c.kids(s)
			i := c.mkn(.with_statement, s)
			c.pnode(i, .body, c.stmt(field_of(kids, 'body') or { return i }.n))
			c.pnode(i, .object, c.expr(field_of(kids, 'object') or { return i }.n))
			return i
		}
		'return_statement', 'throw_statement' {
			i := c.mkn(if kind == 'return_statement' {
				NodeType.return_statement
			} else {
				NodeType.throw_statement
			}, s)
			arg := first_named(c.kids(s)) or {
				c.pnull(i, .argument)
				return i
			}
			c.pnode(i, .argument, c.expr(arg.n))
			return i
		}
		'break_statement', 'continue_statement' {
			i := c.mkn(if kind == 'break_statement' {
				NodeType.break_statement
			} else {
				NodeType.continue_statement
			}, s)
			if label := c.field(s, 'label') {
				c.pnode(i, .label, c.ident(label.n))
			} else {
				c.pnull(i, .label)
			}
			return i
		}
		'labeled_statement' {
			kids := c.kids(s)
			i := c.mkn(.labeled_statement, s)
			c.pnode(i, .body, c.stmt(field_of(kids, 'body') or { return i }.n))
			c.pnode(i, .label, c.ident(field_of(kids, 'label') or { return i }.n))
			return i
		}
		'try_statement' {
			kids := c.kids(s)
			i := c.mkn(.try_statement, s)
			c.pnode(i, .block, c.block(field_of(kids, 'body') or { return i }.n, false))
			mut fin := -1
			if f := field_of(kids, 'finalizer') {
				if b := c.field(f.n, 'body') {
					fin = c.block(b.n, false)
				}
			}
			c.pnode(i, .finalizer, fin)
			mut handler := -1
			if h := field_of(kids, 'handler') {
				handler = c.catch_clause(h.n)
			}
			c.pnode(i, .handler, handler)
			return i
		}
		else {
			return c.decl(s, Ctx{})
		}
	}
}

fn (mut c Converter) block(s C.TSNode, directives bool) int {
	i := c.mkn(.block_statement, s)
	c.plist(i, .body, c.body(c.named(s).map(it.n), directives))
	return i
}

fn (mut c Converter) switch_case(n C.TSNode) int {
	kids := c.kids(n)
	i := c.mkn(.switch_case, n)
	c.plist(i, .consequent, c.body(fields_of(kids, 'body').map(it.n), false))
	if v := field_of(kids, 'value') {
		c.pnode(i, .test, c.expr(v.n))
	} else {
		c.pnull(i, .test)
	}
	return i
}

fn (mut c Converter) catch_clause(n C.TSNode) int {
	kids := c.kids(n)
	i := c.mkn(.catch_clause, n)
	c.pnode(i, .body, c.block(field_of(kids, 'body') or { return i }.n, false))
	if p := field_of(kids, 'parameter') {
		id := c.pattern(p.n)
		if t := field_of(kids, 'type') {
			c.annotate(id, t.n)
		}
		c.pnode(i, .param, id)
	} else {
		c.pnull(i, .param)
	}
	return i
}

// annotate gives a binding name its type annotation and extends it over it.
fn (mut c Converter) annotate(id int, annotation C.TSNode) {
	ta := c.type_annotation(annotation)
	c.pnode(id, .type_annotation, ta)
	c.extend(id, c.t.nodes[ta].start, c.t.nodes[ta].end)
}

fn (mut c Converter) for_stmt(s C.TSNode) int {
	kids := c.kids(s)
	i := c.mkn(.for_statement, s)
	c.pnode(i, .body, c.stmt(field_of(kids, 'body') or { return i }.n))
	mut init := -1
	if k := field_of(kids, 'initializer') {
		match k.kind {
			'lexical_declaration', 'variable_declaration' {
				init = c.var_decl(k.n, Ctx{
					for_init: true
				})
			}
			'empty_statement' {}
			else {
				init = c.expr(k.n)
			}
		}
	}
	c.pnode(i, .init, init)
	mut test := -1
	for k in fields_of(kids, 'condition') {
		if k.named && k.kind != 'empty_statement' {
			test = c.expr(k.n)
		}
	}
	c.pnode(i, .test, test)
	mut update := -1
	if k := field_of(kids, 'increment') {
		update = c.expr(k.n)
	}
	c.pnode(i, .update, update)
	return i
}

fn (mut c Converter) for_in(s C.TSNode) int {
	kids := c.kids(s)
	op := field_of(kids, 'operator') or { return -1 }
	is_of := op.kind == 'of'
	i := c.mkn(if is_of { NodeType.for_of_statement } else { NodeType.for_in_statement }, s)
	if is_of {
		// `for await (`: an `await` before the `(`, not the `await` of `await using`.
		mut awaited := false
		for k in kids {
			if k.is_tok('(') {
				break
			}
			if k.is_tok('await') && k.field == '' {
				awaited = true
			}
		}
		c.pbool(i, .await_, awaited)
	}
	c.pnode(i, .body, c.stmt(field_of(kids, 'body') or { return i }.n))
	left := field_of(kids, 'left') or { return i }
	kinds := fields_of(kids, 'kind')
	if kinds.len > 0 {
		kind := kinds.map(it.kind).join(' ')
		id := c.pattern(left.n)
		mut dend := c.end(left.n)
		value := field_of(kids, 'value')
		if v := value {
			dend = c.end(v.n)
		}
		declarator := c.mk(.variable_declarator, left.n, c.start(left.n), dend)
		c.pbool(declarator, .definite, false)
		c.pnode(declarator, .id, id)
		if v := value {
			c.pnode(declarator, .init, c.expr(v.n))
		} else {
			c.pnull(declarator, .init)
		}
		decl := c.mk(.variable_declaration, kinds[0].n, c.start(kinds[0].n), dend)
		c.plist(decl, .declarations, [declarator])
		c.pbool(decl, .declare_, false)
		c.pstr(decl, .kind, kind)
		c.pnode(i, .left, decl)
	} else {
		c.pnode(i, .left, c.pattern(left.n))
	}
	c.pnode(i, .right, c.expr(field_of(kids, 'right') or { return i }.n))
	return i
}

// Ctx is what a declaration gets from what wraps it: `declare`, `export` or `export default`.
struct Ctx {
	declare  bool
	start    int = -1 // the start of the ESTree node when it is not the tree-sitter node's
	for_init bool // a declaration in the init of a `for`: it ends at its last declarator
	exported bool // `export default`: a nameless function or class is a declaration
}

fn (c Ctx) start_or(n int) int {
	return if c.start >= 0 { c.start } else { n }
}

fn (mut c Converter) var_decl(s C.TSNode, ctx Ctx) int {
	kids := c.kids(s)
	kinds := fields_of(kids, 'kind')
	kind := if kinds.len > 0 { kinds.map(it.kind).join(' ') } else { 'var' }
	declarators := kids.filter(it.kind == 'variable_declarator')
	mut end := c.end(s)
	if ctx.for_init && declarators.len > 0 {
		end = c.end(declarators.last().n)
	}
	i := c.mk(.variable_declaration, s, ctx.start_or(c.start(s)), end)
	mut list := []int{}
	for d in declarators {
		list << c.declarator(d.n)
	}
	c.plist(i, .declarations, list)
	c.pbool(i, .declare_, ctx.declare)
	c.pstr(i, .kind, kind)
	return i
}

fn (mut c Converter) declarator(d C.TSNode) int {
	kids := c.kids(d)
	i := c.mkn(.variable_declarator, d)
	c.pbool(i, .definite, has_tok(kids, '!'))
	id := c.pattern(field_of(kids, 'name') or { return i }.n)
	if t := field_of(kids, 'type') {
		c.annotate(id, t.n)
	}
	c.pnode(i, .id, id)
	if v := field_of(kids, 'value') {
		c.pnode(i, .init, c.expr(v.n))
	} else {
		c.pnull(i, .init)
	}
	return i
}
