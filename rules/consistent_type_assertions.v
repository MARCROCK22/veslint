module rules

import json2
import time
import treesitter { has_child_kind, named_children, node_field, node_kind, node_parent, position_of }

// Port of the `consistent-type-assertions` rule of typescript-eslint 8.62.0, with its options
// `assertionStyle` ('as', 'angle-bracket' or 'never'), `objectLiteralTypeAssertions` and
// `arrayLiteralTypeAssertions` ('allow', 'allow-as-parameter' or 'never'), its fix and its
// suggestions.

const cta_messages = {
	'angle-bracket':                            "Use '<{{cast}}>' instead of 'as {{cast}}'."
	'as':                                       "Use 'as {{cast}}' instead of '<{{cast}}>'."
	'never':                                    'Do not use any type assertions.'
	'replaceArrayTypeAssertionWithAnnotation':  'Use const x: {{cast}} = [ ... ] instead.'
	'replaceArrayTypeAssertionWithSatisfies':   'Use const x = [ ... ] satisfies {{cast}} instead.'
	'replaceObjectTypeAssertionWithAnnotation': 'Use const x: {{cast}} = { ... } instead.'
	'replaceObjectTypeAssertionWithSatisfies':  'Use const x = { ... } satisfies {{cast}} instead.'
	'unexpectedArrayTypeAssertion':             'Always prefer const x: T[] = [ ... ].'
	'unexpectedObjectTypeAssertion':            'Always prefer const x: T = { ... }.'
}

struct CtaOptions {
	assertion_style string
	object_literal  string
	array_literal   string
}

fn cta_options(options []json2.Any) !CtaOptions {
	o := option_object(consistent_type_assertions, options, [
		'arrayLiteralTypeAssertions',
		'assertionStyle',
		'objectLiteralTypeAssertions',
	])!
	literal := ['allow', 'allow-as-parameter', 'never']
	return CtaOptions{
		assertion_style: o.string_value('assertionStyle', ['as', 'angle-bracket', 'never'])!
		object_literal:  o.string_value('objectLiteralTypeAssertions', literal)!
		array_literal:   o.string_value('arrayLiteralTypeAssertions', literal)!
	}
}

// CtaAssertion is a TSAsExpression or a TSTypeAssertion: its expression (as tree-sitter has it,
// maybe in parentheses), its type without parentheses and the text of that type, `const` for a
// const assertion, whose `const` is an anonymous token in tree-sitter.
struct CtaAssertion {
	node       C.TSNode
	expression C.TSNode
	type_node  C.TSNode
	is_const   bool
	type_text  string
}

