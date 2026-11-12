module rules

import time
import tsgo { TypeResponse }
import treesitter { has_child_kind, named_children, node_end, node_field, node_kind, node_parent, nodes_of_kinds, position_of }

// Port of the `prefer-return-this-type` rule of typescript-eslint 8.62.0, with its fix (the type
// reference becomes `this`).

const prtt_messages = {
	'useThisType': 'Use `this` type instead.'
}

// SyntaxKind.ClassDeclaration and ClassExpression of TypeScript 7.1.0-beta.
const prtt_syntax_kind_class_declaration = u32(265)
const prtt_syntax_kind_class_expression = u32(233)

// ObjectFlags.Class: the declared type of a class, the only one with a `thisType`.
const prtt_object_flag_class = u32(1)

// Statements forEachReturnStatement walks into (the rest, functions and classes included, are
// skipped): Block, If, Do, While, For, ForIn, ForOf, With, Switch, CaseBlock, CaseClause,
// DefaultClause, Labeled, Try and CatchClause, with the tree-sitter nodes that wrap their parts.
const prtt_return_containers = ['statement_block', 'if_statement', 'else_clause', 'do_statement',
	'while_statement', 'for_statement', 'for_in_statement', 'with_statement', 'switch_statement',
	'switch_body', 'switch_case', 'switch_default', 'labeled_statement', 'try_statement', 'catch_clause',
	'finally_clause']

// PrttReturn is the expression of a `return` of a block body; `this_keyword` is the fast check
// (a bare `this`, whose type is not requested).
struct PrttReturn {
	expression   C.TSNode
	this_keyword bool
}

// PrttCandidate is a function of a class member whose return type names the class.
struct PrttCandidate {
	report     C.TSNode // the type reference with the name of the class
	class_span Span     // the class, for getTypeAtLocation
	block      bool     // the body is a block
	returns    []PrttReturn
	body       C.TSNode // the expression body of an arrow function
}

