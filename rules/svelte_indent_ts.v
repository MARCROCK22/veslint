module rules

import estree
import svelte

// The TypeScript handlers of svelte/indent: indent-helpers/ts.ts of eslint-plugin-svelte 3.24.1
// (see svelte_indent.v).

// visit_ts is the handler of a TypeScript node's type (and of Decorator, AccessorProperty,
// StaticBlock, ImportAttribute).
fn (mut x SviCtx) visit_ts(i int, typ string) {
	s := x.es(i)
	match typ {
		'TSTypeAnnotation' {
			ft := x.firsts(s, 2)
			colon_or_arrow := svi_at(ft, 0) or { return }
			p := x.parent_of(sv_es_ref(i)) or { return }
			base := x.first(x.span_of(p)) or { return }
			x.set(colon_or_arrow, 1, base)
			x.set(svi_at(ft, 1), 1, base)
			if before := x.tb(colon_or_arrow) {
				if before.value == '?' {
					x.set(before, 1, base)
				}
			}
		}
		'TSAsExpression', 'TSSatisfiesExpression' {
			expression := x.fl(x.ns(i, .expression), 0) or { return }
			op := x.ta(expression.last)
			x.set(op, 1, expression.first)
			x.set(x.flf(x.ns(i, .type_annotation)), 1, expression.first)
		}
		'TSTypeReference', 'TSInstantiationExpression' {
			type_args := x.ns(i, .type_arguments)
			if type_args.start >= 0 {
				first := x.first(s) or { return }
				x.set(x.first(type_args), 1, first)
			}
		}
		'TSTypeParameterInstantiation', 'TSTypeParameterDeclaration' {
			x.element_list(x.ls(i, .params), svi_span(x.first(s)), x.last(s), 1, false)
		}
		'TSTypeAliasDeclaration' {
			type_token := x.first(s) or { return }
			id := x.first(x.ns(i, .id)) or { return }
			x.set(id, 1, type_token)
			type_params := x.ns(i, .type_parameters)
			mut eq := ?svelte.Token(none)
			if type_params.start >= 0 {
				x.set(x.first(type_params), 1, id)
				eq = x.ta(type_params)
			} else {
				eq = x.ta(x.ns(i, .id))
			}
			e := eq or { return }
			x.set(e, 1, id)
			x.set(x.ta(e), 1, id)
		}
		'TSFunctionType', 'TSConstructorType', 'TSCallSignatureDeclaration',
		'TSConstructSignatureDeclaration' {
			first := x.first(s) or { return }
			mut curr := first
			if typ in ['TSConstructorType', 'TSConstructSignatureDeclaration'] {
				curr = x.ta(curr) or { return }
				x.set(curr, 1, first)
			}
			type_params := x.ns(i, .type_parameters)
			if type_params.start >= 0 {
				curr = x.ta(type_params) or { return }
				x.set(curr, 1, first)
			}
			left_paren := curr
			params := x.ls(i, .params)
			right_paren := x.taf(svi_last_or(params, left_paren), .close_paren) or { return }
			x.element_list(params, left_paren, right_paren, 1, false)
			if typ in ['TSFunctionType', 'TSConstructorType'] {
				x.set(x.ta(right_paren), 1, left_paren)
			} else {
				return_type := x.ns(i, .return_type)
				if return_type.start >= 0 {
					annotation := x.first(return_type) or { return }
					x.sets(x.between(right_paren, annotation), 1, first)
					x.set(annotation, 1, first)
				}
			}
		}
		'TSTypeLiteral' {
			x.element_list(x.ls(i, .members), svi_span(x.first(s)), x.last(s), 1, false)
		}
		'TSPropertySignature' {
			first := x.first(s) or { return }
			key := x.ns(i, .key)
			key_tokens := x.fl(key, 0) or { return }
			mut key_last := key_tokens.last
			if x.flag(i, .computed) {
				close_bracket := x.ta(key_tokens.last) or { return }
				x.element_list([key], first, close_bracket, 1, false)
				key_last = close_bracket
			}
			annotation := x.ns(i, .type_annotation)
			if annotation.start >= 0 {
				a := x.first(annotation) or { return }
				x.sets(x.between(key_last, a), 1, first)
				x.set(a, 1, first)
			} else if x.flag(i, .optional) {
				x.set(x.last(s), 1, first)
			}
		}
		'TSIndexSignature' {
			left_bracket := x.first(s) or { return }
			parameters := x.ls(i, .parameters)
			right_bracket := x.taf(svi_last_or(parameters, left_bracket), .close_bracket) or {
				return
			}
			x.element_list(parameters, left_bracket, right_bracket, 1, false)
			annotation := x.ns(i, .type_annotation)
			if annotation.start >= 0 {
				a := x.first(annotation) or { return }
				x.sets(x.between(right_bracket, a), 1, left_bracket)
				x.set(a, 1, left_bracket)
			}
		}
		'TSArrayType' {
			first := x.first(s) or { return }
			x.sets(x.lasts(s, 2), 0, first)
		}
		'TSTupleType' {
			x.element_list(x.ls(i, .element_types), svi_span(x.first(s)), x.last(s), 1,
				false)
		}
		'TSQualifiedName' {
			object_token := x.first(s) or { return }
			dot := x.tb(x.ns(i, .right)) or { return }
			x.set(dot, 1, object_token)
			x.set(x.ta(dot), 1, object_token)
		}
		'TSIndexedAccessType' {
			object_token := x.first(s) or { return }
			index_type := x.ns(i, .index_type)
			left_bracket := x.tbf(index_type, .open_bracket) or { return }
			right_bracket := x.taf(index_type, .close_bracket)
			x.set(left_bracket, 1, object_token)
			x.element_list([index_type], left_bracket, right_bracket, 1, false)
		}
		'TSUnionType', 'TSIntersectionType' {
			first := x.first(s) or { return }
			mut types := x.ls(i, .types)
			if types.len > 0 {
				if f := x.flf(types[0]) {
					if f.start == first.start {
						types.delete(0)
					}
				}
			}
			x.element_list(types, first, none, if x.is_beginning_of_line(first) { 0 } else { 1 },
				false)
		}
		'TSMappedType' {
			x.ts_mapped_type(i)
		}
		'TSTypeParameter' {
			tokens := x.tokens(s, false, .any)
			if tokens.len == 0 {
				return
			}
			first := tokens[0]
			mut after_tokens := tokens[1..].clone()
			for key in [estree.Key.constraint, .default_] {
				child := x.ns(i, key)
				if child.start < 0 {
					continue
				}
				remove := x.tokens(child, false, .any)
				for k, token in remove {
					if k > 0 {
						at := after_tokens.map(it.start).index(token.start)
						if at >= 0 {
							after_tokens.delete(at)
						}
					}
				}
			}
			if after_tokens.len == 0 {
				return
			}
			second := after_tokens[0]
			after_tokens.delete(0)
			x.set(second, 1, first)
			if second.value == 'extends' {
				mut prev := ?svelte.Token(none)
				mut k := 0
				for k < after_tokens.len {
					token := after_tokens[k]
					if token.value == '=' {
						break
					}
					x.set(token, 1, second)
					prev = token
					k++
				}
				for k < after_tokens.len {
					x.set(after_tokens[k], 1, prev or { second })
					k++
				}
			} else {
				x.sets(after_tokens, 1, first)
			}
		}
		'TSConditionalType' {
			check_token := x.first(s) or { return }
			extends_token := x.ta(x.ns(i, .check_type)) or { return }
			x.set(extends_token, 1, check_token)
			x.set(x.first(x.ns(i, .extends_type)), 1, extends_token)
			question := x.taf(x.ns(i, .extends_type), .not_close_paren) or { return }
			consequent := x.ta(question)
			colon := x.taf(x.ns(i, .true_type), .not_close_paren) or { return }
			alternate := x.ta(colon)
			mut base_node := i
			for {
				ptype, parent := x.es_parent_type(base_node)
				if parent < 0 || ptype != 'TSConditionalType'
					|| x.nd(parent, .false_type) != base_node {
					break
				}
				base_node = parent
			}
			base := x.first(x.es(base_node)) or { return }
			x.set(question, 1, base)
			x.set(colon, 1, base)
			x.set(consequent, 1, question)
			x.set(alternate, 1, colon)
		}
		'TSInterfaceDeclaration' {
			interface_token := x.first(s) or { return }
			id := x.first(x.ns(i, .id)) or { return }
			x.set(id, 1, interface_token)
			type_params := x.ns(i, .type_parameters)
			if type_params.start >= 0 {
				x.set(x.first(type_params), 1, id)
			}
			extends := x.ls(i, .extends_)
			if extends.len > 0 {
				if extends_token := x.tb(extends[0]) {
					x.set(extends_token, 1, interface_token)
					x.element_list(extends, extends_token, none, 1, false)
				}
			}
			x.set(x.first(x.ns(i, .body)), 0, interface_token)
		}
		'TSInterfaceBody', 'TSModuleBlock' {
			x.element_list(x.ls(i, .body), svi_span(x.first(s)), x.last(s), 1, false)
		}
		'TSClassImplements', 'TSInterfaceHeritage' {
			type_args := x.ns(i, .type_arguments)
			if type_args.start >= 0 {
				first := x.first(s) or { return }
				x.set(x.first(type_args), 1, first)
			}
		}
		'TSEnumDeclaration' {
			first := x.first(s) or { return }
			id := x.fl(x.ns(i, .id), 0) or { return }
			x.sets(x.between(first, id.first), 0, first)
			x.set(id.first, 1, first)
			left_brace := x.ta(id.last) or { return }
			right_brace := x.last(s)
			x.set(left_brace, 0, first)
			// `members`: the deprecated getter, copies of body.members with stale ranges.
			mut members := []svelte.Token{}
			for m in x.ls(x.nd(i, .body), .members) {
				members << x.stale_span(m.start, m.end)
			}
			x.element_list(members, left_brace, right_brace, 1, false)
		}
		'TSEnumBody' {
			x.element_list(x.ls(i, .members), svi_span(x.first(s)), x.last(s), 1, false)
		}
		'TSModuleDeclaration' {
			first := x.first(s) or { return }
			id := x.fl(x.ns(i, .id), 0) or { return }
			x.sets(x.between(first, id.first), 0, first)
			x.set(id.first, 1, first)
			body := x.ns(i, .body)
			if body.start >= 0 {
				body_first := x.first(body)
				x.set(body_first, if svi_is(body_first, .open_brace) { 0 } else { 1 }, first)
			}
		}
		'TSMethodSignature' {
			first := x.first(s) or { return }
			key := x.ns(i, .key)
			key_tokens := x.fl(key, 0) or { return }
			mut key_last := key_tokens.last
			if x.flag(i, .computed) {
				close_bracket := x.ta(key_tokens.last) or { return }
				x.element_list([key], first, close_bracket, 1, false)
				key_last = close_bracket
			}
			left_paren := x.taf(key_last, .open_paren) or { return }
			x.sets(x.between(key_last, left_paren), 1, first)
			x.set(left_paren, 1, first)
			params := x.ls(i, .params)
			right_paren := x.taf(svi_last_or(params, left_paren), .close_paren)
			x.element_list(params, left_paren, right_paren, 1, false)
			return_type := x.ns(i, .return_type)
			if return_type.start >= 0 {
				annotation := x.first(return_type) or { return }
				x.sets(x.between(key_last, annotation), 1, first)
				x.set(annotation, 1, first)
			}
		}
		'TSEmptyBodyFunctionExpression', 'TSDeclareFunction' {
			first := x.first(s) or { return }
			mut left_paren := ?svelte.Token(none)
			mut body_base := first
			if first.typ == 'Punctuator' {
				left_paren = first
				p := x.parent_of(sv_es_ref(i)) or { return }
				body_base = x.first(x.span_of(p)) or { return }
			} else {
				id := x.ns(i, .id)
				mut next := x.ta(first)
				mut next_offset := 0
				for {
					n := next or { break }
					if sv_is_punctuator(n, '(') || n.value == '<' {
						break
					}
					if n.value == '*' || (id.start >= 0 && n.start == id.start) {
						next_offset = 1
					}
					x.set(n, next_offset, first)
					next = x.ta(n)
				}
				left_paren = next
			}
			type_params := x.ns(i, .type_parameters)
			if !svi_is(left_paren, .open_paren) && type_params.start >= 0 {
				left_paren = x.ta(type_params)
			}
			lp := left_paren or { return }
			params := x.ls(i, .params)
			right_paren := x.taf(svi_last_or(params, lp), .close_paren)
			x.set(lp, 1, body_base)
			x.element_list(params, lp, right_paren, 1, false)
		}
		'TSTypeOperator', 'TSTypeQuery', 'TSInferType', 'TSRestType' {
			first := x.first(s) or { return }
			x.set(x.ta(first), 1, first)
		}
		'TSTypePredicate' {
			first := x.first(s) or { return }
			op := x.taf(x.ns(i, .parameter_name), .not_close_paren)
			base := x.flf(first) or { return }
			x.set(op, 1, base)
			annotation := x.ns(i, .type_annotation)
			if annotation.start >= 0 {
				x.set(x.flf(annotation), 1, base)
			}
		}
		'TSAbstractMethodDefinition', 'TSAbstractPropertyDefinition', 'TSAbstractAccessorProperty',
		'ClassProperty', 'TSAbstractClassProperty', 'AccessorProperty' {
			x.property_like(i, x.ns(i, .key), x.ns(i, .value), x.flag(i, .computed))
		}
		'TSEnumMember' {
			id := x.ns(i, .id)
			// `computed`: the deprecated getter, a name in brackets.
			mut computed := false
			if b := x.tb(id) {
				computed = sv_is_punctuator(b, '[') && b.start >= s.start
			}
			x.property_like(i, id, x.ns(i, .initializer), computed)
		}
		'TSOptionalType', 'TSNonNullExpression', 'TSJSDocNonNullableType' {
			first := x.first(s) or { return }
			x.set(x.last(s), 1, first)
		}
		'TSTypeAssertion' {
			first := x.first(s) or { return }
			expression := x.flf(x.ns(i, .expression)) or { return }
			x.element_list([x.ns(i, .type_annotation)], first, x.tb(expression), 1, false)
			x.set(expression, 1, first)
		}
		'TSImportType' {
			x.ts_import_type(i)
		}
		'TSParameterProperty' {
			first := x.first(s) or { return }
			parameter := x.first(x.ns(i, .parameter)) or { return }
			x.sets(x.between(first, parameter), 1, first)
			x.set(parameter, 1, first)
		}
		'TSImportEqualsDeclaration' {
			import_token := x.first(s) or { return }
			id := x.fl(x.ns(i, .id), 0) or { return }
			x.set(id.first, 1, import_token)
			x.set(x.ta(id.last), 1, id.last)
			x.set(x.first(x.ns(i, .module_reference)), 1, id.last)
		}
		'TSExternalModuleReference' {
			require_token := x.first(s) or { return }
			left_paren := x.taf(require_token, .open_paren) or { return }
			x.set(left_paren, 1, require_token)
			x.element_list([x.ns(i, .expression)], left_paren, x.last(s), 1, false)
		}
		'TSExportAssignment' {
			export_token := x.first(s) or { return }
			expression := x.flf(x.ns(i, .expression)) or { return }
			x.set(x.tb(expression), 1, export_token)
			x.set(expression, 1, export_token)
		}
		'TSNamedTupleMember' {
			label := x.first(s) or { return }
			element := x.flf(x.ns(i, .element_type)) or { return }
			x.sets(x.between(label, element), 1, label)
			x.set(element, 1, label)
		}
		'TSNamespaceExportDeclaration' {
			first := x.first(s) or { return }
			id := x.first(x.ns(i, .id)) or { return }
			x.sets(x.between(first, id), 1, first)
			x.set(id, 1, first)
		}
		'TSTemplateLiteralType' {
			x.template_literal(i)
		}
		'TSParenthesizedType' {
			x.element_list([x.ns(i, .type_annotation)], svi_span(x.first(s)), x.last(s), 1,
				false)
		}
		'Decorator' {
			x.ts_decorator(i)
		}
		'StaticBlock' {
			first := x.first(s) or { return }
			mut next := x.ta(first)
			for {
				n := next or { break }
				if sv_is_punctuator(n, '{') {
					break
				}
				x.set(n, 0, first)
				next = x.ta(n)
			}
			x.set(next, 0, first)
			if n := next {
				x.element_list(x.ls(i, .body), n, x.last(s), 1, false)
			}
		}
		'ImportAttribute' {
			first := x.first(s) or { return }
			key := x.fl(x.ns(i, .key), 0) or { return }
			x.sets(x.between(first, key.first), 0, first)
			x.set(key.first, 0, first)
			init := x.first(x.ns(i, .value)) or { return }
			x.sets(x.between(key.last, init), 1, key.last)
			x.set(init, 1, key.last)
		}
		else {}
	}
}

