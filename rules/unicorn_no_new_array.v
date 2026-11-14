module rules

import time

// Port of the `unicorn/no-new-array` rule of eslint-plugin-unicorn 64.0.0 (it has no options),
// with its fixes and suggestions.

const unna_messages = {
	'error':        '`new Array()` is unclear in intent; use either `[x]` or `Array.from({length: x})`'
	'array-length': 'The argument is the length of array.'
	'only-element': 'The argument is the only element of array.'
	'spread':       'Spread the argument.'
}

fn (mut c Checker) lint_unicorn_no_new_array(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .new_expression {
			continue
		}
		stats.checked++
		if !un_is_new(t, node, names: ['Array'], arguments_length: 1, allow_spread: true) {
			continue
		}
		argument := (t.list(node, .arguments) or { continue })[0]
		mut text := c.un_text(t, argument)
		if c.un_is_parenthesized(t, tokens, argument) {
			text = '(${text})'
		}
		semicolon := if c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false),
			'[')
		{
			';'
		} else {
			''
		}
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'error'
		}
		start, end := t.nodes[node].start, t.nodes[node].end
		// We are not sure how many `arguments` passed
		if t.typ(argument) == .spread_element {
			findings << Finding{
				...finding
				suggestions: [
					Suggestion{
						message_id: 'spread'
						fix:        fix_replace_range(start, end, '${semicolon}[${text}]')
					},
				]
			}
			continue
		}
		from_length := 'Array.from(${if text == 'length' { '{length}' } else { '{length: ${text}}' }})'
		if c.un_is_number(t, argument) {
			findings << Finding{
				...finding
				has_fix: true
				fix:     fix_replace_range(start, end, from_length)
			}
			continue
		}
		only_element := '${semicolon}[${text}]'
		result := c.un_static_value(t, argument)
		if result.found && result.value.kind != .number_ {
			findings << Finding{
				...finding
				has_fix: true
				fix:     fix_replace_range(start, end, only_element)
			}
			continue
		}
		// We don't know the argument is number or not
		finding = Finding{
			...finding
			suggestions: [
				Suggestion{
					message_id: 'array-length'
					fix:        fix_replace_range(start, end, from_length)
				},
				Suggestion{
					message_id: 'only-element'
					fix:        fix_replace_range(start, end, only_element)
				},
			]
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
