module rules

import time
import treesitter { node_field, node_kind, node_start }

// Port of the `no-useless-concat` rule of ESLint 10.6.0 (it has no options).

const nuconcat_messages = {
	'unexpectedConcat': 'Unexpected string concatenation of literals.'
}

fn (mut c Checker) lint_no_useless_concat(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	tokens := c.source_tokens(root)
	for node in c.nodes_of_kinds(root, ['binary_expression'], []) {
		if operator_of(node) != '+' {
			continue
		}
		stats.checked++
		// The operands next to the `+`: the right of a concatenation on the left, the left of
		// one on the right.
		mut left := unwrap_parens(node_field(node, 'left') or { continue })
		for node_kind(left) == 'binary_expression' && operator_of(left) == '+' {
			left = unwrap_parens(node_field(left, 'right') or { break })
		}
		mut right := unwrap_parens(node_field(node, 'right') or { continue })
		for node_kind(right) == 'binary_expression' && operator_of(right) == '+' {
			right = unwrap_parens(node_field(right, 'left') or { break })
		}
		if node_kind(left) !in ['string', 'template_string']
			|| node_kind(right) !in ['string', 'template_string'] {
			continue
		}
		if es_has_line_break(c.src[c.es_end(left)..node_start(right)]) {
			continue
		}
		mut operator := tokens.after(c.es_end(left), false) or { continue }
		for !(operator.kind == .punctuator && c.src[operator.start..operator.end] == '+') {
			operator = tokens.after(operator.end, false) or { break }
		}
		findings << Finding{
			stmt:       c.position_range(operator.start, operator.end)
			message_id: 'unexpectedConcat'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
