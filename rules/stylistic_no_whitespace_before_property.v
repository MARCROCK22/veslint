module rules

import estree
import time

// Port of the `@stylistic/no-whitespace-before-property` rule of @stylistic/eslint-plugin 5.10.0,
// with its fixes: whitespace before the property of a MemberExpression, the index of a
// TSIndexedAccessType, the right side of a TSQualifiedName and the qualifier of a TSImportType.

const snwbp_messages = {
	'unexpectedWhitespace': 'Unexpected whitespace before property {{propName}}.'
}

fn (mut c Checker) lint_stylistic_no_whitespace_before_property(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// In the order of ESLint's traversal: reports that start at the same place keep it.
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.member_expression {
				stats.checked++
				c.snwbp_member(t, tokens, node, mut findings)
			}
			.ts_indexed_access_type {
				stats.checked++
				index_type := t.node(node, .index_type) or { continue }
				right := c.snwbp_bracket_before(tokens, t.nodes[index_type].start) or { continue }
				left := tokens.before(right.start, false) or { continue }
				c.snwbp_report(t, tokens, node, left.end, right.start, c.un_text(t, index_type),
					'', false, mut findings)
			}
			.ts_qualified_name {
				stats.checked++
				left := t.node(node, .left) or { continue }
				right := t.node(node, .right) or { continue }
				c.snwbp_report(t, tokens, node, t.nodes[left].end, t.nodes[right].start,
					c.un_text(t, right), '.', false, mut findings)
			}
			.ts_import_type {
				stats.checked++
				qualifier := t.node(node, .qualifier) or { continue }
				qualifier_start := t.nodes[qualifier].start
				dot := tokens.before(qualifier_start, false) or { continue }
				left := tokens.before(dot.start, false) or { continue }
				c.snwbp_report(t, tokens, node, left.end, qualifier_start, c.un_text(t, qualifier),
					'.', false, mut findings)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// snwbp_member ports the MemberExpression listener.
fn (c &Checker) snwbp_member(t &estree.EsTree, tokens &SourceTokens, node int, mut findings []Finding) {
	object := t.node(node, .object) or { return }
	property := t.node(node, .property) or { return }
	if !sty_same_line_offsets(t, t.nodes[object].end, t.nodes[property].start) {
		return
	}
	computed := t.flag(node, .computed) or { false }
	optional := t.flag(node, .optional) or { false }
	mut right := SourceToken{}
	mut left := SourceToken{}
	if computed {
		right = c.snwbp_bracket_before(tokens, t.nodes[property].start) or { return }
		left = tokens.before(right.start, false) or { return }
		if optional {
			left = tokens.before(left.start, false) or { return }
		}
	} else {
		right = un_first_token(t, tokens, property, 0) or { return }
		dot := tokens.before(right.start, false) or { return }
		left = tokens.before(dot.start, false) or { return }
	}
	replacement := if optional {
		'?.'
	} else if !computed {
		'.'
	} else {
		''
	}
	// If the object is a number literal, fixing it to something like 5.toString() would cause a
	// SyntaxError.
	prevent_fix := !computed && !optional && t.typ(object) == .literal
		&& t.get(object, .value) is f64 && un_is_decimal_integer(un_raw(t, object))
	c.snwbp_report(t, tokens, node, left.end, right.start, c.un_text(t, property), replacement,
		prevent_fix, mut findings)
}

// snwbp_bracket_before ports getTokenBefore(node, isOpeningBracketToken): the last `[` before
// `offset`.
fn (c &Checker) snwbp_bracket_before(tokens &SourceTokens, offset int) ?SourceToken {
	for i := source_tokens_index(tokens.tokens, offset) - 1; i >= 0; i-- {
		if c.token_is(tokens.tokens[i], '[') {
			return tokens.tokens[i]
		}
	}
	return none
}

// snwbp_report ports reportError when there is whitespace between what ends at `left_end` and what
// starts at `right_start`, with the fix of safeReplaceTextBetween (none when comments are in
// between).
fn (c &Checker) snwbp_report(t &estree.EsTree, tokens &SourceTokens, node int, left_end int, right_start int, prop_name string, replacement string, prevent_fix bool, mut findings []Finding) {
	if !tokens.is_space_between(left_end, right_start) {
		return
	}
	has_fix := !prevent_fix && !tokens.comments_exist_between(left_end, right_start)
	findings << Finding{
		stmt:       c.position_range(t.nodes[node].start, t.nodes[node].end)
		message_id: 'unexpectedWhitespace'
		data:       {
			'propName': prop_name
		}
		has_fix:    has_fix
		fix:        if has_fix {
			fix_replace_range(left_end, right_start, replacement)
		} else {
			Fix{}
		}
	}
}
