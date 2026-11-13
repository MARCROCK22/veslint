module rules

import time
import treesitter { position_of }

// Port of the `no-octal-escape` rule of ESLint 10.6.0 (it has no options).

const noe_messages = {
	'octalEscapeSequence': "Don't use octal: '\\{{sequence}}'. Use '\\u....' instead."
}

fn (mut c Checker) lint_no_octal_escape(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['string'], []) {
		stats.checked++
		if sequence := noe_first_octal_escape(c.text(node)) {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'octalEscapeSequence'
				data:       {
					'sequence': sequence
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// noe_first_octal_escape is the first octal escape of the raw text of a string, as
// /^(?:[^\\]|\\.)*?\\([0-3][0-7]{1,2}|[4-7][0-7]|0(?=[89])|[1-7])/su finds it.
fn noe_first_octal_escape(raw string) ?string {
	is_octal := fn (b u8) bool {
		return b >= `0` && b <= `7`
	}
	mut i := 0
	for i < raw.len {
		if raw[i] != `\\` {
			i++
			continue
		}
		if i + 1 >= raw.len {
			return none
		}
		a := raw[i + 1]
		if a >= `0` && a <= `3` && i + 2 < raw.len && is_octal(raw[i + 2]) {
			if i + 3 < raw.len && is_octal(raw[i + 3]) {
				return raw[i + 1..i + 4]
			}
			return raw[i + 1..i + 3]
		}
		if a >= `4` && a <= `7` && i + 2 < raw.len && is_octal(raw[i + 2]) {
			return raw[i + 1..i + 3]
		}
		if a == `0` && i + 2 < raw.len && raw[i + 2] in [`8`, `9`] {
			return '0'
		}
		if a >= `1` && a <= `7` {
			return raw[i + 1..i + 2]
		}
		// `\` and the character it escapes (a UTF-8 sequence counts as one).
		i += 2
		for i < raw.len && raw[i] & 0xc0 == 0x80 {
			i++
		}
	}
	return none
}
