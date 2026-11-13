module estree

// JSX (the tsx dialect).

fn (mut c Converter) jsx_element(n C.TSNode) int {
	kids := c.kids(n)
	if kind_of(n) == 'jsx_self_closing_element' {
		i := c.mkn(.jsx_element, n)
		c.plist(i, .children, [])
		c.pnull(i, .closing_element)
		c.pnode(i, .opening_element, c.jsx_opening(n, kids, true))
		return i
	}
	open := field_of(kids, 'open_tag') or { return -1 }
	close := field_of(kids, 'close_tag')
	children := c.jsx_children(n, kids)
	ok := c.kids(open.n)
	if field_of(ok, 'name') == none {
		i := c.mkn(.jsx_fragment, n)
		c.plist(i, .children, children)
		if cl := close {
			c.pnode(i, .closing_fragment, c.mkn(.jsx_closing_fragment, cl.n))
		}
		c.pnode(i, .opening_fragment, c.mkn(.jsx_opening_fragment, open.n))
		return i
	}
	i := c.mkn(.jsx_element, n)
	c.plist(i, .children, children)
	if cl := close {
		cl_el := c.mkn(.jsx_closing_element, cl.n)
		if name := c.field(cl.n, 'name') {
			c.pnode(cl_el, .name, c.jsx_tag_name(name.n))
		}
		c.pnode(i, .closing_element, cl_el)
	} else {
		c.pnull(i, .closing_element)
	}
	c.pnode(i, .opening_element, c.jsx_opening(open.n, ok, false))
	return i
}

fn (mut c Converter) jsx_opening(n C.TSNode, kids []Kid, self_closing bool) int {
	i := c.mkn(.jsx_opening_element, n)
	mut attrs := []int{}
	for k in kids {
		if k.field != 'attribute' {
			continue
		}
		if k.kind == 'jsx_expression' {
			// {...x}
			a := c.mkn(.jsx_spread_attribute, k.n)
			if sp := first_named(c.kids(k.n)) {
				if arg := first_named(c.kids(sp.n)) {
					c.pnode(a, .argument, c.expr(arg.n))
				}
			}
			attrs << a
			continue
		}
		ak := c.kids(k.n)
		a := c.mkn(.jsx_attribute, k.n)
		named := ak.filter(it.named)
		if named.len == 0 {
			continue
		}
		c.pnode(a, .name, c.jsx_name(named[0].n))
		if named.len > 1 {
			v := named[1]
			match v.kind {
				'string' {
					lit := c.mkn(.literal, v.n)
					raw := c.text(v.n)
					c.pstr(lit, .raw, raw)
					c.pstr(lit, .value, jsx_unescape(raw[1..raw.len - 1]))
					c.pnode(a, .value, lit)
				}
				'jsx_expression' {
					c.pnode(a, .value, c.jsx_expression(v.n))
				}
				else {
					c.pnode(a, .value, c.expr(v.n))
				}
			}
		} else {
			c.pnull(a, .value)
		}
		attrs << a
	}
	c.plist(i, .attributes, attrs)
	if name := field_of(kids, 'name') {
		c.pnode(i, .name, c.jsx_tag_name(name.n))
	}
	c.pbool(i, .self_closing, self_closing)
	if ta := field_of(kids, 'type_arguments') {
		c.pnode(i, .type_arguments, c.type_arguments(ta.n))
	}
	return i
}

// jsx_name converts the name of an attribute.
fn (mut c Converter) jsx_name(n C.TSNode) int {
	if kind_of(n) == 'jsx_namespace_name' {
		return c.jsx_namespace(n)
	}
	i := c.mkn(.jsx_identifier, n)
	c.pstr(i, .name, c.text(n))
	return i
}

fn (mut c Converter) jsx_namespace(n C.TSNode) int {
	named := c.named(n)
	i := c.mkn(.jsx_namespaced_name, n)
	if named.len == 2 {
		ns := c.mkn(.jsx_identifier, named[0].n)
		c.pstr(ns, .name, c.text(named[0].n))
		name := c.mkn(.jsx_identifier, named[1].n)
		c.pstr(name, .name, c.text(named[1].n))
		c.pnode(i, .name, name)
		c.pnode(i, .namespace, ns)
	}
	return i
}

// jsx_tag_name converts the name of an element: JSXIdentifier, JSXMemberExpression or
// JSXNamespacedName.
fn (mut c Converter) jsx_tag_name(n C.TSNode) int {
	match kind_of(n) {
		'jsx_member_expression', 'member_expression', 'nested_identifier' {
			kids := c.kids(n)
			i := c.mkn(.jsx_member_expression, n)
			c.pnode(i, .object, c.jsx_tag_name(field_of(kids, 'object') or { return i }.n))
			prop := field_of(kids, 'property') or { return i }
			p := c.mkn(.jsx_identifier, prop.n)
			c.pstr(p, .name, c.text(prop.n))
			c.pnode(i, .property, p)
			return i
		}
		'jsx_namespace_name' {
			return c.jsx_namespace(n)
		}
		else {
			i := c.mkn(.jsx_identifier, n)
			c.pstr(i, .name, c.text(n))
			return i
		}
	}
}

fn (mut c Converter) jsx_expression(n C.TSNode) int {
	kids := c.kids(n)
	inner := first_named(kids) or {
		i := c.mkn(.jsx_expression_container, n)
		e := c.mk(.jsx_empty_expression, n, c.start(n) + 1, c.end(n) - 1)
		c.pnode(i, .expression, e)
		return i
	}
	if inner.kind == 'spread_element' {
		i := c.mkn(.jsx_spread_child, n)
		if arg := first_named(c.kids(inner.n)) {
			c.pnode(i, .expression, c.expr(arg.n))
		}
		return i
	}
	i := c.mkn(.jsx_expression_container, n)
	c.pnode(i, .expression, c.expr(inner.n))
	return i
}

// jsx_children converts the children between the tags: the text between elements and
// expressions is a JSXText, also when it is only white space.
fn (mut c Converter) jsx_children(n C.TSNode, kids []Kid) []int {
	mut out := []int{}
	open := field_of(kids, 'open_tag') or { return out }
	mut text_start := c.end(open.n)
	for k in kids {
		if k.field in ['open_tag', 'close_tag'] {
			continue
		}
		if k.kind in ['jsx_text', 'html_character_reference'] || !k.named {
			continue
		}
		start := c.start(k.n)
		if start > text_start {
			out << c.jsx_text(n, text_start, start)
		}
		match k.kind {
			'jsx_expression' {
				out << c.jsx_expression(k.n)
			}
			else {
				out << c.jsx_element(k.n)
			}
		}
		text_start = node_end_of(k.n)
	}
	end := if cl := field_of(kids, 'close_tag') { c.start(cl.n) } else { node_end_of(n) }
	if end > text_start {
		out << c.jsx_text(n, text_start, end)
	}
	return out
}

fn (mut c Converter) jsx_text(n C.TSNode, start int, end int) int {
	i := c.mk(.jsx_text, n, start, end)
	i_raw := c.slice(start, end)
	c.pstr(i, .raw, i_raw)
	c.pstr(i, .value, jsx_unescape(i_raw))
	c.t.nodes[i].has_ts = false
	return i
}
