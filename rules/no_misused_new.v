module rules

import time
import treesitter { named_children, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-misused-new` rule of typescript-eslint 8.62.0 (it has no options).

const nmn_messages = {
	'errorMessageClass':     'Class cannot have method named `new`.'
	'errorMessageInterface': 'Interfaces cannot be constructed, only classes.'
}

fn (mut c Checker) lint_no_misused_new(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	for node in c.nodes_of_kinds(root, ['method_signature', 'construct_signature'], []) {
		parent := node_parent(node) or { continue }
		if node_kind(node) == 'construct_signature' {
			// `TSInterfaceBody > TSConstructSignatureDeclaration` that returns the interface.
			if node_kind(parent) != 'interface_body' {
				continue
			}
			checked++
			if c.nmn_returns_parent(node_parent(parent) or { continue }, node) {
				findings << Finding{
					stmt:       c.position_range(node_start(node), c.es_member_end(node))
					message_id: 'errorMessageInterface'
				}
			}
			continue
		}
		name := node_field(node, 'name') or { continue }
		if node_kind(parent) == 'class_body' {
			// `ClassBody > MethodDefinition[key.name='new']` without a body (an overload, or a
			// method of a declared class) that returns the class.
			if c.nmn_key_name(name) != 'new' {
				continue
			}
			checked++
			if c.nmn_returns_parent(node_parent(parent) or { continue }, node) {
				findings << Finding{
					stmt:       c.position_range(cm_start(node), c.es_member_end(node))
					message_id: 'errorMessageClass'
				}
			}
			continue
		}
		// `TSMethodSignature[key.name='constructor']`, in an interface or a type literal.
		if c.nmn_key_name(name) == 'constructor' {
			checked++
			findings << Finding{
				stmt:       c.position_range(node_start(node), c.es_member_end(node))
				message_id: 'errorMessageInterface'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nmn_key_name is the `name` of a key that is an Identifier or a PrivateIdentifier (computed or
// not, as the selector does not look at that), '' for any other key.
fn (c &Checker) nmn_key_name(key C.TSNode) string {
	mut node := key
	if node_kind(node) == 'computed_property_name' {
		node = unwrap_parens(first_named(node) or { return '' })
	}
	return match node_kind(node) {
		'property_identifier', 'identifier' { c.identifier_name(node) }
		'private_property_identifier' { c.identifier_name(node)[1..] }
		else { '' }
	}
}

// nmn_returns_parent ports isMatchingParentType: the class or interface has a name, and the
// return type of the signature is a reference to that name (getTypeReferenceName).
fn (c &Checker) nmn_returns_parent(parent C.TSNode, signature C.TSNode) bool {
	if node_kind(parent) !in ['class_declaration', 'abstract_class_declaration', 'class',
		'interface_declaration'] {
		return false
	}
	id := node_field(parent, 'name') or { return false }
	for child in named_children(signature) {
		if node_kind(child) == 'type_annotation' {
			return c.nmn_type_reference_name(first_named(child) or { return false }) == c.text(id)
		}
	}
	return false
}

// nmn_type_reference_name ports getTypeReferenceName for a type: the name of a TSTypeReference
// whose typeName is an Identifier, with or without type arguments; '' for any other type.
fn (c &Checker) nmn_type_reference_name(type_node C.TSNode) string {
	mut node := unwrap_type_parens(type_node)
	if node_kind(node) == 'generic_type' {
		node = node_field(node, 'name') or { return '' }
	}
	return if node_kind(node) == 'type_identifier' { c.identifier_name(node) } else { '' }
}
