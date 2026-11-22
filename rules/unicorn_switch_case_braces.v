module rules

import estree
import json2
import time
import treesitter { node_start }

// Port of the `unicorn/switch-case-braces` rule of eslint-plugin-unicorn 79.0.0, with its fix.

const uscb_messages = {
	'switch-case-braces/empty':       'Unexpected braces in empty case clause.'
	'switch-case-braces/missing':     'Missing braces in case clause.'
	'switch-case-braces/unnecessary': 'Unnecessary braces in case clause.'
}

// uscb_options reads the option: 'always' (the default), 'avoid' or 'single-statement'.
fn uscb_options(options []json2.Any) !string {
	if options.len == 0 {
		return 'always'
	}
	value := options[0]
	return if value is string { value } else { 'always' }
}

// uscb_needs_case_block ports needsCaseBlock: a declaration that a case clause can only hold in a
// block of its own.
fn uscb_needs_case_block(t &estree.EsTree, node int) bool {
	return (t.typ(node) == .variable_declaration && (t.string_of(node, .kind) or { '' }) != 'var')
		|| t.typ(node) in [.class_declaration, .function_declaration, .ts_declare_function,
		.ts_enum_declaration, .ts_interface_declaration, .ts_module_declaration,
		.ts_type_alias_declaration]
}

// uscb_declaration_allowed_in_avoid_block ports isDeclarationAllowedInAvoidBlock.
fn uscb_declaration_allowed_in_avoid_block(t &estree.EsTree, node int) bool {
	return t.typ(node) == .variable_declaration || uscb_needs_case_block(t, node)
}

fn (mut c Checker) lint_unicorn_switch_case_braces(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	option := uscb_options(c.rule_options(unicorn_switch_case_braces))!
	braces_required := option != 'avoid' && option != 'single-statement'
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
			findings << c.uscb_unnecessary(t, tokens, node, consequent[0], 'switch-case-braces/empty')!
			continue
		}
		if option == 'single-statement' {
			if consequent.len > 1 {
				fixable := consequent.all(!uscb_needs_case_block(t, it))
				findings << c.uscb_missing(t, tokens, node, consequent, fixable)!
				continue
			}
			statement := consequent[0]
			if uscb_needs_case_block(t, statement) {
				findings << c.uscb_missing(t, tokens, node, consequent, false)!
				continue
			}
			if t.typ(statement) == .block_statement && body.len == 1
				&& !uscb_needs_case_block(t, body[0]) {
				findings << c.uscb_unnecessary(t, tokens, node, statement, 'switch-case-braces/unnecessary')!
			}
			continue
		}
		if braces_required && !single_block {
			fixable := !c.uscb_declaration_used_outside_case(root, t, consequent)
			findings << c.uscb_missing(t, tokens, node, consequent, fixable)!
		} else if !braces_required && single_block
			&& body.all(!uscb_declaration_allowed_in_avoid_block(t, it)) {
			findings << c.uscb_unnecessary(t, tokens, node, consequent[0], 'switch-case-braces/unnecessary')!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// uscb_missing reports the missing braces of a case clause, with addBraces as its fix when
// `fixable`.
fn (mut c Checker) uscb_missing(t &estree.EsTree, tokens &SourceTokens, node int, consequent []int, fixable bool) !Finding {
	start := if test := t.node(node, .test) {
		t.nodes[test].end
	} else {
		(un_first_token(t, tokens, node, 0) or { return error('no token') }).end
	}
	colon := c.un_token_after_punctuator(tokens, start, ':') or { return error('no colon') }
	mut has_fix := false
	mut fix := Fix{}
	if fixable {
		// addBraces
		last_consequent := consequent[consequent.len - 1]
		last_end := if comment := un_last_trailing_comment_on_same_line(t, tokens, t.nodes[last_consequent].end) {
			comment.end
		} else {
			(un_last_token(t, tokens, last_consequent) or { return error('no token') }).end
		}
		indent := c.un_indent_string(t, node)
		has_fix, fix = c.merge_fixes([fix_insert_at(colon.end, ' {'),
			fix_insert_at(last_end, '${un_linebreak(c.src)}${indent}}')])!
	}
	return Finding{
		stmt:       c.position_range(t.nodes[node].start, colon.end)
		message_id: 'switch-case-braces/missing'
		has_fix:    has_fix
		fix:        fix
	}
}

// uscb_unnecessary reports the braces of a case clause, with removeBraces as its fix.
fn (mut c Checker) uscb_unnecessary(t &estree.EsTree, tokens &SourceTokens, node int, block int, message_id string) !Finding {
	brace := un_first_token(t, tokens, block, 0) or { return error('no token') }
	has_fix, fix := c.merge_fixes(c.uscb_remove_braces(t, tokens, block))!
	return Finding{
		stmt:       c.position_range(brace.start, brace.end)
		message_id: message_id
		has_fix:    has_fix
		fix:        fix
	}
}

// uscb_declaration_used_outside_case ports isDeclarationUsedOutsideCase: case declarations share
// the scope of the switch, and a new block can hide them from the other cases.
fn (mut c Checker) uscb_declaration_used_outside_case(root C.vt_node, t &estree.EsTree, consequent []int) bool {
	start := t.nodes[consequent[0]].start
	end := t.nodes[consequent[consequent.len - 1]].end
	tree := c.scope_tree(root)
	for statement in consequent {
		if !uscb_needs_case_block(t, statement) {
			continue
		}
		ts := t.ts_node(statement) or { continue }
		for v in c.es_declared_variables(root, ts) {
			for r in tree.variables[v].references {
				reference_start := node_start(tree.references[r].identifier)
				if reference_start < start || reference_start >= end {
					return true
				}
			}
		}
	}
	return false
}

// uscb_last_block_body_token ports getLastBlockBodyToken: the end of the last token (or comment)
// of the body of the block.
fn uscb_last_block_body_token(t &estree.EsTree, tokens &SourceTokens, block int) ?SourceToken {
	body := t.list(block, .body) or { []int{} }
	last_body_token := if body.len > 0 {
		last_statement := body[body.len - 1]
		un_last_trailing_comment_on_same_line(t, tokens, t.nodes[last_statement].end) or {
			un_last_token(t, tokens, last_statement)?
		}
	} else {
		un_first_token(t, tokens, block, 0)?
	}
	comments := tokens.comments_inside(t.nodes[block].start, t.nodes[block].end)
	if comments.len > 0 {
		last_comment := comments[comments.len - 1]
		// `>=`, a comment right after the `{` of an empty block starts where the brace ends.
		if last_comment.start >= last_body_token.end {
			return last_comment
		}
	}
	return last_body_token
}

// uscb_remove_braces ports removeBraces (no fix when it aborts).
fn (c &Checker) uscb_remove_braces(t &estree.EsTree, tokens &SourceTokens, block int) []Fix {
	closing := un_last_token(t, tokens, block) or { return [] }
	if _ := un_last_trailing_comment_on_same_line(t, tokens, closing.end) {
		return []
	}
	opening := un_first_token(t, tokens, block, 0) or { return [] }
	last_block_token := uscb_last_block_body_token(t, tokens, block) or { return [] }
	// The removed range takes the line break with it, so a `//` comment would swallow whatever
	// follows the closing brace on the same line.
	if last_block_token.kind == .line_comment {
		if after := tokens.after(closing.end, false) {
			if un_same_line(t, closing.start, after.start) {
				return []
			}
		}
	}
	return [c.un_replace_token_and_spaces_before(opening, ''),
		fix_remove_range(last_block_token.end, closing.end)]
}
