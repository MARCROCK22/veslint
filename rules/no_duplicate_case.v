module rules

import time
import treesitter { named_children, node_field, node_kind, position_of }

// Port of the `no-duplicate-case` rule of ESLint 10.6.0 (it has no options).

const ndc_messages = {
	'unexpected': 'Duplicate case label.'
}

fn (mut c Checker) lint_no_duplicate_case(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['switch_statement'], []) {
		body := node_field(node, 'body') or { continue }
		stats.checked++
		mut previous := []C.TSNode{}
		for switch_case in named_children(body) {
			if node_kind(switch_case) != 'switch_case' {
				continue
			}
			test := unwrap_parens(node_field(switch_case, 'value') or { continue })
			mut duplicate := false
			for earlier in previous {
				// equal: the same ESTree type and the same tokens.
				if estree_type(earlier) == estree_type(test) && c.es_equal_tokens(earlier, test) {
					duplicate = true
					break
				}
			}
			if duplicate {
				findings << Finding{
					stmt:       position_of(switch_case)
					message_id: 'unexpected'
				}
			} else {
				previous << test
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
