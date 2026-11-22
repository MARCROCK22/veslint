module rules

import estree
import time

// Port of the `vue/require-slots-as-functions` rule of eslint-plugin-vue 10.12.1 (no options): a
// slot of `this.$slots` in a Vue object used as a value (its property read, destructured, spread
// or put in an array), directly or through the variable it is assigned to, reported at its
// property (once per such use).

const vue_require_slots_as_functions_messages = {
	'unexpected': 'Property in `$slots` should be used as function.'
}

fn (mut c Checker) lint_vue_require_slots_as_functions(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	if s.objects.len == 0 {
		return findings
	}
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .member_expression || s.owner_of(node) < 0 {
			continue
		}
		object := vue_skip_chain(t, t.node(node, .object) or { continue })
		if t.typ(object) != .member_expression
			|| (vue_static_property_name(t, object) or { '' }) != '\$slots' {
			continue
		}
		stats.checked++
		property := t.node(node, .property) or { continue }
		if !c.vue_is_this(root, t, t.node(object, .object) or { -1 })
			|| t.typ(property) == .private_identifier {
			continue
		}
		mut seen := map[int]bool{}
		c.vue_verify_slot_value(root, t, node, property, mut seen, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_verify_slot_value is the rule's verify (`seen` as in no-multiple-slot-args).
fn (mut c Checker) vue_verify_slot_value(root C.vt_node, t &estree.EsTree, node int, report int, mut seen map[int]bool, mut findings []Finding) {
	parent := t.nodes[node].parent
	if parent < 0 {
		return
	}
	typ := t.typ(parent)
	if typ == .variable_declarator {
		id := t.node(parent, .id) or { return }
		if t.typ(id) == .identifier {
			c.vue_verify_slot_value_references(root, t, id, report, mut seen, mut findings)
			return
		}
	}
	if typ == .assignment_expression && (t.node(parent, .right) or { -1 }) == node {
		left := t.node(parent, .left) or { return }
		if t.typ(left) == .identifier {
			c.vue_verify_slot_value_references(root, t, left, report, mut seen, mut findings)
			return
		}
	}
	if typ == .chain_expression {
		c.vue_verify_slot_value(root, t, parent, report, mut seen, mut findings)
		return
	}
	if typ in [.member_expression, .variable_declarator, .spread_element, .array_expression] {
		findings << Finding{
			stmt:       c.es_tree_position(t, report)
			message_id: 'unexpected'
		}
	}
}

fn (mut c Checker) vue_verify_slot_value_references(root C.vt_node, t &estree.EsTree, id int, report int, mut seen map[int]bool, mut findings []Finding) {
	v := c.vue_find_variable(root, t, id)
	if v < 0 || seen[v] {
		return
	}
	seen[v] = true
	tree := c.scope_tree(root)
	for r in tree.variables[v].references {
		reference := tree.references[r]
		if !reference.read {
			continue
		}
		identifier := c.es_index_of(t, reference.identifier) or { continue }
		c.vue_verify_slot_value(root, t, identifier, report, mut seen, mut findings)
	}
	seen.delete(v)
}
