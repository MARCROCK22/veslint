module rules

// Port of the `svelte/no-spaces-around-equal-signs-in-attribute` rule of eslint-plugin-svelte
// 3.24.1: the white space and `=` signs between an attribute's (or a directive's) key and its value
// must be a lone `=`; the report is located by the text, and the fix leaves `=`.

const snsaes_messages = {
	'noSpaces': 'Unexpected spaces found around equal signs.'
}

fn (mut c Checker) lint_svelte_no_spaces_around_equal_signs_in_attribute(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes() {
		n := doc.nodes[i]
		if n.typ !in [.attribute, .directive, .style_directive, .special_directive] {
			continue
		}
		_, key_end := c.sv_ref_range(n.key)
		// /^[\s=]*/ after the key, inside the node.
		text := c.sv_text(key_end, n.end)
		mut end := 0
		mut space := false
		for end < text.len {
			r := text[end..].runes()[0]
			if r == `=` {
				end++
			} else if is_js_space(r) {
				space = true
				end += utf8_char_len(text[end])
			} else {
				break
			}
		}
		if !space {
			continue
		}
		findings << Finding{
			...c.sv_report_text(key_end, key_end + end, 'noSpaces', {})
			has_fix: true
			fix:     Fix{
				start: key_end
				end:   key_end + end
				text:  '='
			}
		}
	}
	return findings
}
