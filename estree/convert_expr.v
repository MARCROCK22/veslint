module estree

// Expressions and patterns.

fn (mut c Converter) expr(n C.TSNode) int {
	kind := kind_of(n)
	if c.sub_start >= 0 && c.sub_start == c.start(n) && c.sub_kind == kind {
		return c.await_applied(n, kind)
	}
	match kind {
		'parenthesized_expression' {
			inner := first_named(c.kids(n)) or { return -1 }
			return c.expr(inner.n)
		}
		'identifier', 'undefined', 'property_identifier', 'shorthand_property_identifier',
		'type_identifier', 'statement_identifier' {
			return c.ident(n)
		}
		'private_property_identifier' {
			i := c.mkn(.private_identifier, n)
			c.pstr(i, .name, identifier_name(c.text(n)[1..]))
			return i
		}
		'this' {
			return c.mkn(.this_expression, n)
		}
		'super' {
			return c.mkn(.super, n)
		}
		'number', 'string', 'true', 'false', 'null', 'regex' {
			return c.literal(n)
		}
		'template_string' {
			return c.template(n, false)
		}
		'array' {
			i := c.mkn(.array_expression, n)
			c.plist(i, .elements, c.elements(n, false))
			return i
		}
		'object' {
			return c.object(n)
		}
		'function_expression', 'generator_function' {
			kids := c.kids(n)
			i := c.mkn(.function_expression, n)
			c.pbool(i, .async, has_tok(kids, 'async'))
			saved := c.await_ctx
			c.await_ctx = has_tok(kids, 'async')
			defer {
				c.await_ctx = saved
			}
			c.pnode(i, .body, c.block(field_of(kids, 'body') or { return i }.n, true))
			c.pbool(i, .declare_, false)
			c.pbool(i, .expression, false)
			c.pbool(i, .generator, has_tok(kids, '*'))
			if name := field_of(kids, 'name') {
				c.pnode(i, .id, c.ident(name.n))
			} else {
				c.pnull(i, .id)
			}
			c.function_signature(i, kids, true)
			return i
		}
		'arrow_function' {
			kids := c.kids(n)
			i := c.mkn(.arrow_function_expression, n)
			c.pbool(i, .async, has_tok(kids, 'async'))
			saved := c.await_ctx
			c.await_ctx = has_tok(kids, 'async')
			defer {
				c.await_ctx = saved
			}
			body := field_of(kids, 'body') or { return i }
			if body.kind == 'statement_block' {
				c.pnode(i, .body, c.block(body.n, true))
			} else {
				c.pnode(i, .body, c.expr(body.n))
			}
			c.pbool(i, .expression, body.kind != 'statement_block')
			c.pbool(i, .generator, false)
			c.pnull(i, .id)
			c.function_signature(i, kids, true)
			return i
		}
		'class' {
			return c.class(n, false, Ctx{})
		}
		'member_expression', 'subscript_expression', 'non_null_expression' {
			i, _ := c.chain(n, kind, false)
			return i
		}
		'call_expression' {
			kids := c.kids(n)
			callee := field_of(kids, 'function') or { return -1 }
			args := field_of(kids, 'arguments') or { return -1 }
			if args.kind == 'template_string' {
				i := c.mkn(.tagged_template_expression, n)
				c.pnode(i, .quasi, c.template(args.n, true))
				c.pnode(i, .tag, c.expr(callee.n))
				if ta := field_of(kids, 'type_arguments') {
					c.pnode(i, .type_arguments, c.type_arguments(ta.n))
				}
				return i
			}
			if callee.kind == 'import' {
				i := c.mkn(.import_expression, n)
				list := c.named(args.n)
				if list.len > 1 {
					c.pnode(i, .options, c.expr(list[1].n))
				} else {
					c.pnull(i, .options)
				}
				if list.len > 0 {
					c.pnode(i, .source, c.expr(list[0].n))
				}
				return i
			}
			i, _ := c.chain(n, kind, false)
			return i
		}
		'new_expression' {
			kids := c.kids(n)
			i := c.mkn(.new_expression, n)
			mut args := []int{}
			if a := field_of(kids, 'arguments') {
				for k in c.named(a.n) {
					args << c.expr(k.n)
				}
			}
			c.plist(i, .arguments, args)
			c.pnode(i, .callee, c.expr(field_of(kids, 'constructor') or { return i }.n))
			if ta := field_of(kids, 'type_arguments') {
				c.pnode(i, .type_arguments, c.type_arguments(ta.n))
			}
			return i
		}
		'meta_property' {
			kids := c.kids(n)
			i := c.mkn(.meta_property, n)
			if kids.len >= 3 {
				first := kids[0]
				last := kids.last()
				c.pnode(i, .meta, c.ident_at(first.n, c.start(first.n), c.end(first.n),
					c.text(first.n)))
				c.pnode(i, .property, c.ident_at(last.n, c.start(last.n), c.end(last.n),
					c.text(last.n)))
			}
			return i
		}
		'spread_element' {
			i := c.mkn(.spread_element, n)
			if arg := first_named(c.kids(n)) {
				c.pnode(i, .argument, c.expr(arg.n))
			}
			return i
		}
		'unary_expression' {
			kids := c.kids(n)
			i := c.mkn(.unary_expression, n)
			c.pnode(i, .argument, c.expr(field_of(kids, 'argument') or { return i }.n))
			c.pstr(i, .operator, (field_of(kids, 'operator') or { return i }).kind)
			c.pbool(i, .prefix, true)
			return i
		}
		'update_expression' {
			kids := c.kids(n)
			i := c.mkn(.update_expression, n)
			arg := field_of(kids, 'argument') or { return i }
			op := field_of(kids, 'operator') or { return i }
			c.pnode(i, .argument, c.expr(arg.n))
			c.pstr(i, .operator, op.kind)
			c.pbool(i, .prefix, c.start(op.n) < c.start(arg.n))
			return i
		}
		'binary_expression' {
			kids := c.kids(n)
			op := (field_of(kids, 'operator') or { return -1 }).kind
			typ := if op in ['&&', '||', '??'] {
				NodeType.logical_expression
			} else {
				NodeType.binary_expression
			}
			i := c.mkn(typ, n)
			c.pnode(i, .left, c.expr(field_of(kids, 'left') or { return i }.n))
			c.pstr(i, .operator, op)
			c.pnode(i, .right, c.expr(field_of(kids, 'right') or { return i }.n))
			return i
		}
		'assignment_expression', 'augmented_assignment_expression' {
			kids := c.kids(n)
			i := c.mkn(.assignment_expression, n)
			c.pnode(i, .left, c.pattern(field_of(kids, 'left') or { return i }.n))
			op := if kind == 'assignment_expression' {
				'='
			} else {
				(field_of(kids, 'operator') or { return i }).kind
			}
			c.pstr(i, .operator, op)
			c.pnode(i, .right, c.expr(field_of(kids, 'right') or { return i }.n))
			return i
		}
		'ternary_expression' {
			kids := c.kids(n)
			i := c.mkn(.conditional_expression, n)
			c.pnode(i, .alternate, c.expr(field_of(kids, 'alternative') or { return i }.n))
			c.pnode(i, .consequent, c.expr(field_of(kids, 'consequence') or { return i }.n))
			c.pnode(i, .test, c.expr(field_of(kids, 'condition') or { return i }.n))
			return i
		}
		'sequence_expression' {
			i := c.mkn(.sequence_expression, n)
			mut list := []int{}
			c.sequence(n, mut list)
			c.plist(i, .expressions, list)
			return i
		}
		'await_expression' {
			kids := c.kids(n)
			if !c.await_ctx {
				if r := c.await_identifier(kids) {
					return r
				}
			}
			i := c.mkn(.await_expression, n)
			if arg := first_named(kids) {
				c.pnode(i, .argument, c.expr(arg.n))
			}
			return i
		}
		'yield_expression' {
			kids := c.kids(n)
			i := c.mkn(.yield_expression, n)
			if arg := first_named(kids) {
				c.pnode(i, .argument, c.expr(arg.n))
			} else {
				c.pnull(i, .argument)
			}
			c.pbool(i, .delegate, has_tok(kids, '*'))
			return i
		}
		'as_expression', 'satisfies_expression' {
			kids := c.kids(n)
			i := c.mkn(if kind == 'as_expression' {
				NodeType.ts_as_expression
			} else {
				NodeType.ts_satisfies_expression
			}, n)
			named := kids.filter(it.named)
			if named.len == 0 {
				return i
			}
			c.pnode(i, .expression, c.expr(named[0].n))
			if constant := tok_of(kids, 'const') {
				ref := c.mkn(.ts_type_reference, constant.n)
				c.pnode(ref, .type_name, c.ident_at(constant.n, c.start(constant.n), c.end(constant.n),
					'const'))
				c.pnode(i, .type_annotation, ref)
			} else if named.len > 1 {
				c.pnode(i, .type_annotation, c.typ(named.last().n))
			}
			return i
		}
		'type_assertion' {
			kids := c.kids(n)
			i := c.mkn(.ts_type_assertion, n)
			for k in kids {
				if k.kind == 'type_arguments' {
					tk := c.kids(k.n)
					if t := first_named(tk) {
						c.pnode(i, .type_annotation, c.typ(t.n))
					} else if constant := tok_of(tk, 'const') {
						ref := c.mkn(.ts_type_reference, constant.n)
						c.pnode(ref, .type_name, c.ident_at(constant.n, c.start(constant.n),
							c.end(constant.n), 'const'))
						c.pnode(i, .type_annotation, ref)
					}
				} else if k.named {
					c.pnode(i, .expression, c.expr(k.n))
				}
			}
			return i
		}
		'instantiation_expression' {
			kids := c.kids(n)
			i := c.mkn(.ts_instantiation_expression, n)
			for k in kids {
				if k.kind == 'type_arguments' {
					c.pnode(i, .type_arguments, c.type_arguments(k.n))
				} else if k.named {
					c.pnode(i, .expression, c.expr(k.n))
				}
			}
			return i
		}
		'internal_module' {
			return c.module_decl(n, Ctx{})
		}
		'array_pattern', 'object_pattern', 'assignment_pattern', 'rest_pattern' {
			return c.pattern(n)
		}
		'jsx_element', 'jsx_self_closing_element' {
			return c.jsx_element(n)
		}
		else {
			// Unknown kind: an empty statement keeps the tree well formed.
			return c.mkn(.empty_statement, n)
		}
	}
}

