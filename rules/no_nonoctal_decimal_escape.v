module rules

import time
import treesitter { node_start }

// Port of the `no-nonoctal-decimal-escape` rule of ESLint 10.6.0, with its suggestions (it has no
// options).

const nnde_messages = {
	'decimalEscape':   "Don't use '{{decimalEscape}}' escape sequence."
	'refactor':        "Replace '{{original}}' with '{{replacement}}'. This maintains the current functionality."
	'escapeBackslash': "Replace '{{original}}' with '{{replacement}}' to include the actual backslash character."
}

fn (mut c Checker) lint_no_nonoctal_decimal_escape(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['string'], []) {
		stats.checked++
		raw := c.text(node)
		if !raw.contains('\\8') && !raw.contains('\\9') {
			continue
		}
		start := node_start(node)
		// /(?:[^\\]|(?<previousEscape>\\.))*?(?<decimalEscape>\\[89])/suy, match after match.
		mut i := 0
		mut previous := ''
		for i < raw.len {
			if raw[i] != `\\` {
				// A character between them resets the group (each iteration of the quantifier does).
				previous = ''
				i++
				continue
			}
			if i + 1 < raw.len && raw[i + 1] in [`8`, `9`] {
				decimal := raw[i..i + 2]
				escape_start := start + i
				escape_end := escape_start + 2
				mut suggestions := []Suggestion{}
				if previous == '\\0' {
					suggestions << c.nnde_suggestion('refactor', escape_start - previous.len,
						escape_end, '\\u0000${decimal[1..]}')!
					suggestions << c.nnde_suggestion('refactor', escape_start, escape_end,
						'\\u003${decimal[1..]}')!
				} else {
					suggestions << c.nnde_suggestion('refactor', escape_start, escape_end,
						decimal[1..])!
				}
				suggestions << c.nnde_suggestion('escapeBackslash', escape_start, escape_end,
					'\\${decimal}')!
				findings << Finding{
					stmt:        c.position_at(escape_start)
					message_id:  'decimalEscape'
					data:        {
						'decimalEscape': decimal
					}
					suggestions: suggestions
				}
				// The next match starts after this one: no previous escape yet.
				previous = ''
				i += 2
				continue
			}
			// `\` and the character it escapes.
			mut next := i + 2
			for next < raw.len && raw[next] & 0xc0 == 0x80 {
				next++
			}
			previous = raw[i..if next > raw.len { raw.len } else { next }]
			i = next
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (mut c Checker) nnde_suggestion(message_id string, start int, end int, replacement string) !Suggestion {
	_, suggestion := c.suggestion(message_id, {
		'original':    c.src[start..end]
		'replacement': replacement
	}, [fix_replace_range(start, end, replacement)])!
	return suggestion
}
