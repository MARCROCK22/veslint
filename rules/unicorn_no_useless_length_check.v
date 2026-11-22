module rules

import estree
import time
import treesitter { node_end, node_start }

// Port of the `unicorn/no-useless-length-check` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fixes and suggestions.

const unulc_messages = {
	'for-of':              'The non-empty check is useless as `for…of` does not iterate over an empty array.'
	'non-zero':            'The non-empty check is useless as `Array#some()` returns `false` for an empty array.'
	'zero':                'The empty check is useless as `Array#every()` returns `true` for an empty array.'
	'remove-length-check': 'Remove the length check.'
}

// unulc_is_length_compare_zero ports isLengthCompareZero: `x.length <op> 0`.
fn unulc_is_length_compare_zero(t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) != .binary_expression {
		return false
	}
	right := t.node(node, .right) or { return false }
	return t.typ(right) == .literal && un_raw(t, right) == '0'
		&& un_is_member(t, t.node(node, .left) or { -1 }, properties: ['length'], optional: false)
}

// unulc_flat ports flatLogicalExpression.
fn unulc_flat(t &estree.EsTree, node int, mut out []int) {
	operator := t.string_of(node, .operator) or { '' }
	for key in [estree.Key.left, .right] {
		child := t.node(node, key) or { continue }
		if t.typ(child) == .logical_expression && (t.string_of(child, .operator) or { '' }) == operator {
			unulc_flat(t, child, mut out)
		} else {
			out << child
		}
	}
}

// unulc_is_matching_call ports isMatchingCall: `<method>()` on the object of the length check, not
// on a receiver known not to be an array or a typed array.
fn (mut c Checker) unulc_is_matching_call(mut ctx UnCtx, condition int, method string, length_check int) bool {
	t := ctx.t
	if !un_is_method_call(t, condition,
		methods:         [method]
		optional_call:   false
		optional_member: false
		computed:        false
	) {
		return false
	}
	callee := t.node(condition, .callee) or { return false }
	object := t.node(callee, .object) or { return false }
	check_object := t.node(t.node(length_check, .left) or { return false }, .object) or {
		return false
	}
	return c.un_is_same_reference(t, check_object, object)
		&& !c.un_is_known_non_indexed_collection(mut ctx, object)
}

// unulc_remove_length_check ports removeLengthCheck: the check and its operator go away; none when
// a comment there would be lost.
fn (c &Checker) unulc_remove_length_check(t &estree.EsTree, tokens &SourceTokens, node int) ?Fix {
	parent := t.nodes[node].parent
	left := t.node(parent, .left)?
	right := t.node(parent, .right)?
	left_start, left_end := c.un_parenthesized_range(t, tokens, left)
	right_start, right_end := c.un_parenthesized_range(t, tokens, right)
	start, end := if left == node { left_start, right_start } else { left_end, right_end }
	if un_has_comment_in_range(tokens, start, end) {
		return none
	}
	replacement := if left == node && end < c.src.len
		&& c.un_needs_semicolon(t, tokens, tokens.before(start, false), c.src[end..end + 1]) {
		';'
	} else {
		''
	}
	return fix_replace_range(start, end, replacement)
}

// un_is_side_effect_free_function ports isSideEffectFreeFunction: an inline function whose
// parameters and body have no possible side effect.
fn un_is_side_effect_free_function(t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) !in [.arrow_function_expression, .function_expression] {
		return false
	}
	mut children := (t.list(node, .params) or { []int{} }).clone()
	children << t.node(node, .body) or { return false }
	return children.all(!un_has_possible_side_effect(t, it))
}

// un_single_statement ports getSingleStatement: the statement, or the only one of a block.
fn un_single_statement(t &estree.EsTree, node int) int {
	if node < 0 || t.typ(node) != .block_statement {
		return node
	}
	body := t.list(node, .body) or { return -1 }
	return if body.len == 1 { body[0] } else { -1 }
}

