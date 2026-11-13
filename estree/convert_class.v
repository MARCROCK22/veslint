module estree

// Classes, their members, parameters and decorators.

fn (mut c Converter) decorator(n C.TSNode) int {
	i := c.mkn(.decorator, n)
	if e := first_named(c.kids(n)) {
		c.pnode(i, .expression, c.expr(e.n))
	}
	return i
}

fn (mut c Converter) class(s C.TSNode, declaration bool, ctx Ctx) int {
	kids := c.kids(s)
	typ := if declaration { NodeType.class_declaration } else { NodeType.class_expression }
	i := c.mk(typ, s, ctx.start_or(c.start(s)), c.end(s))
	c.pbool(i, .abstract_, has_tok(kids, 'abstract'))
	if b := field_of(kids, 'body') {
		body := c.mk(.class_body, b.n, c.start(b.n), c.end(s))
		c.plist(body, .body, c.class_members(b.n))
		c.pnode(i, .body, body)
	}
	c.pbool(i, .declare_, ctx.declare)
	c.plist(i, .decorators, fields_of(kids, 'decorator').map(c.decorator(it.n)))
	if name := field_of(kids, 'name') {
		c.pnode(i, .id, c.ident(name.n))
	} else {
		c.pnull(i, .id)
	}
	mut implements := []int{}
	mut super_class := -1
	mut super_args := -1
	for k in kids {
		if k.kind != 'class_heritage' {
			continue
		}
		for clause in c.kids(k.n) {
			match clause.kind {
				'extends_clause' {
					ck := c.kids(clause.n)
					if v := field_of(ck, 'value') {
						if super_class < 0 {
							super_class = c.expr(v.n)
							if ta := field_of(ck, 'type_arguments') {
								super_args = c.type_arguments(ta.n)
							}
						}
					}
				}
				'implements_clause' {
					for t in c.kids(clause.n) {
						if t.named {
							implements << c.heritage(t.n, .ts_class_implements)
						}
					}
				}
				else {}
			}
		}
	}
	c.plist(i, .implements_, implements)
	c.pnode(i, .super_class, super_class)
	c.popt(i, .super_type_arguments, super_args)
	if tp := field_of(kids, 'type_parameters') {
		c.pnode(i, .type_parameters, c.type_parameters(tp.n))
	}
	return i
}

// heritage converts a type of `implements` or of an interface's `extends` to a TSClassImplements
// or a TSInterfaceHeritage.
fn (mut c Converter) heritage(n C.TSNode, typ NodeType) int {
	i := c.mkn(typ, n)
	if kind_of(n) == 'generic_type' {
		kids := c.kids(n)
		c.pnode(i, .expression, c.heritage_expr(field_of(kids, 'name') or { return i }.n))
		if ta := field_of(kids, 'type_arguments') {
			c.pnode(i, .type_arguments, c.type_arguments(ta.n))
		}
		return i
	}
	c.pnode(i, .expression, c.heritage_expr(n))
	return i
}

// heritage_expr converts the name of a heritage type to an Identifier or a MemberExpression.
fn (mut c Converter) heritage_expr(n C.TSNode) int {
	match kind_of(n) {
		'nested_type_identifier', 'nested_identifier' {
			kids := c.kids(n)
			obj := field_of(kids, if kind_of(n) == 'nested_identifier' {
				'object'
			} else {
				'module'
			}) or {
				return -1
			}
			prop := field_of(kids, if kind_of(n) == 'nested_identifier' {
				'property'
			} else {
				'name'
			}) or {
				return -1
			}
			i := c.mkn(.member_expression, n)
			c.pbool(i, .computed, false)
			c.pnode(i, .object, c.heritage_expr(obj.n))
			c.pbool(i, .optional, false)
			c.pnode(i, .property, c.ident(prop.n))
			return i
		}
		'type_identifier', 'identifier' {
			return c.ident(n)
		}
		else {
			return c.expr(n)
		}
	}
}

