module rules

import time
import treesitter { named_children, node_field, node_kind, position_of }

// Port of the `prefer-as-const` rule of typescript-eslint 8.62.0 (it has no options), with its fix
// and its suggestion.

const pac_messages = {
	'preferConstAssertion':   'Expected a `const` instead of a literal type assertion.'
	'variableConstAssertion': 'Expected a `const` assertion instead of a literal type annotation.'
	'variableSuggest':        'You should use `as const` instead of type annotation.'
}

fn (mut c Checker) lint_prefer_as_const(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	for node in c.nodes_of_kinds(root, ['as_expression', 'type_assertion', 'variable_declarator',
		'public_field_definition'], []) {
		parts := named_children(node).filter(node_kind(it) != 'comment')
		match node_kind(node) {
			'as_expression' {
				// TSAsExpression: `x as T` (not `x as const`, whose `const` is a token).
				if parts.len < 2 {
					continue
				}
				checked++
				c.pac_compare(parts[0], parts[parts.len - 1], true, node, mut findings)!
			}
			'type_assertion' {
				// TSTypeAssertion: `<T>x`.
				if parts.len < 2 {
					continue
				}
				types := named_children(parts[0]).filter(node_kind(it) != 'comment')
				if types.len != 1 {
					continue
				}
				checked++
				c.pac_compare(parts[1], types[0], true, node, mut findings)!
			}
			else {
				// A VariableDeclarator or a PropertyDefinition (not an AccessorProperty) with a type
				// annotation and a value.
				if node_kind(node) == 'public_field_definition'
					&& children_of_kind(node, 'accessor').len > 0 {
					continue
				}
				value := node_field(node, 'value') or { continue }
				annotation := node_field(node, 'type') or { continue }
				annotated := named_children(annotation).filter(node_kind(it) != 'comment')
				if annotated.len != 1 {
					continue
				}
				checked++
				c.pac_compare(value, annotated[0], false, annotation, mut findings)!
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// pac_compare ports compareTypes: the value is a Literal and the type a TSLiteralType of a Literal
// (not `-1`, nor `null`, a TSNullKeyword) with the same raw text. An assertion is fixed to
// `const`; an annotation (`annotation` is its TSTypeAnnotation) gets a suggestion that removes it
// and adds ` as const` after the value.
fn (mut c Checker) pac_compare(value_node C.TSNode, type_node C.TSNode, can_fix bool, annotation C.TSNode, mut findings []Finding) ! {
	value := unwrap_parens(value_node)
	type_literal := unwrap_type_parens(type_node)
	if node_kind(value) !in ['string', 'number', 'true', 'false', 'null', 'regex']
		|| node_kind(type_literal) != 'literal_type' {
		return
	}
	literal := first_named(type_literal) or { return }
	if node_kind(literal) !in ['string', 'number', 'true', 'false']
		|| c.text(value) != c.text(literal) {
		return
	}
	if can_fix {
		findings << Finding{
			stmt:       position_of(type_literal)
			message_id: 'preferConstAssertion'
			has_fix:    true
			fix:        fix_replace(type_literal, 'const')
		}
		return
	}
	_, suggestion := c.suggestion('variableSuggest', map[string]string{}, [
		fix_remove(annotation),
		fix_insert_after(value, ' as const'),
	])!
	findings << Finding{
		stmt:        position_of(type_literal)
		message_id:  'variableConstAssertion'
		suggestions: [suggestion]
	}
}
