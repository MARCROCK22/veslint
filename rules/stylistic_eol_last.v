module rules

import time
import x.json2

// Port of the `@stylistic/eol-last` rule of @stylistic/eslint-plugin 6.0.1, with its option
// (`"always"`, the default, or `"never"`) and its fixes.

const seol_messages = {
	'missing':    'Newline required at end of file but not found.'
	'unexpected': 'Newline not allowed at end of file.'
}

fn seol_options(given []json2.Any) !string {
	return sty_option_string(sty_options(given, decoded_default_options(stylistic_eol_last)),
		0, 'always')
}

fn (mut c Checker) lint_stylistic_eol_last(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mode := seol_options(c.rule_options(stylistic_eol_last))!
	stats.checked++
	src := c.src
	ends_with_newline := src.ends_with('\n')
	// Empty source is always valid.
	if src.len == 0 {
		return findings
	}
	if mode == 'always' && !ends_with_newline {
		// File is not newline-terminated, but should be.
		findings << Finding{
			stmt:       c.position_range(src.len, -1)
			message_id: 'missing'
			text_loc:   true
			has_fix:    true
			fix:        fix_insert_at(src.len, '\n')
		}
	} else if mode == 'never' && ends_with_newline {
		// File is newline-terminated, but shouldn't be: the fix removes `(?:\r?\n)+$`.
		mut start := src.len
		for start > 0 && src[start - 1] == `\n` {
			start--
			if start > 0 && src[start - 1] == `\r` {
				start--
			}
		}
		findings << Finding{
			stmt:       c.position_range(src.len - if src.ends_with('\r\n') { 2 } else { 1 },
				src.len)
			message_id: 'unexpected'
			text_loc:   true
			has_fix:    true
			fix:        fix_remove_range(start, src.len)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
