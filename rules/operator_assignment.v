module rules

import json2
import time
import treesitter { node_field, node_kind, node_start, position_of }

// Port of the `operator-assignment` rule of ESLint 10.6.0, with its option and its fixes.

const oa_messages = {
	'replaced':   'Assignment (=) can be replaced with operator assignment ({{operator}}).'
	'unexpected': 'Unexpected operator assignment ({{operator}}) shorthand.'
}

const oa_commutative = ['*', '&', '^', '|']
const oa_non_commutative = ['+', '-', '/', '%', '<<', '>>', '>>>', '**']

// oa_never reads "always" or "never".
fn oa_never(options []json2.Any) !bool {
	option := if options.len > 0 { options[0] } else { json2.Any('always') }
	if option is string && option in ['always', 'never'] {
		return option == 'never'
	}
	return error('the option of `${operator_assignment}` must be "always" or "never"')
}

fn (mut c Checker) lint_operator_assignment(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	never := oa_never(c.rule_options(operator_assignment))!
	mut findings := []Finding{}
	kinds := if never { ['augmented_assignment_expression'] } else { ['assignment_expression'] }
	for node in c.nodes_of_kinds(root, kinds, []) {
		stats.checked++
		if never {
			c.oa_prohibit(root, node, mut findings)
		} else {
			c.oa_verify(root, node, mut findings)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// oa_can_be_fixed ports canBeFixed: an identifier, or a member of an identifier or `this` with a
// name or a literal key.
fn oa_can_be_fixed(n C.TSNode) bool {
	node := unwrap_parens(n)
	match node_kind(node) {
		'identifier', 'undefined' {
			return true
		}
		'member_expression', 'subscript_expression' {
			// Not an optional chain, which is a ChainExpression.
			if estree_type(node) != 'MemberExpression' {
				return false
			}
			object := unwrap_parens(node_field(node, 'object') or { return false })
			if node_kind(object) !in ['identifier', 'undefined', 'this'] {
				return false
			}
			if node_kind(node) == 'subscript_expression' {
				return es_is_literal(unwrap_parens(node_field(node, 'index') or { return false }))
			}
			return true
		}
		else {
			return false
		}
	}
}

// oa_operator_token is the token of the operator between the two sides.
fn (mut c Checker) oa_operator_token(root C.TSNode, left C.TSNode, operator string) ?SourceToken {
	tokens := c.source_tokens(root)
	mut token := tokens.after(c.es_end(unwrap_parens(left)), false)?
	for c.src[token.start..token.end] != operator {
		token = tokens.after(token.end, false)?
	}
	return token
}

fn (mut c Checker) oa_verify(root C.TSNode, node C.TSNode, mut findings []Finding) {
	left := node_field(node, 'left') or { return }
	expr := unwrap_parens(node_field(node, 'right') or { return })
	if estree_binary_kind(expr) != 'BinaryExpression' {
		return
	}
	operator := operator_of(expr)
	if operator !in oa_commutative && operator !in oa_non_commutative {
		return
	}
	replacement := '${operator}='
	expr_left := node_field(expr, 'left') or { return }
	expr_right := node_field(expr, 'right') or { return }
	data := {
		'operator': replacement
	}
	if c.es_is_same_reference(left, expr_left, true) {
		mut has_fix := false
		mut fix := Fix{}
		if oa_can_be_fixed(left) && oa_can_be_fixed(expr_left) {
			equals := c.oa_operator_token(root, left, '=') or { return }
			operator_token := c.oa_operator_token(root, expr_left, operator) or { return }
			tokens := c.source_tokens(root)
			if !tokens.comments_exist_between(equals.end, operator_token.start) {
				left_text := c.src[node_start(node)..equals.start]
				right_text := c.src[operator_token.end..c.es_end(expr)]
				has_fix = true
				fix = fix_replace_range(node_start(node), c.es_end(node), left_text + replacement +
					right_text)
			}
		}
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'replaced'
			data:       data
			has_fix:    has_fix
			fix:        fix
		}
	} else if c.es_is_same_reference(left, expr_right, true) && operator in oa_commutative {
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'replaced'
			data:       data
		}
	}
}

fn (mut c Checker) oa_prohibit(root C.TSNode, node C.TSNode, mut findings []Finding) {
	operator := operator_of(node)
	if operator in ['&&=', '||=', '??='] {
		return
	}
	left := node_field(node, 'left') or { return }
	right := node_field(node, 'right') or { return }
	mut has_fix := false
	mut fix := Fix{}
	if oa_can_be_fixed(left) {
		tokens := c.source_tokens(root)
		first := tokens.after(node_start(node), false) or { return }
		operator_token := c.oa_operator_token(root, left, operator) or { return }
		if !tokens.comments_exist_between(first.end, operator_token.start) {
			left_text := c.src[node_start(node)..operator_token.start]
			new_operator := operator[..operator.len - 1]
			value := unwrap_parens(right)
			mut right_text := ''
			if es_precedence(value) <= es_binary_precedence(new_operator)
				&& !c.es_is_parenthesised(value) {
				right_text = '${c.src[operator_token.end..node_start(value)]}(${c.es_text(value)})'
			} else {
				after := tokens.after(operator_token.end, true) or { return }
				mut prefix := ''
				if operator_token.end == after.start
					&& !es_can_adjacent(.punctuator, new_operator, after.kind, c.src[after.start..after.end]) {
					prefix = ' '
				}
				right_text = prefix + c.src[operator_token.end..c.es_end(node)]
			}
			has_fix = true
			fix = fix_replace_range(node_start(node), c.es_end(node), '${left_text}= ${left_text}${new_operator}${right_text}')
		}
	}
	findings << Finding{
		stmt:       position_of(node)
		message_id: 'unexpected'
		data:       {
			'operator': operator
		}
		has_fix:    has_fix
		fix:        fix
	}
}
