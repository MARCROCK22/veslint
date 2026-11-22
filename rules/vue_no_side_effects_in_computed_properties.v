module rules

import time
import treesitter { node_end, node_start }

// Port of the `vue/no-side-effects-in-computed-properties` rule of eslint-plugin-vue 10.12.1 (no
// options): a mutation of `this` (or `this.$set` / `Vue.set`) directly in the getter of a computed
// property of a Vue object, and a mutation of a variable declared in a setup function or in
// `<script setup>` directly in the getter of a `computed(…)`.

const vue_no_side_effects_in_computed_properties_messages = {
	'unexpectedSideEffectInFunction': 'Unexpected side effect in computed function.'
	'unexpectedSideEffectInProperty': 'Unexpected side effect in "{{key}}" computed property.'
}

fn (mut c Checker) lint_vue_no_side_effects_in_computed_properties(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut getters := []int{}
	for call in c.vue_composition_api_calls(root, t, ['computed']).map(it.call) {
		getter := vue_getter_body_from_computed_function(t, call)
		if getter >= 0 {
			getters << getter
		}
	}
	setup_mode := s.has_setup
	if !setup_mode && s.objects.len == 0 {
		return findings
	}
	if setup_mode && getters.len == 0 {
		return findings
	}
	mut computed := map[int][]VueComputedProperty{}
	mut setup_bodies := []int{} // the setup functions (vue mode), in preorder
	if !setup_mode {
		for obj in s.objects {
			computed[obj] = vue_computed_properties(t, obj)
		}
	}
	tree := c.scope_tree(root)
	for step in t.steps() {
		node := step.node
		if step.leave {
			continue
		}
		if !setup_mode && s.vue_function_kind(t, node) == 'setup' {
			setup_bodies << node
		}
		if t.typ(node) !in [.identifier, .this_expression] {
			continue
		}
		mem := t.nodes[node].parent
		if mem < 0 || t.typ(mem) != .member_expression {
			continue
		}
		owner := s.owner_of(node)
		if setup_mode {
			if !s.in_script_setup(t, node) {
				continue
			}
		} else if owner < 0 {
			continue
		}
		f := vaa_innermost_function(t, node)
		if f < 0 {
			continue
		}
		body := t.node(f, .body) or { continue }
		stats.checked++
		mut found := false
		mut key := ''
		if !setup_mode {
			for cp in computed[owner] or { []VueComputedProperty{} } {
				if cp.value >= 0 && cp.value == body {
					found = true
					key = if cp.has_key && cp.key != '' { cp.key } else { 'Unknown' }
					break
				}
			}
		}
		if found {
			if (t.node(mem, .object) or { -1 }) != node {
				continue
			}
			is_this := c.vue_is_this(root, t, node)
			is_vue := t.typ(node) == .identifier && (t.string_of(node, .name) or { '' }) == 'Vue'
			property := t.node(mem, .property) or { -1 }
			mem_parent := t.nodes[mem].parent
			property_name := if property >= 0 && t.typ(property) == .identifier {
				t.string_of(property, .name) or { '' }
			} else {
				''
			}
			is_vue_set := mem_parent >= 0 && t.typ(mem_parent) == .call_expression
				&& property_name != '' && ((is_this && property_name == '\$set')
				|| (is_vue && property_name == 'set'))
			invalid := if is_vue_set {
				property
			} else if is_this {
				if m := vue_find_mutating(t, mem, vue_script_parent) { m.node } else { -1 }
			} else {
				-1
			}
			if invalid >= 0 {
				findings << Finding{
					stmt:       c.es_tree_position(t, invalid)
					message_id: 'unexpectedSideEffectInProperty'
					data:       {
						'key': key
					}
				}
			}
			continue
		}
		if t.typ(node) == .this_expression || f !in getters
			|| (t.node(mem, .object) or { -1 }) != node {
			continue
		}
		v := c.unb_find_variable(root, t, node)
		if v < 0 || tree.variables[v].defs.len != 1 {
			continue
		}
		def := tree.variables[v].defs[0]
		if def.kind == .import_binding {
			continue
		}
		def_start := node_start(def.node)
		def_end := node_end(def.node)
		mut inside_setup := setup_mode && s.setup_start <= def_start && def_end <= s.setup_end
		if !setup_mode {
			for fn_node in setup_bodies {
				b := t.node(fn_node, .body) or { continue }
				if t.nodes[b].start <= def_start && def_end <= t.nodes[b].end {
					inside_setup = true
					break
				}
			}
		}
		if !inside_setup || (t.nodes[f].start <= def_start && def_end <= t.nodes[f].end) {
			continue
		}
		invalid := if m := vue_find_mutating(t, node, vue_script_parent) { m.node } else { -1 }
		if invalid >= 0 {
			findings << Finding{
				stmt:       c.es_tree_position(t, invalid)
				message_id: 'unexpectedSideEffectInFunction'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
