module rules

import estree
import time

// Port of the `no-negated-condition` rule of ESLint 10.15.0 (it has no options).

const nnc_messages = {
	'unexpectedNegated': 'Unexpected negated condition.'
}

fn (mut c Checker) lint_no_negated_condition(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		typ := t.typ(node)
		if typ !in [.if_statement, .conditional_expression] {
			continue
		}
		stats.checked++
		// hasElseWithoutCondition
		if typ == .if_statement {
			alternate := t.node(node, .alternate) or { continue }
			if t.typ(alternate) == .if_statement {
				continue
			}
		}
		test := t.node(node, .test) or { continue }
		if !nnc_is_negated(t, test) {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'unexpectedNegated'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nnc_is_negated ports isNegatedIf: the test is `!a`, `a != b` or `a !== b`.
fn nnc_is_negated(t &estree.EsTree, test int) bool {
	operator := t.string_of(test, .operator) or { return false }
	return (t.typ(test) == .unary_expression && operator == '!')
		|| (t.typ(test) == .binary_expression && operator in ['!=', '!=='])
}
