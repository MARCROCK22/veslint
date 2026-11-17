module vue

// The conversion of directive attributes and the parse of mustaches (src/template/index.ts).

fn (mut c ExprContext) run_postprocesses(post []PostProcess) {
	for pp in post {
		match pp.kind {
			.directive { c.convert_to_directive(pp.node) }
			.resolve { c.resolve_element(pp.node) }
			.mustache { c.process_mustache(pp.node, pp.tok) }
		}
	}
}

// camelize is /-(\w)/g -> upper case.
fn camelize(s string) string {
	if !s.contains('-') {
		return s
	}
	mut out := []u8{cap: s.len}
	mut i := 0
	for i < s.len {
		if s[i] == `-` && i + 1 < s.len && is_word_char(s[i + 1]) {
			c := s[i + 1]
			out << if c >= `a` && c <= `z` { c - 32 } else { c }
			i += 2
			continue
		}
		out << s[i]
		i++
	}
	return out.bytestr()
}

// add_identifier makes a VIdentifier of the directive key from [start, end) of its text.
fn (mut c ExprContext) key_identifier(key int, offset int, text string, raw string, start int, end int, name ?string) int {
	return c.doc.add_node(VNode{
		typ:      .v_identifier
		parent:   key
		start:    offset + start
		end:      offset + end
		name:     name or { text[start..end] }
		raw_name: raw[start..end]
	})
}

// parse_directive_key_statically is parseDirectiveKeyStatically: the name, the argument and the
// modifiers of the attribute name (a key is a single line).
fn (mut c ExprContext) parse_directive_key_statically(attr_key int) int {
	node := c.doc.nodes[attr_key]
	text := node.name
	raw := node.raw_name
	offset := node.start
	key := c.doc.add_node(VNode{
		typ:    .v_directive_key
		start:  node.start
		end:    node.end
		parent: node.parent
	})
	mut i := 0
	mut name := -1
	mut argument := -1
	if text.len > 0 && text[0] in [`.`, `:`, `@`, `#`] {
		sign := match text[0] {
			`:`, `.` { 'bind' }
			`@` { 'on' }
			else { 'slot' }
		}
		name = c.key_identifier(key, offset, text, raw, 0, 1, sign)
		i = 1
	} else {
		colon := text.index_u8(`:`)
		if colon != -1 {
			name = c.key_identifier(key, offset, text, raw, 0, colon, none)
			i = colon + 1
		}
	}
	if name >= 0 && i < text.len && text[i] == `[` {
		len := text[i..].last_index_u8(`]`)
		if len != -1 {
			argument = c.key_identifier(key, offset, text, raw, i, i + len + 1, none)
			i = i + len + 1 + if i + len + 1 < text.len && text[i + len + 1] == `.` { 1 } else { 0 }
		}
	}
	mut modifiers := []int{}
	rest := if i <= text.len { text[i..] } else { '' }
	for part in rest.split('.') {
		modifier := c.key_identifier(key, offset, text, raw, i, i + part.len, none)
		if part == '' && i < text.len {
			c.doc.insert_error(ParseError{
				message: "Unexpected token '${text[i..i + 1]}'"
				index:   offset + i
			})
		}
		i += part.len + 1
		modifiers << modifier
	}
	if name < 0 {
		name = modifiers[0]
		modifiers.delete(0)
	} else if argument < 0 && c.doc.nodes[modifiers[0]].name != '' {
		argument = modifiers[0]
		modifiers.delete(0)
	}
	modifiers = modifiers.filter(c.doc.nodes[it].name != '')
	if c.doc.nodes[name].name == 'v-' {
		at := c.doc.nodes[name].end
		ch := if at - offset < text.len { text[at - offset..at - offset + 1] } else { 'undefined' }
		c.doc.insert_error(ParseError{
			message: "Unexpected token '${ch}'"
			index:   at
		})
	}
	if c.doc.nodes[name].raw_name == '.' && !modifiers.any(c.doc.nodes[it].name == 'prop') {
		base := if argument >= 0 { argument } else { name }
		pos := c.doc.nodes[base].end - offset
		prop := c.key_identifier(key, offset, text, raw, pos, pos, 'prop')
		modifiers.insert(0, prop)
	}
	c.doc.nodes[key].dir_name = name
	c.doc.nodes[key].argument = argument
	c.doc.nodes[key].modifiers = modifiers
	return key
}

