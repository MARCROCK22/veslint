module rules

import time

// Port of the `vue/no-computed-properties-in-data` rule of eslint-plugin-vue 10.12.1 (no
// options): `this.<computed>` directly in the `data` function of a Vue object (not in a nested
// function), where the computed properties are not initialized yet.

const vue_no_computed_properties_in_data_messages = {
	'cannotBeUsed': 'The computed property cannot be used in `data()` because it is before initialization.'
}

struct VueDataContext {
	data  int
	names []string
}

fn (mut c Checker) lint_vue_no_computed_properties_in_data(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	if s.objects.len == 0 {
		return findings
	}
	mut contexts := map[int]VueDataContext{}
	// The functions the traversal is in (scopeStack).
	mut functions := []int{}
	for step in t.steps() {
		node := step.node
		typ := t.typ(node)
		if typ in [.function_expression, .function_declaration, .arrow_function_expression] {
			if step.leave {
				functions.pop()
			} else {
				functions << node
			}
			continue
		}
		if step.leave {
			continue
		}
		if typ == .object_expression && s.object_type(node) != .none_ {
			// onVueObjectEnter
			data := vue_find_property(t, node, 'data', none)
			if data < 0 || t.typ(vue_property_value(t, data)) !in [
				.function_expression,
				.arrow_function_expression,
			] {
				continue
			}
			contexts[node] = VueDataContext{
				data:  vue_property_value(t, data)
				names: vue_iterate_properties(t, node, ['computed']).map(it.name)
			}
			continue
		}
		owner := s.owner_of(node)
		if typ != .member_expression || owner < 0 || functions.len == 0 {
			continue
		}
		stats.checked++
		if !c.vue_is_this(root, t, t.node(node, .object) or { -1 }) {
			continue
		}
		ctx := contexts[owner] or { continue }
		if ctx.data != functions.last() {
			continue
		}
		name := vue_static_property_name(t, node) or { continue }
		if name == '' || name !in ctx.names {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'cannotBeUsed'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
