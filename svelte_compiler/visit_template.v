module svelte_compiler

// The visitors of template nodes (2-analyze/visitors/*.js and visitors/shared/{attribute,
// component,element,special-element}.js).

fn (mut z Analyzer) with_expression(st State) State {
	mut s := z.copy_state(st)
	s.expression = true
	return s
}

fn (mut z Analyzer) v_fragment(node int, st State) ! {
	mut s := z.copy_state(st)
	s.fragment = node
	z.next(node, s)!
}

fn (mut z Analyzer) v_expression_holder(node int, st State) ! {
	z.next(node, z.with_expression(st))!
}

fn (mut z Analyzer) v_directive(node int, st State) ! {
	z.next(node, z.with_expression(st))!
}

fn (mut z Analyzer) v_expression_tag(node int, st State) ! {
	in_template := z.t.typ(z.path_at(-1)) == 'Fragment'
	if in_template && st.has_parent_element {
		message := is_tag_valid_with_parent('#text', st.parent_element)
		if message != '' {
			return z.error_at(node, e_node_invalid_placement(message))
		}
	}
	z.next(node, z.with_expression(st))!
}

fn is_not_whitespace_text(s string) bool {
	for c in s {
		if c !in [` `, `\t`, `\r`, `\n`] {
			return true
		}
	}
	return false
}

fn (mut z Analyzer) v_text(node int, st State) ! {
	t := z.t
	parent := z.path_at(-1)
	data := t.text(node, .data)
	if t.typ(parent) == 'Fragment' && st.has_parent_element && is_not_whitespace_text(data) {
		message := is_tag_valid_with_parent('#text', st.parent_element)
		if message != '' {
			return z.error_at(node, e_node_invalid_placement(message))
		}
	}
	// regex_bidirectional_control_characters (global): each run of them.
	mut i := 0
	for i < data.len {
		r, n := rune_at(data, i)
		if !is_bidi(r) {
			i += n
			continue
		}
		mut j := i
		for j < data.len {
			r2, n2 := rune_at(data, j)
			if !is_bidi(r2) {
				break
			}
			j += n2
		}
		mut is_ignored := false
		if t.typ(parent) == 'Fragment' {
			for ch in t.list(parent, .nodes) {
				if ch == node {
					break
				}
				if t.typ(ch) == 'Comment' && !is_ignored {
					if 'bidirectional_control_characters' in z.extract_svelte_ignore(t.nodes[ch].start + 4,
						t.text(ch, .data), z.runes) {
						is_ignored = true
					}
				}
			}
		}
		if !is_ignored {
			start := t.nodes[node].start + i
			z.warn_range(start, start + (j - i), w_bidirectional_control_characters())
		}
		i = j
	}
}

fn rune_at(s string, i int) (rune, int) {
	if s[i] < 0x80 {
		return rune(s[i]), 1
	}
	n := utf8_char_len(s[i])
	if i + n > s.len {
		return rune(s[i]), 1
	}
	return s[i..i + n].runes()[0], n
}

fn is_bidi(r rune) bool {
	return r in [rune(0x202a), 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067, 0x2068, 0x2069]
}

fn (mut z Analyzer) v_html_tag(node int, st State) ! {
	if z.runes {
		z.validate_opening_tag(node, '@')!
	}
	z.next(node, z.with_expression(st))!
}

fn (mut z Analyzer) v_debug_tag(node int, st State) ! {
	if z.runes {
		z.validate_opening_tag(node, '@')!
	}
	z.next(node, st)!
}

fn (mut z Analyzer) v_const_tag(node int, st State) ! {
	t := z.t
	if z.runes {
		z.validate_opening_tag(node, '@')!
	}
	parent := z.path_at(-1)
	gp := z.path_at(-2)
	gpt := t.typ(gp)
	mut has_slot := false
	if gpt in ['RegularElement', 'SvelteElement'] {
		for a in t.list(gp, .attributes) {
			if t.typ(a) == 'Attribute' && t.name(a) == 'slot' {
				has_slot = true
			}
		}
	}
	if t.typ(parent) != 'Fragment' || (gpt !in ['IfBlock', 'SvelteFragment', 'Component',
		'SvelteComponent', 'EachBlock', 'AwaitBlock', 'SnippetBlock', 'SvelteBoundary', 'KeyBlock']
		&& (gpt !in ['RegularElement', 'SvelteElement'] || !has_slot)) {
		return z.error_at(node, e_const_tag_invalid_placement())
	}
	decl := t.list(t.get(node, .declaration), .declarations)[0]
	z.child(node, t.get(decl, .id), st)!
	mut s := z.with_expression(st)
	s.function_depth = st.function_depth + 1
	s.derived_function_depth = st.function_depth + 1
	z.child(node, t.get(decl, .init), s)!
}

fn (mut z Analyzer) v_declaration_tag(node int, st State) ! {
	decl := z.t.get(node, .declaration)
	z.validate_opening_tag(node, z.t.text(decl, .kind)[..1])!
	if !z.runes && !z.maybe_runes {
		return z.error_at(node, e_declaration_tag_no_legacy_mode())
	}
	mut s := z.with_expression(st)
	s.in_declaration_tag = true
	z.child(node, decl, s)!
}

fn (mut z Analyzer) v_if(node int, st State) ! {
	z.validate_block_not_empty(z.t.get(node, .consequent))
	z.validate_block_not_empty(z.t.get(node, .alternate))
	if z.runes {
		z.validate_opening_tag(node, if z.t.flag(node, .elseif) { ':' } else { '#' })!
	}
	z.child(node, z.t.get(node, .test), z.with_expression(st))!
	z.child(node, z.t.get(node, .consequent), st)!
	z.child(node, z.t.get(node, .alternate), st)!
}

