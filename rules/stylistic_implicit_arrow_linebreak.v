module rules

import time
import x.json2

// Port of the `@stylistic/implicit-arrow-linebreak` rule of @stylistic/eslint-plugin 6.0.1, with
// its option (`"beside"`, the default, or `"below"`) and its fixes.

const sial_messages = {
	'expected':   'Expected a linebreak before this expression.'
	'unexpected': 'Expected no linebreak before this expression.'
}

fn sial_options(given []json2.Any) !bool {
	options := sty_options(given, [json2.Any('beside')])
	return sty_option_string(options, 0, 'beside') == 'below'
}

fn (mut c Checker) lint_stylistic_implicit_arrow_linebreak(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	below := sial_options(c.rule_options(stylistic_implicit_arrow_linebreak))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave || t.typ(step.node) != .arrow_function_expression {
			continue
		}
		stats.checked++
		body := t.node(step.node, .body) or { continue }
		if t.typ(body) == .block_statement {
			continue
		}
		// getTokenBefore(node.body, isNotOpeningParenToken)
		mut index := source_tokens_index(tokens.tokens, t.nodes[body].start) - 1
		for index >= 0 && c.token_is(tokens.tokens[index], '(') {
			index--
		}
		if index < 0 {
			continue
		}
		arrow := tokens.tokens[index]
		first := tokens.after(arrow.end, false) or { continue }
		on_same_line := sty_same_line(t, arrow, first)
		if on_same_line && below {
			findings << Finding{
				stmt:       c.position_range(first.start, first.end)
				message_id: 'expected'
				has_fix:    true
				fix:        fix_insert_at(first.start, '\n')
			}
		} else if !on_same_line && !below {
			fix := sfcs_safe_replace(tokens, arrow, first, ' ')
			findings << Finding{
				stmt:       c.position_range(first.start, first.end)
				message_id: 'unexpected'
				has_fix:    fix != none
				fix:        fix or { Fix{} }
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
