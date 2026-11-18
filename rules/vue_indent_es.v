module rules

// The ES and Vue listeners of eslint-plugin-vue 10.12.1's indent-common.ts (see vue_indent.v).

fn (x &VindCtx) ftn(n VindNode) int {
	return x.ft(x.item(n))
}

fn (x &VindCtx) ltn(n VindNode) int {
	return x.lt(x.item(n))
}

// last_or is `last(list) || other`: the item of the last node, or `other` when the list is empty
// or ends with a hole.
fn (x &VindCtx) last_or(list []VindNode, other VindItem) VindItem {
	if list.len > 0 && list.last().ok() {
		return x.item(list.last())
	}
	return other
}

// on_expression is the `:expression` listener: the parentheses around an expression.
fn (mut x VindCtx) on_expression(n VindNode) {
	it := x.item(n)
	mut left := x.tb(it)
	mut right := x.ta(it)
	mut first := x.ft(it)
	for left >= 0 && right >= 0 && x.is_punct(left, '(') && x.is_punct(right, ')') {
		x.set(first, 1, left)
		x.set(right, 0, left)
		first = left
		left = x.tb(x.titem(left))
		right = x.ta(x.titem(right))
	}
}

// visit_type runs the listener of the node's own type.
fn (mut x VindCtx) visit_type(n VindNode, typ string) {
	match typ {
		'VAttribute' { x.v_attribute(n) }
		'VElement' { x.v_element(n) }
		'VEndTag' { x.v_end_tag(n) }
		'VExpressionContainer' { x.v_expression_container(n) }
		'VFilter' { x.v_filter(n) }
		'VFilterSequenceExpression' { x.v_filter_sequence(n) }
		'VForExpression' { x.v_for(n) }
		'VOnExpression' { x.node_list(x.items(x.vexprs(n)), VindItem{}, VindItem{}, 0, true) }
		'VStartTag' { x.v_start_tag(n) }
		'VText' { x.v_text(n) }
		'ArrayExpression', 'ArrayPattern' { x.es_array(n) }
		'ArrowFunctionExpression' { x.es_arrow(n) }
		'AssignmentExpression', 'AssignmentPattern', 'BinaryExpression', 'LogicalExpression' {
			x.es_binary(n)
		}
		'AwaitExpression', 'RestElement', 'SpreadElement', 'UnaryExpression', 'UpdateExpression' {
			x.set(x.ta(x.titem(x.ftn(n))), 1, x.ftn(n))
		}
		'BlockStatement', 'ClassBody' {
			x.node_list(x.items(x.list(n, .body)), x.titem(x.ftn(n)), x.titem(x.ltn(n)), 1, true)
		}
		'StaticBlock' { x.es_static_block(n) }
		'BreakStatement', 'ContinueStatement', 'ReturnStatement', 'ThrowStatement' {
			x.es_jump(n, typ)
		}
		'CallExpression' { x.es_call(n) }
		'ImportExpression' { x.es_import_expression(n) }
		'CatchClause' { x.es_catch(n) }
		'ClassDeclaration', 'ClassExpression' { x.es_class(n) }
		'ConditionalExpression' { x.es_conditional(n) }
		'DoWhileStatement' { x.es_do_while(n) }
		'ExportAllDeclaration' { x.es_export_all(n) }
		'ExportDefaultDeclaration' { x.es_export_default(n) }
		'ExportNamedDeclaration' { x.es_export_named(n) }
		'ExportSpecifier', 'ImportSpecifier' { x.es_specifier(n) }
		'ForInStatement', 'ForOfStatement' { x.es_for_in(n, typ) }
		'ForStatement' { x.es_for(n) }
		'FunctionDeclaration', 'FunctionExpression' { x.es_function(n) }
		'IfStatement' { x.es_if(n) }
		'ImportDeclaration' { x.es_import(n) }
		'ImportNamespaceSpecifier' { x.es_import_namespace(n) }
		'LabeledStatement' { x.es_labeled(n) }
		'MemberExpression', 'MetaProperty' { x.es_member(n, typ) }
		'MethodDefinition', 'Property', 'PropertyDefinition' {
			x.property_like(n, x.child(n, .key), x.child(n, .value), x.flag(n, .computed))
		}
		'NewExpression' { x.es_new(n) }
		'ObjectExpression', 'ObjectPattern' { x.es_object(n) }
		'SequenceExpression' {
			x.node_list(x.items(x.list(n, .expressions)), VindItem{}, VindItem{}, 0, true)
		}
		'SwitchCase' { x.es_switch_case(n) }
		'SwitchStatement' { x.es_switch(n) }
		'TaggedTemplateExpression' { x.es_tagged_template(n) }
		'TemplateLiteral', 'TSTemplateLiteralType' { x.es_template_literal(n) }
		'TryStatement' { x.es_try(n) }
		'VariableDeclaration' {
			x.node_list(x.items(x.list(n, .declarations)), x.titem(x.ftn(n)), VindItem{}, 1, true)
		}
		'VariableDeclarator' { x.es_declarator(n) }
		'WhileStatement', 'WithStatement' { x.es_while(n) }
		'YieldExpression' { x.es_yield(n) }
		'Program' { x.es_program(n) }
		else { x.visit_ts(n, typ) }
	}
}

