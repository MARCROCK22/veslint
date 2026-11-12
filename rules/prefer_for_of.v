module rules

import time
import treesitter { named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `prefer-for-of` rule of typescript-eslint 8.62.0 (it has no options).

const pfo_messages = {
	'preferForOf': 'Expected a `for-of` loop instead of a `for` loop with this simple iteration.'
}

fn (mut c Checker) lint_prefer_for_of(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	for node in c.nodes_of_kinds(root, ['for_statement'], []) {
		// isSingleVariableDeclaration: `let`, `var` (not `const`) with a single declarator.
		init := node_field(node, 'initializer') or { continue }
		if node_kind(init) !in ['lexical_declaration', 'variable_declaration'] {
			continue
		}
		if kind := node_field(init, 'kind') {
			if node_kind(kind) == 'const' {
				continue
			}
		}
		declarators := named_children(init).filter(node_kind(it) == 'variable_declarator')
		if declarators.len != 1 {
			continue
		}
		// isZeroInitialized and an Identifier as the id.
		id := node_field(declarators[0], 'name') or { continue }
		value := node_field(declarators[0], 'value') or { continue }
		if node_kind(id) != 'identifier' || !c.pfo_is_literal(value, '0') {
			continue
		}
		checked++
		index_name := c.identifier_name(id)
		test := node_field(node, 'condition') or { continue }
		array := c.pfo_less_than_length(test, index_name) or { continue }
		update := node_field(node, 'increment') or { continue }
		body := node_field(node, 'body') or { continue }
		if !c.pfo_is_increment(update, index_name) {
			continue
		}
		tree := c.scope_tree(root)
		index := tree.declared_variable(id)
		if index < 0 || !c.pfo_only_used_with_array(tree, body, index, array) {
			continue
		}
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'preferForOf'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// pfo_is_literal ports isLiteral: a numeric Literal (not a BigInt) whose value is `value`.
fn (c &Checker) pfo_is_literal(n C.TSNode, value string) bool {
	node := unwrap_parens(n)
	if node_kind(node) != 'number' {
		return false
	}
	text := c.text(node)
	if text.ends_with('n') {
		return false
	}
	return (js_number_string(text) or { return false }) == value
}

// pfo_is_identifier ports isMatchingIdentifier.
fn (c &Checker) pfo_is_identifier(n C.TSNode, name string) bool {
	node := unwrap_parens(n)
	return estree_type(node) == 'Identifier' && c.identifier_name(node) == name
}

// pfo_less_than_length ports isLessThanLengthExpression: `i < x.length` (also `x[length]`) gives
// `x`; an optional chain (`x?.length`) is a ChainExpression, not a MemberExpression.
fn (c &Checker) pfo_less_than_length(n C.TSNode, name string) ?C.TSNode {
	node := unwrap_parens(n)
	if node_kind(node) != 'binary_expression' || operator_of(node) != '<' {
		return none
	}
	if !c.pfo_is_identifier(node_field(node, 'left')?, name) {
		return none
	}
	right := unwrap_parens(node_field(node, 'right')?)
	if !is_member(right) || is_estree_chain_root(right) {
		return none
	}
	if !c.pfo_is_identifier(member_property(right)?, 'length') {
		return none
	}
	return unwrap_parens(node_field(right, 'object')?)
}

// pfo_is_increment ports isIncrement: `i++`, `++i`, `i += 1`, `i = i + 1` or `i = 1 + i`.
fn (c &Checker) pfo_is_increment(n C.TSNode, name string) bool {
	node := unwrap_parens(n)
	match node_kind(node) {
		'update_expression' {
			argument := node_field(node, 'argument') or { return false }
			return operator_of(node) == '++' && c.pfo_is_identifier(argument, name)
		}
		'augmented_assignment_expression', 'assignment_expression' {
			left := node_field(node, 'left') or { return false }
			right := node_field(node, 'right') or { return false }
			if !c.pfo_is_identifier(left, name) {
				return false
			}
			if node_kind(node) == 'augmented_assignment_expression' {
				return operator_of(node) == '+=' && c.pfo_is_literal(right, '1')
			}
			sum := unwrap_parens(right)
			if node_kind(sum) != 'binary_expression' || operator_of(sum) != '+' {
				return false
			}
			sum_left := node_field(sum, 'left') or { return false }
			sum_right := node_field(sum, 'right') or { return false }
			return (c.pfo_is_identifier(sum_left, name) && c.pfo_is_literal(sum_right, '1'))
				|| (c.pfo_is_literal(sum_left, '1') && c.pfo_is_identifier(sum_right, name))
		}
		else {
			return false
		}
	}
}

// pfo_only_used_with_array ports isIndexOnlyUsedWithArray: inside the body, every reference to
// the index is the property of a member access of the same array (by text, not `this`) that is
// not assigned to.
fn (c &Checker) pfo_only_used_with_array(tree &ScopeTree, body C.TSNode, index int, array C.TSNode) bool {
	array_text := c.text(array)
	for r in tree.variables[index].references {
		id := tree.references[r].identifier
		if node_start(id) < node_start(body) || node_end(id) > node_end(body) {
			continue
		}
		member := estree_parent(id) or { return false }
		if !is_member(member) {
			return false
		}
		property := member_property(member) or { return false }
		object := unwrap_parens(node_field(member, 'object') or { return false })
		if node_key(property) != node_key(id) || node_kind(object) == 'this'
			|| c.text(object) != array_text || pfo_is_assignee(member) {
			return false
		}
	}
	return true
}

// pfo_is_assignee ports isAssignee (util/isAssignee): the node is written by its parent.
fn pfo_is_assignee(node C.TSNode) bool {
	// The outermost element of an optional chain has a ChainExpression as its parent.
	if is_chain_element(node) && is_estree_chain_root(node) {
		return false
	}
	parent := estree_parent(node) or { return false }
	match node_kind(parent) {
		'assignment_expression', 'augmented_assignment_expression' {
			// a[i] = 1, a[i] += 1
			return pfo_field_is(parent, 'left', node)
		}
		'unary_expression' {
			// delete a[i]
			return operator_of(parent) == 'delete' && pfo_field_is(parent, 'argument', node)
		}
		'update_expression' {
			// a[i]++, --a[i]
			return pfo_field_is(parent, 'argument', node)
		}
		'array_pattern', 'rest_pattern' {
			// [a[i]] = [0], [...a[i]] = [0]
			return true
		}
		'pair' {
			// ({ foo: a[i] }) = { foo: 0 }: an object in parentheses is an ObjectExpression.
			object := node_parent(parent) or { return false }
			return pfo_field_is(parent, 'value', node) && node_kind(object) == 'object'
				&& pfo_is_assignee(object)
		}
		'non_null_expression', 'as_expression', 'type_assertion', 'satisfies_expression' {
			// (a[i] as number)++, [...a[i]!] = [0]
			return pfo_is_assignee(parent)
		}
		else {
			return false
		}
	}
}

// pfo_field_is: the field of `parent`, without parentheses, is `node`.
fn pfo_field_is(parent C.TSNode, field string, node C.TSNode) bool {
	value := node_field(parent, field) or { return false }
	return node_key(unwrap_parens(value)) == node_key(node)
}
