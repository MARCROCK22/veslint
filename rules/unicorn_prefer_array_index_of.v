module rules

import estree
import time

// Port of the `unicorn/prefer-array-index-of` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options; rules/shared/simple-array-search-rule.js), with its fix and suggestion.

const upaio_messages = {
	'prefer-indexOf-over-findIndex/error':              'Use `.indexOf()` instead of `.findIndex()` when looking for the index of an item.'
	'prefer-indexOf-over-findIndex/suggestion':         'Replace `.findIndex()` with `.indexOf()`.'
	'prefer-lastIndexOf-over-findLastIndex/error':      'Use `.lastIndexOf()` instead of `.findLastIndex() when looking for the index of an item.`'
	'prefer-lastIndexOf-over-findLastIndex/suggestion': 'Replace `.findLastIndex()` with `.lastIndexOf()`.'
}

fn un_is_same_identifier(t &estree.EsTree, a int, b int) bool {
	return a >= 0 && b >= 0 && t.typ(a) == .identifier && t.typ(b) == .identifier
		&& t.string_of(a, .name) or { '' } == t.string_of(b, .name) or { '' }
}

fn un_is_simple_compare(t &estree.EsTree, node int, compare int) bool {
	return node >= 0 && t.typ(node) == .binary_expression
		&& (t.string_of(node, .operator) or { '' }) == '==='
		&& (un_is_same_identifier(t, t.node(node, .left) or { -1 }, compare)
		|| un_is_same_identifier(t, t.node(node, .right) or { -1 }, compare))
}

// un_simple_compare_body is the `===` of a callback `x => x === y` or `function (x) { return x ===
// y }` (isSimpleCompareCallbackFunction), none for any other.
fn un_simple_compare_body(t &estree.EsTree, node int) ?int {
	typ := t.typ(node)
	if typ !in [.arrow_function_expression, .function_expression] || (t.flag(node, .async) or { false }) {
		return none
	}
	params := t.list(node, .params) or { return none }
	if params.len != 1 {
		return none
	}
	body := t.node(node, .body)?
	if typ == .arrow_function_expression && un_is_simple_compare(t, body, params[0]) {
		return body
	}
	if (t.flag(node, .generator) or { false }) || t.typ(body) != .block_statement {
		return none
	}
	statements := t.list(body, .body) or { return none }
	if statements.len != 1 || t.typ(statements[0]) != .return_statement {
		return none
	}
	argument := t.node(statements[0], .argument)?
	if un_is_simple_compare(t, argument, params[0]) {
		return argument
	}
	return none
}

fn (mut c Checker) lint_unicorn_prefer_array_index_of(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		for method, replacement in {
			'findIndex':     'indexOf'
			'findLastIndex': 'lastIndexOf'
		} {
			if finding := c.un_simple_array_search(root, t, tokens, node, method, replacement) {
				findings << finding
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// un_simple_array_search ports the listener of simpleArraySearchRule.
fn (mut c Checker) un_simple_array_search(root C.TSNode, t &estree.EsTree, tokens &SourceTokens, node int, method string, replacement string) ?Finding {
	if !un_is_method_call(t, node, methods: [method], arguments_length: 1, optional_call: false) {
		return none
	}
	callback := (t.list(node, .arguments) or { return none })[0]
	binary := un_simple_compare_body(t, callback)?
	parameter := (t.list(callback, .params) or { return none })[0]
	left := t.node(binary, .left)?
	right := t.node(binary, .right)?
	name := t.string_of(parameter, .name)?
	is_named := fn [t, name] (n int) bool {
		return t.typ(n) == .identifier && (t.string_of(n, .name) or { '' }) == name
	}
	mut search_value := -1
	mut parameter_in_binary := -1
	if is_named(left) {
		search_value, parameter_in_binary = right, left
	} else if is_named(right) {
		search_value, parameter_in_binary = left, right
	} else {
		return none
	}
	tree := c.scope_tree(root)
	v := tree.declared_variable(t.ts_node(parameter)?)
	if v < 0 {
		return none
	}
	// `parameter` is used somewhere else
	for r in tree.variables[v].references {
		if c.es_index_of(t, tree.references[r].identifier) or { -1 } != parameter_in_binary {
			return none
		}
	}
	if c.un_is_function_self_used_inside(root, t, callback) {
		return none
	}
	method_node := t.node(t.node(node, .callee)?, .property)?
	mut text := c.un_text(t, search_value)
	if c.un_is_parenthesized(t, tokens, search_value) && !c.un_is_parenthesized(t, tokens, callback) {
		text = '(${text})'
	}
	has_fix, fix := c.merge_fixes([
		fix_replace_range(t.nodes[method_node].start, t.nodes[method_node].end, replacement),
		fix_replace_range(t.nodes[callback].start, t.nodes[callback].end, text),
	]) or { return none }
	prefix := 'prefer-${replacement}-over-${method}/'
	finding := Finding{
		stmt:       c.es_tree_position(t, method_node)
		message_id: '${prefix}error'
	}
	if un_has_side_effect(t, search_value) {
		return Finding{
			...finding
			suggestions: [Suggestion{
				message_id: '${prefix}suggestion'
				fix:        fix
			}]
		}
	}
	return Finding{
		...finding
		has_fix: has_fix
		fix:     fix
	}
}
