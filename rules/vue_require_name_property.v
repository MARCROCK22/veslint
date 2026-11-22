module rules

import os
import time

// Port of the `vue/require-name-property` rule of eslint-plugin-vue 10.12.1 (no options): a Vue
// object (not a mixin) without a `name` property, in a file without `<script setup>`, with the
// suggestion that adds one named after the file.

const vue_require_name_property_messages = {
	'missingName': 'Required name property is not set.'
	'addName':     'Add name property to component.'
}

fn (mut c Checker) lint_vue_require_name_property(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	if s.has_setup {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	base := os.base(s.filename)
	dot := base.last_index('.') or { -1 }
	// path.basename(filename, path.extname(filename))
	filename := if dot > 0 { base[..dot] } else { base }
	tokens := c.un_tokens(t)
	for component in s.objects_of(vue_all_object_types) {
		stats.checked++
		if s.object_type(component) == .definition
			&& c.vue_component_definition_type(root, t, component) == 'mixin' {
			continue
		}
		properties := t.list(component, .properties) or { []int{} }
		if properties.any(t.typ(it) == .property && !(t.flag(it, .computed) or { false })
			&& (vue_static_property_name(t, it) or { '' }) == 'name') {
			continue
		}
		mut fixes := []Fix{}
		if properties.len > 0 {
			first := un_first_token(t, tokens, properties[0], 0) or { continue }
			indent := c.vue_line_empty_indent(first.start)
			fixes << fix_insert_at(t.nodes[properties[0]].start, "name: '${filename}',\n${indent}")
		} else {
			first := un_first_token(t, tokens, component, 0) or { continue }
			last := un_last_token(t, tokens, component) or { continue }
			if c.src[first.start..first.end] == '{' && c.src[last.start..last.end] == '}' {
				indent := c.vue_line_empty_indent(first.start)
				fixes << fix_replace_range(first.end, last.start, "\n${indent}  name: '${filename}'\n${indent}")
			}
		}
		mut suggestions := []Suggestion{}
		has_fix, suggestion := c.suggestion('addName', {}, fixes)!
		if has_fix {
			suggestions << suggestion
		}
		findings << Finding{
			stmt:        c.es_tree_position(t, component)
			message_id:  'missingName'
			suggestions: suggestions
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_line_empty_indent is the rule's getLineEmptyIndent: the white space that starts the line of
// the offset (after the line terminator before it; at the start of the text, the whole text but
// its last character, as `text.slice(0, -1)` gives upstream).
fn (c &Checker) vue_line_empty_indent(offset int) string {
	text := c.src
	mut i := offset - 1
	for i >= 0 {
		b := text[i]
		if b == `\n` || b == `\r` {
			break
		}
		// U+2028 and U+2029 end with 0xA8 and 0xA9 after E2 80.
		if (b == 0xA8 || b == 0xA9) && i >= 2 && text[i - 1] == 0x80 && text[i - 2] == 0xE2 {
			i -= 2
			break
		}
		i--
	}
	if i < 0 {
		return if text.len > 0 { text[..text.len - utf8_last_char_len(text)] } else { '' }
	}
	start := i + utf8_char_len(text[i])
	mut j := start
	for j < text.len {
		len := utf8_char_len(text[j])
		r := text[j..j + len].runes()[0]
		if !is_js_space(r) {
			break
		}
		j += len
	}
	return text[start..j]
}

// utf8_last_char_len is the length in bytes of the last character of a non-empty text (`slice(0,
// -1)` drops one UTF-16 unit; a character outside the BMP is not split here).
fn utf8_last_char_len(text string) int {
	mut k := text.len - 1
	for k > 0 && text[k] & 0xC0 == 0x80 {
		k--
	}
	return text.len - k
}
