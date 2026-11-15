module rules

import jsregexp
import time

// Port of the `ban-tslint-comment` rule of typescript-eslint 8.72.2, with its fix. The regular
// expression runs on the UTF-16 units of the comments, as in JavaScript.

const btslc_messages = {
	'commentDetected': 'tslint comment detected: "{{ text }}"'
}

fn (mut c Checker) lint_ban_tslint_comment(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	enable_disable := jsregexp.js_regex_new(r'^\s*tslint:(enable|disable)(?:-(line|next-line))?(:|\s|$)',
		'')!
	tokens := c.source_tokens(root)
	mut checked := 0
	for comment in tokens.comments {
		checked++
		value := if comment.kind == .block_comment {
			c.src[comment.start + 2..comment.end - 2]
		} else {
			c.src[comment.start + 2..comment.end]
		}
		if !enable_disable.test(utf16_units(value))! {
			continue
		}
		// toText: a Line comment as `// …`, other comments as `/* … */`.
		text := if comment.kind == .line_comment {
			'// ${js_trim(value)}'
		} else {
			'/* ${js_trim(value)} */'
		}
		// The fix removes the comment, the UTF-16 unit before it on its line, if any, and the one
		// after it (a whole character here: half of a surrogate pair cannot be written in UTF-8).
		mut start := comment.start
		if start > 0 && c.src[start - 1] != `\n` && c.src[start - 1] != `\r`
			&& !btslc_ends_with_line_separator(c.src[..start]) {
			start = btslc_previous_char_start(c.src, start)
		}
		end := btslc_next_char_end(c.src, comment.end)
		findings << Finding{
			stmt:       c.position_range(comment.start, comment.end)
			message_id: 'commentDetected'
			data:       {
				'text': text
			}
			has_fix:    true
			fix:        fix_remove_range(start, end)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// btslc_ends_with_line_separator tells whether the text ends with U+2028 or U+2029.
fn btslc_ends_with_line_separator(text string) bool {
	return text.ends_with(' ') || text.ends_with(' ')
}

// btslc_previous_char_start is the start of the character that ends at `offset`.
fn btslc_previous_char_start(src string, offset int) int {
	mut i := offset - 1
	for i > 0 && src[i] & 0xc0 == 0x80 {
		i--
	}
	return i
}

// btslc_next_char_end is the end of the character that starts at `offset`; at the end of the text,
// one past it, as ESLint's range.
fn btslc_next_char_end(src string, offset int) int {
	if offset >= src.len {
		return offset + 1
	}
	mut i := offset + 1
	for i < src.len && src[i] & 0xc0 == 0x80 {
		i++
	}
	return i
}
