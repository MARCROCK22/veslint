module rules

import time

// Port of the `unicorn/consistent-template-literal-escape` rule of eslint-plugin-unicorn 64.0.0
// (it has no options), with its fix.

const uctle_messages = {
	'consistent-template-literal-escape': 'Use `\\\${` instead of `\$\\{` to escape in template literals.'
}

// uctle_fixed is `raw.replaceAll(/(?<=(?:^|[^\\])(?:\\\\)*)\\?\$\\{/g, '\\${')`.
fn uctle_fixed(raw string) string {
	mut out := []u8{cap: raw.len}
	mut i := 0
	for i < raw.len {
		if !un_is_escaped_at(raw, i) {
			if raw[i..].starts_with('\\$\\{') {
				out << '\\\${'.bytes()
				i += 4
				continue
			}
			if raw[i..].starts_with('$\\{') {
				out << '\\\${'.bytes()
				i += 3
				continue
			}
		}
		out << raw[i]
		i++
	}
	return out.bytestr()
}

fn (mut c Checker) lint_unicorn_consistent_template_literal_escape(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .template_element {
			continue
		}
		stats.checked++
		if un_is_tagged_template(t, t.nodes[node].parent, []) {
			continue
		}
		raw := un_template_raw(t, node)
		fixed := uctle_fixed(raw)
		if fixed != raw {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'consistent-template-literal-escape'
				has_fix:    true
				fix:        un_replace_template_element(t, node, fixed)
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
