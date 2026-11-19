module rules

import estree
import json2
import time

// Port of the `promise/no-return-wrap` rule of eslint-plugin-promise 7.3.0, with its options.

const prm_no_return_wrap_messages = {
	'resolve': 'Avoid wrapping return values in Promise.resolve'
	'reject':  'Expected throw instead of Promise.reject'
}

fn prm_no_return_wrap_options(options []json2.Any) !bool {
	o := option_object(promise_no_return_wrap, options, ['allowReject'])!
	return o.bool_value('allowReject')!
}

// prm_is_in_promise ports isInPromise: the closest function expression around the node (through
// the `.bind(…)` calls made on it) is an argument of a promise call.
fn prm_is_in_promise(t &estree.EsTree, node int) bool {
	ancestors := prm_ancestors(t, node).filter(prm_is_function_expression(t, it))
	if ancestors.len == 0 {
		return false
	}
	mut function := ancestors.last()
	for {
		parent := t.nodes[function].parent
		if parent < 0 || t.typ(parent) != .member_expression || prm_child(t, parent, .object) != function {
			break
		}
		property := prm_child(t, parent, .property)
		if t.typ(property) != .identifier || prm_name(t, property) != 'bind' {
			break
		}
		call := t.nodes[parent].parent
		if call < 0 || t.typ(call) != .call_expression || prm_child(t, call, .callee) != parent {
			break
		}
		function = call
	}
	parent := t.nodes[function].parent
	return parent >= 0 && prm_is_promise(t, parent)
}

fn (mut c Checker) lint_promise_no_return_wrap(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	allow_reject := prm_no_return_wrap_options(c.rule_options(promise_no_return_wrap))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		mut call := -1
		if t.typ(node) == .return_statement {
			argument := prm_child(t, node, .argument)
			if argument >= 0 && t.typ(argument) == .call_expression {
				call = argument
			}
		} else if t.typ(node) == .call_expression {
			// 'ArrowFunctionExpression > CallExpression'
			parent := t.nodes[node].parent
			if parent >= 0 && t.typ(parent) == .arrow_function_expression {
				call = node
			}
		}
		if call < 0 {
			continue
		}
		stats.checked++
		callee := prm_child(t, call, .callee)
		if !prm_is_in_promise(t, node) || t.typ(callee) != .member_expression
			|| prm_name(t, prm_child(t, callee, .object)) != 'Promise' {
			continue
		}
		name := prm_name(t, prm_child(t, callee, .property))
		if name == 'resolve' {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'resolve'
			}
		} else if !allow_reject && name == 'reject' {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'reject'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
