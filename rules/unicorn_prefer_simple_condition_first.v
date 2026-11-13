module rules

import estree
import time

// Port of the `unicorn/prefer-simple-condition-first` rule of eslint-plugin-unicorn 64.0.0 (it has
// no options), with its fix and its suggestion.

const upscf_messages = {
	'prefer-simple-condition-first':            'Prefer simple condition first in `{{operator}}` expression.'
	'prefer-simple-condition-first/suggestion': 'Swap conditions.'
}

// upscf_simple_operand ports isSimpleOperand: an identifier, a literal, or `-1`/`+0`.
fn upscf_simple_operand(t &estree.EsTree, node int) bool {
	if t.typ(node) in [.identifier, .literal] {
		return true
	}
	if t.typ(node) != .unary_expression || (t.string_of(node, .operator) or { '' }) !in ['-', '+'] {
		return false
	}
	argument := t.node(node, .argument) or { return false }
	return t.typ(argument) == .literal && t.get(argument, .value) is f64
}

// upscf_simple ports isSimple: an identifier, its negation, an `===`/`!==` of simple operands with
// an identifier, or a chain of those.
fn upscf_simple(t &estree.EsTree, node int) bool {
	operator := t.string_of(node, .operator) or { '' }
	match t.typ(node) {
		.identifier {
			return true
		}
		.unary_expression {
			return operator == '!' && upscf_simple(t, t.node(node, .argument) or { return false })
		}
		.binary_expression {
			if operator !in ['===', '!=='] {
				return false
			}
			left := t.node(node, .left) or { return false }
			right := t.node(node, .right) or { return false }
			return upscf_simple_operand(t, left) && upscf_simple_operand(t, right)
				&& (t.typ(left) == .identifier || t.typ(right) == .identifier)
		}
		.logical_expression {
			return upscf_simple(t, t.node(node, .left) or { return false })
				&& upscf_simple(t, t.node(node, .right) or { return false })
		}
		else {
			return false
		}
	}
}

// upscf_side_effects_or_throws ports hasSideEffectsOrThrows: assignments, updates, tagged
// templates, `await`, `yield`, `import()`, member accesses, `in` and `instanceof`.
fn upscf_side_effects_or_throws(t &estree.EsTree, node int) bool {
	typ := t.typ(node)
	if typ in [.assignment_expression, .update_expression, .tagged_template_expression,
		.await_expression, .yield_expression, .import_expression, .member_expression] {
		return true
	}
	if typ == .binary_expression && (t.string_of(node, .operator) or { '' }) in ['in', 'instanceof'] {
		return true
	}
	return t.children(node).any(upscf_side_effects_or_throws(t, it))
}

// upscf_call_or_new ports hasCallOrNew.
fn upscf_call_or_new(t &estree.EsTree, node int) bool {
	return t.typ(node) in [.call_expression, .new_expression]
		|| t.children(node).any(upscf_call_or_new(t, it))
}

// upscf_boolean_context ports isBooleanContext: only the truthiness of the value is used.
fn upscf_boolean_context(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	match t.typ(parent) {
		.if_statement, .while_statement, .do_while_statement, .for_statement, .conditional_expression {
			return t.node(parent, .test) or { -1 } == node
		}
		.unary_expression {
			return (t.string_of(parent, .operator) or { '' }) == '!'
		}
		.logical_expression {
			return upscf_boolean_context(t, parent)
		}
		else {
			return false
		}
	}
}

// upscf_swap_text ports getSwapText.
fn (c &Checker) upscf_swap_text(t &estree.EsTree, tokens &SourceTokens, node int, operator string) string {
	parenthesized := c.un_is_parenthesized(t, tokens, node)
	mut text := if parenthesized {
		c.un_parenthesized_text(t, tokens, node)
	} else {
		c.un_text(t, node)
	}
	if !parenthesized && un_logical_child_needs_parens(t, node, operator) {
		text = '(${text})'
	}
	return text
}

fn (mut c Checker) lint_unicorn_prefer_simple_condition_first(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .logical_expression {
			continue
		}
		stats.checked++
		operator := t.string_of(node, .operator) or { continue }
		left := t.node(node, .left) or { continue }
		right := t.node(node, .right) or { continue }
		if operator !in ['&&', '||'] || !upscf_simple(t, right) || upscf_simple(t, left)
			|| t.typ(left) != .conditional_expression || !upscf_boolean_context(t, node)
			|| upscf_side_effects_or_throws(t, left) || upscf_call_or_new(t, left) {
			continue
		}
		right_text := c.upscf_swap_text(t, tokens, right, operator)
		left_text := c.upscf_swap_text(t, tokens, left, operator)
		start, _ := c.un_parenthesized_range(t, tokens, left)
		_, end := c.un_parenthesized_range(t, tokens, right)
		comments := tokens.comments_inside(t.nodes[left].end, t.nodes[right].start).len > 0
		fix := fix_replace_range(start, end, '${right_text} ${operator} ${left_text}')
		mut finding := Finding{
			stmt:       c.es_tree_position(t, right)
			message_id: 'prefer-simple-condition-first'
			data:       {
				'operator': operator
			}
		}
		// A chain gets a suggestion instead of a fix, so that fixes do not swap it back and forth.
		chain := t.typ(left) == .logical_expression
			&& (t.string_of(left, .operator) or { '' }) == operator
		if !comments && chain {
			finding = Finding{
				...finding
				suggestions: [
					Suggestion{
						message_id: 'prefer-simple-condition-first/suggestion'
						fix:        fix
					},
				]
			}
		} else if !comments {
			finding = Finding{
				...finding
				has_fix: true
				fix:     fix
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
