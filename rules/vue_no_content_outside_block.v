module rules

import time

// Port of the `vue/no-content-outside-block` rule of eslint-plugin-vue 10.12.1 (no options): text
// of a .vue file outside its top-level blocks (without its leading and trailing white space),
// with the suggestion that removes it; nothing when the template ends early (an `eof-*` error).

const vue_no_content_outside_block_messages = {
	'unexpectedContent': 'Unexpected content outside of the top-level blocks. It is dropped by the compiler.'
	'removeContent':     'Remove the content outside of the top-level blocks.'
}

fn (mut c Checker) lint_vue_no_content_outside_block(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() || c.vue_has_invalid_eof() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	doc := c.vue.doc
	for child in doc.nodes[0].children {
		node := &doc.nodes[child]
		if node.typ != .v_text {
			continue
		}
		stats.checked++
		raw := doc.src[node.start..node.end]
		leading := vu4_trim_start_offset(raw, 0)
		if leading == raw.len {
			continue
		}
		trailing := raw.len - vu4_trim_end_offset(raw, raw.len)
		start := node.start + leading
		end := node.end - trailing
		has_fix, suggestion := c.suggestion('removeContent', {}, [fix_remove_range(start, end)])!
		findings << Finding{
			stmt:        c.position_range(start, end)
			message_id:  'unexpectedContent'
			text_loc:    true
			suggestions: if has_fix { [suggestion] } else { []Suggestion{} }
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
