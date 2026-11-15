module rules

import time

// Port of the `marcrock/no-newline-if-body-class-empty` rule of @marcrock22/eslintcf 0.0.1
// (src/rules/noNewlineIfBodyClassEmptyRule.ts; it has no options), with its fix: a class body on
// more than one line with no member and no comment inside.

const mnl_messages = {
	'noNewLine': 'Empty body class should not have a newline.'
}

fn (mut c Checker) lint_marcrock_no_newline_if_body_class_empty(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .class_body {
			continue
		}
		stats.checked++
		start := t.nodes[node].start
		end := t.nodes[node].end
		start_line, _ := t.line_column(start)
		end_line, _ := t.line_column(end)
		if start_line == end_line {
			continue
		}
		body := t.list(node, .body) or { []int{} }
		if body.len != 0 || tokens.comments_inside(start, end).len != 0 {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'noNewLine'
			has_fix:    true
			fix:        fix_remove_range(start + 1, end - 1)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
