module rules

import json2
import time
import treesitter { node_end, node_field, node_kind, node_start, position_of }

// Port of the `no-unsafe-negation` rule of ESLint 10.6.0, with its option and its suggestions.

const nun_messages = {
	'unexpected':                   "Unexpected negating the left operand of '{{operator}}' operator."
	'suggestNegatedExpression':     "Negate '{{operator}}' expression instead of its left operand. This changes the current behavior."
	'suggestParenthesisedNegation': "Wrap negation in '()' to make the intention explicit. This preserves the current behavior."
}

// nun_options reads enforceForOrderingRelations.
fn nun_options(options []json2.Any) !bool {
	o := option_object(no_unsafe_negation, options, ['enforceForOrderingRelations'])!
	return o.bool_value('enforceForOrderingRelations')!
}

fn (mut c Checker) lint_no_unsafe_negation(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	ordering := nun_options(c.rule_options(no_unsafe_negation))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['binary_expression'], []) {
		stats.checked++
		operator := operator_of(node)
		if operator !in ['in', 'instanceof']
			&& !(ordering && operator in ['<', '>', '>=', '<=']) {
			continue
		}
		// The left operand is a negation that is not parenthesised (a parenthesized_expression is
		// one that is).
		left := node_field(node, 'left') or { continue }
		if node_kind(left) != 'unary_expression' {
			continue
		}
		negation := node_field(left, 'operator') or { continue }
		if c.text(negation) != '!' {
			continue
		}
		data := {
			'operator': operator
		}
		_, negated := c.suggestion('suggestNegatedExpression', data, [
			fix_replace_range(node_end(negation), node_end(node), '(${c.src[node_end(negation)..node_end(node)]})'),
		])!
		_, wrapped := c.suggestion('suggestParenthesisedNegation', map[string]string{}, [
			fix_replace(left, '(${c.src[node_start(left)..node_end(left)]})'),
		])!
		findings << Finding{
			stmt:        position_of(left)
			message_id:  'unexpected'
			data:        data
			suggestions: [negated, wrapped]
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
