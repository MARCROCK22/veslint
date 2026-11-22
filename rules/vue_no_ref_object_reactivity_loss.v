module rules

import estree
import time

// Port of the `vue/no-ref-object-reactivity-loss` rule of eslint-plugin-vue 10.12.1 (no
// options): the `.value` of a ref object (or a destructuring of `value`) read in the same
// function scope (immediately invoked functions do not count) as the call that defines the ref.

const vue_no_ref_object_reactivity_loss_messages = {
	'getValueInSameScope': 'Getting a value from the ref object in the same scope will cause the value to lose reactivity.'
}

fn (mut c Checker) lint_vue_no_ref_object_reactivity_loss(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	refs := c.vx6r_extract(root, t)
	if refs.refs.len == 0 {
		return findings
	}
	mut order := []int{len: t.nodes.len, init: -1}
	mut next := 0
	for step in t.steps() {
		if !step.leave {
			order[step.node] = next
			next++
		}
	}
	for step in t.steps() {
		node := step.node
		if !step.leave {
			continue
		}
		mut target := -1
		if t.typ(node) == .member_expression {
			if vnrorl_is_update(t, node) || (vue_static_property_name(t, node) or { '' }) != 'value' {
				continue
			}
			target = t.node(node, .object) or { continue }
		} else if t.typ(node) == .object_pattern {
			if vue_find_assignment_property(t, node, 'value') < 0 {
				continue
			}
			target = node
		} else {
			continue
		}
		stats.checked++
		ref := refs.get(target) or { continue }
		define := ref.define
		// The define call was entered before this exit, in the same scope.
		entered := order[define] >= 0 && (order[define] < order[node]
			|| vx6_is_in_range(t, node, define))
		if !entered || vnrorl_scope(t, define) != vnrorl_scope(t, node) {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, target)
			message_id: 'getValueInSameScope'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnrorl_scope is the scope stack's node at `node`: its nearest function that is not immediately
// invoked, -1 for the Program.
fn vnrorl_scope(t &estree.EsTree, node int) int {
	mut n := t.nodes[node].parent
	for n >= 0 {
		if t.typ(n) in [.function_declaration, .function_expression, .arrow_function_expression]
			&& !vnrorl_is_iife(t, n) {
			return n
		}
		n = t.nodes[n].parent
	}
	return -1
}

// vnrorl_is_iife is isImmediatelyInvokedFunction.
fn vnrorl_is_iife(t &estree.EsTree, node int) bool {
	if t.typ(node) == .function_declaration || (t.flag(node, .async) or { false })
		|| (t.typ(node) == .function_expression && (t.flag(node, .generator) or { false })) {
		return false
	}
	parent := t.nodes[node].parent
	return parent >= 0 && t.typ(parent) == .call_expression
		&& (t.node(parent, .callee) or { -1 }) == node
}

// vnrorl_is_update is isUpdate.
fn vnrorl_is_update(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	match t.typ(parent) {
		.update_expression {
			return (t.node(parent, .argument) or { -1 }) == node
		}
		.assignment_expression {
			return (t.node(parent, .left) or { -1 }) == node
		}
		else {}
	}
	nested := match t.typ(parent) {
		.property { (t.node(parent, .value) or { -1 }) == node }
		.array_pattern, .rest_element { true }
		.object_pattern { node in (t.list(parent, .properties) or { []int{} }) }
		.assignment_pattern { (t.node(parent, .left) or { -1 }) == node }
		.member_expression { (t.node(parent, .object) or { -1 }) == node }
		else { false }
	}
	return nested && vnrorl_is_update(t, parent)
}
