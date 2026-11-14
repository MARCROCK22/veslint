module rules

import time

// Port of the `unicorn/no-console-spaces` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fix.

const uncs_messages = {
	'no-console-spaces': 'Do not use {{position}} space between `console.{{method}}` parameters.'
}

fn (mut c Checker) lint_unicorn_no_console_spaces(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !un_is_method_call(t, node,
			objects:           ['console']
			methods:           ['log', 'debug', 'info', 'warn', 'error']
			minimum_arguments: 1
			optional_call:     false
			optional_member:   false
		) {
			continue
		}
		method := t.string_of(t.node(t.node(node, .callee) or { continue }, .property) or {
			continue
		}, .name) or { continue }
		args := t.list(node, .arguments) or { continue }
		for index, argument in args {
			if !un_is_string_literal(t, argument) && t.typ(argument) != .template_literal {
				continue
			}
			raw := c.un_text(t, argument)
			value := raw[1..raw.len - 1]
			// Exactly one leading or trailing space.
			if index != 0 && value.len > 1 && value[0] == ` ` && value[1] != ` ` {
				findings << c.uncs_problem(t.nodes[argument].start + 1, method, 'leading')
			}
			if index != args.len - 1 && value.len > 1 && value[value.len - 1] == ` `
				&& value[value.len - 2] != ` ` {
				findings << c.uncs_problem(t.nodes[argument].end - 2, method, 'trailing')
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) uncs_problem(index int, method string, position string) Finding {
	return Finding{
		stmt:       c.position_range(index, index + 1)
		message_id: 'no-console-spaces'
		data:       {
			'method':   method
			'position': position
		}
		has_fix:    true
		fix:        fix_remove_range(index, index + 1)
	}
}
