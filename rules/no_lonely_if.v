module rules

import estree
import time

// Port of the `no-lonely-if` rule of ESLint 10.15.0 (it has no options), with its fix.

const nli_messages = {
	'unexpectedLonelyIf': 'Unexpected if as the only statement in an else block.'
}

fn (mut c Checker) lint_no_lonely_if(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .if_statement {
			continue
		}
		stats.checked++
		parent := t.nodes[node].parent
		if parent < 0 || t.typ(parent) != .block_statement {
			continue
		}
		body := t.list(parent, .body) or { continue }
		if body.len != 1 {
			continue
		}
		block := t.ts_node(parent) or { continue }
		statement := t.ts_node(node) or { continue }
		if c.cu_braces_necessary(root, block, [statement]) {
			continue
		}
		grandparent := t.nodes[parent].parent
		if grandparent < 0 || t.typ(grandparent) != .if_statement
			|| t.node(grandparent, .alternate) or { -1 } != parent {
			continue
		}
		mut has_fix := false
		mut fix := Fix{}
		if f := c.nli_fix(t, tokens, node, parent) {
			has_fix, fix = c.merge_fixes([f])!
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'unexpectedLonelyIf'
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nli_fix is the fix of the rule: the block of the `else` becomes the `if` it holds, unless a
// comment is in the block or ASI would join the `if` to what follows.
fn (c &Checker) nli_fix(t &estree.EsTree, tokens &SourceTokens, node int, parent int) ?Fix {
	opening := un_first_token(t, tokens, parent, 0)?
	closing := un_last_token(t, tokens, parent)?
	else_keyword := tokens.before(opening.start, false)?
	token_after := tokens.after(closing.end, false)
	consequent := t.node(node, .consequent)?
	last_if_token := un_last_token(t, tokens, consequent)?
	start, end := t.nodes[node].start, t.nodes[node].end
	// Don't fix if there are any non-whitespace characters interfering (e.g. comments).
	if js_trim(c.src[opening.end..start]) != '' || js_trim(c.src[end..closing.start]) != '' {
		return none
	}
	last_value := c.src[last_if_token.start..last_if_token.end]
	if after := token_after {
		value := c.src[after.start..after.end]
		if t.typ(consequent) != .block_statement && last_value != ';'
			&& (!es_has_line_break(c.src[t.nodes[consequent].end..after.start])
				|| (value.len > 0 && value[0] in [`(`, `[`, `/`, `+`, `\``, `-`])
				|| last_value in ['++', '--']) {
			return none
		}
	}
	prefix := if else_keyword.end == opening.start { ' ' } else { '' }
	return fix_replace_range(opening.start, closing.end, prefix + c.src[start..end])
}
