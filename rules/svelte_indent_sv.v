module rules

import svelte

// The Svelte handlers of svelte/indent: indent-helpers/svelte.ts of eslint-plugin-svelte 3.24.1
// (see svelte_indent.v).

const svi_preformatted = ['pre', 'textarea', 'template']

// refs are the spans of Svelte nodes.
fn (x &SviCtx) sns(list []int) []svelte.Token {
	return list.map(x.sn(it))
}

// children_first sets the first token (not white space) of each child `1` from `base`.
fn (mut x SviCtx) children_first(children []int, base svelte.Token) {
	for ch in children {
		x.set(x.first_f(x.sn(ch), .not_ws), 1, base)
	}
}

// close_tag sets the tokens of a block's closing tag (`{/if}`): `{` at its opening's
// indentation, the keyword 1, `}` 0.
fn (mut x SviCtx) close_tag(s svelte.Token, open svelte.Token) {
	l := x.lasts(s, 3)
	if l.len == 0 {
		return
	}
	open_close := l[0]
	x.set(open_close, 0, open)
	x.set(svi_at(l, 1), 1, open_close)
	x.set(svi_at(l, 2), 0, open_close)
}

// is_beginning_of_element is isBeginningOfElement of a SvelteText.
fn (x &SviCtx) is_beginning_of_element(i int) bool {
	p := x.doc.nodes[i].parent
	if p < 0 {
		return false
	}
	pn := x.doc.nodes[p]
	return match pn.typ {
		.element, .await_catch_block, .await_pending_block, .await_then_block, .each_block,
		.else_block, .if_block, .key_block, .snippet_block, .style_element, .program {
			pn.children.len > 0 && pn.children[0] == i
		}
		else {
			false
		}
	}
}

// attribute is the handler of SvelteAttribute and the directives.
fn (mut x SviCtx) attribute(i int) {
	n := x.doc.nodes[i]
	s := x.sn(i)
	key_token := x.first(s) or { return }
	eq := x.ta(x.span_of(n.key)) or { return }
	if eq.end > s.end {
		return
	}
	x.set(eq, 1, key_token)
	value_start := x.ta(eq) or { return }
	if value_start.end > s.end {
		return
	}
	x.set(value_start, 1, key_token)
	values := if n.typ in [.attribute, .style_directive] { n.values } else { []int{} }
	mut processed := false
	if value_start.typ == 'Punctuator' {
		quoted := value_start.value in ['"', "'"]
		mustache := !quoted && value_start.value == '{'
		if quoted || mustache {
			if last := x.last(s) {
				if last.typ == 'Punctuator' && ((quoted && last.value == value_start.value)
					|| (mustache && last.value == '}')) {
					x.set(last, 0, value_start)
					x.element_list(x.sns(values), value_start, last, 1, false)
					processed = true
				}
			}
		}
	}
	if !processed {
		for v in values {
			x.set(x.first(x.sn(v)), 0, value_start)
		}
	}
}

