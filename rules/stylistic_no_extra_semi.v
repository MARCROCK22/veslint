module rules

import estree
import time

// Port of the `@stylistic/no-extra-semi` rule of @stylistic/eslint-plugin 5.10.0, with its fixes.

const snes_messages = {
	'unexpected': 'Unnecessary semicolon.'
}

fn (mut c Checker) lint_stylistic_no_extra_semi(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		node := step.node
		if step.leave {
			continue
		}
		match t.typ(node) {
			.empty_statement {
				stats.checked++
				parent := t.nodes[node].parent
				// Reports this empty statement, except if the parent node is a loop.
				if parent >= 0 && t.typ(parent) in [.for_statement, .for_in_statement,
					.for_of_statement, .while_statement, .do_while_statement, .if_statement,
					.labeled_statement, .with_statement] {
					continue
				}
				findings << c.snes_report(t, tokens, t.nodes[node].start, t.nodes[node].end)
			}
			.class_body {
				stats.checked++
				// Checks tokens from the head of this class body (0 is `{`).
				first := un_first_token(t, tokens, node, 1) or { continue }
				c.snes_check_part_of_class_body(t, tokens, first, mut findings)
			}
			.method_definition, .property_definition, .accessor_property, .static_block,
			.ts_abstract_method_definition, .ts_abstract_property_definition {
				stats.checked++
				first := tokens.after(t.nodes[node].end, false) or { continue }
				c.snes_check_part_of_class_body(t, tokens, first, mut findings)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// snes_check_part_of_class_body ports checkForPartOfClassBody: the semicolons among the
// punctuators from `first_token` to the next other token or `}`.
fn (c &Checker) snes_check_part_of_class_body(t &estree.EsTree, tokens &SourceTokens, first_token SourceToken, mut findings []Finding) {
	mut token := first_token
	for token.kind == .punctuator && !c.token_is(token, '}') {
		if c.token_is(token, ';') {
			findings << c.snes_report(t, tokens, token.start, token.end)
		}
		token = tokens.after(token.end, false) or { return }
	}
}

// snes_report reports the node or token at `start`..`end`, with the fix of FixTracker
// (retainSurroundingTokens, then remove) when it is fixable.
fn (c &Checker) snes_report(t &estree.EsTree, tokens &SourceTokens, start int, end int) Finding {
	before := tokens.before(start, false)
	after := tokens.after(end, false)
	// isFixable: a string after it must not become a directive.
	mut fixable := true
	if next := after {
		if next.kind == .string_ {
			string_node := sty_node_by_range_index(t, next.start)
			parent := if string_node >= 0 { t.nodes[string_node].parent } else { -1 }
			fixable = !(parent >= 0 && snes_is_top_level_expression_statement(t, parent))
		}
	}
	retained_start := if b := before { b.start } else { start }
	retained_end := if a := after { a.end } else { end }
	fix_start := if retained_start < start { retained_start } else { start }
	fix_end := if retained_end > end { retained_end } else { end }
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: 'unexpected'
		has_fix:    fixable
		fix:        fix_replace_range(fix_start, fix_end, c.src[fix_start..start] + c.src[end..fix_end])
	}
}

// snes_is_top_level_expression_statement ports isTopLevelExpressionStatement.
fn snes_is_top_level_expression_statement(t &estree.EsTree, node int) bool {
	if t.typ(node) != .expression_statement {
		return false
	}
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	return t.typ(parent) == .program
		|| (t.typ(parent) == .block_statement && unb_is_function(t, t.nodes[parent].parent))
}
