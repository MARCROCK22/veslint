module rules

import math
import time
import treesitter { children, named_children, node_field, node_kind, position_of }

// Port of the `no-duplicate-enum-values` rule of typescript-eslint 8.62.0 (it has no options).

const ndev_messages = {
	'duplicateValue': 'Duplicate enum member value {{value}}.'
}

// NdevValue is what getMemberValue gives an initializer: a number or a string.
struct NdevValue {
	is_string bool
	number    f64
	units     []u16
}

fn (mut c Checker) lint_no_duplicate_enum_values(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	for node in c.nodes_of_kind(root, c'enum_declaration') {
		body := node_field(node, 'body') or { continue }
		mut seen := []NdevValue{}
		for member in named_children(body) {
			// A member without an initializer (or a comment) has no value.
			if node_kind(member) != 'enum_assignment' {
				continue
			}
			checked++
			value := c.ndev_value(unwrap_parens(node_field(member, 'value') or { continue })) or {
				continue
			}
			if seen.any(ndev_same(it, value)) {
				findings << Finding{
					stmt:       position_of(member)
					message_id: 'duplicateValue'
					data:       {
						'value': ndev_string(value)
					}
				}
			} else {
				seen << value
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// ndev_value ports getMemberValue: a string or number literal, `+` or `-` of a value (through
// Number(), NaN being no value), and a template literal without substitutions (its cooked text).
fn (c &Checker) ndev_value(n C.TSNode) ?NdevValue {
	match node_kind(n) {
		'string' {
			quoted := c.text(n)
			if quoted.len < 2 {
				return none
			}
			return NdevValue{
				is_string: true
				units:     cooked_units(quoted[1..quoted.len - 1], false)?
			}
		}
		'number' {
			text := c.text(n).replace('_', '')
			// A BigInt is not a number.
			if text.ends_with('n') {
				return none
			}
			return NdevValue{
				number: if is_integer_literal(text) {
					integer_to_f64(integer_literal(text)?)
				} else {
					js_atof64(text) or { return none }
				}
			}
		}
		'unary_expression' {
			operator := operator_of(n)
			if operator !in ['-', '+'] {
				return none
			}
			inner := c.ndev_value(unwrap_parens(node_field(n, 'argument')?))?
			x := if inner.is_string {
				js_string_to_number(stv_units_string(inner.units))
			} else {
				inner.number
			}
			if math.is_nan(x) {
				return none
			}
			return NdevValue{
				number: if operator == '-' { -x } else { x }
			}
		}
		'template_string' {
			if children(n).any(node_kind(it) == 'template_substitution') {
				return none
			}
			text := c.text(n)
			return NdevValue{
				is_string: true
				units:     cooked_units(text[1..text.len - 1], true)?
			}
		}
		else {
			return none
		}
	}
}

// ndev_same is Object.is: strings by their units, numbers with -0 apart from 0.
fn ndev_same(a NdevValue, b NdevValue) bool {
	if a.is_string || b.is_string {
		return a.is_string && b.is_string && a.units == b.units
	}
	return a.number == b.number && math.signbit(a.number) == math.signbit(b.number)
}

// ndev_string is String(value), what the message shows.
fn ndev_string(v NdevValue) string {
	return if v.is_string { stv_units_string(v.units) } else { js_number_to_string(v.number) }
}
