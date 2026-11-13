module rules

import regexpp
import time
import treesitter { position_of }

// Port of the `no-empty-character-class` rule of ESLint 10.6.0 (it has no options).

const necc_messages = {
	'unexpected': 'Empty class.'
}

fn (mut c Checker) lint_no_empty_character_class(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['regex'], []) {
		stats.checked++
		pattern, flags := c.es_regex_literal(node) or { continue }
		// QUICK_TEST_REGEX: /\[\]/u
		if !stv_units_string(pattern).contains('[]') {
			continue
		}
		ast := regexpp.parse_pattern(pattern, 0, pattern.len, es_regex_pattern_flags(flags),
			regexpp.Options{}) or { continue }
		for event in ast.visit_events() {
			if !event.enter {
				continue
			}
			class := ast.nodes[event.node]
			if class.kind == .character_class && !class.negate && class.elements.len == 0 {
				findings << Finding{
					stmt:       position_of(node)
					message_id: 'unexpected'
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
