module rules

import treesitter { children, node_kind, node_parent, prev_sibling }

// Port of typescript-eslint 8.62.0's util/getWrappingFixer.js: fixes that wrap a node in other
// code, with the parentheses and the leading `;` the result needs where it goes.
//
// getWrappingFixer({ node, innerNode, wrap }) becomes two steps, with EsNode (fix_tokens.v) for
// the ESTree nodes:
//
//	a := c.wrapping_inner_code(node, inner_a) // one per innerNode
//	fix := c.wrapping_fix(node, '${a}.method()') // what `wrap` returns
//
// Without `wrap` the original replaces the node with the inner codes joined:
// `fix_replace(node.node, a + b)`.

// wrapping_inner_code is the code `wrap` receives for an innerNode: its text, in parentheses if it
// is not a strong precedence node or if it is an object that would become the body of an arrow
// function.
fn (c &Checker) wrapping_inner_code(node EsNode, inner EsNode) string {
	code := c.text(inner.node)
	if !is_strong_precedence_node(inner) || is_object_in_one_line_return(node, inner) {
		return '(${code})'
	}
	return code
}

// wrapping_fix replaces the node with `code`, what `wrap` returned: in parentheses if the parent
// binds tighter and the node has none, and after a `;` if it would continue the previous
// statement.
fn (mut c Checker) wrapping_fix(node EsNode, code string) Fix {
	mut text := code
	if is_weak_precedence_parent(node) && !c.is_parenthesized(node) {
		text = '(${text})'
	}
	if (text.starts_with('`') || text.starts_with('(') || text.starts_with('['))
		&& c.is_missing_semicolon_before(node) {
		text = ';${text}'
	}
	return fix_replace(node.node, text)
}

// moved_node_code ports getMovedNodeCode: the text of a node that moves to where `destination`
// is, in parentheses if it needs them there.
fn (c &Checker) moved_node_code(node_to_move EsNode, destination EsNode) string {
	code := c.text(node_to_move.node)
	if is_strong_precedence_node(node_to_move) || !is_weak_precedence_parent(destination) {
		return code
	}
	return '(${code})'
}

// is_strong_precedence_node ports isStrongPrecedenceNode: a Literal, Identifier, TSTypeReference,
// TSTypeOperator, ArrayExpression, ObjectExpression, MemberExpression, CallExpression,
// NewExpression, TaggedTemplateExpression or TSInstantiationExpression. A ChainExpression is not
// one, nor are `this`, a template or `import()`.
fn is_strong_precedence_node(e EsNode) bool {
	if e.chain {
		return false
	}
	return match node_kind(e.node) {
		'string', 'number', 'true', 'false', 'null', 'regex', 'identifier', 'undefined',
		'property_identifier', 'shorthand_property_identifier',
		'shorthand_property_identifier_pattern', 'statement_identifier', 'type_identifier',
		'generic_type', 'nested_type_identifier', 'index_type_query', 'readonly_type', 'array',
		'object', 'member_expression', 'subscript_expression', 'new_expression',
		'instantiation_expression' {
			true
		}
		'call_expression' {
			!precedence_is_import_call(e.node)
		}
		'predefined_type' {
			// `unique symbol` is a TSTypeOperator; the other ones are keywords.
			parts := children(e.node)
			parts.len > 0 && node_kind(parts[0]) == 'unique symbol'
		}
		else {
			false
		}
	}
}

// is_weak_precedence_parent ports isWeakPrecedenceParent: the parent is an UpdateExpression, a
// UnaryExpression, a BinaryExpression, a LogicalExpression, a ConditionalExpression or an
// AwaitExpression, or the node is the object of a MemberExpression, the callee of a call or a
// `new`, or the tag of a template.
fn is_weak_precedence_parent(e EsNode) bool {
	parent := e.parent() or { return false }
	if parent.chain {
		return false
	}
	return match node_kind(parent.node) {
		'update_expression', 'unary_expression', 'binary_expression', 'ternary_expression',
		'await_expression' {
			true
		}
		'member_expression', 'subscript_expression' {
			parent.has_child('object', e)
		}
		'call_expression' {
			parent.has_child('function', e)
		}
		'new_expression' {
			parent.has_child('constructor', e)
		}
		else {
			false
		}
	}
}

// is_left_hand_side ports isLeftHandSide: the node is where its parent starts (the argument of an
// UpdateExpression, the left of a binary, logical or assignment expression, the test of a
// conditional, a callee or the tag of a template).
fn is_left_hand_side(e EsNode, parent EsNode) bool {
	if parent.chain {
		return false
	}
	return match node_kind(parent.node) {
		'update_expression' {
			true
		}
		'binary_expression', 'assignment_expression', 'augmented_assignment_expression' {
			parent.has_child('left', e)
		}
		'ternary_expression' {
			parent.has_child('condition', e)
		}
		'call_expression' {
			parent.has_child('function', e)
		}
		else {
			false
		}
	}
}

// is_missing_semicolon_before ports isMissingSemicolonBefore: the node is at the start of an
// expression statement of a Program or a BlockStatement whose previous statement does not end
// with `;`.
fn (mut c Checker) is_missing_semicolon_before(e EsNode) bool {
	mut node := e
	for _ in 0 .. max_expression_depth {
		parent := node.parent() or { return false }
		if !parent.chain && node_kind(parent.node) == 'expression_statement' {
			if previous := wrapping_previous_statement(parent.node) {
				last := c.last_token(previous) or { return false }
				if !c.token_is(last, ';') {
					return true
				}
			}
		}
		if !is_left_hand_side(node, parent) {
			return false
		}
		node = parent
	}
	return false
}

// wrapping_previous_statement is the statement before `statement` in the body of its Program or
// BlockStatement (the body of a `namespace`, a `module` or a `global` is a TSModuleBlock and a
// `static` block a StaticBlock: they do not count).
fn wrapping_previous_statement(statement C.TSNode) ?C.TSNode {
	block := node_parent(statement)?
	match node_kind(block) {
		'program' {}
		'statement_block' {
			holder := node_parent(block)?
			if node_kind(holder) in ['internal_module', 'module', 'ambient_declaration',
				'class_static_block'] {
				return none
			}
		}
		else {
			return none
		}
	}
	mut previous := prev_sibling(statement)?
	for !C.ts_node_is_named(previous) || node_kind(previous) in ['comment', 'hash_bang_line'] {
		previous = prev_sibling(previous)?
	}
	return previous
}

// is_object_in_one_line_return ports isObjectExpressionInOneLineReturn: the node is the body of
// an arrow function and the inner node is an object.
fn is_object_in_one_line_return(node EsNode, inner EsNode) bool {
	if inner.chain || node_kind(inner.node) != 'object' {
		return false
	}
	parent := node.parent() or { return false }
	return node_kind(parent.node) == 'arrow_function' && parent.has_child('body', node)
}