// un_reindent_text ports reindentText: every line after the first that starts with
// `source_indent` gets `target_indent` in its place; blank lines become empty.
fn un_reindent_text(text string, source_indent string, target_indent string) string {
	mut out := []u8{}
	mut i := 0
	// The first line stays as it is.
	for i < text.len && !un_is_line_break_at(text, i) {
		out << text[i]
		i++
	}
	for i < text.len {
		break_len := un_line_break_len(text, i)
		linebreak := text[i..i + break_len]
		i += break_len
		mut j := i
		for j < text.len && !un_is_line_break_at(text, j) {
			j++
		}
		line := text[i..j]
		out << linebreak.bytes()
		if js_trim(line) != '' {
			if line.starts_with(source_indent) {
				out << target_indent.bytes()
				out << line[source_indent.len..].bytes()
			} else {
				out << line.bytes()
			}
		}
		i = j
	}
	return out.bytestr()
}

fn un_is_line_break_at(text string, i int) bool {
	return un_line_break_len(text, i) > 0
}

// un_line_break_len is the length of the line break at i (`\r\n`, `\n`, `\r`, U+2028, U+2029), 0
// if none.
fn un_line_break_len(text string, i int) int {
	if text[i] == `\r` {
		return if i + 1 < text.len && text[i + 1] == `\n` { 2 } else { 1 }
	}
	if text[i] == `\n` {
		return 1
	}
	if text[i] == 0xe2 && i + 2 < text.len && text[i + 1] == 0x80 && text[i + 2] in [u8(0xa8), 0xa9] {
		return 3
	}
	return 0
}

// un_has_multiline_token ports hasMultilineToken: a token of the node spans lines.
fn un_has_multiline_token(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	for token in tokens.inside(t.nodes[node].start, t.nodes[node].end, false) {
		start_line, _ := t.line_column(token.start)
		end_line, _ := t.line_column(token.end)
		if start_line != end_line {
			return true
		}
	}
	return false
}

// unulc_loop_binding_in_right ports hasLoopBindingReferenceInRight: a variable of the scope of the
// loop is referenced in its right side.
fn (mut c Checker) unulc_loop_binding_in_right(ctx &UnCtx, loop int) bool {
	t := ctx.t
	ts := t.ts_node(loop) or { return false }
	right := t.node(loop, .right) or { return false }
	tree := c.scope_tree(ctx.root)
	key := node_key(ts)
	for scope in tree.scopes {
		if scope.kind != .for_statement || node_key(scope.block) != key {
			continue
		}
		for v in scope.variables {
			for r in tree.variables[v].references {
				identifier := tree.references[r].identifier
				if node_start(identifier) >= t.nodes[right].start
					&& node_end(identifier) <= t.nodes[right].end {
					return true
				}
			}
		}
	}
	return false
}

