module svelte

import treesitter

// The `generics` attribute of the instance <script> (root.ts convertGenericsAttribute,
// script-let.ts addGenericTypeAliasDeclaration): parsed as `void function<…>(){}`; its type
// parameters become the params of a SvelteGenericsDirective, whose names, constraints and
// defaults come from `type T = …;` lets of the pre-virtual code.

fn (mut c Conv) convert_generics(script int) {
	lang := c.sc.script_attrs['lang'] or { '' }
	if lang != 'ts' && lang != 'typescript' {
		return
	}
	st := c.doc.nodes[script].start_tag
	mut attr := -1
	for a in c.doc.nodes[st].attributes {
		an := c.doc.nodes[a]
		if an.typ == .attribute && an.key.idx >= 0 && !an.key.es
			&& c.doc.nodes[an.key.idx].name == 'generics' && an.values.len == 1
			&& c.doc.nodes[an.values[0]].typ == .literal {
			attr = a
			break
		}
	}
	if attr < 0 {
		return
	}
	value := c.doc.nodes[c.doc.nodes[attr].values[0]]
	code := c.code[value.start..value.end]
	text := 'void function<${code}>(){}'
	c.generics_code = text
	tree := parse_ts(c.parsers.ts, text) or { return }
	root := treesitter.root_node(tree)
	if C.vt_node_has_error(root) {
		treesitter.rows_free(tree)
		return
	}
	es := convert_es(root, text) or {
		treesitter.rows_free(tree)
		return
	}
	c.generics_tree = tree
	c.generics_es = es
	c.generics_at = value.start - 14
	c.generics_attr = attr
	toks, comms := snippet_tokens(root, text, false)
	// The tokens of the value (HTMLText) leave.
	sort_tokens(mut c.doc.tokens)
	mut kept := []Token{cap: c.doc.tokens.len}
	for t in c.doc.tokens {
		if value.start <= t.start && t.end <= value.end {
			continue
		}
		kept << t
	}
	c.doc.tokens = kept
	c.doc.nodes[attr].typ = .generics_directive
	c.doc.nodes[attr].values = []
	// The parse's tokens without `void function <` and `> ( ) { }`, and its comments, that are
	// not inside a parameter.
	fn_expr := c.generics_fn()
	tparams := es.node(fn_expr, .type_parameters) or { -1 }
	params := es.list(tparams, .params) or { []int{} }
	inner := if toks.len >= 8 { toks[3..toks.len - 5] } else { []SnipToken{} }
	for t in inner {
		if params.all(t.end <= es.nodes[it].start || es.nodes[it].end <= t.start) {
			c.generics_toks << t
		}
	}
	for t in comms {
		if params.all(t.end <= es.nodes[it].start || es.nodes[it].end <= t.start) {
			c.generics_comms << t
		}
	}
	for p in params {
		c.add_generic_type_alias(p)
	}
}

// generics_fn is the FunctionExpression of `void function<…>(){}`.
fn (c &Conv) generics_fn() int {
	es := &c.generics_es
	body := es.list(es.root, .body) or { return -1 }
	if body.len == 0 {
		return -1
	}
	expr := es.node(body[0], .expression) or { return -1 }
	return es.node(expr, .argument) or { -1 }
}

// g_file is the file offset of an offset of the generics code.
fn (c &Conv) g_file(p int) int {
	return c.generics_at + p
}

// add_generic_type_alias is addGenericTypeAliasDeclaration for one TSTypeParameter of the
// generics parse (positions moved to the file).
fn (mut c Conv) add_generic_type_alias(param int) {
	es := &c.generics_es
	pn := es.nodes[param]
	name := es.node(param, .name) or { -1 }
	constraint := es.node(param, .constraint) or { -1 }
	default_ := es.node(param, .default_) or { -1 }
	mut id_start := c.g_file(pn.start)
	mut id_end := if constraint >= 0 || default_ >= 0 {
		c.g_file(es.nodes[name].end)
	} else {
		c.g_file(pn.end)
	}
	mut c_start := -1
	mut c_end := -1
	mut d_start := -1
	mut d_end := -1
	if constraint >= 0 {
		c_start = c.g_file(es.nodes[constraint].start)
		c_end = if default_ >= 0 { c.g_file(es.nodes[constraint].end) } else { c.g_file(pn.end) }
		if idx := c.token_index(id_end, c_start, fn (code string, i int) bool {
			return at_(code, i, 'extends')
		})
		{
			id_end = idx
			c_start = idx + 7
		}
	}
	if default_ >= 0 {
		d_start = c.g_file(es.nodes[default_].start)
		d_end = c.g_file(pn.end)
		from := if constraint >= 0 { c_end } else { id_end }
		if idx := c.token_index(from, d_start, fn (code string, i int) bool {
			return code[i] == `=`
		})
		{
			if constraint >= 0 {
				c_end = idx
			} else {
				id_end = idx
			}
			d_start = idx + 1
		}
	}
	id_text := c.code[id_start..id_end]
	mut text := 'type ${id_text}'
	mut segs := [Segment{5, id_text.len, id_start}]
	if constraint >= 0 {
		ctext := c.code[c_start..c_end]
		segs << Segment{text.len + 7, ctext.len, c_start}
		text += ' =     ${ctext};'
	} else {
		text += ' = unknown;'
	}
	c.append_let(ScriptLet{
		kind:           .generic_alias
		node_type:      'TSTypeAliasDeclaration'
		segments:       segs
		param:          param
		has_constraint: constraint >= 0
		part_start:     id_end // the `extends` keyword
	}, text, .generics)
	if default_ >= 0 {
		eq_from := if constraint >= 0 { c_end } else { id_end }
		eq_default := c.code[eq_from..d_end]
		uid := c.generate_unique_id(eq_default)
		c.append_let(ScriptLet{
			kind:      .generic_default
			node_type: 'TSTypeAliasDeclaration'
			segments:  [Segment{5 + uid.len, eq_default.len, eq_from}]
			param:     param
		}, 'type ${uid}${eq_default};', .generics)
	}
	_ = id_start
}

// token_index is getTokenIndex: the first index in [start, end) where `target` holds,
// skipping comments.
fn (c &Conv) token_index(start int, end int, target fn (code string, i int) bool) ?int {
	code := c.code
	mut i := start
	for i < end {
		if target(code, i) {
			return i
		}
		if at_(code, i, '//') {
			lf := code.index_after('\n', i) or { return none }
			i = lf + 1
			continue
		}
		if at_(code, i, '/*') {
			e := code.index_after('*/', i) or { return none }
			i = e + 2
			continue
		}
		i++
	}
	return none
}
