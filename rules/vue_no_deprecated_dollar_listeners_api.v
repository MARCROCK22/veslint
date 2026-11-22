module rules

import time

// Port of the `vue/no-deprecated-dollar-listeners-api` rule of eslint-plugin-vue 10.12.1 (no
// options): in a .vue file, a reference of the template to `$listeners` that no element defines,
// and `this.$listeners` in a Vue object of the script.

const vue_no_deprecated_dollar_listeners_api_messages = {
	'deprecated': 'The `$listeners` is deprecated.'
}

fn (mut c Checker) lint_vue_no_deprecated_dollar_listeners_api(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	// defineTemplateBodyVisitor gives no listener, not even the script's, outside a .vue file.
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for id in c.vue_unresolved_template_refs('$listeners') {
		stats.checked++
		start, end := c.vue_expr_range(id)
		findings << c.vue_report(start, end, 'deprecated', {})
	}
	if t := c.es_tree(root, abs_path) {
		for member in c.vue_this_members_named(root, abs_path, '$listeners') {
			stats.checked++
			findings << Finding{
				stmt:       c.es_tree_position(t, t.node(member, .property) or { continue })
				message_id: 'deprecated'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