// directive_key_tokens is parseDirectiveKeyTokens.
fn (c &ExprContext) directive_key_tokens(key int) []Token {
	k := c.doc.nodes[key]
	name := c.doc.nodes[k.dir_name]
	shorthand := name.end - name.start == 1
	mut tokens := []Token{}
	if shorthand {
		tokens << Token{
			typ:   'Punctuator'
			start: name.start
			end:   name.end
			value: name.raw_name
		}
	} else {
		tokens << Token{
			typ:   'HTMLIdentifier'
			start: name.start
			end:   name.end
			value: name.raw_name
		}
		if k.argument >= 0 {
			tokens << Token{
				typ:   'Punctuator'
				start: name.end
				end:   c.doc.nodes[k.argument].start
				value: ':'
			}
		}
	}
	if k.argument >= 0 {
		arg := c.doc.nodes[k.argument]
		tokens << Token{
			typ:   'HTMLIdentifier'
			start: arg.start
			end:   arg.end
			value: arg.raw_name
		}
	}
	mut last := if k.argument >= 0 { k.argument } else { k.dir_name }
	for m in k.modifiers {
		modifier := c.doc.nodes[m]
		if modifier.raw_name == '' {
			continue
		}
		tokens << Token{
			typ:   'Punctuator'
			start: c.doc.nodes[last].end
			end:   modifier.start
			value: '.'
		}
		tokens << Token{
			typ:   'HTMLIdentifier'
			start: modifier.start
			end:   modifier.end
			value: modifier.raw_name
		}
		last = m
	}
	return tokens
}

// create_directive_key is createDirectiveKey: the key, its tokens (replacing the attribute
// name's), the `v-` prefix dropped, and a dynamic argument parsed.
fn (mut c ExprContext) create_directive_key(attr_key int) int {
	key := c.parse_directive_key_statically(attr_key)
	mut tokens := c.directive_key_tokens(key)
	name := c.doc.nodes[key].dir_name
	if c.doc.nodes[name].name.starts_with('v-') {
		c.doc.nodes[name].name = c.doc.nodes[name].name[2..]
	}
	if c.doc.nodes[name].raw_name.starts_with('v-') {
		c.doc.nodes[name].raw_name = c.doc.nodes[name].raw_name[2..]
	}
	c.convert_dynamic_argument(key, mut tokens)
	c.replacements << Replacement{
		start:  c.doc.nodes[key].start
		end:    c.doc.nodes[key].end
		tokens: tokens
	}
	return key
}

// convert_dynamic_argument is convertDynamicArgument; its tokens replace the argument's in the
// key's tokens.
fn (mut c ExprContext) convert_dynamic_argument(key int, mut key_tokens []Token) {
	argument := c.doc.nodes[key].argument
	if argument < 0 || c.doc.nodes[argument].typ != .v_identifier {
		return
	}
	arg := c.doc.nodes[argument]
	if !(arg.name.starts_with('[') && arg.name.ends_with(']')) {
		return
	}
	code := arg.raw_name[1..arg.raw_name.len - 1]
	start16 := c.doc.utf16(arg.start)
	end16 := c.doc.utf16(arg.end)
	calc := c.doc.sub_after(c.doc.html_calc(0, 0), start16 + 1)
	container := c.doc.add_node(VNode{
		typ:    .v_expression_container
		start:  arg.start
		end:    arg.end
		parent: key
	})
	c.doc.nodes[key].argument = container
	ret := c.parse_expression(code, calc, false, false) or {
		if err is ParseErr {
			c.doc.insert_error(err.perr)
			return
		}
		panic(err)
	}
	c.set_container(container, ret)
	mut tokens := []Token{cap: ret.tokens.len + 2}
	tokens << c.simple_token('Punctuator', start16, start16 + 1, '[')
	tokens << ret.tokens
	tokens << c.simple_token('Punctuator', end16 - 1, end16, ']')
	index := sorted_index_by_start(key_tokens, arg.start)
	last := sorted_last_index_by_end(key_tokens, arg.end)
	if last > index {
		key_tokens.delete_many(index, last - index)
	}
	key_tokens.insert(index, tokens)
	c.doc.insert_comments(ret.comments)
}

// set_container gives a VExpressionContainer the expression and the references of a result.
fn (mut c ExprContext) set_container(container int, ret ExprResult) {
	c.doc.nodes[container].expression = ret.expression
	if ret.expression.kind == .vnode {
		c.doc.nodes[ret.expression.node].parent = container
		c.reparent(ret.expression.node)
	}
	for r in ret.references {
		c.doc.references << r
		c.doc.nodes[container].references << c.doc.references.len - 1
	}
}

