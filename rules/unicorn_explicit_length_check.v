module rules

import estree
import json2
import time

// Port of the `unicorn/explicit-length-check` rule of eslint-plugin-unicorn 79.0.0, with its option,
// fix and suggestion.

const uelc_messages = {
	'non-zero':   'Use `.{{property}} {{code}}` when checking {{property}} is not zero.'
	'zero':       'Use `.{{property}} {{code}}` when checking {{property}} is zero.'
	'suggestion': 'Replace `.{{property}}` with `.{{property}} {{code}}`.'
}

fn uelc_options(options []json2.Any) !string {
	o := option_object(unicorn_explicit_length_check, options, ['non-zero'])!
	style := o.string_value('non-zero', ['greater-than', 'not-equal'])!
	return if style == '' { 'greater-than' } else { style }
}

fn uelc_compare(t &estree.EsTree, node int, operator string, value f64, right bool) bool {
	return node >= 0 && t.typ(node) == .binary_expression
		&& (t.string_of(node, .operator) or { '' }) == operator
		&& un_is_numeric_literal_of(t, t.node(node, if right { estree.Key.right } else { .left }) or {
		-1
	}, value)
}

// uelc_length_check ports getLengthCheckNode: the comparison of the length with 0 or 1 around it
// (through TypeScript wrappers with `allow_ts`), and whether it checks for zero.
fn uelc_length_check(t &estree.EsTree, length int, allow_ts bool) ?(int, bool) {
	mut node := t.nodes[length].parent
	if allow_ts {
		for un_is_ts_expression_wrapper(t, node) {
			node = t.nodes[node].parent
		}
	}
	if node < 0 {
		return none
	}
	if uelc_compare(t, node, '===', 0, true) || uelc_compare(t, node, '==', 0, true)
		|| uelc_compare(t, node, '<', 1, true) || uelc_compare(t, node, '<=', 0, true)
		|| uelc_compare(t, node, '===', 0, false) || uelc_compare(t, node, '==', 0, false)
		|| uelc_compare(t, node, '>', 1, false) || uelc_compare(t, node, '>=', 0, false) {
		return node, true
	}
	if uelc_compare(t, node, '!==', 0, true) || uelc_compare(t, node, '!=', 0, true)
		|| uelc_compare(t, node, '>', 0, true) || uelc_compare(t, node, '>=', 1, true)
		|| uelc_compare(t, node, '!==', 0, false) || uelc_compare(t, node, '!=', 0, false)
		|| uelc_compare(t, node, '<', 0, false) || uelc_compare(t, node, '<=', 1, false) {
		return node, false
	}
	return none
}

// uelc_length_check_member ports getLengthCheckMemberExpression: the `length` or `size` a
// comparison (maybe negated or in `Boolean()`) compares.
fn uelc_length_check_member(t &estree.EsTree, node int) ?int {
	if node < 0 {
		return none
	}
	if un_is_logic_not(t, node) {
		return uelc_length_check_member(t, t.node(node, .argument)?)
	}
	if t.typ(node) == .call_expression {
		callee := t.node(node, .callee)?
		args := t.list(node, .arguments) or { []int{} }
		if t.typ(callee) == .identifier && (t.string_of(callee, .name) or { '' }) == 'Boolean'
			&& args.len == 1 {
			return uelc_length_check_member(t, args[0])
		}
	}
	if t.typ(node) != .binary_expression {
		return none
	}
	left := un_unwrap_ts_expression(t, t.node(node, .left)?)
	if un_is_length_or_size_member(t, left) {
		return left
	}
	right := un_unwrap_ts_expression(t, t.node(node, .right)?)
	if un_is_length_or_size_member(t, right) {
		return right
	}
	return none
}

// uelc_is_same_length_non_zero_check ports isSameLengthNonZeroCheck.
fn (mut c Checker) uelc_is_same_length_non_zero_check(ctx &UnCtx, node int, length int) bool {
	t := ctx.t
	member := uelc_length_check_member(t, node) or { return false }
	if !c.un_is_same_reference(t, member, length) {
		return false
	}
	check, zero := uelc_length_check(t, member, true) or { return false }
	ancestor, negative := c.un_boolean_ancestor_in(ctx, check)
	return ancestor == node && negative == zero
}

// uelc_guarded_by_non_zero_check ports isLengthGuardedByNonZeroCheck: `x.length > 0 && x.length`.
fn (mut c Checker) uelc_guarded_by_non_zero_check(ctx &UnCtx, length int) bool {
	t := ctx.t
	root := un_logical_root(t, length, '&&')
	if t.typ(root) != .logical_expression || (t.string_of(root, .operator) or { '' }) != '&&' {
		return false
	}
	return un_logical_operands(t, root, '&&').any(it != length
		&& c.uelc_is_same_length_non_zero_check(ctx, it, length))
}