// class_members converts the members of a class body. Decorators of methods are children of the
// body before the method; a `;` after a member without body belongs to it.
fn (mut c Converter) class_members(body C.TSNode) []int {
	kids := c.kids(body)
	mut out := []int{}
	mut decorators := []Kid{}
	mut extra := Extra{}
	mut extra_start := -1
	for k, kid in kids {
		if kid.field == 'decorator' {
			decorators << kid
			continue
		}
		if !kid.named {
			continue
		}
		// `get` or `set` on a line before the name is a field to tree-sitter, an accessor to
		// TypeScript.
		if kid.kind == 'public_field_definition' && k + 1 < kids.len && kids[k + 1].named {
			if more := c.lone_modifier_field(kid.n) {
				if more.accessor == '' || kids[k + 1].kind == 'method_definition' {
					extra = Extra{
						accessor: if more.accessor != '' { more.accessor } else { extra.accessor }
						static:   extra.static || more.static
					}
					if extra_start < 0 {
						extra_start = if decorators.len > 0 {
							c.start(decorators[0].n)
						} else {
							c.start(kid.n)
						}
					}
					continue
				}
			}
		}
		mut end := c.end(kid.n)
		if kid.kind in ['public_field_definition', 'method_signature', 'abstract_method_signature',
			'index_signature'] {
			if k + 1 < kids.len && kids[k + 1].is_tok(';') {
				end = c.end(kids[k + 1].n)
			}
		}
		mut start := if decorators.len > 0 { c.start(decorators[0].n) } else { c.start(kid.n) }
		if extra_start >= 0 {
			start = extra_start
		}
		m := c.class_member(kid, decorators, start, end, extra)
		decorators = []Kid{}
		extra = Extra{}
		extra_start = -1
		if m >= 0 {
			out << m
		}
	}
	return out
}

// Modifiers are the modifier keywords of a member or a parameter.
struct Modifiers {
mut:
	accessibility string
	static        bool
	readonly      bool
	abstract      bool
	declare       bool
	override      bool
	accessor      bool
	async         bool
	any           bool // some modifier (makes a parameter a TSParameterProperty)
}

fn (mut c Converter) modifiers(kids []Kid) Modifiers {
	mut m := Modifiers{}
	for k in kids {
		if k.field != '' {
			continue
		}
		match k.kind {
			'accessibility_modifier' {
				m.accessibility = c.text(k.n)
				m.any = true
			}
			'override_modifier' {
				m.override = true
				m.any = true
			}
			'static' {
				if !k.named {
					m.static = true
					m.any = true
				}
			}
			'readonly' {
				if !k.named {
					m.readonly = true
					m.any = true
				}
			}
			'abstract' {
				if !k.named {
					m.abstract = true
				}
			}
			'declare' {
				if !k.named {
					m.declare = true
				}
			}
			'accessor' {
				if !k.named {
					m.accessor = true
				}
			}
			'async' {
				if !k.named {
					m.async = true
				}
			}
			else {}
		}
	}
	return m
}

fn (mut c Converter) set_accessibility(i int, m Modifiers) {
	if m.accessibility != '' {
		c.pstr(i, .accessibility, m.accessibility)
	}
}

// Extra are the modifiers TypeScript reads on a line before a method, which tree-sitter takes for
// a field.
struct Extra {
	accessor string
	static   bool
}

// lone_modifier_field: the field is only `get`, `set` or `static` (maybe after `static`), which
// TypeScript reads as a modifier of the member on the next line.
fn (mut c Converter) lone_modifier_field(n C.TSNode) ?Extra {
	kids := c.kids(n)
	mut is_static := false
	mut accessor := ''
	mut seen_name := false
	for k in kids {
		if k.is_tok('static') && !seen_name {
			is_static = true
		} else if k.field == 'name' && k.kind == 'property_identifier' && c.text(k.n) in [
			'get',
			'set',
			'static',
		] {
			seen_name = true
			if c.text(k.n) == 'static' {
				if is_static {
					return none
				}
				is_static = true
			} else {
				accessor = c.text(k.n)
			}
		} else {
			return none
		}
	}
	if !seen_name {
		return none
	}
	return Extra{
		accessor: accessor
		static:   is_static
	}
}

