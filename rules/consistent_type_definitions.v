module rules

import json2
import time
import treesitter { has_child_kind, named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `consistent-type-definitions` rule of typescript-eslint 8.62.0, with its option
// ('interface' or 'type') and its fixes.

const ctd_messages = {
	'interfaceOverType': 'Use an `interface` instead of a `type`.'
	'typeOverInterface': 'Use a `type` instead of an `interface`.'
}

fn ctd_option(options []json2.Any) !string {
	option := if options.len > 0 { options[0] } else { json2.Any('interface') }
	if option is string && option in ['interface', 'type'] {
		return option
	}
	return error('the option of `${consistent_type_definitions}` must be "interface" or "type"')
}

fn (mut c Checker) lint_consistent_type_definitions(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	option := ctd_option(c.rule_options(consistent_type_definitions))!
	mut findings := []Finding{}
	mut checked := 0
	if option == 'interface' {
		// `TSTypeAliasDeclaration[typeAnnotation.type='TSTypeLiteral']`, reported at its id.
		for node in c.nodes_of_kind(root, c'type_alias_declaration') {
			name := node_field(node, 'name') or { continue }
			value := node_field(node, 'value') or { continue }
			literal := unwrap_type_parens(value)
			if node_kind(literal) != 'object_type' {
				continue
			}
			// `{ [K in T]: U }` is a TSMappedType.
			if _ := scope_mapped_clause(literal) {
				continue
			}
			checked++
			findings << c.with_fixes(Finding{
				stmt:       position_of(name)
				message_id: 'interfaceOverType'
			}, c.ctd_interface_fixes(node, name, literal))!
		}
	} else {
		// TSInterfaceDeclaration, reported at its id; not fixed in `declare global {}`.
		for node in c.nodes_of_kind(root, c'interface_declaration') {
			name := node_field(node, 'name') or { continue }
			checked++
			fixes := if ctd_in_declared_global(node) {
				[]Fix{}
			} else {
				c.ctd_type_fixes(node, name)
			}
			findings << c.with_fixes(Finding{
				stmt:       position_of(name)
				message_id: 'typeOverInterface'
			}, fixes)!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// ctd_interface_fixes: the `type` before the name becomes `interface`, what is between the token
// before the `=` and the type literal becomes a space, and what follows the literal up to the end
// of the declaration goes.
fn (mut c Checker) ctd_interface_fixes(node C.TSNode, name C.TSNode, literal C.TSNode) []Fix {
	tokens := c.source_tokens(node)
	type_token := c.ctd_token_before(tokens, node_start(name), 'type') or { return []Fix{} }
	equals := c.ctd_token_before(tokens, node_start(literal), '=') or { return []Fix{} }
	before_equals := tokens.before(equals.start, true) or { return []Fix{} }
	return [
		fix_replace_range(type_token.start, type_token.end, 'interface'),
		fix_replace_range(before_equals.end, node_start(literal), ' '),
		fix_remove_range(node_end(literal), c.tokens.last_end(node_end(node))),
	]
}

// ctd_type_fixes: the token before the name becomes `type`, what is between the name (or its type
// parameters) and the body becomes ` = `, each heritage follows the body as ` & X`, and the
// `export default` of the interface goes after it.
fn (mut c Checker) ctd_type_fixes(node C.TSNode, name C.TSNode) []Fix {
	body := node_field(node, 'body') or { return []Fix{} }
	type_node := node_field(node, 'type_parameters') or { name }
	mut fixes := []Fix{}
	if first := c.token_before(name) {
		fixes << fix_replace_range(first.start, first.end, 'type')
		fixes << fix_replace_range(node_end(type_node), node_start(body), ' = ')
	}
	for clause in named_children(node) {
		if node_kind(clause) != 'extends_type_clause' {
			continue
		}
		for heritage in named_children(clause) {
			fixes << fix_insert_after(body, ' & ${c.text(heritage)}')
		}
	}
	if parent := node_parent(node) {
		if node_kind(parent) == 'export_statement' && has_child_kind(parent, 'default') {
			fixes << fix_remove_range(node_start(parent), node_start(node))
			fixes << fix_insert_after(body, '\nexport default ${c.identifier_name(name)}')
		}
	}
	return fixes
}

// ctd_token_before ports getTokenBefore(node, token => token.value === text): the last token
// before `offset` with that text.
fn (c &Checker) ctd_token_before(tokens &SourceTokens, offset int, text string) ?SourceToken {
	for i := source_tokens_index(tokens.tokens, offset) - 1; i >= 0; i-- {
		if c.token_text(tokens.tokens[i]) == text {
			return tokens.tokens[i]
		}
	}
	return none
}

// ctd_in_declared_global: an ancestor is `declare global {}` (a TSModuleDeclaration with
// `declare` and the kind 'global'); a `global {}` inside a module has no `declare`.
fn ctd_in_declared_global(n C.TSNode) bool {
	mut node := n
	for {
		node = node_parent(node) or { return false }
		if node_kind(node) == 'ambient_declaration' && has_child_kind(node, 'global')
			&& has_child_kind(node, 'declare') {
			return true
		}
	}
	return false
}