// ---------------------------------------------------------------------------------------------
// Vue nodes
// ---------------------------------------------------------------------------------------------

fn (x &VindCtx) vexprs(n VindNode) []VindNode {
	return x.doc.nodes[n.v].exprs.map(vind_expr(it))
}

fn vind_v(v int) VindNode {
	return if v >= 0 {
		VindNode{
			v: v
		}
	} else {
		VindNode{}
	}
}

fn (mut x VindCtx) v_attribute(n VindNode) {
	node := x.doc.nodes[n.v]
	it := x.item(n)
	key := x.ft(it)
	eq := x.ta(x.item(vind_v(node.key)))
	if eq < 0 || x.st.all[eq].ue > it.e {
		return
	}
	x.set(eq, 1, key)
	value := x.ta(x.titem(eq))
	if value >= 0 && x.st.all[value].ue <= it.e {
		x.set(value, 1, key)
	}
}

fn (mut x VindCtx) v_element(n VindNode) {
	node := x.doc.nodes[n.v]
	if node.name in ['pre', 'textarea'] {
		start_tag := x.ftn(n)
		end_tag := if node.end_tag >= 0 { x.ftn(vind_v(node.end_tag)) } else { -1 }
		x.set(end_tag, 0, start_tag)
		x.preformatted(n)
		return
	}
	top := x.typ(x.parent(n)) != 'VElement'
	offset := if top { x.opts.base_indent } else { 1 }
	mut children := []VindItem{}
	for ch in node.children {
		child := x.doc.nodes[ch]
		if child.typ == .v_text && vind_blank(child.text) {
			continue
		}
		children << x.item(vind_v(ch))
	}
	x.node_list(children, x.item(vind_v(node.start_tag)), x.item(vind_v(node.end_tag)), offset,
		false)
}

// preformatted is setPreformattedTokens.
fn (mut x VindCtx) preformatted(n VindNode) {
	node := x.doc.nodes[n.v]
	mut end_token := if node.end_tag >= 0 { x.ftn(vind_v(node.end_tag)) } else { -1 }
	if end_token < 0 {
		end_token = x.ta(x.item(n))
	}
	start_tag := x.item(vind_v(node.start_tag))
	content := if end_token >= 0 {
		x.st.cursor(true, start_tag.e, x.st.all[end_token].us, true, .html_content, 0, -1)
	} else {
		x.st.cursor(true, start_tag.e, -1, true, .html_content, 0, -1)
	}
	for t in content {
		x.ignored[t] = true
	}
	if end_token >= 0 {
		x.ignored[end_token] = true
	}
}

fn (mut x VindCtx) v_end_tag(n VindNode) {
	element := x.parent(n)
	open := x.ftn(vind_v(x.doc.nodes[element.v].start_tag))
	close := x.ltn(n)
	if close >= 0 && x.st.all[close].typ.ends_with('TagClose') {
		x.set(close, x.opts.close_end, open)
	}
}