// reparent sets the parent of the V* nodes inside a V* expression.
fn (mut c ExprContext) reparent(node int) {
	for f in c.doc.nodes[node].filters {
		c.doc.nodes[f].parent = node
	}
}

fn (c &ExprContext) is_script_setup_ts(element int) bool {
	if !c.doc.is_script_setup(element) {
		return false
	}
	lang := c.doc.lang_of(element) or { return false }
	return lang == 'ts' || lang == 'tsx'
}

// directive_kind is getStandardDirectiveKind.
fn (c &ExprContext) directive_kind(element int, key int) string {
	name := c.doc.nodes[c.doc.nodes[key].dir_name].name
	el := c.doc.nodes[element]
	if name == 'for' {
		return 'for'
	} else if name == 'on' {
		return 'on'
	} else if name == 'slot' || name == 'slot-scope' || (name == 'scope' && el.raw_name == 'template') {
		return 'slot'
	} else if name == 'bind' {
		return 'bind'
	} else if name == 'generic' && el.parent == 0 && el.raw_name == 'script'
		&& c.is_script_setup_ts(element) {
		return 'generic'
	}
	return ''
}

// convert_to_directive is convertToDirective.
fn (mut c ExprContext) convert_to_directive(attr int) {
	c.doc.nodes[attr].directive = true
	key := c.create_directive_key(c.doc.nodes[attr].key)
	c.doc.nodes[key].parent = attr
	c.doc.nodes[attr].key = key
	argument := c.doc.nodes[key].argument
	if argument >= 0 && c.doc.nodes[argument].typ == .v_identifier
		&& c.doc.nodes[argument].name.starts_with('[') {
		at := c.doc.nodes[argument].end
		mut ch := ''
		mut bad := false
		if at >= c.doc.src.len {
			ch = 'EOF'
			bad = true
		} else {
			b := c.doc.src[at]
			if b in [` `, `\t`, `\n`, `\r`, `=`, `/`, `>`, `\f`, `\v`] {
				bad = true
				ch = match b {
					`\t` { '\\t' }
					`\n` { '\\n' }
					`\r` { '\\r' }
					`\f` { '\\f' }
					`\v` { '\\u000b' }
					else { b.ascii_str() }
				}
			} else {
				cp, _ := decode_cp(c.doc.src, at)
				if is_js_space(cp) {
					bad = true
					ch = cp_to_string(cp)
				}
			}
		}
		if bad {
			c.doc.insert_error(ParseError{
				message: "Dynamic argument cannot contain the '${ch}' character."
				index:   at
			})
		}
	}
	value := c.doc.nodes[attr].value
	if value < 0 {
		if c.doc.nodes[c.doc.nodes[key].dir_name].name == 'bind' {
			c.v_bind_same_name_shorthand(attr)
		}
		return
	}
	literal := c.doc.nodes[value]
	element := c.doc.nodes[c.doc.nodes[attr].parent].parent
	container := c.doc.add_node(VNode{
		typ:    .v_expression_container
		start:  literal.start
		end:    literal.end
		parent: attr
	})
	c.doc.nodes[attr].value = container
	ret := c.parse_attribute_value(literal, element, key) or {
		if err is ParseErr {
			c.doc.insert_error(err.perr)
			return
		}
		panic(err)
	}
	c.set_container(container, ret)
	for v in ret.variables {
		c.doc.variables << v
		c.doc.nodes[element].variables << c.doc.variables.len - 1
	}
	c.replacements << Replacement{
		start:  literal.start
		end:    literal.end
		tokens: ret.tokens
	}
	c.doc.insert_comments(ret.comments)
}

