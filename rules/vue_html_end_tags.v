module rules

import time

// Port of the `vue/html-end-tags` rule of eslint-plugin-vue 10.12.1 (no options): the start tag of
// an element that is not void, not self-closing and has no end tag, fixed by an end tag after the
// element; nothing when the document has an `eof-*` parse error (hasInvalidEOF).

const vhet_messages = {
	'missingEndTag': "'<{{name}}>' should have end tag."
}

fn (mut c Checker) lint_vue_html_end_tags(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	if c.vue.doc.errors.any(it.code.starts_with('eof-')) {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_element {
			continue
		}
		stats.checked++
		if vue_is_html_void_element_name(node.name) || node.end_tag >= 0
			|| c.vue.doc.nodes[node.start_tag].self_closing {
			continue
		}
		findings << c.with_fixes(c.vue_report_vnode(node.start_tag, 'missingEndTag', {
			'name': node.name
		}), [fix_insert_at(node.end, '</${node.name}>')])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