fn (mut c Checker) lint_unicorn_no_useless_length_check(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	mut zero_checks := map[int]bool{}
	mut non_zero_checks := map[int]bool{}
	mut logical_expressions := []int{}
	for node in un_enter_order(t) {
		match t.typ(node) {
			.binary_expression {
				if !unulc_is_length_compare_zero(t, node) || !un_is_logical(t, t.nodes[node].parent) {
					continue
				}
				operator := t.string_of(node, .operator) or { '' }
				if operator == '===' {
					zero_checks[node] = true
				} else if operator in ['>', '!=='] {
					non_zero_checks[node] = true
				}
			}
			.if_statement {
				stats.checked++
				if finding := c.unulc_for_of(mut ctx, node) {
					findings << finding
				}
			}
			.logical_expression {
				parent := t.nodes[node].parent
				if un_is_logical(t, node) && !(t.typ(parent) == .logical_expression
					&& (t.string_of(parent, .operator) or { '' }) == (t.string_of(node, .operator) or {
					''
				})) {
					logical_expressions << node
				}
			}
			else {}
		}
	}
	for logical in logical_expressions {
		stats.checked++
		operator := t.string_of(logical, .operator) or { continue }
		mut conditions := []int{}
		unulc_flat(t, logical, mut conditions)
		for index, node in conditions {
			method := if operator == '||' && node in zero_checks {
				'every'
			} else if operator == '&&' && node in non_zero_checks {
				'some'
			} else {
				continue
			}
			previous := if index > 0 { conditions[index - 1] } else { -1 }
			next := if index + 1 < conditions.len { conditions[index + 1] } else { -1 }
			is_leading := next >= 0 && c.unulc_is_matching_call(mut ctx, next, method, node)
			if !is_leading && !(previous >= 0 && c.unulc_is_matching_call(mut ctx, previous, method, node)) {
				continue
			}
			// Removing a leading check evaluates the arguments for an empty array; removing a
			// trailing one ignores callbacks that change the length of the array.
			safe := if is_leading {
				(t.list(next, .arguments) or { []int{} }).all(!un_has_side_effect(t, it))
			} else {
				args := t.list(previous, .arguments) or { []int{} }
				args.len > 0 && un_is_side_effect_free_function(t, args[0])
			}
			property := t.node(t.node(node, .left) or { continue }, .property) or { continue }
			mut finding := Finding{
				stmt:       c.position_range(t.nodes[property].start, t.nodes[node].end)
				message_id: if node in zero_checks { 'zero' } else { 'non-zero' }
			}
			if fix := c.unulc_remove_length_check(t, tokens, node) {
				finding = if safe {
					Finding{
						...finding
						has_fix: true
						fix:     fix
					}
				} else {
					Finding{
						...finding
						suggestions: [
							Suggestion{
								message_id: 'remove-length-check'
								fix:        fix
							},
						]
					}
				}
			}
			findings << finding
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unulc_for_of is the check of `if (array.length > 0) for (… of array) …`.
fn (mut c Checker) unulc_for_of(mut ctx UnCtx, node int) ?Finding {
	t := ctx.t
	tokens := ctx.tokens
	// getGuardedForOfStatement
	if t.node(node, .alternate) != none {
		return none
	}
	loop := un_single_statement(t, t.node(node, .consequent)?)
	if loop < 0 || t.typ(loop) != .for_of_statement || (t.flag(loop, .await_) or { false }) {
		return none
	}
	check := t.node(node, .test)?
	if !unulc_is_length_compare_zero(t, check)
		|| (t.string_of(check, .operator) or { '' }) !in ['>', '!=='] {
		return none
	}
	right := t.node(loop, .right)?
	object := t.node(t.node(check, .left)?, .object)?
	if !c.un_is_same_reference(t, object, right) || c.unulc_loop_binding_in_right(ctx, loop)
		|| c.un_is_known_non_indexed_collection(mut ctx, right) {
		return none
	}
	property := t.node(t.node(check, .left)?, .property)?
	finding := Finding{
		stmt:       c.position_range(t.nodes[property].start, t.nodes[check].end)
		message_id: 'for-of'
	}
	start_line, _ := t.line_column(t.nodes[loop].start)
	end_line, _ := t.line_column(t.nodes[loop].end)
	can_unindent := start_line == end_line
		|| (c.unulc_starts_at_line_indent(t, node) && c.unulc_starts_at_line_indent(t, loop))
	if can_unindent && !un_has_multiline_token(t, tokens, loop)
		&& !un_would_remove_comments(tokens, t.nodes[node].start, t.nodes[node].end, [
		un_range(t, loop),
	]) {
		return Finding{
			...finding
			has_fix: true
			fix:     fix_replace_range(t.nodes[node].start, t.nodes[node].end, un_reindent_text(c.un_text(t,
				loop), c.un_indent_string(t, loop), c.un_indent_string(t, node)))
		}
	}
	return finding
}

// unulc_starts_at_line_indent ports startsAtLineIndent: only white space before the node on its
// line.
fn (c &Checker) unulc_starts_at_line_indent(t &estree.EsTree, node int) bool {
	start := t.nodes[node].start
	return un_line_start(c.src, start) + c.un_indent_string(t, node).len == start
}
