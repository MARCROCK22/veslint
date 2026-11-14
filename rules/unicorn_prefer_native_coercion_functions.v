module rules

import estree
import time

// Port of the `unicorn/prefer-native-coercion-functions` rule of eslint-plugin-unicorn 64.0.0 (it
// has no options), with its fix.

const upncf_messages = {
	'prefer-native-coercion-functions': '{{functionNameWithKind}} is equivalent to `{{replacementFunction}}`. Use `{{replacementFunction}}` directly.'
}

const upncf_coercions = ['String', 'Number', 'BigInt', 'Boolean', 'Symbol']
const upncf_boolean_callbacks = ['every', 'filter', 'find', 'findLast', 'findIndex', 'findLastIndex',
	'some']

fn upncf_name(t &estree.EsTree, node int) string {
	return t.string_of(node, .name) or { '' }
}

// upncf_coercion_call ports isNativeCoercionFunctionCall: `String(v)` with the parameter first.
fn upncf_coercion_call(t &estree.EsTree, node int, parameter string) bool {
	if node < 0 || t.typ(node) != .call_expression || (t.flag(node, .optional) or { false }) {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	args := t.list(node, .arguments) or { return false }
	return t.typ(callee) == .identifier && upncf_name(t, callee) in upncf_coercions && args.len > 0
		&& t.typ(args[0]) == .identifier && upncf_name(t, args[0]) == parameter
}

// upncf_single_return is the argument of `{ return …; }`, the only statement of the body.
fn upncf_single_return(t &estree.EsTree, body int) ?int {
	if t.typ(body) != .block_statement {
		return none
	}
	statements := t.list(body, .body) or { return none }
	if statements.len != 1 || t.typ(statements[0]) != .return_statement {
		return none
	}
	return t.node(statements[0], .argument)
}

// upncf_identity ports isIdentityFunction: `v => v`, `(v) => { return v; }`.
fn upncf_identity(t &estree.EsTree, node int, parameter string) bool {
	body := t.node(node, .body) or { return false }
	if t.typ(node) == .arrow_function_expression && t.typ(body) == .identifier
		&& upncf_name(t, body) == parameter {
		return true
	}
	argument := upncf_single_return(t, body) or { return false }
	return t.typ(argument) == .identifier && upncf_name(t, argument) == parameter
}

// upncf_array_identity ports isArrayIdentityCallback: the identity as the first argument of
// `every`, `filter`, `find`…
fn upncf_array_identity(t &estree.EsTree, node int, parameter string) bool {
	if !upncf_identity(t, node, parameter) {
		return false
	}
	call := t.nodes[node].parent
	if t.typ(call) != .call_expression || (t.flag(call, .optional) or { false }) {
		return false
	}
	args := t.list(call, .arguments) or { return false }
	if args.len == 0 || args[0] != node {
		return false
	}
	callee := t.node(call, .callee) or { return false }
	if t.typ(callee) != .member_expression || (t.flag(callee, .computed) or { false })
		|| (t.flag(callee, .optional) or { false }) {
		return false
	}
	property := t.node(callee, .property) or { return false }
	return t.typ(property) == .identifier && upncf_name(t, property) in upncf_boolean_callbacks
}

// upncf_type_predicate ports isTypeScriptTypePredicateFunction: `(v): v is T => …`.
fn upncf_type_predicate(t &estree.EsTree, node int) bool {
	return_type := t.node(node, .return_type) or { return false }
	inner := t.node(return_type, .type_annotation) or { return false }
	return t.typ(return_type) == .ts_type_annotation && t.typ(inner) == .ts_type_predicate
}

fn (mut c Checker) lint_unicorn_prefer_native_coercion_functions(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		typ := t.typ(node)
		if typ !in [.function_declaration, .function_expression, .arrow_function_expression] {
			continue
		}
		stats.checked++
		params := t.list(node, .params) or { continue }
		if (t.flag(node, .async) or { false }) || (t.flag(node, .generator) or { false })
			|| params.len == 0 || t.typ(params[0]) != .identifier {
			continue
		}
		parent := t.nodes[node].parent
		kind := t.string_of(parent, .kind) or { '' }
		if ((t.typ(parent) == .method_definition && kind in ['constructor', 'set'])
			|| (t.typ(parent) == .property && kind == 'set'))
			&& t.node(parent, .value) or { -1 } == node {
			continue
		}
		parameter := upncf_name(t, params[0])
		mut replacement := ''
		mut fix_text := ?string(none)
		if upncf_array_identity(t, node, parameter) && !upncf_type_predicate(t, node) {
			replacement = 'Boolean'
			fix_text = 'Boolean'
		} else {
			// getCallExpression
			body := t.node(node, .body) or { continue }
			mut call := -1
			if typ == .arrow_function_expression && upncf_coercion_call(t, body, parameter) {
				call = body
			} else if argument := upncf_single_return(t, body) {
				if upncf_coercion_call(t, argument, parameter) {
					call = argument
				}
			}
			if call < 0 {
				continue
			}
			replacement = upncf_name(t, t.node(call, .callee) or { continue })
			if typ != .function_declaration && (t.list(call, .arguments) or { []int{} }).len == 1 {
				mut text := replacement
				if t.typ(parent) == .property && (t.flag(parent, .method) or { false })
					&& t.node(parent, .value) or { -1 } == node {
					text = ': ${text}'
				} else if t.typ(parent) == .method_definition {
					text = ' = ${text};'
				}
				fix_text = text
			}
		}
		mut finding := Finding{
			stmt:       c.es_tree_function_head(t, node)
			message_id: 'prefer-native-coercion-functions'
			data:       {
				'functionNameWithKind': c.un_function_name_with_kind(t, node)
				'replacementFunction':  replacement
			}
		}
		// No fix with comments, which would have no place, or with more parameters.
		if text := fix_text {
			if params.len == 1 && tokens.comments_inside(t.nodes[node].start, t.nodes[node].end).len == 0 {
				finding = Finding{
					...finding
					has_fix: true
					fix:     fix_replace_range(t.nodes[node].start, t.nodes[node].end, text)
				}
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
