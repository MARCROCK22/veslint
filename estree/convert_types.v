module estree

// Types.

const keyword_types = {
	'any':       NodeType.ts_any_keyword
	'bigint':    NodeType.ts_big_int_keyword
	'boolean':   NodeType.ts_boolean_keyword
	'never':     NodeType.ts_never_keyword
	'number':    NodeType.ts_number_keyword
	'object':    NodeType.ts_object_keyword
	'string':    NodeType.ts_string_keyword
	'symbol':    NodeType.ts_symbol_keyword
	'unknown':   NodeType.ts_unknown_keyword
	'void':      NodeType.ts_void_keyword
	'undefined': NodeType.ts_undefined_keyword
}

fn (mut c Converter) typ(n C.TSNode) int {
	kind := kind_of(n)
	match kind {
		'predefined_type' {
			kids := c.kids(n)
			if kids.len == 2 {
				// unique symbol
				i := c.mkn(.ts_type_operator, n)
				c.pstr(i, .operator, 'unique')
				c.pnode(i, .type_annotation, c.mkn(.ts_symbol_keyword, kids[1].n))
				return i
			}
			t := keyword_types[c.text(n)] or { NodeType.ts_any_keyword }
			return c.mkn(t, n)
		}
		'undefined' {
			return c.mkn(.ts_undefined_keyword, n)
		}
		'type_identifier', 'identifier' {
			// tree-sitter has no `bigint` keyword type.
			if c.text(n) == 'bigint' {
				return c.mkn(.ts_big_int_keyword, n)
			}
			i := c.mkn(.ts_type_reference, n)
			c.pnode(i, .type_name, c.ident(n))
			return i
		}
		'nested_type_identifier' {
			i := c.mkn(.ts_type_reference, n)
			c.pnode(i, .type_name, c.entity_name(n))
			return i
		}
		'generic_type' {
			kids := c.kids(n)
			name := field_of(kids, 'name') or { return -1 }
			ta := field_of(kids, 'type_arguments') or { return -1 }
			if name.kind == 'import_type' {
				return c.import_type(name.n, n, ta.n)
			}
			i := c.mkn(.ts_type_reference, n)
			c.pnode(i, .type_arguments, c.type_arguments(ta.n))
			c.pnode(i, .type_name, c.entity_name(name.n))
			return i
		}
		'this_type', 'this' {
			return c.mkn(.ts_this_type, n)
		}
		'literal_type' {
			inner := first_named(c.kids(n)) or { return -1 }
			match inner.kind {
				'null' {
					return c.mkn(.ts_null_keyword, inner.n)
				}
				'undefined' {
					return c.mkn(.ts_undefined_keyword, inner.n)
				}
				else {
					i := c.mkn(.ts_literal_type, n)
					c.pnode(i, .literal, c.expr(inner.n))
					return i
				}
			}
		}
		'template_literal_type' {
			kids := c.kids(n)
			if !kids.any(it.kind == 'template_type') {
				// `x` without substitutions is a literal type.
				i := c.mkn(.ts_literal_type, n)
				c.pnode(i, .literal, c.template(n, false))
				return i
			}
			i := c.mkn(.ts_template_literal_type, n)
			mut quasis := []int{}
			mut types := []int{}
			mut seg := c.start(n)
			for k in kids {
				if k.kind != 'template_type' {
					continue
				}
				sub_start := c.start(k.n)
				quasis << c.template_element(k.n, seg, sub_start + 2, seg + 1, sub_start,
					false, false)
				if t := first_named(c.kids(k.n)) {
					types << c.typ(t.n)
				}
				seg = node_end_of(k.n) - 1
			}
			end := c.end(n)
			quasis << c.template_element(n, seg, end, seg + 1, end - 1, true, false)
			c.plist(i, .quasis, quasis)
			c.plist(i, .types, types)
			return i
		}
		'object_type' {
			return c.object_type(n)
		}
		'array_type' {
			i := c.mkn(.ts_array_type, n)
			if t := first_named(c.kids(n)) {
				c.pnode(i, .element_type, c.typ(t.n))
			}
			return i
		}
		'tuple_type' {
			i := c.mkn(.ts_tuple_type, n)
			mut elems := []int{}
			for k in c.kids(n) {
				if k.named {
					elems << c.tuple_member(k)
				}
			}
			c.plist(i, .element_types, elems)
			return i
		}
		'union_type', 'intersection_type' {
			i := c.mkn(if kind == 'union_type' {
				NodeType.ts_union_type
			} else {
				NodeType.ts_intersection_type
			}, n)
			mut types := []int{}
			c.flatten_types(n, kind, mut types)
			c.plist(i, .types, types)
			return i
		}
		'function_type', 'constructor_type' {
			kids := c.kids(n)
			if kind == 'function_type' {
				i := c.mkn(.ts_function_type, n)
				c.function_signature(i, kids, true)
				return i
			}
			i := c.mkn(.ts_constructor_type, n)
			c.pbool(i, .abstract_, has_tok(kids, 'abstract'))
			c.function_signature(i, kids, true)
			return i
		}
		'conditional_type' {
			kids := c.kids(n)
			i := c.mkn(.ts_conditional_type, n)
			c.pnode(i, .check_type, c.typ(field_of(kids, 'left') or { return i }.n))
			c.pnode(i, .extends_type, c.typ(field_of(kids, 'right') or { return i }.n))
			c.pnode(i, .false_type, c.typ(field_of(kids, 'alternative') or { return i }.n))
			c.pnode(i, .true_type, c.typ(field_of(kids, 'consequence') or { return i }.n))
			return i
		}
		'infer_type' {
			kids := c.kids(n)
			named := kids.filter(it.named)
			i := c.mkn(.ts_infer_type, n)
			if named.len == 0 {
				return i
			}
			end := if named.len > 1 { c.end(named.last().n) } else { c.end(named[0].n) }
			tp := c.mk(.ts_type_parameter, named[0].n, c.start(named[0].n), end)
			c.pbool(tp, .const_, false)
			if named.len > 1 {
				c.pnode(tp, .constraint, c.typ(named.last().n))
			}
			c.pbool(tp, .in_, false)
			c.pnode(tp, .name, c.ident(named[0].n))
			c.pbool(tp, .out_, false)
			c.pnode(i, .type_parameter, tp)
			return i
		}
		'lookup_type' {
			named := c.named(n)
			i := c.mkn(.ts_indexed_access_type, n)
			if named.len == 2 {
				c.pnode(i, .index_type, c.typ(named[1].n))
				c.pnode(i, .object_type, c.typ(named[0].n))
			}
			return i
		}
		'index_type_query', 'readonly_type' {
			i := c.mkn(.ts_type_operator, n)
			c.pstr(i, .operator, if kind == 'readonly_type' { 'readonly' } else { 'keyof' })
			if t := first_named(c.kids(n)) {
				c.pnode(i, .type_annotation, c.typ(t.n))
			}
			return i
		}
		'type_query' {
			return c.type_query(n)
		}
		'import_type' {
			return c.import_type(n, n, none)
		}
		'parenthesized_type' {
			inner := first_named(c.kids(n)) or { return -1 }
			return c.typ(inner.n)
		}
		'optional_type' {
			i := c.mkn(.ts_optional_type, n)
			if t := first_named(c.kids(n)) {
				c.pnode(i, .type_annotation, c.typ(t.n))
			}
			return i
		}
		'rest_type' {
			i := c.mkn(.ts_rest_type, n)
			if t := first_named(c.kids(n)) {
				c.pnode(i, .type_annotation, c.typ(t.n))
			}
			return i
		}
		'type_predicate', 'asserts' {
			return c.type_predicate(n)
		}
		else {
			return c.mkn(.ts_any_keyword, n)
		}
	}
}

