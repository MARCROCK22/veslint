module rules

import json2
import time

// Port of the `unicorn/prefer-number-properties` rule of eslint-plugin-unicorn 64.0.0, with its
// fixes and suggestions, on the ReferenceTracker of eslint_utils.v.

const upnp_messages = {
	'error':      'Prefer `Number.{{property}}` over `{{description}}`.'
	'suggestion': 'Replace `{{description}}` with `Number.{{property}}`.'
}

fn upnp_options(options []json2.Any) !(bool, bool) {
	o := option_object(unicorn_prefer_number_properties, options, ['checkInfinity', 'checkNaN'])!
	check_nan := o.values['checkNaN'] or { json2.Any(true) }
	return o.bool_value('checkInfinity')!, check_nan is bool && check_nan
}

fn (mut c Checker) lint_unicorn_prefer_number_properties(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	check_infinity, check_nan := upnp_options(c.rule_options(unicorn_prefer_number_properties))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut trace := map[string]EsTrace{}
	for name in ['parseInt', 'parseFloat', 'NaN', 'Infinity', 'isNaN', 'isFinite'] {
		if (name == 'Infinity' && !check_infinity) || (name == 'NaN' && !check_nan) {
			continue
		}
		trace[name] = EsTrace{
			read: true
		}
	}
	for traced in c.es_global_references(root, trace) {
		stats.checked++
		node := c.un_reference_node(t, traced.node) or { continue }
		if un_is_left_hand_side(t, node) {
			continue
		}
		name := traced.path[0]
		parent := t.nodes[node].parent
		negative := t.typ(parent) == .unary_expression
			&& (t.string_of(parent, .operator) or { '' }) == '-'
			&& t.node(parent, .argument) or { -1 } == node
		property := if name == 'Infinity' {
			if negative { 'NEGATIVE_INFINITY' } else { 'POSITIVE_INFINITY' }
		} else {
			name
		}
		if property == 'NEGATIVE_INFINITY' {
			mut fixes := [fix_replace_range(t.nodes[parent].start, t.nodes[parent].end, 'Number.NEGATIVE_INFINITY')]
			fixes << c.un_fix_space_around_keyword(t, tokens, parent)
			has_fix, fix := c.merge_fixes(fixes)!
			findings << Finding{
				stmt:       c.es_tree_position(t, parent)
				message_id: 'error'
				data:       {
					'description': '-Infinity'
					'property':    property
				}
				has_fix:    has_fix
				fix:        fix
			}
			continue
		}
		data := {
			'description': name
			'property':    property
		}
		fix := c.un_replace_reference_identifier(t, node, 'Number.${property}')
		if name in ['parseInt', 'parseFloat', 'NaN', 'Infinity'] {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'error'
				data:       data
				has_fix:    true
				fix:        fix
			}
		} else {
			findings << Finding{
				stmt:        c.es_tree_position(t, node)
				message_id:  'error'
				data:        data
				suggestions: [
					Suggestion{
						message_id: 'suggestion'
						data:       data
						fix:        fix
					},
				]
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