fn (mut c Converter) class_member(kid Kid, decorators []Kid, start int, end int, extra Extra) int {
	n := kid.n
	match kid.kind {
		'public_field_definition' {
			kids := c.kids(n)
			mut m := c.modifiers(kids)
			m.static = m.static || extra.static
			typ := if m.accessor {
				if m.abstract {
					NodeType.ts_abstract_accessor_property
				} else {
					NodeType.accessor_property
				}
			} else if m.abstract {
				NodeType.ts_abstract_property_definition
			} else {
				NodeType.property_definition
			}
			own_decorators := fields_of(kids, 'decorator')
			mut s := start
			if own_decorators.len > 0 && decorators.len == 0 {
				s = c.start(own_decorators[0].n)
			}
			i := c.mk(typ, n, s, end)
			c.set_accessibility(i, m)
			name := field_of(kids, 'name') or { return i }
			c.pbool(i, .computed, name.kind == 'computed_property_name')
			c.pbool(i, .declare_, m.declare)
			mut decs := decorators.map(c.decorator(it.n))
			decs << own_decorators.map(c.decorator(it.n))
			c.plist(i, .decorators, decs)
			c.pbool(i, .definite, has_tok(kids, '!'))
			c.pnode(i, .key, c.property_key(name.n))
			c.pbool(i, .optional, has_tok(kids, '?'))
			c.pbool(i, .override, m.override)
			c.pbool(i, .readonly, m.readonly)
			c.pbool(i, .static_, m.static)
			if t := field_of(kids, 'type') {
				c.pnode(i, .type_annotation, c.type_annotation(t.n))
			}
			if m.abstract {
				c.pnull(i, .value)
			} else if v := field_of(kids, 'value') {
				// A field initializer is outside the await context.
				saved := c.await_ctx
				c.await_ctx = false
				c.pnode(i, .value, c.expr(v.n))
				c.await_ctx = saved
			} else {
				c.pnull(i, .value)
			}
			return i
		}
		'method_definition', 'method_signature', 'abstract_method_signature' {
			return c.method(n, kid.kind, decorators, start, end, false, extra)
		}
		'index_signature' {
			return c.index_signature(n, start, end)
		}
		'class_static_block' {
			i := c.mk(.static_block, n, start, end)
			saved := c.await_ctx
			c.await_ctx = true
			defer {
				c.await_ctx = saved
			}
			if b := c.field(n, 'body') {
				c.plist(i, .body, c.body(c.named(b.n).map(it.n), true))
			}
			return i
		}
		else {
			return -1
		}
	}
}

// method converts a method of a class (MethodDefinition, TSAbstractMethodDefinition) or of an
// object literal (Property).
fn (mut c Converter) method(n C.TSNode, kind string, decorators []Kid, start int, end int, in_object bool, extra Extra) int {
	kids := c.kids(n)
	mut m := c.modifiers(kids)
	m.static = m.static || extra.static
	name := field_of(kids, 'name') or { return -1 }
	body := field_of(kids, 'body')
	is_get := has_tok(kids, 'get') || extra.accessor == 'get'
	is_set := has_tok(kids, 'set') || extra.accessor == 'set'
	params := field_of(kids, 'parameters') or { return -1 }
	// A constructor: TypeScript's ConstructorDeclaration (also when static).
	name_text := c.text(name.n)
	is_ctor := !in_object && !is_get && !is_set && !has_tok(kids, '*') && ((name.kind == 'property_identifier'
		&& name_text == 'constructor')
		|| (name.kind == 'string' && name_text.len >= 2 && name_text[1..name_text.len - 1] == 'constructor'
			&& field_of(kids, 'type_parameters') == none))
	vtyp := if body == none {
		NodeType.ts_empty_body_function_expression
	} else {
		NodeType.function_expression
	}
	value := c.mk(vtyp, n, c.start(params.n), end)
	saved_await := c.await_ctx
	c.await_ctx = m.async && !is_ctor
	defer {
		c.await_ctx = saved_await
	}
	c.pbool(value, .async, if is_ctor { false } else { m.async })
	if b := body {
		c.pnode(value, .body, c.block(b.n, true))
	} else {
		c.pnull(value, .body)
	}
	c.pbool(value, .declare_, false)
	c.pbool(value, .expression, false)
	c.pbool(value, .generator, if is_ctor { false } else { has_tok(kids, '*') })
	c.pnull(value, .id)
	c.function_signature(value, kids, !in_object)
	if tp := c.t.node(value, .type_parameters) {
		c.extend(value, c.t.nodes[tp].start, c.t.nodes[tp].end)
	}
	if in_object {
		i := c.mk(.property, n, start, end)
		c.pbool(i, .computed, name.kind == 'computed_property_name')
		c.pnode(i, .key, c.property_key(name.n))
		c.pstr(i, .kind, if is_get {
			'get'
		} else if is_set {
			'set'
		} else {
			'init'
		})
		c.pbool(i, .method, !is_get && !is_set)
		c.pbool(i, .optional, has_tok(kids, '?'))
		c.pbool(i, .shorthand, false)
		c.pnode(i, .value, value)
		return i
	}
	abstract := m.abstract || kind == 'abstract_method_signature'
	typ := if abstract {
		NodeType.ts_abstract_method_definition
	} else {
		NodeType.method_definition
	}
	i := c.mk(typ, n, start, end)
	c.set_accessibility(i, m)
	if is_ctor {
		c.pbool(i, .computed, false)
		c.plist(i, .decorators, [])
		if name.kind == 'string' {
			c.pnode(i, .key, c.literal(name.n))
		} else {
			c.pnode(i, .key, c.ident_at(name.n, c.start(name.n), c.end(name.n), 'constructor'))
		}
		c.pstr(i, .kind, if m.static { 'method' } else { 'constructor' })
		c.pbool(i, .optional, false)
		c.pbool(i, .override, false)
		c.pbool(i, .static_, m.static)
		c.pnode(i, .value, value)
		return i
	}
	c.pbool(i, .computed, name.kind == 'computed_property_name')
	c.plist(i, .decorators, decorators.map(c.decorator(it.n)))
	c.pnode(i, .key, c.property_key(name.n))
	mut k := if is_get {
		'get'
	} else if is_set {
		'set'
	} else {
		'method'
	}
	if k == 'method' && !m.static && name.kind == 'string' && cook(name_text[1..name_text.len - 1],
		false, true) == 'constructor' {
		k = 'constructor'
	}
	c.pstr(i, .kind, k)
	c.pbool(i, .optional, has_tok(kids, '?'))
	c.pbool(i, .override, m.override)
	c.pbool(i, .static_, m.static)
	c.pnode(i, .value, value)
	return i
}

