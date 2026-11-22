module rules

import estree
import time

// Port of the `no-non-null-assertion` rule of typescript-eslint 8.72.2, with its suggestions (an
// optional chain instead of the `!`), on the ESTree.

const nnna_messages = {
	'noNonNull':            'Forbidden non-null assertion.'
	'suggestOptionalChain': 'Consider using the optional chain operator `?.` instead. This operator includes runtime checks, so it is safer than the compile-only non-null assertion operator.'
}

fn (mut c Checker) lint_no_non_null_assertion(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.source_tokens(root)
	mut checked := 0
	// In the order of the traversal: an outer assertion before the one it wraps (`x!!`).
	for step in t.steps() {
		i := step.node
		node := t.nodes[i]
		if step.leave || node.typ != .ts_non_null_expression {
			continue
		}
		checked++
		expression := t.node(i, .expression) or { continue }
		// The `!` after the expression.
		mut at := t.nodes[expression].end
		mut operator := SourceToken{}
		for {
			token := tokens.after(at, false) or { break }
			if c.src[token.start..token.end] == '!' {
				operator = token
				break
			}
			at = token.end
		}
		replace_with_optional := fix_replace_range(operator.start, operator.end, '?.')
		remove_token := fix_remove_range(operator.start, operator.end)
		mut fixes := []Fix{}
		mut has_suggestion := false
		parent := node.parent
		if parent >= 0 && t.typ(parent) == .member_expression
			&& (t.node(parent, .object) or { -1 }) == i && !nnna_is_assignee(t, parent) {
			has_suggestion = true
			if !(t.flag(parent, .optional) or { false }) {
				if t.flag(parent, .computed) or { false } {
					// x![y]?.z
					fixes = [replace_with_optional]
				} else {
					// x!.y?.z: the `!` removed, `?` before the `.`.
					punctuator := tokens.after(operator.end, false) or { continue }
					fixes = [remove_token, fix_insert_at(punctuator.start, '?')]
				}
			} else {
				// x!?.[y].z or x!?.y.z
				fixes = [remove_token]
			}
		} else if parent >= 0 && t.typ(parent) == .call_expression
			&& (t.node(parent, .callee) or { -1 }) == i {
			has_suggestion = true
			fixes = if !(t.flag(parent, .optional) or { false }) {
				// x.y?.z!()
				[replace_with_optional]
			} else {
				// x.y.z!?.()
				[remove_token]
			}
		}
		mut suggestions := []Suggestion{}
		if has_suggestion {
			_, suggestion := c.suggestion('suggestOptionalChain', map[string]string{}, fixes)!
			suggestions << suggestion
		}
		findings << Finding{
			stmt:        c.position_range(node.start, node.end)
			message_id:  'noNonNull'
			suggestions: suggestions
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nnna_is_assignee ports isAssignee.
fn nnna_is_assignee(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	match t.typ(parent) {
		.assignment_expression {
			if (t.node(parent, .left) or { -1 }) == node {
				return true
			}
		}
		.unary_expression {
			if (t.string_of(parent, .operator) or { '' }) == 'delete'
				&& (t.node(parent, .argument) or { -1 }) == node {
				return true
			}
		}
		.update_expression {
			if (t.node(parent, .argument) or { -1 }) == node {
				return true
			}
		}
		.array_pattern, .rest_element {
			return true
		}
		.property {
			grand := t.nodes[parent].parent
			if (t.node(parent, .value) or { -1 }) == node && grand >= 0
				&& t.typ(grand) == .object_expression && nnna_is_assignee(t, grand) {
				return true
			}
		}
		.ts_non_null_expression, .ts_as_expression, .ts_type_assertion, .ts_satisfies_expression {
			return nnna_is_assignee(t, parent)
		}
		else {}
	}
	return false
}