fn (mut z Analyzer) v_each(node int, st State) ! {
	t := z.t
	z.validate_opening_tag(node, '#')!
	z.validate_block_not_empty(t.get(node, .body))
	z.validate_block_not_empty(t.get(node, .fallback))
	id := t.get(node, .context)
	if t.typ(id) == 'Identifier' && t.name(id) in ['\$state', '\$derived'] {
		return z.error_at(node, e_state_invalid_placement(t.name(id)))
	}
	key := t.get(node, .key)
	mut keyed := false
	if key >= 0 {
		index := t.text(node, .index)
		keyed = t.typ(key) != 'Identifier' || !t.has(node, .index) || t.name(key) != index
	}
	if keyed && id < 0 {
		return z.error_at(key, e_each_key_without_as())
	}
	z.each_keyed[node] = keyed
	mut s := z.with_expression(st)
	s.scope = z.s.scopes[st.scope].parent
	z.child(node, t.get(node, .expression), s)!
	z.child(node, t.get(node, .body), st)!
	if key >= 0 {
		z.child(node, key, st)!
	}
	z.child(node, t.get(node, .fallback), st)!
	if !z.runes {
		mut mutated := false
		if id >= 0 {
			for i in t.extract_identifiers(id) {
				b := z.s.get(st.scope, t.name(i))
				if b >= 0 && z.s.bindings[b].mutated {
					mutated = true
				}
			}
		}
		if mutated {
			// The transitive dependencies of the expression become state.
			mut deps := []int{}
			z.collect_expression_bindings(t.get(node, .expression), -1, z.s.scopes[st.scope].parent, mut
				deps)
			mut transitive := []int{}
			for d in deps {
				if z.s.bindings[d].declaration_kind != 'function' {
					z.collect_transitive(d, mut transitive)
				}
			}
			for b in transitive {
				binding := z.s.bindings[b]
				if binding.kind == 'normal' && binding.declaration_kind in ['const', 'let', 'var'] {
					z.s.bindings[b].kind = 'state'
				}
			}
		}
	}
}

// collect_expression_bindings: the bindings an expression references (its metadata
// dependencies), functions included.
fn (z &Analyzer) collect_expression_bindings(node int, parent int, scope int, mut out []int) {
	if node < 0 {
		return
	}
	mut sc := scope
	if s := z.s.of[node] {
		sc = s
	}
	typ := z.t.typ(node)
	if typ == 'Identifier' {
		if parent < 0 || z.t.is_reference(node, parent) {
			b := z.s.get(sc, z.t.name(node))
			if b >= 0 && b !in out {
				out << b
			}
		}
		return
	}
	// visit_function: no expression metadata inside functions.
	if typ in ['ArrowFunctionExpression', 'FunctionExpression', 'FunctionDeclaration'] {
		return
	}
	for ch in z.t.children(node) {
		z.collect_expression_bindings(ch, node, sc, mut out)
	}
}

fn (z &Analyzer) collect_transitive(binding int, mut out []int) {
	if binding in out {
		return
	}
	out << binding
	if z.s.bindings[binding].kind == 'legacy_reactive' {
		for d in z.s.bindings[binding].legacy_dependencies {
			z.collect_transitive(d, mut out)
		}
	}
}

fn (mut z Analyzer) v_await_block(node int, st State) ! {
	t := z.t
	z.validate_block_not_empty(t.get(node, .pending))
	z.validate_block_not_empty(t.get(node, .then))
	z.validate_block_not_empty(t.get(node, .catch_))
	if z.runes {
		z.validate_opening_tag(node, '#')!
		for k, kw in ['then', 'catch'] {
			v := t.get(node, if k == 0 { Key.value } else { Key.error })
			if v < 0 {
				continue
			}
			start := t.nodes[v].start
			from := if start - 10 < 0 { 0 } else { start - 10 }
			before := z.c.src[from..start]
			// /{(\s*):then\s+$/
			if lead := await_lead(before, kw) {
				if lead != '' {
					return z.error_range(start - 10, start, e_block_unexpected_character(':'))
				}
			}
		}
	}
	z.child(node, t.get(node, .expression), z.with_expression(st))!
	z.child(node, t.get(node, .pending), st)!
	z.child(node, t.get(node, .then), st)!
	z.child(node, t.get(node, .catch_), st)!
}

// await_lead matches /{(\s*):KW\s+$/ against `s`, giving the white space captured.
fn await_lead(s string, kw string) ?string {
	mut e := s.len
	mut ws := 0
	for e > 0 && s[e - 1] in [` `, `\t`, `\n`, `\r`, `\f`, `\v`] {
		e--
		ws++
	}
	if ws == 0 {
		return none
	}
	tail := ':' + kw
	if e < tail.len || s[e - tail.len..e] != tail {
		return none
	}
	e -= tail.len
	mut b := e
	for b > 0 && s[b - 1] in [` `, `\t`, `\n`, `\r`, `\f`, `\v`] {
		b--
	}
	if b == 0 || s[b - 1] != `{` {
		return none
	}
	return s[b..e]
}

fn (mut z Analyzer) v_key(node int, st State) ! {
	z.validate_block_not_empty(z.t.get(node, .fragment))
	if z.runes {
		z.validate_opening_tag(node, '#')!
	}
	z.child(node, z.t.get(node, .expression), z.with_expression(st))!
	z.child(node, z.t.get(node, .fragment), st)!
}

