module rules

import time

// Port of the `@stylistic/no-floating-decimal` rule of @stylistic/eslint-plugin 6.0.1, with its
// fixes.

const snfd_messages = {
	'leading':  'A leading decimal point can be confused with a dot.'
	'trailing': 'A trailing decimal point can be confused with a dot.'
}

fn (mut c Checker) lint_stylistic_no_floating_decimal(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		node := step.node
		if step.leave || t.typ(node) != .literal {
			continue
		}
		value := t.get(node, .value)
		if value !is f64 {
			continue
		}
		stats.checked++
		start := t.nodes[node].start
		end := t.nodes[node].end
		raw := c.src[start..end]
		if raw.starts_with('.') {
			// canTokensBeAdjacent(tokenBefore, `0${node.raw}`): espree tokenizes the right side as a
			// Numeric token, or fails (a BigInt with a decimal point).
			mut needs_space_before := false
			if token_before := tokens.before(start, false) {
				if token_before.end == start {
					right := '0${raw}'
					needs_space_before = raw.ends_with('n')
						|| !es_can_adjacent(token_before.kind, c.token_text(token_before), .numeric, right)
				}
			}
			findings << Finding{
				stmt:       c.position_range(start, end)
				message_id: 'leading'
				has_fix:    true
				fix:        fix_insert_at(start, if needs_space_before { ' 0' } else { '0' })
			}
		}
		if raw.index_u8(`.`) == raw.len - 1 {
			findings << Finding{
				stmt:       c.position_range(start, end)
				message_id: 'trailing'
				has_fix:    true
				fix:        fix_insert_at(end, '0')
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
