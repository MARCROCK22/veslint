module rules

import time
import treesitter { named_children, node_field, node_kind, node_start, position_of }

// Port of the `prefer-object-has-own` rule of ESLint 10.6.0, with its fix (it has no options).

const poho_messages = {
	'useHasOwn': "Use 'Object.hasOwn()' instead of 'Object.prototype.hasOwnProperty.call()'."
}

fn (mut c Checker) lint_prefer_object_has_own(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['call_expression'], []) {
		args_node := node_field(node, 'arguments') or { continue }
		if node_kind(args_node) != 'arguments' {
			continue
		}
		callee := unwrap_parens(node_field(node, 'function') or { continue })
		if estree_type(callee) != 'MemberExpression' {
			continue
		}
		object := unwrap_parens(node_field(callee, 'object') or { continue })
		if estree_type(object) != 'MemberExpression' {
			continue
		}
		stats.checked++
		if (c.es_static_property_name(callee) or { '' }) != 'call'
			|| (c.es_static_property_name(object) or { '' }) != 'hasOwnProperty'
			|| !c.poho_left_hand_object(object) {
			continue
		}
		tree := c.scope_tree(root)
		v := tree.find_variable(tree.get_scope(node), 'Object', -1)
		if v < 0 || tree.variables[v].scope != 0 {
			continue
		}
		tokens := c.source_tokens(root)
		start := node_start(callee)
		end := c.es_end(callee)
		mut has_fix := tokens.comments_inside(start, end).len == 0
		mut text := 'Object.hasOwn'
		if has_fix {
			if before := tokens.before(start, true) {
				if before.end == start
					&& !es_can_adjacent(before.kind, c.src[before.start..before.end], .identifier, 'Object') {
					text = ' Object.hasOwn'
				}
			}
		}
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'useHasOwn'
			has_fix:    has_fix
			fix:        fix_replace_range(start, end, text)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// poho_left_hand_object ports hasLeftHandObject: `{}.hasOwnProperty`,
// `Object.hasOwnProperty` or `Object.prototype.hasOwnProperty`.
fn (mut c Checker) poho_left_hand_object(member C.TSNode) bool {
	object := unwrap_parens(node_field(member, 'object') or { return false })
	if node_kind(object) == 'object' && !named_children(object).any(node_kind(it) != 'comment') {
		return true
	}
	mut target := object
	if estree_type(object) == 'MemberExpression'
		&& (c.es_static_property_name(object) or { '' }) == 'prototype' {
		target = unwrap_parens(node_field(object, 'object') or { return false })
	}
	return node_kind(target) == 'identifier' && c.text(target) == 'Object'
}
