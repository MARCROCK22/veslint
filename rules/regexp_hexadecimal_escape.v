module rules

import json2
import time

// Port of the `regexp/hexadecimal-escape` rule of eslint-plugin-regexp 3.3.3 with its option
// ("always", the default, or "never") and its fix: with "always", a unicode or unicode code point
// escape of a character up to U+00FF; with "never", a hexadecimal escape.

const regexp_hexadecimal_escape_messages = {
	'expectedHexEscape':   "Expected hexadecimal escape ('{{hexEscape}}'), but {{unexpectedKind}} escape ('{{rejectEscape}}') is used."
	'unexpectedHexEscape': "Unexpected hexadecimal escape ('{{hexEscape}}')."
}

// rxhe_options is the option: true for "always".
fn rxhe_options(options []json2.Any) !bool {
	if options.len == 0 {
		return true
	}
	value := options[0]
	return !(value is string && value == 'never')
}

fn (mut c Checker) lint_regexp_hexadecimal_escape(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	always := rxhe_options(c.rule_options(regexp_hexadecimal_escape))!
	mut findings := []Finding{}
	regexps := c.rx_regexps(root, abs_path)
	t := c.es_tree(root, abs_path) or { return findings }
	for re in regexps {
		if re.kind !in [.literal, .source] {
			continue
		}
		stats.checked++
		ast := &re.ast
		for event in ast.visit_events() {
			n := ast.nodes[event.node]
			if !event.enter || n.kind != .character || n.value > 0xff {
				continue
			}
			raw := rx_raw(ast, event.node)
			kind := rx_escape_sequence_kind(raw)
			if kind == .none {
				continue
			}
			range := rx_node_range(ast, event.node)
			if always {
				if kind !in [.unicode, .unicode_code_point] {
					continue
				}
				hex := n.value.hex()
				hex_escape := '\\x${'0'.repeat(if hex.len < 2 { 2 - hex.len } else { 0 })}${hex}'
				findings << rx_with_fix(c.rx_report(t, &re, range, 'expectedHexEscape', {
					'hexEscape':      hex_escape
					'unexpectedKind': kind.str()
					'rejectEscape':   raw
				}), c.rx_fix_replace_node(t, &re, range, hex_escape))
			} else {
				if kind != .hexadecimal {
					continue
				}
				findings << rx_with_fix(c.rx_report(t, &re, range, 'unexpectedHexEscape', {
					'hexEscape': raw
				}), c.rx_fix_replace_node(t, &re, range, '\\u00${raw[2..]}'))
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
