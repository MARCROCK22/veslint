module rules

import estree
import os
import time

// Port of the `unicorn/no-anonymous-default-export` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its suggestion.

const unade_messages = {
	'no-anonymous-default-export/error':      'The {{description}} should be named.'
	'no-anonymous-default-export/suggestion': 'Name it as `{{name}}`.'
}

fn (mut c Checker) lint_unicorn_no_anonymous_default_export(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.export_default_declaration {
				stats.checked++
				declaration := t.node(node, .declaration) or { continue }
				if unade_is_anonymous(t, declaration) {
					findings << c.unade_problem(root, t, tokens, declaration, abs_path)
				}
			}
			.assignment_expression {
				stats.checked++
				right := t.node(node, .right) or { continue }
				parent := t.nodes[node].parent
				left := t.node(node, .left) or { continue }
				if !unade_is_anonymous(t, right) || parent < 0
					|| t.typ(parent) != .expression_statement
					|| (t.node(parent, .expression) or { -1 }) != node {
					continue
				}
				if !(un_is_member(t, left, UnMember{
					objects:    ['module']
					properties: ['exports']
					computed:   false
					optional:   false
				}) || (t.typ(left) == .identifier && (t.string_of(left, .name) or { '' }) == 'exports')) {
					continue
				}
				findings << c.unade_problem(root, t, tokens, right, abs_path)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unade_is_anonymous ports isAnonymousClassOrFunction.
fn unade_is_anonymous(t &estree.EsTree, node int) bool {
	if t.typ(node) == .arrow_function_expression {
		return true
	}
	return t.typ(node) in [.function_declaration, .function_expression, .class_declaration,
		.class_expression] && t.node(node, .id) == none
}

fn unade_is_class(t &estree.EsTree, node int) bool {
	return t.typ(node) in [.class_declaration, .class_expression]
}

// unade_export_statement ports getExportStatement: `export default …` or the `module.exports = …;`
// statement.
fn unade_export_statement(t &estree.EsTree, node int) int {
	parent := t.nodes[node].parent
	if t.typ(parent) == .export_default_declaration {
		return parent
	}
	return t.nodes[parent].parent
}

// unade_suggestion_name ports getSuggestionName: the camel-cased file name, free in the scope of
// the node.
fn (mut c Checker) unade_suggestion_name(root C.TSNode, t &estree.EsTree, node int, abs_path string) ?string {
	mut name := os.file_name(abs_path).all_before('.')
	name = ucc_camel_case(name)
	if !un_is_identifier_name(name) {
		return none
	}
	if unade_is_class(t, node) {
		name = un_upper_first(name)
	}
	tree := c.scope_tree(root)
	ts := t.ts_node(node)?
	mut scope := if t.typ(node) in [.function_declaration, .function_expression,
		.arrow_function_expression] {
		tree.function_scope_of(ts)
	} else {
		-1
	}
	if scope < 0 {
		scope = tree.get_scope(ts)
	}
	return un_available_variable_name(tree, name, un_scopes(tree, scope), fn (_ string) bool {
		return true
	})
}

fn (mut c Checker) unade_problem(root C.TSNode, t &estree.EsTree, tokens &SourceTokens, node int, abs_path string) Finding {
	suggestion_name := c.unade_suggestion_name(root, t, node, abs_path) or { '' }
	mut finding := if unade_is_class(t, node) {
		// getClassHeadLocation: from the class to the token before its body.
		body := t.node(node, .body) or { -1 }
		before := tokens.before(t.nodes[body].start, false) or { SourceToken{} }
		Finding{
			stmt:       c.position_range(t.nodes[node].start, before.end)
			message_id: 'no-anonymous-default-export/error'
			data:       {
				'description': 'class'
			}
		}
	} else {
		mut description := c.un_function_name_with_kind(t, node)
		// ` 'name'` at the end goes.
		if description.ends_with("'") {
			quote := description[..description.len - 1].last_index(" '") or { -1 }
			if quote >= 0 {
				description = description[..quote]
			}
		}
		Finding{
			stmt:       c.un_function_head_location(t, node)
			message_id: 'no-anonymous-default-export/error'
			data:       {
				'description': description
			}
		}
	}
	// An arrow function becomes a declaration, only allowed in a statement list.
	statement_parent := t.nodes[unade_export_statement(t, node)].parent
	if suggestion_name == '' || (t.typ(node) == .arrow_function_expression
		&& t.list(statement_parent, .body) == none && t.typ(statement_parent) != .switch_case) {
		return finding
	}
	fixes := c.unade_add_name(t, tokens, node, suggestion_name)
	if fixes.len == 0 {
		return finding
	}
	has_fix, fix := c.merge_fixes(fixes) or { return finding }
	if has_fix {
		finding = Finding{
			...finding
			suggestions: [Suggestion{
				message_id: 'no-anonymous-default-export/suggestion'
				data:       {
					'name': suggestion_name
				}
				fix:        fix
			}]
		}
	}
	return finding
}

// unade_add_name ports addName.
fn (c &Checker) unade_add_name(t &estree.EsTree, tokens &SourceTokens, node int, name string) []Fix {
	match t.typ(node) {
		.class_declaration, .class_expression {
			decorators := t.list(node, .decorators) or { []int{} }
			from := if decorators.len > 0 {
				t.nodes[decorators.last()].end
			} else {
				t.nodes[node].start
			}
			mut at := from
			for {
				token := tokens.after(at, false) or { return [] }
				if token.kind == .keyword && c.src[token.start..token.end] == 'class' {
					return [fix_insert_at(token.end, ' ${name}')]
				}
				at = token.end
			}
		}
		.function_declaration, .function_expression {
			for token in tokens.inside(t.nodes[node].start, t.nodes[node].end, false) {
				if c.token_is(token, '(') {
					before := if token.start > 0 { c.src[token.start - 1] } else { u8(0) }
					return [fix_insert_at(token.start, '${if before == ` ` { '' } else { ' ' }}${name} ')]
				}
			}
			return []
		}
		.arrow_function_expression {
			statement := unade_export_statement(t, node)
			statement_start, statement_end := t.nodes[statement].start, t.nodes[statement].end
			arrow_start, arrow_end := c.un_parenthesized_range(t, tokens, node)
			mut before := c.src[statement_start..arrow_start]
			mut after := c.src[arrow_end..statement_end]
			// The statement is re-emitted on its own line, with the indentation of its line.
			before = un_linebreak(c.src) + c.un_line_indent(statement_start) + before
			// `/\s$/`
			runes := before.runes()
			if runes.len == 0 || js_trim(runes.last().str()) != '' {
				before += ' '
			}
			if !after.ends_with(';') {
				after += ';'
			}
			return [
				fix_replace_range(statement_start, arrow_start, 'const ${name} = '),
				fix_replace_range(arrow_end, statement_end, ';'),
				fix_insert_at(statement_end, '${before}${name}${after}'),
			]
		}
		else {
			return []
		}
	}
}