fn (mut c Checker) lint_consistent_type_assertions(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := cta_options(c.rule_options(consistent_type_assertions))!
	mut findings := []Finding{}
	mut checked := 0
	for node in c.nodes_of_kinds(root, ['as_expression', 'type_assertion'], []) {
		a := c.cta_assertion(node) or { continue }
		checked++
		is_as := node_kind(node) == 'as_expression'
		if (is_as && o.assertion_style != 'as') || (!is_as && o.assertion_style != 'angle-bracket') {
			c.cta_report_incorrect(a, o.assertion_style, mut findings)
			continue
		}
		c.cta_check_literal(a, o, mut findings)!
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

fn (c &Checker) cta_assertion(node C.TSNode) ?CtaAssertion {
	parts := named_children(node)
	if node_kind(node) == 'as_expression' {
		if parts.len == 0 {
			return none
		}
		if parts.len < 2 || has_child_kind(node, 'const') {
			return CtaAssertion{
				node:       node
				expression: parts[0]
				type_node:  node
				is_const:   true
				type_text:  'const'
			}
		}
		type_node := unwrap_type_parens(parts[parts.len - 1])
		return CtaAssertion{
			node:       node
			expression: parts[0]
			type_node:  type_node
			type_text:  c.text(type_node)
		}
	}
	if parts.len < 2 || node_kind(parts[0]) != 'type_arguments' {
		return none
	}
	if has_child_kind(parts[0], 'const') {
		return CtaAssertion{
			node:       node
			expression: parts[1]
			type_node:  node
			is_const:   true
			type_text:  'const'
		}
	}
	type_node := unwrap_type_parens(first_named(parts[0])?)
	return CtaAssertion{
		node:       node
		expression: parts[1]
		type_node:  type_node
		type_text:  c.text(type_node)
	}
}

// cta_report_incorrect ports reportIncorrectAssertionType: the assertion is not of the style of
// the options (a const assertion is fine for 'never'); `<T>x` gets a fix to `x as T`.
fn (mut c Checker) cta_report_incorrect(a CtaAssertion, style string, mut findings []Finding) {
	if a.is_const && style == 'never' {
		return
	}
	data := if style != 'never' {
		{
			'cast': a.type_text
		}
	} else {
		map[string]string{}
	}
	if style != 'as' {
		findings << Finding{
			stmt:       position_of(a.node)
			message_id: style
			data:       data
		}
		return
	}
	findings << Finding{
		stmt:       position_of(a.node)
		message_id: style
		data:       data
		has_fix:    true
		fix:        c.cta_as_fix(a)
	}
}

// cta_as_fix: `<T>x` becomes `x as T`, the expression in parentheses unless it binds tighter
// than `as` (getOperatorPrecedenceForNode), and the whole in parentheses unless it already has
// them or the TypeScript parent binds less tightly (getOperatorPrecedence).
fn (mut c Checker) cta_as_fix(a CtaAssertion) Fix {
	expression := unwrap_parens(a.expression)
	code := c.text(expression)
	wrapped := if estree_operator_precedence(expression) > precedence_relational {
		code
	} else {
		'(${code})'
	}
	text := '${wrapped} as ${a.type_text}'
	if c.is_parenthesized(EsNode{
		node: a.node
	}) || precedence_relational > cta_parent_precedence(a.node) {
		return fix_replace(a.node, text)
	}
	return fix_replace(a.node, '(${text})')
}

// cta_parent_precedence ports getOperatorPrecedence for the TypeScript parent of an assertion:
// tree-sitter's parent, but for the `arguments` of a call or a `new` (TypeScript has none), the
// parentheses of a statement (part of its syntax) and a spread in an object or in JSX (a
// SpreadAssignment or a JsxSpreadAttribute).
fn cta_parent_precedence(n C.TSNode) int {
	parent := node_parent(n) or { return precedence_invalid }
	match node_kind(parent) {
		'arguments' {
			holder := node_parent(parent) or { return precedence_invalid }
			return match node_kind(holder) {
				'call_expression' { precedence_left_hand_side }
				'new_expression' { precedence_member }
				else { precedence_invalid }
			}
		}
		'parenthesized_expression' {
			holder := node_parent(parent) or { return precedence_primary }
			field := match node_kind(holder) {
				'if_statement', 'while_statement', 'do_statement' { 'condition' }
				'switch_statement' { 'value' }
				'with_statement' { 'object' }
				else { '' }
			}
			if field != '' {
				if syntax := node_field(holder, field) {
					if node_key(syntax) == node_key(parent) {
						return precedence_invalid
					}
				}
			}
			return precedence_primary
		}
		'spread_element' {
			holder := node_parent(parent) or { return precedence_spread }
			if node_kind(holder) in ['object', 'jsx_expression'] {
				return precedence_invalid
			}
			return precedence_spread
		}
		'new_expression' {
			mut has_arguments := false
			if arguments := node_field(parent, 'arguments') {
				has_arguments = named_children(arguments).len > 0
			}
			return ts_operator_precedence(parent, '', has_arguments)
		}
		else {
			return ts_operator_precedence(parent, ts_binary_operator(parent), false)
		}
	}
}

// cta_check_literal ports checkExpressionForObjectAssertion and
// checkExpressionForArrayAssertion: an object or array literal asserted to a type other than
// any, unknown or const, unless the options allow it there.
fn (mut c Checker) cta_check_literal(a CtaAssertion, o CtaOptions, mut findings []Finding) ! {
	if o.assertion_style == 'never' {
		return
	}
	expression := unwrap_parens(a.expression)
	is_object := node_kind(expression) == 'object'
	if !is_object && node_kind(expression) != 'array' {
		return
	}
	option := if is_object { o.object_literal } else { o.array_literal }
	if option == 'allow' || (option == 'allow-as-parameter' && cta_is_as_parameter(a.node)) {
		return
	}
	if a.is_const || (node_kind(a.type_node) == 'predefined_type'
		&& c.text(a.type_node) in ['any', 'unknown']) {
		return
	}
	kind := if is_object { 'Object' } else { 'Array' }
	findings << Finding{
		stmt:        position_of(a.node)
		message_id:  'unexpected${kind}TypeAssertion'
		suggestions: c.cta_suggestions(a, 'replace${kind}TypeAssertionWithAnnotation',
			'replace${kind}TypeAssertionWithSatisfies')!
	}
}

// cta_suggestions ports getSuggestions: an annotation on the variable the assertion initializes
// (when it has none), and `satisfies`; both leave the expression with its parentheses.
fn (mut c Checker) cta_suggestions(a CtaAssertion, annotation_id string, satisfies_id string) ![]Suggestion {
	data := {
		'cast': a.type_text
	}
	text := c.text_with_parentheses(es_child(a.expression))
	mut out := []Suggestion{}
	if declarator := cta_declarator(a.node) {
		if id := node_field(declarator, 'name') {
			_, s := c.suggestion(annotation_id, data, [
				fix_insert_after(id, ': ${a.type_text}'),
				fix_replace(a.node, text),
			])!
			out << s
		}
	}
	_, s := c.suggestion(satisfies_id, data, [fix_replace(a.node, text),
		fix_insert_after(a.node, ' satisfies ${a.type_text}')])!
	out << s
	return out
}

// cta_estree_parent is the ESTree parent of an assertion, without the parentheses around it, and
// the node of the assertion as a child of that parent.
fn cta_estree_parent(n C.TSNode) ?(C.TSNode, C.TSNode) {
	mut child := n
	mut parent := node_parent(n)?
	for node_kind(parent) == 'parenthesized_expression' {
		child = parent
		parent = node_parent(parent)?
	}
	return parent, child
}

// cta_declarator is the VariableDeclarator the assertion initializes, if its id has no type
// annotation.
fn cta_declarator(n C.TSNode) ?C.TSNode {
	parent, child := cta_estree_parent(n)?
	if node_kind(parent) != 'variable_declarator' {
		return none
	}
	if _ := node_field(parent, 'type') {
		return none
	}
	value := node_field(parent, 'value')?
	if node_key(value) != node_key(child) {
		return none
	}
	return parent
}

// cta_is_as_parameter ports isAsParameter: the parent is a NewExpression, a CallExpression, a
// ThrowStatement, an AssignmentPattern, a JSXExpressionContainer, or the TemplateLiteral of a
// tagged template.
fn cta_is_as_parameter(n C.TSNode) bool {
	parent, child := cta_estree_parent(n) or { return false }
	match node_kind(parent) {
		'arguments' {
			holder := node_parent(parent) or { return false }
			return node_kind(holder) == 'new_expression'
				|| (node_kind(holder) == 'call_expression' && !precedence_is_import_call(holder))
		}
		'new_expression', 'throw_statement', 'jsx_expression' {
			return true
		}
		'call_expression' {
			// The callee of a call, not the tag of a template.
			arguments := node_field(parent, 'arguments') or { return false }
			return node_kind(arguments) == 'arguments'
		}
		'required_parameter', 'optional_parameter' {
			value := node_field(parent, 'value') or { return false }
			return node_key(value) == node_key(child)
		}
		'assignment_pattern', 'object_assignment_pattern' {
			value := node_field(parent, 'right') or { return false }
			return node_key(value) == node_key(child)
		}
		'template_substitution' {
			template := node_parent(parent) or { return false }
			holder := node_parent(template) or { return false }
			return node_kind(holder) == 'call_expression' && precedence_is_tagged_template(holder)
		}
		else {
			return false
		}
	}
}