// sequence flattens nested unparenthesized sequences (TypeScript's comma operator is left
// associative; a parenthesized sequence stays one element).
fn (mut c Converter) sequence(n C.TSNode, mut out []int) {
	for k in c.kids(n) {
		if !k.named {
			continue
		}
		if k.kind == 'sequence_expression' {
			c.sequence(k.n, mut out)
		} else {
			out << c.expr(k.n)
		}
	}
}

fn is_chain_kind(kind string) bool {
	return kind in ['member_expression', 'subscript_expression', 'non_null_expression',
		'call_expression']
}

// chain converts a member access, a call or a `!`, wrapping it in a ChainExpression when it ends
// an optional chain. `continued`: the node is the object, callee or expression of another chain
// element, which wraps the chain. Returns the node and whether its chain has a `?.`.
fn (mut c Converter) chain(n C.TSNode, kind string, continued bool) (int, bool) {
	kids := c.kids(n)
	mut optional := false
	mut lhs_field := ''
	match kind {
		'member_expression', 'subscript_expression' {
			optional = kids.any(it.kind == 'optional_chain')
			lhs_field = 'object'
		}
		'call_expression' {
			optional = has_tok(kids, '?.')
			lhs_field = 'function'
		}
		else {}
	}
	lhs := if lhs_field != '' {
		field_of(kids, lhs_field) or { return -1, false }
	} else {
		first_named(kids) or { return -1, false }
	}
	mut child := -1
	mut child_optional := false
	lhs_kind := lhs.kind
	if is_chain_kind(lhs_kind) && c.is_chain_element(lhs.n, lhs_kind) {
		child, child_optional = c.chain(lhs.n, lhs_kind, true)
	} else {
		child = c.expr(lhs.n)
	}
	mut i := -1
	match kind {
		'member_expression' {
			i = c.mkn(.member_expression, n)
			c.pbool(i, .computed, false)
			c.pnode(i, .object, child)
			c.pbool(i, .optional, optional)
			c.pnode(i, .property, c.expr(field_of(kids, 'property') or { return i, false }.n))
		}
		'subscript_expression' {
			i = c.mkn(.member_expression, n)
			c.pbool(i, .computed, true)
			c.pnode(i, .object, child)
			c.pbool(i, .optional, optional)
			c.pnode(i, .property, c.expr(field_of(kids, 'index') or { return i, false }.n))
		}
		'call_expression' {
			i = c.mkn(.call_expression, n)
			mut args := []int{}
			if a := field_of(kids, 'arguments') {
				for k in c.named(a.n) {
					args << c.expr(k.n)
				}
			}
			c.plist(i, .arguments, args)
			c.pnode(i, .callee, child)
			c.pbool(i, .optional, optional)
			if ta := field_of(kids, 'type_arguments') {
				c.pnode(i, .type_arguments, c.type_arguments(ta.n))
			}
		}
		else {
			i = c.mkn(.ts_non_null_expression, n)
			c.pnode(i, .expression, child)
		}
	}
	has_optional := optional || child_optional
	if has_optional && !continued {
		chain := c.mkn(.chain_expression, n)
		c.pnode(chain, .expression, i)
		return chain, true
	}
	return i, has_optional
}

