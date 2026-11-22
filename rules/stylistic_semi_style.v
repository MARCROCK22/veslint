module rules

import estree
import time
import x.json2

// Port of the `@stylistic/semi-style` rule of @stylistic/eslint-plugin 6.0.1, with its option
// (`"last"`, the default, or `"first"`) and its fixes.

const ssms_messages = {
	'expectedSemiColon': 'Expected this semicolon to be at {{pos}}.'
}

fn ssms_options(given []json2.Any) !string {
	return sty_option_string(sty_options(given, decoded_default_options(stylistic_semi_style)),
		0, 'last')
}

fn (mut c Checker) lint_stylistic_semi_style(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	option := ssms_options(c.rule_options(stylistic_semi_style))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		node := step.node
		if step.leave {
			continue
		}
		match t.typ(node) {
			.break_statement, .continue_statement, .debugger_statement, .do_while_statement,
			.export_all_declaration, .export_default_declaration, .export_named_declaration,
			.expression_statement, .import_declaration, .return_statement, .throw_statement,
			.variable_declaration, .property_definition, .accessor_property {
				stats.checked++
				if option == 'first' && ssms_is_last_child(t, node) {
					continue
				}
				last_token := un_last_token(t, tokens, node) or { continue }
				if c.token_is(last_token, ';') {
					c.ssms_check(t, tokens, last_token, option, mut findings)
				}
			}
			.for_statement {
				stats.checked++
				if init := t.node(node, .init) {
					if semi := c.un_token_after_punctuator(tokens, t.nodes[init].end, ';') {
						c.ssms_check(t, tokens, semi, 'last', mut findings)
					}
				}
				if test := t.node(node, .test) {
					if semi := c.un_token_after_punctuator(tokens, t.nodes[test].end, ';') {
						c.ssms_check(t, tokens, semi, 'last', mut findings)
					}
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ssms_children ports getChildren: the statements or members of a block, -1 for other nodes.
fn ssms_children(t &estree.EsTree, node int) ?[]int {
	return match t.typ(node) {
		.block_statement, .static_block, .program, .class_body { t.list(node, .body) }
		.switch_case { t.list(node, .consequent) }
		else { none }
	}
}

// ssms_is_last_child ports isLastChild.
fn ssms_is_last_child(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 {
		return true
	}
	if t.typ(parent) == .if_statement {
		consequent := t.node(parent, .consequent) or { -1 }
		if consequent == node && t.node(parent, .alternate) != none {
			// Before the `else` keyword.
			return true
		}
	}
	if t.typ(parent) == .do_while_statement {
		// Before the `while` keyword.
		return true
	}
	list := ssms_children(t, parent) or { return false }
	return list.len > 0 && list.last() == node
}

// ssms_check ports check.
fn (c &Checker) ssms_check(t &estree.EsTree, tokens &SourceTokens, semi SourceToken, expected string, mut findings []Finding) {
	prev := tokens.before(semi.start, false)
	next := tokens.after(semi.end, false)
	prev_is_same_line := if p := prev { sty_same_line(t, p, semi) } else { true }
	next_is_same_line := if n := next { sty_same_line(t, semi, n) } else { true }
	if !((expected == 'last' && !prev_is_same_line) || (expected == 'first' && !next_is_same_line)) {
		return
	}
	mut fixable := true
	if p := prev {
		if n := next {
			fixable = !tokens.comments_exist_between(p.end, n.start)
		}
	}
	start := if p := prev { p.end } else { semi.start }
	end := if n := next { n.start } else { semi.end }
	findings << Finding{
		stmt:       c.position_range(semi.start, semi.end)
		message_id: 'expectedSemiColon'
		data:       {
			'pos': if expected == 'last' {
				'the end of the previous line'
			} else {
				'the beginning of the next line'
			}
		}
		has_fix:    fixable
		fix:        fix_replace_range(start, end, if expected == 'last' { ';\n' } else { '\n;' })
	}
}
