module rules

import estree
import time

// Port of the `unicorn/no-hex-escape` rule of eslint-plugin-unicorn 64.0.0 (it has no options),
// with its fix.

const unhe_messages = {
	'no-hex-escape': 'Use Unicode escapes instead of hexadecimal escapes.'
}

// unhe_fixed is `value.replaceAll(/(?<=(?:^|[^\\])(?:\\\\)*\\)x/g, 'u00')`.
fn unhe_fixed(value string) string {
	mut out := []u8{cap: value.len + 8}
	for i in 0 .. value.len {
		if value[i] == `x` && un_is_escaped_at(value, i) {
			out << 'u00'.bytes()
		} else {
			out << value[i]
		}
	}
	return out.bytestr()
}

fn (mut c Checker) lint_unicorn_no_hex_escape(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.literal {
				stats.checked++
				if !un_is_string_literal(t, node) && !un_is_regex_literal(t, node) {
					continue
				}
				raw := un_raw(t, node)
				fixed := unhe_fixed(raw)
				if fixed != raw {
					findings << c.unhe_finding(t, node, fix_replace_range(t.nodes[node].start,
						t.nodes[node].end, fixed))
				}
			}
			.template_element {
				stats.checked++
				if un_is_tagged_template(t, t.nodes[node].parent, ['String.raw']) {
					continue
				}
				raw := un_template_raw(t, node)
				fixed := unhe_fixed(raw)
				if fixed != raw {
					findings << c.unhe_finding(t, node, un_replace_template_element(t, node, fixed))
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) unhe_finding(t &estree.EsTree, node int, fix Fix) Finding {
	return Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: 'no-hex-escape'
		has_fix:    true
		fix:        fix
	}
}
