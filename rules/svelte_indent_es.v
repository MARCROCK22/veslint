module rules

import estree
import svelte

// The ESTree handlers of svelte/indent: indent-helpers/es.ts of eslint-plugin-svelte 3.24.1
// (see svelte_indent.v).

// nd is a node property of an ESTree node (-1: none or null).
fn (x &SviCtx) nd(i int, key estree.Key) int {
	return x.doc.es.node(i, key) or { -1 }
}

// ns is the span of a node property (svi_null: none).
fn (x &SviCtx) ns(i int, key estree.Key) svelte.Token {
	return x.es(x.nd(i, key))
}

// ls are the spans of a list property (holes and a missing list: svi_null / empty).
fn (x &SviCtx) ls(i int, key estree.Key) []svelte.Token {
	items := x.doc.es.list(i, key) or { return [] }
	return items.map(x.es(it))
}

fn (x &SviCtx) has(i int, key estree.Key) bool {
	return x.nd(i, key) >= 0
}

fn (x &SviCtx) flag(i int, key estree.Key) bool {
	return x.doc.es.flag(i, key) or { false }
}

// svi_last_or is `list[list.length - 1] || other`.
fn svi_last_or(list []svelte.Token, other svelte.Token) svelte.Token {
	if list.len > 0 && list.last().start >= 0 {
		return list.last()
	}
	return other
}

// svi_or is `a || b` of two spans.
fn svi_or(a svelte.Token, b svelte.Token) svelte.Token {
	return if a.start >= 0 { a } else { b }
}

// svi_span is a token as a span (svi_null: none).
fn svi_span(t ?svelte.Token) svelte.Token {
	return t or { svi_null }
}

// es_parent_of is getParent of an ESTree node: its type and node (none at the top).
fn (x &SviCtx) es_parent_type(i int) (string, int) {
	p := x.parent_of(sv_es_ref(i)) or { return '', -1 }
	if !p.es {
		return x.type_of(p), -1
	}
	return x.type_of(p), p.idx
}

// chain_head is getChainHeadNode.
fn (x &SviCtx) chain_head(node int) int {
	mut target := node
	for {
		ptype, parent := x.es_parent_type(target)
		if parent < 0 || ptype !in ['AssignmentExpression', 'AssignmentPattern', 'BinaryExpression',
			'LogicalExpression'] {
			break
		}
		prev := x.tb(x.es(target))
		next := x.ta(x.es(target))
		if svi_is(prev, .open_paren) && svi_is(next, .close_paren) {
			break
		}
		target = parent
	}
	return target
}

