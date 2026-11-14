module rules

import estree
import json2
import time

// Port of the `unicorn/escape-case` rule of eslint-plugin-unicorn 64.0.0, with its fix.

const uec_messages = {
	'escape-uppercase': 'Use uppercase characters for the value of the escape sequence.'
	'escape-lowercase': 'Use lowercase characters for the value of the escape sequence.'
}

fn uec_options(options []json2.Any) !bool {
	if options.len == 0 {
		return false
	}
	value := options[0]
	return value is string && value == 'lowercase'
}

fn uec_is_hex(b u8) bool {
	return b.is_digit() || (b >= `a` && b <= `f`) || (b >= `A` && b <= `F`)
}

// uec_match is the length of the escape data that starts at `i` (`x41`, `u0041`, `u{41}` and, in a
// pattern, `cA`), 0 if none.
fn uec_match(text string, i int, pattern bool) int {
	rest := text[i..]
	if rest.len >= 3 && rest[0] == `x` && uec_is_hex(rest[1]) && uec_is_hex(rest[2]) {
		return 3
	}
	if rest.len >= 5 && rest[0] == `u` && rest[1..5].bytes().all(uec_is_hex(it)) {
		return 5
	}
	if rest.len >= 4 && rest[0] == `u` && rest[1] == `{` && uec_is_hex(rest[2]) {
		mut j := 2
		for j < rest.len && uec_is_hex(rest[j]) {
			j++
		}
		if j < rest.len && rest[j] == `}` {
			return j + 1
		}
	}
	if pattern && rest.len >= 2 && rest[0] == `c` && rest[1].is_letter() {
		return 2
	}
	return 0
}

// uec_fixed is `original.replace(regex, data => data[0] + data.slice(1)[case]())`.
fn uec_fixed(original string, pattern bool, lowercase bool) string {
	mut out := []u8{cap: original.len}
	mut i := 0
	for i < original.len {
		if un_is_escaped_at(original, i) {
			length := uec_match(original, i, pattern)
			if length > 0 {
				data := original[i..i + length]
				out << data[0]
				out << (if lowercase { data[1..].to_lower() } else { data[1..].to_upper() }).bytes()
				i += length
				continue
			}
		}
		out << original[i]
		i++
	}
	return out.bytestr()
}

fn (mut c Checker) lint_unicorn_escape_case(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	lowercase := uec_options(c.rule_options(unicorn_escape_case))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.literal {
				stats.checked++
				regex := un_is_regex_literal(t, node)
				if !un_is_string_literal(t, node) && !regex {
					continue
				}
				raw := un_raw(t, node)
				fixed := uec_fixed(raw, regex, lowercase)
				if fixed != raw {
					findings << c.uec_finding(t, node, lowercase, fix_replace_range(t.nodes[node].start,
						t.nodes[node].end, fixed))
				}
			}
			.template_element {
				stats.checked++
				if un_is_tagged_template(t, t.nodes[node].parent, ['String.raw']) {
					continue
				}
				raw := un_template_raw(t, node)
				fixed := uec_fixed(raw, false, lowercase)
				if fixed != raw {
					findings << c.uec_finding(t, node, lowercase, un_replace_template_element(t,
						node, fixed))
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) uec_finding(t &estree.EsTree, node int, lowercase bool, fix Fix) Finding {
	return Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: if lowercase { 'escape-lowercase' } else { 'escape-uppercase' }
		has_fix:    true
		fix:        fix
	}
}
