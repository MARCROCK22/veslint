module rules

import time

// Port of the `vue/no-deprecated-inline-template` rule of eslint-plugin-vue 10.12.1 (no options):
// the name of every plain attribute written `inline-template` (its rawName).

const vndit_messages = {
	'unexpected': '`inline-template` are deprecated.'
}

fn (mut c Checker) lint_vue_no_deprecated_inline_template(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		// `VAttribute[directive=false] > VIdentifier[rawName='inline-template']`
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute || node.directive || node.key < 0 {
			continue
		}
		stats.checked++
		if c.vue.doc.nodes[node.key].raw_name == 'inline-template' {
			findings << c.vue_report_vnode(node.key, 'unexpected', {})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
