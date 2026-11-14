module rules

import estree
import json2
import time

// Port of the `unicorn/prefer-number-properties` rule of eslint-plugin-unicorn 79.0.0, with its
// fixes and suggestions, on the ReferenceTracker of eslint_utils.v (GlobalReferenceTracker's
// mergeTraceMap gives the same trace here: the six names are distinct globals).

const upnp_messages = {
	'error':      'Prefer `Number.{{property}}` over `{{description}}`.'
	'suggestion': 'Replace `{{description}}` with `Number.{{property}}`.'
}

fn upnp_options(options []json2.Any) !(bool, bool) {
	o := option_object(unicorn_prefer_number_properties, options, ['checkInfinity', 'checkNaN'])!
	return o.bool_value('checkInfinity')!, o.bool_value('checkNaN')!
}

// upnp_is_base10_or_no_radix_parse_int ports isBase10OrNoRadixParseIntCall: `parseInt(x)` or
// `parseInt(x, 10)` (a radix whose static value is 10), the same as `Number.parseInt()`.
fn (mut c Checker) upnp_is_base10_or_no_radix_parse_int(t &estree.EsTree, node int, root C.TSNode) bool {
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .call_expression || t.node(parent, .callee) or { -1 } != node {
		return false
	}
	arguments := t.list(parent, .arguments) or { []int{} }
	if arguments.len < 2 {
		return true
	}
	radix := arguments[1]
	if t.typ(radix) == .spread_element {
		return false
	}
	value := c.unb_static_value_if_no_side_effects(root, t, radix) or { return false }
	return value.value.kind == .number_ && value.value.number == 10
}

// upnp_is_call_with_number_argument ports isCallWithNumberArgument: `isNaN(x)` and `isFinite(x)`
// with one argument that is a number, which they do not coerce.
fn (mut c Checker) upnp_is_call_with_number_argument(t &estree.EsTree, node int, mut ctx UnbTypeContext) bool {
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .call_expression || t.node(parent, .callee) or { -1 } != node {
		return false
	}
	arguments := t.list(parent, .arguments) or { []int{} }
	return arguments.len == 1 && t.typ(arguments[0]) != .spread_element
		&& c.unb_is_number(t, arguments[0], mut ctx)
}

fn (mut c Checker) lint_unicorn_prefer_number_properties(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	check_infinity, check_nan := upnp_options(c.rule_options(unicorn_prefer_number_properties))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := &UnbTypeContext{
		root:     root
		abs_path: abs_path
		stats:    unsafe { &stats }
	}
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
		name := traced.path[0]
		parent := t.nodes[node].parent
		negative := t.typ(parent) == .unary_expression
			&& (t.string_of(parent, .operator) or { '' }) == '-'
			&& t.node(parent, .argument) or { -1 } == node
		// The filter: not written, not `delete -Infinity`, not a base-10 `parseInt()`.
		if unb_is_left_hand_side(t, node) || (name == 'Infinity' && negative
			&& unb_is_left_hand_side(t, parent))
			|| (name == 'parseInt' && c.upnp_is_base10_or_no_radix_parse_int(t, node, root)) {
			continue
		}
		property := if name == 'Infinity' {
			if negative { 'NEGATIVE_INFINITY' } else { 'POSITIVE_INFINITY' }
		} else {
			name
		}
		if property == 'NEGATIVE_INFINITY' {
			// The whole unary expression is replaced, so a comment between `-` and `Infinity` is lost.
			mut has_fix := false
			mut fix := Fix{}
			if tokens.comments_inside(t.nodes[parent].start, t.nodes[parent].end).len == 0 {
				mut fixes := [fix_replace_range(t.nodes[parent].start, t.nodes[parent].end, 'Number.NEGATIVE_INFINITY')]
				fixes << c.unb_fix_space_around_keyword(t, tokens, parent)
				has_fix, fix = c.merge_fixes(fixes)!
			}
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
		if name in ['parseInt', 'parseFloat', 'NaN', 'Infinity']
			|| c.upnp_is_call_with_number_argument(t, node, mut ctx) {
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
