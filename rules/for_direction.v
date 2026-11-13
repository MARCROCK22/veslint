module rules

import math
import time
import treesitter { named_children, node_end, node_field, node_kind, node_start, position_of }

// Port of the `for-direction` rule of ESLint 10.6.0 (it has no options).

const fd_messages = {
	'incorrectDirection': 'The update clause in this loop moves the variable in the wrong direction.'
}

fn (mut c Checker) lint_for_direction(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['for_statement'], []) {
		test_field := node_field(node, 'condition') or { continue }
		if node_kind(test_field) in [';', 'empty_statement'] {
			continue
		}
		test := unwrap_parens(test_field)
		update := node_field(node, 'increment') or { continue }
		if estree_binary_kind(test) != 'BinaryExpression' {
			continue
		}
		stats.checked++
		operator := operator_of(test)
		if operator !in ['<', '<=', '>', '>='] {
			continue
		}
		for position in ['left', 'right'] {
			side := unwrap_parens(node_field(test, position) or { continue })
			if node_kind(side) !in ['identifier', 'undefined'] {
				continue
			}
			counter := c.identifier_name(side)
			wrong := if operator in ['<', '<='] {
				if position == 'left' { -1 } else { 1 }
			} else {
				if position == 'left' { 1 } else { -1 }
			}
			mut mutating := []C.TSNode{}
			c.fd_modifying(update, counter, mut mutating)
			if mutating.len == 1 && c.fd_direction(mutating[0], counter) == wrong {
				// From the `for` to the token before the body (its `)`).
				body := node_field(node, 'body') or { node }
				before := c.source_tokens(node).before(node_start(body), false) or {
					SourceToken{
						end: node_end(node)
					}
				}
				findings << Finding{
					stmt:       c.position_range(node_start(node), before.end)
					message_id: 'incorrectDirection'
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// fd_is_counter: an Identifier named `counter`.
fn (c &Checker) fd_is_counter(n C.TSNode, counter string) bool {
	node := unwrap_parens(n)
	return node_kind(node) in ['identifier', 'undefined'] && c.identifier_name(node) == counter
}

// fd_modifying ports getModifyingExpressions: the updates and assignments of the counter in the
// update clause and in its sequences.
fn (c &Checker) fd_modifying(n C.TSNode, counter string, mut out []C.TSNode) {
	node := unwrap_parens(n)
	match node_kind(node) {
		'sequence_expression' {
			for child in named_children(node).filter(node_kind(it) != 'comment') {
				c.fd_modifying(child, counter, mut out)
			}
		}
		'update_expression' {
			if c.fd_is_counter(node_field(node, 'argument') or { return }, counter) {
				out << node
			}
		}
		'assignment_expression', 'augmented_assignment_expression' {
			left := node_field(node, 'left') or { return }
			// A parenthesised left side is the Identifier too.
			if c.fd_is_counter(left, counter) {
				out << node
			}
		}
		else {}
	}
}

// fd_direction ports getDirectionFromExpression: 1 when the expression increases the counter, -1
// when it decreases it, 0 when it is not known.
fn (mut c Checker) fd_direction(n C.TSNode, counter string) int {
	if node_kind(n) == 'update_expression' {
		operator := operator_of(n)
		return if operator == '++' {
			1
		} else if operator == '--' {
			-1
		} else {
			0
		}
	}
	operator := operator_of(n)
	if operator !in ['+=', '-='] {
		return 0
	}
	dir := if operator == '+=' { 1 } else { -1 }
	right := node_field(n, 'right') or { return 0 }
	value := c.get_static_value(right)
	if !value.found {
		return 0
	}
	sign := match value.value.kind {
		.number_ {
			x := value.value.number
			if math.is_nan(x) || x == 0 {
				0
			} else if x > 0 {
				1
			} else {
				-1
			}
		}
		.boolean_ {
			if value.value.boolean { 1 } else { 0 }
		}
		.bigint_ {
			digits := value.value.digits
			if digits.starts_with('-') {
				-1
			} else if digits.trim_left('0') == '' {
				0
			} else {
				1
			}
		}
		else {
			0
		}
	}
	return dir * sign
}
