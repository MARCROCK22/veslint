module rules

import time

// Port of the `vue/no-deprecated-scope-attribute` rule of eslint-plugin-vue 10.12.1
// (syntaxes/scope-attribute.ts; no options): the key of every `scope` directive (`scope` on a
// <template>), fixed to `slot-scope`.

const vndsa_messages = {
	'forbiddenScopeAttribute': '`scope` attributes are deprecated.'
}

fn (mut c Checker) lint_vue_no_deprecated_scope_attribute(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		// `VAttribute[directive=true] > VDirectiveKey[name.name='scope']`
		if !c.vue_is_directive(i, 'scope') {
			continue
		}
		stats.checked++
		key := c.vue.doc.nodes[i].key
		node := &c.vue.doc.nodes[key]
		findings << c.with_fixes(c.vue_report_vnode(key, 'forbiddenScopeAttribute', {}), [
			fix_replace_range(node.start, node.end, 'slot-scope'),
		])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
