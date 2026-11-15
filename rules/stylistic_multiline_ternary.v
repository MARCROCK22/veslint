module rules

import estree
import time
import x.json2

// Port of the `@stylistic/multiline-ternary` rule of @stylistic/eslint-plugin 5.10.0, with its
// options (`"always"`, the default, `"always-multiline"` or `"never"`, and `ignoreJSX`) and its
// fixes.

const smtn_messages = {
	'expectedTestCons':   'Expected newline between test and consequent of ternary expression.'
	'expectedConsAlt':    'Expected newline between consequent and alternate of ternary expression.'
	'unexpectedTestCons': 'Unexpected newline between test and consequent of ternary expression.'
	'unexpectedConsAlt':  'Unexpected newline between consequent and alternate of ternary expression.'
}

struct SmtnOptions {
	multiline         bool
	allow_single_line bool
	ignore_jsx        bool
}

fn smtn_options(given []json2.Any) !SmtnOptions {
	options := sty_options(given, [json2.Any('always')])
	style := sty_option_string(options, 0, 'always')
	return SmtnOptions{
		multiline:         style != 'never'
		allow_single_line: style == 'always-multiline'
		ignore_jsx:        sty_option_bool(sty_option_object(options, 1), 'ignoreJSX') or { false }
	}
}

fn (mut c Checker) lint_stylistic_multiline_ternary(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := smtn_options(c.rule_options(stylistic_multiline_ternary))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave || t.typ(step.node) != .conditional_expression {
			continue
		}
		stats.checked++
		c.smtn_check(t, tokens, step.node, options, mut findings)!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// smtn_token_after_not_closing_paren is getTokenAfter(node, isNotClosingParenToken).
fn (c &Checker) smtn_token_after_not_closing_paren(tokens &SourceTokens, offset int) ?SourceToken {
	for i := source_tokens_index(tokens.tokens, offset); i < tokens.tokens.len; i++ {
		if !c.token_is(tokens.tokens[i], ')') {
			return tokens.tokens[i]
		}
	}
	return none
}

fn (c &Checker) smtn_check(t &estree.EsTree, tokens &SourceTokens, node int, options SmtnOptions, mut findings []Finding) ! {
	test := t.node(node, .test) or { return }
	consequent := t.node(node, .consequent) or { return }
	question := c.smtn_token_after_not_closing_paren(tokens, t.nodes[test].end) or { return }
	colon := c.smtn_token_after_not_closing_paren(tokens, t.nodes[consequent].end) or { return }
	first_of_test := un_first_token(t, tokens, node, 0) or { return }
	last_of_test := tokens.before(question.start, false) or { return }
	first_of_consequent := tokens.after(question.end, false) or { return }
	last_of_consequent := tokens.before(colon.start, false) or { return }
	first_of_alternate := tokens.after(colon.end, false) or { return }
	test_and_consequent_same_line := sty_same_line(t, last_of_test, first_of_consequent)
	consequent_and_alternate_same_line := sty_same_line(t, last_of_consequent, first_of_alternate)
	has_comments := tokens.comments_inside(t.nodes[node].start, t.nodes[node].end).len > 0
	if options.ignore_jsx {
		parent := t.nodes[node].parent
		if parent >= 0 && t.typ(parent) in [.jsx_element, .jsx_fragment, .jsx_expression_container] {
			return
		}
	}
	if !options.multiline {
		if !test_and_consequent_same_line {
			mut fixes := []Fix{}
			if !has_comments {
				if !sty_same_line(t, last_of_test, question) {
					fixes << fix_remove_range(last_of_test.end, question.start)
				}
				if !sty_same_line(t, question, first_of_consequent) {
					fixes << fix_remove_range(question.end, first_of_consequent.start)
				}
			}
			has_fix, fix := c.merge_fixes(fixes)!
			findings << Finding{
				stmt:       c.position_range(first_of_test.start, last_of_test.end)
				message_id: 'unexpectedTestCons'
				has_fix:    has_fix
				fix:        fix
			}
		}
		if !consequent_and_alternate_same_line {
			mut fixes := []Fix{}
			if !has_comments {
				if !sty_same_line(t, last_of_consequent, colon) {
					fixes << fix_remove_range(last_of_consequent.end, colon.start)
				}
				if !sty_same_line(t, colon, first_of_alternate) {
					fixes << fix_remove_range(colon.end, first_of_alternate.start)
				}
			}
			has_fix, fix := c.merge_fixes(fixes)!
			findings << Finding{
				stmt:       c.position_range(first_of_consequent.start, last_of_consequent.end)
				message_id: 'unexpectedConsAlt'
				has_fix:    has_fix
				fix:        fix
			}
		}
		return
	}
	if options.allow_single_line
		&& sty_same_line_offsets(t, t.nodes[node].start, t.nodes[node].end) {
		return
	}
	if test_and_consequent_same_line {
		findings << Finding{
			stmt:       c.position_range(first_of_test.start, last_of_test.end)
			message_id: 'expectedTestCons'
			has_fix:    !has_comments
			fix:        fix_replace_range(last_of_test.end, question.start, '\n')
		}
	}
	if consequent_and_alternate_same_line {
		findings << Finding{
			stmt:       c.position_range(first_of_consequent.start, last_of_consequent.end)
			message_id: 'expectedConsAlt'
			has_fix:    !has_comments
			fix:        fix_replace_range(last_of_consequent.end, colon.start, '\n')
		}
	}
}