// is_chain_element: a call is one unless it is a tagged template or `import(…)`.
fn (mut c Converter) is_chain_element(n C.TSNode, kind string) bool {
	if kind != 'call_expression' {
		return true
	}
	kids := c.kids(n)
	args := field_of(kids, 'arguments') or { return false }
	callee := field_of(kids, 'function') or { return false }
	return args.kind == 'arguments' && callee.kind != 'import'
}

// elements converts the elements of an array or array pattern, with null for each hole.
fn (mut c Converter) elements(n C.TSNode, pattern bool) []int {
	mut out := []int{}
	mut seen := false // an element since the last comma
	for k in c.kids(n) {
		if k.is_tok(',') {
			if !seen {
				out << -1
			}
			seen = false
			continue
		}
		if !k.named {
			continue
		}
		out << if pattern { c.pattern(k.n) } else { c.expr(k.n) }
		seen = true
	}
	return out
}

fn (mut c Converter) object(n C.TSNode) int {
	i := c.mkn(.object_expression, n)
	mut props := []int{}
	for k in c.kids(n) {
		if !k.named {
			continue
		}
		match k.kind {
			'pair' {
				pk := c.kids(k.n)
				p := c.mkn(.property, k.n)
				key := field_of(pk, 'key') or { continue }
				c.pbool(p, .computed, key.kind == 'computed_property_name')
				c.pnode(p, .key, c.property_key(key.n))
				c.pstr(p, .kind, 'init')
				c.pbool(p, .method, false)
				c.pbool(p, .optional, false)
				c.pbool(p, .shorthand, false)
				c.pnode(p, .value, c.expr(field_of(pk, 'value') or { continue }.n))
				props << p
			}
			'shorthand_property_identifier' {
				p := c.mkn(.property, k.n)
				c.pbool(p, .computed, false)
				c.pnode(p, .key, c.ident(k.n))
				c.pstr(p, .kind, 'init')
				c.pbool(p, .method, false)
				c.pbool(p, .optional, false)
				c.pbool(p, .shorthand, true)
				c.pnode(p, .value, c.ident(k.n))
				props << p
			}
			'method_definition' {
				props << c.method(k.n, k.kind, [], c.start(k.n), c.end(k.n), true, Extra{})
			}
			else {
				props << c.expr(k.n)
			}
		}
	}
	c.plist(i, .properties, props)
	return i
}