// ts_mapped_type is TSMappedType's handler; its `typeParameter` (a deprecated getter, not
// traversed) is the node from the key to the constraint, with a stale range.
fn (mut x SviCtx) ts_mapped_type(i int) {
	s := x.es(i)
	left_brace := x.first(s) or { return }
	key := x.ns(i, .key)
	constraint := x.ns(i, .constraint)
	name_type := x.ns(i, .name_type)
	mut type_parameter := svi_null
	if key.start >= 0 && constraint.start >= 0 {
		end := if c := x.fl(constraint, key.end) { c.last.end } else { constraint.end }
		type_parameter = x.stale_span(key.start, end)
	}
	left_bracket := x.tb(svi_or(key, type_parameter)) or { return }
	right_bracket := x.ta(svi_or(name_type, svi_or(constraint, type_parameter))) or { return }
	x.sets(x.between(left_brace, left_bracket), 1, left_brace)
	x.set(left_bracket, 1, left_brace)
	x.element_list([key, constraint, type_parameter, name_type], left_bracket, right_bracket,
		1, false)
	if key.start >= 0 && constraint.start >= 0 {
		first := x.first(key) or { return }
		x.sets(x.between(first, constraint), 1, first)
		x.set(x.first(constraint), 1, first)
	}
	right_brace := x.last(s) or { return }
	annotation := x.ns(i, .type_annotation)
	if annotation.start >= 0 {
		a := x.first(annotation) or { return }
		x.sets(x.between(right_bracket, a), 1, left_brace)
		x.set(a, 1, left_brace)
	} else {
		x.sets(x.between(right_bracket, right_brace), 1, left_brace)
	}
	x.set(right_brace, 0, left_brace)
}

