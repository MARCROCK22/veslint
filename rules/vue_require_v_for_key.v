module rules

import time

// Port of the `vue/require-v-for-key` rule of eslint-plugin-vue 10.12.1 (no options): the start tag
// of an element with a `v-for` and without a `v-bind:key`, unless it is a custom component; a
// <template> or a <slot> passes the check on to its child elements.

const vrvfk_messages = {
	'requireKey': "Elements in iteration expect to have 'v-bind:key' directives."
}

// vrvfk_check is checkKey (with a stack: templates may nest deeply).
fn (c &Checker) vrvfk_check(element int, mut findings []Finding) {
	mut stack := [element]
	for stack.len > 0 {
		el := stack.pop()
		if c.vue_has_directive(el, 'bind', 'key') {
			continue
		}
		node := &c.vue.doc.nodes[el]
		if node.name == 'template' || node.name == 'slot' {
			children := node.children.filter(c.vue.doc.nodes[it].typ == .v_element)
			for k := children.len - 1; k >= 0; k-- {
				stack << children[k]
			}
		} else if !c.vue_is_custom_component(el, false) {
			findings << c.vue_report_vnode(node.start_tag, 'requireKey', {})
		}
	}
}

fn (mut c Checker) lint_vue_require_v_for_key(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if c.vue_is_directive(i, 'for') {
			stats.checked++
			c.vrvfk_check(c.vue_attribute_element(i), mut findings)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
