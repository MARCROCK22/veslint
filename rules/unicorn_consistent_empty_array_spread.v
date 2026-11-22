module rules

import estree
import time

// Port of the `unicorn/consistent-empty-array-spread` rule of eslint-plugin-unicorn 79.0.0 (it has
// no options), with its fix.

const uceas_messages = {
	'consistent-empty-array-spread': 'Prefer using empty {{replacementDescription}} since the {{anotherNodePosition}} is {{anotherNodeDescription}}.'
}

fn (mut c Checker) lint_unicorn_consistent_empty_array_spread(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .array_expression {
			continue
		}
		for element in t.list(node, .elements) or { []int{} } {
			if element < 0 || t.typ(element) != .spread_element {
				continue
			}
			argument := t.node(element, .argument) or { continue }
			if t.typ(argument) != .conditional_expression {
				continue
			}
			stats.checked++
			if f := c.uceas_problem(mut ctx, argument) {
				findings << f
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// uceas_is_string ports isString: a static string without side effects.
fn (mut c Checker) uceas_is_string(mut ctx UnCtx, node int) bool {
	value := c.un_static_value_if_no_side_effects(mut ctx, node) or { return false }
	return value.value.kind == .string_
}

// uceas_is_array ports isArray: an array literal, or a static array without side effects.
fn (mut c Checker) uceas_is_array(mut ctx UnCtx, node int) bool {
	if ctx.t.typ(node) == .array_expression {
		return true
	}
	value := c.un_static_value_if_no_side_effects(mut ctx, node) or { return false }
	return value.value.kind == .array_
}

// uceas_problem ports getProblem: an empty string beside an array, or an empty array beside a
// string, in either branch.
fn (mut c Checker) uceas_problem(mut ctx UnCtx, conditional int) ?Finding {
	t := ctx.t
	consequent := t.node(conditional, .consequent)?
	alternate := t.node(conditional, .alternate)?
	// The first case: '' where the other side is an array.
	if (un_static_string_value(t, consequent) or { 'x' }) == ''
		&& c.uceas_is_array(mut ctx, alternate) {
		return c.uceas_create(t, ctx.tokens, consequent, 'alternate', 'an array', 'array', '[]')
	}
	if (un_static_string_value(t, alternate) or { 'x' }) == ''
		&& c.uceas_is_array(mut ctx, consequent) {
		return c.uceas_create(t, ctx.tokens, alternate, 'consequent', 'an array', 'array', '[]')
	}
	// The second case: [] where the other side is a string.
	if un_is_empty_array(t, consequent) && c.uceas_is_string(mut ctx, alternate) {
		return c.uceas_create(t, ctx.tokens, consequent, 'alternate', 'a string', 'string', "''")
	}
	if un_is_empty_array(t, alternate) && c.uceas_is_string(mut ctx, consequent) {
		return c.uceas_create(t, ctx.tokens, alternate, 'consequent', 'a string', 'string', "''")
	}
	return none
}

// uceas_create ports createProblem: fixed unless a comment is inside the node it replaces.
fn (c &Checker) uceas_create(t &estree.EsTree, tokens &SourceTokens, problem int, position string, description string, replacement string, code string) Finding {
	start, end := t.nodes[problem].start, t.nodes[problem].end
	has_fix := tokens.comments_inside(start, end).len == 0
	return Finding{
		stmt:       c.es_tree_position(t, problem)
		message_id: 'consistent-empty-array-spread'
		data:       {
			'replacementDescription': replacement
			'anotherNodePosition':    position
			'anotherNodeDescription': description
		}
		has_fix:    has_fix
		fix:        if has_fix { fix_replace_range(start, end, code) } else { Fix{} }
	}
}
