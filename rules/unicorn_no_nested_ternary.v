module rules

import time

// Port of the `unicorn/no-nested-ternary` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fix.

const unnt_messages = {
	'too-deep':             'Do not nest ternary expressions.'
	'should-parenthesized': 'Nested ternary expression should be parenthesized.'
}

fn (mut c Checker) lint_unicorn_no_nested_ternary(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .conditional_expression {
			continue
		}
		stats.checked++
		if t.children(node).any(t.typ(it) == .conditional_expression) {
			continue
		}
		// The ancestors, the closest first, up to the first that is not a conditional.
		mut ancestors := []int{}
		mut nest_level := 0
		for ancestor := t.nodes[node].parent; ancestor >= 0; ancestor = t.nodes[ancestor].parent {
			ancestors << ancestor
			if t.typ(ancestor) != .conditional_expression {
				break
			}
			nest_level++
		}
		if nest_level == 1 && !c.un_is_parenthesized(t, tokens, node) {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'should-parenthesized'
				has_fix:    true
				fix:        fix_replace_range(t.nodes[node].start, t.nodes[node].end, '(' +
					c.src[t.nodes[node].start..t.nodes[node].end] + ')')
			}
		} else if nest_level > 1 {
			reported := if nest_level > 2 { ancestors[nest_level - 3] } else { node }
			findings << Finding{
				stmt:       c.es_tree_position(t, reported)
				message_id: 'too-deep'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
