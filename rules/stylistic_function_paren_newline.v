module rules

import estree
import time
import x.json2

// Port of the `@stylistic/function-paren-newline` rule of @stylistic/eslint-plugin 5.10.0, with its
// option (`"multiline"`, the default, `"always"`, `"never"`, `"consistent"`,
// `"multiline-arguments"` or `{ minItems }`) and its fixes.

const sfpn_messages = {
	'expectedBefore':   "Expected newline before ')'."
	'expectedAfter':    "Expected newline after '('."
	'expectedBetween':  'Expected newline between arguments/params.'
	'unexpectedBefore': "Unexpected newline before ')'."
	'unexpectedAfter':  "Unexpected newline after '('."
}

struct SfpnOptions {
	multiline           bool
	multiline_arguments bool
	consistent          bool
	// min_items is -1 when it is undefined, and max_int for `Infinity` (`"never"`).
	min_items int = -1
}

fn sfpn_options(given []json2.Any) !SfpnOptions {
	options := sty_options(given, [json2.Any('multiline')])
	raw := if options.len > 0 { options[0] } else { json2.Any('multiline') }
	if raw is map[string]json2.Any {
		mut min_items := -1
		if value := raw['minItems'] {
			if value is i64 {
				min_items = int(value)
			} else if value is int {
				min_items = value
			} else if value is f64 {
				min_items = int(value)
			}
		}
		return SfpnOptions{
			min_items: min_items
		}
	}
	text := sty_option_string(options, 0, '')
	return SfpnOptions{
		multiline:           text == 'multiline'
		multiline_arguments: text == 'multiline-arguments'
		consistent:          text == 'consistent'
		min_items:           match text {
			'always' { 0 }
			'never' { max_i32 }
			else { -1 }
		}
	}
}

