module rules

import estree
import time
import x.json2

// Port of the `@stylistic/nonblock-statement-body-position` rule of @stylistic/eslint-plugin
// 5.10.0, with its options (`"beside"`, the default, `"below"` or `"any"`, and `overrides` per
// keyword: `if`, `else`, `while`, `do` and `for`) and its fixes.

const snsbp_messages = {
	'expectNoLinebreak': 'Expected no linebreak before this statement.'
	'expectLinebreak':   'Expected a linebreak before this statement.'
}

struct SnsbpOptions {
	style     string
	overrides map[string]string
}

fn snsbp_options(given []json2.Any) !SnsbpOptions {
	options := sty_options(given, [json2.Any('beside')])
	mut overrides := map[string]string{}
	if object := sty_option_object(options, 1)['overrides'] {
		if object is map[string]json2.Any {
			for key, value in object {
				if value is string {
					overrides[key] = value
				}
			}
		}
	}
	return SnsbpOptions{
		style:     sty_option_string(options, 0, 'beside')
		overrides: overrides
	}
}

fn (mut c Checker) lint_stylistic_nonblock_statement_body_position(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := snsbp_options(c.rule_options(stylistic_nonblock_statement_body_position))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.if_statement {
				stats.checked++
				if consequent := t.node(node, .consequent) {
					c.snsbp_validate(t, tokens, consequent, 'if', options, mut findings)
				}
				// Check the `else`, but not an `else if`.
				if alternate := t.node(node, .alternate) {
					if t.typ(alternate) != .if_statement {
						c.snsbp_validate(t, tokens, alternate, 'else', options, mut findings)
					}
				}
			}
			.while_statement, .do_while_statement, .for_statement, .for_in_statement,
			.for_of_statement {
				stats.checked++
				keyword := match t.typ(node) {
					.while_statement { 'while' }
					.do_while_statement { 'do' }
					else { 'for' }
				}
				if body := t.node(node, .body) {
					c.snsbp_validate(t, tokens, body, keyword, options, mut findings)
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// snsbp_validate ports validateStatement.
fn (c &Checker) snsbp_validate(t &estree.EsTree, tokens &SourceTokens, node int, keyword string, options SnsbpOptions, mut findings []Finding) {
	option := options.overrides[keyword] or { options.style }
	if t.typ(node) == .block_statement || option == 'any' {
		return
	}
	start := t.nodes[node].start
	before := tokens.before(start, false) or { return }
	on_same_line := sty_same_line_offsets(t, before.end, start)
	if on_same_line && option == 'below' {
		findings << Finding{
			stmt:       c.position_range(start, t.nodes[node].end)
			message_id: 'expectLinebreak'
			has_fix:    true
			fix:        fix_insert_at(start, '\n')
		}
	} else if !on_same_line && option == 'beside' {
		has_comments := tokens.comments_exist_between(before.end, start)
		findings << Finding{
			stmt:       c.position_range(start, t.nodes[node].end)
			message_id: 'expectNoLinebreak'
			has_fix:    !has_comments
			fix:        fix_replace_range(before.end, start, ' ')
		}
	}
}
