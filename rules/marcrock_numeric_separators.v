module rules

import time
import estree

// Port of the `marcrock/numeric-separators` rule of @marcrock22/eslintcf 0.0.1
// (src/rules/numericSeparators.ts; it has no options), with its fix: a number or BigInt literal
// whose digits are not grouped by three with `_`, except one written with `e`, `0x` or `0b`.

const mns_messages = {
	'numericSeparators': 'Number its not using numeric separators as expected'
}

fn (mut c Checker) lint_marcrock_numeric_separators(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .literal {
			continue
		}
		value := t.get(node, .value)
		if value !is f64 && value !is estree.BigIntValue {
			continue
		}
		stats.checked++
		raw := t.string_of(node, .raw) or { continue }
		if raw.contains('e') || raw.contains('0x') || raw.contains('0b') {
			continue
		}
		// node.raw.replaceAll('_', '').split('.'): the part before the dot and the one after it.
		parts := raw.replace('_', '').split('.')
		first := parts[0]
		second := if parts.len > 1 { parts[1] } else { '' }
		result := mns_parse_number(first) + if second != '' {
			'.' + mns_parse_number(second)
		} else {
			''
		}
		if result == raw {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'numericSeparators'
			has_fix:    true
			fix:        fix_replace_range(t.nodes[node].start, t.nodes[node].end, result)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// mns_parse_number is the rule's parseNumber: `str.replaceAll(/\B(?<!\.\d*)(?=(\d{3})+(?!\d))/g,
// '_')` on a part without a dot or `_`, whose characters are all word characters: a `_` before
// each position inside it where a run of digits that is a multiple of three long starts.
fn mns_parse_number(str string) string {
	mut out := []u8{cap: str.len + str.len / 3}
	for p in 0 .. str.len {
		if p > 0 {
			mut run := 0
			for q in p .. str.len {
				if !str[q].is_digit() {
					break
				}
				run++
			}
			if run >= 3 && run % 3 == 0 {
				out << `_`
			}
		}
		out << str[p]
	}
	return out.bytestr()
}
