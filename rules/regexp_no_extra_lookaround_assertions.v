module rules

import time

// Port of the `regexp/no-extra-lookaround-assertions` rule of eslint-plugin-regexp 3.3.3 (it has no
// options), with its fix: a positive lookahead at the end (lookbehind at the start) of an
// alternative of a lookaround of the same kind, which can be inlined or made a group.

const regexp_no_extra_lookaround_assertions_messages = {
	'canBeInlined':            'This {{kind}} assertion is useless and can be inlined.'
	'canBeConvertedIntoGroup': 'This {{kind}} assertion is useless and can be converted into a group.'
}

fn (mut c Checker) lint_regexp_no_extra_lookaround_assertions(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
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
			if !event.enter || n.kind != .assertion || n.assertion_kind !in [.lookahead, .lookbehind] {
				continue
			}
			for alternative in n.alternatives {
				elements := ast.nodes[alternative].elements
				if elements.len == 0 {
					continue
				}
				nested := if n.assertion_kind == .lookahead { elements.last() } else { elements[0] }
				m := ast.nodes[nested]
				if m.kind != .assertion || m.assertion_kind != n.assertion_kind || m.negate {
					continue
				}
				message_id, replace_text := if m.alternatives.len == 1 {
					'canBeInlined', rx_raw(ast, m.alternatives[0])
				} else {
					'canBeConvertedIntoGroup', '(?:${m.alternatives.map(rx_raw(ast, it)).join('|')})'
				}
				range := rx_node_range(ast, nested)
				findings << rx_with_fix(c.rx_report(t, &re, range, message_id, {
					'kind': m.assertion_kind.str()
				}), c.rx_fix_replace_node(t, &re, range, replace_text))
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
