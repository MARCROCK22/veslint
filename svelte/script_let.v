module svelte

import estree
import treesitter

fn C.ts_node_is_error(self C.TSNode) bool
fn C.ts_node_is_missing(self C.TSNode) bool
fn C.ts_node_has_error(self C.TSNode) bool

// The script side of a Svelte document: the pre-virtual code parsed by tree-sitter, its ESTree
// and tokens, and ScriptLetContext.restore — the template expressions taken out of it and put
// back in the Svelte AST with file offsets (src/context/script-let.ts restoreNodes), the
// tokens merged and the gaps filled (src/parser/index.ts extractTokens), the script statements
// given to the script elements.

// map_pos maps a byte offset of a let's text to the file through its segments (`end`: the
// offset ends a range). Outside every segment, the first segment's shift.
fn map_pos(p int, segs []Segment, end bool) int {
	for s in segs {
		if (!end && s.pre_start <= p && p < s.pre_start + s.len)
			|| (end && s.pre_start < p && p <= s.pre_start + s.len) {
			return p - s.pre_start + s.file_start
		}
	}
	if segs.len == 0 {
		return p
	}
	s := segs[0]
	return p - s.pre_start + s.file_start
}

// remap moves a subtree of `pre` to the file through segments.
fn (mut c Conv) remap(node int, segs []Segment) {
	if node < 0 {
		return
	}
	mut stack := [node]
	for stack.len > 0 {
		n := stack.pop()
		mut en := &c.doc.es.nodes[n]
		start := map_pos(en.start, segs, false)
		end := if en.end == en.start { start } else { map_pos(en.end, segs, true) }
		en.start = start
		en.end = end
		for ch in c.doc.es.children(n) {
			stack << ch
		}
	}
}

fn (c &Conv) es_node(i int, key estree.Key) int {
	if i < 0 {
		return -1
	}
	return c.doc.es.node(i, key) or { -1 }
}

fn (c &Conv) es_list(i int, key estree.Key) []int {
	if i < 0 {
		return []int{}
	}
	return c.doc.es.list(i, key) or { []int{} }
}

fn (mut c Conv) drop_prop(i int, key estree.Key) {
	mut props := c.doc.es.nodes[i].props.clone()
	props = props.filter(it.key != key)
	c.doc.es.nodes[i].props = props
}

