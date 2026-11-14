module rules

import estree
import time

// Port of the `unicorn/prefer-array-index-of` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options; rules/shared/simple-array-search-rule.js), with its fix and suggestion.

const upaio_messages = {
	'prefer-indexOf-over-findIndex/error':              'Use `.indexOf()` instead of `.findIndex()` when looking for the index of an item.'
	'prefer-indexOf-over-findIndex/suggestion':         'Replace `.findIndex()` with `.indexOf()`.'
	'prefer-lastIndexOf-over-findLastIndex/error':      'Use `.lastIndexOf()` instead of `.findLastIndex()` when looking for the index of an item.'
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

// un_single_return_expression ports getSingleReturnExpression: the returned expression of
// `bar => …`, `bar => {return …}` or `function (bar) {return …}` (not async, not a generator, one
// parameter); -1 for anything else.
fn un_single_return_expression(t &estree.EsTree, node int) int {
	if t.typ(node) !in [.arrow_function_expression, .function_expression]
		|| (t.flag(node, .async) or { false }) || (t.flag(node, .generator) or { false })
		|| (t.list(node, .params) or { []int{} }).len != 1 {
		return -1
	}
	return un_function_return_expression(t, node)
}

// un_simple_compare_body is the `===` of a callback `x => x === y` or `function (x) { return x ===
// y }` (isSimpleCompareCallbackFunction), none for any other.
fn un_simple_compare_body(t &estree.EsTree, node int) ?int {
	expression := un_single_return_expression(t, node)
	if expression < 0 {
		return none
	}
	parameter := (t.list(node, .params) or { return none })[0]
	return if un_is_simple_compare(t, expression, parameter) { expression } else { none }
}

// un_search_value_not_assignable is the type check of the search value: with types, the value is
// not assignable to the parameter of the replacement method of the receiver.
fn (mut c Checker) un_search_value_not_assignable(mut ctx UnCtx, call int, search_value int, replacement string) bool {
	t := ctx.t
	search_type := c.un_ts_type(ctx, search_value) or { return false }
	object := t.node(t.node(call, .callee) or { return false }, .object) or { return false }
	receiver := c.un_ts_type(ctx, object) or { return false }
	non_nullable := c.client.non_nullable_type(c.snapshot, c.project, receiver.id) or { return false }
	method := c.property(non_nullable, replacement) or { return false }
	if method.id == 0 {
		return false
	}
	call_ts := t.ts_node(call) or { return false }
	mut stats := Stats{}
	c.resolve_node_types([call_ts], ctx.abs_path, mut stats) or { return false }
	location := c.symbol_location(call_ts)
	method_type := c.symbol_type_at(method, location) or { return false }
	signatures := c.signatures_of(method_type, signature_kind_call) or { return false }
	if signatures.len == 0 {
		return false
	}
	parameters := c.signature_parameters(signatures[0]) or { return false }
	if parameters.len == 0 {
		return false
	}
	parameter_type := c.parameter_type_at(parameters[0], location) or { return false }
	return !(c.assignable(search_type.id, parameter_type.id) or { return false })
}

fn (mut c Checker) lint_unicorn_prefer_array_index_of(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		for method, replacement in {
			'findIndex':     'indexOf'
			'findLastIndex': 'lastIndexOf'
		} {
			if finding := c.un_simple_array_search(mut ctx, node, method, replacement) {
				findings << finding
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// un_simple_array_search ports the listener of simpleArraySearchRule.
fn (mut c Checker) un_simple_array_search(mut ctx UnCtx, node int, method string, replacement string) ?Finding {
	t := ctx.t
	tokens := ctx.tokens
	root := ctx.root
	if !un_is_method_call(t, node, methods: [method], arguments_length: 1, optional_call: false) {
		return none
	}
	callback := (t.list(node, .arguments) or { return none })[0]
	binary := un_simple_compare_body(t, callback)?
	// Receivers known to be neither an array nor a typed array are left.
	if c.un_should_skip_known_non_array_receiver(mut ctx, t.node(t.node(node, .callee)?, .object)?) {
		return none
	}
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
	if c.un_search_value_not_assignable(mut ctx, node, search_value, replacement) {
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
	// The callback is replaced by the search value: a comment inside it would be lost.
	if tokens.comments_inside(t.nodes[callback].start, t.nodes[callback].end).len > 0 {
		return Finding{
			stmt:       c.es_tree_position(t, method_node)
			message_id: 'prefer-${replacement}-over-${method}/error'
		}
	}
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