// property_key converts the name of a property, method, enum member or import attribute.
fn (mut c Converter) property_key(n C.TSNode) int {
	match kind_of(n) {
		'computed_property_name' {
			inner := first_named(c.kids(n)) or { return -1 }
			return c.expr(inner.n)
		}
		'string', 'number' {
			return c.literal(n)
		}
		else {
			return c.expr(n)
		}
	}
}

fn (mut c Converter) literal(n C.TSNode) int {
	raw := c.text(n)
	i := c.mkn(.literal, n)
	match kind_of(n) {
		'string' {
			c.pstr(i, .raw, raw)
			c.pstr(i, .value, cook(raw[1..raw.len - 1], false, true))
		}
		'number' {
			lit := number_literal(raw)
			c.pstr(i, .raw, raw)
			if lit.is_big {
				c.pstr(i, .bigint, lit.decimal)
				c.t.nodes[i].props << Prop{
					key:  .value
					kind: .bigint
					str:  lit.decimal
				}
			} else {
				c.t.nodes[i].props << Prop{
					key:  .value
					kind: .number
					num:  lit.value
				}
			}
		}
		'true', 'false' {
			c.pstr(i, .raw, raw)
			c.pbool(i, .value, raw == 'true')
		}
		'null' {
			c.pstr(i, .raw, 'null')
			c.pnull(i, .value)
		}
		'regex' {
			kids := c.kids(n)
			pattern := if p := field_of(kids, 'pattern') { c.text(p.n) } else { '' }
			flags := if f := field_of(kids, 'flags') { c.text(f.n) } else { '' }
			c.pstr(i, .raw, raw)
			c.t.nodes[i].props << Prop{
				key:  .regex
				kind: .regex
				str:  pattern
				str2: flags
			}
			mut valid := true
			if f := c.opts.regexp_valid {
				valid = f(pattern, flags)
			}
			c.t.nodes[i].props << Prop{
				key:  .value
				kind: if valid { ValueKind.regexp } else { ValueKind.null }
			}
		}
		else {}
	}
	return i
}

