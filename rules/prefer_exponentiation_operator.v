module rules

import time
import treesitter { node_field, node_kind, node_start, position_of }

// Port of the `prefer-exponentiation-operator` rule of ESLint 10.6.0, with its fix (it has no
// options).

const peo_messages = {
	'useExponentiation': "Use the '**' operator instead of 'Math.pow'."
}

fn (mut c Checker) lint_prefer_exponentiation_operator(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	trace := {
		'Math': EsTrace{
			children: {
				'pow': EsTrace{
					call: true
				}
			}
		}
	}
	for traced in c.es_global_references(root, trace) {
		stats.checked++
		has_fix, fix := c.peo_fix(root, traced.node)
		findings << Finding{
			stmt:       position_of(traced.node)
			message_id: 'useExponentiation'
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// peo_fix writes `base**exponent`, with the parentheses each part and the whole need.
fn (mut c Checker) peo_fix(root C.TSNode, call C.TSNode) (bool, Fix) {
	args := (call_arguments(call) or { return false, Fix{} }).filter(node_kind(it) != 'comment')
	tokens := c.source_tokens(root)
	end := c.es_end(call)
	if args.len != 2 || args.any(node_kind(it) == 'spread_element')
		|| tokens.comments_inside(node_start(call), end).len > 0 {
		return false, Fix{}
	}
	base := unwrap_parens(args[0])
	exponent := unwrap_parens(args[1])
	base_parens := es_precedence(base) <= 15 || node_kind(base) in ['await_expression',
		'unary_expression']
	exponent_parens := es_precedence(exponent) < 15
	at_statement_start := is_start_of_expression_statement(call)
	mut all_parens := c.peo_needs_parens(call)
	if !all_parens && !base_parens && at_statement_start {
		first := tokens.after(node_start(base), false) or { return false, Fix{} }
		text := c.src[first.start..first.end]
		if text == '{' || (first.kind == .keyword && text in ['function', 'class']) {
			all_parens = true
		}
	}
	mut prefix := ''
	mut suffix := ''
	if !all_parens {
		if !base_parens {
			first := tokens.after(node_start(base), false) or { return false, Fix{} }
			if before := tokens.before(node_start(call), false) {
				if before.end == node_start(call) && !c.es_can_tokens_be_adjacent(before, first) {
					prefix = ' '
				}
			}
		}
		if !exponent_parens {
			last := tokens.before(c.es_end(exponent), false) or { return false, Fix{} }
			if after := tokens.after(end, false) {
				if end == after.start && !c.es_can_tokens_be_adjacent(last, after) {
					suffix = ' '
				}
			}
		}
	}
	base_text := if base_parens { '(${c.es_text(base)})' } else { c.es_text(base) }
	exponent_text := if exponent_parens {
		'(${c.es_text(exponent)})'
	} else {
		c.es_text(exponent)
	}
	mut replacement := '${base_text}**${exponent_text}'
	if all_parens {
		replacement = '(${replacement})'
	}
	if prefix == '' && at_statement_start && replacement[0] in [`(`, `[`, `/`, `\``]
		&& c.eslint_needs_preceding_semicolon(call, node_start(call)) {
		prefix = ';'
	}
	return true, fix_replace_range(node_start(call), end, prefix + replacement + suffix)
}

// peo_needs_parens ports doesExponentiationExpressionNeedParens: the parent binds stronger than
// `**`, except where the expression is an operand on its own.
fn (mut c Checker) peo_needs_parens(call C.TSNode) bool {
	parent := cti_estree_parent(call) or { return false }
	key := node_key(call)
	mut needs := false
	kind := node_kind(parent)
	if kind == 'arguments' {
		// An argument of a call or a `new`.
		return false
	}
	if kind == 'extends_clause' {
		// The superclass of a ClassDeclaration or a ClassExpression.
		needs = true
	} else if peo_is_expression(parent) {
		precedence := es_precedence(parent)
		needs = precedence == -1 || precedence >= 15
		if kind == 'binary_expression' && operator_of(parent) == '**' {
			right := node_field(parent, 'right') or { parent }
			if node_key(unwrap_parens(right)) == key {
				needs = false
			}
		}
		if kind == 'subscript_expression' {
			index := node_field(parent, 'index') or { parent }
			if node_key(unwrap_parens(index)) == key {
				needs = false
			}
		}
		if kind == 'array' {
			needs = false
		}
	}
	return needs && !c.es_is_parenthesised(call)
}

// peo_is_expression: the ESTree type of the node ends with "Expression".
fn peo_is_expression(n C.TSNode) bool {
	return node_kind(n) in ['binary_expression', 'unary_expression', 'update_expression',
		'await_expression', 'yield_expression', 'call_expression', 'new_expression', 'member_expression',
		'subscript_expression', 'ternary_expression', 'assignment_expression',
		'augmented_assignment_expression', 'sequence_expression', 'arrow_function',
		'function_expression', 'generator_function', 'class', 'array', 'object', 'as_expression',
		'satisfies_expression', 'non_null_expression', 'type_assertion', 'instantiation_expression']
}
