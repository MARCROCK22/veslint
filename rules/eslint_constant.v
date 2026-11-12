module rules

import treesitter { children, node_field, node_kind }

// Ports of isConstant and isLogicalIdentity of ESLint 10.6.0's ast-utils, with
// isReferenceToGlobalVariable, for no-constant-condition and no-constant-binary-expression. Nodes
// are taken without their parentheses (unwrap_parens).

// es_is_global_reference ports isReferenceToGlobalVariable: the identifier references a variable
// of the global scope that has no definition (a builtin global).
fn (mut c Checker) es_is_global_reference(root C.TSNode, n C.TSNode) bool {
	node := unwrap_parens(n)
	tree := c.scope_tree(root)
	v := tree.own_variable(tree.global_scope(), c.identifier_name(node))
	if v < 0 || tree.variables[v].defs.len > 0 {
		return false
	}
	key := node_key(node)
	return tree.variables[v].references.any(node_key(tree.references[it].identifier) == key)
}

// es_is_literal: an ESTree Literal (a string, number, BigInt, boolean, null or regular expression).
fn es_is_literal(n C.TSNode) bool {
	return node_kind(n) in ['string', 'number', 'true', 'false', 'null', 'regex']
}

// es_is_identifier_named: an Identifier with that name.
fn (c &Checker) es_is_identifier_named(n C.TSNode, name string) bool {
	return node_kind(n) in ['identifier', 'undefined'] && c.identifier_name(n) == name
}

// es_is_global_undefined: the Identifier `undefined` referencing the global variable.
fn (mut c Checker) es_is_global_undefined(root C.TSNode, n C.TSNode) bool {
	return c.es_is_identifier_named(n, 'undefined') && c.es_is_global_reference(root, n)
}

// es_plain_call is a CallExpression (not an optional chain, not a tagged template) with its callee
// and its arguments.
fn es_plain_call(n C.TSNode) ?(C.TSNode, []C.TSNode) {
	if node_kind(n) != 'call_expression' || estree_type(n) != 'CallExpression' {
		return none
	}
	args := call_arguments(n)?
	callee := unwrap_parens(node_field(n, 'function')?)
	return callee, args.filter(node_kind(it) != 'comment')
}

// es_global_call_name is the name of the callee of a CallExpression when it is an Identifier.
fn (c &Checker) es_call_identifier(n C.TSNode) ?(C.TSNode, []C.TSNode) {
	callee, args := es_plain_call(n)?
	if node_kind(callee) !in ['identifier', 'undefined'] {
		return none
	}
	return callee, args
}

// es_is_boolean_call_constant is the CallExpression case of isConstant (and of the comparisons of
// no-constant-binary-expression): a call of the global `Boolean` without arguments or with a
// constant first one.
fn (mut c Checker) es_is_constant_boolean_call(root C.TSNode, callee C.TSNode, args []C.TSNode) bool {
	return c.identifier_name(callee) == 'Boolean' && c.es_is_global_reference(root, callee)
		&& (args.len == 0 || c.es_is_constant(root, args[0], true))
}

// es_template_parts are the expressions of a template literal and whether one of its quasis has
// a non-empty cooked value (a line continuation cooks to nothing).
fn (c &Checker) es_template_parts(n C.TSNode) ([]C.TSNode, bool) {
	mut expressions := []C.TSNode{}
	mut has_text := false
	for child in children(n) {
		match node_kind(child) {
			'string_fragment' {
				has_text = true
			}
			'escape_sequence' {
				if !c.es_is_line_continuation(child) {
					has_text = true
				}
			}
			'template_substitution' {
				if expression := first_named(child) {
					expressions << expression
				}
			}
			else {}
		}
	}
	return expressions, has_text
}

// es_is_line_continuation: an escape sequence that is a backslash before a line terminator.
fn (c &Checker) es_is_line_continuation(n C.TSNode) bool {
	rest := c.text(n)[1..]
	return rest.starts_with('\n') || rest.starts_with('\r') || rest.starts_with('\u2028')
		|| rest.starts_with('\u2029')
}

