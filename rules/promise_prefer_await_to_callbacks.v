module rules

import estree
import time

// Port of the `promise/prefer-await-to-callbacks` rule of eslint-plugin-promise 7.3.0 (it has no
// options).

const prm_prefer_await_to_callbacks_messages = {
	'error': 'Avoid callbacks. Prefer Async/Await.'
}

const prm_array_methods = ['map', 'every', 'forEach', 'some', 'find', 'filter']

// prm_is_inside_yield_or_await ports isInsideYieldOrAwait: an ancestor is an await or a yield.
fn prm_is_inside_yield_or_await(t &estree.EsTree, node int) bool {
	return prm_ancestors(t, node).any(t.typ(it) in [.await_expression, .yield_expression])
}

fn (mut c Checker) lint_promise_prefer_await_to_callbacks(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if !t.visits(node) {
			continue
		}
		match t.typ(node) {
			.call_expression {
				stats.checked++
				callee := prm_child(t, node, .callee)
				callee_name := prm_name(t, callee)
				if callee_name in ['cb', 'callback'] {
					findings << Finding{
						stmt:       c.es_tree_position(t, node)
						message_id: 'error'
					}
					continue
				}
				args := t.list(node, .arguments) or { []int{} }
				if args.len == 0 || !prm_is_function_expression(t, args.last()) {
					continue
				}
				arg := args.last()
				property := prm_child(t, callee, .property)
				property_name := prm_name(t, property)
				if property >= 0 && property_name in ['on', 'once'] {
					continue
				}
				is_lodash := prm_name(t, prm_child(t, callee, .object)) in ['lodash', 'underscore',
					'_']
				calls_array_method := property >= 0 && property_name in prm_array_methods
					&& (args.len == 1 || (args.len == 2 && is_lodash))
				is_array_method := callee_name in prm_array_methods && args.len == 2
				if calls_array_method || is_array_method {
					continue
				}
				if prm_first_param_name(t, arg) in ['err', 'error']
					&& !prm_is_inside_yield_or_await(t, node) {
					findings << Finding{
						stmt:       c.es_tree_position(t, arg)
						message_id: 'error'
					}
				}
			}
			.function_declaration, .function_expression, .arrow_function_expression {
				stats.checked++
				params := t.list(node, .params) or { []int{} }
				if params.len == 0 {
					continue
				}
				last := params.last()
				if prm_name(t, last) in ['callback', 'cb'] {
					findings << Finding{
						stmt:       c.es_tree_position(t, last)
						message_id: 'error'
					}
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