fn (mut z Analyzer) v_snippet(node int, st State) ! {
	t := z.t
	z.snippets << node
	z.validate_block_not_empty(t.get(node, .body))
	if z.runes {
		z.validate_opening_tag(node, '#')!
	}
	for arg in t.list(node, .parameters) {
		if t.typ(arg) == 'RestElement' {
			return z.error_at(arg, e_snippet_invalid_rest_parameter())
		}
	}
	mut s := z.copy_state(st)
	s.has_parent_element = false
	s.parent_element = ''
	z.next(node, s)!
	can_hoist := z.path.len == 1 && t.typ(z.path[0]) == 'Fragment'
		&& z.can_hoist_snippet(st.scope, mut []int{})
	name := t.name(t.get(node, .expression))
	if can_hoist {
		binding := z.s.get(st.scope, name)
		z.s.scopes[z.module_scope].declarations[name] = binding
	}
	parent := z.path_at(-2)
	if parent < 0 {
		return
	}
	if t.typ(parent) == 'Component' {
		for a in t.list(parent, .attributes) {
			if t.typ(a) in ['Attribute', 'BindDirective'] && t.name(a) == name {
				return z.error_at(node, e_snippet_shadowing_prop(name))
			}
		}
	}
	if name != 'children' {
		return
	}
	if t.typ(parent) in ['Component', 'SvelteComponent', 'SvelteSelf'] {
		for n in t.list(t.get(parent, .fragment), .nodes) {
			nt := t.typ(n)
			if nt != 'SnippetBlock' && (nt != 'Text' || t.text(n, .data).trim_space() != '')
				&& nt != 'Comment' {
				return z.error_at(node, e_snippet_conflict())
			}
		}
	}
}

fn (z &Analyzer) can_hoist_snippet(scope int, mut visited []int) bool {
	for name, _ in z.s.scopes[scope].references {
		binding := z.s.get(scope, name)
		if binding < 0 {
			continue
		}
		b := z.s.bindings[binding]
		if z.s.scopes[b.scope].function_depth == 0 {
			continue
		}
		if z.s.scopes[b.scope].function_depth >= z.s.scopes[scope].function_depth {
			continue
		}
		if z.t.typ(b.initial) == 'SnippetBlock' {
			if binding in visited {
				continue
			}
			visited << binding
			if z.can_hoist_snippet(z.s.of[b.initial], mut visited) {
				continue
			}
		}
		return false
	}
	return true
}

fn (mut z Analyzer) v_render(node int, st State) ! {
	t := z.t
	z.validate_opening_tag(node, '@')!
	z.meta_path[node] = z.path.clone()
	expression := t.unwrap_optional(t.get(node, .expression))
	callee := t.get(expression, .callee)
	binding := if t.typ(callee) == 'Identifier' { z.s.get(st.scope, t.name(callee)) } else { -1 }
	resolved := t.typ(callee) == 'Identifier' && z.is_resolved_snippet(binding)
	if binding >= 0 && t.typ(z.s.bindings[binding].initial) == 'SnippetBlock' {
		z.add_snippet(node, z.s.bindings[binding].initial)
	}
	z.snippet_renderers << node
	z.snippet_resolved << resolved
	z.uses_render_tags = true
	for arg in t.list(expression, .arguments) {
		if t.typ(arg) == 'SpreadElement' {
			return z.error_at(arg, e_render_tag_invalid_spread_argument())
		}
	}
	if t.typ(callee) == 'MemberExpression' && t.typ(t.get(callee, .property)) == 'Identifier'
		&& t.name(t.get(callee, .property)) in ['bind', 'apply', 'call'] {
		return z.error_at(node, e_render_tag_invalid_call_expression())
	}
	z.child(node, callee, z.with_expression(st))!
	for arg in t.list(expression, .arguments) {
		z.child(node, arg, z.with_expression(st))!
	}
}

fn (mut z Analyzer) add_snippet(node int, snippet int) {
	mut list := z.snippets_of[node] or { []int{} }
	if snippet !in list {
		list << snippet
	}
	z.snippets_of[node] = list
}

fn (z &Analyzer) is_resolved_snippet(binding int) bool {
	if binding < 0 {
		return true
	}
	b := z.s.bindings[binding]
	return b.declaration_kind == 'import' || b.kind in ['prop', 'rest_prop', 'bindable_prop']
		|| z.t.typ(b.initial) == 'SnippetBlock'
}

fn (mut z Analyzer) v_let(node int) ! {
	parent := z.path_at(-1)
	if parent < 0 || z.t.typ(parent) !in ['Component', 'RegularElement', 'SlotElement', 'SvelteElement',
		'SvelteComponent', 'SvelteSelf', 'SvelteFragment'] {
		return z.error_at(node, e_let_directive_invalid_placement())
	}
}

fn (mut z Analyzer) v_on(node int, st State) ! {
	parent := z.path_at(-1)
	pt := z.t.typ(parent)
	if z.runes && pt in ['RegularElement', 'SvelteElement'] {
		z.warn(node, w_event_directive_deprecated(z.t.name(node)))
	}
	if pt in ['SvelteElement', 'RegularElement'] && z.event_directive_node < 0 {
		z.event_directive_node = node
	}
	z.next(node, z.with_expression(st))!
}

fn (mut z Analyzer) v_attribute(node int, st State) ! {
	z.next(node, st)!
	if !z.t.attr_is_true(node) && z.t.is_event_attribute(node) {
		parent := z.path_at(-1)
		if z.t.typ(parent) in ['RegularElement', 'SvelteElement'] {
			z.uses_event_attributes = true
		}
	}
}

fn (mut z Analyzer) v_style_directive(node int, st State) ! {
	mods := z.t.strs(node, .modifiers)
	if mods.len > 1 || (mods.len > 0 && mods[0] != 'important') {
		return z.error_at(node, e_style_directive_invalid_modifier())
	}
	if !z.t.attr_is_true(node) {
		z.next(node, st)!
	}
}

