module rules

import estree
import regexpp
import time

// Port of the `regexp/no-control-character` rule of eslint-plugin-regexp 3.3.3 (it has no options),
// with its suggestion: a control character (U+0000 to U+001F) written as itself, or as a
// hexadecimal or unicode escape, in the pattern and in the source; `\0 \f \n \r \t \v` are allowed.

const regexp_no_control_character_messages = {
	'unexpected': 'Unexpected control character {{ char }}.'
	'escape':     'Use {{ escape }} instead.'
}

// rx_control_char_escapes are CONTROL_CHARS: the escape of each control character that has one.
const rx_control_char_escapes = {
	0:  '\\0'
	9:  '\\t'
	10: '\\n'
	11: '\\v'
	12: '\\f'
	13: '\\r'
}

fn (mut c Checker) lint_regexp_no_control_character(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
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
			if !event.enter || n.kind != .character || n.value > 0x1f
				|| !c.rxncc_is_bad_escape(t, &re, event.node) {
				continue
			}
			range := rx_node_range(ast, event.node)
			mut suggestions := []Suggestion{}
			if escape := rx_control_char_escapes[n.value] {
				if s := rx_suggestion('escape', {
					'escape': rx_mention(escape)
				}, c.rx_fix_replace_node(t, &re, range, escape))
				{
					suggestions << s
				}
			}
			findings << Finding{
				...c.rx_report(t, &re, range, 'unexpected', {
					'char': rx_mention_char(ast, event.node)
				})
				suggestions: suggestions
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// rxncc_is_allowed_escape_raw ports isAllowedEscapeRaw: `\0 \f \n \r \t \v`, or one of them after
// a backslash.
fn rxncc_is_allowed_escape_raw(raw string) bool {
	allowed := fn (s string) bool {
		return s.len == 2 && s[0] == `\\` && '0fnrtv'.contains(s[1..])
	}
	return allowed(raw) || (raw.len > 0 && raw[0] == `\\` && allowed(raw[1..]))
}

// rxncc_is_bad_escape_raw ports isBadEscapeRaw: the character itself, or a \x or \u escape.
fn rxncc_is_bad_escape_raw(raw []u16, cp int) bool {
	first := rx_code_point_at(raw, 0) or { return false }
	text := regexpp.utf16_to_wtf8(raw)
	return int(first) == cp || text.starts_with('\\x') || text.starts_with('\\u')
}

// rxncc_is_bad_escape ports isBadEscape: the character is written with an unwanted escape (or as
// itself) in the pattern and in the source.
fn (c &Checker) rxncc_is_bad_escape(t &estree.EsTree, re &RxRegExp, ch int) bool {
	ast := &re.ast
	raw16 := ast.raw16(ch)
	raw := regexpp.utf16_to_wtf8(raw16)
	source_raw := if range := c.rx_replace_range(t, &re.source, rx_node_range(ast, ch)) {
		c.src[range.start..range.end]
	} else {
		raw
	}
	if rxncc_is_allowed_escape_raw(raw) || rxncc_is_allowed_escape_raw(source_raw) {
		return false
	}
	value := ast.nodes[ch].value
	return rxncc_is_bad_escape_raw(raw16, value)
		|| (raw.len > 0 && raw[0] == `\\` && rxncc_is_bad_escape_raw(raw16[1..], value))
}
