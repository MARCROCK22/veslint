module rules

import json2
import time
import treesitter { named_children, node_field, node_kind, node_parent, position_of }

// Port of the `no-empty-pattern` rule of ESLint 10.6.0, with its option.

const nep_messages = {
	'unexpected': 'Unexpected empty {{type}} pattern.'
}

// nep_allow_parameters reads allowObjectPatternsAsParameters.
fn nep_allow_parameters(options []json2.Any) !bool {
	o := option_object(no_empty_pattern, options, ['allowObjectPatternsAsParameters'])!
	return o.bool_value('allowObjectPatternsAsParameters')!
}

fn (mut c Checker) lint_no_empty_pattern(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	allow_parameters := nep_allow_parameters(c.rule_options(no_empty_pattern))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['object_pattern', 'array_pattern'], []) {
		stats.checked++
		if node_kind(node) == 'array_pattern' {
			if es_array_elements(node).len == 0 {
				findings << Finding{
					stmt:       position_of(node)
					message_id: 'unexpected'
					data:       {
						'type': 'array'
					}
				}
			}
			continue
		}
		if named_children(node).any(node_kind(it) != 'comment') {
			continue
		}
		if allow_parameters && nep_is_parameter(node) {
			continue
		}
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'unexpected'
			data:       {
				'type': 'object'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nep_is_parameter: the pattern is a parameter, or one with an empty object as its default.
fn nep_is_parameter(pattern C.TSNode) bool {
	parameter := node_parent(pattern) or { return false }
	if node_kind(parameter) !in ['required_parameter', 'optional_parameter'] {
		return false
	}
	value := node_field(parameter, 'value') or { return true }
	object := unwrap_parens(value)
	return node_kind(object) == 'object' && !named_children(object).any(node_kind(it) != 'comment')
}
