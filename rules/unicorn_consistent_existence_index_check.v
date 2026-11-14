module rules

import estree
import time

// Port of the `unicorn/consistent-existence-index-check` rule of eslint-plugin-unicorn 64.0.0 (it
// has no options), with its fix.

const uceic_messages = {
	'consistent-existence-index-check': 'Prefer `{{replacementOperator}} {{replacementValue}}` over `{{originalOperator}} {{originalValue}}` to check {{existenceOrNonExistence}}.'
}

fn un_is_numeric_literal_of(t &estree.EsTree, node int, number f64) bool {
	value := t.get(node, .value)
	return node >= 0 && t.typ(node) == .literal && value is f64 && value == number
}

// un_is_negative_one ports isNegativeOne: `-1`.
fn un_is_negative_one(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .unary_expression
		&& (t.string_of(node, .operator) or { '' }) == '-'
		&& un_is_numeric_literal_of(t, t.node(node, .argument) or { -1 }, 1)
}

// uceic_replacement ports getReplacement: the replacement operator and value, and the original
// operator and value.
fn uceic_replacement(t &estree.EsTree, binary int) ?(string, string, string, string) {
	operator := t.string_of(binary, .operator)?
	right := t.node(binary, .right)?
	if operator == '<' && un_is_numeric_literal_of(t, right, 0) {
		return '===', '-1', operator, '0'
	}
	if operator == '>' && un_is_negative_one(t, right) {
		return '!==', '-1', operator, '-1'
	}
	if operator == '>=' && un_is_numeric_literal_of(t, right, 0) {
		return '!==', '-1', operator, '0'
	}
	return none
}

fn (mut c Checker) lint_unicorn_consistent_existence_index_check(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .variable_declarator {
			continue
		}
		stats.checked++
		parent := t.nodes[node].parent
		id := t.node(node, .id) or { continue }
		if !(t.typ(parent) == .variable_declaration && (t.string_of(parent, .kind) or { '' }) == 'const'
			&& t.typ(id) == .identifier && un_is_method_call(t, t.node(node, .init) or { -1 },
			methods: ['indexOf', 'lastIndexOf', 'findIndex', 'findLastIndex']
		)) {
			continue
		}
		tree := c.scope_tree(root)
		v := tree.declared_variable(t.ts_node(id) or { continue })
		// Just for safety
		if v < 0 || tree.variables[v].identifiers.len != 1 {
			continue
		}
		for r in tree.variables[v].references {
			identifier := c.es_index_of(t, tree.references[r].identifier) or { continue }
			binary := t.nodes[identifier].parent
			if binary < 0 || t.typ(binary) != .binary_expression || t.node(binary, .left) or { -1 } != identifier {
				continue
			}
			// The first comparison that has no replacement ends the checks of the variable.
			replacement_operator, replacement_value, original_operator, original_value := uceic_replacement(t,
				binary) or { break }
			right := t.node(binary, .right) or { break }
			operator_token := c.un_token_after_punctuator(tokens, t.nodes[identifier].end, original_operator) or {
				break
			}
			mut fixes := [
				fix_replace_range(operator_token.start, operator_token.end, replacement_operator),
			]
			if replacement_value != original_value {
				fixes << fix_replace_range(t.nodes[right].start, t.nodes[right].end, replacement_value)
			}
			has_fix, fix := c.merge_fixes(fixes)!
			findings << Finding{
				stmt:       c.position_range(operator_token.start, t.nodes[right].end)
				message_id: 'consistent-existence-index-check'
				data:       {
					'replacementOperator':     replacement_operator
					'replacementValue':        replacement_value
					'originalOperator':        original_operator
					'originalValue':           original_value
					'existenceOrNonExistence': '${if replacement_operator == '===' { 'non-' } else { '' }}existence'
				}
				has_fix:    has_fix
				fix:        fix
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
