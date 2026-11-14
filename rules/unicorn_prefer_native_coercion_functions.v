module rules

import estree
import time

// Port of the `unicorn/prefer-native-coercion-functions` rule of eslint-plugin-unicorn 79.0.0 (it
// has no options), with its fix and its suggestion.

const upncf_messages = {
	'prefer-native-coercion-functions':            '{{functionNameWithKind}} is equivalent to `{{replacementFunction}}`. Use `{{replacementFunction}}` directly.'
	'prefer-native-coercion-functions/suggestion': 'Replace with `{{replacementFunction}}`.'
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

// upncf_returned_expression ports getReturnedExpression: `v => value` or
// `function (v) {return value;}`, without the TypeScript expression wrappers of the value.
fn upncf_returned_expression(t &estree.EsTree, node int) int {
	expression := un_function_return_expression(t, node)
	return if expression < 0 { -1 } else { un_unwrap_ts_expression(t, expression) }
}

// upncf_identity ports isIdentityFunction: `v => v`.
fn upncf_identity(t &estree.EsTree, node int, parameter string) bool {
	returned := upncf_returned_expression(t, node)
	return returned >= 0 && t.typ(returned) == .identifier && upncf_name(t, returned) == parameter
}

// upncf_needs_semicolon_after ports needsSemicolonAfter: the replacement ends with a bare
// identifier, which a `(`, `[`, `+`, `-`, regular expression or template that ASI separated from
// the function would continue.
fn (c &Checker) upncf_needs_semicolon_after(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	next := tokens.after(t.nodes[node].end, false) or { return false }
	return next.start >= t.nodes[t.nodes[node].parent].end
		&& (c.token_text(next) in ['(', '[', '+', '-']
		|| next.kind in [.regular_expression, .template])
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
			|| upncf_type_predicate(t, node) || params.len == 0 || t.typ(params[0]) != .identifier {
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
		mut fixes := ?[]Fix(none)
		if upncf_array_identity(t, node, parameter) {
			replacement = 'Boolean'
			fixes = [fix_replace_range(t.nodes[node].start, t.nodes[node].end, 'Boolean')]
		} else {
			// getCallExpression: `v => String(v)`
			call := upncf_returned_expression(t, node)
			if call < 0 || !upncf_coercion_call(t, call, parameter) {
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
				} else if c.upncf_needs_semicolon_after(t, tokens, node) {
					text += ';'
				}
				mut list := [fix_replace_range(t.nodes[node].start, t.nodes[node].end, text)]
				list << c.un_fix_space_around_keyword(t, tokens, node)
				fixes = list
			}
		}
		data := {
			'functionNameWithKind': c.un_function_name_with_kind(t, node)
			'replacementFunction':  replacement
		}
		mut finding := Finding{
			stmt:       c.un_function_head_location(t, node)
			message_id: 'prefer-native-coercion-functions'
			data:       data
		}
		outer_parent := t.nodes[un_outermost_ts_expression(t, node)].parent
		is_delete := t.typ(outer_parent) == .unary_expression
			&& (t.string_of(outer_parent, .operator) or { '' }) == 'delete'
		// No fix with comments, which would have no place, or with more parameters.
		if list := fixes {
			if !is_delete && params.len == 1
				&& tokens.comments_inside(t.nodes[node].start, t.nodes[node].end).len == 0 {
				has_fix, fix := c.merge_fixes(list)!
				if t.typ(parent) == .method_definition {
					// A class field is not on the prototype: only a suggestion.
					finding = Finding{
						...finding
						suggestions: [
							Suggestion{
								message_id: 'prefer-native-coercion-functions/suggestion'
								data:       data
								fix:        fix
							},
						]
					}
				} else {
					finding = Finding{
						...finding
						has_fix: has_fix
						fix:     fix
					}
				}
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
