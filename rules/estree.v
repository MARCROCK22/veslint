module rules

import treesitter { children, has_child_kind, named_children, node_field, node_kind, node_parent }

// ESTree shapes on tree-sitter nodes: the node types typescript-eslint rules compare, the
// ChainExpression that typescript-estree wraps around an optional chain, and the parts of member
// expressions. ESTree has no parentheses: callers unwrap them (unwrap_parens, estree_parent).

// is_chain_element: a node typescript-estree may put in an optional chain (a member access, a call
// that is not a tagged template, or a `!`).
fn is_chain_element(n C.TSNode) bool {
	return match node_kind(n) {
		'member_expression', 'subscript_expression', 'non_null_expression' {
			true
		}
		'call_expression' {
			args := node_field(n, 'arguments') or { return false }
			node_kind(args) == 'arguments'
		}
		else {
			false
		}
	}
}

// is_optional_element: the element has its own `?.` (an `optional_chain` node in a member access,
// an anonymous `?.` token in a call).
fn is_optional_element(n C.TSNode) bool {
	return match node_kind(n) {
		'member_expression', 'subscript_expression' { has_child_kind(n, 'optional_chain') }
		'call_expression' { has_child_kind(n, '?.') }
		else { false }
	}
}

// chain_lhs is the part a chain element applies to: the object, the callee or the expression of a
// `!`, with its parentheses (which break a chain).
fn chain_lhs(n C.TSNode) ?C.TSNode {
	return match node_kind(n) {
		'member_expression', 'subscript_expression' { node_field(n, 'object') }
		'call_expression' { node_field(n, 'function') }
		'non_null_expression' { first_named(n) }
		else { none }
	}
}

// chain_has_optional: some element of the chain that ends at `n` has a `?.`.
fn chain_has_optional(n C.TSNode) bool {
	mut node := n
	for depth := 0; depth < max_expression_depth; depth++ {
		if !is_chain_element(node) {
			return false
		}
		if is_optional_element(node) {
			return true
		}
		node = chain_lhs(node) or { return false }
	}
	return false
}

// is_estree_chain_root: `n` is the outermost element of an optional chain, which typescript-estree
// wraps in a ChainExpression (a `!` continues the chain; parentheses break it).
fn is_estree_chain_root(n C.TSNode) bool {
	if !chain_has_optional(n) {
		return false
	}
	parent := node_parent(n) or { return true }
	if !is_chain_element(parent) {
		return true
	}
	lhs := chain_lhs(parent) or { return true }
	return node_key(lhs) != node_key(n)
}

// estree_type is the ESTree type of a node as rules compare it; other kinds keep their tree-sitter
// name, which never matches an ESTree one.
fn estree_type(n C.TSNode) string {
	kind := node_kind(n)
	return match kind {
		'identifier', 'undefined', 'property_identifier', 'shorthand_property_identifier' {
			'Identifier'
		}
		'this' {
			'ThisExpression'
		}
		'string', 'number', 'true', 'false', 'null', 'regex' {
			'Literal'
		}
		'unary_expression' {
			'UnaryExpression'
		}
		'binary_expression' {
			estree_binary_kind(n)
		}
		'member_expression', 'subscript_expression', 'call_expression', 'non_null_expression' {
			if is_chain_element(n) && is_estree_chain_root(n) {
				'ChainExpression'
			} else if kind == 'call_expression' {
				'CallExpression'
			} else if kind == 'non_null_expression' {
				'TSNonNullExpression'
			} else {
				'MemberExpression'
			}
		}
		else {
			kind
		}
	}
}

// estree_binary_kind tells ESTree's LogicalExpression (`&&`, `||`, `??`) from BinaryExpression.
fn estree_binary_kind(n C.TSNode) string {
	if node_kind(n) != 'binary_expression' {
		return ''
	}
	return if operator_of(n) in ['&&', '||', '??'] {
		'LogicalExpression'
	} else {
		'BinaryExpression'
	}
}

fn is_member(n C.TSNode) bool {
	return node_kind(n) in ['member_expression', 'subscript_expression']
}

