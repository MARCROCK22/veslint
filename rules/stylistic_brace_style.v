module rules

import estree
import time
import x.json2

// Port of the `@stylistic/brace-style` rule of @stylistic/eslint-plugin 6.0.1, with its options
// (`"1tbs"`, the default, `"stroustrup"` or `"allman"`, and `allowSingleLine`) and its fixes.

const sbs_messages = {
	'nextLineOpen':    'Opening curly brace does not appear on the same line as controlling statement.'
	'sameLineOpen':    'Opening curly brace appears on the same line as controlling statement.'
	'blockSameLine':   'Statement inside of curly braces should be on next line.'
	'nextLineClose':   'Closing curly brace does not appear on the same line as the subsequent block.'
	'singleLineClose': 'Closing curly brace should be on the same line as opening curly brace or on the line after the previous block.'
	'sameLineClose':   'Closing curly brace appears on the same line as the subsequent block.'
}

struct SbsOptions {
	style             string
	allow_single_line bool
}

fn sbs_options(given []json2.Any) !SbsOptions {
	options := sty_options(given, [json2.Any('1tbs'), json2.Any({
		'allowSingleLine': json2.Any(false)
	})])
	return SbsOptions{
		style:             sty_option_string(options, 0, '1tbs')
		allow_single_line: sty_option_bool(sty_option_object(options, 1), 'allowSingleLine') or {
			false
		}
	}
}

fn (mut c Checker) lint_stylistic_brace_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := sbs_options(c.rule_options(stylistic_brace_style))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.block_statement {
				parent := t.nodes[node].parent
				if parent >= 0 && t.typ(parent) in [.program, .block_statement, .static_block, .switch_case] {
					continue
				}
				stats.checked++
				open := un_first_token(t, tokens, node, 0) or { continue }
				close := un_last_token(t, tokens, node) or { continue }
				c.sbs_validate_pair(t, tokens, open, close, options, mut findings)
			}
			.static_block {
				stats.checked++
				// Skip the `static` token.
				open := un_first_token(t, tokens, node, 1) or { continue }
				close := un_last_token(t, tokens, node) or { continue }
				c.sbs_validate_pair(t, tokens, open, close, options, mut findings)
			}
			.class_body, .ts_module_block {
				stats.checked++
				open := un_first_token(t, tokens, node, 0) or { continue }
				close := un_last_token(t, tokens, node) or { continue }
				c.sbs_validate_pair(t, tokens, open, close, options, mut findings)
			}
			.switch_statement {
				stats.checked++
				close := un_last_token(t, tokens, node) or { continue }
				cases := t.list(node, .cases) or { []int{} }
				open := tokens.before(if cases.len > 0 {
					t.nodes[cases[0]].start
				} else {
					close.start
				}, false) or { continue }
				c.sbs_validate_pair(t, tokens, open, close, options, mut findings)
			}
			.if_statement {
				consequent := t.node(node, .consequent) or { continue }
				if t.typ(consequent) == .block_statement && t.node(node, .alternate) != none {
					stats.checked++
					close_brace := un_last_token(t, tokens, consequent) or { continue }
					c.sbs_validate_before_keyword(t, tokens, close_brace, options, mut findings)
				}
			}
			.try_statement {
				stats.checked++
				block := t.node(node, .block) or { continue }
				close_brace := un_last_token(t, tokens, block) or { continue }
				c.sbs_validate_before_keyword(t, tokens, close_brace, options, mut findings)
				handler := t.node(node, .handler) or { continue }
				if t.node(node, .finalizer) != none {
					body := t.node(handler, .body) or { continue }
					handler_curly := un_last_token(t, tokens, body) or { continue }
					c.sbs_validate_before_keyword(t, tokens, handler_curly, options, mut
						findings)
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) sbs_report(token SourceToken, message_id string, fix ?Fix, mut findings []Finding) {
	findings << Finding{
		stmt:       c.position_range(token.start, token.end)
		message_id: message_id
		has_fix:    fix != none
		fix:        fix or { Fix{} }
	}
}

// sbs_validate_pair ports validateCurlyPair.
fn (c &Checker) sbs_validate_pair(t &estree.EsTree, tokens &SourceTokens, open SourceToken, close SourceToken, options SbsOptions, mut findings []Finding) {
	before_open := tokens.before(open.start, false) or { return }
	before_close := tokens.before(close.start, false) or { return }
	after_open := tokens.after(open.end, false) or { return }
	single_line_exception := options.allow_single_line && sty_same_line(t, open, close)
	is_allman := options.style == 'allman'
	if !is_allman && !sty_same_line(t, before_open, open) {
		c.sbs_report(open, 'nextLineOpen', sfcs_safe_replace(tokens, before_open, open, ' '), mut
			findings)
	}
	if is_allman && sty_same_line(t, before_open, open) && !single_line_exception {
		c.sbs_report(open, 'sameLineOpen', fix_insert_at(open.start, '\n'), mut findings)
	}
	if sty_same_line(t, open, after_open) && after_open.start != close.start
		&& !single_line_exception {
		c.sbs_report(open, 'blockSameLine', fix_insert_at(open.end, '\n'), mut findings)
	}
	if sty_same_line(t, before_close, close) && before_close.start != open.start
		&& !single_line_exception {
		c.sbs_report(close, 'singleLineClose', fix_insert_at(close.start, '\n'), mut findings)
	}
}

// sbs_validate_before_keyword ports validateCurlyBeforeKeyword.
fn (c &Checker) sbs_validate_before_keyword(t &estree.EsTree, tokens &SourceTokens, close_brace SourceToken, options SbsOptions, mut findings []Finding) {
	keyword := tokens.after(close_brace.end, false) or { return }
	if options.style == '1tbs' && !sty_same_line(t, close_brace, keyword) {
		c.sbs_report(close_brace, 'nextLineClose', sfcs_safe_replace(tokens, close_brace, keyword, ' '), mut
			findings)
	}
	if options.style != '1tbs' && sty_same_line(t, close_brace, keyword) {
		c.sbs_report(close_brace, 'sameLineClose', fix_insert_at(close_brace.end, '\n'), mut findings)
	}
}