fn (mut x VindCtx) v_expression_container(n VindNode) {
	expr := vind_expr(x.doc.nodes[n.v].expression)
	if !expr.ok() {
		return
	}
	start, _ := x.range(n)
	expr_start, _ := x.range(expr)
	if start == expr_start {
		return
	}
	start_quote := x.ftn(n)
	end_quote := x.ltn(n)
	child := x.ta(x.titem(start_quote))
	x.set(child, 1, start_quote)
	x.set(end_quote, 0, start_quote)
}

fn (mut x VindCtx) v_filter(n VindNode) {
	id := x.ftn(n)
	last := x.ltn(n)
	if !x.is_punct(last, ')') {
		return
	}
	left_paren := x.ta(x.item(VindNode{ v: n.v, callee: true }))
	x.set(left_paren, 1, id)
	x.node_list(x.items(x.vexprs(n)), x.titem(left_paren), x.titem(last), 1, true)
}

fn (mut x VindCtx) v_filter_sequence(n VindNode) {
	filters := x.doc.nodes[n.v].filters
	if filters.len == 0 {
		return
	}
	first := x.ftn(n)
	mut tokens := []int{}
	for f in filters {
		it := x.item(vind_v(f))
		tokens << x.tbf(it, .pipe)
		tokens << x.ft(it)
	}
	x.sets(tokens, 1, first)
}

fn (mut x VindCtx) v_for(n VindNode) {
	node := x.doc.nodes[n.v]
	first := x.ftn(n)
	lefts := x.vexprs(n)
	last_of_left := x.last_or(lefts, x.titem(first))
	in_token := x.taf(last_of_left, .not_close_paren)
	right := x.ftn(vind_expr(node.right))
	if x.is_punct(first, '(') {
		right_paren := x.taf(last_of_left, .close_paren)
		x.node_list(x.items(lefts), x.titem(first), x.titem(right_paren), 1, true)
	}
	x.set(in_token, 1, first)
	x.set(right, 1, in_token)
}

fn (mut x VindCtx) v_start_tag(n VindNode) {
	node := x.doc.nodes[n.v]
	open := x.ftn(n)
	close := x.ltn(n)
	x.node_list(node.attributes.map(x.item(vind_v(it))), x.titem(open), VindItem{}, x.opts.attribute,
		x.opts.align)
	if close < 0 || !x.st.all[close].typ.ends_with('TagClose') {
		return
	}
	offset := if x.st.all[close].typ == 'HTMLSelfClosingTagClose' {
		x.opts.close_self
	} else {
		x.opts.close_start
	}
	x.set(close, offset, open)
}

fn (mut x VindCtx) v_text(n VindNode) {
	it := x.item(n)
	tokens := x.tokensf(it, .not_ws)
	first := x.info(x.ft(it)) or { VindOff{} }
	for t in tokens {
		x.put(t, first)
	}
}

// ---------------------------------------------------------------------------------------------
// ES nodes
// ---------------------------------------------------------------------------------------------

fn (mut x VindCtx) es_array(n VindNode) {
	first := x.ftn(n)
	elements := x.list(n, .elements)
	right := x.taf(x.last_or(elements, x.titem(first)), .close_bracket)
	x.node_list(x.items(elements), x.titem(first), x.titem(right), 1, true)
}

fn (mut x VindCtx) es_arrow(n VindNode) {
	first := x.ftn(n)
	second := x.ta(x.titem(first))
	is_async := x.flag(n, .async)
	left := if is_async { second } else { first }
	body := x.child(n, .body)
	arrow := x.tbf(x.item(body), .arrow)
	if is_async {
		x.set(second, 1, first)
	}
	if x.is_punct(left, '(') {
		params := x.list(n, .params)
		right := x.taf(x.last_or(params, x.titem(left)), .close_paren)
		x.node_list(x.items(params), x.titem(left), x.titem(right), 1, true)
	}
	x.set(arrow, 1, first)
	x.maybe_block(body, first)
}

fn (mut x VindCtx) es_binary(n VindNode) {
	left := x.chain_head(n)
	op := x.taf(x.item(x.child(n, .left)), .not_close_paren)
	right := x.ta(x.titem(op))
	prev := x.tb(x.titem(left))
	indent := prev < 0 || x.st.all[prev].end_line == x.st.all[left].line
		|| x.beginning_of_element(left, n)
	x.sets([op, right], if indent { 1 } else { 0 }, left)
}