// restore parses the pre-virtual code and builds everything that comes from the script parser.
fn (mut c Conv) restore() ! {
	mut doc := c.doc
	pre := c.pre_code()
	doc.pre = pre
	doc.pre_u16 = c.pre_code_u16()
	if c.started {
		doc.separator = c.trimmed_len
		prefix := if c.trimmed_len + 2 > c.code.len { c.trimmed_len + 2 } else { c.code.len }
		doc.lets_index = new_text_index(pre[prefix..])
	}
	tree := parse_ts(c.parsers.ts, pre)!
	doc.tree = tree
	root := treesitter.root_node(tree)
	if C.ts_node_has_error(root) {
		c.syntax_error(root)
		return
	}
	es := convert_es(root, pre) or {
		doc.error = ParseError{
			message:    'Parsing error.'
			index:      0
			ts_message: true
			pre_index:  0
		}
		return
	}
	doc.es = es
	pre_starts := doc.es.nodes.map(it.start)
	toks, comms := snippet_tokens(root, pre, false)
	c.build_virtual(toks, comms)
	first_let := if c.lets.len > 0 { c.lets[0].start } else { pre.len + 1 }
	sep := c.trimmed_len
	// Script tokens and comments (before the first let, without the separator `;`).
	for t in toks {
		if t.start >= first_let {
			break
		}
		if c.started && t.start == sep + 1 && pre[t.start] == `;` {
			continue
		}
		doc.tokens << Token{
			typ:   t.typ
			start: t.start
			end:   t.end
			value: token_value(pre, t)
		}
	}
	for t in comms {
		if t.start >= first_let {
			break
		}
		doc.comments << comment_token(pre, t, t.start, t.end)
	}
	// Match each let to its statement, in order of a pre-order walk.
	mut matched := []int{len: c.lets.len, init: -1}
	mut k := 0
	mut stack := [doc.es.root]
	for stack.len > 0 {
		n := stack.pop()
		en := doc.es.nodes[n]
		// A last script statement that took the separator ends before it again.
		if c.started && c.lets.len > 0 {
			mut e := en.end
			for e - 1 == sep || e - 1 == sep + 1 {
				e--
			}
			if e != en.end {
				doc.es.nodes[n].end = e
			}
		}
		if k < c.lets.len && c.lets[k].node_type == en.typ.type_name() && c.lets[k].start <= en.start
			&& en.end <= c.lets[k].end {
			matched[k] = n
			k++
		}
		kids := doc.es.children(n)
		for i := kids.len - 1; i >= 0; i-- {
			stack << kids[i]
		}
	}
	c.merge_generics()
	for i, l in c.lets {
		c.lets[i].matched = matched[i]
		c.restore_let(l, matched[i], toks, comms)
		if c.err != none {
			break
		}
	}
	if e := c.err {
		doc.error = e
		return
	}
	for l in c.lets {
		for s in l.segments {
			doc.segments << s
		}
	}
	// The statements of the script.
	mut statements := []int{}
	for st in c.es_list(doc.es.root, .body) {
		if c.started && c.lets.len > 0 && doc.es.nodes[st].start >= sep {
			continue
		}
		statements << st
		// parseScriptInSvelte: a top-level `$:` statement is a SvelteReactiveStatement.
		if doc.es.nodes[st].typ == .labeled_statement {
			label := c.es_node(st, .label)
			if label >= 0 && (doc.es.string_of(label, .name) or { '' }) == '\$' {
				doc.reactive[st] = true
			}
		}
	}
	sort_tokens(mut doc.comments)
	sort_tokens(mut doc.tokens)
	c.extract_tokens()
	mut scripts := []int{}
	for b in doc.nodes[0].children {
		if doc.nodes[b].typ == .script_element {
			scripts << b
		}
	}
	mut si := 0
	for k2, script in scripts {
		sn := doc.nodes[script]
		for si < statements.len {
			st := doc.es.nodes[statements[si]]
			if sn.start <= st.start && (st.end <= sn.end || k2 == scripts.len - 1) {
				doc.nodes[script].body << statements[si]
				doc.es_parent[statements[si]] = script
				si++
				continue
			}
			break
		}
	}
	if si < statements.len {
		doc.error = ParseError{
			message: 'The script is unterminated'
			index:   doc.es.nodes[statements[si]].end
		}
		return
	}
	// The scopes of the lets' blocks.
	for i, l in c.lets {
		m := matched[i]
		if m < 0 {
			continue
		}
		c.lets[i].scope_node = match l.kind {
			.block_params, .each_block {
				mut call := c.es_node(m, .expression)
				if l.kind == .each_block {
					args := c.es_list(call, .arguments)
					call = if args.len > 0 { args[0] } else { -1 }
				}
				call
			}
			.if_block {
				c.es_node(m, .consequent)
			}
			else {
				m
			}
		}
	}
	typed := c.lets.filter(it.typed)
	an := c.an
	c.build_scope(&an, pre_starts, typed)
}

fn comment_token(src string, t SnipToken, start int, end int) Token {
	text := src[t.start..t.end]
	block := t.typ == 'Block'
	value := if block {
		text[2..text.len - 2]
	} else if text.starts_with('//') {
		text[2..]
	} else {
		// An HTML-like comment (`<!--`, `-->`).
		text
	}
	return Token{
		typ:   if block { 'Block' } else { 'Line' }
		start: start
		end:   end
		value: value
	}
}

fn sort_tokens(mut list []Token) {
	list.sort_with_compare(fn (a &Token, b &Token) int {
		if a.start != b.start {
			return a.start - b.start
		}
		return a.end - b.end
	})
}

// syntax_error records the error of a pre-virtual code tree-sitter rejects: a compiler error
// (acorn rejected the template expression) when the expression alone does not parse either,
// else typescript-eslint's error at the position in the pre-virtual code.
fn (mut c Conv) syntax_error(root C.TSNode) {
	at := first_error_offset(root)
	for l in c.lets {
		for s in l.segments {
			if s.pre_start <= at && at <= s.pre_start + s.len {
				// What the compiler read (acorn): the expression without the comments around.
				part := if l.core_start >= 0 {
					c.code[l.core_start..l.core_end]
				} else {
					c.code[s.file_start..s.file_start + s.len]
				}
				if !c.expression_parses(part) {
					c.doc.error = ParseError{
						message: 'Unexpected token\nhttps://svelte.dev/e/js_parse_error'
						index:   map_pos(at, l.segments, false)
						code:    'js_parse_error'
					}
					return
				}
			}
		}
	}
	c.doc.error = ParseError{
		message:    'Parsing error.'
		index:      if at < c.code.len { at } else { c.code.len }
		ts_message: true
		pre_index:  at
	}
}