fn (mut c Converter) index_signature(n C.TSNode, start int, end int) int {
	kids := c.kids(n)
	m := c.modifiers(kids)
	i := c.mk(.ts_index_signature, n, start, end)
	c.set_accessibility(i, m)
	mut params := []int{}
	if name := field_of(kids, 'name') {
		id := c.ident(name.n)
		if t := field_of(kids, 'index_type') {
			colon := tok_of(kids, ':') or { Kid{} }
			ta := c.mk(.ts_type_annotation, t.n, c.start(colon.n), c.end(t.n))
			c.pnode(ta, .type_annotation, c.typ(t.n))
			c.pnode(id, .type_annotation, ta)
			c.extend(id, c.t.nodes[ta].start, c.t.nodes[ta].end)
		}
		params << id
	}
	c.plist(i, .parameters, params)
	c.pbool(i, .readonly, m.readonly)
	c.pbool(i, .static_, m.static)
	if t := field_of(kids, 'type') {
		c.pnode(i, .type_annotation, c.type_annotation(t.n))
	}
	return i
}

// params converts formal parameters; `decorators`: the decorators of each parameter are set on it
// (convertParameters), which object methods do not do.
fn (mut c Converter) params(n C.TSNode, decorators bool) []int {
	mut out := []int{}
	for k in c.kids(n) {
		if k.kind in ['required_parameter', 'optional_parameter'] {
			out << c.param(k.n, k.kind == 'optional_parameter', decorators)
		}
	}
	return out
}

fn (mut c Converter) param(p C.TSNode, optional bool, with_decorators bool) int {
	kids := c.kids(p)
	m := c.modifiers(kids)
	pat := field_of(kids, 'pattern') or { field_of(kids, 'name') or { return -1 } }
	value := field_of(kids, 'value')
	mut parameter := -1
	mut result := -1
	if pat.kind == 'rest_pattern' {
		parameter = c.mk(.rest_element, p, c.start(p), c.end(p))
		result = parameter
		if arg := first_named(c.kids(pat.n)) {
			c.pnode(parameter, .argument, c.pattern(arg.n))
		}
		c.plist(parameter, .decorators, [])
		c.pbool(parameter, .optional, false)
	} else if v := value {
		parameter = c.pattern(pat.n)
		result = c.mk(.assignment_pattern, p, c.start(pat.n), c.end(v.n))
		c.plist(result, .decorators, [])
		c.pnode(result, .left, parameter)
		c.pbool(result, .optional, false)
		c.pnode(result, .right, c.expr(v.n))
	} else {
		parameter = c.pattern(pat.n)
		result = parameter
	}
	if t := field_of(kids, 'type') {
		c.annotate(parameter, t.n)
	}
	if optional {
		if q := tok_of(kids, '?') {
			if c.end(q.n) > c.t.nodes[parameter].end {
				c.t.nodes[parameter].end = c.end(q.n)
			}
		}
		c.set_bool_prop(parameter, .optional, true)
	}
	if m.any {
		pp := c.mkn(.ts_parameter_property, p)
		c.set_accessibility(pp, m)
		c.plist(pp, .decorators, [])
		c.pbool(pp, .override, m.override)
		c.pnode(pp, .parameter, result)
		c.pbool(pp, .readonly, m.readonly)
		c.pbool(pp, .static_, m.static)
		result = pp
	}
	if with_decorators {
		decs := fields_of(kids, 'decorator')
		if decs.len > 0 {
			c.set_list_prop(result, .decorators, decs.map(c.decorator(it.n)))
		}
	}
	return result
}
