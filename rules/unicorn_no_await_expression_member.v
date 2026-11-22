module rules

import estree
import time

// Port of the `unicorn/no-await-expression-member` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fix.

const unaem_messages = {
	'no-await-expression-member': 'Do not access a member directly from an await expression.'
}

// unaem_non_iterable_types are nonIterableNodeTypes of utils/is-known-non-iterable.js.
const unaem_non_iterable_types = [estree.NodeType.object_expression, .binary_expression,
	.unary_expression, .update_expression]

fn (mut c Checker) lint_unicorn_no_await_expression_member(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for member in 0 .. t.nodes.len {
		if t.typ(member) != .member_expression {
			continue
		}
		object := t.node(member, .object) or { continue }
		if t.typ(object) != .await_expression {
			continue
		}
		stats.checked++
		property := t.node(member, .property) or { continue }
		mut finding := Finding{
			stmt:       c.es_tree_position(t, property)
			message_id: 'no-await-expression-member'
		}
		if fixes := c.unaem_fix(t, tokens, member, object, property) {
			has_fix, fix := c.merge_fixes(fixes)!
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unaem_is_known_non_iterable ports isKnownNonIterable: an object, an arithmetic expression or a
// literal that is not a string.
fn unaem_is_known_non_iterable(t &estree.EsTree, node int) bool {
	if t.typ(node) in unaem_non_iterable_types {
		return true
	}
	return t.typ(node) == .literal && t.get(node, .value) !is string
}

// unaem_fix is the fix of `const foo = (await bar)[0]` (a destructuring pattern) and of
// `const foo = (await bar).foo` (an object pattern).
fn (c &Checker) unaem_fix(t &estree.EsTree, tokens &SourceTokens, member int, object int, property int) ?[]Fix {
	computed := t.flag(member, .computed) or { false }
	if t.flag(member, .optional) or { false } {
		return none
	}
	parent := t.nodes[member].parent
	if parent < 0 || t.typ(parent) != .variable_declarator
		|| (t.node(parent, .init) or { -1 }) != member {
		return none
	}
	variable := t.node(parent, .id)?
	if t.typ(variable) != .identifier || t.node(variable, .type_annotation) != none {
		return none
	}
	object_start, object_end := c.un_parenthesized_range(t, tokens, object)
	if un_would_remove_comments(tokens, t.nodes[member].start, t.nodes[member].end, [
		UnRange{object_start, object_end},
	]) {
		return none
	}
	mut opening := ''
	mut closing := ''
	if computed {
		// `[-0]` and `[+0]` are the same index as `[0]`.
		index := un_static_number_value(t, property) or { return none }
		if index != 0 && index != 1 {
			return none
		}
		argument := t.node(object, .argument)?
		if unaem_is_known_non_iterable(t, un_unwrap_ts_expression(t, argument)) {
			return none
		}
		opening = if index == 0 { '[' } else { '[, ' }
		closing = ']'
	} else {
		if t.typ(property) != .identifier
			|| (t.string_of(variable, .name) or { '' }) != (t.string_of(property, .name) or { '' }) {
			return none
		}
		opening = '{'
		closing = '}'
	}
	mut fixes := [fix_insert_at(t.nodes[variable].start, opening),
		fix_insert_at(t.nodes[variable].end, closing),
		fix_remove_range(object_end, t.nodes[member].end)]
	fixes << c.un_remove_parentheses(t, tokens, object)
	return fixes
}
