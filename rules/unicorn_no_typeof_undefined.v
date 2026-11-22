module rules

import estree
import json2
import time

// Port of the `unicorn/no-typeof-undefined` rule of eslint-plugin-unicorn 79.0.0, with its fix and
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

fn (mut c Checker) lint_unicorn_no_typeof_undefined(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
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
			|| (unb_static_string_value(t, undefined_string) or { '' }) != 'undefined' {
			continue
		}
		value := unb_unwrap_ts(t, t.node(typeof_node, .argument) or { continue })
		mut is_global := false
		if t.typ(value) == .identifier {
			resolved := c.unty_resolved(root, t, value)
			if c.unty_is_ambient_variable(root, t, resolved) {
				continue
			}
			ts := t.ts_node(value) or { continue }
			is_global = c.es_is_global_reference(root, ts) || resolved < 0
		}
		if !check_globals && is_global {
			continue
		}
		typeof_token := un_first_token(t, tokens, typeof_node, 0) or { continue }
		second := un_first_token(t, tokens, typeof_node, 1) or { continue }
		keyword_parent := c.unb_unparenthesized_keyword_argument_parent(t, tokens, typeof_node)
		argument := t.node(typeof_node, .argument) or { continue }
		needs_parens := !c.un_is_parenthesized(t, tokens, argument)
			&& c.unb_should_add_parens_to_expression_start(t, tokens, argument, typeof_node)
		has_fix, fix := c.merge_fixes(c.unty_fix(t, tokens, node, typeof_node, undefined_string,
			operator, typeof_token, second, keyword_parent, needs_parens))!
		mut finding := Finding{
			stmt:       c.position_range(typeof_token.start, typeof_token.end)
			message_id: 'no-typeof-undefined/error'
		}
		if keyword_parent >= 0 && t.typ(keyword_parent) == .yield_expression
			&& !un_same_line(t, typeof_token.start, second.start) {
			// Removing `typeof` would leave a bare `yield`.
		} else if is_global {
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

// unty_resolved ports getIdentifierReference(identifier, scope)?.resolved: the variable the
// reference of the identifier resolves to, -1 for none.
fn (mut c Checker) unty_resolved(root C.vt_node, t &estree.EsTree, identifier int) int {
	ts := t.ts_node(identifier) or { return -1 }
	tree := c.scope_tree(root)
	key := node_key(ts)
	mut scope := tree.get_scope(ts)
	for scope >= 0 {
		for r in tree.scopes[scope].references {
			if node_key(tree.references[r].identifier) == key {
				return tree.references[r].resolved
			}
		}
		scope = tree.scopes[scope].upper
	}
	return -1
}

// unty_is_ambient_definition ports isAmbientVariableDefinition: a variable of a `declare`
// declaration.
fn (mut c Checker) unty_is_ambient_definition(t &estree.EsTree, def ScopeDefinition) bool {
	if def.kind != .variable {
		return false
	}
	declarator := c.es_index_of(t, def.node) or { return false }
	declaration := t.nodes[declarator].parent
	return declaration >= 0 && t.typ(declaration) == .variable_declaration
		&& (t.flag(declaration, .declare_) or { false })
}

// unty_is_ambient_variable ports isAmbientVariable: some definition is ambient and the others are
// types.
fn (mut c Checker) unty_is_ambient_variable(root C.vt_node, t &estree.EsTree, v int) bool {
	if v < 0 {
		return false
	}
	tree := c.scope_tree(root)
	defs := tree.variables[v].defs
	return defs.any(c.unty_is_ambient_definition(t, it))
		&& defs.all(it.kind == .type_definition || c.unty_is_ambient_definition(t, it))
}

fn (c &Checker) unty_fix(t &estree.EsTree, tokens &SourceTokens, node int, typeof_node int, undefined_string int, operator string, typeof_token SourceToken, second SourceToken, keyword_parent int, needs_parens bool) []Fix {
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
	if needs_parens {
		argument := t.node(typeof_node, .argument) or { return [] }
		fixes << fix_insert_at(t.nodes[argument].start, '(')
		fixes << fix_insert_at(t.nodes[argument].end, ')')
	}
	if keyword_parent >= 0 && t.typ(keyword_parent) in [.return_statement, .throw_statement]
		&& !un_same_line(t, typeof_token.start, second.start) {
		fixes << c.un_add_parens_to_return_or_throw(t, tokens, keyword_parent)
		return fixes
	}
	before := tokens.before(t.nodes[node].start, false)
	if c.unb_needs_semicolon(t, tokens, before, if needs_parens { '(' } else { c.token_text(second) }) {
		fixes << fix_insert_at(t.nodes[node].start, ';')
	}
	return fixes
}
