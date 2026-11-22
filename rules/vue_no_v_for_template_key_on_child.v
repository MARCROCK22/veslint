module rules

import time

// Port of the `vue/no-v-for-template-key-on-child` rule of eslint-plugin-vue 10.12.1 (no options):
// in a <template v-for> whose own `:key` does not use a variable of the `v-for`, the `:key` of a
// child element (without v-if, v-else-if, v-else or v-for) that uses one.

const vnvftkoc_messages = {
	'vForTemplateKeyPlacement': '`<template v-for>` key should be placed on the `<template>` tag.'
}

// vnvftkoc_uses_iteration_var is isUsingIterationVar: a reference of the `:key`'s value names a
// `v-for` variable of the template.
fn (c &Checker) vnvftkoc_uses_iteration_var(template int, key int) bool {
	value := c.vue.doc.nodes[key].value
	if value < 0 {
		return false
	}
	for r in c.vue.doc.nodes[value].references {
		name := c.vue.doc.references[r].name
		for v in c.vue.doc.nodes[template].variables {
			if c.vue.doc.variables[v].name == name && c.vue.doc.variables[v].kind == 'v-for' {
				return true
			}
		}
	}
	return false
}

fn (mut c Checker) lint_vue_no_v_for_template_key_on_child(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		// `VElement[name='template'] > VStartTag > VAttribute[directive=true][key.name.name='for']`
		if !c.vue_is_directive(i, 'for') {
			continue
		}
		template := c.vue_attribute_element(i)
		if template < 0 || c.vue.doc.nodes[template].name != 'template' {
			continue
		}
		stats.checked++
		own_key := c.vue_get_directive(template, 'bind', 'key')
		if own_key >= 0 && c.vnvftkoc_uses_iteration_var(template, own_key) {
			continue
		}
		for child in c.vue.doc.nodes[template].children {
			if c.vue.doc.nodes[child].typ != .v_element || c.vue_has_directive(child, 'if', none)
				|| c.vue_has_directive(child, 'else-if', none)
				|| c.vue_has_directive(child, 'else', none)
				|| c.vue_has_directive(child, 'for', none) {
				continue
			}
			key := c.vue_get_directive(child, 'bind', 'key')
			if key >= 0 && c.vnvftkoc_uses_iteration_var(template, key) {
				findings << c.vue_report_vnode(key, 'vForTemplateKeyPlacement', {})
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
