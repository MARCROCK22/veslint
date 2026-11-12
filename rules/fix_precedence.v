module rules

import treesitter { named_children, node_field, node_kind, node_start }

// Port of typescript-eslint 8.62.0's util/getOperatorPrecedence.js (and
// isHigherPrecedenceThanAwait.js), which the fixers use to decide where parentheses are needed.
// The original has two functions that do not always agree, and both are ported: one by the
// SyntaxKind of a TypeScript node, the other by the type of an ESTree node. Both take a
// tree-sitter node that is an expression; a destructuring pattern (array_pattern, object_pattern),
// which no fixer asks about, is invalid in both here.

// OperatorPrecedence.
const precedence_comma = 0
const precedence_spread = 1
const precedence_yield = 2
const precedence_assignment = 3
const precedence_conditional = 4
const precedence_coalesce = 4
const precedence_logical_or = 5
const precedence_logical_and = 6
const precedence_bitwise_or = 7
const precedence_bitwise_xor = 8
const precedence_bitwise_and = 9
const precedence_equality = 10
const precedence_relational = 11
const precedence_shift = 12
const precedence_additive = 13
const precedence_multiplicative = 14
const precedence_exponentiation = 15
const precedence_unary = 16
const precedence_update = 17
const precedence_left_hand_side = 18
const precedence_member = 19
const precedence_primary = 20
const precedence_highest = 20
const precedence_lowest = 0
const precedence_invalid = -1

// Operators of a TypeScript BinaryExpression with the precedence of an assignment.
const precedence_ts_assignment_operators = ['&&=', '&=', '**=', '*=', '||=', '|=', '^=', '=', '>>=',
	'>>>=', '<<=', '-=', '%=', '+=', '??=', '/=']

// Operators getOperatorPrecedenceForNode gives the precedence of an assignment: its list has `==`
// where `=` was meant, so `a == b` counts as an assignment and `a = b` is invalid.
const precedence_estree_assignment_operators = ['==', '+=', '-=', '**=', '*=', '/=', '%=', '<<=',
	'>>=', '>>>=', '&=', '^=', '|=', '||=', '&&=', '??=']

// Leaves and literals with OperatorPrecedence.Primary in both functions.
const precedence_primary_kinds = ['this', 'super', 'identifier', 'undefined', 'property_identifier',
	'shorthand_property_identifier', 'private_property_identifier', 'null', 'true', 'false', 'number',
	'string', 'regex', 'template_string', 'array', 'object', 'function_expression', 'generator_function',
	'class', 'jsx_element', 'jsx_self_closing_element']

// binary_operator_precedence ports getBinaryOperatorPrecedence for an operator given as its text
// (-1 for any other text, like the original for a kind it does not list).
fn binary_operator_precedence(operator string) int {
	return match operator {
		'-', '+' { precedence_additive }
		'!=', '!==', '==', '===' { precedence_equality }
		'??' { precedence_coalesce }
		'*', '/', '%' { precedence_multiplicative }
		'**' { precedence_exponentiation }
		'&' { precedence_bitwise_and }
		'&&' { precedence_logical_and }
		'^' { precedence_bitwise_xor }
		'<', '<=', '>', '>=', 'in', 'instanceof' { precedence_relational }
		'<<', '>>', '>>>' { precedence_shift }
		'|' { precedence_bitwise_or }
		'||' { precedence_logical_or }
		else { precedence_invalid }
	}
}

// ts_binary_operator is the text of the operator token of the TypeScript BinaryExpression a node
// is (`a + b`, `a = b`, `a += b` and `a, b` are all BinaryExpressions there), or '' for another
// node: what a caller passes as `tsNode.operatorToken.kind`.
fn ts_binary_operator(n C.TSNode) string {
	return match node_kind(n) {
		'binary_expression', 'augmented_assignment_expression' { operator_of(n) }
		'assignment_expression' { '=' }
		'sequence_expression' { ',' }
		else { '' }
	}
}

// is_prefix_update: `++a` or `--a` (a PrefixUnaryExpression), not `a++`.
fn is_prefix_update(n C.TSNode) bool {
	operator := node_field(n, 'operator') or { return false }
	argument := node_field(n, 'argument') or { return false }
	return node_start(operator) < node_start(argument)
}

