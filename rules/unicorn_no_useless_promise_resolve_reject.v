module rules

import estree
import time

// Port of the `unicorn/no-useless-promise-resolve-reject` rule of eslint-plugin-unicorn 79.0.0 (it
// has no options), with its fix.

const unuprr_messages = {
	'resolve': 'Prefer `{{type}} value` over `{{type}} Promise.resolve(value)`.'
	'reject':  'Prefer `throw error` over `{{type}} Promise.reject(error)`.'
}

// UnuprrInfo is getCallExpressionInfo: the expression of the call (its `await` when awaited) and
// its parent.
struct UnuprrInfo {
	expression int
	parent     int
	is_awaited bool
}

fn (mut c Checker) lint_unicorn_no_useless_promise_resolve_reject(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for call in 0 .. t.nodes.len {
		if t.typ(call) != .call_expression {
			continue
		}
		stats.checked++
		info := unuprr_info(t, call)
		if info.parent < 0 || !un_is_method_call(t, call,
			objects:         ['Promise']
			methods:         ['resolve', 'reject']
			optional_call:   false
			optional_member: false
		) {
			continue
		}
		parent := info.parent
		in_position := match t.typ(parent) {
			.arrow_function_expression { (t.node(parent, .body) or { -1 }) == info.expression }
			.return_statement { (t.node(parent, .argument) or { -1 }) == info.expression }
			.yield_expression {
				!(t.flag(parent, .delegate) or { false })
					&& (t.node(parent, .argument) or { -1 }) == info.expression
			}
			else { false }
		}
		if !in_position {
			continue
		}
		// getFunctionNode
		mut function := -1
		mut in_try := false
		mut node := call
		for node >= 0 {
			if unb_is_function(t, node) {
				function = node
				break
			}
			if t.typ(node) == .try_statement {
				in_try = true
			}
			node = t.nodes[node].parent
		}
		// A synchronous generator callback returns an iterator, whose values the promise does not
		// adopt.
		if function < 0 || !((t.flag(function, .async) or { false })
			|| (!(t.flag(function, .generator) or { false })
				&& unuprr_is_promise_callback(t, function))) {
			continue
		}
		callee := t.node(call, .callee) or { continue }
		method := t.string_of(t.node(callee, .property) or { continue }, .name) or { continue }
		mut finding := Finding{
			stmt:       c.es_tree_position(t, callee)
			message_id: method
			data:       {
				'type': if t.typ(parent) == .yield_expression { 'yield' } else { 'return' }
			}
		}
		if f := c.unuprr_fix(t, tokens, call, info, in_try) {
			finding = Finding{
				...finding
				has_fix: true
				fix:     f
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unuprr_info ports getCallExpressionInfo.
fn unuprr_info(t &estree.EsTree, call int) UnuprrInfo {
	parent := t.nodes[call].parent
	if parent >= 0 && t.typ(parent) == .await_expression
		&& (t.node(parent, .argument) or { -1 }) == call {
		return UnuprrInfo{
			expression: parent
			parent:     t.nodes[parent].parent
			is_awaited: true
		}
	}
	return UnuprrInfo{
		expression: call
		parent:     parent
	}
}

// unuprr_is_promise_callback ports isPromiseCallback: a function given to `then`, `catch` or
// `finally`.
fn unuprr_is_promise_callback(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .call_expression {
		return false
	}
	callee := t.node(parent, .callee) or { return false }
	if t.typ(callee) != .member_expression || (t.flag(callee, .computed) or { false }) {
		return false
	}
	property := t.node(callee, .property) or { return false }
	if t.typ(property) != .identifier {
		return false
	}
	name := t.string_of(property, .name) or { return false }
	arguments := t.list(parent, .arguments) or { return false }
	if arguments.len == 1 && name in ['then', 'catch', 'finally'] && arguments[0] == node {
		return true
	}
	return arguments.len == 2 && name == 'then' && (arguments[0] == node
		|| (t.typ(arguments[0]) != .spread_element && arguments[1] == node))
}

// unuprr_concise_arrow_body_text ports getConciseArrowBodyText.
fn (c &Checker) unuprr_concise_arrow_body_text(t &estree.EsTree, tokens &SourceTokens, node int) string {
	mut needs_parens := c.src[t.nodes[node].start..t.nodes[node].end].starts_with('{')
		|| t.typ(node) in [.sequence_expression, .assignment_expression]
	if !needs_parens {
		mut in_for_init := false
		mut current := node
		for t.nodes[current].parent >= 0 {
			parent := t.nodes[current].parent
			if t.typ(parent) == .for_statement && (t.node(parent, .init) or { -1 }) == current {
				in_for_init = true
				break
			}
			current = parent
		}
		if in_for_init {
			needs_parens = tokens.inside(t.nodes[node].start, t.nodes[node].end, false).any(it.kind == .keyword
				&& c.src[it.start..it.end] == 'in')
		}
	}
	return c.unb_expression_text(t, tokens, node, needs_parens)
}

// unuprr_awaited_text ports getAwaitedResolveArgumentText.
fn (c &Checker) unuprr_awaited_text(t &estree.EsTree, tokens &SourceTokens, node int) string {
	if node < 0 {
		return 'undefined'
	}
	text := c.unb_call_argument_text(t, tokens, node)
	if t.typ(node) != .sequence_expression && unb_should_add_parens_to_await_argument(t, node) {
		return '(${text})'
	}
	return text
}

// unuprr_fix ports fix: none when it cannot be made safely.
fn (c &Checker) unuprr_fix(t &estree.EsTree, tokens &SourceTokens, call int, info UnuprrInfo, in_try bool) ?Fix {
	arguments := t.list(call, .arguments) or { []int{} }
	if arguments.len > 1 {
		return none
	}
	value := if arguments.len == 1 { arguments[0] } else { -1 }
	if value >= 0 && t.typ(value) == .spread_element {
		return none
	}
	callee := t.node(call, .callee)?
	is_reject := (t.string_of(t.node(callee, .property)?, .name) or { '' }) == 'reject'
	parent := info.parent
	is_yield := t.typ(parent) == .yield_expression
	if is_reject && (in_try || (is_yield
		&& t.typ(t.nodes[parent].parent) != .expression_statement)) {
		return none
	}
	// getFixTarget
	target := if info.is_awaited && !is_reject {
		start, end := c.un_parenthesized_range(t, tokens, call)
		UnRange{start, end}
	} else if is_reject && is_yield {
		start, end := c.un_parenthesized_range(t, tokens, parent)
		UnRange{start, end}
	} else if t.typ(parent) == .arrow_function_expression {
		if is_reject {
			start, end := c.un_parenthesized_range(t, tokens, info.expression)
			UnRange{start, end}
		} else {
			un_range(t, call)
		}
	} else {
		un_range(t, parent)
	}
	if un_would_remove_comments(tokens, target.start, target.end, if value >= 0 {
		[un_range(t, value)]
	} else {
		[]UnRange{}
	}) {
		return none
	}
	is_arrow_body := t.typ(parent) == .arrow_function_expression
	mut text := if value >= 0 { c.unb_call_argument_text(t, tokens, value) } else { '' }
	if is_reject {
		// `return Promise.reject()` becomes `throw undefined`.
		if text == '' {
			text = 'undefined'
		}
		text = 'throw ${text}'
		if is_yield {
			start, end := c.un_parenthesized_range(t, tokens, parent)
			return fix_replace_range(start, end, text)
		}
		text += ';'
		// `=> Promise.reject(error)` becomes `=> { throw error; }`.
		if is_arrow_body {
			start, end := c.un_parenthesized_range(t, tokens, info.expression)
			return fix_replace_range(start, end, '{ ${text} }')
		}
	} else {
		if info.is_awaited {
			start, end := c.un_parenthesized_range(t, tokens, call)
			return fix_replace_range(start, end, c.unuprr_awaited_text(t, tokens, value))
		}
		if is_yield {
			text = 'yield${if text != '' { ' ' } else { '' }}${text}'
		} else if t.typ(parent) == .return_statement {
			text = 'return${if text != '' { ' ' } else { '' }}${text};'
		} else {
			// `=> Promise.resolve()` becomes `=> {}`.
			text = if value >= 0 {
				c.unuprr_concise_arrow_body_text(t, tokens, value)
			} else {
				'{}'
			}
		}
	}
	replaced := if is_arrow_body { call } else { parent }
	return fix_replace_range(t.nodes[replaced].start, t.nodes[replaced].end, text)
}
