module rules

import time

// Port of the `unicorn/no-new-array` rule of eslint-plugin-unicorn 79.0.0 (it has no options),
// with its fix and suggestion.

const unna_messages = {
	'error':  '`new Array()` is unclear in intent; use an array literal or `Array.from()`.'
	'spread': 'Spread the argument.'
}

fn (mut c Checker) lint_unicorn_no_new_array(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .new_expression {
			continue
		}
		stats.checked++
		if !un_is_new(t, node, names: ['Array'], arguments_length: 1, allow_spread: true) {
			continue
		}
		argument := (t.list(node, .arguments) or { continue })[0]
		finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'error'
		}
		start, end := t.nodes[node].start, t.nodes[node].end
		// Every replacement is built from the argument alone: comments outside it would be lost.
		if un_would_remove_comments(tokens, start, end, [un_range(t, argument)]) {
			findings << finding
			continue
		}
		mut text := c.un_text(t, argument)
		if c.un_is_parenthesized(t, tokens, argument) {
			text = '(${text})'
		}
		semicolon := if c.un_needs_semicolon(t, tokens, tokens.before(start, false), '[') {
			';'
		} else {
			''
		}
		array_literal := '${semicolon}[${text}]'
		// We are not sure how many `arguments` passed
		if t.typ(argument) == .spread_element {
			findings << Finding{
				...finding
				suggestions: [
					Suggestion{
						message_id: 'spread'
						fix:        fix_replace_range(start, end, array_literal)
					},
				]
			}
			continue
		}
		// `new Array(length)` makes holes, which no literal spells: a length, or a value that may be
		// one, is only reported.
		result := c.un_static_value_for_control_flow(mut ctx, argument) or {
			findings << finding
			continue
		}
		if result.value.kind == .number_ {
			findings << finding
			continue
		}
		findings << Finding{
			...finding
			has_fix: true
			fix:     fix_replace_range(start, end, array_literal)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
