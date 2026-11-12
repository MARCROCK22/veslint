module rules

import json2
import time
import treesitter { named_children, node_field, node_kind, position_of }

// Port of the `no-self-assign` rule of ESLint 10.6.0, with its option.

const nsa_messages = {
	'selfAssignment': "'{{name}}' is assigned to itself."
}

// nsa_options reads props.
fn nsa_options(options []json2.Any) !bool {
	o := option_object(no_self_assign, options, ['props'])!
	return o.bool_value('props')!
}

fn (mut c Checker) lint_no_self_assign(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	props := nsa_options(c.rule_options(no_self_assign))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['assignment_expression', 'augmented_assignment_expression'], []) {
		if node_kind(node) == 'augmented_assignment_expression'
			&& c.text(node_field(node, 'operator') or { continue }) !in ['&&=', '||=', '??='] {
			continue
		}
		stats.checked++
		left := node_field(node, 'left') or { continue }
		right := node_field(node, 'right') or { continue }
		c.nsa_each(left, right, props, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nsa_report reports `node` (the right side): its text without white space is the name.
fn (c &Checker) nsa_report(node C.TSNode, mut findings []Finding) {
	findings << Finding{
		stmt:       position_of(node)
		message_id: 'selfAssignment'
		data:       {
			'name': c.text(node).fields().join('')
		}
	}
}

// nsa_each ports eachSelfAssignment.
fn (c &Checker) nsa_each(l C.TSNode, r C.TSNode, props bool, mut findings []Finding) {
	left := unwrap_parens(l)
	right := unwrap_parens(r)
	lk := node_kind(left)
	rk := node_kind(right)
	if es_reference_type(left) == 'Identifier' && es_reference_type(right) == 'Identifier'
		&& lk != 'property_identifier' && rk != 'property_identifier' {
		if c.identifier_name(left) == c.identifier_name(right) {
			c.nsa_report(right, mut findings)
		}
	} else if lk == 'array_pattern' && rk == 'array' {
		left_elements := es_array_elements(left)
		right_elements := es_array_elements(right)
		end := if left_elements.len < right_elements.len {
			left_elements.len
		} else {
			right_elements.len
		}
		for i in 0 .. end {
			le := left_elements[i]
			re := right_elements[i]
			// Avoid cases such as [...a] = [...a, 1]
			if !le.hole && node_kind(le.node) == 'rest_pattern' && i < right_elements.len - 1 {
				break
			}
			if !le.hole && !re.hole {
				c.nsa_each(le.node, re.node, props, mut findings)
			}
			// After a spread element, those indices are unknown.
			if !re.hole && node_kind(re.node) == 'spread_element' {
				break
			}
		}
	} else if lk == 'rest_pattern' && rk == 'spread_element' {
		la := first_named(left) or { return }
		ra := first_named(right) or { return }
		c.nsa_each(la, ra, props, mut findings)
	} else if lk == 'object_pattern' && rk == 'object' {
		right_properties := named_children(right).filter(node_kind(it) != 'comment')
		if right_properties.len == 0 {
			return
		}
		mut start := 0
		for i := right_properties.len - 1; i >= 0; i-- {
			if node_kind(right_properties[i]) == 'spread_element' {
				start = i + 1
				break
			}
		}
		for lp in named_children(left).filter(node_kind(it) != 'comment') {
			for j in start .. right_properties.len {
				c.nsa_property(lp, right_properties[j], props, mut findings)
			}
		}
	} else if props && es_reference_type(left) == 'MemberExpression'
		&& es_reference_type(right) == 'MemberExpression' && c.es_is_same_reference(left, right, false) {
		c.nsa_report(right, mut findings)
	}
}

// nsa_property is the case of two Properties: the right one an `init` that is not a method, both
// with the same static name; then their values.
fn (c &Checker) nsa_property(left C.TSNode, right C.TSNode, props bool, mut findings []Finding) {
	left_name, left_value := c.nsa_property_parts(left) or { return }
	if node_kind(right) !in ['pair', 'shorthand_property_identifier'] {
		return
	}
	right_name, right_value := c.nsa_property_parts(right) or { return }
	if left_name == right_name {
		c.nsa_each(left_value, right_value, props, mut findings)
	}
}

// nsa_property_parts are the static name (getStaticPropertyName) and the value of a Property of
// an object literal or pattern; none for another node, or a name that is not static.
fn (c &Checker) nsa_property_parts(n C.TSNode) ?(string, C.TSNode) {
	match node_kind(n) {
		'pair', 'pair_pattern' {
			name := c.core_static_property_name(node_field(n, 'key'))?
			return name, node_field(n, 'value')?
		}
		'shorthand_property_identifier', 'shorthand_property_identifier_pattern' {
			return c.identifier_name(n), n
		}
		'object_assignment_pattern' {
			// `{ a = 1 }`: its value is an AssignmentPattern, which nothing matches.
			left := node_field(n, 'left')?
			return c.identifier_name(left), n
		}
		else {
			return none
		}
	}
}
