module svelte

// Attributes and directives (src/parser/converts/attr.ts convertAttributes).

fn (mut c Conv) convert_attributes(attrs []int, parent int) []int {
	mut out := []int{}
	for a in attrs {
		cn := c.ca.nodes[a]
		r := match cn.typ {
			.attribute {
				c.convert_attribute(a, parent)
			}
			.spread_attribute {
				d := c.add(SNode{
					typ:    .spread_attribute
					start:  cn.start
					end:    cn.end
					parent: parent
				})
				at := c.index_of_from('...', cn.start)
				c.add_token('Punctuator', at, at + 3)
				c.add_expression(cn.expression, d, '', .expression, '')
				d
			}
			.attach_tag {
				d := c.add(SNode{
					typ:    .attach_tag
					start:  cn.start
					end:    cn.end
					parent: parent
				})
				c.add_expression(cn.expression, d, '', .expression, '')
				at := c.index_of_from('@attach', cn.start)
				c.add_token('MustacheKeyword', at, at + 7)
				d
			}
			.bind_directive {
				c.convert_directive(a, parent, 'Binding')
			}
			.on_directive {
				c.convert_directive(a, parent, 'EventHandler')
			}
			.class_directive {
				c.convert_directive(a, parent, 'Class')
			}
			.style_directive {
				c.convert_style_directive(a, parent)
			}
			.transition_directive {
				c.convert_directive(a, parent, 'Transition')
			}
			.animate_directive {
				c.convert_directive(a, parent, 'Animation')
			}
			.use_directive {
				c.convert_directive(a, parent, 'Action')
			}
			.let_directive {
				c.convert_directive(a, parent, 'Let')
			}
			else {
				c.fail('Unknown directive or attribute (${cn.typ.name()}) are not supported.',
					cn.start)
				-1
			}
		}
		if r >= 0 {
			out << r
		}
	}
	return out
}

fn (mut c Conv) convert_attribute(a int, parent int) int {
	cn := c.ca.nodes[a]
	attr := c.add(SNode{
		typ:    .attribute
		start:  cn.start
		end:    cn.end
		parent: parent
	})
	key_start := c.index_of_from(cn.name, cn.start)
	key_end := key_start + cn.name.len
	key := c.add(SNode{
		typ:    .name
		name:   cn.name
		start:  key_start
		end:    key_end
		parent: attr
	})
	c.doc.nodes[attr].key = sref(key)
	if cn.value_kind == .true_ {
		c.doc.nodes[attr].boolean = true
		c.add_token('HTMLIdentifier', key_start, key_end)
		return attr
	}
	if cn.value_kind == .node && c.ca.nodes[cn.value[0]].typ == .expression_tag
		&& c.code[cn.start] == `{` && c.code[cn.end - 1] == `}` {
		// SvelteShorthandAttribute: key and value are the script parser's identifiers.
		c.doc.nodes[attr].typ = .shorthand_attribute
		c.doc.nodes[attr].key = Ref{}
		c.doc.nodes[key].parent = -1
		c.add_object_shorthand_property(key_start, key_end, attr)
		return attr
	}
	c.add_token('HTMLIdentifier', key_start, key_end)
	c.process_attribute_value(cn.value, attr, parent)
	return attr
}

// process_attribute_value is processAttributeValue.
fn (mut c Conv) process_attribute_value(values []int, attr int, attr_parent int) {
	mut nodes := []CNode{}
	for v in values {
		vn := c.ca.nodes[v]
		if vn.typ == .text && vn.start >= vn.end {
			continue
		}
		nodes << vn
	}
	for k in 0 .. nodes.len {
		if nodes[k].typ == .text && k + 1 < nodes.len && nodes[k + 1].start < nodes[k].end {
			nodes[k].end = nodes[k + 1].start
		}
	}
	if nodes.len == 1 && nodes[0].typ == .expression_tag && c.doc.nodes[attr].typ == .attribute {
		key_name := c.doc.nodes[c.doc.nodes[attr].key.idx].name
		typing := c.build_attribute_type(c.doc.nodes[attr_parent].parent, key_name)
		m := c.mustache_of(nodes[0], attr, typing)
		c.doc.nodes[attr].values << m
		return
	}
	for v in nodes {
		if v.typ == .text {
			lit := c.add(SNode{
				typ:    .literal
				value:  v.data
				start:  v.start
				end:    v.end
				parent: attr
			})
			c.text_tokens(v.start, v.end)
			c.doc.nodes[attr].values << lit
			continue
		}
		m := c.mustache_of(v, attr, '')
		c.doc.nodes[attr].values << m
	}
}