fn (mut x VindCtx) es_static_block(n VindNode) {
	first := x.ftn(n)
	mut next := x.ta(x.titem(first))
	for next >= 0 && !x.is_punct(next, '{') {
		x.set(next, 0, first)
		next = x.ta(x.titem(next))
	}
	x.set(next, 0, first)
	x.node_list(x.items(x.list(n, .body)), x.titem(next), x.titem(x.ltn(n)), 1, true)
}

fn (mut x VindCtx) es_jump(n VindNode, typ string) {
	if (typ !in ['ReturnStatement', 'ThrowStatement'] || !x.child(n, .argument).ok())
		&& (typ !in ['BreakStatement', 'ContinueStatement'] || !x.child(n, .label).ok()) {
		return
	}
	first := x.ftn(n)
	x.set(x.ta(x.titem(first)), 1, first)
}

fn (mut x VindCtx) es_call(n VindNode) {
	type_args := x.child(n, .type_arguments)
	head := if type_args.ok() { type_args } else { x.child(n, .callee) }
	first := x.ftn(n)
	right := x.ltn(n)
	left := x.taf(x.item(head), .open_paren)
	if type_args.ok() {
		x.set(x.ftn(type_args), 1, first)
	}
	for t in x.betweenf(x.titem(x.ltn(head)), x.titem(left), .optional) {
		x.set(t, 1, first)
	}
	x.set(left, 1, first)
	x.node_list(x.items(x.list(n, .arguments)), x.titem(left), x.titem(right), 1, true)
}

fn (mut x VindCtx) es_import_expression(n VindNode) {
	first := x.ftn(n)
	right := x.ltn(n)
	left := x.taf(x.titem(first), .open_paren)
	x.set(left, 1, first)
	x.node_list([x.item(x.child(n, .source))], x.titem(left), x.titem(right), 1, true)
}

fn (mut x VindCtx) es_catch(n VindNode) {
	first := x.ftn(n)
	body := x.ftn(x.child(n, .body))
	param := x.child(n, .param)
	if param.ok() {
		left := x.ta(x.titem(first))
		right := x.ta(x.item(param))
		x.set(left, 1, first)
		x.node_list([x.item(param)], x.titem(left), x.titem(right), 1, true)
	}
	x.set(body, 0, first)
}

fn (mut x VindCtx) es_class(n VindNode) {
	first := x.ftn(n)
	body := x.ftn(x.child(n, .body))
	id := x.child(n, .id)
	if id.ok() {
		x.set(x.ftn(id), 1, first)
	}
	super_class := x.child(n, .super_class)
	if super_class.ok() {
		extends := x.tbf(x.item(super_class), .extends_kw)
		super_token := x.ta(x.titem(extends))
		x.set(extends, 1, first)
		x.set(super_token, 1, extends)
	}
	x.set(body, 0, first)
}

fn (mut x VindCtx) es_conditional(n VindNode) {
	it := x.item(n)
	prev := x.tb(it)
	first := x.ft(it)
	test := x.item(x.child(n, .test))
	consequent := x.item(x.child(n, .consequent))
	question := x.taf(test, .not_close_paren)
	consequent_token := x.ta(x.titem(question))
	colon := x.taf(consequent, .not_close_paren)
	alternate_token := x.ta(x.titem(colon))
	flat := prev >= 0 && x.st.all[prev].end_line != it.sline && test.eline == consequent.sline
	if flat {
		x.sets([question, consequent_token, colon, alternate_token], 0, first)
	} else {
		x.sets([question, colon], 1, first)
		x.sets([consequent_token, alternate_token], 1, question)
	}
}

fn (mut x VindCtx) es_do_while(n VindNode) {
	do_token := x.ftn(n)
	body := x.child(n, .body)
	while_token := x.taf(x.item(body), .not_close_paren)
	left := x.ta(x.titem(while_token))
	test := x.ta(x.titem(left))
	last := x.ltn(n)
	right := if x.is_punct(last, ';') { x.tb(x.titem(last)) } else { last }
	x.maybe_block(body, do_token)
	x.set(while_token, 0, do_token)
	x.set(left, 1, while_token)
	x.set(test, 1, left)
	x.set(right, 0, left)
}

