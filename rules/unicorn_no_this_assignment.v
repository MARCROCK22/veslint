module rules

import time

// Port of the `unicorn/no-this-assignment` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options).

const unta_messages = {
	'no-this-assignment': 'Do not assign `this` to `{{name}}`.'
}

fn (mut c Checker) lint_unicorn_no_this_assignment(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		variable, value := match t.typ(node) {
			.variable_declarator { t.node(node, .id) or { continue }, t.node(node, .init) or { continue } }
			.assignment_expression { t.node(node, .left) or { continue }, t.node(node, .right) or { continue } }
			else { continue }
		}
		stats.checked++
		if t.typ(variable) != .identifier || t.typ(value) != .this_expression {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, t.nodes[value].parent)
			message_id: 'no-this-assignment'
			data:       {
				'name': t.string_of(variable, .name) or { '' }
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