// member_property is the ESTree property of a MemberExpression: the name, or the index without
// parentheses.
fn member_property(n C.TSNode) ?C.TSNode {
	if node_kind(n) == 'subscript_expression' {
		return unwrap_parens(node_field(n, 'index')?)
	}
	return node_field(n, 'property')
}

// first_named is the first named child of a node, comments excluded.
fn first_named(n C.TSNode) ?C.TSNode {
	for child in children(n) {
		if C.ts_node_is_named(child) && node_kind(child) != 'comment' {
			return child
		}
	}
	return none
}

// call_arguments are the ESTree arguments of a call (spreads included), or none for a tagged
// template.
fn call_arguments(call C.TSNode) ?[]C.TSNode {
	args := node_field(call, 'arguments')?
	if node_kind(args) != 'arguments' {
		return none
	}
	return named_children(args)
}

// children_of_kind are the children (named or not) of a node with that kind.
fn children_of_kind(n C.TSNode, kind string) []C.TSNode {
	return children(n).filter(node_kind(it) == kind)
}

// unwrap_type_parens removes the parentheses around a type: typescript-estree converts a
// ParenthesizedType to its inner type.
fn unwrap_type_parens(n C.TSNode) C.TSNode {
	mut node := n
	for node_kind(node) == 'parenthesized_type' {
		node = first_named(node) or { return node }
	}
	return node
}

// type_members are the ESTree `types` of a union_type or intersection_type: tree-sitter nests
// `A | B | C` to the left, `(A | B) | C`, whose inner node is not an ESTree node, and parentheses
// are not ESTree nodes (a parenthesized union stays one member, a nested TSUnionType).
fn type_members(n C.TSNode) []C.TSNode {
	mut out := []C.TSNode{}
	collect_type_members(n, node_kind(n), mut out)
	return out
}

fn collect_type_members(n C.TSNode, kind string, mut out []C.TSNode) {
	for child in named_children(n) {
		if node_kind(child) == kind {
			collect_type_members(child, kind, mut out)
		} else {
			out << unwrap_type_parens(child)
		}
	}
}

// type_parent is the ESTree parent of a type node: its parent without the parenthesized_type
// nodes, which typescript-estree removes.
fn type_parent(n C.TSNode) ?C.TSNode {
	mut parent := node_parent(n)?
	for node_kind(parent) == 'parenthesized_type' {
		parent = node_parent(parent)?
	}
	return parent
}

// TypeNameRole is what a `type_identifier` is in ESTree: the name of a TSTypeReference, the
// expression of a TSClassImplements or a TSInterfaceHeritage, or something else (the name it
// declares, a part of a TSQualifiedName).
enum TypeNameRole {
	other
	reference
	heritage
}

// type_name_role tells the role of a `type_identifier` (a `generic_type` is a TSTypeReference
// with type arguments, or a heritage clause with them).
fn type_name_role(n C.TSNode) TypeNameRole {
	mut name := n
	parent := node_parent(n) or { return .other }
	if node_kind(parent) == 'generic_type' {
		generic_name := node_field(parent, 'name') or { return .other }
		if node_key(generic_name) != node_key(n) {
			return .other
		}
		name = parent
	}
	context := node_parent(name) or { return .other }
	match node_kind(context) {
		'nested_type_identifier' {
			return .other
		}
		'implements_clause', 'extends_type_clause' {
			return .heritage
		}
		'class', 'class_declaration', 'abstract_class_declaration', 'interface_declaration',
		'type_alias_declaration', 'type_parameter', 'mapped_type_clause' {
			declared := node_field(context, 'name') or { return .reference }
			return if node_key(declared) == node_key(name) { .other } else { .reference }
		}
		'infer_type' {
			// `infer U extends C`: U is the name of a TSTypeParameter.
			for child in named_children(context) {
				if node_kind(child) == 'type_identifier' {
					return if node_key(child) == node_key(name) { .other } else { .reference }
				}
			}
			return .reference
		}
		else {
			return .reference
		}
	}
}
