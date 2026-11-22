module rules

import time

// Port of the `vue/no-this-in-before-route-enter` rule of eslint-plugin-vue 10.12.1 (no options):
// `this` in the `beforeRouteEnter` function of a Vue object (not in a nested function, an arrow
// function being part of it).

const vue_no_this_in_before_route_enter_messages = {
	'disallow': "'beforeRouteEnter' does NOT have access to `this` component instance. https://router.vuejs.org/guide/advanced/navigation-guards.html#in-component-guards."
}

struct VueRouteScope {
	node               int
	before_route_enter bool
}

fn (mut c Checker) lint_vue_no_this_in_before_route_enter(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	if s.objects.len == 0 {
		return findings
	}
	mut functions := map[int]bool{}
	mut stack := []VueRouteScope{}
	for step in t.steps() {
		node := step.node
		// defineVueVisitor calls the listeners only inside a Vue object.
		if s.owner_of(node) < 0 {
			continue
		}
		typ := t.typ(node)
		if step.leave {
			if typ in [.function_expression, .function_declaration] && stack.len > 0
				&& stack.last().node == node {
				stack.pop()
			}
			continue
		}
		match typ {
			.object_expression {
				if s.object_type(node) != .none_ {
					// onVueObjectEnter
					property := vue_find_property(t, node, 'beforeRouteEnter', none)
					if property >= 0 && t.typ(vue_property_value(t, property)) == .function_expression {
						functions[vue_property_value(t, property)] = true
					}
				}
			}
			.function_expression, .function_declaration {
				stack << VueRouteScope{
					node:               node
					before_route_enter: functions[node]
				}
			}
			.this_expression {
				stats.checked++
				if stack.len > 0 && stack.last().before_route_enter {
					findings << Finding{
						stmt:       c.es_tree_position(t, node)
						message_id: 'disallow'
					}
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
