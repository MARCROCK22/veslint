module rules

import estree
import time

// Port of the `unicorn/prefer-simple-condition-first` rule of eslint-plugin-unicorn 79.0.0 (it has
// no options), with its fix.

const upscf_messages = {
	'prefer-simple-condition-first':        'Prefer this simple condition first in the `{{operator}}` expression.'
	'prefer-simple-condition-first/unsafe': 'Consider moving this simple condition first after verifying short-circuit behavior.'
}

// upscf_is_typeof_identifier ports isTypeofIdentifier: `typeof x`.
fn upscf_is_typeof_identifier(t &estree.EsTree, n int) bool {
	node := unb_unwrap_ts(t, n)
	return t.typ(node) == .unary_expression && (t.string_of(node, .operator) or { '' }) == 'typeof'
		&& t.typ(unb_unwrap_ts(t, t.node(node, .argument) or { return false })) == .identifier
}

fn upscf_is_identifier_or_typeof(t &estree.EsTree, n int) bool {
	node := unb_unwrap_ts(t, n)
	return t.typ(node) == .identifier || upscf_is_typeof_identifier(t, node)
}

// upscf_simple_operand ports isSimpleOperand: an identifier, `typeof` of one, a literal, a static
// string, or a signed number (`-1`, `+0`) or negative BigInt literal.
fn upscf_simple_operand(t &estree.EsTree, n int) bool {
	node := unb_unwrap_ts(t, n)
	if upscf_is_identifier_or_typeof(t, node) || t.typ(node) == .literal
		|| unb_has_static_string(t, node) {
		return true
	}
	operator := t.string_of(node, .operator) or { '' }
	if t.typ(node) != .unary_expression || operator !in ['-', '+'] {
		return false
	}
	argument := unb_unwrap_ts(t, t.node(node, .argument) or { return false })
	if t.typ(argument) != .literal {
		return false
	}
	value := t.get(argument, .value)
	return value is f64 || (operator == '-' && value is estree.BigIntValue)
}

// upscf_simple ports isSimple.
fn (c &Checker) upscf_simple(t &estree.EsTree, n int) bool {
	node := unb_unwrap_ts(t, n)
	operator := t.string_of(node, .operator) or { '' }
	match t.typ(node) {
		.identifier {
			return true
		}
		.unary_expression {
			return operator == '!' && c.upscf_simple(t, t.node(node, .argument) or { return false })
		}
		.binary_expression {
			left := unb_unwrap_ts(t, t.node(node, .left) or { return false })
			right := unb_unwrap_ts(t, t.node(node, .right) or { return false })
			if operator in ['==', '!='] {
				return (t.typ(left) == .identifier && c.unb_is_null_literal(t, right))
					|| (c.unb_is_null_literal(t, left) && t.typ(right) == .identifier)
					|| (upscf_is_typeof_identifier(t, left) && (unb_has_static_string(t, right)
					|| upscf_is_typeof_identifier(t, right)))
					|| (unb_has_static_string(t, left) && upscf_is_typeof_identifier(t, right))
			}
			return upscf_simple_operand(t, left) && upscf_simple_operand(t, right)
				&& operator in ['===', '!=='] && (upscf_is_identifier_or_typeof(t, left)
				|| upscf_is_identifier_or_typeof(t, right))
		}
		else {
			return false
		}
	}
}

// upscf_operands ports getLogicalOperands: the operands of the chain of `operator`, through
// TypeScript wrappers.
fn upscf_operands(t &estree.EsTree, node int, operator string, mut out []int) {
	unwrapped := unb_unwrap_ts(t, node)
	if t.typ(unwrapped) != .logical_expression
		|| (t.string_of(unwrapped, .operator) or { '' }) != operator {
		out << node
		return
	}
	upscf_operands(t, t.node(unwrapped, .left) or { return }, operator, mut out)
	upscf_operands(t, t.node(unwrapped, .right) or { return }, operator, mut out)
}

// upscf_is_typeof_guard ports isTypeofGuardForIdentifier: `typeof name !== 'undefined'` for `&&`,
// `typeof name === 'undefined'` for `||`.
fn upscf_is_typeof_guard(t &estree.EsTree, n int, name string, logical_operator string) bool {
	node := unb_unwrap_ts(t, n)
	guard_operators := if logical_operator == '&&' { ['!==', '!='] } else { ['===', '=='] }
	if t.typ(node) != .binary_expression || (t.string_of(node, .operator) or { '' }) !in guard_operators {
		return false
	}
	left := unb_unwrap_ts(t, t.node(node, .left) or { return false })
	right := unb_unwrap_ts(t, t.node(node, .right) or { return false })
	typeof_expression := if upscf_is_typeof_identifier(t, left) { left } else { right }
	undefined_literal := if typeof_expression == left { right } else { left }
	return upscf_is_typeof_identifier(t, typeof_expression)
		&& (unb_static_string_value(t, undefined_literal) or { '' }) == 'undefined'
		&& (t.string_of(unb_unwrap_ts(t, t.node(typeof_expression, .argument) or { return false }), .name) or {
		''
	}) == name
}

