module esquery

import estree
import treesitter

fn tree_of(src string) estree.EsTree {
	p := treesitter.new_parser() or { panic(err) }
	tree := p.parse(src) or { panic(err) }
	return estree.convert(treesitter.root_node(tree), src, false) or { panic(err) }
}

fn names(t &estree.EsTree, nodes []int) []string {
	return nodes.map(t.typ(it).type_name())
}

fn test_parse_shapes() {
	s := parse('Foo > Bar[x=1], :has(> Baz)') or { panic(err) }
	assert s.kind == .matches
	assert s.selectors[0].kind == .child
	right := s.selectors[0].selectors[1]
	assert right.kind == .compound
	attr := right.selectors[1]
	assert attr.kind == .attribute && attr.operator == '=' && attr.is_number && attr.str_value == '1'
	has := s.selectors[1]
	assert has.kind == .has && has.selectors[0].kind == .child
	assert has.selectors[0].selectors[0].kind == .exact_node
	assert (parse('') or { panic(err) }).kind == .empty
	assert (parse('!A ~ B') or { panic(err) }).selectors[0].subject
	for bad in ['[', 'A >', ':not(A', '[x=/[]/]', '[x=/(/]', '[x=/a/ii]', 'A,'] {
		if _ := parse(bad) {
			assert false, bad
		}
	}
}

fn test_matches() {
	t := tree_of('function f(a, b, c) { return a?.b; }\nconst x = /re/g;')
	sel := parse('FunctionDeclaration[params.length>2] > BlockStatement') or { panic(err) }
	assert names(&t, match_all(&t, sel)!) == ['BlockStatement']
	opt := parse('[optional=true]') or { panic(err) }
	assert names(&t, match_all(&t, opt)!) == ['MemberExpression']
	re := parse('Literal[regex.flags=/./]') or { panic(err) }
	assert match_all(&t, re)!.len == 1
	first := parse('Identifier:first-child') or { panic(err) }
	assert match_all(&t, first)!.len == 1
	unknown := parse(':nope') or { panic(err) }
	if _ := match_all(&t, unknown) {
		assert false
	}
}

fn test_eslint_order() {
	t := tree_of('a;')
	calls := run(&t, ['Identifier', '*', 'ExpressionStatement > Identifier', 'Identifier:exit']) or {
		panic(err)
	}
	// On the Identifier: `*` and `Identifier` (no attributes, fewer identifiers first), then the
	// child selector; its exit last.
	ident := calls.filter(t.typ(it.node) == .identifier)
	assert ident.map(it.selector) == [1, 0, 2, 3]
	assert ident.last().exit
}
