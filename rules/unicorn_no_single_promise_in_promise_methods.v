module rules

import estree
import time

// Port of the `unicorn/no-single-promise-in-promise-methods` rule of eslint-plugin-unicorn 79.0.0
// (it has no options), with its fixes and suggestions.

const unspipm_messages = {
	'no-single-promise-in-promise-methods/error':               'Wrapping single-element array with `Promise.{{method}}()` is unnecessary.'
	'no-single-promise-in-promise-methods/unwrap':              'Use the value directly.'
	'no-single-promise-in-promise-methods/use-promise-resolve': 'Switch to `Promise.resolve(…)`.'
}

fn (mut c Checker) lint_unicorn_no_single_promise_in_promise_methods(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for call in 0 .. t.nodes.len {
		if t.typ(call) != .call_expression {
			continue
		}
		stats.checked++
		if !unspipm_is_single_element_call(t, call) {
			continue
		}
		if f := c.unspipm_problem(t, tokens, call) {
			findings << f
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unspipm_is_single_element_call ports isPromiseMethodCallWithSingleElementArray.
fn unspipm_is_single_element_call(t &estree.EsTree, node int) bool {
	if !un_is_method_call(t, node,
		objects:          ['Promise']
		methods:          ['all', 'any', 'race']
		optional_member:  false
		optional_call:    false
		arguments_length: 1
	) {
		return false
	}
	array := (t.list(node, .arguments) or { return false })[0]
	if t.typ(array) != .array_expression {
		return false
	}
	elements := t.list(array, .elements) or { return false }
	return elements.len == 1 && elements[0] >= 0 && t.typ(elements[0]) != .spread_element
}

fn unspipm_promise(t &estree.EsTree, call int) int {
	array := (t.list(call, .arguments) or { return -1 })[0]
	return (t.list(array, .elements) or { return -1 })[0]
}

// unspipm_awaited_text ports getAwaitedPromiseText.
fn (c &Checker) unspipm_awaited_text(t &estree.EsTree, tokens &SourceTokens, call int) string {
	promise := unspipm_promise(t, call)
	text := c.un_parenthesized_text(t, tokens, promise)
	if !c.un_is_parenthesized(t, tokens, promise) && unb_should_add_parens_to_await_argument(t, promise) {
		return '(${text})'
	}
	return text
}

// unspipm_unwrap_awaited ports unwrapAwaitedCallExpression.
fn (c &Checker) unspipm_unwrap_awaited(t &estree.EsTree, tokens &SourceTokens, call int) []Fix {
	mut fixes := c.un_fix_space_around_keyword(t, tokens, call)
	fixes << fix_replace_range(t.nodes[call].start, t.nodes[call].end, c.unspipm_awaited_text(t,
		tokens, call))
	return fixes
}

// unspipm_unwrap_not_awaited ports unwrapNonAwaitedCallExpression.
fn (c &Checker) unspipm_unwrap_not_awaited(t &estree.EsTree, tokens &SourceTokens, call int) []Fix {
	promise := unspipm_promise(t, call)
	mut text := c.un_parenthesized_text(t, tokens, promise)
	if !c.un_is_parenthesized(t, tokens, promise)
		&& (c.un_expression_start_needs_parens(t, tokens, promise, call)
			|| t.typ(promise) !in [.identifier, .member_expression]) {
		text = '(${text})'
	}
	if c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[call].start, false), text) {
		text = ';${text}'
	}
	mut fixes := c.un_fix_space_around_keyword(t, tokens, call)
	fixes << fix_replace_range(t.nodes[call].start, t.nodes[call].end, text)
	return fixes
}

// unspipm_switch_to_resolve ports switchToPromiseResolve.
fn (c &Checker) unspipm_switch_to_resolve(t &estree.EsTree, tokens &SourceTokens, call int) []Fix {
	property := t.node(t.node(call, .callee) or { return [] }, .property) or { return [] }
	array := (t.list(call, .arguments) or { return [] })[0]
	inside := tokens.inside(t.nodes[array].start, t.nodes[array].end, false)
	if inside.len < 2 {
		return []
	}
	mut fixes := [
		fix_replace_range(t.nodes[property].start, t.nodes[property].end, 'resolve'),
		fix_remove_range(inside[0].start, inside[0].end),
		fix_remove_range(inside.last().start, inside.last().end),
	]
	penultimate := inside[inside.len - 2]
	if c.token_is(penultimate, ',') {
		fixes << fix_remove_range(penultimate.start, penultimate.end)
	}
	return fixes
}

// unspipm_is_single_identifier_array_pattern ports isSingleIdentifierArrayPattern.
fn unspipm_is_single_identifier_array_pattern(t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) != .array_pattern || t.node(node, .type_annotation) != none {
		return false
	}
	elements := t.list(node, .elements) or { return false }
	return elements.len == 1 && elements[0] >= 0 && t.typ(elements[0]) == .identifier
}

// unspipm_is_expression_statement ports isExpressionStatement of ast/.
fn unspipm_is_expression_statement(t &estree.EsTree, node int) bool {
	if node < 0 {
		return false
	}
	if t.typ(node) == .expression_statement {
		return true
	}
	parent := t.nodes[node].parent
	return t.typ(node) == .chain_expression && parent >= 0
		&& t.typ(parent) == .expression_statement
}

