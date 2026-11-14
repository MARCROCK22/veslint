module rules

import estree
import time

// Port of the `no-throw-literal` rule of ESLint 10.15.0 (it has no options).

const ntl_messages = {
	'object': 'Expected an error object to be thrown.'
	'undef':  'Do not throw undefined.'
}

fn (mut c Checker) lint_no_throw_literal(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .throw_statement {
			continue
		}
		stats.checked++
		argument := t.node(node, .argument) or { continue }
		if !es_could_be_error(t, argument) {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'object'
			}
		} else if t.typ(argument) == .identifier {
			if (t.string_of(argument, .name) or { '' }) == 'undefined' {
				id := t.ts_node(argument) or { continue }
				if c.es_is_global_reference(root, id) {
					findings << Finding{
						stmt:       c.es_tree_position(t, node)
						message_id: 'undef'
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// es_could_be_error ports couldBeError of ESLint's ast-utils: whether the value of an expression
// may be an error object. TypeScript's wrappers (`as`, `!`…) are not looked through.
fn es_could_be_error(t &estree.EsTree, node int) bool {
	match t.typ(node) {
		.identifier, .call_expression, .new_expression, .member_expression,
		.tagged_template_expression, .yield_expression, .await_expression, .chain_expression {
			return true
		}
		.assignment_expression {
			operator := t.string_of(node, .operator) or { return false }
			right := t.node(node, .right) or { return false }
			if operator in ['=', '&&='] {
				return es_could_be_error(t, right)
			}
			if operator in ['||=', '??='] {
				left := t.node(node, .left) or { return false }
				return es_could_be_error(t, left) || es_could_be_error(t, right)
			}
			return false
		}
		.sequence_expression {
			expressions := t.list(node, .expressions) or { return false }
			return expressions.len != 0 && es_could_be_error(t, expressions.last())
		}
		.logical_expression {
			right := t.node(node, .right) or { return false }
			if (t.string_of(node, .operator) or { '' }) == '&&' {
				return es_could_be_error(t, right)
			}
			left := t.node(node, .left) or { return false }
			return es_could_be_error(t, left) || es_could_be_error(t, right)
		}
		.conditional_expression {
			consequent := t.node(node, .consequent) or { return false }
			alternate := t.node(node, .alternate) or { return false }
			return es_could_be_error(t, consequent) || es_could_be_error(t, alternate)
		}
		else {
			return false
		}
	}
}
