module rules

import time

// Port of the `unicorn/error-message` rule of eslint-plugin-unicorn 64.0.0 (it has no options).

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
		result := c.get_static_value(t.ts_node(message) or { continue })
		if !result.found {
			continue
		}
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
