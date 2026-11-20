module rules

import time

// Port of the `regexp/no-standalone-backslash` rule of eslint-plugin-regexp 3.3.3 (it has no
// options): a `\` that is a character of its own (Annex B).

const regexp_no_standalone_backslash_messages = {
	'unexpected': "Unexpected standalone backslash (`\\`). It looks like an escape sequence, but it's a single `\\` character pattern."
}

fn (mut c Checker) lint_regexp_no_standalone_backslash(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
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
			if event.enter && n.kind == .character && n.value == `\\`
				&& rx_raw(ast, event.node) == '\\' {
				findings << c.rx_report(t, &re, rx_node_range(ast, event.node), 'unexpected',
					{})
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