// template converts a template literal; in a tagged one an invalid escape makes `cooked` null.
fn (mut c Converter) template(n C.TSNode, tagged bool) int {
	i := c.mkn(.template_literal, n)
	mut quasis := []int{}
	mut exprs := []int{}
	mut seg := c.start(n)
	for k in c.kids(n) {
		if k.kind != 'template_substitution' {
			continue
		}
		sub_start := c.start(k.n)
		quasis << c.template_element(k.n, seg, sub_start + 2, seg + 1, sub_start, false,
			tagged)
		if e := first_named(c.kids(k.n)) {
			exprs << c.expr(e.n)
		}
		seg = node_end_of(k.n) - 1
	}
	end := c.end(n)
	quasis << c.template_element(n, seg, end, seg + 1, end - 1, true, tagged)
	c.plist(i, .expressions, exprs)
	c.plist(i, .quasis, quasis)
	return i
}

fn node_end_of(n C.TSNode) int {
	return int(C.ts_node_end_byte(n))
}

fn (mut c Converter) template_element(n C.TSNode, start int, end int, raw_start int, raw_end int, tail bool, tagged bool) int {
	i := c.mk(.template_element, n, start, end)
	raw := c.slice(raw_start, raw_end)
	c.pbool(i, .tail, tail)
	null := tagged && !valid_template_escapes(raw)
	c.t.nodes[i].props << Prop{
		key:  .value
		kind: .template
		b:    null
		str:  if null { '' } else { cook(raw, true, !tagged) }
		str2: raw
	}
	return i
}

