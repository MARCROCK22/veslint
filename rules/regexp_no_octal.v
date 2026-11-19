module rules

import time

// Port of the `regexp/no-octal` rule of eslint-plugin-regexp 3.3.3 (it has no options), with its
// suggestion: an octal escape other than `\0`, outside a character class unless it starts with
// `\0`.

const regexp_no_octal_messages = {
	'unexpected': "Unexpected octal escape sequence '{{expr}}'."
	'replaceHex': 'Replace the octal escape sequence with a hexadecimal escape sequence.'
}

fn (mut c Checker) lint_regexp_no_octal(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
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
			if !event.enter || n.kind != .character {
				continue
			}
			raw := rx_raw(ast, event.node)
			if raw == '\\0' || !rx_is_octal_escape(raw) {
				continue
			}
			parent_kind := ast.nodes[n.parent].kind
			if !raw.starts_with('\\0') && parent_kind in [.character_class, .character_class_range] {
				continue
			}
			range := rx_node_range(ast, event.node)
			hex := n.value.hex()
			mut suggestions := []Suggestion{}
			if s := rx_suggestion('replaceHex', {}, c.rx_fix_replace_node(t, &re, range, '\\x${'0'.repeat(if hex.len < 2 {
				2 - hex.len
			} else {
				0
			})}${hex}'))
			{
				suggestions << s
			}
			findings << Finding{
				...c.rx_report(t, &re, range, 'unexpected', {
					'expr': raw
				})
				suggestions: suggestions
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
