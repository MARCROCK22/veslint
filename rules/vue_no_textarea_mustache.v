module rules

import time

// Port of the `vue/no-textarea-mustache` rule of eslint-plugin-vue 10.12.1 (no options): a mustache
// (a VExpressionContainer child of an element) inside a <textarea> (by its rawName).

const vntm_messages = {
	'unexpected': "Unexpected mustache. Use 'v-model' instead."
}

fn (mut c Checker) lint_vue_no_textarea_mustache(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		// `VElement[rawName='textarea'] VExpressionContainer`, whose parent is an element.
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_expression_container || node.parent < 0
			|| c.vue.doc.nodes[node.parent].typ != .v_element {
			continue
		}
		stats.checked++
		mut ancestor := node.parent
		for ancestor >= 0 {
			a := &c.vue.doc.nodes[ancestor]
			if a.typ == .v_element && a.raw_name == 'textarea' {
				findings << c.vue_report_vnode(i, 'unexpected', {})
				break
			}
			ancestor = a.parent
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