fn (mut c Checker) lint_prefer_return_this_type(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut candidates := []PrttCandidate{}
	mut spans := []Span{}
	for class in c.nodes_of_kinds(root, ['class_declaration', 'abstract_class_declaration', 'class'],
		[]string{}) {
		name := node_field(class, 'name') or { continue }
		body := node_field(class, 'body') or { continue }
		class_name := c.identifier_name(name)
		class_span := prtt_class_span(class)
		for member in named_children(body) {
			func := prtt_member_function(member) or { continue }
			candidate := c.prtt_check_function(func, class_name, class_span) or { continue }
			spans << class_span
			if candidate.block {
				for r in candidate.returns {
					if !r.this_keyword {
						spans << node_span(r.expression)
					}
				}
			} else {
				spans << node_span(candidate.body)
			}
			candidates << candidate
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for candidate in candidates {
		if c.prtt_returns_this(candidate)! {
			findings << Finding{
				stmt:       position_of(candidate.report)
				message_id: 'useThisType'
				has_fix:    true
				fix:        fix_replace(candidate.report, 'this')
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += candidates.len
	return findings
}

// prtt_class_span requests the type of a class like getTypeAtLocation on its ESTree node: the
// declared type of a ClassDeclaration, the constructor type of a ClassExpression. An exported
// declaration starts at `export` (a modifier in TypeScript) and a decorated one at its decorator.
fn prtt_class_span(class C.TSNode) Span {
	// `export default class {}` is a declaration without a name, which tree-sitter reads as an
	// expression.
	mut is_default_export := false
	if parent := node_parent(class) {
		is_default_export = node_kind(parent) == 'export_statement'
	}
	if node_kind(class) == 'class' && !is_default_export {
		return Span{
			key:   node_key(class)
			first: class
			end:   node_end(class)
			kind:  prtt_syntax_kind_class_expression
		}
	}
	mut first := class
	if parent := node_parent(class) {
		if node_kind(parent) == 'export_statement' {
			first = parent
		}
	}
	return Span{
		key:   node_key(first)
		first: first
		end:   node_end(first)
		kind:  prtt_syntax_kind_class_declaration
	}
}

// prtt_member_function gives the function of a member the rule visits: a MethodDefinition (not
// an abstract one) or the function or arrow function value of a PropertyDefinition or
// AccessorProperty (not an abstract one).
fn prtt_member_function(member C.TSNode) ?C.TSNode {
	match node_kind(member) {
		'method_definition' {
			return member
		}
		'public_field_definition' {
			if has_child_kind(member, 'abstract') {
				return none
			}
			value := unwrap_parens(node_field(member, 'value')?)
			if node_kind(value) in ['function_expression', 'generator_function', 'arrow_function'] {
				return value
			}
			return none
		}
		else {
			return none
		}
	}
}

// prtt_check_function ports checkFunction up to the type checks: the return type must name the
// class, the first parameter must not be `this` and the function must have a body.
fn (c &Checker) prtt_check_function(func C.TSNode, class_name string, class_span Span) ?PrttCandidate {
	annotation := node_field(func, 'return_type')?
	if node_kind(annotation) != 'type_annotation' {
		return none
	}
	report := c.prtt_name_in_type(class_name, first_named(annotation)?)?
	if params := node_field(func, 'parameters') {
		if node_kind(params) == 'formal_parameters' {
			if first := first_named(params) {
				if pattern := node_field(first, 'pattern') {
					if node_kind(pattern) == 'this' {
						return none
					}
				}
			}
		}
	}
	body := node_field(func, 'body')?
	if node_kind(body) != 'statement_block' {
		return PrttCandidate{
			report:     report
			class_span: class_span
			body:       unwrap_parens(body)
		}
	}
	mut returns := []PrttReturn{}
	prtt_collect_returns(body, mut returns, 0)
	return PrttCandidate{
		report:     report
		class_span: class_span
		block:      true
		returns:    returns
		body:       body
	}
}

// prtt_name_in_type ports tryGetNameInType: a type reference whose name is the class (type
// arguments allowed), alone or in a union.
fn (c &Checker) prtt_name_in_type(name string, type_node C.TSNode) ?C.TSNode {
	t := unwrap_type_parens(type_node)
	match node_kind(t) {
		'type_identifier' {
			if c.identifier_name(t) == name {
				return t
			}
		}
		'generic_type' {
			type_name := node_field(t, 'name')?
			if node_kind(type_name) == 'type_identifier' && c.identifier_name(type_name) == name {
				return t
			}
		}
		'union_type' {
			for part in named_children(t) {
				if found := c.prtt_name_in_type(name, part) {
					return found
				}
			}
		}
		else {}
	}
	return none
}

// prtt_collect_returns ports the walk of forEachReturnStatement: the `return` statements of the
// body outside nested functions and classes, in order.
fn prtt_collect_returns(n C.TSNode, mut out []PrttReturn, depth int) {
	if depth > max_expression_depth {
		return
	}
	for child in named_children(n) {
		kind := node_kind(child)
		if kind == 'return_statement' {
			expression := first_named(child) or { continue }
			out << PrttReturn{
				expression:   unwrap_parens(expression)
				this_keyword: node_kind(expression) == 'this'
			}
		} else if kind in prtt_return_containers {
			prtt_collect_returns(child, mut out, depth + 1)
		}
	}
}

// prtt_returns_this ports isFunctionReturningThis once the types are known.
fn (mut c Checker) prtt_returns_this(candidate PrttCandidate) !bool {
	class_type := c.span_type(candidate.class_span) or { return false }
	if !candidate.block {
		t := c.node_type(candidate.body) or { return false }
		return prtt_is_this_type(t, class_type)
	}
	mut has_return_this := false
	for r in candidate.returns {
		if r.this_keyword {
			has_return_this = true
			continue
		}
		t := c.node_type(r.expression) or { return false }
		if t.id == class_type.id {
			return false
		}
		if prtt_is_this_type(t, class_type) {
			has_return_this = true
			continue
		}
		if t.flags & type_flag_union != 0 {
			for part in c.members_of(t)! {
				if part.id == class_type.id {
					return false
				}
			}
		}
	}
	return has_return_this
}

// prtt_is_this_type: `t` is `classType.thisType`, the `this` type parameter TypeScript creates
// with the declared type of a class (and that a class expression's constructor type lacks).
fn prtt_is_this_type(t TypeResponse, class_type TypeResponse) bool {
	return class_type.object_flags & prtt_object_flag_class != 0
		&& t.flags & type_flag_type_parameter != 0 && t.is_this_type
		&& t.symbol == class_type.symbol
}