// ts_import_type is TSImportType's handler. veslint's tree has no `source` here: it is the string
// after the parenthesis (the literal of `argument`).
fn (mut x SviCtx) ts_import_type(i int) {
	s := x.es(i)
	first := x.first(s) or { return }
	left_paren := x.taf(first, .open_paren) or { return }
	x.set(left_paren, 1, first)
	mut args := []svelte.Token{}
	mut source := x.ns(i, .source)
	if source.start < 0 {
		source = x.ns(i, .argument)
	}
	if source.start < 0 {
		source = svi_span(x.ta(left_paren))
	}
	args << source
	options := x.ns(i, .options)
	if options.start >= 0 {
		args << options
	}
	right_paren := x.taf(args.last(), .close_paren)
	x.element_list(args, left_paren, right_paren, 1, false)
	qualifier := x.ns(i, .qualifier)
	if qualifier.start >= 0 {
		if dot := x.tb(qualifier) {
			x.set(dot, 1, first)
			x.set(x.ta(dot), 1, first)
		}
	}
	type_args := x.ns(i, .type_arguments)
	if type_args.start >= 0 {
		x.set(x.first(type_args), 1, first)
	}
}

// ts_decorator is Decorator's handler.
fn (mut x SviCtx) ts_decorator(i int) {
	s := x.es(i)
	ft := x.firsts(s, 2)
	at_token := svi_at(ft, 0) or { return }
	x.set(svi_at(ft, 1), 0, at_token)
	_, parent := x.es_parent_type(i)
	if parent < 0 {
		return
	}
	decorators := x.ls(parent, .decorators)
	if decorators.len == 0 {
		return
	}
	if decorators[0].start == s.start && decorators[0].end == s.end {
		parent_span := x.es(parent)
		if parent_span.start == s.start {
			x.set(x.ta(decorators.last()), 0, at_token)
		} else {
			gtype, grand := x.es_parent_type(parent)
			mut target := parent_span
			if grand >= 0 && gtype in ['ExportDefaultDeclaration', 'ExportNamedDeclaration']
				&& s.start < x.es(grand).start {
				target = x.es(grand)
			}
			start_parent := x.first(target) or { return }
			x.copy_offset(at_token.start, start_parent.start)
		}
	} else {
		x.set_base(at_token, 0, x.first(decorators[0]))
	}
}