fn (mut z Analyzer) v_bind(node int, st State) ! {
	t := z.t
	parent := z.path_at(-1)
	pt := t.typ(parent)
	name := t.name(node)
	if pt in ['RegularElement', 'SvelteElement', 'SvelteWindow', 'SvelteDocument', 'SvelteBody'] {
		pname := t.name(parent)
		mut prop := BindingProperty{}
		mut found := false
		for p in binding_properties {
			if p.name == name {
				prop = p
				found = true
				break
			}
		}
		if found {
			if prop.has_valid && pname !in prop.valid {
				return z.error_at(node, e_bind_invalid_target(name, prop.valid.map('`<${it}>`').join(', ')))
			}
			if prop.has_invalid && pname in prop.invalid {
				mut valid := []string{}
				for p in binding_properties {
					if (p.has_valid && pname in p.valid)
						|| (!p.has_valid && !(p.has_invalid && pname in p.invalid)) {
						valid << p.name
					}
				}
				valid.sort()
				return z.error_at(node, e_bind_invalid_name(name, 'Possible bindings for <${pname}> are ${valid.join(', ')}'))
			}
			if pname == 'input' && name != 'this' {
				mut typ := -1
				for a in t.list(parent, .attributes) {
					if t.typ(a) == 'Attribute' && t.name(a) == 'type' {
						typ = a
						break
					}
				}
				if typ >= 0 && !t.is_text_attribute(typ) {
					if name != 'value' || t.attr_is_true(typ) {
						return z.error_at(typ, e_attribute_invalid_type())
					}
				} else {
					tv := if typ >= 0 { t.text_value(typ) } else { '' }
					if name == 'checked' && (typ < 0 || tv != 'checkbox') {
						extra := if typ >= 0 && tv == 'radio' {
							' — for `<input type="radio">`, use `bind:group`'
						} else {
							''
						}
						return z.error_at(node, e_bind_invalid_target(name, '`<input type="checkbox">`' +
							extra))
					}
					if name == 'files' && (typ < 0 || tv != 'file') {
						return z.error_at(node, e_bind_invalid_target(name, '`<input type="file">`'))
					}
				}
			}
			if pname == 'select' && name != 'this' {
				for a in t.list(parent, .attributes) {
					if t.typ(a) == 'Attribute' && t.name(a) == 'multiple' && !t.is_text_attribute(a)
						&& !t.attr_is_true(a) {
						return z.error_at(a, e_attribute_invalid_multiple())
					}
				}
			}
			if name == 'offsetWidth' && is_svg(pname) {
				return z.error_at(node, e_bind_invalid_target(name, 'non-`<svg>` elements. Use `bind:clientWidth` for `<svg>` instead'))
			}
			if is_content_editable_binding(name) {
				mut ce := -1
				for a in t.list(parent, .attributes) {
					if t.typ(a) == 'Attribute' && t.name(a) == 'contenteditable' {
						ce = a
						break
					}
				}
				if ce < 0 {
					return z.error_at(node, e_attribute_contenteditable_missing())
				} else if !t.is_text_attribute(ce) && !t.attr_is_true(ce) {
					return z.error_at(ce, e_attribute_contenteditable_dynamic())
				}
			}
		} else {
			match_ := fuzzymatch(name, binding_properties.map(it.name))
			if match_ != '' {
				for p in binding_properties {
					if p.name == match_ {
						if !p.has_valid || pname in p.valid {
							return z.error_at(node, e_bind_invalid_name(name, "Did you mean '${match_}'?"))
						}
						break
					}
				}
			}
			return z.error_at(node, e_bind_invalid_name(name, ''))
		}
	}
	expr := t.get(node, .expression)
	if t.typ(expr) == 'SequenceExpression' {
		if name == 'group' {
			return z.error_at(node, e_bind_group_invalid_expression())
		}
		mut i := t.nodes[expr].start
		leading := t.nodes[expr].leading
		lc_start := if leading.len > 0 { t.comments[leading[0]].start } else { -1 }
		lc_end := if leading.len > 0 { t.comments[leading.last()].end } else { -1 }
		src := z.c.src
		for {
			i--
			if i < 0 || src[i] == `{` {
				break
			}
			if src[i] == `(` && !(lc_start > 0 && lc_end > 0 && i <= lc_end && i >= lc_start) {
				return z.error_at(node, e_bind_invalid_parens(name))
			}
		}
		exprs := t.list(expr, .expressions)
		if exprs.len != 2 {
			return z.error_at(node, e_bind_invalid_expression())
		}
		for f in exprs {
			target := if t.typ(f) == 'ArrowFunctionExpression' { t.get(f, .body) } else { f }
			z.child(node, target, z.with_expression(st))!
		}
		return
	}
	z.validate_assignment(node, expr, st)!
	left := t.object(expr)
	if left < 0 {
		return z.error_at(node, e_bind_invalid_expression())
	}
	binding := z.s.get(st.scope, t.name(left))
	if t.typ(expr) == 'Identifier' {
		if name != 'this' && (binding < 0 || (z.s.bindings[binding].kind !in ['state', 'raw_state',
			'prop', 'bindable_prop', 'each', 'store_sub'] && !z.s.bindings[binding].updated())) {
			return z.error_at(expr, e_bind_invalid_value())
		}
	}
	if name == 'group' {
		if binding < 0 {
			return z.error_at(node, Diag{
				code:    'internal'
				message: 'Cannot find declaration for bind:group'
			})
		}
		if z.s.bindings[binding].kind == 'snippet' {
			return z.error_at(node, e_bind_group_invalid_snippet_parameter())
		}
	}
	if binding >= 0 && z.s.bindings[binding].kind == 'each' && z.s.bindings[binding].inside_rest {
		bn := z.s.bindings[binding].node
		z.warn(bn, w_bind_invalid_each_rest(t.name(bn)))
	}
	z.next(node, z.with_expression(st))!
}

// ---------------------------------------------------------------------------------------------
// Elements.