// ts_operator_precedence ports getOperatorPrecedence(nodeKind, operatorKind, hasArguments) for
// the TypeScript node of the expression `n`. `operator` is the operatorKind the caller passes, as
// its text ('' for SyntaxKind.Unknown; see ts_binary_operator), and `has_arguments` what it passes
// for a `new` expression. `n` is not unwrapped: a parenthesized_expression is TypeScript's
// ParenthesizedExpression (Primary), and the node an ESTree expression maps to is the one inside
// its parentheses.
fn ts_operator_precedence(n C.TSNode, operator string, has_arguments bool) int {
	kind := node_kind(n)
	return match kind {
		'spread_element' {
			precedence_spread
		}
		'yield_expression' {
			precedence_yield
		}
		'ternary_expression' {
			precedence_conditional
		}
		'binary_expression', 'assignment_expression', 'augmented_assignment_expression',
		'sequence_expression' {
			if operator in precedence_ts_assignment_operators {
				precedence_assignment
			} else if operator == ',' {
				precedence_comma
			} else {
				binary_operator_precedence(operator)
			}
		}
		'type_assertion', 'non_null_expression', 'unary_expression', 'await_expression' {
			precedence_unary
		}
		'update_expression' {
			if is_prefix_update(n) { precedence_unary } else { precedence_update }
		}
		'call_expression' {
			if precedence_is_tagged_template(n) {
				precedence_member
			} else {
				precedence_left_hand_side
			}
		}
		'new_expression' {
			if has_arguments { precedence_member } else { precedence_left_hand_side }
		}
		'member_expression', 'subscript_expression', 'meta_property' {
			precedence_member
		}
		'as_expression', 'satisfies_expression' {
			precedence_relational
		}
		'arrow_function', 'parenthesized_expression' {
			precedence_primary
		}
		else {
			if kind in precedence_primary_kinds { precedence_primary } else { precedence_invalid }
		}
	}
}

// estree_operator_precedence ports getOperatorPrecedenceForNode for the ESTree node of `n` (the
// root of an optional chain counts as its ChainExpression, which has the precedence of its
// expression). It differs from ts_operator_precedence: it reads the operator from the node, an
// arrow function has the precedence of `yield`, and `a satisfies T`, `import(x)` and `a = b` are
// invalid.
fn estree_operator_precedence(n C.TSNode) int {
	kind := node_kind(n)
	return match kind {
		'spread_element', 'rest_pattern' {
			precedence_spread
		}
		'yield_expression', 'arrow_function' {
			precedence_yield
		}
		'ternary_expression' {
			precedence_conditional
		}
		'sequence_expression' {
			precedence_comma
		}
		'binary_expression', 'assignment_expression', 'augmented_assignment_expression' {
			operator := ts_binary_operator(n)
			if operator in precedence_estree_assignment_operators {
				precedence_assignment
			} else {
				binary_operator_precedence(operator)
			}
		}
		'type_assertion', 'non_null_expression', 'unary_expression', 'await_expression' {
			precedence_unary
		}
		'update_expression' {
			if is_prefix_update(n) { precedence_unary } else { precedence_update }
		}
		'call_expression' {
			if precedence_is_tagged_template(n) {
				precedence_member
			} else if precedence_is_import_call(n) {
				precedence_invalid
			} else {
				precedence_left_hand_side
			}
		}
		'new_expression' {
			args := node_field(n, 'arguments') or { return precedence_left_hand_side }
			if named_children(args).len > 0 {
				precedence_member
			} else {
				precedence_left_hand_side
			}
		}
		'member_expression', 'subscript_expression', 'meta_property' {
			precedence_member
		}
		'as_expression' {
			precedence_relational
		}
		else {
			if kind in precedence_primary_kinds { precedence_primary } else { precedence_invalid }
		}
	}
}

// is_higher_precedence_than_await ports isHigherPrecedenceThanAwait for the TypeScript node of
// `n` (see ts_operator_precedence): its precedence, with its own operator if it is a
// BinaryExpression, is above that of `await`.
fn is_higher_precedence_than_await(n C.TSNode) bool {
	return ts_operator_precedence(n, ts_binary_operator(n), false) > precedence_unary
}

// precedence_is_tagged_template: a call_expression that is a TaggedTemplateExpression.
fn precedence_is_tagged_template(n C.TSNode) bool {
	args := node_field(n, 'arguments') or { return false }
	return node_kind(args) == 'template_string'
}

// precedence_is_import_call: `import(x)`, an ImportExpression in ESTree and a CallExpression in
// TypeScript.
fn precedence_is_import_call(n C.TSNode) bool {
	function := node_field(n, 'function') or { return false }
	return node_kind(function) == 'import'
}
