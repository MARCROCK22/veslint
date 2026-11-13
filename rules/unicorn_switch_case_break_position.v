module rules

import estree
import time

// Port of the `unicorn/switch-case-break-position` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fix.

const uscbp_messages = {
	'switch-case-break-position': 'Move `{{keyword}}` inside the block statement.'
}

fn uscbp_keyword(t &estree.EsTree, node int) ?string {
	return match t.typ(node) {
		.break_statement { 'break' }
		.return_statement { 'return' }
		.continue_statement { 'continue' }
		.throw_statement { 'throw' }
		else { none }
	}
}

fn (mut c Checker) lint_unicorn_switch_case_break_position(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .switch_case {
			continue
		}
		stats.checked++
		consequent := t.list(node, .consequent) or { continue }
		if consequent.len != 2 {
			continue
		}
		last := consequent[1]
		keyword := uscbp_keyword(t, last) or { continue }
		block := consequent[0]
		if t.typ(block) != .block_statement || (t.list(block, .body) or { []int{} }).len == 0 {
			continue
		}
		mut finding := Finding{
			stmt:       c.es_tree_position(t, last)
			message_id: 'switch-case-break-position'
			data:       {
				'keyword': keyword
			}
		}
		if t.typ(last) !in [.return_statement, .throw_statement] {
			has_fix, fix := c.merge_fixes(c.uscbp_fix(t, tokens, block, last))!
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) uscbp_fix(t &estree.EsTree, tokens &SourceTokens, block int, last int) []Fix {
	closing := un_last_token(t, tokens, block) or { return [] }
	// No fix with comments between the block and the statement.
	if tokens.comments_inside(closing.end, t.nodes[last].start).len > 0 {
		return []
	}
	// Nor for a block on a single line.
	if un_same_line(t, t.nodes[block].start, t.nodes[block].end) {
		return []
	}
	// Nor when a comment follows the statement on its line.
	end_line, _ := t.line_column(t.nodes[last].end)
	for comment in tokens.comments_after(t.nodes[last].end) {
		line, _ := t.line_column(comment.start)
		if line == end_line {
			return []
		}
	}
	body := t.list(block, .body) or { return [] }
	indent := c.un_indent_string(t, body.last())
	before_brace := tokens.before(closing.start, true) or { return [] }
	return [fix_insert_at(before_brace.end, '\n${indent}${c.un_text(t, last)}'),
		fix_remove_range(closing.end, t.nodes[last].end)]
}
