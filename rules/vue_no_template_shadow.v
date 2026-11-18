module rules

import json2
import time

// Port of the `vue/no-template-shadow` rule of eslint-plugin-vue 10.12.1 (option allow: names):
// a variable of an element of the template (v-for, slot scope) named like a variable of an
// enclosing element or a name of the script (with `<script setup>`, the variables of the global
// and module scopes that have definitions; the props of defineProps; the props, computed, data,
// asyncData, methods and setup names of the Vue objects).

const vue_no_template_shadow_messages = {
	'alreadyDeclaredInUpperScope': "Variable '{{name}}' is already declared in the upper scope."
}

fn vnts_options(options []json2.Any) ![]string {
	o := option_object(vue_no_template_shadow, options, ['allow'])!
	return o.string_list('allow')!
}

const vnts_group_names = ['props', 'computed', 'data', 'asyncData', 'methods', 'setup']

fn (mut c Checker) lint_vue_no_template_shadow(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	allow := vnts_options(c.rule_options(vue_no_template_shadow))!
	mut findings := []Finding{}
	mut js_vars := map[string]bool{}
	if s := c.vue_script(root, abs_path) {
		t := c.es_tree(root, abs_path) or { return findings }
		if s.has_setup {
			tree := c.scope_tree(root)
			for v in tree.scopes[0].variables {
				if tree.variables[v].defs.len > 0 {
					js_vars[tree.variables[v].name] = true
				}
			}
			for child in tree.scopes[0].children {
				if tree.scopes[child].kind != .esmodule {
					continue
				}
				for v in tree.scopes[child].variables {
					if tree.variables[v].defs.len > 0 {
						js_vars[tree.variables[v].name] = true
					}
				}
				break
			}
			for call in c.vue_macros_named(t, 'defineProps') {
				for prop in c.vue_define_props(root, t, call, abs_path, true, mut stats) {
					if prop.has_name && prop.name != '' {
						js_vars[prop.name] = true
					}
				}
			}
		}
		for object in s.objects_of(vue_all_object_types) {
			for p in vue_iterate_properties(t, object, vnts_group_names) {
				js_vars[p.name] = true
			}
		}
	}
	doc := c.vue.doc
	// The names of the variables of the elements entered (scopeStack), one list per element.
	mut scopes := [][]string{}
	for step in c.vue_template_steps() {
		n := step.node
		if n.kind != .vnode || doc.nodes[n.v].typ != .v_element {
			continue
		}
		if step.leave {
			scopes.pop()
			continue
		}
		mut scope_names := if scopes.len > 0 { scopes.last().clone() } else { []string{} }
		for v in doc.nodes[n.v].variables {
			variable := &doc.variables[v]
			name := variable.name
			if name in allow {
				continue
			}
			stats.checked++
			if name in scope_names || name in js_vars {
				start, end := c.vue_expr_range(variable.id)
				findings << c.vue_report(start, end, 'alreadyDeclaredInUpperScope', {
					'name': name
				})
			} else {
				scope_names << name
			}
		}
		scopes << scope_names
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
