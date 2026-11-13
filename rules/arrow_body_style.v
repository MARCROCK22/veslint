module rules

import json2
import time
import treesitter { named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `arrow-body-style` rule of ESLint 10.6.0, with its options and its fixes.

const abs_messages = {
	'unexpectedOtherBlock':  'Unexpected block statement surrounding arrow body.'
	'unexpectedEmptyBlock':  'Unexpected block statement surrounding arrow body; put a value of `undefined` immediately after the `=>`.'
	'unexpectedObjectBlock': 'Unexpected block statement surrounding arrow body; parenthesize the returned value and move it immediately after the `=>`.'
	'unexpectedSingleBlock': 'Unexpected block statement surrounding arrow body; move the returned value immediately after the `=>`.'
	'expectedBlock':         'Expected block statement surrounding arrow body.'
}

struct AbsOptions {
	mode               string // always, as-needed or never
	require_for_object bool
}

// abs_options reads "always", "as-needed" or "never", and requireReturnForObjectLiteral.
fn abs_options(options []json2.Any) !AbsOptions {
	mode := if options.len > 0 { options[0] } else { json2.Any('as-needed') }
	if mode !is string || mode.str() !in ['always', 'as-needed', 'never'] {
		return error('the first option of `${arrow_body_style}` must be "always", "as-needed" or "never"')
	}
	o := option_object(arrow_body_style, if options.len > 1 { options[1..] } else { []json2.Any{} },
		['requireReturnForObjectLiteral'])!
	return AbsOptions{
		mode:               mode.str()
		require_for_object: o.bool_value('requireReturnForObjectLiteral') or { false }
	}
}

fn (mut c Checker) lint_arrow_body_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := abs_options(c.rule_options(arrow_body_style))!
	mut findings := []Finding{}
	never := o.mode == 'never'
	as_needed := o.mode == 'as-needed'
	for node in c.nodes_of_kinds(root, ['arrow_function'], []) {
		body := node_field(node, 'body') or { continue }
		stats.checked++
		if node_kind(body) == 'statement_block' {
			statements := named_children(body).filter(node_kind(it) != 'comment')
			if statements.len != 1 && !never {
				continue
			}
			first_is_return := statements.len > 0 && node_kind(statements[0]) == 'return_statement'
			argument := if first_is_return { first_named(statements[0]) } else { none }
			if as_needed && o.require_for_object && first_is_return {
				if a := argument {
					if node_kind(unwrap_parens(a)) == 'object' {
						continue
					}
				}
			}
			if !(never || (as_needed && first_is_return)) {
				continue
			}
			tokens := c.source_tokens(root)
			message_id := if statements.len == 0 {
				'unexpectedEmptyBlock'
			} else if statements.len > 1 || !first_is_return {
				'unexpectedOtherBlock'
			} else if argument == none {
				'unexpectedSingleBlock'
			} else if second := tokens.after(node_start(statements[0]) + 1, false) {
				if c.src[second.start..second.end] == '{' {
					'unexpectedObjectBlock'
				} else {
					'unexpectedSingleBlock'
				}
			} else {
				'unexpectedSingleBlock'
			}
			mut fixes := []Fix{}
			if statements.len == 1 && first_is_return {
				if a := argument {
					fixes = c.abs_unwrap_fixes(root, node, body, statements[0], a)
				}
			}
			has_fix, fix := c.merge_fixes(fixes) or { false, Fix{} }
			findings << Finding{
				stmt:       position_of(body)
				message_id: message_id
				has_fix:    has_fix
				fix:        fix
			}
		} else if o.mode == 'always'
			|| (as_needed && o.require_for_object && node_kind(unwrap_parens(body)) == 'object') {
			fixes := c.abs_block_fixes(root, node, body)
			has_fix, fix := c.merge_fixes(fixes) or { false, Fix{} }
			findings << Finding{
				stmt:       position_of(unwrap_parens(body))
				message_id: 'expectedBlock'
				has_fix:    has_fix
				fix:        fix
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// abs_unwrap_fixes removes the braces and the `return` of a block that returns a value.
fn (mut c Checker) abs_unwrap_fixes(root C.TSNode, arrow C.TSNode, body C.TSNode, statement C.TSNode, argument C.TSNode) []Fix {
	tokens := c.source_tokens(root)
	body_end := c.es_end(body)
	// A token after the block that would continue the value (hasASIProblem).
	if after := tokens.after(body_end, false) {
		text := c.src[after.start..after.end]
		if after.kind == .punctuator && text.len > 0 && text[0] in [`(`, `[`, `/`, `\``, `+`, `-`] {
			return []Fix{}
		}
	}
	open := tokens.after(node_start(body), false) or { return []Fix{} }
	close := tokens.before(body_end, false) or { return []Fix{} }
	return_token := tokens.after(node_start(statement), false) or { return []Fix{} }
	first_value := tokens.after(return_token.end, false) or { return []Fix{} }
	last_value := tokens.before(c.es_end(statement), false) or { return []Fix{} }
	mut fixes := []Fix{}
	if tokens.comments_exist_between(open.end, first_value.start)
		|| tokens.comments_exist_between(last_value.end, close.start) {
		fixes << fix_remove_range(open.start, open.end)
		fixes << fix_remove_range(close.start, close.end)
		fixes << fix_remove_range(return_token.start, return_token.end)
	} else {
		fixes << fix_remove_range(open.start, first_value.start)
		fixes << fix_remove_range(last_value.end, close.end)
	}
	value := unwrap_parens(argument)
	if c.src[first_value.start..first_value.end] == '{' || node_kind(value) == 'sequence_expression'
		|| (c.nodes_of_kinds(arrow, ['binary_expression'], []).any(operator_of(it) == 'in')
			&& abs_inside_for_init(arrow)) {
		if node_kind(argument) != 'parenthesized_expression' {
			fixes << fix_insert_at(first_value.start, '(')
			fixes << fix_insert_at(last_value.end, ')')
		}
	}
	if c.src[last_value.start..last_value.end] == ';' {
		fixes << fix_remove_range(last_value.start, last_value.end)
	}
	return fixes
}

// abs_inside_for_init ports isInsideForLoopInitializer.
fn abs_inside_for_init(n C.TSNode) bool {
	mut current := n
	for {
		parent := node_parent(current) or { return false }
		if node_kind(parent) == 'for_statement' {
			if init := node_field(parent, 'initializer') {
				if node_key(init) == node_key(current) {
					return true
				}
			}
		}
		current = parent
	}
	return false
}

// abs_block_fixes wraps an expression body in `{return ` and `}`.
fn (mut c Checker) abs_block_fixes(root C.TSNode, arrow C.TSNode, body C.TSNode) []Fix {
	tokens := c.source_tokens(root)
	mut arrow_token := tokens.before(node_start(body), false) or { return []Fix{} }
	for c.src[arrow_token.start..arrow_token.end] != '=>' {
		arrow_token = tokens.before(arrow_token.start, false) or { return []Fix{} }
	}
	first := tokens.after(arrow_token.end, false) or { return []Fix{} }
	last := tokens.before(c.es_end(arrow), false) or { return []Fix{} }
	mut fixes := []Fix{}
	// `(` and `{` of an object (getNodeByRangeIndex: the object, whatever is around it).
	second := tokens.after(first.end, false) or { first }
	if c.src[first.start..first.end] == '(' && second.start > first.start
		&& c.src[second.start..second.end] == '{' && node_kind(second.node) == '{'
		&& node_kind(node_parent(second.node) or { second.node }) == 'object' {
		object := node_parent(second.node) or { return []Fix{} }
		if !es_has_line_break(c.src[first.start..second.start]) {
			fixes << fix_replace_range(first.start, first.end, '{return ')
		} else {
			fixes << fix_replace_range(first.start, first.end, '{')
			fixes << fix_insert_at(second.start, 'return ')
		}
		// findClosingParen: the token after the closest node, from the object up, that is
		// parenthesised.
		mut wrapped := object
		for {
			parent := node_parent(wrapped) or { break }
			if node_kind(parent) == 'parenthesized_expression' {
				break
			}
			wrapped = parent
		}
		closing := tokens.after(c.es_end(wrapped), false) or { return []Fix{} }
		fixes << fix_remove_range(closing.start, closing.end)
		fixes << fix_insert_at(last.end, '}')
	} else {
		fixes << fix_insert_at(first.start, '{return ')
		fixes << fix_insert_at(last.end, '}')
	}
	return fixes
}
