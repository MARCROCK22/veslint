module rules

import time
import treesitter { node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-extra-label` rule of ESLint 10.6.0, with its fix (it has no options).

const nel_messages = {
	'unexpected': "This label '{{name}}' is unnecessary."
}

// nel_breakable are the statements a `break` without label leaves (isBreakableStatement).
const nel_breakable = ['while_statement', 'do_statement', 'for_statement', 'for_in_statement',
	'switch_statement']

fn (mut c Checker) lint_no_extra_label(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['break_statement', 'continue_statement'], []) {
		label := node_field(node, 'label') or { continue }
		stats.checked++
		name := c.text(label)
		// The closest breakable statement or labeled statement with that name: the label is
		// unnecessary when it is the label of that breakable statement.
		mut current := node
		for {
			current = node_parent(current) or { break }
			kind := node_kind(current)
			if kind in nel_breakable {
				parent := node_parent(current) or { break }
				if node_kind(parent) == 'labeled_statement'
					&& c.text(node_field(parent, 'label') or { break }) == name {
					keyword_end := node_start(node) + (if node_kind(node) == 'break_statement' {
						5
					} else {
						8
					})
					between := c.src[keyword_end..node_start(label)]
					findings << Finding{
						stmt:       position_of(label)
						message_id: 'unexpected'
						data:       {
							'name': name
						}
						has_fix:    between.trim_space() == ''
						fix:        fix_remove_range(keyword_end, node_end(label))
					}
				}
				break
			}
			if kind == 'labeled_statement' {
				body := node_field(current, 'body') or { break }
				if node_kind(body) !in nel_breakable
					&& c.text(node_field(current, 'label') or { break }) == name {
					break
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