// assertions are the `with { … }` of an import or export: from the source to the last token.
fn (mut x VindCtx) assertions(n VindNode, source VindNode, base int) {
	last := x.ltf(x.item(n), .not_semicolon)
	mut tokens := x.between(x.item(source), x.titem(last))
	if tokens.len == 0 {
		return
	}
	assert_token := tokens[0]
	tokens.delete(0)
	x.set(assert_token, 0, base)
	if tokens.len == 0 {
		return
	}
	open := tokens[0]
	tokens.delete(0)
	x.set(open, 1, assert_token)
	x.node_list(tokens.map(x.titem(it)), x.titem(open), x.titem(last), 1, true)
}

fn (mut x VindCtx) es_export_all(n VindNode) {
	export := x.ftn(n)
	source := x.child(n, .source)
	mut tokens := x.between(x.titem(export), x.item(source))
	tokens << x.ftn(source)
	if x.child(n, .exported).ok() {
		mut star := -1
		for t in tokens {
			if x.is_punct(t, '*') {
				star = t
				break
			}
		}
		as_token := x.ta(x.titem(star))
		exported := x.ta(x.titem(as_token))
		index := tokens.index(exported)
		after := tokens[index + 1..]
		x.set(star, 1, export)
		x.set(as_token, 1, star)
		x.set(exported, 1, star)
		x.sets(after, 1, export)
	} else {
		x.sets(tokens, 1, export)
	}
	x.assertions(n, source, export)
}

fn (mut x VindCtx) es_export_default(n VindNode) {
	export := x.ftn(n)
	default_token := x.fts(x.item(n), 1)
	declaration := x.first_of(x.item(x.child(n, .declaration)))
	x.sets([default_token, declaration], 1, export)
}

fn (mut x VindCtx) es_export_named(n VindNode) {
	export := x.ftn(n)
	if x.child(n, .declaration).ok() {
		x.set(x.fts(x.item(n), 1), 1, export)
		return
	}
	specifiers := x.list(n, .specifiers)
	if specifiers.len > 0 && x.typ(specifiers[0]) != 'ExportSpecifier' {
		return
	}
	left_braces := if specifiers.len > 0 {
		x.between(x.titem(export), x.item(specifiers[0]))
	} else {
		[x.ta(x.titem(export))]
	}
	source := x.child(n, .source)
	right_brace := if source.ok() {
		x.tbf(x.item(source), .close_brace)
	} else {
		x.ltf(x.item(n), .close_brace)
	}
	x.sets(left_braces, 0, export)
	x.node_list(x.items(specifiers), x.titem(if left_braces.len > 0 {
		left_braces.last()
	} else {
		-1
	}),
		x.titem(right_brace), 1, true)
	if source.ok() {
		mut tokens := x.between(x.titem(right_brace), x.item(source))
		tokens << x.ftn(source)
		x.sets(tokens, 1, export)
		x.assertions(n, source, export)
	}
}

fn (mut x VindCtx) es_specifier(n VindNode) {
	mut tokens := x.toks(x.item(n))
	if tokens.len == 0 {
		return
	}
	mut first := tokens[0]
	tokens.delete(0)
	if x.value(first) == 'type' {
		type_token := first
		first = if tokens.len > 0 { tokens[0] } else { -1 }
		if tokens.len > 0 {
			tokens.delete(0)
		}
		x.set(first, 0, type_token)
	}
	x.sets(tokens, 1, first)
}

fn (mut x VindCtx) es_for_in(n VindNode, typ string) {
	for_token := x.ftn(n)
	await_token := if typ == 'ForOfStatement' && x.flag(n, .await_) {
		x.ta(x.titem(for_token))
	} else {
		-1
	}
	left_paren := x.ta(x.titem(if await_token >= 0 { await_token } else { for_token }))
	left := x.ta(x.titem(left_paren))
	in_token := x.taf(x.titem(left), .not_close_paren)
	right := x.ta(x.titem(in_token))
	body := x.child(n, .body)
	right_paren := x.tbf(x.item(body), .not_open_paren)
	if await_token >= 0 {
		x.set(await_token, 0, for_token)
	}
	x.set(left_paren, 1, for_token)
	x.set(left, 1, left_paren)
	x.set(in_token, 1, left)
	x.set(right, 1, left)
	x.set(right_paren, 0, left_paren)
	x.maybe_block(body, for_token)
}

