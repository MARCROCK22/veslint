module svelte

fn test_compile_basic() {
	ast := compile_parse('<div class="a {b}">x &amp; {c}</div>') or { panic(err) }
	assert ast.fragments[ast.fragment].len == 1
	div := ast.nodes[ast.fragments[ast.fragment][0]]
	assert div.typ == .regular_element
	assert div.name == 'div'
	assert div.end == 36
	kids := ast.fragments[div.fragment]
	assert ast.nodes[kids[0]].data == 'x & '
	ex := ast.exprs[ast.nodes[kids[1]].expression]
	assert ex.kind == .identifier && ex.start == 29 && ex.end == 30
}
