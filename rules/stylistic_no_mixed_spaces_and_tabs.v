module rules

import time
import x.json2

// Port of the `@stylistic/no-mixed-spaces-and-tabs` rule of @stylistic/eslint-plugin 6.0.1,
// with its option (`"smart-tabs"`).

const snmst_messages = {
	'mixedSpacesAndTabs': 'Mixed spaces and tabs.'
}

// snmst_options gives `smartTabs`.
fn snmst_options(given []json2.Any) !bool {
	options := sty_options(given, decoded_default_options(stylistic_no_mixed_spaces_and_tabs))
	if options.len > 0 {
		style := options[0]
		if style is string {
			return style == 'smart-tabs'
		}
	}
	return false
}

fn (mut c Checker) lint_stylistic_no_mixed_spaces_and_tabs(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	smart_tabs := snmst_options(c.rule_options(stylistic_no_mixed_spaces_and_tabs))!
	t := c.es_tree(root, abs_path) or { return findings }
	stats.checked++
	src := c.src
	// The lines of the comments but their first ones.
	mut ignored_lines := map[int]bool{}
	for comment in c.un_tokens(t).comments {
		start_line, _ := t.line_column(comment.start)
		end_line, _ := t.line_column(comment.end)
		for line in start_line + 1 .. end_line + 1 {
			ignored_lines[line] = true
		}
	}
	mut line_start := 0
	mut line_number := 1
	for {
		line_end, next_start := sntr_line_end(src, line_start)
		// The length of the match of the regular expression, 0 without one: `^(?=( +|\t+))\1(?:\t| )`
		// (a run of spaces or of tabs, then the other one) or with smartTabs
		// `^(?=(\t*))\1(?=( +))\2\t` (tabs or none, spaces, then a tab).
		mut length := 0
		mut i := line_start
		if smart_tabs {
			for i < line_end && src[i] == `\t` {
				i++
			}
			spaces := i
			for i < line_end && src[i] == ` ` {
				i++
			}
			if i > spaces && i < line_end && src[i] == `\t` {
				length = i + 1 - line_start
			}
		} else if line_start < line_end && src[line_start] in [` `, `\t`] {
			first := src[line_start]
			for i < line_end && src[i] == first {
				i++
			}
			if i < line_end && src[i] in [` `, `\t`] {
				length = i + 1 - line_start
			}
		}
		if length > 0 && line_number !in ignored_lines {
			start := line_start + length - 2
			containing := sty_node_by_range_index(t, start)
			if !(containing >= 0 && t.typ(containing) in [.literal, .template_element]) {
				findings << Finding{
					stmt:       c.position_range(start, line_start + length)
					message_id: 'mixedSpacesAndTabs'
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
