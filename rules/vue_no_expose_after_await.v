module rules

import estree
import time

// Port of the `vue/no-expose-after-await` rule of eslint-plugin-vue 10.12.1 (no options): a call
// of `expose` (the context's, or the destructured `expose` of a `setup` function) after an
// `await` of that function, and a top-level `defineExpose(…)` of `<script setup>` after a
// top-level `await` of it.

const vue_no_expose_after_await_messages = {
	'forbidden': '`{{name}}` is forbidden after an `await` expression.'
}

fn (mut c Checker) lint_vue_no_expose_after_await(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	if s.objects.len == 0 && !s.has_setup {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	scopes := vaa_scopes(t)
	if scopes.first_await.len == 0 {
		return findings
	}
	// onSetupFunctionEnter: the read references of the context parameter, or of its `expose`.
	mut context_ids := map[int]map[u64]bool{}
	mut expose_ids := map[int]map[u64]bool{}
	for step in t.steps() {
		if step.leave || s.vue_function_kind(t, step.node) != 'setup' {
			continue
		}
		f := step.node
		params := t.list(f, .params) or { []int{} }
		if params.len < 2 || t.typ(params[1]) in [.rest_element, .array_pattern] {
			continue
		}
		param := params[1]
		mut context_set := map[u64]bool{}
		mut expose_set := map[u64]bool{}
		if t.typ(param) == .object_pattern {
			property := vue_find_assignment_property(t, param, 'expose')
			if property < 0 {
				continue
			}
			value := vue_property_value(t, property)
			if t.typ(value) != .identifier {
				continue
			}
			if !c.vneaa_read_references(root, t, value, mut expose_set) {
				continue
			}
		} else if t.typ(param) == .identifier {
			if !c.vneaa_read_references(root, t, param, mut context_set) {
				continue
			}
		}
		context_ids[f] = context_set.clone()
		expose_ids[f] = expose_set.clone()
	}
	for step in t.steps() {
		if step.leave || t.typ(step.node) != .call_expression {
			continue
		}
		call := step.node
		f := vaa_innermost_function(t, call)
		is_program := f < 0 && s.has_setup
		if !is_program && f !in context_ids {
			continue
		}
		start := if is_program { s.setup_start } else { t.nodes[f].start }
		end := if is_program { s.setup_end } else { t.nodes[f].end }
		if !(start <= t.nodes[call].start && t.nodes[call].end <= end)
			|| !scopes.after_await(t, f, start, end, call) {
			continue
		}
		stats.checked++
		callee := t.node(call, .callee) or { continue }
		if t.typ(callee) == .identifier {
			name := t.string_of(callee, .name) or { '' }
			is_expose := if is_program {
				parent := t.nodes[call].parent
				t.typ(parent) == .expression_statement && t.nodes[parent].parent == t.root
					&& name == 'defineExpose'
			} else {
				key := vneaa_key(t, callee)
				key != 0 && key in expose_ids[f]
			}
			if is_expose {
				findings << Finding{
					stmt:       c.es_tree_position(t, call)
					message_id: 'forbidden'
					data:       {
						'name': name
					}
				}
				continue
			}
		}
		member := vue_skip_chain(t, callee)
		if t.typ(member) != .member_expression {
			continue
		}
		name := vue_static_property_name(t, member) or { continue }
		object := t.node(member, .object) or { continue }
		if name == 'expose' && t.typ(object) == .identifier && !is_program {
			key := vneaa_key(t, object)
			if key != 0 && key in context_ids[f] {
				findings << Finding{
					stmt:       c.es_tree_position(t, call)
					message_id: 'forbidden'
					data:       {
						'name': name
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vneaa_read_references adds the identifiers of the read references of the variable `id`
// declares; false when there is no variable (findVariable).
fn (mut c Checker) vneaa_read_references(root C.vt_node, t &estree.EsTree, id int, mut out map[u64]bool) bool {
	v := c.unb_find_variable(root, t, id)
	if v < 0 {
		return false
	}
	tree := c.scope_tree(root)
	for r in tree.variables[v].references {
		reference := tree.references[r]
		if reference.read {
			out[node_key(reference.identifier)] = true
		}
	}
	return true
}

fn vneaa_key(t &estree.EsTree, node int) u64 {
	ts := t.ts_node(node) or { return 0 }
	return node_key(ts)
}
