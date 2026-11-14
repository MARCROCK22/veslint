module rules

import estree
import time
import treesitter { node_kind }

// Port of the `unicorn/no-accessor-recursion` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options).

const unaccr_messages = {
	'no-accessor-recursion/error': 'Disallow recursive access to `this` within {{kind}}ters.'
}

fn (mut c Checker) lint_unicorn_no_accessor_recursion(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .this_expression {
			continue
		}
		stats.checked++
		function := c.unaccr_closest_function(root, t, node) or { continue }
		property := if t.typ(function) in [.method_definition, .property] {
			function
		} else {
			t.nodes[function].parent
		}
		if !unaccr_is_valid_property(t, property) {
			continue
		}
		kind := t.string_of(property, .kind) or { continue }
		if (kind == 'get' && unaccr_is_property_read(t, node, property))
			|| (kind == 'set' && unaccr_is_property_write(t, node, property)) {
			findings << Finding{
				stmt:       c.es_tree_position(t, t.nodes[node].parent)
				message_id: 'no-accessor-recursion/error'
				data:       {
					'kind': kind
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unaccr_closest_function ports getClosestFunctionScope: the ESTree block of the closest function
// scope of the node that is not an arrow function's, none when a class scope comes first.
fn (mut c Checker) unaccr_closest_function(root C.TSNode, t &estree.EsTree, node int) ?int {
	ts := t.ts_node(node)?
	tree := c.scope_tree(root)
	for scope := tree.get_scope(ts); scope >= 0; scope = tree.scopes[scope].upper {
		s := tree.scopes[scope]
		if s.kind == .class_scope {
			return none
		}
		if s.kind == .function && node_kind(s.block) != 'arrow_function' {
			return c.es_index_of(t, s.block)
		}
	}
	return none
}

fn unaccr_is_identifier(t &estree.EsTree, node int) bool {
	return t.typ(node) in [.identifier, .private_identifier]
}

// unaccr_is_dot_notation_access ports isDotNotationAccess.
fn unaccr_is_dot_notation_access(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if t.typ(parent) != .member_expression || t.node(parent, .object) or { -1 } != node {
		return false
	}
	property := t.node(parent, .property) or { return false }
	computed := t.flag(parent, .computed) or { false }
	// `this['foo']` is the same access as `this.foo`.
	return (!computed && unaccr_is_identifier(t, property))
		|| (computed && un_static_string_value(t, property) != none)
}

// unaccr_is_valid_property ports isValidProperty: a getter or setter with a plain name.
fn unaccr_is_valid_property(t &estree.EsTree, property int) bool {
	if property < 0 || t.typ(property) !in [.property, .method_definition] {
		return false
	}
	if t.flag(property, .computed) or { false } {
		return false
	}
	if (t.string_of(property, .kind) or { '' }) !in ['set', 'get'] {
		return false
	}
	key := t.node(property, .key) or { return false }
	return unaccr_is_identifier(t, key)
}

// unaccr_key_name ports getKeyName.
fn unaccr_key_name(t &estree.EsTree, key int) ?string {
	if value := un_static_string_value(t, key) {
		return value
	}
	return t.string_of(key, .name)
}

// unaccr_is_same_key ports isSameKey: a private name is never the same as a string key.
fn unaccr_is_same_key(t &estree.EsTree, left int, right int) bool {
	if (t.typ(left) == .private_identifier) != (t.typ(right) == .private_identifier) {
		return false
	}
	left_name := unaccr_key_name(t, left)
	right_name := unaccr_key_name(t, right)
	if left_name == none || right_name == none {
		return left_name == none && right_name == none
	}
	return left_name or { '' } == right_name or { '' }
}

// unaccr_is_member_access ports isMemberAccess.
fn unaccr_is_member_access(t &estree.EsTree, node int, property int) bool {
	return unaccr_is_dot_notation_access(t, node)
		&& unaccr_is_same_key(t, t.node(t.nodes[node].parent, .property) or { return false }, t.node(property,
			.key) or { return false })
}

// unaccr_is_recursive_destructuring_access ports isRecursiveDestructuringAccess.
fn unaccr_is_recursive_destructuring_access(t &estree.EsTree, node int, property int) bool {
	parent := t.nodes[node].parent
	if t.typ(parent) != .variable_declarator || t.node(parent, .init) or { -1 } != node {
		return false
	}
	id := t.node(parent, .id) or { return false }
	if t.typ(id) != .object_pattern {
		return false
	}
	key := t.node(property, .key) or { return false }
	for declarator_property in t.list(id, .properties) or { []int{} } {
		if declarator_property >= 0 && t.typ(declarator_property) == .property
			&& !(t.flag(declarator_property, .computed) or { false }) {
			if unaccr_is_same_key(t, t.node(declarator_property, .key) or { continue }, key) {
				return true
			}
		}
	}
	return false
}

// unaccr_is_pure_property_write ports isPurePropertyWrite: a pure write dispatches to the setter
// instead of re-entering the getter; a compound assignment or an update also reads.
fn unaccr_is_pure_property_write(t &estree.EsTree, node int, property int) bool {
	if !unaccr_is_property_write(t, node, property) {
		return false
	}
	parent := t.nodes[t.nodes[node].parent].parent
	return t.typ(parent) != .update_expression && (t.typ(parent) != .assignment_expression
		|| t.string_of(parent, .operator) or { '' } == '=')
}

// unaccr_is_property_read ports isPropertyRead.
fn unaccr_is_property_read(t &estree.EsTree, node int, property int) bool {
	return (unaccr_is_member_access(t, node, property)
		&& !unaccr_is_pure_property_write(t, node, property))
		|| unaccr_is_recursive_destructuring_access(t, node, property)
}

// unaccr_is_property_write ports isPropertyWrite.
fn unaccr_is_property_write(t &estree.EsTree, node int, property int) bool {
	if !unaccr_is_member_access(t, node, property) {
		return false
	}
	member := t.nodes[node].parent
	parent := t.nodes[member].parent
	if parent < 0 {
		return false
	}
	return match t.typ(parent) {
		// `this.foo = …`, `[this.foo = …] = …`, `({property: this.foo = …} = …)`
		.assignment_expression, .assignment_pattern {
			t.node(parent, .left) or { -1 } == member
		}
		// `++ this.foo`
		.update_expression {
			t.node(parent, .argument) or { -1 } == member
		}
		// `[this.foo] = …`
		.array_pattern {
			member in (t.list(parent, .elements) or { []int{} })
		}
		// `[...this.foo] = …`
		.rest_element {
			t.node(parent, .argument) or { -1 } == member
		}
		// `for (this.foo of …) {}` / `for (this.foo in …) {}`
		.for_of_statement, .for_in_statement {
			t.node(parent, .left) or { -1 } == member
		}
		// `({property: this.foo} = …)`: `parent.parent.properties.includes(memberExpression.parent)`
		.property {
			grand := t.nodes[parent].parent
			t.node(parent, .value) or { -1 } == member && grand >= 0
				&& t.typ(grand) == .object_pattern
				&& parent in (t.list(grand, .properties) or { []int{} })
		}
		else {
			false
		}
	}
}
