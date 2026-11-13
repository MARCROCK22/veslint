module rules

import json2
import time
import treesitter { node_field, node_kind, node_start, position_of }

// Port of the `no-implicit-coercion` rule of ESLint 10.6.0, with its options, its fix and its
// suggestions.

const nic_messages = {
	'implicitCoercion':  'Unexpected implicit coercion encountered. Use `{{recommendation}}` instead.'
	'useRecommendation': 'Use `{{recommendation}}` instead.'
}

struct NicOptions {
	allow                       []string
	boolean                     bool
	number                      bool
	string_                     bool
	disallow_template_shorthand bool
}

// nic_options reads boolean, number, string, disallowTemplateShorthand and allow.
fn nic_options(options []json2.Any) !NicOptions {
	o := option_object(no_implicit_coercion, options, ['boolean', 'number', 'string',
		'disallowTemplateShorthand', 'allow'])!
	allow := o.values['allow'] or { json2.Any([]json2.Any{}) }
	return NicOptions{
		allow:                       allow.as_array().map(it.str())
		boolean:                     o.bool_value('boolean')!
		number:                      o.bool_value('number')!
		string_:                     o.bool_value('string')!
		disallow_template_shorthand: o.bool_value('disallowTemplateShorthand')!
	}
}

fn (mut c Checker) lint_no_implicit_coercion(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nic_options(c.rule_options(no_implicit_coercion))!
	mut findings := []Finding{}
	kinds := ['unary_expression', 'binary_expression', 'augmented_assignment_expression',
		'template_string']
	for node in c.nodes_of_kinds(root, kinds, []) {
		stats.checked++
		match node_kind(node) {
			'unary_expression' {
				c.nic_unary(root, o, node, mut findings)!
			}
			'binary_expression' {
				c.nic_binary(root, o, node, mut findings)!
			}
			'augmented_assignment_expression' {
				right := unwrap_parens(node_field(node, 'right') or { continue })
				if '+' !in o.allow && o.string_ && operator_of(node) == '+='
					&& c.nic_is_empty_string(right) {
					left := unwrap_parens(node_field(node, 'left') or { continue })
					code := c.es_text(left)
					first := c.source_tokens(root).after(node_start(left), false) or { continue }
					c.nic_report(root, node, '${code} = String(${code})', first.kind, first_text(c,
						first), true, false, mut findings)!
				}
			}
			else {
				c.nic_template(root, o, node, mut findings)!
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn first_text(c &Checker, t SourceToken) string {
	return c.src[t.start..t.end]
}

// nic_report reports the node with the recommendation as a fix (shouldFix) or a suggestion
// (shouldSuggest), with a space when the token before would join its first token.
fn (mut c Checker) nic_report(root C.TSNode, node C.TSNode, recommendation string, first_kind SourceTokenKind, first string, should_suggest bool, should_fix bool, mut findings []Finding) ! {
	tokens := c.source_tokens(root)
	start := node_start(node)
	end := c.es_end(node)
	mut text := recommendation
	if before := tokens.before(start, false) {
		if before.end == start && !es_can_adjacent(before.kind, c.src[before.start..before.end],
			first_kind, first) {
			text = ' ${recommendation}'
		}
	}
	fix := fix_replace_range(start, end, text)
	data := {
		'recommendation': recommendation
	}
	mut suggestions := []Suggestion{}
	if !should_fix && should_suggest {
		_, suggestion := c.suggestion('useRecommendation', data, [fix])!
		suggestions << suggestion
	}
	findings << Finding{
		stmt:        position_of(node)
		message_id:  'implicitCoercion'
		data:        data
		has_fix:     should_fix
		fix:         if should_fix { fix } else { Fix{} }
		suggestions: suggestions
	}
}

// nic_is_numeric ports isNumeric: a number literal, or a call of Number, parseInt or parseFloat.
fn (c &Checker) nic_is_numeric(n C.TSNode) bool {
	node := unwrap_parens(n)
	if node_kind(node) == 'number' {
		return !c.text(node).ends_with('n')
	}
	if node_kind(node) == 'call_expression' && estree_type(node) == 'CallExpression' {
		callee := unwrap_parens(node_field(node, 'function') or { return false })
		return node_kind(callee) == 'identifier' && c.text(callee) in ['Number', 'parseInt',
			'parseFloat']
	}
	return false
}

// nic_is_string_type ports isStringType: a string literal, a template, or a call of String.
fn (c &Checker) nic_is_string_type(n C.TSNode) bool {
	node := unwrap_parens(n)
	if node_kind(node) in ['string', 'template_string'] {
		return true
	}
	if callee, _ := c.es_call_identifier(node) {
		return c.text(callee) == 'String'
	}
	return false
}

// nic_is_empty_string ports isEmptyString: '' or a template that is ``.
fn (c &Checker) nic_is_empty_string(n C.TSNode) bool {
	node := unwrap_parens(n)
	return match node_kind(node) {
		'string' { (c.literal_name(node) or { 'x' }) == '' }
		'template_string' { (c.literal_name(node) or { 'x' }) == '' }
		else { false }
	}
}

// nic_is_number_one: the Literal 1.
fn (c &Checker) nic_is_number_value(n C.TSNode, value f64) bool {
	node := unwrap_parens(n)
	if node_kind(node) != 'number' || c.text(node).ends_with('n') {
		return false
	}
	v := number_literal_value(c.text(node)) or { return false }
	return v == value
}

fn (mut c Checker) nic_unary(root C.TSNode, o NicOptions, node C.TSNode, mut findings []Finding) ! {
	operator := operator_of(node)
	argument := unwrap_parens(node_field(node, 'argument') or { return })
	// `!!x`.
	if '!!' !in o.allow && o.boolean && operator == '!' && node_kind(argument) == 'unary_expression'
		&& operator_of(argument) == '!' {
		inner := unwrap_parens(node_field(argument, 'argument') or { return })
		recommendation := 'Boolean(${c.es_text(inner)})'
		tree := c.scope_tree(root)
		v := tree.find_variable(tree.get_scope(node), 'Boolean', -1)
		boolean_exists := v >= 0 && tree.variables[v].identifiers.len == 0
		c.nic_report(root, node, recommendation, .identifier, 'Boolean', true, boolean_exists, mut
			findings)!
	}
	// `~x.indexOf(y)`.
	if '~' !in o.allow && o.boolean && operator == '~' && node_kind(argument) == 'call_expression' {
		callee := node_field(argument, 'function') or { return }
		if args := node_field(argument, 'arguments') {
			if node_kind(args) == 'arguments' {
				name := c.es_static_property_name(callee) or { '' }
				if node_kind(unwrap_parens(callee)) in ['member_expression', 'subscript_expression']
					&& name in ['indexOf', 'lastIndexOf'] {
					comparison := if estree_type(argument) == 'ChainExpression' {
						'>= 0'
					} else {
						'!== -1'
					}
					c.nic_report(root, node, '${c.es_text(argument)} ${comparison}', .identifier,
						'', false, false, mut findings)!
				}
			}
		}
	}
	// `+x`.
	if '+' !in o.allow && o.number && operator == '+' && !c.nic_is_numeric(argument) {
		c.nic_report(root, node, 'Number(${c.es_text(argument)})', .identifier, 'Number',
			true, false, mut findings)!
	}
	// `- -x`.
	if '- -' !in o.allow && o.number && operator == '-' && node_kind(argument) == 'unary_expression'
		&& operator_of(argument) == '-' {
		inner := unwrap_parens(node_field(argument, 'argument') or { return })
		if !c.nic_is_numeric(inner) {
			c.nic_report(root, node, 'Number(${c.es_text(inner)})', .identifier, 'Number',
				true, false, mut findings)!
		}
	}
}

fn (mut c Checker) nic_binary(root C.TSNode, o NicOptions, node C.TSNode, mut findings []Finding) ! {
	if estree_binary_kind(node) != 'BinaryExpression' {
		return
	}
	operator := operator_of(node)
	left := unwrap_parens(node_field(node, 'left') or { return })
	right := unwrap_parens(node_field(node, 'right') or { return })
	// `x * 1`, but not `x * 1 / y`.
	if '*' !in o.allow && o.number && operator == '*'
		&& (c.nic_is_number_value(left, 1) || c.nic_is_number_value(right, 1))
		&& !c.nic_is_fraction_of_one(node, right) {
		mut operand := ?C.TSNode(none)
		if estree_binary_kind(right) != 'BinaryExpression' && !c.nic_is_numeric(right) {
			operand = right
		} else if estree_binary_kind(left) != 'BinaryExpression' && !c.nic_is_numeric(left) {
			operand = left
		}
		if x := operand {
			c.nic_report(root, node, 'Number(${c.es_text(x)})', .identifier, 'Number', true,
				false, mut findings)!
		}
	}
	// `x - 0`.
	if '-' !in o.allow && o.number && operator == '-' && c.nic_is_number_value(right, 0)
		&& !c.nic_is_numeric(left) {
		c.nic_report(root, node, 'Number(${c.es_text(left)})', .identifier, 'Number', true,
			false, mut findings)!
	}
	// `'' + x`.
	if '+' !in o.allow && o.string_ && operator == '+'
		&& ((c.nic_is_empty_string(left) && !c.nic_is_string_type(right))
			|| (c.nic_is_empty_string(right) && !c.nic_is_string_type(left))) {
		operand := if c.nic_is_empty_string(left) { right } else { left }
		c.nic_report(root, node, 'String(${c.es_text(operand)})', .identifier, 'String', true,
			false, mut findings)!
	}
}

// nic_is_fraction_of_one ports isMultiplyByFractionOfOne: `x * 1` as the left side of a `/`,
// without parentheses.
fn (mut c Checker) nic_is_fraction_of_one(node C.TSNode, right C.TSNode) bool {
	if !c.nic_is_number_value(right, 1) {
		return false
	}
	parent := cti_estree_parent(node) or { return false }
	if node_kind(parent) != 'binary_expression' || operator_of(parent) != '/' {
		return false
	}
	left := node_field(parent, 'left') or { return false }
	return node_key(unwrap_parens(left)) == node_key(node) && !c.es_is_parenthesised(node)
}

fn (mut c Checker) nic_template(root C.TSNode, o NicOptions, node C.TSNode, mut findings []Finding) ! {
	if !o.disallow_template_shorthand {
		return
	}
	parent := node_parent_or(node)
	if node_kind(parent) == 'call_expression' {
		if args := node_field(parent, 'arguments') {
			if node_key(args) == node_key(node) {
				return
			}
		}
	}
	expressions, _ := c.es_template_parts(node)
	if expressions.len != 1 {
		return
	}
	// Both quasis cook to nothing (a line continuation does).
	_, has_text := c.es_template_parts(node)
	if has_text {
		return
	}
	expression := unwrap_parens(expressions[0])
	if c.nic_is_string_type(expression) {
		return
	}
	c.nic_report(root, node, 'String(${c.es_text(expression)})', .identifier, 'String', true,
		false, mut findings)!
}

fn node_parent_or(n C.TSNode) C.TSNode {
	return treesitter.node_parent(n) or { n }
}