// ts_type_parens is the `*[type=/^TS/]` listener: the parentheses around a type.
fn (mut x SviCtx) ts_type_parens(r svelte.Ref, typ string, parent_type string) {
	if typ !in svi_ts_paren_types || parent_type == 'TSParenthesizedType' {
		return
	}
	x.expression_parens(r)
}

// ts_class_extends is the `ClassDeclaration[implements], …` listener (every class: typescript-
// estree gives each one an `implements` array).
fn (mut x SviCtx) ts_class_extends(i int) {
	type_params := x.ns(i, .type_parameters)
	if type_params.start >= 0 {
		id := x.ns(i, .id)
		if base := x.first(svi_or(id, x.es(i))) {
			x.set(x.first(type_params), 1, base)
		}
	}
	super_type_args := x.ns(i, .super_type_arguments)
	super_class := x.ns(i, .super_class)
	if super_type_args.start >= 0 && super_class.start >= 0 {
		if base := x.first(super_class) {
			x.set(x.first(super_type_args), 1, base)
		}
	}
	implements := x.ls(i, .implements_)
	if implements.len > 0 {
		class_token := x.first(x.es(i)) or { return }
		implements_token := x.tb(implements[0]) or { return }
		x.set(implements_token, 1, class_token)
		x.element_list(implements, implements_token, none, 1, false)
	}
}

