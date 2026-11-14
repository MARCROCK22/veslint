module rules

import estree
import time

// Port of the `unicorn/no-useless-fallback-in-spread` rule of eslint-plugin-unicorn 79.0.0 (it has
// no options), with its fix.

const unufis_messages = {
	'no-useless-fallback-in-spread': 'The empty object is useless.'
}

fn (mut c Checker) lint_unicorn_no_useless_fallback_in_spread(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .object_expression {
			continue
		}
		stats.checked++
		// `{...(foo || {})}`, `{...(foo ?? {})}`
		if !un_is_empty_object(t, node) {
			continue
		}
		logical := t.nodes[node].parent
		if logical < 0 || t.typ(logical) != .logical_expression
			|| (t.node(logical, .right) or { -1 }) != node
			|| (t.string_of(logical, .operator) or { '' }) !in ['||', '??'] {
			continue
		}
		spread := t.nodes[logical].parent
		if spread < 0 || t.typ(spread) != .spread_element
			|| (t.node(spread, .argument) or { -1 }) != logical {
			continue
		}
		object := t.nodes[spread].parent
		if object < 0 || t.typ(object) != .object_expression
			|| spread !in (t.list(object, .properties) or { []int{} }) {
			continue
		}
		mut has_fix := false
		mut fix := Fix{}
		if fixes := c.unufis_fix(t, tokens, logical) {
			has_fix, fix = c.merge_fixes(fixes)!
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'no-useless-fallback-in-spread'
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unufis_fix removes the operator and the empty object, and the parentheses of the logical
// expression unless the left side is a sequence without its own parentheses; aborted when that
// would remove a comment.
fn (c &Checker) unufis_fix(t &estree.EsTree, tokens &SourceTokens, logical int) ?[]Fix {
	left := t.node(logical, .left)?
	left_parenthesized := c.un_is_parenthesized(t, tokens, left)
	_, start := c.un_parenthesized_range(t, tokens, left)
	end := t.nodes[logical].end
	if un_would_remove_comments(tokens, start, end, []) {
		return none
	}
	mut fixes := [fix_remove_range(start, end)]
	if left_parenthesized || t.typ(left) != .sequence_expression {
		fixes << c.un_remove_parentheses(t, tokens, logical)
	}
	return fixes
}