fn (mut x VindCtx) es_for(n VindNode) {
	for_token := x.ftn(n)
	left_paren := x.ta(x.titem(for_token))
	body := x.child(n, .body)
	right_paren := x.tbf(x.item(body), .not_open_paren)
	x.set(left_paren, 1, for_token)
	x.node_list([x.item(x.child(n, .init)), x.item(x.child(n, .test)), x.item(x.child(n, .update))], x.titem(left_paren), x.titem(right_paren), 1, true)
	x.maybe_block(body, for_token)
}

// function_head walks the tokens of a function's head up to its `(` or `<` (normal functions:
// `function`, `*`, the name), setting their offsets; it gives the `(` (or `<`).
fn (mut x VindCtx) function_head(n VindNode, first int) int {
	id := x.child(n, .id)
	id_start := if id.ok() { x.item(id).s } else { -1 }
	mut next := x.ta(x.titem(first))
	mut next_offset := 0
	for next >= 0 && !x.is_punct(next, '(') && x.value(next) != '<' {
		if x.value(next) == '*' || (id.ok() && x.st.all[next].us == id_start) {
			next_offset = 1
		}
		x.set(next, next_offset, first)
		next = x.ta(x.titem(next))
	}
	return next
}

fn (mut x VindCtx) es_function(n VindNode) {
	first := x.ftn(n)
	mut left_paren := -1
	mut body_base := -1
	if x.is_punct(first, '(') {
		left_paren = first
		body_base = x.ftn(x.parent(n))
	} else {
		left_paren = x.function_head(n, first)
		body_base = first
	}
	type_params := x.child(n, .type_parameters)
	if !x.is_punct(left_paren, '(') && type_params.ok() {
		left_paren = x.ta(x.item(type_params))
	}
	params := x.list(n, .params)
	right_paren := x.taf(x.last_or(params, x.titem(left_paren)), .close_paren)
	x.set(left_paren, 1, body_base)
	x.node_list(x.items(params), x.titem(left_paren), x.titem(right_paren), 1, true)
	x.set(x.ftn(x.child(n, .body)), 0, body_base)
}

fn (mut x VindCtx) es_if(n VindNode) {
	if_token := x.ftn(n)
	left := x.ta(x.titem(if_token))
	consequent := x.child(n, .consequent)
	right := x.tbf(x.item(consequent), .close_paren)
	x.set(left, 1, if_token)
	x.set(right, 0, left)
	x.maybe_block(consequent, if_token)
	alternate := x.child(n, .alternate)
	if !alternate.ok() {
		return
	}
	else_token := x.taf(x.item(consequent), .not_close_paren)
	x.set(else_token, 0, if_token)
	x.maybe_block(alternate, else_token)
}

fn (mut x VindCtx) es_import(n VindNode) {
	import_token := x.ftn(n)
	source := x.child(n, .source)
	tokens := x.between(x.titem(import_token), x.item(source))
	mut from_index := -1
	for i := tokens.len - 1; i >= 0; i-- {
		if x.value(tokens[i]) == 'from' {
			from_index = i
			break
		}
	}
	mut from_token := -1
	mut before := []int{}
	mut after := []int{}
	if from_index == -1 {
		before = tokens.clone()
		before << x.ftn(source)
	} else {
		from_token = tokens[from_index]
		before = tokens[..from_index].clone()
		after = tokens[from_index + 1..].clone()
		after << x.ftn(source)
	}
	mut named := []VindNode{}
	for spec in x.list(n, .specifiers) {
		if x.typ(spec) == 'ImportSpecifier' {
			named << spec
		} else {
			remove := x.toks(x.item(spec))
			for t in remove[1..] {
				i := before.index(t)
				if i != -1 {
					before.delete(i)
				}
			}
		}
	}
	if named.len > 0 {
		left_brace := x.tb(x.item(named[0]))
		right_brace := x.taf(x.item(named.last()), .close_brace)
		x.node_list(x.items(named), x.titem(left_brace), x.titem(right_brace), 1, true)
		mut remove := x.between(x.titem(left_brace), x.titem(right_brace))
		remove << right_brace
		for t in remove {
			i := before.index(t)
			if i != -1 {
				before.delete(i)
			}
		}
	}
	braces_only := before.all(x.is_punct(it, '{') || x.is_punct(it, '}'))
	x.sets(before, if braces_only { 0 } else { 1 }, import_token)
	if from_token >= 0 {
		x.set(from_token, 1, import_token)
		x.sets(after, 0, from_token)
	}
	x.assertions(n, source, import_token)
}