fn (mut z Analyzer) v_regular_element(node int, st State) ! {
	t := z.t
	z.validate_element(node, st)!
	z.check_element(node)
	z.meta_path[node] = z.path.clone()
	z.elements << node
	name := t.name(node)
	frag := t.get(node, .fragment)
	nodes := t.list(frag, .nodes)
	if name == 'textarea' && nodes.len > 0 {
		for a in t.list(node, .attributes) {
			if t.typ(a) == 'Attribute' && t.name(a) == 'value' {
				return z.error_at(node, e_textarea_invalid_content())
			}
		}
		if nodes.len > 1 || t.typ(nodes[0]) != 'Text' {
			// The children become a `value` attribute.
			attr := z.t.new_node('Attribute', -1, -1)
			z.t.set_str(attr, .name, 'value')
			z.t.set_list(attr, .value, nodes)
			mut attrs := t.list(node, .attributes)
			attrs << attr
			z.t.set_list(node, .attributes, attrs)
			z.t.set_list(frag, .nodes, [])
		}
	}
	binding := z.s.get(st.scope, name)
	if binding >= 0 && z.s.bindings[binding].declaration_kind == 'import'
		&& z.s.bindings[binding].references.len == 0 {
		z.warn(node, w_component_name_lowercase(name))
	}
	if st.has_parent_element {
		mut past_parent := false
		mut only_warn := false
		mut ancestors := [st.parent_element]
		for i := z.path.len - 1; i >= 0; i-- {
			ancestor := z.path[i]
			at := t.typ(ancestor)
			if at in ['IfBlock', 'EachBlock', 'AwaitBlock', 'KeyBlock'] {
				only_warn = true
			}
			if !past_parent {
				if at == 'RegularElement' && t.name(ancestor) == st.parent_element {
					message := is_tag_valid_with_parent(name, st.parent_element)
					if message != '' {
						if only_warn {
							z.warn(node, w_node_invalid_placement_ssr(message))
						} else {
							return z.error_at(node, e_node_invalid_placement(message))
						}
					}
					past_parent = true
				}
			} else if at == 'RegularElement' {
				ancestors << t.name(ancestor)
				message := is_tag_valid_with_ancestor(name, ancestors)
				if message != '' {
					if only_warn {
						z.warn(node, w_node_invalid_placement_ssr(message))
					} else {
						return z.error_at(node, e_node_invalid_placement(message))
					}
				}
			} else if at in ['Component', 'SvelteComponent', 'SvelteElement', 'SvelteSelf',
				'SnippetBlock'] {
				break
			}
		}
	}
	// Strip off any namespace from the beginning of the node name.
	node_name := strip_namespaces(name)
	end := t.nodes[node].end
	if end >= 2 && z.c.src[end - 2] == `/` && !is_void(node_name) && !is_svg(node_name)
		&& !is_mathml(node_name) {
		z.warn(node, w_element_invalid_self_closing_tag(name))
	}
	mut s := z.copy_state(st)
	s.parent_element = name
	s.has_parent_element = true
	z.next(node, s)!
}

// strip_namespaces is name.replace(/[a-zA-Z-]*:/g, '').
fn strip_namespaces(name string) string {
	mut out := []u8{}
	mut i := 0
	for i < name.len {
		mut j := i
		for j < name.len && ((name[j] >= `a` && name[j] <= `z`) || (name[j] >= `A` && name[j] <= `Z`)
			|| name[j] == `-`) {
			j++
		}
		if j < name.len && name[j] == `:` {
			i = j + 1
			continue
		}
		out << name[i]
		i++
	}
	return out.bytestr()
}

fn (mut z Analyzer) v_svelte_element(node int, st State) ! {
	t := z.t
	z.validate_element(node, st)!
	z.check_element(node)
	z.meta_path[node] = z.path.clone()
	z.elements << node
	z.child(node, t.get(node, .tag), z.with_expression(st))!
	for a in t.list(node, .attributes) {
		z.child(node, a, st)!
	}
	mut s := z.copy_state(st)
	s.parent_element = ''
	s.has_parent_element = false
	z.child(node, t.get(node, .fragment), s)!
}

fn (mut z Analyzer) v_slot(node int, st State) ! {
	t := z.t
	if z.runes && !z.custom_element {
		z.warn(node, w_slot_element_deprecated())
	}
	mut name := 'default'
	for a in t.list(node, .attributes) {
		at := t.typ(a)
		if at == 'Attribute' {
			if t.name(a) == 'name' {
				if !t.is_text_attribute(a) {
					return z.error_at(a, e_slot_element_invalid_name())
				}
				name = t.text_value(a)
				if name == 'default' {
					return z.error_at(a, e_slot_element_invalid_name_default())
				}
			}
		} else if at != 'SpreadAttribute' && at != 'LetDirective' {
			return z.error_at(a, e_slot_element_invalid_attribute())
		}
	}
	z.slot_names[name] = node
	z.next(node, st)!
}

fn (mut z Analyzer) v_svelte_fragment(node int, st State) ! {
	t := z.t
	parent := z.path_at(-2)
	if t.typ(parent) != 'Component' && t.typ(parent) != 'SvelteComponent' {
		return z.error_at(node, e_svelte_fragment_invalid_placement())
	}
	for a in t.list(node, .attributes) {
		if t.typ(a) == 'Attribute' {
			if t.name(a) == 'slot' {
				z.validate_slot_attribute(a, st, false)!
			}
		} else if t.typ(a) != 'LetDirective' {
			return z.error_at(a, e_svelte_fragment_invalid_attribute())
		}
	}
	mut s := z.copy_state(st)
	s.parent_element = ''
	s.has_parent_element = false
	z.next(node, s)!
}

fn (mut z Analyzer) v_svelte_head(node int, st State) ! {
	for a in z.t.list(node, .attributes) {
		return z.error_at(a, e_svelte_head_illegal_attribute())
	}
	z.next(node, st)!
}

fn (mut z Analyzer) disallow_children(node int) ! {
	nodes := z.t.list(z.t.get(node, .fragment), .nodes)
	if nodes.len > 0 {
		return z.error_range(z.t.nodes[nodes[0]].start, z.t.nodes[nodes.last()].end,
			e_svelte_meta_invalid_content(z.t.name(node)))
	}
}