fn (mut c Converter) flatten_types(n C.TSNode, kind string, mut out []int) {
	for k in c.kids(n) {
		if !k.named {
			continue
		}
		if k.kind == kind {
			c.flatten_types(k.n, kind, mut out)
		} else {
			out << c.typ(k.n)
		}
	}
}

// tuple_member converts an element of a tuple type; `a: T`, `a?: T` and `...a: T` are named.
fn (mut c Converter) tuple_member(k Kid) int {
	if k.kind !in ['required_parameter', 'optional_parameter'] {
		return c.typ(k.n)
	}
	kids := c.kids(k.n)
	name := field_of(kids, 'name') or { field_of(kids, 'pattern') or { return -1 } }
	t := field_of(kids, 'type') or { return -1 }
	inner := first_named(c.kids(t.n)) or { return -1 }
	if name.kind == 'rest_pattern' {
		label := first_named(c.kids(name.n)) or { return -1 }
		rest := c.mkn(.ts_rest_type, k.n)
		member := c.mk(.ts_named_tuple_member, k.n, c.start(label.n), c.end(k.n))
		c.pnode(member, .element_type, c.typ(inner.n))
		c.pnode(member, .label, c.ident(label.n))
		c.pbool(member, .optional, false)
		c.pnode(rest, .type_annotation, member)
		return rest
	}
	member := c.mkn(.ts_named_tuple_member, k.n)
	c.pnode(member, .element_type, c.typ(inner.n))
	c.pnode(member, .label, c.ident(name.n))
	c.pbool(member, .optional, k.kind == 'optional_parameter')
	return member
}

