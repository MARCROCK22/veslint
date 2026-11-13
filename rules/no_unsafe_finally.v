module rules

import time
import treesitter { node_field, node_kind, node_parent, position_of }

// Port of the `no-unsafe-finally` rule of ESLint 10.6.0 (it has no options).

const nuf_messages = {
	'unsafeUsage': 'Unsafe usage of {{nodeType}}.'
}

// nuf_sentinels are the nodes that end the search for a `finally` (SENTINEL_NODE_TYPE_*): the
// program, functions and classes, and for a `break` or `continue` the statements they leave.
const nuf_sentinels = ['program', 'function_declaration', 'function_expression', 'generator_function',
	'generator_function_declaration', 'arrow_function', 'method_definition', 'class_declaration',
	'abstract_class_declaration', 'class']
const nuf_loops = ['do_statement', 'while_statement', 'for_in_statement', 'for_statement']

fn (mut c Checker) lint_no_unsafe_finally(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	kinds := ['return_statement', 'throw_statement', 'break_statement', 'continue_statement']
	for node in c.nodes_of_kinds(root, kinds, []) {
		stats.checked++
		kind := node_kind(node)
		label := if l := node_field(node, 'label') { c.text(l) } else { '' }
		mut sentinels := nuf_sentinels.clone()
		if kind == 'break_statement' && label == '' {
			sentinels << nuf_loops
			sentinels << 'switch_statement'
		} else if kind == 'continue_statement' {
			sentinels << nuf_loops
		}
		if c.nuf_in_finally(node, label, sentinels) {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unsafeUsage'
				data:       {
					'nodeType': match kind {
						'return_statement' { 'ReturnStatement' }
						'throw_statement' { 'ThrowStatement' }
						'break_statement' { 'BreakStatement' }
						else { 'ContinueStatement' }
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nuf_in_finally ports isInFinallyBlock: a `finally` block contains the statement before a
// sentinel, and the statement's label, if any, is not inside that block.
fn (c &Checker) nuf_in_finally(n C.TSNode, label string, sentinels []string) bool {
	mut label_inside := false
	mut current := n
	for node_kind(current) !in sentinels {
		parent := node_parent(current) or { return false }
		if label != '' && node_kind(parent) == 'labeled_statement' {
			if name := node_field(parent, 'label') {
				if c.text(name) == label {
					label_inside = true
				}
			}
		}
		if node_kind(current) == 'statement_block' && node_kind(parent) == 'finally_clause' {
			return !(label != '' && label_inside)
		}
		current = parent
	}
	return false
}
