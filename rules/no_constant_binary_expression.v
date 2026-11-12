module rules

import json2
import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-constant-binary-expression` rule of ESLint 10.6.0, with its option.

const ncbe_messages = {
	'constantBinaryOperand':        'Unexpected constant binary expression. Compares constantly with the {{otherSide}}-hand side of the `{{operator}}`.'
	'constantShortCircuit':         'Unexpected constant {{property}} on the left-hand side of a `{{operator}}` expression.'
	'alwaysNew':                    'Unexpected comparison to newly constructed object. These two values can never be equal.'
	'bothAlwaysNew':                'Unexpected comparison of two newly constructed objects. These two values can never be equal.'
	'constantRelationalComparison': 'Unexpected constant relational comparison. Both sides of the `{{operator}}` are literal values.'
}

const ncbe_numeric_or_string_operators = ['+', '-', '*', '/', '%', '|', '^', '&', '**', '<<', '>>',
	'>>>']

// ncbe_options reads checkRelationalComparisons.
fn ncbe_options(options []json2.Any) !bool {
	o := option_object(no_constant_binary_expression, options, ['checkRelationalComparisons'])!
	return o.bool_value('checkRelationalComparisons')!
}

fn (mut c Checker) lint_no_constant_binary_expression(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	relational := ncbe_options(c.rule_options(no_constant_binary_expression))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['binary_expression'], []) {
		stats.checked++
		operator := operator_of(node)
		left := unwrap_parens(node_field(node, 'left') or { continue })
		right := unwrap_parens(node_field(node, 'right') or { continue })
		if estree_binary_kind(node) == 'LogicalExpression' {
			if operator in ['&&', '||'] && c.es_is_constant(root, left, true) {
				findings << Finding{
					stmt:       position_of(left)
					message_id: 'constantShortCircuit'
					data:       {
						'property': 'truthiness'
						'operator': operator
					}
				}
			} else if operator == '??' && c.ncbe_constant_nullishness(root, left, false) {
				findings << Finding{
					stmt:       position_of(left)
					message_id: 'constantShortCircuit'
					data:       {
						'property': 'nullishness'
						'operator': operator
					}
				}
			}
			continue
		}
		if c.ncbe_constant_operand(root, left, right, operator) {
			findings << Finding{
				stmt:       position_of(right)
				message_id: 'constantBinaryOperand'
				data:       {
					'operator':  operator
					'otherSide': 'left'
				}
			}
		} else if c.ncbe_constant_operand(root, right, left, operator) {
			findings << Finding{
				stmt:       position_of(left)
				message_id: 'constantBinaryOperand'
				data:       {
					'operator':  operator
					'otherSide': 'right'
				}
			}
		} else if operator in ['===', '!=='] {
			if c.ncbe_always_new(root, left) {
				findings << Finding{
					stmt:       position_of(left)
					message_id: 'alwaysNew'
				}
			} else if c.ncbe_always_new(root, right) {
				findings << Finding{
					stmt:       position_of(right)
					message_id: 'alwaysNew'
				}
			}
		} else if operator in ['==', '!='] {
			if c.ncbe_always_new(root, left) && c.ncbe_always_new(root, right) {
				findings << Finding{
					stmt:       position_of(left)
					message_id: 'bothAlwaysNew'
				}
			}
		} else if relational && operator in ['<', '<=', '>', '>='] {
			if c.ncbe_static_literal(root, left) && c.ncbe_static_literal(root, right) {
				findings << Finding{
					stmt:       position_of(node)
					message_id: 'constantRelationalComparison'
					data:       {
						'operator': operator
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ncbe_constant_operand ports findBinaryExpressionConstantOperand: `b` compares constantly with
// `a`.
fn (mut c Checker) ncbe_constant_operand(root C.TSNode, a C.TSNode, b C.TSNode, operator string) bool {
	if operator in ['==', '!='] {
		return (c.ncbe_null_or_undefined(root, a) && c.ncbe_constant_nullishness(root, b, false))
			|| (c.ncbe_static_boolean(root, a) && c.ncbe_loose_boolean(root, b))
	}
	if operator in ['===', '!=='] {
		return (c.ncbe_null_or_undefined(root, a) && c.ncbe_constant_nullishness(root, b, false))
			|| (c.ncbe_static_boolean(root, a) && c.ncbe_strict_boolean(root, b))
	}
	return false
}

// ncbe_null_or_undefined ports isNullOrUndefined: `null`, the global `undefined` or a `void`.
fn (mut c Checker) ncbe_null_or_undefined(root C.TSNode, n C.TSNode) bool {
	node := unwrap_parens(n)
	return node_kind(node) == 'null' || c.es_is_global_undefined(root, node)
		|| (node_kind(node) == 'unary_expression' && operator_of(node) == 'void')
}

// ncbe_is_logical_assignment: `||=`, `&&=` or `??=`.
fn ncbe_is_logical_assignment(n C.TSNode) bool {
	return operator_of(n) in ['||=', '&&=', '??=']
}

// ncbe_constant_nullishness ports hasConstantNullishness.
fn (mut c Checker) ncbe_constant_nullishness(root C.TSNode, n C.TSNode, non_nullish bool) bool {
	node := unwrap_parens(n)
	if non_nullish && c.ncbe_null_or_undefined(root, node) {
		return false
	}
	match node_kind(node) {
		'object', 'array', 'arrow_function', 'function_expression', 'generator_function', 'class',
		'new_expression', 'string', 'number', 'true', 'false', 'null', 'regex', 'template_string',
		'update_expression', 'unary_expression' {
			return true
		}
		'binary_expression' {
			if estree_binary_kind(node) == 'LogicalExpression' {
				return operator_of(node) == '??'
					&& c.ncbe_constant_nullishness(root, node_field(node, 'right') or { return false }, true)
			}
			return true
		}
		'call_expression' {
			callee, _ := c.es_call_identifier(node) or { return false }
			return c.identifier_name(callee) in ['Boolean', 'String', 'Number', 'Symbol', 'BigInt']
				&& c.es_is_global_reference(root, callee)
		}
		'assignment_expression' {
			return c.ncbe_constant_nullishness(root, node_field(node, 'right') or { return false },
				non_nullish)
		}
		'augmented_assignment_expression' {
			// Arithmetic and bitwise assignments give numbers and strings.
			return !ncbe_is_logical_assignment(node)
		}
		'sequence_expression' {
			return c.ncbe_constant_nullishness(root, es_sequence_last(node), non_nullish)
		}
		'identifier', 'undefined' {
			return c.es_is_global_undefined(root, node)
		}
		else {
			return false
		}
	}
}

// ncbe_static_boolean ports isStaticBoolean.
fn (mut c Checker) ncbe_static_boolean(root C.TSNode, n C.TSNode) bool {
	node := unwrap_parens(n)
	match node_kind(node) {
		'true', 'false' {
			return true
		}
		'call_expression' {
			callee, args := c.es_call_identifier(node) or { return false }
			return c.es_is_constant_boolean_call(root, callee, args)
		}
		'unary_expression' {
			return operator_of(node) == '!'
				&& c.es_is_constant(root, node_field(node, 'argument') or { return false }, true)
		}
		else {
			return false
		}
	}
}

// ncbe_loose_boolean ports hasConstantLooseBooleanComparison.
fn (mut c Checker) ncbe_loose_boolean(root C.TSNode, n C.TSNode) bool {
	node := unwrap_parens(n)
	match node_kind(node) {
		'object', 'class', 'arrow_function', 'function_expression', 'generator_function', 'string',
		'number', 'true', 'false', 'null', 'regex' {
			return true
		}
		'array' {
			elements := es_array_elements(node)
			// An empty array is "" (0); two elements or more cannot be 0 or 1.
			return elements.len == 0
				|| elements.filter(!it.hole && node_kind(it.node) != 'spread_element').len > 1
		}
		'unary_expression' {
			operator := operator_of(node)
			if operator in ['void', 'typeof'] {
				return true
			}
			if operator == '!' {
				return c.es_is_constant(root, node_field(node, 'argument') or { return false },
					true)
			}
			return false
		}
		'call_expression' {
			callee, args := c.es_call_identifier(node) or { return false }
			return c.es_is_constant_boolean_call(root, callee, args)
		}
		'identifier', 'undefined' {
			return c.es_is_global_undefined(root, node)
		}
		'template_string' {
			expressions, _ := c.es_template_parts(node)
			return expressions.len == 0
		}
		'assignment_expression' {
			return c.ncbe_loose_boolean(root, node_field(node, 'right') or { return false })
		}
		'sequence_expression' {
			return c.ncbe_loose_boolean(root, es_sequence_last(node))
		}
		else {
			return false
		}
	}
}

// ncbe_strict_boolean ports hasConstantStrictBooleanComparison.
fn (mut c Checker) ncbe_strict_boolean(root C.TSNode, n C.TSNode) bool {
	node := unwrap_parens(n)
	match node_kind(node) {
		'object', 'array', 'arrow_function', 'function_expression', 'generator_function', 'class',
		'new_expression', 'template_string', 'string', 'number', 'true', 'false', 'null', 'regex',
		'update_expression' {
			return true
		}
		'binary_expression' {
			return estree_binary_kind(node) == 'BinaryExpression'
				&& operator_of(node) in ncbe_numeric_or_string_operators
		}
		'unary_expression' {
			operator := operator_of(node)
			if operator == 'delete' {
				return false
			}
			if operator == '!' {
				return c.es_is_constant(root, node_field(node, 'argument') or { return false },
					true)
			}
			return true
		}
		'sequence_expression' {
			return c.ncbe_strict_boolean(root, es_sequence_last(node))
		}
		'identifier', 'undefined' {
			return c.es_is_global_undefined(root, node)
		}
		'assignment_expression' {
			return c.ncbe_strict_boolean(root, node_field(node, 'right') or { return false })
		}
		'augmented_assignment_expression' {
			return !ncbe_is_logical_assignment(node)
		}
		'call_expression' {
			callee, args := c.es_call_identifier(node) or { return false }
			name := c.identifier_name(callee)
			if name in ['String', 'Number', 'BigInt', 'Symbol'] {
				return c.es_is_global_reference(root, callee)
			}
			return c.es_is_constant_boolean_call(root, callee, args)
		}
		else {
			return false
		}
	}
}

// ncbe_always_new ports isAlwaysNew: a value that is a new object each time.
fn (mut c Checker) ncbe_always_new(root C.TSNode, n C.TSNode) bool {
	node := unwrap_parens(n)
	match node_kind(node) {
		'object', 'array', 'arrow_function', 'function_expression', 'generator_function', 'class',
		'regex' {
			return true
		}
		'new_expression' {
			callee := unwrap_parens(node_field(node, 'constructor') or { return false })
			if node_kind(callee) !in ['identifier', 'undefined'] {
				return false
			}
			return c.identifier_name(callee) in scope_es_globals
				&& c.es_is_global_reference(root, callee)
		}
		'sequence_expression' {
			return c.ncbe_always_new(root, es_sequence_last(node))
		}
		'assignment_expression' {
			return c.ncbe_always_new(root, node_field(node, 'right') or { return false })
		}
		'ternary_expression' {
			return c.ncbe_always_new(root, node_field(node, 'consequence') or { return false })
				&& c.ncbe_always_new(root, node_field(node, 'alternative') or { return false })
		}
		else {
			return false
		}
	}
}

// ncbe_static_literal ports isStaticLiteral.
fn (mut c Checker) ncbe_static_literal(root C.TSNode, n C.TSNode) bool {
	node := unwrap_parens(n)
	match node_kind(node) {
		'string', 'number', 'true', 'false', 'null', 'regex' {
			return true
		}
		'unary_expression' {
			argument := unwrap_parens(node_field(node, 'argument') or { return false })
			return operator_of(node) in ['-', '+', '~'] && es_is_literal(argument)
		}
		'identifier', 'undefined' {
			return c.es_is_global_undefined(root, node)
		}
		'template_string' {
			expressions, _ := c.es_template_parts(node)
			return expressions.len == 0
		}
		else {
			return false
		}
	}
}
