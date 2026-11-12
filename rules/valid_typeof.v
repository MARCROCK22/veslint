module rules

import json2
import time
import treesitter { children, node_field, node_kind, position_of }

// Port of the `valid-typeof` rule of ESLint 10.6.0, with its option and its suggestion.

const vt_messages = {
	'invalidValue':  'Invalid typeof comparison value.'
	'notString':     'Typeof comparisons should be to string literals.'
	'suggestString': 'Use `"{{type}}"` instead of `{{type}}`.'
}

const vt_valid_types = ['symbol', 'undefined', 'object', 'boolean', 'number', 'string', 'function',
	'bigint']

// vt_options reads requireStringLiterals.
fn vt_options(options []json2.Any) !bool {
	o := option_object(valid_typeof, options, ['requireStringLiterals'])!
	return o.bool_value('requireStringLiterals')!
}

fn (mut c Checker) lint_valid_typeof(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	require_strings := vt_options(c.rule_options(valid_typeof))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['unary_expression'], []) {
		if !c.vt_is_typeof(node) {
			continue
		}
		// The parent of the UnaryExpression: a BinaryExpression of equality (parentheses are not
		// ESTree nodes).
		parent := cti_estree_parent(node) or { continue }
		if node_kind(parent) != 'binary_expression'
			|| c.text(node_field(parent, 'operator') or { continue }) !in ['==', '===', '!=', '!=='] {
			continue
		}
		stats.checked++
		left := node_field(parent, 'left') or { continue }
		right := node_field(parent, 'right') or { continue }
		sibling := unwrap_parens(if node_key(unwrap_parens(left)) == node_key(node) {
			right
		} else {
			left
		})
		if value := c.vt_literal_value(sibling) {
			if value !in vt_valid_types {
				findings << Finding{
					stmt:       position_of(sibling)
					message_id: 'invalidValue'
				}
			}
		} else if c.vt_is_literal(sibling) {
			// A Literal whose value is not a string (a number, a boolean, null, a RegExp).
			findings << Finding{
				stmt:       position_of(sibling)
				message_id: 'invalidValue'
			}
		} else if c.es_is_specific_id(sibling, 'undefined')
			&& c.es_is_global_reference(root, sibling) {
			_, suggestion := c.suggestion('suggestString', {
				'type': 'undefined'
			}, [fix_replace(sibling, '"undefined"')])!
			findings << Finding{
				stmt:        position_of(sibling)
				message_id:  if require_strings { 'notString' } else { 'invalidValue' }
				suggestions: [suggestion]
			}
		} else if require_strings && !c.vt_is_typeof(sibling) {
			findings << Finding{
				stmt:       position_of(sibling)
				message_id: 'notString'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vt_is_typeof ports isTypeofExpression: a UnaryExpression `typeof`.
fn (c &Checker) vt_is_typeof(n C.TSNode) bool {
	if node_kind(n) != 'unary_expression' {
		return false
	}
	operator := node_field(n, 'operator') or { return false }
	return c.text(operator) == 'typeof'
}

// vt_is_literal is whether a node is an ESTree Literal or a template literal without
// substitutions (isStaticTemplateLiteral).
fn (c &Checker) vt_is_literal(n C.TSNode) bool {
	return match node_kind(n) {
		'string', 'number', 'true', 'false', 'null', 'regex' {
			true
		}
		'template_string' {
			!children(n).any(node_kind(it) == 'template_substitution')
		}
		else {
			false
		}
	}
}

// vt_literal_value is the value of a string Literal or of a template literal without
// substitutions (its cooked text); none for any other node.
fn (c &Checker) vt_literal_value(n C.TSNode) ?string {
	if node_kind(n) !in ['string', 'template_string'] {
		return none
	}
	return c.literal_name(n)
}