fn (mut z Analyzer) v_svelte_meta(node int, st State, tag string) ! {
	z.disallow_children(node)!
	for a in z.t.list(node, .attributes) {
		if z.t.typ(a) == 'SpreadAttribute' || (z.t.typ(a) == 'Attribute' && !z.t.is_event_attribute(a)) {
			if tag == 'svelte:body' {
				return z.error_at(a, e_svelte_body_illegal_attribute())
			}
			return z.error_at(a, e_illegal_element_attribute(tag))
		}
	}
	z.next(node, st)!
}

fn (mut z Analyzer) v_svelte_boundary(node int, st State) ! {
	t := z.t
	for a in t.list(node, .attributes) {
		if t.typ(a) != 'Attribute' || t.name(a) !in ['onerror', 'failed', 'pending'] {
			return z.error_at(a, e_svelte_boundary_invalid_attribute())
		}
		if t.attr_is_true(a) || (t.attr_is_list(a) && (t.list(a, .value).len != 1
			|| t.typ(t.list(a, .value)[0]) != 'ExpressionTag')) {
			return z.error_at(a, e_svelte_boundary_invalid_attribute_value())
		}
	}
	z.next(node, st)!
}

fn (mut z Analyzer) v_title(node int, st State) ! {
	t := z.t
	for a in t.list(node, .attributes) {
		return z.error_at(a, e_title_illegal_attribute())
	}
	for ch in t.list(t.get(node, .fragment), .nodes) {
		if t.typ(ch) != 'Text' && t.typ(ch) != 'ExpressionTag' {
			return z.error_at(ch, e_title_invalid_content())
		}
	}
	z.next(node, st)!
}

// ---------------------------------------------------------------------------------------------
// Components.

fn (mut z Analyzer) v_component(node int, st State) ! {
	z.visit_component(node, st)!
}

fn (mut z Analyzer) v_svelte_component(node int, st State) ! {
	if z.runes {
		z.warn(node, w_svelte_component_deprecated())
	}
	z.child(node, z.t.get(node, .expression), z.with_expression(st))!
	z.visit_component(node, st)!
}

fn (mut z Analyzer) v_svelte_self(node int, st State) ! {
	mut valid := false
	for p in z.path {
		if z.t.typ(p) in ['IfBlock', 'EachBlock', 'Component', 'SnippetBlock'] {
			valid = true
			break
		}
	}
	if !valid {
		return z.error_at(node, e_svelte_self_invalid_placement())
	}
	if z.runes {
		z.warn(node, w_svelte_self_deprecated('Self', 'Self.svelte'))
	}
	z.visit_component(node, st)!
}

fn (mut z Analyzer) visit_component(node int, st State) ! {
	t := z.t
	z.meta_path[node] = z.path.clone()
	z.snippets_of[node] = []
	mut resolved := true
	for a in t.list(node, .attributes) {
		at := t.typ(a)
		if at == 'SpreadAttribute' || at == 'BindDirective' {
			resolved = false
			continue
		}
		if at != 'Attribute' || !t.is_expression_attribute(a) {
			continue
		}
		expression := t.get_attribute_expression(a)
		if t.typ(expression) == 'Identifier' {
			binding := z.s.get(st.scope, t.name(expression))
			resolved = resolved && z.is_resolved_snippet(binding)
			if binding >= 0 && t.typ(z.s.bindings[binding].initial) == 'SnippetBlock' {
				z.add_snippet(node, z.s.bindings[binding].initial)
			}
		} else if t.typ(expression) != 'Literal' {
			resolved = false
		}
	}
	if resolved {
		for ch in t.list(t.get(node, .fragment), .nodes) {
			if t.typ(ch) == 'SnippetBlock' {
				z.add_snippet(node, ch)
			}
		}
	}
	z.snippet_renderers << node
	z.snippet_resolved << resolved
	for a in t.list(node, .attributes) {
		at := t.typ(a)
		if at !in ['Attribute', 'SpreadAttribute', 'LetDirective', 'OnDirective', 'BindDirective',
			'AttachTag'] {
			return z.error_at(a, e_component_invalid_directive())
		}
		if at == 'OnDirective' {
			mods := t.strs(a, .modifiers)
			if mods.len > 1 || mods.any(it != 'once') {
				return z.error_at(a, e_event_handler_invalid_component_modifier())
			}
		}
		if at == 'Attribute' {
			if z.runes {
				z.validate_attribute(a, node)!
				if t.is_expression_attribute(a) {
					z.disallow_unparenthesized_sequences(t.get_attribute_expression(a))!
				}
			}
			z.validate_attribute_name(a)
			if t.name(a) == 'slot' {
				z.validate_slot_attribute(a, st, true)!
			}
		}
		if at == 'AttachTag' {
			z.disallow_unparenthesized_sequences(t.get(a, .expression))!
		}
	}
	scopes := (z.component_scopes[node] or { map[string]int{} }).clone()
	is_slot := (t.determine_slot(node) or { '' }) != ''
	mut default_state := st
	if !is_slot {
		default_state = z.copy_state(st)
		default_state.scope = scopes['default'] or { st.scope }
	}
	for a in t.list(node, .attributes) {
		z.child(node, a, if t.typ(a) == 'LetDirective' { default_state } else { st })!
	}
	mut comments := []int{}
	mut order := ['default']
	mut groups := map[string][]int{}
	groups['default'] = []int{}
	for ch in t.list(t.get(node, .fragment), .nodes) {
		if t.typ(ch) == 'Comment' {
			comments << ch
			continue
		}
		slot_name := t.determine_slot(ch) or { 'default' }
		if slot_name !in groups {
			groups[slot_name] = []int{}
			order << slot_name
		}
		groups[slot_name] << comments
		groups[slot_name] << ch
		if slot_name != 'default' {
			comments = []
		}
	}
	z.slot_sets << map[string]bool{}
	slots := z.slot_sets.len - 1
	frag := t.get(node, .fragment)
	for slot_name in order {
		mut s := z.copy_state(st)
		s.scope = scopes[slot_name] or { st.scope }
		s.parent_element = ''
		s.has_parent_element = false
		s.component_slots = slots
		// `{ ...node.fragment, nodes }`: a copy of the fragment with this slot's nodes.
		slot_frag := z.t.new_node('Fragment', no_pos, no_pos)
		z.t.set_list(slot_frag, .nodes, groups[slot_name])
		z.t.set_flag(slot_frag, .transparent, t.flag(frag, .transparent))
		z.child(node, slot_frag, s)!
	}
}