// unspipm_destructuring_pattern ports getPromiseAllDestructuringPattern: `const [a] = await …`
// or `[a] = await …;`.
fn unspipm_destructuring_pattern(t &estree.EsTree, await_expression int) int {
	parent := t.nodes[await_expression].parent
	if parent < 0 {
		return -1
	}
	if t.typ(parent) == .variable_declarator && (t.node(parent, .init) or { -1 }) == await_expression {
		id := t.node(parent, .id) or { return -1 }
		if unspipm_is_single_identifier_array_pattern(t, id) {
			return id
		}
	}
	if t.typ(parent) == .assignment_expression
		&& (t.node(parent, .right) or { -1 }) == await_expression {
		left := t.node(parent, .left) or { return -1 }
		if unspipm_is_single_identifier_array_pattern(t, left)
			&& unspipm_is_expression_statement(t, t.nodes[parent].parent) {
			return left
		}
	}
	return -1
}

// unspipm_fix_all_first_element ports fixPromiseAllFirstElement: `const [a] = await
// Promise.all([p])` and `(await Promise.all([p]))[0]`.
fn (c &Checker) unspipm_fix_all_first_element(t &estree.EsTree, tokens &SourceTokens, call int) ?[]Fix {
	promise_start, promise_end := c.un_parenthesized_range(t, tokens, unspipm_promise(t, call))
	promise_range := UnRange{promise_start, promise_end}
	if un_would_remove_comments(tokens, t.nodes[call].start, t.nodes[call].end, [promise_range]) {
		return none
	}
	await_expression := t.nodes[call].parent
	if t.typ(await_expression) != .await_expression
		|| (t.node(await_expression, .argument) or { -1 }) != call {
		return none
	}
	pattern := unspipm_destructuring_pattern(t, await_expression)
	if pattern >= 0 {
		if un_would_remove_comments(tokens, t.nodes[pattern].start, t.nodes[pattern].end, []) {
			return none
		}
		element := (t.list(pattern, .elements) or { return none })[0]
		mut fixes := c.un_fix_space_around_keyword(t, tokens, pattern)
		fixes << c.un_fix_space_around_keyword(t, tokens, call)
		fixes << fix_replace_range(t.nodes[pattern].start, t.nodes[pattern].end, c.src[t.nodes[element].start..t.nodes[element].end])
		fixes << fix_replace_range(t.nodes[call].start, t.nodes[call].end, c.unspipm_awaited_text(t,
			tokens, call))
		return fixes
	}
	member := t.nodes[await_expression].parent
	if member < 0 || t.typ(member) != .member_expression || !(t.flag(member, .computed) or { false }) {
		return none
	}
	property := t.node(member, .property) or { return none }
	value := t.get(property, .value)
	if t.typ(property) != .literal || !(value is f64 && value == 0)
		|| (t.node(member, .object) or { -1 }) != await_expression {
		return none
	}
	parent := t.nodes[member].parent
	safe := parent >= 0 && ((t.typ(parent) == .variable_declarator
		&& (t.node(parent, .init) or { -1 }) == member) || (t.typ(parent) == .assignment_expression
		&& (t.node(parent, .right) or { -1 }) == member))
	if !safe || un_would_remove_comments(tokens, t.nodes[member].start, t.nodes[member].end, [
		promise_range,
	]) {
		return none
	}
	return [fix_replace_range(t.nodes[member].start, t.nodes[member].end, 'await ${c.unspipm_awaited_text(t, tokens, call)}')]
}

fn (c &Checker) unspipm_problem(t &estree.EsTree, tokens &SourceTokens, call int) ?Finding {
	method := t.string_of(t.node(t.node(call, .callee)?, .property)?, .name)?
	array := (t.list(call, .arguments)?)[0]
	mut finding := Finding{
		stmt:       c.es_tree_position(t, array)
		message_id: 'no-single-promise-in-promise-methods/error'
		data:       {
			'method': method
		}
	}
	// The unwrapped call is rebuilt from the promise alone: comments outside it would be lost.
	promise_start, promise_end := c.un_parenthesized_range(t, tokens, unspipm_promise(t, call))
	can_unwrap := !un_is_left_hand_side(t, call)
		&& !un_would_remove_comments(tokens, t.nodes[call].start, t.nodes[call].end, [
			UnRange{promise_start, promise_end},
		])
	parent := t.nodes[call].parent
	is_awaited := parent >= 0 && t.typ(parent) == .await_expression
		&& (t.node(parent, .argument) or { -1 }) == call
	// `Promise.any()` wraps rejections in `AggregateError`: unwrapping stays a suggestion.
	if method != 'any' && is_awaited
		&& (method != 'all' || unspipm_is_expression_statement(t, t.nodes[parent].parent)) {
		if can_unwrap {
			has_fix, fix := c.merge_fixes(c.unspipm_unwrap_awaited(t, tokens, call)) or {
				return finding
			}
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
		return finding
	}
	if method == 'all' {
		if fixes := c.unspipm_fix_all_first_element(t, tokens, call) {
			has_fix, fix := c.merge_fixes(fixes) or { return finding }
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
		return finding
	}
	mut suggestions := []Suggestion{}
	if can_unwrap {
		fixes := if is_awaited {
			c.unspipm_unwrap_awaited(t, tokens, call)
		} else {
			c.unspipm_unwrap_not_awaited(t, tokens, call)
		}
		has_fix, fix := c.merge_fixes(fixes) or { false, Fix{} }
		if has_fix {
			suggestions << Suggestion{
				message_id: 'no-single-promise-in-promise-methods/unwrap'
				fix:        fix
			}
		}
	}
	has_fix, fix := c.merge_fixes(c.unspipm_switch_to_resolve(t, tokens, call)) or { false, Fix{} }
	if has_fix {
		suggestions << Suggestion{
			message_id: 'no-single-promise-in-promise-methods/use-promise-resolve'
			fix:        fix
		}
	}
	return Finding{
		...finding
		suggestions: suggestions
	}
}