fn (mut x VindCtx) es_import_namespace(n VindNode) {
	tokens := x.toks(x.item(n))
	if tokens.len > 0 {
		x.sets(tokens[1..], 1, tokens[0])
	}
}

fn (mut x VindCtx) es_labeled(n VindNode) {
	label := x.ftn(n)
	colon := x.ta(x.titem(label))
	body := x.ta(x.titem(colon))
	x.sets([colon, body], 1, label)
}

fn (mut x VindCtx) es_member(n VindNode, typ string) {
	object := x.ftn(n)
	property := x.item(x.child(n, .property))
	if typ == 'MemberExpression' && x.flag(n, .computed) {
		left_bracket := x.tbf(property, .open_bracket)
		property_token := x.ta(x.titem(left_bracket))
		right_bracket := x.taf(property, .close_bracket)
		for t in x.betweenf(x.titem(x.ltn(x.child(n, .object))), x.titem(left_bracket), .optional) {
			x.set(t, 1, object)
		}
		x.set(left_bracket, 1, object)
		x.set(property_token, 1, left_bracket)
		x.set(right_bracket, 0, left_bracket)
	} else {
		dot := x.tb(property)
		property_token := x.ta(x.titem(dot))
		x.sets([dot, property_token], 1, object)
	}
}

// property_like is the listener of `MethodDefinition, Property, PropertyDefinition` (and of the
// TypeScript members and AccessorProperty, which are written the same).
fn (mut x VindCtx) property_like(n VindNode, key VindNode, value VindNode, computed bool) {
	first := x.ftn(n)
	key_first, key_last := x.first_last(x.item(key), 0)
	mut prefix := x.between(x.titem(first), x.titem(key_first))
	if computed && prefix.len > 0 {
		prefix.delete_last()
	}
	x.sets(prefix, 0, first)
	mut last_key := -1
	if computed {
		left_bracket := x.tb(x.titem(key_first))
		right_bracket := x.ta(x.titem(key_last))
		last_key = right_bracket
		x.set(left_bracket, 0, first)
		x.node_list([x.item(key)], x.titem(left_bracket), x.titem(right_bracket), 1, true)
	} else {
		x.set(key_first, 0, first)
		last_key = key_last
	}
	if !value.ok() {
		return
	}
	init := x.ftn(value)
	mut tokens := x.between(x.titem(last_key), x.titem(init))
	tokens << init
	x.sets(tokens, 1, last_key)
}

fn (mut x VindCtx) es_new(n VindNode) {
	type_args := x.child(n, .type_arguments)
	new_token := x.ftn(n)
	callee := x.ta(x.titem(new_token))
	right := x.ltn(n)
	head := if type_args.ok() { type_args } else { x.child(n, .callee) }
	left := if x.is_punct(right, ')') {
		hi := x.item(head)
		vind_one(x.st.cursor(true, hi.e, x.st.all[right].us, false, .open_paren, 0, 1))
	} else {
		-1
	}
	if type_args.ok() {
		x.set(x.ftn(type_args), 1, callee)
	}
	x.set(callee, 1, new_token)
	if left < 0 {
		return
	}
	x.set(left, 1, callee)
	x.node_list(x.items(x.list(n, .arguments)), x.titem(left), x.titem(right), 1, true)
}

fn (mut x VindCtx) es_object(n VindNode) {
	first := x.ftn(n)
	properties := x.list(n, .properties)
	right := x.taf(x.last_or(properties, x.titem(first)), .close_brace)
	x.node_list(x.items(properties), x.titem(first), x.titem(right), 1, true)
}

