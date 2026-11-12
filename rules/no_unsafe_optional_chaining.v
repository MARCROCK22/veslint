module rules

import json2
import time
import treesitter { node_field, node_kind, node_parent, position_of }

// Port of the `no-unsafe-optional-chaining` rule of ESLint 10.6.0, with its option.

const nuoc_messages = {
	'unsafeOptionalChain': "Unsafe usage of optional chaining. If it short-circuits with 'undefined' the evaluation will throw TypeError."
	'unsafeArithmetic':    'Unsafe arithmetic operation on optional chaining. It can result in NaN.'
}

const nuoc_arithmetic_operators = ['+', '-', '/', '*', '%', '**']
const nuoc_assignment_operators = ['+=', '-=', '/=', '*=', '%=', '**=']

// nuoc_options reads disallowArithmeticOperators.
fn nuoc_options(options []json2.Any) !bool {
	o := option_object(no_unsafe_optional_chaining, options, ['disallowArithmeticOperators'])!
	return o.bool_value('disallowArithmeticOperators')!
}

fn (mut c Checker) lint_no_unsafe_optional_chaining(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	arithmetic := nuoc_options(c.rule_options(no_unsafe_optional_chaining))!
	mut findings := []Finding{}
	kinds := ['assignment_expression', 'assignment_pattern', 'object_assignment_pattern',
		'required_parameter', 'optional_parameter', 'extends_clause', 'call_expression',
		'new_expression', 'variable_declarator', 'member_expression', 'subscript_expression',
		'for_in_statement', 'spread_element', 'binary_expression', 'with_statement', 'unary_expression',
		'augmented_assignment_expression']
	for node in c.nodes_of_kinds(root, kinds, []) {
		stats.checked++
		match node_kind(node) {
			'assignment_expression', 'assignment_pattern', 'object_assignment_pattern' {
				// AssignmentExpression and AssignmentPattern with a destructuring pattern on the left.
				left := node_field(node, 'left') or { continue }
				if node_kind(left) in ['object_pattern', 'array_pattern'] {
					nuoc_check(node_field(node, 'right') or { continue }, 'unsafeOptionalChain', mut
						findings)
				}
			}
			'required_parameter', 'optional_parameter' {
				// A parameter with a default value is an AssignmentPattern.
				pattern := node_field(node, 'pattern') or { continue }
				if node_kind(pattern) in ['object_pattern', 'array_pattern'] {
					nuoc_check(node_field(node, 'value') or { continue }, 'unsafeOptionalChain', mut
						findings)
				}
			}
			'extends_clause' {
				nuoc_check(node_field(node, 'value') or { continue }, 'unsafeOptionalChain', mut
					findings)
			}
			'call_expression' {
				// A CallExpression that is not optional, or a TaggedTemplateExpression.
				if !is_optional_element(node) {
					nuoc_check(node_field(node, 'function') or { continue }, 'unsafeOptionalChain', mut
						findings)
				}
			}
			'new_expression' {
				nuoc_check(node_field(node, 'constructor') or { continue }, 'unsafeOptionalChain', mut
					findings)
			}
			'variable_declarator' {
				name := node_field(node, 'name') or { continue }
				if node_kind(name) in ['object_pattern', 'array_pattern'] {
					nuoc_check(node_field(node, 'value') or { continue }, 'unsafeOptionalChain', mut
						findings)
				}
			}
			'member_expression', 'subscript_expression' {
				if !is_optional_element(node) {
					nuoc_check(node_field(node, 'object') or { continue }, 'unsafeOptionalChain', mut
						findings)
				}
			}
			'for_in_statement' {
				operator := node_field(node, 'operator') or { continue }
				if node_kind(operator) == 'of' {
					nuoc_check(node_field(node, 'right') or { continue }, 'unsafeOptionalChain', mut
						findings)
				}
			}
			'spread_element' {
				// A SpreadElement outside an object literal (in JSX it is a JSXSpreadAttribute or a
				// JSXSpreadChild).
				parent := node_parent(node) or { continue }
				if node_kind(parent) !in ['object', 'jsx_expression'] {
					nuoc_check(first_named(node) or { continue }, 'unsafeOptionalChain', mut
						findings)
				}
			}
			'binary_expression' {
				operator := operator_of(node)
				if operator in ['in', 'instanceof'] {
					nuoc_check(node_field(node, 'right') or { continue }, 'unsafeOptionalChain', mut
						findings)
				}
				if arithmetic && operator in nuoc_arithmetic_operators {
					nuoc_check(node_field(node, 'right') or { continue }, 'unsafeArithmetic', mut
						findings)
					nuoc_check(node_field(node, 'left') or { continue }, 'unsafeArithmetic', mut
						findings)
				}
			}
			'with_statement' {
				nuoc_check(node_field(node, 'object') or { continue }, 'unsafeOptionalChain', mut
					findings)
			}
			'unary_expression' {
				if arithmetic && operator_of(node) in nuoc_arithmetic_operators {
					nuoc_check(node_field(node, 'argument') or { continue }, 'unsafeArithmetic', mut
						findings)
				}
			}
			else {
				if arithmetic && operator_of(node) in nuoc_assignment_operators {
					nuoc_check(node_field(node, 'right') or { continue }, 'unsafeArithmetic', mut
						findings)
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nuoc_check ports checkUndefinedShortCircuit: the optional chains whose `undefined` the
// expression can evaluate to.
fn nuoc_check(n C.TSNode, message_id string, mut findings []Finding) {
	node := unwrap_parens(n)
	match node_kind(node) {
		'binary_expression' {
			if estree_binary_kind(node) != 'LogicalExpression' {
				return
			}
			operator := operator_of(node)
			if operator in ['||', '??'] {
				nuoc_check(node_field(node, 'right') or { return }, message_id, mut findings)
			} else if operator == '&&' {
				nuoc_check(node_field(node, 'left') or { return }, message_id, mut findings)
				nuoc_check(node_field(node, 'right') or { return }, message_id, mut findings)
			}
		}
		'sequence_expression' {
			nuoc_check(es_sequence_last(node), message_id, mut findings)
		}
		'ternary_expression' {
			nuoc_check(node_field(node, 'consequence') or { return }, message_id, mut findings)
			nuoc_check(node_field(node, 'alternative') or { return }, message_id, mut findings)
		}
		'await_expression' {
			nuoc_check(first_named(node) or { return }, message_id, mut findings)
		}
		else {
			if estree_type(node) == 'ChainExpression' {
				findings << Finding{
					stmt:       position_of(node)
					message_id: message_id
				}
			}
		}
	}
}