// visit_es is the handler of an ESTree node's type.
fn (mut x SviCtx) visit_es(i int, typ string) {
	s := x.es(i)
	match typ {
		'ArrayExpression', 'ArrayPattern' {
			first := x.first(s) or { return }
			elements := x.ls(i, .elements)
			right := x.taf(svi_last_or(elements, first), .close_bracket)
			x.element_list(elements, first, right, 1, false)
		}
		'ArrowFunctionExpression' {
			ft := x.firsts(s, 2)
			first := svi_at(ft, 0) or { return }
			second := svi_at(ft, 1)
			is_async := x.flag(i, .async)
			left := if is_async { second } else { ?svelte.Token(first) }
			arrow := x.tbf(x.ns(i, .body), .arrow)
			if is_async {
				x.set(second, 1, first)
			}
			if svi_is(left, .open_paren) {
				l := left or { return }
				params := x.ls(i, .params)
				right := x.taf(svi_last_or(params, l), .close_paren)
				x.element_list(params, l, right, 1, false)
			}
			x.set(arrow, 1, first)
			body_first := x.first(x.ns(i, .body))
			x.set(body_first, if svi_is(body_first, .open_brace) { 0 } else { 1 }, first)
		}
		'AssignmentExpression', 'AssignmentPattern', 'BinaryExpression', 'LogicalExpression' {
			base_node := x.chain_head(i)
			op := x.taf(x.ns(i, .left), .not_close_paren)
			base_type := x.doc.es_type_name(base_node)
			base := if base_type in ['AssignmentExpression', 'AssignmentPattern'] {
				x.first(x.es(base_node))
			} else {
				x.flf(x.es(base_node))
			}
			b := base or { return }
			left := x.flf(x.ns(i, .left))
			right := x.flf(x.ns(i, .right))
			if !svi_same(left, b) {
				x.set(left, 1, b)
			}
			x.set(op, 1, b)
			x.set(right, 1, b)
		}
		'AwaitExpression', 'RestElement', 'SpreadElement', 'UnaryExpression', 'UpdateExpression' {
			first := x.first(s) or { return }
			x.set(x.ta(first), 1, first)
		}
		'BlockStatement', 'ClassBody' {
			x.element_list(x.ls(i, .body), svi_span(x.first(s)), x.last(s), 1, false)
		}
		'BreakStatement', 'ContinueStatement' {
			if x.has(i, .label) {
				first := x.first(s) or { return }
				x.set(x.ta(first), 1, first)
			}
		}
		'CallExpression' {
			type_args := x.ns(i, .type_arguments)
			first := x.first(s) or { return }
			left_paren := x.taf(svi_or(type_args, x.ns(i, .callee)), .open_paren) or { return }
			right_paren := x.last(s)
			if type_args.start >= 0 {
				x.set(x.first(type_args), 1, first)
			}
			if callee_last := x.last(svi_or(type_args, x.ns(i, .callee))) {
				x.sets(x.between_f(callee_last, left_paren, .optional), 1, first)
			}
			x.set(left_paren, 1, first)
			x.element_list(x.ls(i, .arguments), left_paren, right_paren, 1, false)
		}
		'CatchClause' {
			catch_token := x.first(s) or { return }
			param := x.ns(i, .param)
			if param.start >= 0 {
				if left_paren := x.tb(param) {
					right_paren := x.ta(param)
					x.set(left_paren, 1, catch_token)
					x.element_list([param], left_paren, right_paren, 1, false)
				}
			}
			x.set(x.first(x.ns(i, .body)), 0, catch_token)
		}
		'ClassDeclaration', 'ClassExpression' {
			class_token := x.first(s) or { return }
			id := x.ns(i, .id)
			if id.start >= 0 {
				x.set(x.first(id), 1, class_token)
			}
			super_class := x.ns(i, .super_class)
			if super_class.start >= 0 {
				if extends_token := x.tb(super_class) {
					x.set(extends_token, 1, class_token)
					x.set(x.ta(extends_token), 1, extends_token)
				}
			}
			x.set(x.first(x.ns(i, .body)), 0, class_token)
		}
		'ConditionalExpression' {
			question := x.taf(x.ns(i, .test), .not_close_paren) or { return }
			consequent := x.ta(question)
			colon := x.taf(x.ns(i, .consequent), .not_close_paren) or { return }
			alternate := x.ta(colon)
			mut base_node := i
			for {
				ptype, parent := x.es_parent_type(base_node)
				if parent < 0 || ptype != 'ConditionalExpression'
					|| x.nd(parent, .alternate) != base_node {
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
		'DoWhileStatement' {
			do_token := x.first(s) or { return }
			while_token := x.taf(x.ns(i, .body), .not_close_paren) or { return }
			left_paren := x.ta(while_token)
			right_paren := x.ta(x.ns(i, .test))
			body_first := x.first(x.ns(i, .body))
			x.set(body_first, if svi_is(body_first, .open_brace) { 0 } else { 1 }, do_token)
			x.set(while_token, 0, do_token)
			if lp := left_paren {
				x.set(lp, 1, while_token)
				x.element_list([x.ns(i, .test)], lp, right_paren, 1, false)
			}
		}
		'ExportAllDeclaration' {
			export_token := x.first(s) or { return }
			source := x.ns(i, .source)
			tokens := x.between(export_token, source)
			from_index := tokens.map(it.value).index('from')
			from_token := svi_at(tokens, from_index)
			// slice(0, -1) when there is no `from`.
			mut before_tokens := []svelte.Token{}
			if from_index >= 0 {
				before_tokens = tokens[..from_index].clone()
			} else if tokens.len > 0 {
				before_tokens = tokens[..tokens.len - 1].clone()
			}
			mut after_tokens := tokens[from_index + 1..].clone()
			if f := x.first(source) {
				after_tokens << f
			}
			if !x.has(i, .exported) {
				x.sets(before_tokens, 1, export_token)
			} else {
				as_index := before_tokens.map(it.value).index('as')
				if as_index >= 1 {
					x.sets(before_tokens[..as_index], 1, export_token)
					x.sets(before_tokens[as_index..], 1, before_tokens[as_index - 1])
				}
			}
			if f := from_token {
				x.set(f, 0, export_token)
				x.sets(after_tokens, 1, f)
			}
			x.assertions(i, source, export_token)
		}
		'ExportDefaultDeclaration' {
			export_token := x.first(s) or { return }
			declaration := x.flf(x.ns(i, .declaration)) or { return }
			x.sets(x.between(export_token, declaration), 1, export_token)
			x.set(declaration, 1, export_token)
		}
		'ExportNamedDeclaration' {
			export_token := x.first(s) or { return }
			declaration := x.ns(i, .declaration)
			if declaration.start >= 0 {
				x.set(x.first(declaration), 1, export_token)
				return
			}
			specifiers := x.doc.es.list(i, .specifiers) or { []int{} }
			if specifiers.len > 0 && x.doc.es_type_name(specifiers[0]) != 'ExportSpecifier' {
				return
			}
			mut left_braces := []svelte.Token{}
			if specifiers.len > 0 {
				left_braces = x.between(export_token, x.es(specifiers[0]))
			} else if t := x.ta(export_token) {
				left_braces = [t]
			}
			source := x.ns(i, .source)
			right_brace := if source.start >= 0 {
				x.tbf(source, .close_brace)
			} else {
				x.last_f(s, .close_brace)
			}
			x.sets(left_braces, 0, export_token)
			if left_braces.len > 0 {
				x.element_list(specifiers.map(x.es(it)), left_braces.last(), right_brace, 1,
					false)
			}
			if source.start >= 0 {
				rb := right_brace or { return }
				tokens := x.between(rb, source)
				if tokens.len > 0 {
					from_token := tokens[0]
					x.set(from_token, 0, export_token)
					x.sets(tokens[1..], 1, from_token)
					x.set(x.first(source), 1, from_token)
				}
				x.assertions(i, source, export_token)
			}
		}
		'ExportSpecifier', 'ImportSpecifier' {
			mut tokens := x.tokens(s, false, .any)
			if tokens.len == 0 {
				return
			}
			mut first := tokens[0]
			tokens = tokens[1..].clone()
			if first.value == 'type' {
				type_token := first
				first = svi_at(tokens, 0) or { return }
				tokens = tokens[1..].clone()
				x.set(first, 0, type_token)
			}
			x.sets(tokens, 1, first)
		}
		'ForInStatement', 'ForOfStatement' {
			for_token := x.first(s) or { return }
			mut await_token := ?svelte.Token(none)
			if typ == 'ForOfStatement' && x.flag(i, .await_) {
				await_token = x.ta(for_token)
			}
			left_paren := x.ta(await_token or { for_token })
			left_token := x.first(x.ns(i, .left))
			in_or_of := x.taf(x.ns(i, .left), .not_close_paren)
			right_paren := x.tbf(x.ns(i, .body), .not_open_paren)
			if a := await_token {
				x.set(a, 0, for_token)
			}
			x.set(left_paren, 1, for_token)
			x.set_base(left_token, 1, left_paren)
			if io := in_or_of {
				x.set_base(io, 1, left_token)
				x.set_base(x.ta(io), 1, left_token)
			}
			x.set_base(right_paren, 0, left_paren)
			body_first := x.first(x.ns(i, .body))
			x.set(body_first, if svi_is(body_first, .open_brace) { 0 } else { 1 }, for_token)
		}
		'ForStatement' {
			for_token := x.first(s) or { return }
			left_paren := x.ta(for_token) or { return }
			right_paren := x.tbf(x.ns(i, .body), .not_open_paren)
			x.set(left_paren, 1, for_token)
			x.element_list([x.ns(i, .init), x.ns(i, .test), x.ns(i, .update)], left_paren,
				right_paren, 1, false)
			body_first := x.first(x.ns(i, .body))
			x.set(body_first, if svi_is(body_first, .open_brace) { 0 } else { 1 }, for_token)
		}
		'FunctionDeclaration', 'FunctionExpression' {
			first := x.first(s) or { return }
			params := x.ls(i, .params)
			mut anchor := svi_null
			if params.len > 0 && params[0].start >= 0 {
				anchor = params[0]
			} else if x.has(i, .return_type) {
				anchor = x.ns(i, .return_type)
			} else {
				anchor = svi_span(x.tb(x.ns(i, .body)))
			}
			left_paren := x.tbf(anchor, .open_paren) or { return }
			mut body_base := first
			if first.typ == 'Punctuator' {
				// A method: from its property's first token.
				_, parent := x.es_parent_type(i)
				if parent >= 0 {
					body_base = x.first(x.es(parent)) or { return }
				} else {
					p := x.parent_of(sv_es_ref(i)) or { return }
					body_base = x.first(x.span_of(p)) or { return }
				}
			} else {
				id := x.ns(i, .id)
				mut token_offset := 0
				for token in x.between(first, left_paren) {
					if token.value == '<' {
						break
					}
					if token.value == '*' || (id.start >= 0 && token.start == id.start) {
						token_offset = 1
					}
					x.set(token, token_offset, first)
				}
			}
			right_paren := x.taf(svi_last_or(params, left_paren), .close_paren)
			x.set(left_paren, 1, body_base)
			x.element_list(params, left_paren, right_paren, 1, false)
			x.set(x.first(x.ns(i, .body)), 0, body_base)
		}
		'IfStatement' {
			ft := x.firsts(s, 2)
			if_token := svi_at(ft, 0) or { return }
			if_left_paren := svi_at(ft, 1)
			if_right_paren := x.tbf(x.ns(i, .consequent), .close_paren)
			x.set(if_left_paren, 1, if_token)
			x.set_base(if_right_paren, 0, if_left_paren)
			consequent_first := x.first(x.ns(i, .consequent))
			x.set(consequent_first, if svi_is(consequent_first, .open_brace) { 0 } else { 1 },
				if_token)
			alternate := x.ns(i, .alternate)
			if alternate.start >= 0 {
				else_token := x.taf(x.ns(i, .consequent), .not_close_paren) or { return }
				x.set(else_token, 0, if_token)
				alternate_first := x.first(alternate)
				x.set(alternate_first, if svi_is(alternate_first, .open_brace) { 0 } else { 1 },
					else_token)
			}
		}
		'ImportDeclaration' {
			import_token := x.first(s) or { return }
			source := x.ns(i, .source)
			tokens := x.between(import_token, source)
			from_index := tokens.map(it.value).last_index('from')
			mut from_token := ?svelte.Token(none)
			mut before_tokens := []svelte.Token{}
			mut after_tokens := []svelte.Token{}
			if from_index >= 0 {
				from_token = tokens[from_index]
				before_tokens = tokens[..from_index].clone()
				after_tokens = tokens[from_index + 1..].clone()
				if f := x.first(source) {
					after_tokens << f
				}
			} else {
				before_tokens = tokens.clone()
				if f := x.first(source) {
					before_tokens << f
				}
			}
			mut named := []svelte.Token{}
			for spec in x.doc.es.list(i, .specifiers) or { []int{} } {
				if x.doc.es_type_name(spec) == 'ImportSpecifier' {
					named << x.es(spec)
				} else {
					remove := x.tokens(x.es(spec), false, .any)
					for k, token in remove {
						if k > 0 {
							before_tokens = before_tokens.filter(it.start != token.start)
						}
					}
				}
			}
			if named.len > 0 {
				left_brace := x.tb(named[0]) or { return }
				right_brace := x.taf(named.last(), .close_brace) or { return }
				x.element_list(named, left_brace, right_brace, 1, false)
				mut drop := x.between(left_brace, right_brace)
				drop << right_brace
				for token in drop {
					before_tokens = before_tokens.filter(it.start != token.start)
				}
			}
			if before_tokens.all(sv_is_punctuator(it, '{') || sv_is_punctuator(it, '}')) {
				x.sets(before_tokens, 0, import_token)
			} else {
				x.sets(before_tokens, 1, import_token)
			}
			if f := from_token {
				x.set(f, 0, import_token)
				x.sets(after_tokens, 1, f)
			}
			x.assertions(i, source, import_token)
		}
		'ImportExpression' {
			first := x.first(s) or { return }
			right := x.last(s)
			left := x.after(first.end, false, .open_paren) or { return }
			x.set(left, 1, first)
			x.element_list([x.ns(i, .source)], left, right, 1, false)
		}
		'ImportNamespaceSpecifier' {
			tokens := x.tokens(s, false, .any)
			if tokens.len > 0 {
				x.sets(tokens[1..], 1, tokens[0])
			}
		}
		'LabeledStatement', 'SvelteReactiveStatement' {
			label := x.first(s) or { return }
			colon := x.ta(label) or { return }
			x.set(colon, 1, label)
			x.set(x.ta(colon), 1, label)
		}
		'MemberExpression', 'MetaProperty' {
			object_token := x.first(s) or { return }
			property := x.ns(i, .property)
			if typ == 'MemberExpression' && x.flag(i, .computed) {
				left_bracket := x.tbf(property, .open_bracket) or { return }
				right_bracket := x.taf(property, .close_bracket)
				if object_last := x.last(x.ns(i, .object)) {
					x.sets(x.between_f(object_last, left_bracket, .optional), 1, object_token)
				}
				x.set(left_bracket, 1, object_token)
				x.element_list([property], left_bracket, right_bracket, 1, false)
			} else {
				dot := x.tb(property) or { return }
				x.set(dot, 1, object_token)
				x.set(x.ta(dot), 1, object_token)
			}
		}
		'MethodDefinition', 'Property', 'PropertyDefinition' {
			x.property_like(i, x.ns(i, .key), x.ns(i, .value), x.flag(i, .computed))
		}
		'NewExpression' {
			type_args := x.ns(i, .type_arguments)
			new_token := x.first(s) or { return }
			callee := x.fl(x.ns(i, .callee), 0) or { return }
			x.set(callee.first, 1, new_token)
			if type_args.start >= 0 {
				x.set(x.first(type_args), 1, callee.first)
			}
			left_paren_before := if type_args.start >= 0 { type_args } else { callee.last }
			arguments := x.ls(i, .arguments)
			if arguments.len > 0 || left_paren_before.end < s.end {
				right_paren := x.last(s)
				left_paren := x.ta(left_paren_before) or { return }
				x.set(left_paren, 1, callee.first)
				x.element_list(arguments, left_paren, right_paren, 1, false)
			}
		}
		'ObjectExpression', 'ObjectPattern' {
			first := x.first(s) or { return }
			properties := x.ls(i, .properties)
			right := x.taf(svi_last_or(properties, first), .close_brace)
			x.element_list(properties, first, right, 1, false)
		}
		'ReturnStatement', 'ThrowStatement' {
			if x.has(i, .argument) {
				first := x.first(s) or { return }
				x.set(x.ta(first), 1, first)
			}
		}
		'SequenceExpression' {
			first := x.first(s) or { return }
			x.element_list(x.ls(i, .expressions), first, none, 0, false)
		}
		'SwitchCase' {
			case_token := x.first(s) or { return }
			test := x.ns(i, .test)
			if test.start >= 0 {
				t := x.fl(test, 0) or { return }
				x.set(t.first, 1, case_token)
				x.set(x.ta(t.last), 1, case_token)
			} else {
				x.set(x.ta(case_token), 1, case_token)
			}
			consequent := x.doc.es.list(i, .consequent) or { []int{} }
			if consequent.len == 1 && x.doc.es_type_name(consequent[0]) == 'BlockStatement' {
				x.set(x.first(x.es(consequent[0])), 0, case_token)
			} else {
				for st in consequent {
					x.set(x.flf(x.es(st)), 1, case_token)
				}
			}
		}
		'SwitchStatement' {
			switch_token := x.first(s) or { return }
			d := x.fl(x.ns(i, .discriminant), 0) or { return }
			left_brace := x.ta(d.last)
			right_brace := x.last(s)
			x.set(d.first, 1, switch_token)
			x.element_list([x.ns(i, .discriminant)], d.first, d.last, 1, false)
			x.set(left_brace, 0, switch_token)
			if lb := left_brace {
				x.element_list(x.ls(i, .cases), lb, right_brace, x.opts.switch_case, false)
			}
		}
		'TaggedTemplateExpression' {
			tag := x.flf(x.ns(i, .tag)) or { return }
			x.set(x.first(x.ns(i, .quasi)), 1, tag)
		}
		'TemplateLiteral', 'TSTemplateLiteralType' {
			x.template_literal(i)
		}
		'TryStatement' {
			try_token := x.first(s) or { return }
			x.set(x.first(x.ns(i, .block)), 0, try_token)
			handler := x.ns(i, .handler)
			if handler.start >= 0 {
				x.set(x.first(handler), 0, try_token)
			}
			finalizer := x.ns(i, .finalizer)
			if finalizer.start >= 0 {
				x.set(x.tb(finalizer), 0, try_token)
				x.set(x.first(finalizer), 0, try_token)
			}
		}
		'VariableDeclaration' {
			first := x.first(s) or { return }
			x.element_list(x.ls(i, .declarations), first, none, 1, false)
		}
		'VariableDeclarator' {
			if x.has(i, .init) {
				id_token := x.first(s) or { return }
				eq := x.ta(x.ns(i, .id)) or { return }
				x.set(eq, 1, id_token)
				x.set(x.ta(eq), 1, id_token)
			}
		}
		'WhileStatement', 'WithStatement' {
			first := x.first(s) or { return }
			left_paren := x.ta(first) or { return }
			right_paren := x.tbf(x.ns(i, .body), .close_paren)
			x.set(left_paren, 1, first)
			x.set(right_paren, 0, left_paren)
			body_first := x.first(x.ns(i, .body))
			x.set(body_first, if svi_is(body_first, .open_brace) { 0 } else { 1 }, first)
		}
		'YieldExpression' {
			if x.has(i, .argument) {
				ft := x.firsts(s, 2)
				yield_token := svi_at(ft, 0) or { return }
				second := svi_at(ft, 1) or { return }
				x.set(second, 1, yield_token)
				if x.flag(i, .delegate) {
					x.set(x.ta(second), 1, yield_token)
				}
			}
		}
		else {}
	}
}

// template_literal is the TemplateLiteral handler (and TSTemplateLiteralType's).
fn (mut x SviCtx) template_literal(i int) {
	first := x.first(x.es(i)) or { return }
	quasis := x.ls(i, .quasis)
	for k, q in quasis {
		if k > 0 {
			x.set(x.first(q), 0, first)
		}
	}
	for k, q in quasis {
		if k < quasis.len - 1 {
			x.set(x.ta(q), 1, first)
		}
	}
}

// assertions are the import attributes of an import or export declaration.
fn (mut x SviCtx) assertions(i int, source svelte.Token, base svelte.Token) {
	last_token := x.last_f(x.es(i), .not_semicolon) or { return }
	mut tokens := x.between(source, last_token)
	if tokens.len == 0 {
		return
	}
	assert_token := tokens[0]
	x.set(assert_token, 0, base)
	if tokens.len < 2 {
		return
	}
	open := tokens[1]
	x.set(open, 1, assert_token)
	tokens = tokens[2..].clone()
	x.element_list(tokens, open, last_token, 1, false)
}

// property_like is MethodDefinition's handler (Property, PropertyDefinition, and the TS
// variants of ts.ts that do the same: the value is from the key's last token).
fn (mut x SviCtx) property_like(i int, key svelte.Token, value svelte.Token, computed bool) {
	first := x.first(x.es(i)) or { return }
	key_tokens := x.fl(key, 0) or { return }
	mut prefix := x.between(first, key_tokens.first)
	if computed && prefix.len > 0 {
		prefix.delete_last()
	}
	x.sets(prefix, 0, first)
	mut last_key := key_tokens.last
	if computed {
		left_bracket := x.tb(key_tokens.first) or { return }
		right_bracket := x.ta(key_tokens.last) or { return }
		last_key = right_bracket
		x.set(left_bracket, 0, first)
		x.element_list([key], left_bracket, right_bracket, 1, false)
	} else {
		x.set(key_tokens.first, 0, first)
	}
	if value.start >= 0 {
		init := x.first(value) or { return }
		x.sets(x.between(last_key, init), 1, last_key)
		x.set(init, 1, last_key)
	}
}