fn (mut x VindCtx) es_switch_case(n VindNode) {
	case_token := x.ftn(n)
	test := x.child(n, .test)
	if !test.ok() {
		x.set(x.ta(x.titem(case_token)), 1, case_token)
	} else {
		test_token := x.ta(x.titem(case_token))
		colon := x.taf(x.item(test), .not_close_paren)
		x.sets([test_token, colon], 1, case_token)
	}
	consequent := x.list(n, .consequent)
	if consequent.len == 1 && x.typ(consequent[0]) == 'BlockStatement' {
		x.set(x.ftn(consequent[0]), 0, case_token)
	} else if consequent.len > 0 {
		x.set(x.ftn(consequent[0]), 1, case_token)
		x.node_list(x.items(consequent), VindItem{}, VindItem{}, 0, true)
	}
}

fn (mut x VindCtx) es_switch(n VindNode) {
	switch_token := x.ftn(n)
	left_paren := x.ta(x.titem(switch_token))
	discriminant := x.ta(x.titem(left_paren))
	left_brace := x.taf(x.item(x.child(n, .discriminant)), .open_brace)
	right_paren := x.tb(x.titem(left_brace))
	right_brace := x.ltn(n)
	x.set(left_paren, 1, switch_token)
	x.set(discriminant, 1, left_paren)
	x.set(right_paren, 0, left_paren)
	x.set(left_brace, 0, switch_token)
	x.node_list(x.items(x.list(n, .cases)), x.titem(left_brace), x.titem(right_brace),
		x.opts.switch_case, true)
}

fn (mut x VindCtx) es_tagged_template(n VindNode) {
	tag_first, tag_last := x.first_last(x.item(x.child(n, .tag)), x.item(n).s)
	quasi := x.ta(x.titem(tag_last))
	x.set(quasi, 1, tag_first)
}

fn (mut x VindCtx) es_template_literal(n VindNode) {
	first := x.ftn(n)
	quasis := x.list(n, .quasis)
	if quasis.len == 0 {
		return
	}
	x.sets(quasis[1..].map(x.ftn(it)), 0, first)
	x.sets(quasis[..quasis.len - 1].map(x.ta(x.item(it))), 1, first)
}

fn (mut x VindCtx) es_try(n VindNode) {
	try_token := x.ftn(n)
	x.set(x.ftn(x.child(n, .block)), 0, try_token)
	handler := x.child(n, .handler)
	if handler.ok() {
		x.set(x.ftn(handler), 0, try_token)
	}
	finalizer := x.child(n, .finalizer)
	if !finalizer.ok() {
		return
	}
	finally_token := x.tb(x.item(finalizer))
	x.sets([finally_token, x.ftn(finalizer)], 0, try_token)
}

fn (mut x VindCtx) es_declarator(n VindNode) {
	if !x.child(n, .init).ok() {
		return
	}
	id := x.ftn(n)
	eq := x.ta(x.item(x.child(n, .id)))
	init := x.ta(x.titem(eq))
	x.sets([eq, init], 1, id)
}

fn (mut x VindCtx) es_while(n VindNode) {
	first := x.ftn(n)
	left_paren := x.ta(x.titem(first))
	body := x.child(n, .body)
	right_paren := x.tbf(x.item(body), .close_paren)
	x.set(left_paren, 1, first)
	x.set(right_paren, 0, left_paren)
	x.maybe_block(body, first)
}

fn (mut x VindCtx) es_yield(n VindNode) {
	if !x.child(n, .argument).ok() {
		return
	}
	yield_token := x.ftn(n)
	x.set(x.ta(x.titem(yield_token)), 1, yield_token)
	if x.flag(n, .delegate) {
		x.set(x.tas(x.titem(yield_token), 1), 1, yield_token)
	}
}

// es_program is the Program listener: the base indentation of the top-level statements (the
// tokens of a .vue file's Program start with the `<script>` punctuator).
fn (mut x VindCtx) es_program(n VindNode) {
	script_tag := x.st.code.len > 0 && x.is_punct(x.st.code[0], '<script>')
	base := if script_tag { x.opts.indent_size * x.opts.base_indent } else { 0 }
	for statement in x.list(n, .body) {
		x.top_level(statement, base)
	}
}