fn (c &Conv) expression_parses(part string) bool {
	tree := parse_ts(c.parsers.ts, '(${part});') or { return false }
	defer {
		treesitter.tree_delete(tree)
	}
	return !C.ts_node_has_error(treesitter.root_node(tree))
}

fn first_error_offset(root C.TSNode) int {
	mut cursor := C.ts_tree_cursor_new(root)
	defer {
		C.ts_tree_cursor_delete(&cursor)
	}
	for {
		node := C.ts_tree_cursor_current_node(&cursor)
		if C.ts_node_is_error(node) || C.ts_node_is_missing(node) {
			return treesitter.node_start(node)
		}
		if C.ts_node_has_error(node) && C.ts_tree_cursor_goto_first_child(&cursor) {
			continue
		}
		for !C.ts_tree_cursor_goto_next_sibling(&cursor) {
			if !C.ts_tree_cursor_goto_parent(&cursor) {
				return treesitter.node_start(root)
			}
		}
	}
	return 0
}

// let_tokens adds the tokens and comments of a let's segments (moved to the file).
fn (mut c Conv) let_tokens(l ScriptLet, toks []SnipToken, comms []SnipToken) {
	pre := c.doc.pre
	for s in l.segments {
		lo := lower_bound_tokens(toks, s.pre_start)
		for i in lo .. toks.len {
			t := toks[i]
			if t.start >= s.pre_start + s.len {
				break
			}
			if t.end > s.pre_start + s.len {
				continue
			}
			mut inside_insertion := false
			for ins in l.insertions {
				if ins.pre_start <= t.start && t.end <= ins.pre_start + ins.len {
					inside_insertion = true
				}
			}
			if inside_insertion {
				continue
			}
			delta := s.file_start - s.pre_start
			c.doc.tokens << Token{
				typ:   t.typ
				start: t.start + delta
				end:   t.end + delta
				value: token_value(pre, t)
			}
		}
		lc := lower_bound_tokens(comms, s.pre_start)
		for i in lc .. comms.len {
			t := comms[i]
			if t.start >= s.pre_start + s.len {
				break
			}
			delta := s.file_start - s.pre_start
			c.doc.comments << comment_token(pre, t, t.start + delta, t.end + delta)
		}
	}
}

