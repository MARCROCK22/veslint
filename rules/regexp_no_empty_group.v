module rules

import time

// Port of the `regexp/no-empty-group` rule of eslint-plugin-regexp 3.3.3 (it has no options): a
// group or capturing group whose alternatives are all empty.

const regexp_no_empty_group_messages = {
	'unexpected': 'Unexpected empty group.'
}

fn (mut c Checker) lint_regexp_no_empty_group(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
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
			if !event.enter || n.kind !in [.group, .capturing_group] {
				continue
			}
			if n.alternatives.all(ast.nodes[it].elements.len == 0) {
				findings << c.rx_report(t, &re, rx_node_range(ast, event.node), 'unexpected',
					{})
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
