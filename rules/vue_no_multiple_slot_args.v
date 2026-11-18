module rules

import estree
import time

// Port of the `vue/no-multiple-slot-args` rule of eslint-plugin-vue 10.12.1 (no options): a call
// of a slot of `this.$slots` or `this.$scopedSlots` (directly, or through the variable it is
// assigned to) in a Vue object with a second argument, or with a spread first argument.

const vue_no_multiple_slot_args_messages = {
	'unexpected':       'Unexpected multiple arguments.'
	'unexpectedSpread': 'Unexpected spread argument.'
}

fn (mut c Checker) lint_vue_no_multiple_slot_args(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
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
		if t.typ(object) != .member_expression {
			continue
		}
		name := vue_static_property_name(t, object) or { continue }
		if name !in ['$slots', '$scopedSlots'] {
			continue
		}
		stats.checked++
		if c.vue_is_this(root, t, t.node(object, .object) or { -1 }) {
			mut seen := map[int]bool{}
			c.vue_verify_slot_call(root, t, node, mut seen, mut findings)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_verify_slot_call is the rule's verify: the call of the node, or the calls of the variable
// it is assigned to (`seen`, the variables being followed, keeps a variable assigned to itself
// from looping, where upstream overflows its stack).
fn (mut c Checker) vue_verify_slot_call(root C.TSNode, t &estree.EsTree, node int, mut seen map[int]bool, mut findings []Finding) {
	parent := t.nodes[node].parent
	if parent < 0 {
		return
	}
	if t.typ(parent) == .variable_declarator {
		id := t.node(parent, .id) or { return }
		if t.typ(id) == .identifier {
			c.vue_verify_slot_references(root, t, id, mut seen, mut findings)
		}
		return
	}
	if t.typ(parent) == .assignment_expression && (t.node(parent, .right) or { -1 }) == node {
		left := t.node(parent, .left) or { return }
		if t.typ(left) == .identifier {
			c.vue_verify_slot_references(root, t, left, mut seen, mut findings)
			return
		}
	}
	if t.typ(parent) != .call_expression {
		return
	}
	args := t.list(parent, .arguments) or { return }
	if node in args || args.len == 0 {
		return
	}
	if args.len > 1 {
		findings << Finding{
			stmt:       c.es_tree_position(t, args[1])
			message_id: 'unexpected'
		}
	}
	if t.typ(args[0]) == .spread_element {
		findings << Finding{
			stmt:       c.es_tree_position(t, args[0])
			message_id: 'unexpectedSpread'
		}
	}
}

fn (mut c Checker) vue_verify_slot_references(root C.TSNode, t &estree.EsTree, id int, mut seen map[int]bool, mut findings []Finding) {
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
		c.vue_verify_slot_call(root, t, identifier, mut seen, mut findings)
	}
	seen.delete(v)
}