fn lower_bound_tokens(toks []SnipToken, p int) int {
	mut lo := 0
	mut hi := toks.len
	for lo < hi {
		mid := (lo + hi) / 2
		if toks[mid].start < p {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo
}

fn (mut c Conv) set_parent(es int, svelte_parent int) {
	if es >= 0 {
		c.doc.es_parent[es] = svelte_parent
	}
}

// restore_let puts back the nodes of one let (its RestoreCallback).
fn (mut c Conv) restore_let(l ScriptLet, m int, toks []SnipToken, comms []SnipToken) {
	if l.kind == .prep {
		return
	}
	if m < 0 {
		c.fail('svelte: the restore of a ${l.kind} found no ${l.node_type}', 0)
		return
	}
	c.let_tokens(l, toks, comms)
	match l.kind {
		.expression {
			mut node := c.es_node(m, .expression)
			if l.typed {
				// The typing moves with the expression (its references stay, shifted).
				c.remap(c.es_node(node, .type_annotation), l.segments)
				node = c.es_node(node, .expression)
			}
			c.remap(node, l.segments)
			c.set_expression(l, node)
		}
		.shorthand_property {
			obj := c.es_node(m, .expression)
			props := c.es_list(obj, .properties)
			if props.len == 0 {
				return
			}
			key := c.es_node(props[0], .key)
			value := c.es_node(props[0], .value)
			c.remap(key, l.segments)
			c.remap(value, l.segments)
			c.doc.nodes[l.target].key = eref(key)
			c.doc.nodes[l.target].value_ref = eref(value)
			c.set_parent(key, l.target)
			c.set_parent(value, l.target)
		}
		.variable_declarator {
			decls := c.es_list(m, .declarations)
			if decls.len == 0 {
				return
			}
			c.remap(decls[0], l.segments)
			c.doc.nodes[l.target].declarations = [decls[0]]
			c.set_parent(decls[0], l.target)
		}
		.declaration {
			c.remap(m, l.segments)
			c.doc.es.nodes[m].start = l.part_start
			c.doc.es.nodes[m].end = l.part_end
			c.doc.nodes[l.target].declaration = eref(m)
			c.set_parent(m, l.target)
		}
		.if_block {
			test := c.es_node(m, .test)
			c.remap(test, l.segments)
			c.doc.nodes[l.target].expression = eref(test)
			c.set_parent(test, l.target)
		}
		.each_block {
			call := c.es_node(m, .expression)
			callee := c.es_node(call, .callee)
			from_call := c.es_node(callee, .object)
			args := c.es_list(from_call, .arguments)
			expr := if args.len > 0 { args[0] } else { -1 }
			fn_args := c.es_list(call, .arguments)
			arrow := if fn_args.len > 0 { fn_args[0] } else { -1 }
			params := c.es_list(arrow, .params)
			c.remap(expr, [l.segments[0]])
			c.doc.nodes[l.target].expression = eref(expr)
			c.set_parent(expr, l.target)
			mut seg := 1
			if l.has_context && params.len > 0 {
				c.remap(params[0], [l.segments[seg]])
				c.doc.nodes[l.target].context = eref(params[0])
				c.set_parent(params[0], l.target)
				seg++
			}
			if l.has_index && params.len > 1 {
				c.remap(params[1], [l.segments[seg]])
				c.doc.nodes[l.target].index_ref = eref(params[1])
				c.set_parent(params[1], l.target)
			}
		}
		.snippet_block {
			id := c.es_node(m, .id)
			params := c.es_list(m, .params)
			for p in params {
				ann := c.es_node(p, .type_annotation)
				if ann >= 0 && l.insertions.any(it.pre_start == c.doc.es.nodes[ann].start) {
					c.doc.es.nodes[p].end = c.doc.es.nodes[ann].start
					c.drop_prop(p, .type_annotation)
				}
			}
			c.remap(id, l.segments)
			for p in params {
				c.remap(p, l.segments)
				c.set_parent(p, l.target)
			}
			c.doc.nodes[l.target].id = eref(id)
			c.doc.nodes[l.target].params = params
			c.set_parent(id, l.target)
		}
		.generic_alias, .generic_default {
			id := c.es_node(m, .id)
			ta := c.es_node(m, .type_annotation)
			param := l.param + c.generics_offset
			if l.kind == .generic_alias {
				c.remap(id, [l.segments[0]])
				c.set_prop_node(param, .name, id)
				c.set_parent(id, -1)
				if l.has_constraint {
					c.remap(ta, [l.segments[1]])
					c.set_prop_node(param, .constraint, ta)
					// The `=` of `type T =     C;` is the `extends` keyword, with a stale loc.
					c.doc.tokens << Token{
						typ:       'Keyword'
						start:     l.part_start
						end:       l.part_start + 7
						value:     'extends'
						loc_start: l.part_start + 1
						loc_end:   l.part_start + 2
					}
				}
			} else {
				c.remap(ta, l.segments)
				c.set_prop_node(param, .default_, ta)
			}
		}
		.block {}
		.block_params {
			arrow := c.es_node(m, .expression)
			params := c.es_list(arrow, .params)
			for i, p in params {
				if i >= l.segments.len {
					break
				}
				ann := c.es_node(p, .type_annotation)
				if c.is_ts() && ann >= 0 {
					c.doc.es.nodes[p].end = c.doc.es.nodes[ann].start
					c.drop_prop(p, .type_annotation)
				}
				c.remap(p, [l.segments[i]])
				ps := l.param_setters[i]
				match ps.field {
					0 { c.doc.nodes[ps.node].value_es = eref(p) }
					1 { c.doc.nodes[ps.node].error_es = eref(p) }
					else { c.doc.nodes[ps.node].expression = eref(p) }
				}
				c.set_parent(p, l.param_parents[i])
			}
		}
		else {}
	}
}

// set_expression applies a let's setter and checks to the node it gave.
fn (mut c Conv) set_expression(l ScriptLet, node int) {
	if node < 0 {
		return
	}
	typ := c.doc.es.nodes[node].typ
	match l.check {
		'Identifier', 'Identifier, or MemberExpression' {
			ok := typ == .identifier || (l.check != 'Identifier' && typ == .member_expression)
			if !ok {
				c.fail('Expected JS ${l.check}, but ${typ.type_name()} found.', c.doc.es.nodes[node].start)
				return
			}
		}
		'compiler:Identifier' {
			// SvelteFunctionBindingsExpression counts as a SequenceExpression.
			if typ != .identifier {
				c.fail('Expected Identifier, but ${typ.type_name()} found.', c.doc.es.nodes[node].start)
				return
			}
		}
		'style_identifier' {
			if typ != .identifier {
				c.fail('Expected JS identifier or attribute value.', c.doc.es.nodes[node].start)
				return
			}
		}
		else {}
	}
	c.set_parent(node, l.target)
	match l.setter {
		.expression {
			c.doc.nodes[l.target].expression = eref(node)
			if l.binding && typ == .sequence_expression
				&& c.es_list(node, .expressions).len == 2
				&& c.is_function_bindings_text(c.doc.es.nodes[node].start) {
				c.doc.nodes[l.target].function_bindings = true
			}
		}
		.debug_identifier {
			c.doc.nodes[l.target].identifiers << node
		}
		.key_name {
			c.doc.nodes[l.target].key = eref(node)
		}
		.element_name {
			c.doc.nodes[l.target].name_ref = eref(node)
		}
		.member_object {
			c.doc.nodes[l.target].object = eref(node)
		}
		.each_key {
			c.doc.nodes[l.target].key_expr = eref(node)
		}
		.none {}
	}
}

// extract_tokens is extractTokens: every non-whitespace character of the template code that no
// token or comment covers becomes a one-character token.
fn (mut c Conv) extract_tokens() {
	mut used := []Token{cap: c.doc.tokens.len + c.doc.comments.len}
	used << c.doc.tokens
	used << c.doc.comments
	sort_tokens(mut used)
	template := c.sc.template
	mut ri := 0
	mut i := 0
	for i < template.len {
		for ri < used.len && used[ri].end <= i {
			ri++
		}
		if ri < used.len && used[ri].start <= i {
			i = used[ri].end
			continue
		}
		if is_space_at(template, i) {
			_, n := code_point_at(template, i)
			i += n
			continue
		}
		ch := template[i]
		_, n := code_point_at(template, i)
		typ := if ch.is_letter() || ch.is_digit() || ch == `_` || ch == `$` {
			'Identifier'
		} else {
			'Punctuator'
		}
		c.doc.tokens << Token{
			typ:   typ
			start: i
			end:   i + n
			value: c.code[i..i + n]
		}
		i += n
	}
	sort_tokens(mut c.doc.comments)
	sort_tokens(mut c.doc.tokens)
}

// pre_code_u16 is the pre-virtual code as svelte-eslint-parser builds it (JavaScript blanks).
fn (c &Conv) pre_code_u16() string {
	if !c.started {
		return c.sc.script_u16
	}
	lu := c.doc.index.to_u16(c.trimmed_len)
	raw := c.sc.script_u16
	l_b := u16_byte_offset(raw, lu)
	after := u16_byte_offset(raw, lu + 2)
	return raw[..l_b] + '\n;' + raw[after..] + c.render.bytestr() + c.snippet.bytestr() +
		c.generics.bytestr()
}

// has_type_info is hasTypeInfo of a compiler expression: its text parsed by tree-sitter.
fn (c &Conv) has_type_info(e int) bool {
	ex := c.ca.exprs[e]
	// An identifier (the usual handler) has none: no parse needed.
	if ex.kind == .identifier && ex.leading.len == 0 && ex.trailing.len == 0 {
		return false
	}
	text := c.code[ex.start..ex.end]
	code := '(${text});'
	tree := parse_ts(c.parsers.ts, code) or { return false }
	defer {
		treesitter.tree_delete(tree)
	}
	root := treesitter.root_node(tree)
	if C.ts_node_has_error(root) {
		return false
	}
	es := convert_es(root, code) or { return false }
	body := es.list(es.root, .body) or { return false }
	if body.len == 0 {
		return false
	}
	expr := es.node(body[0], .expression) or { return false }
	return type_info(&es, expr)
}

fn type_info(es &estree.EsTree, n int) bool {
	if n < 0 {
		return false
	}
	typ := es.nodes[n].typ
	name := typ.type_name()
	if name.starts_with('TS') || typ == .literal || typ == .template_literal {
		return true
	}
	match typ {
		.arrow_function_expression, .function_expression {
			for p in es.list(n, .params) or { []int{} } {
				if !type_info(es, p) {
					return false
				}
			}
			if _ := es.node(n, .return_type) {
				return true
			}
			body := es.node(n, .body) or { return false }
			if es.nodes[body].typ != .block_statement {
				return type_info(es, body)
			}
			return false
		}
		.object_expression {
			for p in es.list(n, .properties) or { []int{} } {
				if !type_info(es, p) {
					return false
				}
			}
			return true
		}
		.array_expression {
			for p in es.list(n, .elements) or { []int{} } {
				if p >= 0 && !type_info(es, p) {
					return false
				}
			}
			return true
		}
		.unary_expression, .update_expression {
			return true
		}
		.conditional_expression {
			return type_info(es, es.node(n, .consequent) or { -1 })
				&& type_info(es, es.node(n, .alternate) or { -1 })
		}
		.assignment_expression {
			return type_info(es, es.node(n, .right) or { -1 })
		}
		.sequence_expression {
			list := es.list(n, .expressions) or { []int{} }
			return list.len > 0 && type_info(es, list.last())
		}
		.identifier, .object_pattern, .array_pattern, .assignment_pattern, .rest_element {
			_ := es.node(n, .type_annotation) or { return false }
			return true
		}
		.spread_element {
			return type_info(es, es.node(n, .argument) or { -1 })
		}
		.property {
			return type_info(es, es.node(n, .value) or { -1 })
		}
		else {
			return false
		}
	}
}

// token_value is a token's `value`: its text (a PrivateIdentifier's without the `#`).
fn token_value(src string, t SnipToken) string {
	if t.typ == 'PrivateIdentifier' {
		return src[t.start + 1..t.end]
	}
	return src[t.start..t.end]
}

fn (mut c Conv) set_prop_node(i int, key estree.Key, value int) {
	for k, p in c.doc.es.nodes[i].props {
		if p.key == key {
			c.doc.es.nodes[i].props[k] = estree.Prop{
				key:  key
				kind: .node
				idx:  value
			}
			return
		}
	}
}

// merge_generics appends the ESTree of the generics parse to the document's (positions moved to
// the file) and gives the SvelteGenericsDirective its params, with the parse's tokens and
// comments that are outside them.
fn (mut c Conv) merge_generics() {
	if c.generics_tree == unsafe { nil } {
		return
	}
	mut doc := c.doc
	doc.extra_trees << c.generics_tree
	g := &c.generics_es
	off := doc.es.nodes.len
	loff := doc.es.lists.len
	c.generics_offset = off
	for n in g.nodes {
		mut dup := n
		dup.start += c.generics_at
		dup.end += c.generics_at
		if dup.parent >= 0 {
			dup.parent += off
		}
		mut props := []estree.Prop{cap: n.props.len}
		for p in n.props {
			props << match p.kind {
				.node {
					estree.Prop{
						...p
						idx: p.idx + off
					}
				}
				.list {
					estree.Prop{
						...p
						idx: p.idx + loff
					}
				}
				else {
					p
				}
			}
		}
		dup.props = props
		doc.es.nodes << dup
	}
	for list in g.lists {
		doc.es.lists << list.map(if it >= 0 { it + off } else { it })
	}
	fn_expr := c.generics_fn()
	tparams := g.node(fn_expr, .type_parameters) or { -1 }
	params := g.list(tparams, .params) or { []int{} }
	doc.nodes[c.generics_attr].generic_params = params.map(it + off)
	for p in params {
		doc.es_parent[p + off] = c.generics_attr
	}
	gcode := c.generics_code
	for t in c.generics_toks {
		doc.tokens << Token{
			typ:   t.typ
			start: t.start + c.generics_at
			end:   t.end + c.generics_at
			value: token_value(gcode, t)
		}
	}
	for t in c.generics_comms {
		doc.comments << comment_token(gcode, t, t.start + c.generics_at, t.end + c.generics_at)
	}
}