// parse_attribute_value is parseAttributeValue.
fn (mut c ExprContext) parse_attribute_value(literal VNode, element int, key int) !ExprResult {
	first := c.doc.src[literal.start]
	quoted := first == `"` || first == `'`
	start16 := c.doc.utf16(literal.start)
	end16 := c.doc.utf16(literal.end)
	calc := c.doc.sub_after(c.doc.html_calc(0, 0), start16 + if quoted { 1 } else { 0 })
	kind := c.directive_kind(element, key)
	code := literal.text
	mut result := if quoted && code == '' {
		ExprResult{}
	} else if kind == 'for' {
		c.parse_v_for(code, calc)!
	} else if kind == 'on' && c.doc.nodes[key].argument >= 0 {
		c.parse_v_on(code, calc)!
	} else if kind == 'slot' {
		c.parse_slot_scope(code, calc)!
	} else if kind == 'bind' {
		c.parse_expression(code, calc, false, true)!
	} else if kind == 'generic' {
		c.parse_generic(code, calc)!
	} else {
		c.parse_expression(code, calc, false, false)!
	}
	if quoted {
		q := first.ascii_str()
		result.tokens.insert(0, c.simple_token('Punctuator', start16, start16 + 1, q))
		result.tokens << c.simple_token('Punctuator', end16 - 1, end16, q)
	}
	return result
}

// v_bind_same_name_shorthand is convertForVBindSameNameShorthandValue (`:foo` is `:foo="foo"`):
// an Identifier and a reference, without tokens.
fn (mut c ExprContext) v_bind_same_name_shorthand(attr int) {
	key := c.doc.nodes[attr].key
	argument := c.doc.nodes[key].argument
	if argument < 0 || c.doc.nodes[argument].typ != .v_identifier {
		return
	}
	arg := c.doc.nodes[argument]
	calc := c.doc.sub_after(c.doc.html_calc(0, 0), c.doc.utf16(arg.start))
	frag := c.parse_fragment(camelize(arg.raw_name), calc) or { return }
	es := c.es(frag.snippet)
	body := es.list(frag.root, .body) or { return }
	if body.len != 1 || es.typ(body[0]) != .expression_statement {
		return
	}
	id := es.node(body[0], .expression) or { return }
	if es.typ(id) != .identifier {
		return
	}
	c.doc.snippets[frag.snippet].es.nodes[id].end = arg.end
	container := c.doc.add_node(VNode{
		typ:        .v_expression_container
		start:      arg.start
		end:        arg.end
		parent:     attr
		expression: c.es_expr(frag.snippet, id)
	})
	c.doc.references << Reference{
		id:   c.es_expr(frag.snippet, id)
		name: es.string_of(id, .name) or { '' }
		mode: 'r'
	}
	c.doc.nodes[container].references << c.doc.references.len - 1
	c.doc.nodes[attr].value = container
}

// process_mustache is processMustache.
fn (mut c ExprContext) process_mustache(container int, tok IToken) {
	start16 := c.doc.utf16(tok.open_end)
	calc := c.doc.sub_after(c.doc.html_calc(0, 0), start16)
	ret := c.parse_expression(tok.value, calc, true, true) or {
		if err is ParseErr {
			c.doc.insert_error(err.perr)
			c.resolve_references(container)
			return
		}
		panic(err)
	}
	c.set_container(container, ret)
	c.replacements << Replacement{
		start:  tok.open_end
		end:    tok.close_start
		tokens: ret.tokens
	}
	c.doc.insert_comments(ret.comments)
	c.resolve_references(container)
}

// resolve_element resolves the references of the directives of an element.
fn (mut c ExprContext) resolve_element(element int) {
	start_tag := c.doc.nodes[c.doc.nodes[element].start_tag]
	for a in start_tag.attributes {
		attr := c.doc.nodes[a]
		if !attr.directive {
			continue
		}
		argument := c.doc.nodes[attr.key].argument
		if argument >= 0 && c.doc.nodes[argument].typ == .v_expression_container {
			c.resolve_references(argument)
		}
		if attr.value >= 0 {
			c.resolve_references(attr.value)
		}
	}
}

// resolve_references is resolveReferences: each reference of the container to the first
// variable of that name of its element or of an ancestor element.
fn (mut c ExprContext) resolve_references(container int) {
	mut element := c.doc.nodes[container].parent
	for element >= 0 && c.doc.nodes[element].typ != .v_element {
		element = c.doc.nodes[element].parent
	}
	if element < 0 {
		return
	}
	for r in c.doc.nodes[container].references {
		name := c.doc.references[r].name
		mut node := element
		mut found := false
		for node >= 0 && c.doc.nodes[node].typ == .v_element {
			for v in c.doc.nodes[node].variables {
				if c.doc.variables[v].name == name {
					c.doc.references[r].variable = v
					c.doc.variables[v].references << r
					found = true
					break
				}
			}
			if found {
				break
			}
			node = c.doc.nodes[node].parent
		}
	}
}