fn (mut c Checker) lint_stylistic_function_paren_newline(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := sfpn_options(c.rule_options(stylistic_function_paren_newline))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		typ := t.typ(node)
		if typ !in [.arrow_function_expression, .call_expression, .function_declaration,
			.function_expression, .import_expression, .new_expression] {
			continue
		}
		stats.checked++
		left, right := c.sfpn_paren_tokens(t, tokens, node) or { continue }
		params := match typ {
			.import_expression {
				mut list := []int{}
				if source := t.node(node, .source) {
					list << source
				}
				if opts := t.node(node, .options) {
					list << opts
				}
				list
			}
			.arrow_function_expression, .function_declaration, .function_expression {
				t.list(node, .params) or { []int{} }
			}
			else {
				t.list(node, .arguments) or { []int{} }
			}
		}
		c.sfpn_validate_parens(t, tokens, left, right, params, options, mut findings)
		if options.multiline_arguments {
			c.sfpn_validate_arguments(t, tokens, left, params, options, mut findings)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sfpn_should_have_newlines ports shouldHaveNewlines.
fn sfpn_should_have_newlines(t &estree.EsTree, elements []int, has_left_newline bool, options SfpnOptions) bool {
	if options.multiline_arguments && elements.len == 1 {
		return has_left_newline
	}
	if options.multiline || options.multiline_arguments {
		for index in 0 .. elements.len - 1 {
			if !sty_same_line_offsets(t, t.nodes[elements[index]].end, t.nodes[elements[index + 1]].start) {
				return true
			}
		}
		return false
	}
	if options.consistent {
		return has_left_newline
	}
	return options.min_items < 0 || elements.len >= options.min_items
}

fn (c &Checker) sfpn_report(token SourceToken, message_id string, fix ?Fix, mut findings []Finding) {
	findings << Finding{
		stmt:       c.position_range(token.start, token.end)
		message_id: message_id
		has_fix:    fix != none
		fix:        fix or { Fix{} }
	}
}

// sfpn_validate_parens ports validateParens.
fn (c &Checker) sfpn_validate_parens(t &estree.EsTree, tokens &SourceTokens, left SourceToken, right SourceToken, elements []int, options SfpnOptions, mut findings []Finding) {
	after_left := tokens.after(left.end, false) or { return }
	before_right := tokens.before(right.start, false) or { return }
	has_left_newline := !sty_same_line(t, left, after_left)
	has_right_newline := !sty_same_line(t, before_right, right)
	needs_newlines := sfpn_should_have_newlines(t, elements, has_left_newline, options)
	if has_left_newline && !needs_newlines {
		c.sfpn_report(left, 'unexpectedAfter', sfcs_safe_replace(tokens, left, after_left, ''), mut
			findings)
	} else if !has_left_newline && needs_newlines {
		c.sfpn_report(left, 'expectedAfter', fix_insert_at(left.end, '\n'), mut findings)
	}
	if has_right_newline && !needs_newlines {
		c.sfpn_report(right, 'unexpectedBefore', sfcs_safe_replace(tokens, before_right, right,
			''), mut findings)
	} else if !has_right_newline && needs_newlines {
		c.sfpn_report(right, 'expectedBefore', fix_insert_at(right.start, '\n'), mut findings)
	}
}

// sfpn_validate_arguments ports validateArguments.
fn (c &Checker) sfpn_validate_arguments(t &estree.EsTree, tokens &SourceTokens, left SourceToken, elements []int, options SfpnOptions, mut findings []Finding) {
	after_left := tokens.after(left.end, false) or { return }
	has_left_newline := !sty_same_line(t, left, after_left)
	needs_newlines := sfpn_should_have_newlines(t, elements, has_left_newline, options)
	for i := 0; i <= elements.len - 2; i++ {
		current := elements[i]
		next := elements[i + 1]
		has_newline := !sty_same_line_offsets(t, t.nodes[current].end, t.nodes[next].start)
		if !has_newline && needs_newlines {
			findings << Finding{
				stmt:       c.position_range(t.nodes[current].start, t.nodes[current].end)
				message_id: 'expectedBetween'
				has_fix:    true
				fix:        fix_insert_at(t.nodes[next].start, '\n')
			}
		}
	}
}

// sfpn_opening_paren_outside_type_parameter is the first token of `list` from `index` that
// isOpeningParenTokenOutsideTypeParameter accepts: a `(` at the level of the `<` and `>` seen so
// far.
fn (c &Checker) sfpn_opening_paren_outside_type_parameter(list []SourceToken, index int) ?SourceToken {
	mut level := 0
	for i := index; i < list.len; i++ {
		token := list[i]
		if c.token_is(token, '<') {
			level++
		}
		if c.token_is(token, '>') {
			level--
		}
		if level == 0 && c.token_is(token, '(') {
			return token
		}
	}
	return none
}

// sfpn_token_after_closing_paren is getTokenAfter(node, isClosingParenToken).
fn (c &Checker) sfpn_token_after_closing_paren(tokens &SourceTokens, offset int) ?SourceToken {
	return c.un_token_after_punctuator(tokens, offset, ')')
}

// sfpn_paren_tokens ports getParenTokens: none when the node has no parentheses.
fn (c &Checker) sfpn_paren_tokens(t &estree.EsTree, tokens &SourceTokens, node int) ?(SourceToken, SourceToken) {
	match t.typ(node) {
		.new_expression, .call_expression {
			callee := t.node(node, .callee)?
			last := un_last_token(t, tokens, node)?
			if t.typ(node) == .new_expression {
				arguments := t.list(node, .arguments) or { []int{} }
				if arguments.len == 0 {
					before_last := tokens.before(last.start, false)?
					if !(c.token_is(before_last, '(') && c.token_is(last, ')')
						&& t.nodes[callee].end < t.nodes[node].end) {
						// `new Foo` has no parentheses.
						return none
					}
				}
			}
			left := c.sfpn_opening_paren_outside_type_parameter(tokens.tokens, source_tokens_index(tokens.tokens,
				t.nodes[callee].end))?
			return left, last
		}
		.function_declaration, .function_expression {
			left := c.sfpn_opening_paren_outside_type_parameter(tokens.tokens, source_tokens_index(tokens.tokens,
				t.nodes[node].start))?
			if left.start >= t.nodes[node].end {
				return none
			}
			params := t.list(node, .params) or { []int{} }
			right := if params.len > 0 {
				c.sfpn_token_after_closing_paren(tokens, t.nodes[params.last()].end)?
			} else {
				tokens.after(left.end, false)?
			}
			return left, right
		}
		.arrow_function_expression {
			skip := if t.flag(node, .async) or { false } { 1 } else { 0 }
			first := un_first_token(t, tokens, node, skip)?
			if !c.token_is(first, '(') {
				// A single parameter without parentheses.
				return none
			}
			params := t.list(node, .params) or { []int{} }
			right := if params.len > 0 {
				c.sfpn_token_after_closing_paren(tokens, t.nodes[params.last()].end)?
			} else {
				tokens.after(first.end, false)?
			}
			return first, right
		}
		.import_expression {
			left := un_first_token(t, tokens, node, 1)?
			right := un_last_token(t, tokens, node)?
			return left, right
		}
		else {
			return none
		}
	}
}
