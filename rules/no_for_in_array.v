module rules

import time
import tsgo { TypeResponse }
import treesitter { node_field, node_kind, nodes_of_kind, position_of }

// Port of the `no-for-in-array` rule of typescript-eslint 8.62.0 (it has no options).

const nfia_messages = {
	'forInViolation': 'For-in loops over arrays skips holes, returns indices as strings, and may visit the prototype chain or other enumerable properties. Use a more robust iteration method such as for-of or array.forEach instead.'
}

fn (mut c Checker) lint_no_for_in_array(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	// ForInStatement: a tree-sitter for_in_statement whose operator is `in` (not `of`).
	mut loops := []C.TSNode{}
	mut rights := []C.TSNode{}
	for node in c.nodes_of_kind(root, c'for_in_statement') {
		operator := node_field(node, 'operator') or { continue }
		if node_kind(operator) != 'in' {
			continue
		}
		right := node_field(node, 'right') or { continue }
		loops << node
		rights << unwrap_parens(right)
	}
	c.resolve_spans(rights.map(node_span(it)), abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for i, loop in loops {
		t := c.node_type(rights[i]) or { continue }
		if c.nfia_is_array_like(c.constrained(t)!, 0)! {
			// getForStatementHeadLoc starts at the `for` keyword.
			findings << Finding{
				stmt:       c.es_for_head_position(loop)
				message_id: 'forInViolation'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += loops.len
	return findings
}

// nfia_is_array_like ports isArrayLike with isTypeRecurser: some part of a union or an
// intersection (recursively) has a number index and a numeric `length`.
fn (mut c Checker) nfia_is_array_like(t TypeResponse, depth int) !bool {
	if t.flags & (type_flag_union | type_flag_intersection) != 0 {
		if depth >= max_type_depth {
			return false
		}
		for part in c.members_of(t)! {
			if c.nfia_is_array_like(part, depth + 1)! {
				return true
			}
		}
		return false
	}
	if c.number_index_type(t)!.is_null() {
		return false
	}
	// hasArrayishLength: tsutils.isTypeFlagSet, on the own flags of the type of `length`.
	length := c.property(t, 'length')!
	if length.is_null() {
		return false
	}
	return c.symbol_type(length.id)!.flags & type_flag_number_like != 0
}
