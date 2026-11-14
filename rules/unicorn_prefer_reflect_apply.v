module rules

import estree
import time

// Port of the `unicorn/prefer-reflect-apply` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fix.

const upra_messages = {
	'prefer-reflect-apply': 'Prefer `Reflect.apply()` over `Function#apply()`.'
}

fn (mut c Checker) lint_unicorn_prefer_reflect_apply(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !un_is_method_call(t, node, optional_call: false, optional_member: false) {
			continue
		}
		callee := t.node(node, .callee) or { continue }
		object := t.node(callee, .object) or { continue }
		if t.typ(object) in [.literal, .array_expression, .object_expression]
			|| un_static_string_value(t, object) != none {
			continue
		}
		arguments := t.list(node, .arguments) or { continue }
		mut replacement := c.upra_fix_direct_apply_call(t, tokens, node)
		if replacement == '' {
			replacement = c.upra_fix_function_prototype_call(t, tokens, node)
		}
		if replacement == '' {
			continue
		}
		target := if arguments.len == 2 { object } else { arguments[0] }
		mut preserved := []UnRange{}
		if t.typ(target) == .sequence_expression {
			start, end := c.un_parenthesized_range(t, tokens, target)
			preserved << UnRange{start, end}
		} else {
			preserved << un_range(t, target)
		}
		for argument in arguments[arguments.len - 2..] {
			preserved << un_range(t, argument)
		}
		// The call is rebuilt from retained inputs, so comments elsewhere would be dropped
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'prefer-reflect-apply'
		}
		if !un_would_remove_comments(tokens, t.nodes[node].start, t.nodes[node].end, preserved) {
			mut fixes := [fix_replace_range(t.nodes[node].start, t.nodes[node].end, replacement)]
			fixes << c.un_fix_space_around_keyword(t, tokens, node)
			has_fix, fix := c.merge_fixes(fixes) or { false, Fix{} }
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// upra_method_name ports getMethodName: the name of a member expression whose computed property
// is a static string.
fn upra_method_name(t &estree.EsTree, node int) ?string {
	if node < 0 || t.typ(node) != .member_expression {
		return none
	}
	property := t.node(node, .property)?
	if t.flag(node, .computed) or { false } {
		return un_static_string_value(t, property)
	}
	if t.typ(property) == .private_identifier {
		return none
	}
	return t.string_of(property, .name)
}

// upra_is_apply_signature ports isApplySignature: `(null|this, [...]|arguments)`.
fn (c &Checker) upra_is_apply_signature(t &estree.EsTree, argument1 int, argument2 int) bool {
	return (c.unb_is_null_literal(t, argument1) || t.typ(argument1) == .this_expression)
		&& (t.typ(argument2) == .array_expression || (t.typ(argument2) == .identifier
		&& (t.string_of(argument2, .name) or { '' }) == 'arguments'))
}

// upra_target_text ports getTargetText: a SequenceExpression keeps its parentheses.
fn (c &Checker) upra_target_text(t &estree.EsTree, tokens &SourceTokens, node int) string {
	if t.typ(node) == .sequence_expression {
		return c.un_parenthesized_text(t, tokens, node)
	}
	return c.src[t.nodes[node].start..t.nodes[node].end]
}

fn (c &Checker) upra_text(t &estree.EsTree, node int) string {
	return c.src[t.nodes[node].start..t.nodes[node].end]
}

// upra_fix_direct_apply_call ports fixDirectApplyCall: `foo.apply(null, [42])`; the text of the
// replacement, or '' without a fix.
fn (c &Checker) upra_fix_direct_apply_call(t &estree.EsTree, tokens &SourceTokens, node int) string {
	callee := t.node(node, .callee) or { return '' }
	arguments := t.list(node, .arguments) or { return '' }
	object := t.node(callee, .object) or { return '' }
	if (upra_method_name(t, callee) or { '' }) != 'apply' || arguments.len != 2
		|| t.typ(object) == .super || !c.upra_is_apply_signature(t, arguments[0], arguments[1])
		|| c.un_has_unparenthesized_optional_chain_element(t, tokens, object) {
		return ''
	}
	return 'Reflect.apply(${c.upra_target_text(t, tokens, object)}, ${c.upra_text(t, arguments[0])}, ${c.upra_text(t,
		arguments[1])})'
}

// upra_fix_function_prototype_call ports fixFunctionPrototypeCall:
// `Function.prototype.apply.call(foo, null, [42])`.
fn (c &Checker) upra_fix_function_prototype_call(t &estree.EsTree, tokens &SourceTokens, node int) string {
	callee := t.node(node, .callee) or { return '' }
	arguments := t.list(node, .arguments) or { return '' }
	apply := t.node(callee, .object) or { return '' }
	if (upra_method_name(t, callee) or { '' }) != 'call'
		|| (upra_method_name(t, apply) or { '' }) != 'apply' {
		return ''
	}
	prototype := t.node(apply, .object) or { return '' }
	if (upra_method_name(t, prototype) or { '' }) != 'prototype' {
		return ''
	}
	function := t.node(prototype, .object) or { return '' }
	if t.typ(function) != .identifier || (t.string_of(function, .name) or { '' }) != 'Function'
		|| arguments.len != 3 || !c.upra_is_apply_signature(t, arguments[1], arguments[2]) {
		return ''
	}
	return 'Reflect.apply(${c.upra_target_text(t, tokens, arguments[0])}, ${c.upra_text(t,
		arguments[1])}, ${c.upra_text(t, arguments[2])})'
}