fn (mut c Conv) mustache_of(v CNode, parent int, typing string) int {
	m := c.add(SNode{
		typ:    .mustache_tag
		kind:   'text'
		start:  v.start
		end:    v.end
		parent: parent
	})
	t := if typing != '' && c.has_type_info(v.expression) { '' } else { typing }
	c.add_expression(v.expression, m, t, .expression, '')
	return m
}

// process_directive_key is processDirectiveKey: the tokens of the prefix, name and modifiers
// and the SvelteDirectiveKey with its SvelteName.
fn (mut c Conv) process_directive_key(cn CNode, directive int) {
	dstart := c.doc.nodes[directive].start
	colon := c.index_of_from(':', dstart)
	c.add_token('HTMLIdentifier', dstart, colon)
	name_index := c.index_of_from(cn.name, colon + 1)
	name_end := name_index + cn.name.len
	mut key_end := name_end
	if name_end < c.code.len && c.code[name_end] == `|` {
		mut next_start := name_end + 1
		mut next_end := c.modifier_end(next_start)
		c.add_token('HTMLIdentifier', next_start, next_end)
		for next_end < c.code.len && c.code[next_end] == `|` {
			next_start = next_end + 1
			next_end = c.modifier_end(next_start)
			c.add_token('HTMLIdentifier', next_start, next_end)
		}
		key_end = next_end
	}
	key := c.add(SNode{
		typ:       .directive_key
		modifiers: cn.modifiers
		start:     cn.start
		end:       key_end
		parent:    directive
	})
	name := c.add(SNode{
		typ:    .name
		name:   cn.name
		start:  name_index
		end:    name_end
		parent: key
	})
	c.doc.nodes[key].key = sref(name) // the key's `name`
	c.doc.nodes[directive].key = sref(key)
}

fn (c &Conv) modifier_end(from int) int {
	mut i := from
	for i < c.code.len {
		ch := c.code[i]
		if ch == `=` || ch == `>` || ch == `/` || ch == `|` || is_space_at(c.code, i) {
			return i
		}
		i++
	}
	return -1
}

fn (mut c Conv) convert_directive(a int, parent int, kind string) int {
	cn := c.ca.nodes[a]
	d := c.add(SNode{
		typ:    .directive
		kind:   kind
		start:  cn.start
		end:    cn.end
		parent: parent
		intro:  cn.intro
		outro:  cn.outro
	})
	c.process_directive_key(cn, d)
	key := c.doc.nodes[d].key.idx
	key_name := c.doc.nodes[key].key.idx
	kn := c.doc.nodes[key_name]
	element := c.doc.nodes[parent].parent
	mut shorthand := false
	if cn.expression >= 0 {
		ex := c.ca.exprs[cn.expression]
		shorthand = ex.kind == .identifier && ex.name == cn.name && ex.start == kn.start
		if shorthand && ex.end != kn.end {
			c.ca.exprs[cn.expression].end = kn.end
		}
		// The type of the script parser's node must be the compiler's (processDirectiveExpression):
		// checked for the compiler's own Identifier of `bind:x` / `class:x`.
		check := if ex.synthetic { 'compiler:Identifier' } else { '' }
		match kind {
			'Binding' {
				c.doc.nodes[d].shorthand = shorthand
				typing := c.build_function_bindings_type(cn, element, cn.expression)
				s, e := c.node_range(cn.expression)
				part := c.code[s..e]
				typed := typing != ''
				text := if typed { '(${part})as (${typing});' } else { '(${part});' }
				c.append_let(ScriptLet{
					kind:      .expression
					node_type: 'ExpressionStatement'
					segments:  [Segment{1, part.len, s}]
					target:    d
					setter:    .expression
					typed:     typed
					binding:   true
					check:     check
				}, text, c.current_kind)
			}
			'EventHandler' {
				typing := c.build_event_handler_type(element, cn.name)
				t := if c.has_type_info(cn.expression) { '' } else { typing }
				c.add_expression(cn.expression, d, t, .expression, '')
			}
			'Class' {
				c.doc.nodes[d].shorthand = shorthand
				c.add_expression(cn.expression, d, '', .expression, check)
			}
			'Action' {
				typing := 'Parameters<typeof ${cn.name}>[1]'
				t := if c.has_type_info(cn.expression) { '' } else { typing }
				c.add_expression(cn.expression, d, t, .expression, '')
			}
			'Let' {
				ps, pe := c.node_range(cn.expression)
				c.add_let_param(ps, pe, c.build_let_directive_type(element, cn.name), ParamSetter{
					node:  d
					field: 2
				}, d)
			}
			else {
				// Transition, Animation.
				c.add_expression(cn.expression, d, '', .expression, '')
			}
		}
	}
	if !shorthand {
		match kind {
			'Transition', 'Animation' {
				c.add_name_expression(key_name, key, .key_name, 'Identifier')
			}
			'Action' {
				c.add_name_expression(key_name, key, .key_name, 'Identifier, or MemberExpression')
			}
			'Let' {
				if cn.expression < 0 {
					c.add_let_param(kn.start, kn.end, c.build_let_directive_type(element,
						cn.name), ParamSetter{
						node:  d
						field: 2
					}, d)
				} else {
					c.add_token('HTMLIdentifier', kn.start, kn.end)
				}
			}
			else {
				c.add_token('HTMLIdentifier', kn.start, kn.end)
			}
		}
	}
	return d
}