fn (mut z Analyzer) disallow_unparenthesized_sequences(expression int) ! {
	if z.t.typ(expression) != 'SequenceExpression' {
		return
	}
	mut i := z.t.nodes[expression].start
	src := z.c.src
	for {
		i--
		if i <= 0 {
			break
		}
		if src[i] == `(` {
			break
		}
		if src[i] == `{` {
			return z.error_at(expression, e_attribute_invalid_sequence_expression())
		}
	}
}

// ---------------------------------------------------------------------------------------------
// shared/attribute.js

fn (mut z Analyzer) validate_attribute_name(attr int) {
	name := z.t.name(attr)
	if name.contains(':') && !name.starts_with('xmlns:') && !name.starts_with('xlink:')
		&& !name.starts_with('xml:') {
		z.warn(attr, w_attribute_illegal_colon())
	}
}

fn (mut z Analyzer) validate_attribute(attr int, parent int) ! {
	t := z.t
	if t.attr_is_list(attr) {
		v := t.list(attr, .value)
		if v.len == 1 && t.typ(v[0]) == 'ExpressionTag' && (t.typ(parent) in [
			'Component',
			'SvelteComponent',
			'SvelteSelf',
		] || (t.typ(parent) == 'RegularElement'
			&& t.is_custom_element_node(parent))) {
			z.warn(attr, w_attribute_quoted())
		}
	}
	if t.attr_is_true(attr) || !t.attr_is_list(attr) || t.list(attr, .value).len == 1 {
		return
	}
	v := t.list(attr, .value)
	if t.nodes[v.last()].end == t.nodes[attr].end {
		return z.error_at(attr, e_attribute_unquoted_sequence())
	}
}

fn (mut z Analyzer) validate_slot_attribute(attr int, st State, is_component bool) ! {
	t := z.t
	parent := z.path_at(-2)
	if t.typ(parent) == 'SnippetBlock' {
		if !t.is_text_attribute(attr) {
			return z.error_at(attr, e_slot_attribute_invalid())
		}
		return
	}
	mut owner := -1
	for i := z.path.len - 1; i >= 0; i-- {
		a := z.path[i]
		if owner < 0 && (t.typ(a) in ['Component', 'SvelteComponent', 'SvelteSelf', 'SvelteElement']
			|| (t.typ(a) == 'RegularElement' && t.is_custom_element_node(a))) {
			owner = a
		}
	}
	if owner >= 0 {
		if t.typ(owner) in ['Component', 'SvelteComponent', 'SvelteSelf'] {
			if owner != parent {
				if !is_component {
					return z.error_at(attr, e_slot_attribute_invalid_placement())
				}
			} else {
				if !t.is_text_attribute(attr) {
					return z.error_at(attr, e_slot_attribute_invalid())
				}
				name := t.text_value(attr)
				if name in z.slot_sets[st.component_slots] {
					return z.error_at(attr, e_slot_attribute_duplicate(name, t.name(owner)))
				}
				z.slot_sets[st.component_slots][name] = true
				if name == 'default' {
					for n in t.list(t.get(owner, .fragment), .nodes) {
						if t.typ(n) == 'Text' && is_only_whitespace(t.text(n, .data)) {
							continue
						}
						if t.typ(n) in ['RegularElement', 'SvelteFragment'] {
							mut has_slot := false
							for a in t.list(n, .attributes) {
								if t.typ(a) == 'Attribute' && t.name(a) == 'slot' {
									has_slot = true
								}
							}
							if has_slot {
								continue
							}
						}
						return z.error_at(n, e_slot_default_duplicate())
					}
				}
			}
		}
	} else if !is_component {
		return z.error_at(attr, e_slot_attribute_invalid_placement())
	}
}

// is_only_whitespace is /^[ \t\n\r\f]+$/.
fn is_only_whitespace(s string) bool {
	if s.len == 0 {
		return false
	}
	for c in s {
		if c !in [` `, `\t`, `\n`, `\r`, `\f`] {
			return false
		}
	}
	return true
}

// ---------------------------------------------------------------------------------------------
// shared/element.js

const event_modifiers = ['preventDefault', 'stopPropagation', 'stopImmediatePropagation', 'capture',
	'once', 'passive', 'nonpassive', 'self', 'trusted']

// has_illegal_attribute_character is /(^[0-9-.])|[\^$@%&#?!|()[\]{}^*+~;]/.
fn has_illegal_attribute_character(name string) bool {
	if name.len > 0 && ((name[0] >= `0` && name[0] <= `9`) || name[0] == `-` || name[0] == `.`) {
		return true
	}
	for c in name {
		if c in [`^`, `$`, `@`, `%`, `&`, `#`, `?`, `!`, `|`, `(`, `)`, `[`, `]`, `{`, `}`, `*`,
			`+`, `~`, `;`] {
			return true
		}
	}
	return false
}

