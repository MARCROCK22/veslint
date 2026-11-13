module rules

import json2
import time
import treesitter { node_field, node_kind, node_parent }

// Port of the `no-sequences` rule of ESLint 10.6.0, with its option.

const nseq_messages = {
	'unexpectedCommaExpression': 'Unexpected use of comma operator.'
}

// nseq_allow_parentheses reads allowInParentheses.
fn nseq_allow_parentheses(options []json2.Any) !bool {
	o := option_object(no_sequences, options, ['allowInParentheses'])!
	return o.bool_value('allowInParentheses')!
}

fn (mut c Checker) lint_no_sequences(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	allow_parentheses := nseq_allow_parentheses(c.rule_options(no_sequences))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['sequence_expression'], []) {
		// The SequenceExpression is the outermost of the commas tree-sitter nests.
		direct := node_parent(node) or { continue }
		if node_kind(direct) == 'sequence_expression' {
			continue
		}
		stats.checked++
		parent := cti_estree_parent(node) or { continue }
		if node_kind(parent) == 'for_statement' {
			init := node_field(parent, 'initializer') or { parent }
			update := node_field(parent, 'increment') or { parent }
			key := node_key(node)
			if node_key(unwrap_parens(init)) == key || node_key(unwrap_parens(update)) == key {
				continue
			}
		}
		if allow_parentheses {
			if c.nseq_requires_extra_parens(node, parent) {
				if c.es_is_parenthesised_twice(node) {
					continue
				}
			} else if c.es_is_parenthesised(node) {
				continue
			}
		}
		// The first comma, after the first expression.
		mut first := node
		for node_kind(first) == 'sequence_expression' {
			first = first_named(first) or { break }
		}
		tokens := c.source_tokens(root)
		mut comma := tokens.after(c.es_end(first), false) or { continue }
		for c.src[comma.start..comma.end] != ',' {
			comma = tokens.after(comma.end, false) or { break }
		}
		findings << Finding{
			stmt:       c.position_at(comma.start)
			message_id: 'unexpectedCommaExpression'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nseq_requires_extra_parens ports requiresExtraParens: the node is where the grammar already has
// parentheses (the test of an if, while or do-while, the discriminant of a switch, the object of
// a with) or the body of an arrow.
fn (c &Checker) nseq_requires_extra_parens(node C.TSNode, parent C.TSNode) bool {
	field := match node_kind(parent) {
		'if_statement', 'while_statement', 'do_statement' { 'condition' }
		'switch_statement' { 'value' }
		'with_statement' { 'object' }
		'arrow_function' { 'body' }
		else { return false }
	}
	value := node_field(parent, field) or { return false }
	return node_key(unwrap_parens(value)) == node_key(node)
}
