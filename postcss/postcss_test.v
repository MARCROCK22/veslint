module postcss

// tools/postcss_diff.mjs compares the whole port with postcss on the fixtures; these are a few of
// its cases, to run without node.

fn test_parse_positions() {
	r := parse(units('a{color:red} /* x */'), ParseOptions{})!
	assert r.nodes.len == 4
	assert r.nodes[1].typ == .rule && r.nodes[1].selector == 'a'
	assert r.nodes[2].prop == 'color' && r.nodes[2].value == 'red'
	assert r.nodes[2].start.offset == 2 && r.nodes[2].end.offset == 11
	assert r.nodes[3].typ == .comment && r.nodes[3].text == 'x'
}

fn test_errors() {
	parse(units('\n  .a {\n    class .b/35\n    color: red;\n  }'), ParseOptions{ from: 'x.svelte' }) or {
		assert err.msg() == 'x.svelte:3:11: Unknown word .b/35'
		return
	}
	assert false
}

fn test_template_safe() {
	r := parse(units('color: {c}; top: 1px'), ParseOptions{ safe: true, template: true })!
	assert r.nodes[0].nodes.len == 2
	assert r.nodes[1].value == '{c}'
	assert r.nodes[2].prop == 'top'
}

fn test_selector() {
	s := parse_selector(':global(.a) b#c')!
	assert s.nodes.map(it.typ) == [.root, .selector, .pseudo, .selector, .class, .combinator, .tag,
		.id]
	assert s.nodes[4].value == 'a' && s.nodes[4].start_column == 9 && s.nodes[4].end_column == 10
	assert sel_unesc('\\31 a') == '1a'
}
