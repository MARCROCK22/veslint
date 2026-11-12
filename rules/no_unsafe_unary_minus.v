module rules

import time
import treesitter { node_field, nodes_of_kind, position_of }

// Port of the `no-unsafe-unary-minus` rule of typescript-eslint 8.62.0 (it has no options).

const nuum_messages = {
	'unaryMinus': 'Argument of unary negation should be assignable to number | bigint but is {{type}} instead.'
}

// nuum_allowed_flags are the TypeFlags a union part may have: Any | Never | BigIntLike | NumberLike.
const nuum_allowed_flags = type_flag_any | type_flag_never | type_flag_bigint_like | type_flag_number_like

fn (mut c Checker) lint_no_unsafe_unary_minus(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	// Every `UnaryExpression` with the `-` operator, also the ones of literal types (`type T = -1`).
	mut negations := []C.TSNode{}
	mut operands := []C.TSNode{}
	for node in c.nodes_of_kind(root, c'unary_expression') {
		if operator_of(node) != '-' {
			continue
		}
		argument := node_field(node, 'argument') or { continue }
		negations << node
		operands << unwrap_parens(argument)
	}
	c.resolve_spans(operands.map(node_span(it)), abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for i, node in negations {
		t := c.node_type(operands[i]) or { continue }
		argument_type := c.constrained(t)!
		// tsutils.unionConstituents and tsutils.isTypeFlagSet (the own flags of each part).
		mut negatable := true
		for part in c.constituents(argument_type)! {
			if part.flags & nuum_allowed_flags == 0 {
				negatable = false
				break
			}
		}
		if !negatable {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unaryMinus'
				data:       {
					'type': c.type_string(argument_type)!
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += negations.len
	return findings
}