fn (mut c Converter) type_annotation(n C.TSNode) int {
	i := c.mkn(.ts_type_annotation, n)
	if t := first_named(c.kids(n)) {
		c.pnode(i, .type_annotation, c.typ(t.n))
	}
	return i
}

// return_type converts the return type of a function (`: T`, `: x is T`, `: asserts x`) or of a
// function type (after `=>`).
fn (mut c Converter) return_type(rt C.TSNode, fn_kids []Kid) int {
	match kind_of(rt) {
		'type_annotation', 'type_predicate_annotation', 'asserts_annotation' {
			i := c.mkn(.ts_type_annotation, rt)
			if t := first_named(c.kids(rt)) {
				c.pnode(i, .type_annotation, c.typ(t.n))
			}
			return i
		}
		else {
			// After `=>`: the annotation starts at the arrow.
			arrow := tok_of(fn_kids, '=>') or {
				Kid{
					n: rt
				}
			}
			i := c.mk(.ts_type_annotation, rt, c.start(arrow.n), c.end(rt))
			c.pnode(i, .type_annotation, c.typ(rt))
			return i
		}
	}
}

fn (mut c Converter) type_predicate(n C.TSNode) int {
	kids := c.kids(n)
	if kind_of(n) == 'asserts' {
		i := c.mkn(.ts_type_predicate, n)
		c.pbool(i, .asserts, true)
		inner := first_named(kids) or { return i }
		if inner.kind == 'type_predicate' {
			pk := c.kids(inner.n)
			c.pnode(i, .parameter_name, c.predicate_name(field_of(pk, 'name') or { return i }.n))
			c.pnode(i, .type_annotation, c.predicate_type(field_of(pk, 'type') or { return i }.n))
		} else {
			c.pnode(i, .parameter_name, c.predicate_name(inner.n))
			c.pnull(i, .type_annotation)
		}
		return i
	}
	i := c.mkn(.ts_type_predicate, n)
	c.pbool(i, .asserts, false)
	c.pnode(i, .parameter_name, c.predicate_name(field_of(kids, 'name') or { return i }.n))
	c.pnode(i, .type_annotation, c.predicate_type(field_of(kids, 'type') or { return i }.n))
	return i
}

fn (mut c Converter) predicate_name(n C.TSNode) int {
	if kind_of(n) == 'this' {
		return c.mkn(.ts_this_type, n)
	}
	return c.ident(n)
}

// predicate_type is the TSTypeAnnotation of a type predicate, with the range of its type.
fn (mut c Converter) predicate_type(n C.TSNode) int {
	t := c.typ(n)
	i := c.mk(.ts_type_annotation, n, c.t.nodes[t].start, c.t.nodes[t].end)
	c.pnode(i, .type_annotation, t)
	return i
}

fn (mut c Converter) type_parameters(n C.TSNode) int {
	i := c.mkn(.ts_type_parameter_declaration, n)
	mut params := []int{}
	for k in c.kids(n) {
		if k.kind != 'type_parameter' {
			continue
		}
		pk := c.kids(k.n)
		p := c.mkn(.ts_type_parameter, k.n)
		c.pbool(p, .const_, has_tok(pk, 'const'))
		if con := field_of(pk, 'constraint') {
			if t := first_named(c.kids(con.n)) {
				c.pnode(p, .constraint, c.typ(t.n))
			}
		}
		if def := field_of(pk, 'value') {
			if t := first_named(c.kids(def.n)) {
				c.pnode(p, .default_, c.typ(t.n))
			}
		}
		c.pbool(p, .in_, has_tok(pk, 'in'))
		c.pnode(p, .name, c.ident(field_of(pk, 'name') or { continue }.n))
		c.pbool(p, .out_, has_tok(pk, 'out'))
		params << p
	}
	c.plist(i, .params, params)
	return i
}

