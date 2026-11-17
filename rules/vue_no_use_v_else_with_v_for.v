module rules

import time

// Port of the `vue/no-use-v-else-with-v-for` rule of eslint-plugin-vue 10.12.1 (no options): an
// element with a `v-for` and a `v-else-if` or a `v-else`, reported for each of its `v-for`s.

const vnuvewvf_messages = {
	'unexpectedDirectiveWithVFor': 'Unexpected `{{ directiveName }}` and `v-for` on the same element. Move `{{ directiveName }}` to a wrapper element instead.'
}

fn (mut c Checker) lint_vue_no_use_v_else_with_v_for(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, 'for') {
			continue
		}
		stats.checked++
		element := c.vue_attribute_element(i)
		name := if c.vue_has_directive(element, 'else-if', none) {
			'v-else-if'
		} else if c.vue_has_directive(element, 'else', none) {
			'v-else'
		} else {
			continue
		}
		findings << c.vue_report_vnode(element, 'unexpectedDirectiveWithVFor', {
			'directiveName': name
		})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
