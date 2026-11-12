module rules

import time
import tsgo { TypeResponse, handle_kind, handle_path }
import treesitter { named_children, node_field, node_kind, position_of }

// Port of the `no-method-destructure` rule of @slipher/eslint-plugin 1.1.0 (it has no options): a
// property of an object pattern that takes a method declared in seyfert's lib off the destructured
// value.

const sy_nmd_messages = {
	'methodDestructure': '`{{name}}` is a method of a seyfert class; destructuring it loses its `this` binding and it will throw when called. Keep it on the object and call `object.{{name}}(...)`.'
}

fn (mut c Checker) lint_seyfert_no_method_destructure(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	// Each ObjectPattern with the node whose type is asked: the `init` of its VariableDeclarator,
	// or the pattern itself.
	mut patterns := []C.TSNode{}
	mut sources := []C.TSNode{}
	for pattern in c.nodes_of_kind(root, c'object_pattern') {
		mut source := pattern
		if parent := treesitter.node_parent(pattern) {
			if node_kind(parent) == 'variable_declarator' {
				if value := node_field(parent, 'value') {
					source = unwrap_parens(value)
				}
			}
		}
		patterns << pattern
		sources << source
	}
	c.resolve_node_types(sources, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for i, pattern in patterns {
		t := c.node_type(sources[i]) or { continue }
		for property in named_children(pattern) {
			key := sy_nmd_property_key(property) or { continue }
			name := c.sy_nmd_key_name(key) or { continue }
			if c.sy_nmd_is_seyfert_method(t, name)! {
				findings << Finding{
					stmt:       position_of(key)
					message_id: 'methodDestructure'
					data:       {
						'name': name
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += patterns.len
	return findings
}

// sy_nmd_property_key is the key of a Property of an ObjectPattern that is not computed; none for a
// RestElement or a computed key.
fn sy_nmd_property_key(property C.TSNode) ?C.TSNode {
	return match node_kind(property) {
		'shorthand_property_identifier_pattern' {
			property
		}
		'object_assignment_pattern' {
			left := node_field(property, 'left')?
			if node_kind(left) == 'shorthand_property_identifier_pattern' { left } else { none }
		}
		'pair_pattern' {
			key := node_field(property, 'key')?
			if node_kind(key) == 'computed_property_name' { none } else { key }
		}
		else {
			none
		}
	}
}

// sy_nmd_key_name is the name of a key: an Identifier's, or String(value) of a Literal.
fn (c &Checker) sy_nmd_key_name(key C.TSNode) ?string {
	return match node_kind(key) {
		'string' { c.literal_string_value(key) }
		'number' { js_number_string(c.text(key)) }
		'property_identifier', 'shorthand_property_identifier_pattern' { c.identifier_name(key) }
		else { none }
	}
}

// sy_nmd_is_seyfert_method ports isSeyfertMethod: a part of a union or an intersection, or the type
// itself, has a property of that name declared as a method in seyfert's lib.
fn (mut c Checker) sy_nmd_is_seyfert_method(t TypeResponse, name string) !bool {
	if t.flags & (type_flag_union | type_flag_intersection) != 0 {
		for part in c.members_of(t)! {
			if c.sy_nmd_is_seyfert_method(part, name)! {
				return true
			}
		}
		return false
	}
	symbol := c.property(t, name)!
	return symbol.declarations.any(handle_kind(it) in [syntax_kind_method_declaration,
		syntax_kind_method_signature]
		&& sy_in_path(handle_path(it), '/seyfert/lib/'))
}
