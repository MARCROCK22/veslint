module rules

import estree
import time

// Port of the `regexp/no-invisible-character` rule of eslint-plugin-regexp 3.3.3 (it has no
// options), with its fix: an invisible character (other than the space) written as itself in a
// regular expression literal, or in the source of a string literal given to RegExp.

const regexp_no_invisible_character_messages = {
	'unexpected': "Unexpected invisible character. Use '{{instead}}' instead."
}

fn (mut c Checker) lint_regexp_no_invisible_character(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	regexps := c.rx_regexps(root, abs_path)
	t := c.es_tree(root, abs_path) or { return findings }
	for re in regexps {
		if re.kind == .source {
			stats.checked++
			if t.typ(re.node) == .literal {
				findings << c.rxnic_verify_string(t, re.node)
			}
			continue
		}
		if re.kind != .literal {
			continue
		}
		stats.checked++
		ast := &re.ast
		for event in ast.visit_events() {
			n := ast.nodes[event.node]
			if !event.enter || n.kind != .character {
				continue
			}
			raw := ast.raw16(event.node)
			if raw.len != 1 || raw[0] == ` ` || !rx_is_invisible(n.value) {
				continue
			}
			instead := rx_char_set_source(n.value)
			range := rx_node_range(ast, event.node)
			findings << rx_with_fix(c.rx_report(t, &re, range, 'unexpected', {
				'instead': instead
			}), c.rx_fix_replace_node(t, &re, range, instead))
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// rxnic_verify_string ports verifyString: the invisible characters of the text of a literal. As
// upstream, a space does not advance the index, so the places after one are shifted back.
fn (c &Checker) rxnic_verify_string(t &estree.EsTree, node int) []Finding {
	mut findings := []Finding{}
	start := t.nodes[node].start
	text := c.src[start..t.nodes[node].end]
	mut index := 0
	for r in text.runes() {
		if r == ` ` {
			continue
		}
		size := if r >= 0x10000 { 2 } else { 1 }
		if rx_is_invisible(int(r)) {
			instead := rx_char_set_source(int(r))
			from := rx_bytes_after_units(c.src, start, index)
			to := rx_bytes_after_units(c.src, start, index + size)
			findings << Finding{
				stmt:       c.position_range(from, to)
				message_id: 'unexpected'
				data:       {
					'instead': instead
				}
				text_loc:   true
				has_fix:    true
				fix:        fix_replace_range(from, to, instead)
			}
		}
		index += size
	}
	return findings
}
