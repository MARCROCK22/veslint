module rules

import time
import x.json2

// Port of the `@stylistic/no-trailing-spaces` rule of @stylistic/eslint-plugin 5.10.0, with its
// options (`skipBlankLines` and `ignoreComments`) and its fixes.

const sntr_messages = {
	'trailingSpace': 'Trailing spaces not allowed.'
}

struct SntrOptions {
	skip_blank_lines bool
	ignore_comments  bool
}

fn sntr_options(given []json2.Any) !SntrOptions {
	options := sty_options(given, decoded_default_options(stylistic_no_trailing_spaces))
	object := sty_option_object(options, 0)
	return SntrOptions{
		skip_blank_lines: sty_option_bool(object, 'skipBlankLines') or { false }
		ignore_comments:  sty_option_bool(object, 'ignoreComments') or { false }
	}
}

fn (mut c Checker) lint_stylistic_no_trailing_spaces(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := sntr_options(c.rule_options(stylistic_no_trailing_spaces))!
	t := c.es_tree(root, abs_path) or { return findings }
	stats.checked++
	src := c.src
	// getCommentLineNumbers: the lines of the comments, but the last one of a block comment.
	mut comment_lines := map[int]bool{}
	if options.ignore_comments {
		tokens := c.un_tokens(t)
		for comment in tokens.comments {
			start_line, _ := t.line_column(comment.start)
			mut end_line, _ := t.line_column(comment.end)
			if comment.kind == .block_comment {
				end_line--
			}
			for line in start_line .. end_line + 1 {
				comment_lines[line] = true
			}
		}
	}
	mut line_start := 0
	mut line_number := 1
	for {
		line_end, next_start := sntr_line_end(src, line_start)
		// The trailing run of blanks (BLANK_CLASS: space, tab, U+00A0, U+2000 to U+200B, U+3000).
		mut blank_start := line_end
		for blank_start > line_start {
			mut first := blank_start - 1
			for first > line_start && src[first] & 0xc0 == 0x80 {
				first--
			}
			if !sntr_is_blank(src[first..blank_start]) {
				break
			}
			blank_start = first
		}
		if blank_start < line_end {
			mut skip := false
			containing := sty_node_by_range_index(t, blank_start)
			if containing >= 0 && t.typ(containing) == .template_element {
				parent := t.nodes[containing].parent
				if parent >= 0 && blank_start > t.nodes[parent].start
					&& line_end < t.nodes[parent].end {
					skip = true
				}
			}
			// If the line has only white space and skipBlankLines is true, don't report it.
			if options.skip_blank_lines && blank_start == line_start {
				skip = true
			}
			if !skip && !(options.ignore_comments && line_number in comment_lines) {
				findings << Finding{
					stmt:       c.position_range(blank_start, line_end)
					message_id: 'trailingSpace'
					has_fix:    true
					fix:        fix_remove_range(blank_start, line_end)
				}
			}
		}
		if next_start < 0 {
			break
		}
		line_start = next_start
		line_number++
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sntr_is_blank tells whether a character (its UTF-8 bytes) is one of BLANK_CLASS.
fn sntr_is_blank(ch string) bool {
	if ch == ' ' || ch == '\t' {
		return true
	}
	if ch.len < 2 {
		return false
	}
	r := ch.runes()[0]
	return r == 0xa0 || (r >= 0x2000 && r <= 0x200b) || r == 0x3000
}

// sntr_line_end gives where the line that starts at `start` ends (before its line break: `\r\n`,
// `\r`, `\n`, U+2028 or U+2029, the lines of SourceCode) and where the next one starts, -1 for the
// last line.
fn sntr_line_end(src string, start int) (int, int) {
	mut i := start
	for i < src.len {
		b := src[i]
		if b == `\n` {
			return i, i + 1
		}
		if b == `\r` {
			return i, if i + 1 < src.len && src[i + 1] == `\n` { i + 2 } else { i + 1 }
		}
		if b == 0xe2 && i + 2 < src.len && src[i + 1] == 0x80
			&& (src[i + 2] == 0xa8 || src[i + 2] == 0xa9) {
			return i, i + 3
		}
		i++
	}
	return src.len, -1
}