fn upscf_has_earlier_typeof_guard(t &estree.EsTree, operands []int, index int, logical_operator string) bool {
	identifier := unb_unwrap_ts(t, operands[index])
	if t.typ(identifier) != .identifier {
		return false
	}
	name := t.string_of(identifier, .name) or { return false }
	return operands[..index].any(upscf_is_typeof_guard(t, it, name, logical_operator))
}

fn (c &Checker) upscf_is_safe_conditional(t &estree.EsTree, n int) bool {
	node := unb_unwrap_ts(t, n)
	if t.typ(node) != .conditional_expression {
		return false
	}
	for key in [estree.Key.test, .consequent, .alternate] {
		child := t.node(node, key) or { return false }
		if !(c.upscf_simple(t, child) || upscf_simple_operand(t, child)
			|| c.upscf_is_safe_conditional(t, child)) {
			return false
		}
	}
	return true
}

fn (c &Checker) upscf_is_safe_to_move(t &estree.EsTree, node int) bool {
	return c.upscf_simple(t, node) || c.upscf_is_safe_conditional(t, node)
}

// upscf_has_ts_wrapped_logical ports hasTypeScriptWrappedLogicalExpression.
fn upscf_has_ts_wrapped_logical(t &estree.EsTree, node int, operator string) bool {
	if unb_is_ts_wrapper(t, node) {
		unwrapped := unb_unwrap_ts(t, node)
		return t.typ(unwrapped) == .logical_expression
			&& (t.string_of(unwrapped, .operator) or { '' }) == operator
	}
	return t.typ(node) == .logical_expression && (t.string_of(node, .operator) or { '' }) == operator
		&& (upscf_has_ts_wrapped_logical(t, t.node(node, .left) or { return false }, operator)
		|| upscf_has_ts_wrapped_logical(t, t.node(node, .right) or { return false }, operator))
}

// upscf_has_comments_that_prevent_fix ports hasCommentsThatPreventFix: a comment between the
// operands, or right before the first or right after the last.
fn (c &Checker) upscf_has_comments_that_prevent_fix(t &estree.EsTree, tokens &SourceTokens, node int, operands []int) bool {
	if c.unb_would_remove_comments(tokens, unb_node_range(t, node), operands.map(c.unb_parenthesized_range(t,
		tokens, it)), false) {
		return true
	}
	start := c.unb_parenthesized_range(t, tokens, operands[0]).start
	end := c.unb_parenthesized_range(t, tokens, operands.last()).end
	if before := tokens.before(start, true) {
		if before.is_comment() {
			return true
		}
	}
	if after := tokens.after(end, true) {
		if after.is_comment() {
			return true
		}
	}
	return false
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
		if operator !in ['&&', '||'] {
			continue
		}
		outermost := unb_outermost_ts(t, node)
		parent := t.nodes[outermost].parent
		if parent >= 0 && t.typ(parent) == .logical_expression
			&& (t.string_of(parent, .operator) or { '' }) == operator {
			continue
		}
		// The rule only reorders operands, so TypeScript wrappers around a boolean context keep
		// their type.
		if !c.unb_is_boolean_context(root, t, outermost) {
			continue
		}
		mut operands := []int{}
		upscf_operands(t, node, operator, mut operands)
		simple := operands.map(c.upscf_simple(t, it))
		first_complex := simple.index(false)
		if first_complex < 0 {
			continue
		}
		mut first_misplaced := -1
		for i, is_simple in simple {
			if is_simple && i > first_complex
				&& !upscf_has_earlier_typeof_guard(t, operands, i, operator) {
				first_misplaced = i
				break
			}
		}
		if first_misplaced < 0 {
			continue
		}
		mut reordered := []int{}
		for i, operand in operands {
			if simple[i] {
				reordered << operand
			}
		}
		for i, operand in operands {
			if !simple[i] {
				reordered << operand
			}
		}
		mut last_simple := -1
		for i, is_simple in simple {
			if is_simple {
				last_simple = i
			}
		}
		mut safe := true
		for i, operand in operands {
			if !(simple[i] || i > last_simple || c.upscf_is_safe_to_move(t, operand)) {
				safe = false
				break
			}
		}
		can_fix := safe && !upscf_has_ts_wrapped_logical(t, node, operator)
			&& !c.upscf_has_comments_that_prevent_fix(t, tokens, node, operands)
		mut finding := Finding{
			stmt:       c.es_tree_position(t, operands[first_misplaced])
			message_id: if safe {
				'prefer-simple-condition-first'
			} else {
				'prefer-simple-condition-first/unsafe'
			}
			data:       {
				'operator': operator
			}
		}
		if can_fix {
			text := reordered.map(c.unb_logical_child_text(t, tokens, it, operator)).join(' ${operator} ')
			has_fix, fix := c.merge_fixes([
				fix_replace_range(t.nodes[node].start, t.nodes[node].end, text),
			])!
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