// pattern converts a binding or assignment target.
fn (mut c Converter) pattern(n C.TSNode) int {
	kind := kind_of(n)
	match kind {
		'identifier', 'undefined', 'shorthand_property_identifier_pattern' {
			return c.ident(n)
		}
		'this' {
			return c.ident_at(n, c.start(n), c.end(n), 'this')
		}
		'array_pattern' {
			i := c.mkn(.array_pattern, n)
			c.plist(i, .decorators, [])
			c.plist(i, .elements, c.elements(n, true))
			c.pbool(i, .optional, false)
			return i
		}
		'object_pattern' {
			i := c.mkn(.object_pattern, n)
			c.plist(i, .decorators, [])
			c.pbool(i, .optional, false)
			mut props := []int{}
			for k in c.kids(n) {
				if k.named {
					props << c.pattern_property(k.n, k.kind)
				}
			}
			c.plist(i, .properties, props)
			return i
		}
		'assignment_pattern' {
			kids := c.kids(n)
			i := c.mkn(.assignment_pattern, n)
			c.plist(i, .decorators, [])
			c.pnode(i, .left, c.pattern(field_of(kids, 'left') or { return i }.n))
			c.pbool(i, .optional, false)
			c.pnode(i, .right, c.expr(field_of(kids, 'right') or { return i }.n))
			return i
		}
		'rest_pattern' {
			i := c.mkn(.rest_element, n)
			if arg := first_named(c.kids(n)) {
				c.pnode(i, .argument, c.pattern(arg.n))
			}
			c.plist(i, .decorators, [])
			c.pbool(i, .optional, false)
			return i
		}
		else {
			return c.expr(n)
		}
	}
}

fn (mut c Converter) pattern_property(n C.TSNode, kind string) int {
	match kind {
		'pair_pattern' {
			kids := c.kids(n)
			p := c.mkn(.property, n)
			key := field_of(kids, 'key') or { return p }
			c.pbool(p, .computed, key.kind == 'computed_property_name')
			c.pnode(p, .key, c.property_key(key.n))
			c.pstr(p, .kind, 'init')
			c.pbool(p, .method, false)
			c.pbool(p, .optional, false)
			c.pbool(p, .shorthand, false)
			c.pnode(p, .value, c.pattern(field_of(kids, 'value') or { return p }.n))
			return p
		}
		'shorthand_property_identifier_pattern' {
			p := c.mkn(.property, n)
			c.pbool(p, .computed, false)
			c.pnode(p, .key, c.ident(n))
			c.pstr(p, .kind, 'init')
			c.pbool(p, .method, false)
			c.pbool(p, .optional, false)
			c.pbool(p, .shorthand, true)
			c.pnode(p, .value, c.ident(n))
			return p
		}
		'object_assignment_pattern' {
			kids := c.kids(n)
			left := field_of(kids, 'left') or { return -1 }
			p := c.mkn(.property, n)
			c.pbool(p, .computed, false)
			c.pnode(p, .key, c.ident(left.n))
			c.pstr(p, .kind, 'init')
			c.pbool(p, .method, false)
			c.pbool(p, .optional, false)
			c.pbool(p, .shorthand, true)
			a := c.mkn(.assignment_pattern, n)
			c.plist(a, .decorators, [])
			c.pnode(a, .left, c.ident(left.n))
			c.pbool(a, .optional, false)
			c.pnode(a, .right, c.expr(field_of(kids, 'right') or { return p }.n))
			c.pnode(p, .value, a)
			return p
		}
		else {
			return c.pattern(n)
		}
	}
}

