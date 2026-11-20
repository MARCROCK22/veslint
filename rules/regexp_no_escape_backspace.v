module rules

import time

// Port of the `regexp/no-escape-backspace` rule of eslint-plugin-regexp 3.3.3 (it has no options),
// with its suggestion: `[\b]`, the backspace escape of a character class.

const regexp_no_escape_backspace_messages = {
	'unexpected': "Unexpected '[\\b]'. Use '\\u0008' instead."
	'suggest':    "Use '\\u0008'."
}

fn (mut c Checker) lint_regexp_no_escape_backspace(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
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
			if event.enter && n.kind == .character && n.value == rx_cp_backspace
				&& rx_raw(ast, event.node) == '\\b' {
				range := rx_node_range(ast, event.node)
				mut suggestions := []Suggestion{}
				if s := rx_suggestion('suggest', {}, c.rx_fix_replace_node(t, &re, range, '\\u0008')) {
					suggestions << s
				}
				findings << Finding{
					...c.rx_report(t, &re, range, 'unexpected', {})
					suggestions: suggestions
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
