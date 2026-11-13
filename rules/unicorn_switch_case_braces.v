module rules

import estree
import json2
import time

// Port of the `unicorn/switch-case-braces` rule of eslint-plugin-unicorn 64.0.0, with its fix.

const uscb_messages = {
	'switch-case-braces/empty':       'Unexpected braces in empty case clause.'
	'switch-case-braces/missing':     'Missing braces in case clause.'
	'switch-case-braces/unnecessary': 'Unnecessary braces in case clause.'
}

fn uscb_options(options []json2.Any) !bool {
	if options.len == 0 {
		return true
	}
	value := options[0]
	return !(value is string && value == 'avoid')
}

fn (mut c Checker) lint_unicorn_switch_case_braces(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	braces_required := uscb_options(c.rule_options(unicorn_switch_case_braces))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .switch_case {
			continue
		}
		stats.checked++
		consequent := t.list(node, .consequent) or { continue }
		if consequent.len == 0 {
			continue
		}
		single_block := consequent.len == 1 && t.typ(consequent[0]) == .block_statement
		body := if single_block { t.list(consequent[0], .body) or { []int{} } } else { []int{} }
		if single_block && body.len == 0 {
			brace := un_first_token(t, tokens, consequent[0], 0) or { continue }
			has_fix, fix := c.merge_fixes(c.uscb_remove_braces(t, tokens, consequent[0]))!
			findings << Finding{
				stmt:       c.position_range(brace.start, brace.end)
				message_id: 'switch-case-braces/empty'
				has_fix:    has_fix
				fix:        fix
			}
		} else if braces_required && !single_block {
			start := if test := t.node(node, .test) {
				t.nodes[test].end
			} else {
				(un_first_token(t, tokens, node, 0) or { continue }).end
			}
			colon := c.un_token_after_punctuator(tokens, start, ':') or { continue }
			last := un_last_token(t, tokens, node) or { continue }
			indent := c.un_indent_string(t, node)
			has_fix, fix := c.merge_fixes([fix_insert_at(colon.end, ' {'),
				fix_insert_at(last.end, '\n${indent}}')])!
			findings << Finding{
				stmt:       c.position_range(t.nodes[node].start, colon.end)
				message_id: 'switch-case-braces/missing'
				has_fix:    has_fix
				fix:        fix
			}
		} else if !braces_required && single_block
			&& body.all(t.typ(it) !in [.variable_declaration, .function_declaration]) {
			brace := un_first_token(t, tokens, consequent[0], 0) or { continue }
			has_fix, fix := c.merge_fixes(c.uscb_remove_braces(t, tokens, consequent[0]))!
			findings << Finding{
				stmt:       c.position_range(brace.start, brace.end)
				message_id: 'switch-case-braces/unnecessary'
				has_fix:    has_fix
				fix:        fix
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// uscb_remove_braces ports removeBraces.
fn (c &Checker) uscb_remove_braces(t &estree.EsTree, tokens &SourceTokens, block int) []Fix {
	opening := un_first_token(t, tokens, block, 0) or { return [] }
	closing := un_last_token(t, tokens, block) or { return [] }
	return [c.un_replace_token_and_spaces_before(opening, ''),
		fix_remove_range(closing.start, closing.end)]
}
