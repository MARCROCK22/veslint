module rules

import time

// Port of the `unicorn/no-useless-switch-case` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its suggestion.

const unusc_messages = {
	'no-useless-switch-case/error':      'Useless case in switch statement.'
	'no-useless-switch-case/suggestion': 'Remove this case.'
}

fn (mut c Checker) lint_unicorn_no_useless_switch_case(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .switch_statement {
			continue
		}
		stats.checked++
		cases := t.list(node, .cases) or { continue }
		// Only when the last case is `default`.
		if cases.len < 2 || t.node(cases.last(), .test) != none {
			continue
		}
		for index := cases.len - 2; index >= 0; index-- {
			item := cases[index]
			if !(t.list(item, .consequent) or { []int{} }).all(un_is_empty_node(t, it)) {
				break
			}
			findings << Finding{
				stmt:        c.un_switch_case_head(t, tokens, item) or { continue }
				message_id:  'no-useless-switch-case/error'
				suggestions: [
					Suggestion{
						message_id: 'no-useless-switch-case/suggestion'
						fix:        fix_remove_range(t.nodes[item].start, t.nodes[item].end)
					},
				]
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
