module rules

import json2
import time
import treesitter { node_field, node_kind, node_parent, position_of }

// Port of the `no-cond-assign` rule of ESLint 10.6.0, with its option.

const nca_messages = {
	'unexpected': 'Unexpected assignment within {{type}}.'
	'missing':    'Expected a conditional expression and instead saw an assignment.'
}

// nca_test_kinds are the statements and expressions with a test, and the `type` of the message.
const nca_test_kinds = {
	'if_statement':       "an 'if' statement"
	'while_statement':    "a 'while' statement"
	'do_statement':       "a 'do...while' statement"
	'for_statement':      "a 'for' statement"
	'ternary_expression': 'ConditionalExpression'
}

const nca_function_kinds = ['function_declaration', 'function_expression', 'generator_function',
	'generator_function_declaration', 'arrow_function']

// nca_always reads the option: 'always' or 'except-parens'.
fn nca_always(options []json2.Any) !bool {
	option := if options.len > 0 { options[0] } else { json2.Any('except-parens') }
	if option is string && option in ['except-parens', 'always'] {
		return option == 'always'
	}
	return error('the option of `${no_cond_assign}` must be "except-parens" or "always"')
}

fn (mut c Checker) lint_no_cond_assign(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	always := nca_always(c.rule_options(no_cond_assign))!
	mut findings := []Finding{}
	if always {
		for node in c.nodes_of_kinds(root, ['assignment_expression', 'augmented_assignment_expression'], []) {
			stats.checked++
			if ancestor := nca_conditional_ancestor(node) {
				findings << Finding{
					stmt:       position_of(node)
					message_id: 'unexpected'
					data:       {
						'type': nca_test_kinds[node_kind(ancestor)]
					}
				}
			}
		}
	} else {
		for node in c.nodes_of_kinds(root, nca_test_kinds.keys(), []) {
			stats.checked++
			mut test := nca_test(node) or { continue }
			// The parentheses around the test: those of an if, while or do...while statement count
			// as the first pair; one pair is enough in a `for`, two elsewhere.
			mut parens := 0
			for node_kind(test) == 'parenthesized_expression' {
				inner := first_named(test) or { break }
				if node_kind(inner) == 'sequence_expression' {
					break
				}
				test = inner
				parens++
			}
			if node_kind(test) !in ['assignment_expression', 'augmented_assignment_expression'] {
				continue
			}
			allowed := if node_kind(node) == 'for_statement' { 1 } else { 2 }
			if parens < allowed {
				findings << Finding{
					stmt:       position_of(test)
					message_id: 'missing'
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nca_test is the `test` of a statement or a conditional expression, with its parentheses (those
// of an if, while or do...while statement included).
fn nca_test(n C.TSNode) ?C.TSNode {
	test := node_field(n, 'condition')?
	if node_kind(test) in [';', 'empty_statement'] {
		return none
	}
	return test
}

// nca_conditional_ancestor ports findConditionalAncestor: the closest statement or conditional
// expression whose test contains the node, without crossing a function.
fn nca_conditional_ancestor(n C.TSNode) ?C.TSNode {
	mut current := n
	for {
		parent := cti_estree_parent(current) or { return none }
		if node_kind(parent) in nca_test_kinds {
			if test := nca_test(parent) {
				if node_key(unwrap_parens(test)) == node_key(current) {
					return parent
				}
			}
		}
		if node_kind(parent) in nca_function_kinds {
			return none
		}
		// A method is a FunctionExpression for its parameters and its body, not for its key.
		if node_kind(parent) == 'method_definition' {
			name := node_field(parent, 'name') or { return none }
			if node_key(name) != node_key(nca_child_of(current, parent)) {
				return none
			}
		}
		current = parent
	}
	return none
}

// nca_child_of is the child of `ancestor` that contains `n`.
fn nca_child_of(n C.TSNode, ancestor C.TSNode) C.TSNode {
	mut node := n
	for {
		parent := node_parent(node) or { return node }
		if node_key(parent) == node_key(ancestor) {
			return node
		}
		node = parent
	}
	return node
}