// stale_span is the range ESLint sees for a node that only a deprecated getter of
// typescript-estree gives (TSEnumDeclaration.members, TSMappedType.typeParameter): the getter
// converts the node again, and svelte-eslint-parser, which moves the nodes it traverses from the
// virtual code back to the file, never sees the copy. Its range stays the one it has in the
// virtual code (UTF-16), which the rule then reads as a range of the file.
fn (x &SviCtx) stale_span(start int, end int) svelte.Token {
	nowhere := svelte.Token{
		start: x.doc.src.len + 1
		end:   x.doc.src.len + 1
	}
	vs := x.doc.file_to_virtual(start)
	ve := x.doc.file_to_virtual(end - 1)
	if vs < 0 || ve < 0 || end <= start {
		return nowhere
	}
	// The last character's units.
	last_len := utf8_char_len(x.doc.src[end - 1 - svi_char_back(x.doc.src, end - 1)])
	ve_end := ve + if last_len == 4 { 2 } else { 1 }
	file_units := x.doc.utf16(x.doc.src.len)
	if vs > file_units {
		return nowhere
	}
	return svelte.Token{
		start: x.doc.byte_offset(vs)
		end:   if ve_end > file_units { x.doc.src.len } else { x.doc.byte_offset(ve_end) }
	}
}

// svi_char_back is how many bytes before `at` its character starts (`at` in a UTF-8 sequence).
fn svi_char_back(s string, at int) int {
	mut k := 0
	for at - k > 0 && s[at - k] & 0xc0 == 0x80 {
		k++
	}
	return k
}
