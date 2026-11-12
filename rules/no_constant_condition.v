module rules

import json2
import time
import treesitter { node_field, node_kind, node_start, position_of }

// Port of the `no-constant-condition` rule of ESLint 10.6.0, with its option.

const ncc_messages = {
	'unexpected': 'Unexpected constant condition.'
}

// ncc_function_kinds are the FunctionDeclarations and FunctionExpressions: a `yield` makes
// the loops of its own function non-constant.
const ncc_function_kinds = ['function_declaration', 'function_expression', 'generator_function',
	'generator_function_declaration', 'method_definition']

// ncc_check_loops reads checkLoops: 'all', 'allExceptWhileTrue' or 'none' (true is 'all' and
// false 'none').
fn ncc_check_loops(options []json2.Any) !string {
	o := option_object(no_constant_condition, options, ['checkLoops'])!
	value := o.values['checkLoops'] or { return 'allExceptWhileTrue' }
	if value is bool {
		return if value { 'all' } else { 'none' }
	}
	if value is string && value in ['all', 'allExceptWhileTrue', 'none'] {
		return value
	}
	return error('the option `checkLoops` of `${no_constant_condition}` must be "all", "allExceptWhileTrue", "none", true or false')
}

fn (mut c Checker) lint_no_constant_condition(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	check_loops := ncc_check_loops(c.rule_options(no_constant_condition))!
	mut findings := []Finding{}
	kinds := ['if_statement', 'ternary_expression', 'while_statement', 'do_statement', 'for_statement']
	for node in c.nodes_of_kinds(root, kinds, []) {
		kind := node_kind(node)
		test_field := node_field(node, 'condition') or { continue }
		if node_kind(test_field) in [';', 'empty_statement'] {
			continue
		}
		test := unwrap_parens(test_field)
		stats.checked++
		if kind in ['if_statement', 'ternary_expression'] {
			if c.es_is_constant(root, test, true) {
				findings << Finding{
					stmt:       position_of(test)
					message_id: 'unexpected'
				}
			}
			continue
		}
		if check_loops !in ['all', 'allExceptWhileTrue'] {
			continue
		}
		if kind == 'while_statement' && node_kind(test) == 'true' && check_loops == 'allExceptWhileTrue' {
			continue
		}
		if !c.es_is_constant(root, test, true) {
			continue
		}
		// A `yield` of the loop's function inside the loop clears it; in a `for`, the test adds it
		// again after its init.
		from := if kind == 'for_statement' { node_start(test_field) } else { node_start(node) }
		if c.ncc_has_own_yield(node, from) {
			continue
		}
		findings << Finding{
			stmt:       position_of(test)
			message_id: 'unexpected'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ncc_has_own_yield: a `yield` of the loop's own function (nested functions are not entered)
// starts inside the loop at or after `from`.
fn (c &Checker) ncc_has_own_yield(loop C.TSNode, from int) bool {
	return c.nodes_of_kinds(loop, ['yield_expression'], ncc_function_kinds).any(node_start(it) >= from)
}
