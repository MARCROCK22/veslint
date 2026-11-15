module rules

import time
import x.json2

// Port of the `@stylistic/one-var-declaration-per-line` rule of @stylistic/eslint-plugin 5.10.0,
// with its option (`"initializations"`, the default, or `"always"`) and its fixes.

const sovdpl_messages = {
	'expectVarOnNewline': 'Expected variable declaration to be on a new line.'
}

fn sovdpl_options(given []json2.Any) !bool {
	options := sty_options(given, [json2.Any('initializations')])
	return sty_option_string(options, 0, 'initializations') == 'always'
}

fn (mut c Checker) lint_stylistic_one_var_declaration_per_line(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	always := sovdpl_options(c.rule_options(stylistic_one_var_declaration_per_line))!
	t := c.es_tree(root, abs_path) or { return findings }
	for step in t.steps() {
		if step.leave || t.typ(step.node) != .variable_declaration {
			continue
		}
		node := step.node
		parent := t.nodes[node].parent
		if parent >= 0 && t.typ(parent) in [.for_statement, .for_in_statement, .for_of_statement] {
			continue
		}
		stats.checked++
		declarations := t.list(node, .declarations) or { continue }
		for i := 1; i < declarations.len; i++ {
			previous := declarations[i - 1]
			current := declarations[i]
			if !sty_same_line_offsets(t, t.nodes[previous].end, t.nodes[current].start) {
				continue
			}
			if always || t.node(previous, .init) != none || t.node(current, .init) != none {
				findings << Finding{
					stmt:       c.position_range(t.nodes[current].start, t.nodes[current].end)
					message_id: 'expectVarOnNewline'
					has_fix:    true
					fix:        fix_insert_at(t.nodes[current].start, '\n')
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
