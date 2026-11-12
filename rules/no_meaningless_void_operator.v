module rules

import json2
import time
import treesitter { node_field, node_start, nodes_of_kind, position_of }

// Port of the `no-meaningless-void-operator` rule of typescript-eslint 8.62.0, with its option, its
// fix and its `removeVoid` suggestion.

const nmvo_messages = {
	'meaninglessVoidOperator': "void operator shouldn't be used on {{type}}; it should convey that a return value is being ignored"
	'removeVoid':              "Remove 'void'"
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
		// The fixer removes from the first token of the expression, `void`, to its second token: the
		// start of the argument with its parentheses (comments between them go too).
		fix := fix_remove_range(node_start(node), node_start(void_arguments[i]))
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
