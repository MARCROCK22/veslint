module estree

import treesitter

fn parse_ts(src string) EsTree {
	p := treesitter.new_parser() or { panic(err) }
	tree := p.parse(src) or { panic(err) }
	assert !treesitter.tree_has_error(tree)
	return convert(treesitter.root_node(tree), src, false) or { panic(err) }
}

fn test_values() {
	t := parse_ts("const a: number = 0x10, b = 'x\\u0041', c = /re/g, d = 1n;")
	assert t.typ(t.root) == .program
	assert t.get(t.root, .source_type) == Value('script')
	body := t.list(t.root, .body) or { panic('no body') }
	decl := body[0]
	assert t.typ(decl) == .variable_declaration
	assert t.string_of(decl, .kind) or { '' } == 'const'
	decls := t.list(decl, .declarations) or { panic('no declarations') }
	assert decls.len == 4
	id := t.node(decls[0], .id) or { panic('no id') }
	assert t.string_of(id, .name) or { '' } == 'a'
	// The id spans its type annotation.
	assert t.nodes[id].start == 6 && t.nodes[id].end == 15
	ann := t.node(id, .type_annotation) or { panic('no annotation') }
	assert t.typ(ann) == .ts_type_annotation
	init := t.node(decls[0], .init) or { panic('no init') }
	assert t.get(init, .value) == Value(f64(16))
	assert t.get(init, .raw) == Value('0x10')
	s := t.node(decls[1], .init) or { panic('no init') }
	assert t.get(s, .value) == Value('xA')
	re := t.node(decls[2], .init) or { panic('no init') }
	assert t.get(re, .regex) == Value(RegexInfo{'re', 'g'})
	big := t.node(decls[3], .init) or { panic('no init') }
	assert t.get(big, .bigint) == Value('1')
	assert t.get(big, .value) == Value(BigIntValue{'1'})
	// An absent property is undefined; a property set to null is null.
	assert t.get(decls[0], .type_parameters) == Value(Undefined{})
	assert t.get(id, .type_annotation) is NodeRef
	assert t.get(decls[1], .definite) == Value(false)
}

fn test_holes_and_chain() {
	t := parse_ts('[a, , b] = c; x?.y.z;')
	body := t.list(t.root, .body) or { panic('no body') }
	assign := t.node(body[0], .expression) or { panic('no expression') }
	left := t.node(assign, .left) or { panic('no left') }
	assert t.typ(left) == .array_pattern
	elements := t.list(left, .elements) or { panic('no elements') }
	assert elements.len == 3 && elements[1] == -1
	chain := t.node(body[1], .expression) or { panic('no expression') }
	assert t.typ(chain) == .chain_expression
	member := t.node(chain, .expression) or { panic('no member') }
	assert t.typ(member) == .member_expression
	assert t.flag(member, .optional) or { true } == false
	inner := t.node(member, .object) or { panic('no object') }
	assert t.flag(inner, .optional) or { false } == true
	assert t.nodes[inner].parent == member
}

fn test_errors() {
	p := treesitter.new_parser() or { panic(err) }
	tree := p.parse('let x = ;') or { panic(err) }
	if _ := convert(treesitter.root_node(tree), 'let x = ;', false) {
		assert false
	}
	t := convert_with(treesitter.root_node(tree), 'let x = ;', false, allow_errors: true) or {
		panic(err)
	}
	assert t.typ(t.root) == .program
}

fn test_traversal_order() {
	t := parse_ts('class A<T> extends B { @d m(x = 1) {} }')
	mut names := []string{}
	for step in t.steps() {
		if !step.leave {
			names << t.typ(step.node).type_name()
		}
	}
	assert names == ['Program', 'ClassDeclaration', 'Identifier', 'TSTypeParameterDeclaration',
		'TSTypeParameter', 'Identifier', 'Identifier', 'ClassBody', 'MethodDefinition', 'Decorator',
		'Identifier', 'Identifier', 'FunctionExpression', 'AssignmentPattern', 'Identifier', 'Literal',
		'BlockStatement']
	// traverse visits the same nodes, with their parents.
	mut count := 0
	mut counter := &count
	t.traverse(fn [mut counter] (node int, parent int) {
		unsafe {
			*counter += 1
		}
	}, fn (node int, parent int) {})
	assert count == names.len
	cls := t.children(t.root)[0]
	assert t.children(cls).map(t.typ(it)) == [NodeType.identifier, .ts_type_parameter_declaration,
		.identifier, .class_body]
}
