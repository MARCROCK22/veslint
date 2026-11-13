module rules

import json2
import time
import treesitter { node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-extra-boolean-cast` rule of ESLint 10.6.0, with its options and its fixes.

const nebc_messages = {
	'unexpectedCall':     'Redundant Boolean call.'
	'unexpectedNegation': 'Redundant double negation.'
}

struct NebcOptions {
	logical_operands  bool
	inner_expressions bool
}

// nebc_options reads enforceForLogicalOperands or enforceForInnerExpressions.
fn nebc_options(options []json2.Any) !NebcOptions {
	o := option_object(no_extra_boolean_cast, options, ['enforceForLogicalOperands',
		'enforceForInnerExpressions'])!
	return NebcOptions{
		logical_operands:  o.bool_value('enforceForLogicalOperands') or { false }
		inner_expressions: o.bool_value('enforceForInnerExpressions') or { false }
	}
}

fn (mut c Checker) lint_no_extra_boolean_cast(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nebc_options(c.rule_options(no_extra_boolean_cast))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['unary_expression', 'call_expression'], []) {
		stats.checked++
		if node_kind(node) == 'unary_expression' {
			if operator_of(node) != '!' {
				continue
			}
			parent := cti_estree_parent(node) or { continue }
			if node_kind(parent) != 'unary_expression' || operator_of(parent) != '!' {
				continue
			}
			if !c.nebc_flagged(root, o, parent) {
				continue
			}
			argument := unwrap_parens(node_field(node, 'argument') or { continue })
			has_fix, fix := c.nebc_negation_fix(root, parent, argument)
			findings << Finding{
				stmt:       position_of(parent)
				message_id: 'unexpectedNegation'
				has_fix:    has_fix
				fix:        fix
			}
			continue
		}
		callee, args := c.es_call_identifier(node) or {
			// `Boolean?.(x)` is an optional chain: its CallExpression is in a ChainExpression.
			if !is_chain_element(node) {
				continue
			}
			callee := unwrap_parens(node_field(node, 'function') or { continue })
			if node_kind(callee) != 'identifier' {
				continue
			}
			list := (call_arguments(node) or { continue }).filter(node_kind(it) != 'comment')
			callee, list
		}
		if c.identifier_name(callee) != 'Boolean' || !c.es_is_global_reference(root, callee) {
			continue
		}
		if !c.nebc_flagged(root, o, node) {
			continue
		}
		has_fix, fix := c.nebc_call_fix(root, node, args)
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'unexpectedCall'
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nebc_estree_parent is the ESTree parent: the call or `new` of an argument, the node around the
// parentheses otherwise.
fn nebc_estree_parent(n C.TSNode) ?C.TSNode {
	parent := cti_estree_parent(n)?
	if node_kind(parent) == 'arguments' {
		return node_parent(parent)
	}
	return parent
}

// nebc_is_boolean_call ports isBooleanFunctionOrConstructorCall.
fn (mut c Checker) nebc_is_boolean_call(root C.TSNode, n C.TSNode) bool {
	if node_kind(n) !in ['call_expression', 'new_expression'] {
		return false
	}
	callee := unwrap_parens(node_field(n, if node_kind(n) == 'call_expression' {
		'function'
	} else {
		'constructor'
	}) or { return false })
	return node_kind(callee) == 'identifier' && c.text(callee) == 'Boolean'
		&& c.es_is_global_reference(root, callee)
}

// nebc_test_of is the test of an if, do-while, while, conditional or for.
fn nebc_test_of(parent C.TSNode) ?C.TSNode {
	match node_kind(parent) {
		'if_statement', 'while_statement', 'do_statement', 'ternary_expression', 'for_statement' {
			test := node_field(parent, 'condition')?
			if node_kind(test) in [';', 'empty_statement'] {
				return none
			}
			return unwrap_parens(test)
		}
		else {
			return none
		}
	}
}

// nebc_flagged ports isInFlaggedContext.
fn (mut c Checker) nebc_flagged(root C.TSNode, o NebcOptions, n C.TSNode) bool {
	parent := nebc_estree_parent(n) or { return false }
	key := node_key(n)
	kind := node_kind(parent)
	if o.logical_operands || o.inner_expressions {
		if kind == 'binary_expression' && estree_binary_kind(parent) == 'LogicalExpression' {
			operator := operator_of(parent)
			if operator in ['||', '&&'] {
				return c.nebc_flagged(root, o, parent)
			}
			if o.inner_expressions && operator == '??' {
				right := node_field(parent, 'right') or { return false }
				if node_key(unwrap_parens(right)) == key {
					return c.nebc_flagged(root, o, parent)
				}
			}
		}
	}
	if o.inner_expressions {
		if kind == 'ternary_expression' {
			consequence := node_field(parent, 'consequence') or { return false }
			alternative := node_field(parent, 'alternative') or { return false }
			if node_key(unwrap_parens(consequence)) == key || node_key(unwrap_parens(alternative)) == key {
				return c.nebc_flagged(root, o, parent)
			}
		}
		if kind == 'sequence_expression' && node_key(es_sequence_last(parent)) == key {
			mut outer := parent
			for {
				up := cti_estree_parent(outer) or { break }
				if node_kind(up) != 'sequence_expression' {
					break
				}
				outer = up
			}
			return c.nebc_flagged(root, o, outer)
		}
	}
	// isInBooleanContext.
	if c.nebc_is_boolean_call(root, parent) {
		args := (call_arguments(parent) or { []C.TSNode{} }).filter(node_kind(it) != 'comment')
		if args.len > 0 && node_key(unwrap_parens(args[0])) == key {
			return true
		}
	}
	if test := nebc_test_of(parent) {
		if node_key(test) == key {
			return true
		}
	}
	return kind == 'unary_expression' && operator_of(parent) == '!'
}

// nebc_is_parenthesized ports eslint-utils' isParenthesized(1, node): parentheses around the node
// that are not those of the syntax of its parent (a call's around its only argument, an if's
// around its test…).
fn (mut c Checker) nebc_is_parenthesized(root C.TSNode, n C.TSNode) bool {
	tokens := c.source_tokens(root)
	before := tokens.before(node_start(n), false) or { return false }
	after := tokens.after(c.es_end(n), false) or { return false }
	if c.src[before.start..before.end] != '(' || c.src[after.start..after.end] != ')' {
		return false
	}
	parent := nebc_estree_parent(n) or { return true }
	mut syntax := -1
	match node_kind(parent) {
		'call_expression', 'new_expression' {
			if args := node_field(parent, 'arguments') {
				list := named_args(args)
				if list.len == 1 && node_key(unwrap_parens(list[0])) == node_key(n) {
					syntax = node_start(args)
				}
			}
		}
		'if_statement', 'while_statement', 'do_statement', 'switch_statement', 'with_statement' {
			field := match node_kind(parent) {
				'switch_statement' { 'value' }
				'with_statement' { 'object' }
				else { 'condition' }
			}
			if test := node_field(parent, field) {
				syntax = node_start(test)
			}
		}
		else {}
	}
	return before.start != syntax
}

fn named_args(args C.TSNode) []C.TSNode {
	return treesitter.named_children(args).filter(node_kind(it) != 'comment')
}

// nebc_needs_parens ports needsParens: the replacement needs parentheses where the cast was.
fn (mut c Checker) nebc_needs_parens(root C.TSNode, previous C.TSNode, node C.TSNode) bool {
	if c.nebc_is_parenthesized(root, previous) {
		return false
	}
	parent := nebc_estree_parent(previous) or { return false }
	key := node_key(previous)
	match node_kind(parent) {
		'call_expression', 'new_expression' {
			return node_kind(node) == 'sequence_expression'
		}
		'if_statement', 'do_statement', 'while_statement', 'for_statement', 'sequence_expression' {
			return false
		}
		'ternary_expression' {
			if test := nebc_test_of(parent) {
				if node_key(test) == key {
					return es_precedence(node) <= es_precedence(parent)
				}
			}
			return es_precedence(node) < 1
		}
		'unary_expression' {
			return es_precedence(node) < es_precedence(parent)
		}
		'binary_expression' {
			if estree_binary_kind(parent) != 'LogicalExpression' {
				return false
			}
			if es_is_mixed_logical_and_coalesce(node, parent) {
				return true
			}
			left := node_field(parent, 'left') or { return false }
			if node_key(unwrap_parens(left)) == key {
				return es_precedence(node) < es_precedence(parent)
			}
			return es_precedence(node) <= es_precedence(parent)
		}
		else {
			return false
		}
	}
}

// es_is_mixed_logical_and_coalesce ports isMixedLogicalAndCoalesceExpressions.
fn es_is_mixed_logical_and_coalesce(left C.TSNode, right C.TSNode) bool {
	is_logical := fn (n C.TSNode) bool {
		return estree_binary_kind(n) == 'LogicalExpression' && operator_of(n) in ['&&', '||']
	}
	is_coalesce := fn (n C.TSNode) bool {
		return estree_binary_kind(n) == 'LogicalExpression' && operator_of(n) == '??'
	}
	return (is_logical(left) && is_coalesce(right)) || (is_coalesce(left) && is_logical(right))
}

fn (mut c Checker) nebc_negation_fix(root C.TSNode, parent C.TSNode, argument C.TSNode) (bool, Fix) {
	tokens := c.source_tokens(root)
	start := node_start(parent)
	end := c.es_end(parent)
	if tokens.comments_inside(start, end).len > 0 {
		return false, Fix{}
	}
	if c.nebc_needs_parens(root, parent, argument) {
		return true, fix_replace_range(start, end, '(${c.es_text(argument)})')
	}
	mut prefix := ''
	if before := tokens.before(start, false) {
		first := tokens.after(node_start(argument), false) or { return false, Fix{} }
		if before.end == start && !c.es_can_tokens_be_adjacent(before, first) {
			prefix = ' '
		}
	}
	return true, fix_replace_range(start, end, prefix + c.es_text(argument))
}

fn (mut c Checker) nebc_call_fix(root C.TSNode, call C.TSNode, args []C.TSNode) (bool, Fix) {
	tokens := c.source_tokens(root)
	start := node_start(call)
	end := c.es_end(call)
	if args.len == 0 {
		parent := nebc_estree_parent(call) or { return false, Fix{} }
		if node_kind(parent) == 'unary_expression' && operator_of(parent) == '!' {
			p_start := node_start(parent)
			p_end := c.es_end(parent)
			if tokens.comments_inside(p_start, p_end).len > 0 {
				return false, Fix{}
			}
			mut prefix := ''
			if before := tokens.before(p_start, false) {
				if before.end == p_start
					&& !es_can_adjacent(before.kind, c.src[before.start..before.end], .boolean, 'true') {
					prefix = ' '
				}
			}
			return true, fix_replace_range(p_start, p_end, prefix + 'true')
		}
		if tokens.comments_inside(start, end).len > 0 {
			return false, Fix{}
		}
		return true, fix_replace_range(start, end, 'false')
	}
	if args.len == 1 {
		argument := unwrap_parens(args[0])
		if node_kind(args[0]) == 'spread_element' || tokens.comments_inside(start, end).len > 0 {
			return false, Fix{}
		}
		if c.nebc_needs_parens(root, call, argument) {
			return true, fix_replace_range(start, end, '(${c.es_text(argument)})')
		}
		return true, fix_replace_range(start, end, c.es_text(argument))
	}
	return false, Fix{}
}
