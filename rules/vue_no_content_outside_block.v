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
		leading := vue_js_space_prefix(raw)
		if leading == raw.len {
			continue
		}
		trailing := vue_js_space_suffix(raw)
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

// vue_js_space_prefix is how many bytes of JavaScript white space and line terminators the text
// starts with (what trimStart removes).
fn vue_js_space_prefix(s string) int {
	mut i := 0
	for i < s.len {
		len := utf8_char_len(s[i])
		r := s[i..i + len].runes()[0]
		if !is_js_space(r) {
			break
		}
		i += len
	}
	return i
}

// vue_js_space_suffix is how many bytes of white space the text ends with (what trimEnd removes).
fn vue_js_space_suffix(s string) int {
	runes := s.runes()
	mut bytes := 0
	for i := runes.len - 1; i >= 0 && is_js_space(runes[i]); i-- {
		bytes += runes[i].length_in_bytes()
	}
	return bytes
}