fn (mut c Converter) type_arguments(n C.TSNode) int {
	i := c.mkn(.ts_type_parameter_instantiation, n)
	mut params := []int{}
	for k in c.kids(n) {
		if k.named {
			params << c.typ(k.n)
		}
	}
	c.plist(i, .params, params)
	return i
}

// type_members converts the members of an interface body or object type; a `;` or `,` after a
// member belongs to it.
fn (mut c Converter) type_members(body C.TSNode) []int {
	kids := c.kids(body)
	mut out := []int{}
	for k, kid in kids {
		if !kid.named {
			continue
		}
		mut end := c.end(kid.n)
		if k + 1 < kids.len && (kids[k + 1].is_tok(';') || kids[k + 1].is_tok(',')) {
			end = c.end(kids[k + 1].n)
		}
		m := c.type_member(kid, c.start(kid.n), end)
		if m >= 0 {
			out << m
		}
	}
	return out
}

fn (mut c Converter) type_member(kid Kid, start int, end int) int {
	n := kid.n
	kids := c.kids(n)
	match kid.kind {
		'property_signature' {
			m := c.modifiers(kids)
			i := c.mk(.ts_property_signature, n, start, end)
			c.set_accessibility(i, m)
			name := field_of(kids, 'name') or { return i }
			c.pbool(i, .computed, name.kind == 'computed_property_name')
			c.pnode(i, .key, c.property_key(name.n))
			c.pbool(i, .optional, has_tok(kids, '?'))
			c.pbool(i, .readonly, m.readonly)
			c.pbool(i, .static_, m.static)
			if t := field_of(kids, 'type') {
				c.pnode(i, .type_annotation, c.type_annotation(t.n))
			}
			return i
		}
		'method_signature' {
			m := c.modifiers(kids)
			i := c.mk(.ts_method_signature, n, start, end)
			c.set_accessibility(i, m)
			name := field_of(kids, 'name') or { return i }
			c.pbool(i, .computed, name.kind == 'computed_property_name')
			c.pnode(i, .key, c.property_key(name.n))
			c.pstr(i, .kind, if has_tok(kids, 'get') {
				'get'
			} else if has_tok(kids, 'set') {
				'set'
			} else {
				'method'
			})
			c.pbool(i, .optional, has_tok(kids, '?'))
			c.pbool(i, .readonly, m.readonly)
			c.pbool(i, .static_, m.static)
			c.function_signature(i, kids, true)
			return i
		}
		'call_signature' {
			i := c.mk(.ts_call_signature_declaration, n, start, end)
			c.function_signature(i, kids, true)
			return i
		}
		'construct_signature' {
			i := c.mk(.ts_construct_signature_declaration, n, start, end)
			c.function_signature(i, kids, true)
			return i
		}
		'index_signature' {
			return c.index_signature(n, start, end)
		}
		else {
			return -1
		}
	}
}

// object_type converts `{ … }`: a TSTypeLiteral, or a TSMappedType for `{ [K in T]: U }`.
fn (mut c Converter) object_type(n C.TSNode) int {
	kids := c.kids(n)
	for k in kids {
		if k.kind == 'index_signature' {
			ik := c.kids(k.n)
			for clause in ik {
				if clause.kind == 'mapped_type_clause' {
					return c.mapped_type(n, ik, clause)
				}
			}
		}
	}
	i := c.mkn(.ts_type_literal, n)
	c.plist(i, .members, c.type_members(n))
	return i
}

