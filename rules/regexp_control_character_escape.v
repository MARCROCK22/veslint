module rules

import estree
import time

// Port of the `regexp/control-character-escape` rule of eslint-plugin-regexp 3.3.3 (it has no
// options), with its fix: a control character that has an escape (`\0 \t \n \v \f \r`) written
// otherwise, outside ranges; the character itself is allowed in a string of the source.

const regexp_control_character_escape_messages = {
	'unexpected': "Unexpected control character escape {{actual}}. Use '{{expected}}' instead."
}

fn (mut c Checker) lint_regexp_control_character_escape(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
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
			if !event.enter || n.kind != .character
				|| ast.nodes[n.parent].kind == .character_class_range {
				continue
			}
			expected := rx_control_char_escapes[n.value] or { continue }
			raw := rx_raw(ast, event.node)
			if raw == expected {
				continue
			}
			range := rx_node_range(ast, event.node)
			if !c.rxcce_is_literal_at(t, &re, range) && ast.raw16(event.node) == rx_from_code_point(u32(n.value)) {
				continue
			}
			findings << rx_with_fix(c.rx_report(t, &re, range, 'unexpected', {
				'actual':   rx_mention_char(ast, event.node)
				'expected': expected
			}), c.rx_fix_replace_node(t, &re, range, expected))
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// rxcce_is_literal_at ports isRegExpLiteralAt: the pattern is a regular expression literal of the
// source at that range.
fn (c &Checker) rxcce_is_literal_at(t &estree.EsTree, re &RxRegExp, range RxRange) bool {
	if rx_is_regexp_literal(t, re.node) {
		return true
	}
	if replace := c.rx_replace_range(t, &re.source, range) {
		return replace.kind == .regexp
	}
	return false
}
