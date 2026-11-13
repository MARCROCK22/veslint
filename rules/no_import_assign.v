module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-import-assign` rule of ESLint 10.6.0 (it has no options).

const nia_messages = {
	'readonly':       "'{{name}}' is read-only."
	'readonlyMember': "The members of '{{name}}' are read-only."
}

fn (mut c Checker) lint_no_import_assign(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['import_statement'], []) {
		stats.checked++
		tree := c.scope_tree(root)
		for v in c.es_declared_variables(root, node) {
			variable := tree.variables[v]
			members := variable.defs.any(node_kind(it.node) == 'namespace_import')
			mut previous := u64(0)
			for r in variable.references {
				reference := tree.references[r]
				id := reference.identifier
				if node_key(id) == previous {
					continue
				}
				previous = node_key(id)
				mut message_id := ''
				if reference.write {
					message_id = 'readonly'
				} else if members && c.nia_is_member_write(root, id) {
					message_id = 'readonlyMember'
				}
				if message_id != '' {
					findings << Finding{
						stmt:       position_of(nia_write_node(id))
						message_id: message_id
						data:       {
							'name': c.text(id)
						}
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nia_write_node ports getWriteNode: the assignment, update, unary, call or for-in/of around.
fn nia_write_node(id C.TSNode) C.TSNode {
	mut node := id
	for {
		node = cti_estree_parent(node) or { return id }
		if node_kind(node) in ['assignment_expression', 'augmented_assignment_expression',
			'update_expression', 'unary_expression', 'call_expression', 'for_in_statement'] {
			return node
		}
	}
	return id
}

// nia_is_assignment_left ports isAssignmentLeft: the node is a target of an assignment.
fn nia_is_assignment_left(n C.TSNode) bool {
	parent := cti_estree_parent(n) or { return false }
	key := node_key(n)
	match node_kind(parent) {
		'assignment_expression', 'augmented_assignment_expression', 'assignment_pattern',
		'object_assignment_pattern' {
			left := node_field(parent, 'left') or { return false }
			return node_key(unwrap_parens(left)) == key
		}
		'array_pattern', 'rest_pattern' {
			return true
		}
		'pair_pattern' {
			value := node_field(parent, 'value') or { return false }
			return node_key(unwrap_parens(value)) == key
		}
		else {
			return false
		}
	}
}

// nia_is_member_write ports isMemberWrite for a namespace import.
fn (mut c Checker) nia_is_member_write(root C.TSNode, id C.TSNode) bool {
	parent := cti_estree_parent(id) or { return false }
	if node_kind(parent) in ['member_expression', 'subscript_expression'] {
		object := node_field(parent, 'object') or { return false }
		if node_key(unwrap_parens(object)) == node_key(id) {
			if nia_is_assignment_left(parent) {
				return true
			}
			outer := cti_estree_parent(parent) or { return false }
			match node_kind(outer) {
				'update_expression' {
					return true
				}
				'unary_expression' {
					return operator_of(outer) == 'delete'
				}
				'for_in_statement' {
					left := node_field(outer, 'left') or { return false }
					return node_key(unwrap_parens(left)) == node_key(parent)
				}
				else {}
			}
		}
	}
	// The first argument of a mutation function of the global Object or Reflect.
	call := cti_estree_parent(id) or { return false }
	if node_kind(call) != 'arguments' {
		return false
	}
	call_node := treesitter.node_parent(call) or { return false }
	if node_kind(call_node) != 'call_expression' {
		return false
	}
	args := (call_arguments(call_node) or { return false }).filter(node_kind(it) != 'comment')
	if args.len == 0 || node_key(unwrap_parens(args[0])) != node_key(id) {
		return false
	}
	callee := unwrap_parens(node_field(call_node, 'function') or { return false })
	name := c.es_static_property_name(callee) or { return false }
	object_name := if o := node_field(callee, 'object') { c.text(unwrap_parens(o)) } else { '' }
	mutation := (object_name == 'Object'
		&& name in ['assign', 'defineProperty', 'defineProperties', 'freeze', 'setPrototypeOf'])
		|| (object_name == 'Reflect'
			&& name in ['defineProperty', 'deleteProperty', 'set', 'setPrototypeOf'])
	if !mutation || !c.es_is_specific_member_access(callee, object_name, name) {
		return false
	}
	object := unwrap_parens(node_field(callee, 'object') or { return false })
	tree := c.scope_tree(root)
	v := tree.find_variable(tree.get_scope(object), object_name, node_start_of(object))
	return v >= 0 && tree.variables[v].scope == 0
}

fn node_start_of(n C.TSNode) int {
	return treesitter.node_start(n)
}