// es_is_constant ports isConstant(scope, node, inBooleanPosition).
fn (mut c Checker) es_is_constant(root C.TSNode, n C.TSNode, in_boolean bool) bool {
	node := unwrap_parens(n)
	kind := node_kind(node)
	match kind {
		'string', 'number', 'true', 'false', 'null', 'regex', 'arrow_function',
		'function_expression', 'generator_function', 'class', 'object' {
			return true
		}
		'template_string' {
			expressions, has_text := c.es_template_parts(node)
			return (in_boolean && has_text) || expressions.all(c.es_is_constant(root, it, false))
		}
		'array' {
			if !in_boolean {
				return es_array_elements(node).all(it.hole
					|| c.es_is_constant(root, it.node, false))
			}
			return true
		}
		'unary_expression' {
			operator := operator_of(node)
			if operator == 'void' || (operator == 'typeof' && in_boolean) {
				return true
			}
			argument := node_field(node, 'argument') or { return false }
			return c.es_is_constant(root, argument, operator == '!')
		}
		'binary_expression' {
			left := node_field(node, 'left') or { return false }
			right := node_field(node, 'right') or { return false }
			operator := operator_of(node)
			if estree_binary_kind(node) == 'LogicalExpression' {
				left_constant := c.es_is_constant(root, left, in_boolean)
				right_constant := c.es_is_constant(root, right, in_boolean)
				return (left_constant && right_constant)
					|| (left_constant && c.es_is_logical_identity(left, operator))
					|| (in_boolean && right_constant && c.es_is_logical_identity(right, operator))
			}
			return c.es_is_constant(root, left, false) && c.es_is_constant(root, right, false)
				&& operator != 'in'
		}
		'new_expression' {
			return in_boolean
		}
		'assignment_expression' {
			return c.es_is_constant(root, node_field(node, 'right') or { return false },
				in_boolean)
		}
		'augmented_assignment_expression' {
			operator := operator_of(node)
			if operator in ['||=', '&&='] && in_boolean {
				return c.es_is_logical_identity(node_field(node, 'right') or { return false },
					operator[..2])
			}
			return false
		}
		'sequence_expression' {
			return c.es_is_constant(root, es_sequence_last(node), in_boolean)
		}
		'spread_element' {
			return c.es_is_constant(root, first_named(node) or { return false }, in_boolean)
		}
		'call_expression' {
			callee, args := c.es_call_identifier(node) or { return false }
			return c.es_is_constant_boolean_call(root, callee, args)
		}
		'identifier', 'undefined' {
			return c.es_is_global_undefined(root, node)
		}
		else {
			return false
		}
	}
}

// es_is_logical_identity ports isLogicalIdentity: a value that makes the logical operator give
// the other operand away (`true` for `||`, `false` for `&&`).
fn (c &Checker) es_is_logical_identity(n C.TSNode, operator string) bool {
	node := unwrap_parens(n)
	match node_kind(node) {
		'string', 'number', 'true', 'false', 'null', 'regex' {
			value := c.es_literal_boolean(node) or { return false }
			return (operator == '||' && value) || (operator == '&&' && !value)
		}
		'unary_expression' {
			return operator == '&&' && operator_of(node) == 'void'
		}
		'binary_expression' {
			if estree_binary_kind(node) != 'LogicalExpression' || operator_of(node) != operator {
				return false
			}
			left := node_field(node, 'left') or { return false }
			right := node_field(node, 'right') or { return false }
			return c.es_is_logical_identity(left, operator)
				|| c.es_is_logical_identity(right, operator)
		}
		'augmented_assignment_expression' {
			assign := operator_of(node)
			return assign in ['||=', '&&='] && operator == assign[..2]
				&& c.es_is_logical_identity(node_field(node, 'right') or { return false }, operator)
		}
		else {
			return false
		}
	}
}

// es_literal_boolean ports getBooleanValue: the truthiness of a Literal.
fn (c &Checker) es_literal_boolean(n C.TSNode) ?bool {
	text := c.text(n)
	return match node_kind(n) {
		'null' {
			false
		}
		'regex', 'true' {
			true
		}
		'false' {
			false
		}
		'string' {
			(c.literal_name(n) or { return none }) != ''
		}
		'number' {
			if text.ends_with('n') {
				es_bigint_is_nonzero(text)
			} else {
				value := number_literal_value(text) or { return none }
				value != 0 && value == value
			}
		}
		else {
			none
		}
	}
}

// es_bigint_is_nonzero: a BigInt literal (`0x1_0n`) whose value is not zero.
fn es_bigint_is_nonzero(text string) bool {
	mut digits := text.replace('_', '').trim_right('n')
	if digits.len > 1 && digits[0] == `0` && digits[1] in [`x`, `X`, `b`, `B`, `o`, `O`] {
		digits = digits[2..]
	}
	return digits.bytes().any(it != `0`)
}
