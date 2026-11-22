module rules

import time

// Port of the `vue/no-deprecated-dollar-scopedslots-api` rule of eslint-plugin-vue 10.12.1 (no
// options): in a .vue file, a reference of the template to `$scopedSlots` that no element defines,
// and `this.$scopedSlots` in a Vue object of the script, fixed to `$slots`.

const vue_no_deprecated_dollar_scopedslots_api_messages = {
	'deprecated': 'The `$scopedSlots` is deprecated.'
}

fn (mut c Checker) lint_vue_no_deprecated_dollar_scopedslots_api(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	// defineTemplateBodyVisitor gives no listener, not even the script's, outside a .vue file.
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for id in c.vue_unresolved_template_refs('$scopedSlots') {
		stats.checked++
		start, end := c.vue_expr_range(id)
		findings << c.with_fixes(c.vue_report(start, end, 'deprecated', {}), [
			fix_replace_range(start, end, r'$slots'),
		])!
	}
	if t := c.es_tree(root, abs_path) {
		for member in c.vue_this_members_named(root, abs_path, '$scopedSlots') {
			stats.checked++
			property := t.node(member, .property) or { continue }
			findings << c.with_fixes(Finding{
				stmt:       c.es_tree_position(t, property)
				message_id: 'deprecated'
			}, [fix_replace_range(t.nodes[property].start, t.nodes[property].end, r'$slots')])!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
