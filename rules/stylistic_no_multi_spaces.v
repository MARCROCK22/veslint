module rules

import time
import x.json2

// Port of the `@stylistic/no-multi-spaces` rule of @stylistic/eslint-plugin 6.0.1, with its
// options (`exceptions`, by node type, none by default since 6.0.0, `ignoreEOLComments` and
// `includeTabs`) and its fixes.

const snms_messages = {
	'multipleSpaces': "Multiple spaces found before '{{displayValue}}'."
}

struct SnmsOptions {
	exceptions          map[string]bool // the node types whose exception is true
	ignore_eol_comments bool
	include_tabs        bool
}

fn snms_options(given []json2.Any) !SnmsOptions {
	options := sty_options(given, decoded_default_options(stylistic_no_multi_spaces))
	object := sty_option_object(options, 0)
	mut exceptions := map[string]bool{}
	if value := object['exceptions'] {
		if value is map[string]json2.Any {
			for key, flag in value {
				if flag is bool && flag {
					exceptions[key] = true
				}
			}
		}
	}
	return SnmsOptions{
		exceptions:          exceptions
		ignore_eol_comments: sty_option_bool(object, 'ignoreEOLComments') or { false }
		include_tabs:        sty_option_bool(object, 'includeTabs') or { true }
	}
}

fn (mut c Checker) lint_stylistic_no_multi_spaces(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := snms_options(c.rule_options(stylistic_no_multi_spaces))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// A .svelte file: every token of svelte-eslint-parser, the template's markup included.
	all := if c.is_svelte() { c.svelte_file_tokens() } else { tokens.all }
	stats.checked++
	for left_index in 0 .. all.len - 1 {
		left := all[left_index]
		right := all[left_index + 1]
		// Ignore tokens that don't have 2 spaces between them or are on different lines.
		if !snms_has_spaces(c.src[left.end..right.start], options.include_tabs)
			|| !sty_same_line_offsets(t, left.end, right.start) {
			continue
		}
		// Ignore comments that are the last token on their line if `ignoreEOLComments` is active.
		if options.ignore_eol_comments && right.is_comment() && (left_index == all.len - 2
			|| !sty_same_line_offsets(t, right.end, all[left_index + 2].start)) {
			continue
		}
		// Ignore tokens that are in a node in the "exceptions" object.
		if options.exceptions.len > 0 {
			parent := sty_node_by_range_index(t, right.start - 1)
			if parent >= 0 && t.typ(parent).type_name() in options.exceptions {
				continue
			}
		}
		display_value := match right.kind {
			.block_comment { '/*${snms_comment_value(c.src[right.start + 2..right.end - 2])}*/' }
			.line_comment { '//${snms_comment_value(c.src[right.start + 2..right.end])}' }
			else { c.sty_token_value(right) }
		}
		findings << Finding{
			stmt:       c.position_range(left.end, right.start)
			message_id: 'multipleSpaces'
			data:       {
				'displayValue': display_value
			}
			has_fix:    true
			fix:        fix_replace_range(left.end, right.start, ' ')
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// snms_has_spaces is `spacesRe.test(text)`: two spaces in a row, or with `includeTabs` two of
// spaces and tabs.
fn snms_has_spaces(text string, include_tabs bool) bool {
	for i in 1 .. text.len {
		if include_tabs {
			if text[i - 1] in [` `, `\t`] && text[i] in [` `, `\t`] {
				return true
			}
		} else if text[i - 1] == ` ` && text[i] == ` ` {
			return true
		}
	}
	return false
}

// snms_comment_value ports formatReportedCommentValue: the first line of the comment's value, cut
// to 12 UTF-16 units and followed by `...` when it is longer or the comment has several lines.
fn snms_comment_value(value string) string {
	value_lines := value.split('\n')
	first := value_lines[0]
	units := utf16_units(first)
	if value_lines.len == 1 && units.len <= 12 {
		return first
	}
	cut := if units.len > 12 { units[..12] } else { units }
	return '${stv_units_string(cut)}...'
}
