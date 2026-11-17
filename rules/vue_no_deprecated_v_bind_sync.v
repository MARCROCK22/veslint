module rules

import time

// Port of the `vue/no-deprecated-v-bind-sync` rule of eslint-plugin-vue 10.12.1 (no options): a
// `v-bind` with a `sync` modifier, fixed to `v-model:<argument>` when it has an argument and no
// other modifier.

const vndvbs_messages = {
	'syncModifierIsDeprecated': "'.sync' modifier on 'v-bind' directive is deprecated. Use 'v-model:propName' instead."
}

fn (mut c Checker) lint_vue_no_deprecated_v_bind_sync(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, 'bind') {
			continue
		}
		stats.checked++
		modifiers := c.vue_directive_modifiers(i)
		if !modifiers.any(c.vue.doc.nodes[it].name == 'sync') {
			continue
		}
		report := c.vue_report_vnode(i, 'syncModifierIsDeprecated', {})
		argument := c.vue_directive_argument(i)
		if argument < 0 || modifiers.len > 1 {
			findings << report
			continue
		}
		key := &c.vue.doc.nodes[c.vue.doc.nodes[i].key]
		findings << c.with_fixes(report, [
			fix_replace_range(key.start, key.end, 'v-model:${c.vue_vnode_text(argument)}'),
		])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