fn (mut c Converter) mapped_type(n C.TSNode, ik []Kid, clause Kid) int {
	i := c.mkn(.ts_mapped_type, n)
	ck := c.kids(clause.n)
	c.pnode(i, .constraint, c.typ(field_of(ck, 'type') or { return i }.n))
	c.pnode(i, .key, c.ident(field_of(ck, 'name') or { return i }.n))
	if alias := field_of(ck, 'alias') {
		c.pnode(i, .name_type, c.typ(alias.n))
	} else {
		c.pnull(i, .name_type)
	}
	mut optional_set := false
	if t := field_of(ik, 'type') {
		match t.kind {
			'opting_type_annotation' {
				c.pbool(i, .optional, true)
				optional_set = true
			}
			'adding_type_annotation' {
				c.pstr(i, .optional, '+')
				optional_set = true
			}
			'omitting_type_annotation' {
				c.pstr(i, .optional, '-')
				optional_set = true
			}
			else {}
		}
		if inner := first_named(c.kids(t.n)) {
			c.pnode(i, .type_annotation, c.typ(inner.n))
		}
	}
	if !optional_set {
		// `?` without a type is an anonymous token.
		if has_tok(ik, '?') {
			c.pbool(i, .optional, true)
		} else if has_tok(ik, '+?') {
			c.pstr(i, .optional, '+')
		} else if has_tok(ik, '-?') {
			c.pstr(i, .optional, '-')
		} else {
			c.pbool(i, .optional, false)
		}
	}
	if has_tok(ik, 'readonly') {
		if sign := field_of(ik, 'sign') {
			c.pstr(i, .readonly, sign.kind)
		} else {
			c.pbool(i, .readonly, true)
		}
	}
	return i
}

fn (mut c Converter) type_query(n C.TSNode) int {
	i := c.mkn(.ts_type_query, n)
	inner := first_named(c.kids(n)) or { return i }
	match inner.kind {
		'import_type' {
			c.pnode(i, .expr_name, c.import_type(inner.n, inner.n, none))
		}
		'instantiation_expression' {
			ik := c.kids(inner.n)
			if f := field_of(ik, 'function') {
				if f.kind == 'import_type' {
					// typeof import('x').A<T>: the type arguments are the import type's.
					ta := ik.filter(it.kind == 'type_arguments')
					c.pnode(i, .expr_name, c.import_type(f.n, inner.n, if ta.len > 0 {
						?C.TSNode(ta[0].n)
					} else {
						none
					}))
					return i
				}
			}
			for k in ik {
				if k.kind == 'type_arguments' {
					c.pnode(i, .type_arguments, c.type_arguments(k.n))
				} else if k.named {
					c.pnode(i, .expr_name, c.query_name(k.n))
				}
			}
		}
		else {
			c.pnode(i, .expr_name, c.query_name(inner.n))
		}
	}
	return i
}

// query_name converts the name of a `typeof` type: `this` is a ThisExpression there.
fn (mut c Converter) query_name(n C.TSNode) int {
	return c.entity_name(n)
}

// import_type converts `import('x').A.B<T>`: `n` is the import_type node, `whole` the node with
// the type arguments `ta` (a generic_type) or `n` itself.
fn (mut c Converter) import_type(n C.TSNode, whole C.TSNode, type_args ?C.TSNode) int {
	i := c.mkn(.ts_import_type, whole)
	mut call := first_named(c.kids(n)) or { return i }
	mut qualifier := -1
	if call.kind == 'member_expression' {
		// The qualifier: the names after the call.
		mut names := []Kid{}
		mut cur := call
		for cur.kind == 'member_expression' {
			mk := c.kids(cur.n)
			names << field_of(mk, 'property') or { break }
			cur = field_of(mk, 'object') or { break }
		}
		call = cur
		for name in names.reverse() {
			id := c.ident(name.n)
			if qualifier < 0 {
				qualifier = id
			} else {
				q := c.mk(.ts_qualified_name, name.n, c.t.nodes[qualifier].start, c.t.nodes[id].end)
				c.pnode(q, .left, qualifier)
				c.pnode(q, .right, id)
				qualifier = q
			}
		}
	}
	args := c.named(field_of(c.kids(call.n), 'arguments') or { return i }.n)
	if args.len > 1 {
		c.pnode(i, .options, c.expr(args[1].n))
	} else {
		c.pnull(i, .options)
	}
	c.pnode(i, .qualifier, qualifier)
	if args.len > 0 {
		c.pnode(i, .source, c.literal(args[0].n))
	}
	if ta := type_args {
		c.pnode(i, .type_arguments, c.type_arguments(ta))
	} else {
		c.pnull(i, .type_arguments)
	}
	return i
}
