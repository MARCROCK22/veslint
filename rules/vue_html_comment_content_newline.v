module rules

import json2
import time

// Port of the `vue/html-comment-content-newline` rule of eslint-plugin-vue 10.12.1 (options:
// "always", "never" or `{singleline, multiline}` (by default "never" and "always"), and
// `{exceptions}`): the line break after `<!--` (or its decoration) and before `-->` of the HTML
// comments of the template, with the fixes that add or remove it.

const vue_html_comment_content_newline_messages = {
	'expectedAfterHTMLCommentOpen':    "Expected line break after '<!--'."
	'expectedBeforeHTMLCommentOpen':   "Expected line break before '-->'."
	'expectedAfterExceptionBlock':     'Expected line break after exception block.'
	'expectedBeforeExceptionBlock':    'Expected line break before exception block.'
	'unexpectedAfterHTMLCommentOpen':  "Unexpected line breaks after '<!--'."
	'unexpectedBeforeHTMLCommentOpen': "Unexpected line breaks before '-->'."
}

struct VhccnOptions {
	singleline string
	multiline  string
	exceptions []string
}

fn vue_html_comment_content_newline_options(options []json2.Any) !VhccnOptions {
	mut singleline := 'never'
	mut multiline := 'always'
	if options.len > 0 {
		first := options[0]
		if first is string && first != '' {
			singleline = first
			multiline = first
		} else if first is map[string]json2.Any {
			if v := first['singleline'] {
				singleline = if v is string { v } else { '' }
			}
			if v := first['multiline'] {
				multiline = if v is string { v } else { '' }
			}
		}
	}
	rest := if options.len > 1 { options[1..].clone() } else { []json2.Any{} }
	o := option_object(vue_html_comment_content_newline, rest, ['exceptions'])!
	return VhccnOptions{
		singleline: singleline
		multiline:  multiline
		exceptions: o.string_list('exceptions')!
	}
}

fn (mut c Checker) lint_vue_html_comment_content_newline(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	o := vue_html_comment_content_newline_options(c.rule_options(vue_html_comment_content_newline))!
	mut findings := []Finding{}
	comments := c.vhc_comments(o.exceptions, false)
	if comments.len == 0 {
		return findings
	}
	lines := c.vhc_lines()
	for comment in comments {
		stats.checked++
		value := comment.value
		if !value.present {
			continue
		}
		start_line := vhc_line(lines, if comment.open_decoration.present {
			comment.open_decoration.end
		} else {
			value.start
		})
		end_line := vhc_line(lines, if comment.close_decoration.present {
			comment.close_decoration.start
		} else {
			value.end
		})
		newline_type := if start_line == end_line { o.singleline } else { o.multiline }
		if newline_type == 'ignore' {
			continue
		}
		requires := newline_type != 'never'
		// After `<!--`.
		before := if comment.open_decoration.present { comment.open_decoration } else { comment.open }
		before_line := vhc_line(lines, before.end)
		value_start_line := vhc_line(lines, value.start)
		if requires {
			if before_line >= value_start_line {
				f := c.vhc_report(before.end, value.start, if comment.open_decoration.present {
					'expectedAfterExceptionBlock'
				} else {
					'expectedAfterHTMLCommentOpen'
				}, {})
				findings << if comment.open_decoration.present {
					f
				} else {
					c.with_fixes(f, [fix_insert_at(before.end, '\n')])!
				}
			}
		} else if before_line != value_start_line {
			findings << c.with_fixes(c.vhc_report(before.end, value.start, 'unexpectedAfterHTMLCommentOpen',
				{}), [fix_replace_range(before.end, value.start, ' ')])!
		}
		// Before `-->`.
		after := if comment.close_decoration.present { comment.close_decoration } else { comment.close }
		value_end_line := vhc_line(lines, value.end)
		after_line := vhc_line(lines, after.start)
		if requires {
			if value_end_line >= after_line {
				f := c.vhc_report(value.end, after.start, if comment.close_decoration.present {
					'expectedBeforeExceptionBlock'
				} else {
					'expectedBeforeHTMLCommentOpen'
				}, {})
				findings << if comment.close_decoration.present {
					f
				} else {
					c.with_fixes(f, [fix_insert_at(after.start, '\n')])!
				}
			}
		} else if value_end_line != after_line {
			findings << c.with_fixes(c.vhc_report(value.end, after.start, 'unexpectedBeforeHTMLCommentOpen',
				{}), [fix_replace_range(value.end, after.start, ' ')])!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