// visit_sv is the handler of a Svelte node's type.
fn (mut x SviCtx) visit_sv(i int) {
	n := x.doc.nodes[i]
	s := x.sn(i)
	match n.typ {
		.script_element {
			x.element_list(n.body.map(x.es(it)), x.sn(n.start_tag), x.sn(n.end_tag),
				if x.opts.indent_script { 1 } else { 0 }, false)
		}
		.style_element {
			for ch in n.children {
				x.ignore(x.doc.nodes[ch].start, x.doc.nodes[ch].end)
			}
		}
		.element {
			name_type := if n.name_ref.idx >= 0 { x.type_of(n.name_ref) } else { '' }
			if name_type in ['Identifier', 'SvelteName'] {
				name := if n.name_ref.es {
					x.doc.es.string_of(n.name_ref.idx, .name) or { '' }
				} else {
					x.doc.nodes[n.name_ref.idx].name
				}
				if name in svi_preformatted {
					start_tag := x.first(s) or { return }
					if n.end_tag >= 0 {
						x.set(x.first(x.sn(n.end_tag)), 0, start_tag)
					}
					for ch in n.children {
						x.ignore(x.doc.nodes[ch].start, x.doc.nodes[ch].end)
					}
					return
				}
				if name == 'style' {
					for ch in n.children {
						x.ignore(x.doc.nodes[ch].start, x.doc.nodes[ch].end)
					}
					return
				}
			}
			if n.end_tag >= 0 {
				children := n.children.filter(!(x.doc.nodes[it].typ == .text
					&& svi_blank(x.doc.nodes[it].value)))
				x.element_list(x.sns(children), x.sn(n.start_tag), x.sn(n.end_tag), 1,
					false)
			}
		}
		.start_tag {
			open := x.first(s) or { return }
			close := x.last(s) or { return }
			x.element_list(x.sns(n.attributes), open, close, 1, x.opts.align)
			if n.self_closing {
				if slash := x.tb(close) {
					if slash.value == '/' {
						x.set(slash, 0, open)
					}
				}
			}
		}
		.end_tag, .shorthand_attribute, .spread_attribute {
			open := x.first(s) or { return }
			close := x.last(s) or { return }
			x.element_list([], open, close, 1, false)
		}
		.attribute, .directive, .style_directive, .special_directive {
			x.attribute(i)
		}
		.text {
			mut tokens := x.tokens(s, false, .not_ws)
			if tokens.len == 0 {
				return
			}
			first := tokens[0]
			tokens.delete(0)
			offset := if x.is_beginning_of_line(first) {
				0
			} else if x.is_beginning_of_element(i) {
				1
			} else {
				0
			}
			x.sets(tokens, offset, first)
		}
		.literal {
			mut tokens := x.tokens(s, false, .not_ws)
			if tokens.len == 0 {
				return
			}
			first := tokens[0]
			tokens.delete(0)
			x.sets(tokens, if x.is_beginning_of_line(first) { 0 } else { 1 }, first)
		}
		.mustache_tag {
			open := x.first(s) or { return }
			close := x.last(s) or { return }
			x.element_list([x.span_of(n.expression)], open, close, 1, false)
		}
		.debug_tag {
			open := x.first(s) or { return }
			close := x.last(s) or { return }
			x.element_list(n.identifiers.map(x.es(it)), open, close, 1, false)
		}
		.const_tag {
			open := x.first(s) or { return }
			const_token := x.ta(open)
			declaration := if n.declarations.len > 0 { x.es(n.declarations[0]) } else { svi_null }
			close := x.last(s)
			x.set(const_token, 1, open)
			x.set(x.first(declaration), 1, open)
			x.set(close, 0, open)
		}
		.declaration_tag {
			open := x.first(s) or { return }
			x.set(x.first(x.span_of(n.declaration)), 1, open)
			x.set(x.last(s), 0, open)
		}
		.render_tag {
			open := x.first(s) or { return }
			render := x.ta(open) or { return }
			x.set(render, 1, open)
			// setOffsetToken(node.expression): the node as a token, its start.
			expression := x.span_of(n.expression)
			if expression.start >= 0 {
				x.set_index(expression.start, 1, render.start)
			}
		}
		.if_block {
			ft := x.firsts(s, if n.elseif { 3 } else { 2 })
			open := svi_at(ft, 0) or { return }
			if_tokens := if ft.len > 1 { ft[1..] } else { []svelte.Token{} }
			x.sets(if_tokens, 1, open)
			exp := x.fl(x.span_of(n.expression), 0) or { return }
			if if_tokens.len > 0 {
				x.set(exp.first, 1, if_tokens[0])
			}
			x.set(x.ta(exp.last), 0, open)
			x.children_first(n.children, open)
			if n.else_ >= 0 {
				x.set(x.first(x.sn(n.else_)), 0, open)
				if x.doc.nodes[n.else_].elseif {
					return
				}
			}
			x.close_tag(s, open)
		}
		.else_block {
			if n.elseif {
				return
			}
			ft := x.firsts(s, 3)
			open := svi_at(ft, 0) or { return }
			x.set(svi_at(ft, 1), 1, open)
			x.set(svi_at(ft, 2), 0, open)
			x.children_first(n.children, open)
		}
		.each_block {
			ft := x.firsts(s, 2)
			open := svi_at(ft, 0) or { return }
			each := svi_at(ft, 1) or { return }
			x.set(each, 1, open)
			x.element_list([x.span_of(n.expression), x.span_of(n.context), x.span_of(n.index_ref)],
				each, none, 1, false)
			if n.key_expr.idx >= 0 {
				key := x.fl(x.span_of(n.key_expr), 0) or { return }
				x.set(key.first, 1, each)
				x.set(x.ta(key.last), 0, open)
			} else {
				mut last := x.span_of(n.index_ref)
				if last.start < 0 {
					last = x.span_of(n.context)
				}
				if last.start < 0 {
					last = x.span_of(n.expression)
				}
				x.set(x.ta(last), 0, open)
			}
			x.children_first(n.children, open)
			if n.else_ >= 0 {
				x.set(x.first(x.sn(n.else_)), 0, open)
			}
			x.close_tag(s, open)
		}
		.await_block {
			ft := x.firsts(s, 2)
			open := svi_at(ft, 0) or { return }
			await_token := svi_at(ft, 1) or { return }
			x.set(await_token, 1, open)
			exp := x.fl(x.span_of(n.expression), 0) or { return }
			x.set(exp.first, 1, await_token)
			if n.pending >= 0 {
				x.set(x.ta(exp.last), 0, open)
				x.set(x.first_f(x.sn(n.pending), .not_ws), 1, open)
			}
			if n.then >= 0 {
				if n.kind == 'await-then' {
					then_token := x.ta(exp.last) or { return }
					x.set(then_token, 1, open)
					value := x.span_of(x.doc.nodes[n.then].value_es)
					if value.start >= 0 {
						x.set(x.first(value), 1, then_token)
					}
					x.set(x.ta(svi_or(value, then_token)), 0, open)
				} else {
					x.set(x.first(x.sn(n.then)), 0, open)
				}
			}
			if n.catch_ >= 0 {
				if n.kind == 'await-catch' {
					catch_token := x.ta(exp.last) or { return }
					x.set(catch_token, 1, open)
					error := x.span_of(x.doc.nodes[n.catch_].error_es)
					if error.start >= 0 {
						x.set(x.first(error), 1, catch_token)
					}
					x.set(x.ta(svi_or(error, catch_token)), 0, open)
				} else {
					x.set(x.first(x.sn(n.catch_)), 0, open)
				}
			}
			x.close_tag(s, open)
		}
		.await_pending_block {
			open := x.first(s) or { return }
			x.children_first(n.children, open)
		}
		.await_then_block, .await_catch_block {
			value := x.span_of(if n.typ == .await_then_block { n.value_es } else { n.error_es })
			awaited := if n.typ == .await_then_block { n.await_then } else { n.await_catch }
			if !awaited {
				ft := x.firsts(s, 2)
				open := svi_at(ft, 0) or { return }
				keyword := svi_at(ft, 1) or { return }
				x.set(keyword, 1, open)
				if value.start >= 0 {
					x.set(x.first(value), 1, keyword)
				}
				x.set(x.ta(svi_or(value, keyword)), 0, open)
			}
			open := x.first(s) or { return }
			x.children_first(n.children, open)
		}
		.key_block {
			ft := x.firsts(s, 2)
			open := svi_at(ft, 0) or { return }
			key := svi_at(ft, 1) or { return }
			x.set(key, 1, open)
			exp := x.fl(x.span_of(n.expression), 0) or { return }
			x.set(exp.first, 1, key)
			x.set(x.ta(exp.last), 0, open)
			x.children_first(n.children, open)
			x.close_tag(s, open)
		}
		.snippet_block {
			ft := x.firsts(s, 2)
			open := svi_at(ft, 0) or { return }
			snippet := svi_at(ft, 1) or { return }
			x.set(snippet, 1, open)
			name := x.ta(snippet) or { return }
			x.set(name, 1, snippet)
			params := n.params.map(x.es(it))
			anchor := if params.len > 0 { params[0] } else { svi_span(x.last(s)) }
			left_paren := x.tbf(anchor, .open_paren) or { return }
			right_paren := x.taf(svi_last_or(params, left_paren), .close_paren) or { return }
			x.set(left_paren, 1, name)
			x.element_list(params, left_paren, right_paren, 1, false)
			x.set(x.ta(right_paren), 0, open)
			x.children_first(n.children, open)
			x.close_tag(s, open)
		}
		else {}
	}
}