fn (mut z Analyzer) validate_element(node int, st State) ! {
	t := z.t
	mut has_animate := false
	mut in_transition := -1
	mut out_transition := -1
	for a in t.list(node, .attributes) {
		at := t.typ(a)
		if at == 'Attribute' {
			is_expression := t.is_expression_attribute(a)
			name := t.name(a)
			if z.runes {
				z.validate_attribute(a, node)!
				if is_expression {
					expression := t.get_attribute_expression(a)
					if t.typ(expression) == 'SequenceExpression' {
						mut i := t.nodes[expression].start
						src := z.c.src
						for {
							i--
							if i <= 0 {
								break
							}
							if src[i] == `(` {
								break
							}
							if src[i] == `{` {
								return z.error_at(expression, e_attribute_invalid_sequence_expression())
							}
						}
					}
				}
			}
			if has_illegal_attribute_character(name) {
				return z.error_at(a, e_attribute_invalid_name(name))
			}
			if name.starts_with('on') && name.len > 2 {
				if !is_expression {
					return z.error_at(a, e_attribute_invalid_event_handler())
				}
				value := t.get_attribute_expression(a)
				if t.typ(value) == 'Identifier' && t.name(value) == name
					&& z.s.get(st.scope, t.name(value)) < 0 {
					z.warn(a, w_attribute_global_event_reference(name))
				}
			}
			if name == 'slot' {
				z.validate_slot_attribute(a, st, false)!
			}
			if name == 'is' {
				z.warn(a, w_attribute_avoid_is())
			}
			correct := match name {
				'className' { 'class' }
				'htmlFor' { 'for' }
				else { '' }
			}
			if correct != '' {
				z.warn(a, w_attribute_invalid_property_name(name, correct))
			}
			z.validate_attribute_name(a)
		} else if at == 'AnimateDirective' {
			parent := z.path_at(-2)
			if t.typ(parent) != 'EachBlock' {
				return z.error_at(a, e_animation_invalid_placement())
			} else if t.get(parent, .key) < 0 {
				return z.error_at(a, e_animation_missing_key())
			} else {
				mut count := 0
				for n in t.list(t.get(parent, .body), .nodes) {
					nt := t.typ(n)
					if nt != 'Comment' && nt != 'ConstTag'
						&& (nt != 'Text' || t.text(n, .data).trim_space() != '') {
						count++
					}
				}
				if count > 1 {
					return z.error_at(a, e_animation_invalid_placement())
				}
			}
			if has_animate {
				return z.error_at(a, e_animation_duplicate())
			}
			has_animate = true
		} else if at == 'TransitionDirective' {
			intro := t.flag(a, .intro)
			outro := t.flag(a, .outro)
			existing := if intro && in_transition >= 0 {
				in_transition
			} else if outro && out_transition >= 0 {
				out_transition
			} else {
				-1
			}
			if existing >= 0 {
				ea := if t.flag(existing, .intro) {
					if t.flag(existing, .outro) { 'transition' } else { 'in' }
				} else {
					'out'
				}
				eb := if intro {
					if outro { 'transition' } else { 'in' }
				} else {
					'out'
				}
				if ea == eb {
					return z.error_at(a, e_transition_duplicate(ea))
				}
				return z.error_at(a, e_transition_conflict(ea, eb))
			}
			if intro {
				in_transition = a
			}
			if outro {
				out_transition = a
			}
		} else if at == 'OnDirective' {
			mut has_passive := false
			mut conflicting := ''
			for m in t.strs(a, .modifiers) {
				if m !in event_modifiers {
					list := event_modifiers[..event_modifiers.len - 1].join(', ') + ' or ' +
						event_modifiers.last()
					return z.error_at(a, e_event_handler_invalid_modifier(list))
				}
				if m == 'passive' {
					has_passive = true
				} else if m == 'nonpassive' || m == 'preventDefault' {
					conflicting = m
				}
				if has_passive && conflicting != '' {
					return z.error_at(a, e_event_handler_invalid_modifier_combination('passive',
						conflicting))
				}
			}
		}
	}
}

// ---------------------------------------------------------------------------------------------
// html-tree-validation.js

fn find_disallowed(tag string) ?Disallowed {
	for d in disallowed_children {
		if d.parent == tag {
			return d
		}
	}
	return none
}

fn is_tag_valid_with_ancestor(child_tag string, ancestors []string) string {
	if child_tag.contains('-') {
		return ''
	}
	ancestor_tag := ancestors.last()
	disallowed := find_disallowed(ancestor_tag) or { return '' }
	if disallowed.has_reset_by {
		for i := ancestors.len - 2; i >= 0; i-- {
			ancestor := ancestors[i]
			if ancestor.contains('-') {
				return ''
			}
			if ancestor in disallowed.reset_by {
				return ''
			}
		}
	}
	if disallowed.has_descendant && child_tag in disallowed.descendant {
		return '`<${child_tag}>` cannot be a descendant of `<${ancestor_tag}>`'
	}
	return ''
}

fn is_tag_valid_with_parent(child_tag string, parent_tag string) string {
	if child_tag.contains('-') || parent_tag.contains('-') {
		return ''
	}
	if parent_tag == 'template' {
		return ''
	}
	child := '`<${child_tag}>`'
	parent := '`<${parent_tag}>`'
	if disallowed := find_disallowed(parent_tag) {
		if disallowed.has_direct && child_tag in disallowed.direct {
			return '${child} cannot be a direct child of ${parent}'
		}
		if disallowed.has_descendant && child_tag in disallowed.descendant {
			return '${child} cannot be a child of ${parent}'
		}
		if disallowed.has_only {
			if child_tag in disallowed.only {
				return ''
			}
			return '${child} cannot be a child of ${parent}. `<${parent_tag}>` only allows these children: ${disallowed.only.map('`<${it}>`').join(', ')}'
		}
	}
	match child_tag {
		'body', 'caption', 'col', 'colgroup', 'frameset', 'frame', 'head', 'html' {
			return '${child} cannot be a child of ${parent}'
		}
		'thead', 'tbody', 'tfoot' {
			return '${child} must be the child of a `<table>`, not a ${parent}'
		}
		'td', 'th' {
			return '${child} must be the child of a `<tr>`, not a ${parent}'
		}
		'tr' {
			return '`<tr>` must be the child of a `<thead>`, `<tbody>`, or `<tfoot>`, not a ${parent}'
		}
		else {}
	}
	return ''
}
