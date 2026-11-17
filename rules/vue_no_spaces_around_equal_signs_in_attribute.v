module rules

import time

// Port of the `vue/no-spaces-around-equal-signs-in-attribute` rule of eslint-plugin-vue 10.12.1 (no
// options): an attribute with a value whose `=` has white space around it (the text between the
// key and the value, trimmed as String#trim does), fixed to the bare `=`.

const vnsaesia_messages = {
	'unexpectedSpaces': 'Unexpected spaces found around equal signs.'
}

fn (mut c Checker) lint_vue_no_spaces_around_equal_signs_in_attribute(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute || node.value < 0 {
			continue
		}
		stats.checked++
		key := &c.vue.doc.nodes[node.key]
		value := &c.vue.doc.nodes[node.value]
		eq_text := c.vue_text(key.end, value.start)
		expect := js_trim(eq_text)
		if eq_text == expect {
			continue
		}
		// loc: from the end of the key to the start of the value.
		_, key_end := c.vue_vnode_range(node.key)
		value_start, _ := c.vue_vnode_range(node.value)
		findings << c.with_fixes(c.vue_report(key_end, value_start, 'unexpectedSpaces', {}), [
			fix_replace_range(key.end, value.start, expect),
		])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
