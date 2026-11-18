module rules

import estree
import time

// Port of the `vue/no-deprecated-props-default-this` rule of eslint-plugin-vue 10.12.1 (no
// options): `this` in the `default` function of an object prop (whose `type` is not `Function`)
// of a Vue object, not in a nested function (an arrow function being part of it).

const vue_no_deprecated_props_default_this_messages = {
	'deprecated': 'Props default value factory functions no longer have access to `this`.'
}

struct VuePropDefaultScope {
	node         int
	prop_default bool
}

fn (mut c Checker) lint_vue_no_deprecated_props_default_this(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	if s.objects.len == 0 {
		return findings
	}
	mut defaults := map[int]bool{}
	mut stack := []VuePropDefaultScope{}
	for step in t.steps() {
		node := step.node
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
				if s.object_type(node) == .none_ {
					continue
				}
				// onVueObjectEnter
				for prop in vue_props_from_options(t, node) {
					if prop.kind != .object || prop.value < 0
						|| t.typ(prop.value) != .object_expression {
						continue
					}
					def := vue_find_property(t, prop.value, 'default', none)
					if def < 0 {
						continue
					}
					typ_property := vue_find_property(t, prop.value, 'type', none)
					if (typ_property >= 0 && vue_has_function_type(t, vue_property_value(t, typ_property)))
						|| t.typ(vue_property_value(t, def)) != .function_expression {
						continue
					}
					defaults[vue_property_value(t, def)] = true
				}
			}
			.function_expression, .function_declaration {
				if stack.len > 0 {
					stack << VuePropDefaultScope{
						node: node
					}
				} else if typ == .function_expression && defaults[node] {
					stack << VuePropDefaultScope{
						node:         node
						prop_default: true
					}
				}
			}
			.this_expression {
				stats.checked++
				if stack.len > 0 && stack.last().prop_default {
					findings << Finding{
						stmt:       c.es_tree_position(t, node)
						message_id: 'deprecated'
					}
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_has_function_type is the rule's hasFunctionType: `Function`, or an array with it.
fn vue_has_function_type(t &estree.EsTree, node int) bool {
	is_function := fn [t] (n int) bool {
		return n >= 0 && t.typ(n) == .identifier && (t.string_of(n, .name) or { '' }) == 'Function'
	}
	if is_function(node) {
		return true
	}
	return t.typ(node) == .array_expression
		&& (t.list(node, .elements) or { []int{} }).any(is_function(it))
}