fn (mut c Conv) add_let_param(s int, e int, typing string, setter ParamSetter, parent int) {
	if c.letdir_stack.len == 0 {
		return
	}
	c.letdir_stack[c.letdir_stack.len - 1] << LetParam{
		start:  s
		end:    e
		typing: typing
		setter: setter
		parent: parent
	}
}

// build_function_bindings_type is buildFunctionBindingsType.
fn (c &Conv) build_function_bindings_type(cn CNode, element int, expr int) string {
	en := c.doc.nodes[element]
	if en.typ != .element || en.kind != 'component' {
		return ''
	}
	ex := c.ca.exprs[expr]
	if ex.kind != .sequence || ex.elems.len != 2 || !c.is_function_bindings_text(ex.start) {
		return ''
	}
	prop := c.build_attribute_type(element, cn.name)
	if prop == '' {
		return ''
	}
	return '(value: [${prop}] extends [never] ? any : (${prop})) => void'
}

// is_function_bindings_text: the text between the `{` before the expression and the expression
// is empty once comments are removed (isFunctionBindings).
fn (c &Conv) is_function_bindings_text(start int) bool {
	open := c.code[..start].last_index('{') or { return false }
	between := strip_js_comments(c.code[open + 1..start])
	return is_blank(between)
}

// strip_js_comments is `.replace(/\/\/[^\n]*\n|\/\*[\s\S]*?\*\//g, "")`.
fn strip_js_comments(s string) string {
	mut out := []u8{cap: s.len}
	mut i := 0
	for i < s.len {
		if s[i] == `/` && i + 1 < s.len && s[i + 1] == `/` {
			nl := s.index_after('\n', i + 2) or { -1 }
			if nl >= 0 {
				i = nl + 1
				continue
			}
		}
		if s[i] == `/` && i + 1 < s.len && s[i + 1] == `*` {
			e := s.index_after('*/', i + 2) or { -1 }
			if e >= 0 {
				i = e + 2
				continue
			}
		}
		out << s[i]
		i++
	}
	return out.bytestr()
}

fn (mut c Conv) convert_style_directive(a int, parent int) int {
	cn := c.ca.nodes[a]
	d := c.add(SNode{
		typ:    .style_directive
		start:  cn.start
		end:    cn.end
		parent: parent
	})
	c.process_directive_key(cn, d)
	key := c.doc.nodes[d].key.idx
	key_name := c.doc.nodes[key].key.idx
	if cn.value_kind == .true_ {
		c.doc.nodes[d].shorthand = true
		c.add_name_expression(key_name, key, .key_name, 'style_identifier')
		return d
	}
	kn := c.doc.nodes[key_name]
	c.add_token('HTMLIdentifier', kn.start, kn.end)
	c.process_attribute_value(cn.value, d, parent)
	return d
}
