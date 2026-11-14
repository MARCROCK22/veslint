module rules

import estree
import time

// Port of the `unicorn/error-message` rule of eslint-plugin-unicorn 79.0.0 (it has no options).

const uem_messages = {
	'missing-message':         'Pass a message to the `{{constructorName}}` constructor.'
	'message-is-empty-string': 'Error message should not be an empty string.'
	'message-is-not-a-string': 'Error message should be a string.'
}

// un_builtin_errors are the errors of unicorn's shared/builtin-errors.js.
const un_builtin_errors = ['Error', 'EvalError', 'RangeError', 'ReferenceError', 'SyntaxError',
	'TypeError', 'URIError', 'AggregateError', 'SuppressedError']

fn (mut c Checker) lint_unicorn_error_message(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) !in [.call_expression, .new_expression] {
			continue
		}
		stats.checked++
		if !un_is_call_or_new(t, node, names: un_builtin_errors, optional: false) {
			continue
		}
		callee := t.node(node, .callee) or { continue }
		if !c.es_is_global_reference(root, t.ts_node(callee) or { continue }) {
			continue
		}
		name := t.string_of(callee, .name) or { continue }
		index := match name {
			'AggregateError' { 1 }
			'SuppressedError' { 2 }
			else { 0 }
		}
		args := t.list(node, .arguments) or { []int{} }
		// A spread at or before the message.
		if args.len > 0 && args[..int_min(index + 1, args.len)].any(t.typ(it) == .spread_element) {
			continue
		}
		if index >= args.len {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'missing-message'
				data:       {
					'constructorName': name
				}
			}
			continue
		}
		message := args[index]
		// These can never be strings.
		if t.typ(message) in [.array_expression, .object_expression] {
			findings << Finding{
				stmt:       c.es_tree_position(t, message)
				message_id: 'message-is-not-a-string'
			}
			continue
		}
		result := c.uem_static_value(root, t, message) or { continue }
		if result.value.kind != .string_ {
			findings << Finding{
				stmt:       c.es_tree_position(t, message)
				message_id: 'message-is-not-a-string'
			}
		} else if result.value.units.len == 0 {
			findings << Finding{
				stmt:       c.es_tree_position(t, message)
				message_id: 'message-is-empty-string'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// uem_is_safe_object_freeze_argument ports isSafeObjectFreezeArgument: an object literal without
// mutable member reads, or a `const` of one that is not read elsewhere.
fn (mut c Checker) uem_is_safe_object_freeze_argument(root C.TSNode, t &estree.EsTree, node int) bool {
	if node < 0 {
		return false
	}
	mut visited := map[int]bool{}
	if t.typ(node) == .object_expression {
		return !c.unb_has_potentially_mutable_member_access(root, t, node, mut visited)
	}
	if t.typ(node) != .identifier {
		return false
	}
	v := c.unb_find_variable(root, t, node)
	def := c.unb_single_definition(root, v) or { return false }
	if !unb_is_simple_declarator(def) || def.parent_kind != 'const' {
		return false
	}
	init := c.es_index_of(t, def.init or { return false }) or { return false }
	if t.typ(init) != .object_expression
		|| c.unb_has_potentially_mutable_member_access(root, t, init, mut visited) {
		return false
	}
	tree := c.scope_tree(root)
	key := node_key(t.ts_node(node) or { return false })
	return tree.variables[v].references.all(tree.references[it].init
		|| node_key(tree.references[it].identifier) == key)
}

// uem_is_object_freeze_member ports isObjectFreezeMemberExpression: `Object.freeze({…}).x`, or a
// `const` of it.
fn (mut c Checker) uem_is_object_freeze_member(root C.TSNode, t &estree.EsTree, n int) bool {
	mut node := n
	if t.typ(node) == .identifier {
		_, init := c.unb_const_definition(root, t, node) or { return false }
		node = init
	}
	if t.typ(node) != .member_expression {
		return false
	}
	object := t.node(node, .object) or { return false }
	if t.typ(object) != .call_expression {
		return false
	}
	callee := t.node(object, .callee) or { return false }
	if t.typ(callee) != .member_expression || (t.flag(callee, .computed) or { false }) {
		return false
	}
	callee_object := t.node(callee, .object) or { return false }
	property := t.node(callee, .property) or { return false }
	if t.typ(callee_object) != .identifier || (t.string_of(callee_object, .name) or { '' }) != 'Object'
		|| t.typ(property) != .identifier || (t.string_of(property, .name) or { '' }) != 'freeze' {
		return false
	}
	args := t.list(object, .arguments) or { []int{} }
	return c.uem_is_safe_object_freeze_argument(root, t, if args.len > 0 { args[0] } else { -1 })
}

// uem_static_value ports getStaticValueForNode: a conditional or logical expression, or one with
// a member read that may change, is evaluated only when that is safe.
fn (mut c Checker) uem_static_value(root C.TSNode, t &estree.EsTree, node int) ?StaticValue {
	value_node := unb_unwrap_ts(t, node)
	is_branch := unb_is_branch_expression(t, value_node)
	mut visited := map[int]bool{}
	if is_branch || c.unb_has_potentially_mutable_member_access(root, t, value_node, mut visited) {
		if c.uem_is_object_freeze_member(root, t, value_node) {
			return unb_found(c.un_static_value(t, value_node))
		}
		return if is_branch {
			c.unb_static_value_for_control_flow(root, t, value_node)
		} else {
			c.unb_static_value_if_no_side_effects(root, t, value_node)
		}
	}
	return unb_found(c.un_static_value(t, value_node))
}
