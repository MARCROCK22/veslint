module rules

import json2
import time
import treesitter { node_kind, node_parent, node_start, position_of }

// Port of the `no-useless-computed-key` rule of ESLint 10.6.0, with its option and its fix.

const nuck_messages = {
	'unnecessarilyComputedProperty': 'Unnecessarily computed property [{{property}}] found.'
}

// nuck_class_members reads enforceForClassMembers.
fn nuck_class_members(options []json2.Any) !bool {
	o := option_object(no_useless_computed_key, options, ['enforceForClassMembers'])!
	return o.bool_value('enforceForClassMembers')!
}

fn (mut c Checker) lint_no_useless_computed_key(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	class_members := nuck_class_members(c.rule_options(no_useless_computed_key))!
	mut findings := []Finding{}
	kinds := ['pair', 'pair_pattern', 'method_definition', 'public_field_definition']
	for node in c.nodes_of_kinds(root, kinds, []) {
		parent := node_parent(node) or { continue }
		in_class := node_kind(parent) == 'class_body'
		if in_class && !class_members {
			continue
		}
		key, computed := es_property_key(node) or { continue }
		if !computed || node_kind(key) !in ['string', 'number'] || c.text(key).ends_with('n') {
			continue
		}
		stats.checked++
		value := c.literal_name(key) or { continue }
		is_string := node_kind(key) == 'string'
		// The names a computed key keeps from being special.
		useful := if !in_class {
			node_kind(parent) == 'object' && is_string && value == '__proto__'
		} else if node_kind(node) == 'public_field_definition' {
			is_string && (value == 'constructor' || (es_is_static_member(node) && value == 'prototype'))
		} else if es_is_static_member(node) {
			is_string && value == 'prototype'
		} else {
			is_string && value == 'constructor'
		}
		if useful {
			continue
		}
		has_fix, fix := c.nuck_fix(root, key)
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'unnecessarilyComputedProperty'
			data:       {
				'property': c.text(key)
			}
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nuck_fix replaces the brackets and the key with the key as written, with a space when the token
// before would join it.
fn (mut c Checker) nuck_fix(root C.TSNode, key C.TSNode) (bool, Fix) {
	tokens := c.source_tokens(root)
	mut left := tokens.before(node_start(key), false) or { return false, Fix{} }
	for c.src[left.start..left.end] != '[' {
		left = tokens.before(left.start, false) or { return false, Fix{} }
	}
	mut right := tokens.after(c.es_end(key), false) or { return false, Fix{} }
	for c.src[right.start..right.end] != ']' {
		right = tokens.after(right.end, false) or { return false, Fix{} }
	}
	if tokens.comments_exist_between(left.end, right.start) {
		return false, Fix{}
	}
	before := tokens.before(left.start, false) or { return false, Fix{} }
	first := tokens.after(node_start(key), false) or { return false, Fix{} }
	space := before.end == left.start && !c.es_can_tokens_be_adjacent(before, first)
	return true, fix_replace_range(left.start, right.end, (if space { ' ' } else { '' }) + c.text(key))
}
