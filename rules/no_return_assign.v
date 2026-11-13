module rules

import json2
import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-return-assign` rule of ESLint 10.6.0, with its option.

const nra_messages = {
	'returnAssignment': 'Return statement should not contain assignment.'
	'arrowAssignment':  'Arrow function should not return assignment.'
}

// The ESTree types that end the search (SENTINEL_TYPE): the statements, and the functions and
// classes that are expressions.
const nra_sentinels = ['expression_statement', 'statement_block', 'empty_statement',
	'debugger_statement', 'with_statement', 'return_statement', 'labeled_statement', 'break_statement',
	'continue_statement', 'if_statement', 'switch_statement', 'throw_statement', 'try_statement',
	'while_statement', 'do_statement', 'for_statement', 'for_in_statement', 'arrow_function',
	'function_expression', 'generator_function', 'method_definition', 'class']

// nra_always reads "except-parens" or "always".
fn nra_always(options []json2.Any) !bool {
	option := if options.len > 0 { options[0] } else { json2.Any('except-parens') }
	if option is string && option in ['except-parens', 'always'] {
		return option == 'always'
	}
	return error('the option of `${no_return_assign}` must be "except-parens" or "always"')
}

fn (mut c Checker) lint_no_return_assign(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	always := nra_always(c.rule_options(no_return_assign))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['assignment_expression', 'augmented_assignment_expression'], []) {
		stats.checked++
		if !always && c.es_is_parenthesised(node) {
			continue
		}
		mut current := node
		mut parent := cti_estree_parent(current) or { continue }
		for node_kind(parent) !in nra_sentinels {
			current = parent
			parent = cti_estree_parent(current) or { break }
		}
		if node_kind(parent) == 'return_statement' {
			findings << Finding{
				stmt:       position_of(parent)
				message_id: 'returnAssignment'
			}
		} else if node_kind(parent) == 'arrow_function' {
			body := node_field(parent, 'body') or { continue }
			if node_key(unwrap_parens(body)) == node_key(current) {
				findings << Finding{
					stmt:       position_of(parent)
					message_id: 'arrowAssignment'
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
