module rules

import estree
import json2
import time

// Port of the `unicorn/no-typeof-undefined` rule of eslint-plugin-unicorn 64.0.0, with its fix and
// its suggestion.

const unty_messages = {
	'no-typeof-undefined/error':      'Compare with `undefined` directly instead of using `typeof`.'
	'no-typeof-undefined/suggestion': 'Switch to `… {{operator}} undefined`.'
}

fn unty_options(options []json2.Any) !bool {
	o := option_object(unicorn_no_typeof_undefined, options, ['checkGlobalVariables'])!
	return o.bool_value('checkGlobalVariables')!
}

// un_is_string_literal_of ports isLiteral(node, value) of unicorn's ast/literal.js for a string.
fn un_is_string_literal_of(t &estree.EsTree, node int, value string) bool {
	if t.typ(node) != .literal {
		return false
	}
	v := t.get(node, .value)
	return v is string && v == value
}

fn (mut c Checker) lint_unicorn_no_typeof_undefined(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	check_globals := unty_options(c.rule_options(unicorn_no_typeof_undefined))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .binary_expression {
			continue
		}
		stats.checked++
		operator := t.string_of(node, .operator) or { continue }
		typeof_node := t.node(node, .left) or { continue }
		undefined_string := t.node(node, .right) or { continue }
		if operator !in ['===', '!==', '==', '!='] || t.typ(typeof_node) != .unary_expression
			|| (t.string_of(typeof_node, .operator) or { '' }) != 'typeof'
			|| !(t.flag(typeof_node, .prefix) or { false })
			|| !un_is_string_literal_of(t, undefined_string, 'undefined') {
			continue
		}
		value := t.node(typeof_node, .argument) or { continue }
		is_global := t.typ(value) == .identifier && c.un_is_global_or_unresolved(root, t, value)
		if !check_globals && is_global {
			continue
		}
		typeof_token := un_first_token(t, tokens, typeof_node, 0) or { continue }
		second := un_first_token(t, tokens, typeof_node, 1) or { continue }
		has_fix, fix := c.merge_fixes(c.unty_fix(t, tokens, node, typeof_node, undefined_string,
			operator, typeof_token, second))!
		mut finding := Finding{
			stmt:       c.position_range(typeof_token.start, typeof_token.end)
			message_id: 'no-typeof-undefined/error'
		}
		if is_global {
			finding = Finding{
				...finding
				suggestions: [
					Suggestion{
						message_id: 'no-typeof-undefined/suggestion'
						data:       {
							'operator': if operator.starts_with('!') { '!==' } else { '===' }
						}
						fix:        fix
					},
				]
			}
		} else {
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

// un_is_global_or_unresolved: sourceCode.isGlobalReference(identifier) or isUnresolvedVariable
// (findVariable finds no variable of that name from its scope).
fn (mut c Checker) un_is_global_or_unresolved(root C.TSNode, t &estree.EsTree, identifier int) bool {
	ts := t.ts_node(identifier) or { return false }
	if c.es_is_global_reference(root, ts) {
		return true
	}
	tree := c.scope_tree(root)
	name := t.string_of(identifier, .name) or { return false }
	return tree.find_variable(tree.get_scope(ts), name, t.nodes[identifier].start) < 0
}

fn (c &Checker) unty_fix(t &estree.EsTree, tokens &SourceTokens, node int, typeof_node int, undefined_string int, operator string, typeof_token SourceToken, second SourceToken) []Fix {
	mut fixes := []Fix{}
	// `==` and `!=` become `===` and `!==`.
	if operator in ['==', '!='] {
		operator_token := c.un_token_after_punctuator(tokens, t.nodes[typeof_node].end, operator) or {
			return []
		}
		fixes << fix_insert_at(operator_token.end, '=')
	}
	fixes << fix_replace_range(t.nodes[undefined_string].start, t.nodes[undefined_string].end,
		'undefined')
	fixes << fix_remove_range(typeof_token.start, typeof_token.end)
	fixes << c.un_remove_spaces_after(typeof_token.end)
	parent := t.nodes[node].parent
	if t.typ(parent) in [.return_statement, .throw_statement]
		&& t.node(parent, .argument) or { -1 } == node
		&& !un_same_line(t, typeof_token.start, second.start)
		&& !c.un_is_parenthesized(t, tokens, node) && !c.un_is_parenthesized(t, tokens, typeof_node) {
		fixes << c.un_add_parens_to_return_or_throw(t, tokens, parent)
		return fixes
	}
	before := tokens.before(t.nodes[node].start, false)
	if c.un_needs_semicolon(t, tokens, before, c.token_text(second)) {
		fixes << fix_insert_at(t.nodes[node].start, ';')
	}
	return fixes
}
