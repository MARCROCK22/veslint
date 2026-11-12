module rules

import time
import tsgo { TypeResponse }
import treesitter { nodes_of_kinds, position_of }

// Port of the `no-unsafe-type-assertion` rule of typescript-eslint 8.62.0 (it has no options).

const nusta_messages = {
	'unsafeOfAnyTypeAssertion':                  'Unsafe assertion from {{type}} detected: consider using type guards or a safer assertion.'
	'unsafeToAnyTypeAssertion':                  'Unsafe assertion to {{type}} detected: consider using a more specific type to ensure safety.'
	'unsafeToUnconstrainedTypeAssertion':        "Unsafe type assertion: '{{type}}' could be instantiated with an arbitrary type which could be unrelated to the original type."
	'unsafeTypeAssertion':                       "Unsafe type assertion: type '{{type}}' is more narrow than the original type."
	'unsafeTypeAssertionAssignableToConstraint': "Unsafe type assertion: the original type is assignable to the constraint of type '{{type}}', but '{{type}}' could be instantiated with a different subtype of its constraint."
}

// ObjectFlags.ObjectLiteral.
const object_flag_object_literal = u32(128)

struct NustaAssertion {
	node       C.TSNode
	expression C.TSNode
	type_node  C.TSNode
}

fn (mut c Checker) lint_no_unsafe_type_assertion(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	// 'TSAsExpression, TSTypeAssertion'. An `as const` has no type to compare: its type is that
	// of the expression itself, which the rule never reports.
	mut assertions := []NustaAssertion{}
	mut spans := []Span{}
	for node in c.nodes_of_kinds(root, ['as_expression', 'type_assertion'], []string{}) {
		expression, type_node := prtp_type_assertion(node) or { continue }
		assertions << NustaAssertion{
			node:       node
			expression: expression
			type_node:  type_node
		}
		spans << node_span(expression)
		spans << c.type_node_span(type_node)
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for assertion in assertions {
		expression_type := c.node_type(assertion.expression) or { continue }
		asserted_type := c.node_type(assertion.type_node) or { continue }
		message_id, type_text := c.nusta_check(expression_type, asserted_type, assertion.expression)!
		if message_id == '' {
			continue
		}
		findings << Finding{
			stmt:       position_of(assertion.node)
			message_id: message_id
			data:       {
				'type': type_text
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += assertions.len
	return findings
}

// nusta_any_type_name ports getAnyTypeName.
fn nusta_any_type_name(t TypeResponse) string {
	return if is_error_type(t) { 'error typed' } else { '`any`' }
}

// nusta_check ports checkExpression: the message of the assertion and its `type`, or '' when the
// assertion is safe.
fn (mut c Checker) nusta_check(expression_type TypeResponse, asserted_type TypeResponse, expression C.TSNode) !(string, string) {
	if expression_type.id == asserted_type.id {
		return '', ''
	}
	// Asserting unknown ==> any.
	if asserted_type.flags & type_flag_any != 0 && expression_type.flags & type_flag_unknown != 0 {
		return 'unsafeToAnyTypeAssertion', '`any`'
	}
	unsafe_expression := c.unsafe_assignment(expression_type, asserted_type, expression)!
	if unsafe_expression.found {
		return 'unsafeOfAnyTypeAssertion', nusta_any_type_name(unsafe_expression.sender)
	}
	// The sender node only matters for a `new Map()`, which a type is not.
	unsafe_asserted := c.unsafe_assignment(asserted_type, expression_type, none)!
	if unsafe_asserted.found {
		return 'unsafeToAnyTypeAssertion', nusta_any_type_name(unsafe_asserted.sender)
	}
	// The widened type of an object literal, so that excess properties do not make it
	// unassignable.
	widened := if expression_type.flags & type_flag_object != 0
		&& expression_type.object_flags & object_flag_object_literal != 0 {
		c.client.widened_type(c.snapshot, c.project, expression_type.id)!
	} else {
		expression_type
	}
	safe := c.assignable(widened.id, asserted_type.id) or {
		// The original catches what isTypeAssignableTo throws (microsoft/TypeScript#62933).
		if tsgo.is_panic(err) {
			return '', ''
		}
		return err
	}
	if safe {
		return '', ''
	}
	if asserted_type.flags & type_flag_type_parameter != 0 {
		constraint := c.base_constraint(asserted_type)!
		if constraint.is_null() {
			return 'unsafeToUnconstrainedTypeAssertion', c.type_string(asserted_type)!
		}
		if c.assignable(widened.id, constraint.id)! {
			return 'unsafeTypeAssertionAssignableToConstraint', c.type_string(asserted_type)!
		}
	}
	return 'unsafeTypeAssertion', c.type_string(asserted_type)!
}
