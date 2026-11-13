module rules

import esquery
import json2
import time

// Port of the `no-restricted-syntax` rule of ESLint 10.6.0: each option is a selector, run on the
// ESTree of the file by the esquery module the way ESLint's traverser runs listeners.

const nrsx_messages = {
	'restrictedSyntax': '{{message}}'
}

struct NrsxOptions {
	selectors []string
	messages  []string
}

fn nrsx_options(options []json2.Any) !NrsxOptions {
	mut selectors := []string{}
	mut messages := []string{}
	for item in options {
		if item is string {
			selectors << item
			messages << "Using '${item}' is not allowed."
			continue
		}
		if item is map[string]json2.Any {
			selector := item['selector'] or { json2.Any('') }
			if selector !is string {
				return error('invalid option of `${no_restricted_syntax}`: a selector must be a string')
			}
			text := selector as string
			message := item['message'] or { json2.Any('') }
			selectors << text
			messages << if message is string && message != '' {
				message
			} else {
				"Using '${text}' is not allowed."
			}
			continue
		}
		return error('invalid option of `${no_restricted_syntax}`: a selector or an object with one')
	}
	return NrsxOptions{
		selectors: selectors
		messages:  messages
	}
}

fn (mut c Checker) lint_no_restricted_syntax(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	opts := nrsx_options(c.rule_options(no_restricted_syntax))!
	mut findings := []Finding{}
	if opts.selectors.len == 0 {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	// A selector given twice is one listener, with the message of the last one.
	for m in esquery.run(t, opts.selectors)! {
		stats.checked++
		findings << Finding{
			stmt:       c.position_at(t.nodes[m.node].start)
			message_id: 'restrictedSyntax'
			data:       {
				'message': opts.messages[m.selector]
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