// await_identifier: outside an await context, TypeScript reads `await` as an identifier unless an
// identifier, a keyword or a number or string literal follows it on the same line. tree-sitter
// always reads an await expression; `await (x)`, await`x` and `await [x]` are then a call, a
// tagged template and a member access of the identifier `await`.
fn (mut c Converter) await_identifier(kids []Kid) ?int {
	if kids.len < 2 || !kids[0].is_tok('await') {
		return none
	}
	arg := kids[1]
	if arg.kind == 'unary_expression' {
		// await -x: a subtraction.
		ak := c.kids(arg.n)
		op := field_of(ak, 'operator') or { return none }
		if op.kind !in ['-', '+'] {
			return none
		}
		operand := field_of(ak, 'argument') or { return none }
		i := c.mk(.binary_expression, arg.n, c.start(kids[0].n), c.end(arg.n))
		c.pnode(i, .left, c.ident_at(kids[0].n, c.start(kids[0].n), c.end(kids[0].n), 'await'))
		c.pstr(i, .operator, op.kind)
		c.pnode(i, .right, c.expr(operand.n))
		return i
	}
	mut leaf := arg.n
	for C.ts_node_child_count(leaf) > 0 {
		leaf = C.ts_node_child(leaf, 0)
	}
	head_kind := match kind_of(leaf) {
		'(' { 'parenthesized_expression' }
		'`' { 'template_string' }
		'[' { 'array' }
		else { return none }
	}
	saved_start, saved_kind, saved_await := c.sub_start, c.sub_kind, c.sub_await
	c.sub_start = c.start(leaf)
	c.sub_kind = head_kind
	c.sub_await = kids[0].n
	r := c.expr(arg.n)
	c.sub_start, c.sub_kind, c.sub_await = saved_start, saved_kind, saved_await
	// The nodes from the result down to the applied `await` start at it.
	start := c.start(kids[0].n)
	mut i := r
	for i >= 0 {
		if c.t.nodes[i].start <= start {
			break
		}
		c.t.nodes[i].start = start
		key := match c.t.nodes[i].typ {
			.chain_expression, .ts_non_null_expression { Key.expression }
			.member_expression { Key.object }
			.call_expression { Key.callee }
			.tagged_template_expression { Key.tag }
			else { break }
		}
		i = c.t.node(i, key) or { break }
	}
	return r
}

// await_applied converts the node after an `await` read as an identifier.
fn (mut c Converter) await_applied(n C.TSNode, kind string) int {
	aw := c.sub_await
	c.sub_start = -1
	start := c.start(aw)
	id := c.ident_at(aw, start, c.end(aw), 'await')
	match kind {
		'parenthesized_expression' {
			i := c.mk(.call_expression, n, start, c.end(n))
			mut args := []int{}
			if inner := first_named(c.kids(n)) {
				if inner.kind == 'sequence_expression' {
					c.sequence(inner.n, mut args)
				} else {
					args << c.expr(inner.n)
				}
			}
			c.plist(i, .arguments, args)
			c.pnode(i, .callee, id)
			c.pbool(i, .optional, false)
			return i
		}
		'template_string' {
			i := c.mk(.tagged_template_expression, n, start, c.end(n))
			c.pnode(i, .quasi, c.template(n, true))
			c.pnode(i, .tag, id)
			return i
		}
		else {
			i := c.mk(.member_expression, n, start, c.end(n))
			c.pbool(i, .computed, true)
			c.pnode(i, .object, id)
			c.pbool(i, .optional, false)
			elems := c.named(n)
			if elems.len == 1 {
				c.pnode(i, .property, c.expr(elems[0].n))
			} else if elems.len > 1 {
				seq := c.mk(.sequence_expression, n, c.start(elems[0].n), c.end(elems.last().n))
				c.plist(seq, .expressions, elems.map(c.expr(it.n)))
				c.pnode(i, .property, seq)
			}
			return i
		}
	}
}
