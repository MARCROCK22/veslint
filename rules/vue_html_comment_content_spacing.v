module rules

import json2
import time

// Port of the `vue/html-comment-content-spacing` rule of eslint-plugin-vue 10.12.1 (options:
// "always", the default, or "never", and `{exceptions}`): the space after `<!--` (or its
// decoration) and before `-->` of the HTML comments of the template, with the fixes that add or
// remove it.

const vue_html_comment_content_spacing_messages = {
	'expectedAfterHTMLCommentOpen':    "Expected space after '<!--'."
	'expectedBeforeHTMLCommentOpen':   "Expected space before '-->'."
	'expectedAfterExceptionBlock':     'Expected space after exception block.'
	'expectedBeforeExceptionBlock':    'Expected space before exception block.'
	'unexpectedAfterHTMLCommentOpen':  "Unexpected space after '<!--'."
	'unexpectedBeforeHTMLCommentOpen': "Unexpected space before '-->'."
}

struct VhccsOptions {
	requires_space bool
	exceptions     []string
}

fn vue_html_comment_content_spacing_options(options []json2.Any) !VhccsOptions {
	requires_space := !(options.len > 0 && options[0] is string && options[0] as string == 'never')
	rest := if options.len > 1 { options[1..].clone() } else { []json2.Any{} }
	o := option_object(vue_html_comment_content_spacing, rest, ['exceptions'])!
	return VhccsOptions{
		requires_space: requires_space
		exceptions:     o.string_list('exceptions')!
	}
}

fn (mut c Checker) lint_vue_html_comment_content_spacing(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	o := vue_html_comment_content_spacing_options(c.rule_options(vue_html_comment_content_spacing))!
	mut findings := []Finding{}
	comments := c.vhc_comments(o.exceptions, true)
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
		// After `<!--`.
		before := if comment.open_decoration.present { comment.open_decoration } else { comment.open }
		if vhc_line(lines, before.end) == vhc_line(lines, value.start) {
			if o.requires_space {
				if before.end >= value.start {
					f := c.vhc_report(before.end, value.start, if comment.open_decoration.present {
						'expectedAfterExceptionBlock'
					} else {
						'expectedAfterHTMLCommentOpen'
					}, {})
					findings << if comment.open_decoration.present {
						f
					} else {
						c.with_fixes(f, [fix_insert_at(before.end, ' ')])!
					}
				}
			} else if !comment.open_decoration.present && before.end != value.start {
				findings << c.with_fixes(c.vhc_report(before.end, value.start, 'unexpectedAfterHTMLCommentOpen',
					{}), [fix_remove_range(before.end, value.start)])!
			}
		}
		// Before `-->`.
		after := if comment.close_decoration.present { comment.close_decoration } else { comment.close }
		if vhc_line(lines, value.end) == vhc_line(lines, after.start) {
			if o.requires_space {
				if value.end >= after.start {
					f := c.vhc_report(value.end, after.start, if comment.close_decoration.present {
						'expectedBeforeExceptionBlock'
					} else {
						'expectedBeforeHTMLCommentOpen'
					}, {})
					findings << if comment.close_decoration.present {
						f
					} else {
						c.with_fixes(f, [fix_insert_at(after.start, ' ')])!
					}
				}
			} else if !comment.close_decoration.present && value.end != after.start {
				findings << c.with_fixes(c.vhc_report(value.end, after.start, 'unexpectedBeforeHTMLCommentOpen',
					{}), [fix_remove_range(value.end, after.start)])!
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