// uelc_comparison_needs_parens ports shouldAddParenthesesToComparison: the comparison that replaces
// the node binds more loosely than its place.
fn (c &Checker) uelc_comparison_needs_parens(t &estree.EsTree, tokens &SourceTokens, node int, operator string) bool {
	if c.un_is_parenthesized(t, tokens, node) {
		return false
	}
	parent := t.nodes[node].parent
	is_key := fn [t, parent, node] (key estree.Key) bool {
		return (t.node(parent, key) or { -1 }) == node
	}
	match t.typ(parent) {
		.member_expression {
			return is_key(.object)
		}
		.call_expression, .new_expression {
			return is_key(.callee)
		}
		.tagged_template_expression {
			return is_key(.tag)
		}
		.binary_expression, .ts_as_expression, .ts_satisfies_expression {
			precedence := match operator {
				'===', '!==', '==', '!=' { 9 }
				else { 10 }
			}
			parent_precedence := un_precedence(t, parent)
			return parent_precedence > precedence || (parent_precedence == precedence
				&& t.typ(parent) == .binary_expression && is_key(.right))
		}
		.await_expression, .ts_non_null_expression, .ts_type_assertion, .unary_expression {
			return true
		}
		else {
			return false
		}
	}
}

fn (mut c Checker) lint_unicorn_explicit_length_check(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	non_zero_style := uelc_options(c.rule_options(unicorn_explicit_length_check))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for length in 0 .. t.nodes.len {
		if t.typ(length) != .member_expression {
			continue
		}
		stats.checked++
		if !un_is_length_or_size_member(t, length)
			|| t.typ(t.node(length, .object) or { continue }) == .this_expression {
			continue
		}
		// Ignore the length or size properties that are known not to be counts.
		if c.un_is_known_non_collection_length_or_size(mut ctx, length) {
			continue
		}
		mut node := -1
		mut auto_fix := true
		mut is_zero := false
		if check, zero := uelc_length_check(t, length, false) {
			ancestor, negative := c.un_boolean_ancestor_in(ctx, check)
			node = ancestor
			is_zero = if negative { !zero } else { zero }
		} else {
			ancestor, negative := c.un_boolean_ancestor_in(ctx, length)
			parent := t.nodes[length].parent
			if c.un_is_boolean_context(ctx, ancestor) {
				is_zero = negative
				node = ancestor
			} else if un_is_logical(t, parent) && (t.string_of(parent, .operator) or { '' }) == '&&' {
				is_zero = negative
				node = length
				auto_fix = false
			}
		}
		if node < 0 || (node == length && c.uelc_guarded_by_non_zero_check(ctx, length))
			|| c.un_has_same_object_shape_property_check(t, node, length) {
			continue
		}
		parent := t.nodes[node].parent
		unsafe_negation := un_is_logic_not(t, node) && parent >= 0
			&& t.typ(parent) == .binary_expression && t.node(parent, .left) or { -1 } == node
		// getProblem
		code := if is_zero {
			'=== 0'
		} else if non_zero_style == 'not-equal' {
			'!== 0'
		} else {
			'> 0'
		}
		if (is_zero && uelc_compare(t, node, '===', 0, true)) || (!is_zero && non_zero_style == 'greater-than'
			&& uelc_compare(t, node, '>', 0, true)) || (!is_zero && non_zero_style == 'not-equal'
			&& uelc_compare(t, node, '!==', 0, true)) {
			continue
		}
		comparison := '${c.un_text(t, length)} ${code}'
		needs_parentheses := c.uelc_comparison_needs_parens(t, tokens, node, code.all_before(' '))
			|| c.un_expression_start_needs_parens(t, tokens, length, node)
		mut fixed := if needs_parentheses { '(${comparison})' } else { comparison }
		if c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false), fixed) {
			fixed = ';${fixed}'
		}
		mut fixes := [fix_replace_range(t.nodes[node].start, t.nodes[node].end, fixed)]
		fixes << c.un_fix_space_around_keyword(t, tokens, node)
		_, fix := c.merge_fixes(fixes)!
		property := t.string_of(t.node(length, .property) or { continue }, .name) or { continue }
		data := {
			'code':     code
			'property': property
		}
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: if is_zero { 'zero' } else { 'non-zero' }
			data:       data
		}
		// The whole comparison is rebuilt from the member alone: a comment in it would be lost.
		if un_has_comment_in_range(tokens, t.nodes[node].start, t.nodes[node].end) {
			findings << finding
			continue
		}
		if auto_fix && !unsafe_negation {
			finding = Finding{
				...finding
				has_fix: true
				fix:     fix
			}
		} else if !unsafe_negation {
			finding = Finding{
				...finding
				suggestions: [Suggestion{
					message_id: 'suggestion'
					data:       data
					fix:        fix
				}]
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
