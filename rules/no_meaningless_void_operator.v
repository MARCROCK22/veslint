module rules

import json2
import time
import treesitter { named_children, node_field, node_kind, node_start, nodes_of_kind, position_of }

// Port of the `no-meaningless-void-operator` rule of typescript-eslint 8.72.2, with its option, its
// fixes and its `removeVoid` suggestion.

const nmvo_messages = {
	'meaninglessVoidOnNonCall': "void operator is useless here; it should only discard a call's return value"
	'meaninglessVoidOperator':  "void operator shouldn't be used on {{type}}; it should convey that a return value is being ignored"
	'removeVoid':               "Remove 'void'"
}

struct NmvoOptions {
	check_never bool
}

fn nmvo_options(options []json2.Any) !NmvoOptions {
	o := option_object(no_meaningless_void_operator, options, ['checkNever'])!
	return NmvoOptions{
		check_never: o.bool_value('checkNever')!
	}
}

fn (mut c Checker) lint_no_meaningless_void_operator(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	options := nmvo_options(c.rule_options(no_meaningless_void_operator))!
	// `UnaryExpression[operator="void"]`.
	mut voids := []C.TSNode{}
	mut void_arguments := []C.TSNode{}
	mut operands := []C.TSNode{}
	for node in c.nodes_of_kind(root, c'unary_expression') {
		if operator_of(node) != 'void' {
			continue
		}
		argument := node_field(node, 'argument') or { continue }
		voids << node
		void_arguments << argument
		operands << unwrap_parens(argument)
	}
	c.resolve_spans(operands.map(node_span(it)), abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for i, node in voids {
		// The fixer removes from the first token of the expression, `void`, to its second token: the
		// start of the argument with its parentheses (comments between them go too).
		fix := fix_remove_range(node_start(node), node_start(void_arguments[i]))
		inner := nmvo_unwrap_void_argument(operands[i])
		if !nmvo_is_call(inner) {
			// `void 0` is the common undefined idiom, and `void (x = value)` discards the result of
			// an assignment so that the expression is undefined (`() => void (x = 1)`).
			if node_kind(inner) == 'number' && (number_literal_value(c.text(inner)) or { 1.0 }) == 0 {
				continue
			}
			if node_kind(inner) in ['assignment_expression', 'augmented_assignment_expression'] {
				continue
			}
			// `void promiseValue` is allowed, so that the rule does not fight no-floating-promises.
			t := c.node_type(operands[i]) or { continue }
			if c.is_thenable(t, c.symbol_location(operands[i]))! {
				continue
			}
			finding := Finding{
				stmt:       position_of(node)
				message_id: 'meaninglessVoidOnNonCall'
			}
			// Fixed only as a statement of its own.
			mut in_statement := false
			if parent := estree_parent(node) {
				in_statement = node_kind(parent) == 'expression_statement'
			}
			if in_statement {
				findings << c.with_fixes(finding, [fix])!
			} else {
				findings << finding
			}
			continue
		}
		// The exact type (not the constrained one), split with tsutils.unionConstituents; each part
		// is tested with tsutils.isTypeFlagSet (its own flags).
		argument_type := c.node_type(operands[i]) or { continue }
		parts := c.constituents(argument_type)!
		meaningless := parts.all(it.flags & (type_flag_void | type_flag_undefined) != 0)
		if !meaningless && !(options.check_never
			&& parts.all(it.flags & (type_flag_void | type_flag_undefined | type_flag_never) != 0)) {
			continue
		}
		finding := Finding{
			stmt:       position_of(node)
			message_id: 'meaninglessVoidOperator'
			data:       {
				'type': c.type_string(argument_type)!
			}
		}
		if meaningless {
			findings << c.with_fixes(finding, [fix])!
		} else {
			// With checkNever, an argument that may be `never` only gets the suggestion.
			_, suggestion := c.suggestion('removeVoid', map[string]string{}, [fix])!
			findings << Finding{
				...finding
				suggestions: [suggestion]
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += voids.len
	return findings
}

// nmvo_unwrap_void_argument ports unwrapVoidArgument: through optional chains, `as`, `!`,
// `satisfies`, `<T>` assertions and to the last expression of a sequence (and parentheses, which
// ESTree does not have).
fn nmvo_unwrap_void_argument(n C.TSNode) C.TSNode {
	mut current := unwrap_parens(n)
	for _ in 0 .. max_expression_depth {
		next := match node_kind(current) {
			'as_expression', 'satisfies_expression', 'non_null_expression' {
				first_named(current) or { return current }
			}
			'type_assertion' {
				parts := named_children(current)
				if parts.len < 2 {
					return current
				}
				parts[1]
			}
			'sequence_expression' {
				parts := named_children(current)
				if parts.len == 0 {
					return current
				}
				parts.last()
			}
			else {
				return current
			}
		}
		current = unwrap_parens(next)
	}
	return current
}

// nmvo_is_call: a CallExpression in ESTree (not a tagged template or `import()`).
fn nmvo_is_call(n C.TSNode) bool {
	if node_kind(n) != 'call_expression' {
		return false
	}
	call_arguments(n) or { return false }
	callee := node_field(n, 'function') or { return false }
	return node_kind(callee) != 'import'
}
