module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `prefer-spread` rule of ESLint 10.6.0 (it has no options).

const psp_messages = {
	'preferSpread': "Use the spread operator instead of '.apply()'."
}

fn (mut c Checker) lint_prefer_spread(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['call_expression'], []) {
		args := (call_arguments(node) or { continue }).filter(node_kind(it) != 'comment')
		callee := unwrap_parens(node_field(node, 'function') or { continue })
		if !c.es_is_specific_member_access(callee, '', 'apply') || args.len != 2
			|| node_kind(unwrap_parens(args[1])) in ['array', 'spread_element'] {
			continue
		}
		stats.checked++
		applied := unwrap_parens(node_field(callee, 'object') or { continue })
		if c.es_valid_this_arg(applied, args[0]) {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'preferSpread'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
