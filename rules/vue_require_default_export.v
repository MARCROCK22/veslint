module rules

import time

// Port of the `vue/require-default-export` rule of eslint-plugin-vue 10.12.1 (no options): a .vue
// file with a `<script>` (not `<script setup>`) whose program has statements but no
// `export default`, reported at the last token of the program (the `</script>`).

const vue_require_default_export_messages = {
	'missing':             'Missing default export.'
	'mustBeDefaultExport': 'Component must be the default export.'
}

fn (mut c Checker) lint_vue_require_default_export(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() || c.vue.doc.top_elements('script').len == 0 {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	if s.has_setup {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	stats.checked++
	body := t.list(t.root, .body) or { []int{} }
	if body.any(t.typ(it) == .export_default_declaration) || body.len == 0 {
		return findings
	}
	program_tokens := c.vue.doc.script.tokens
	if program_tokens.len == 0 {
		return findings
	}
	last := program_tokens.last()
	findings << Finding{
		stmt:       c.position_range(last.start, last.end)
		message_id: if s.objects.len > 0 { 'mustBeDefaultExport' } else { 'missing' }
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
