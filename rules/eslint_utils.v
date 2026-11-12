module rules

import treesitter { named_children, node_field, node_kind }

// Ports of the helpers of ESLint 10.6.0's lib/rules/utils/ast-utils.js that the rules of ESLint
// core use. A tree-sitter node stands for the ESTree node it is without its parentheses, which
// are not ESTree nodes (unwrap_parens). There is no ChainExpression either: skipChainExpression is
// that too.

// es_is_specific_id ports isSpecificId: an Identifier with that name.
fn (c &Checker) es_is_specific_id(n C.TSNode, name string) bool {
	node := unwrap_parens(n)
	return node_kind(node) in ['identifier', 'undefined'] && c.identifier_name(node) == name
}

// es_static_property_name ports getStaticPropertyName for a MemberExpression: the name of a
// property that is not computed (a private one is not static), or getStaticStringValue of a
// computed one.
fn (c &Checker) es_static_property_name(n C.TSNode) ?string {
	node := unwrap_parens(n)
	match node_kind(node) {
		'member_expression' {
			property := node_field(node, 'property')?
			if node_kind(property) != 'property_identifier' {
				return none
			}
			return c.identifier_name(property)
		}
		'subscript_expression' {
			return c.es_static_string_value(node_field(node, 'index')?)
		}
		else {
			return none
		}
	}
}

// es_static_string_value ports getStaticStringValue: String(value) of a literal, and the cooked
// text of a template literal without substitutions. A regular expression that V8 rejects has no
// value: it is given as written.
fn (c &Checker) es_static_string_value(n C.TSNode) ?string {
	node := unwrap_parens(n)
	if node_kind(node) == 'regex' {
		pattern := node_field(node, 'pattern') or { return none }
		flags := if f := node_field(node, 'flags') { c.text(f) } else { '' }
		re := regexp_new(utf16_units(c.text(pattern)), flags) or {
			return '/${c.text(pattern)}/${flags}'
		}
		return '/${c.text(pattern)}/${re.flags}'
	}
	return c.literal_name(node)
}

// es_is_specific_member_access ports isSpecificMemberAccess: a MemberExpression whose object is
// the Identifier `object` (any object when it is '') and whose static property name is
// `property` (any property when it is '').
fn (c &Checker) es_is_specific_member_access(n C.TSNode, object string, property string) bool {
	node := unwrap_parens(n)
	if node_kind(node) !in ['member_expression', 'subscript_expression'] {
		return false
	}
	if object != '' && !c.es_is_specific_id(node_field(node, 'object') or { return false }, object) {
		return false
	}
	if property != '' {
		name := c.es_static_property_name(node) or { return false }
		return name == property
	}
	return true
}

// es_sequence_last is the last expression of a SequenceExpression (`expressions.at(-1)`), and the
// node itself when it is not one.
fn es_sequence_last(n C.TSNode) C.TSNode {
	mut node := unwrap_parens(n)
	for node_kind(node) == 'sequence_expression' {
		named := named_children(node).filter(node_kind(it) != 'comment')
		if named.len == 0 {
			break
		}
		node = unwrap_parens(named.last())
	}
	return node
}
