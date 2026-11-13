module rules

import json2
import time
import treesitter { node_field, node_kind, node_parent, position_of }

// Port of the `no-labels` rule of ESLint 10.6.0, with its options.

const nl_messages = {
	'unexpectedLabel':           'Unexpected labeled statement.'
	'unexpectedLabelInBreak':    'Unexpected label in break statement.'
	'unexpectedLabelInContinue': 'Unexpected label in continue statement.'
}

struct NlOptions {
	allow_loop   bool
	allow_switch bool
}

// nl_options reads allowLoop and allowSwitch.
fn nl_options(options []json2.Any) !NlOptions {
	o := option_object(no_labels, options, ['allowLoop', 'allowSwitch'])!
	return NlOptions{
		allow_loop:   o.bool_value('allowLoop')!
		allow_switch: o.bool_value('allowSwitch')!
	}
}

fn (mut c Checker) lint_no_labels(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nl_options(c.rule_options(no_labels))!
	mut findings := []Finding{}
	kinds := ['labeled_statement', 'break_statement', 'continue_statement']
	for node in c.nodes_of_kinds(root, kinds, []) {
		stats.checked++
		if node_kind(node) == 'labeled_statement' {
			if !nl_allowed(o, nl_body_kind(node)) {
				findings << Finding{
					stmt:       position_of(node)
					message_id: 'unexpectedLabel'
				}
			}
			continue
		}
		label := node_field(node, 'label') or { continue }
		if !nl_allowed(o, c.nl_label_kind(node, c.text(label))) {
			findings << Finding{
				stmt:       position_of(node)
				message_id: if node_kind(node) == 'break_statement' {
					'unexpectedLabelInBreak'
				} else {
					'unexpectedLabelInContinue'
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nl_body_kind ports getBodyKind: 'loop', 'switch' or 'other', for the body of a labeled statement.
fn nl_body_kind(labeled C.TSNode) string {
	body := node_field(labeled, 'body') or { return 'other' }
	return match node_kind(body) {
		'for_statement', 'for_in_statement', 'while_statement', 'do_statement' { 'loop' }
		'switch_statement' { 'switch' }
		else { 'other' }
	}
}

// nl_label_kind ports getKind: the body kind of the closest enclosing statement with that label.
fn (c &Checker) nl_label_kind(n C.TSNode, label string) string {
	mut current := n
	for {
		current = node_parent(current) or { return 'other' }
		if node_kind(current) == 'labeled_statement' {
			name := node_field(current, 'label') or { continue }
			if c.text(name) == label {
				return nl_body_kind(current)
			}
		}
	}
	return 'other'
}

fn nl_allowed(o NlOptions, kind string) bool {
	return match kind {
		'loop' { o.allow_loop }
		'switch' { o.allow_switch }
		else { false }
	}
}
