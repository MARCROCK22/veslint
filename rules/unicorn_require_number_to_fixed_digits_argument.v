module rules

import time

// Port of the `unicorn/require-number-to-fixed-digits-argument` rule of eslint-plugin-unicorn
// 64.0.0 (it has no options), with its fix.

const urntfda_messages = {
	'require-number-to-fixed-digits-argument': 'Missing the digits argument.'
}

fn (mut c Checker) lint_unicorn_require_number_to_fixed_digits_argument(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !un_is_method_call(t, node, methods: ['toFixed'], arguments_length: 0, optional_call: false) {
			continue
		}
		object := t.node(t.node(node, .callee) or { continue }, .object) or { continue }
		if t.typ(object) == .new_expression {
			continue
		}
		inside := tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
		if inside.len < 2 {
			continue
		}
		opening := inside[inside.len - 2]
		closing := inside.last()
		findings << Finding{
			stmt:       c.position_range(opening.start, closing.end)
			message_id: 'require-number-to-fixed-digits-argument'
			has_fix:    true
			// appendArgument without arguments: the text goes before the `)`.
			fix:        fix_insert_at(closing.start, '0')
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
