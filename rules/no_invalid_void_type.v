module rules

import json2
import time
import treesitter { children, named_children, node_field, node_kind, node_parent, position_of }

// Port of the `no-invalid-void-type` rule of typescript-eslint 8.62.0, with its options
// `allowAsThisParameter` and `allowInGenericTypeArguments` (true, false or a list of type names).

const nivt_messages = {
	'invalidVoidForGeneric':                    '{{ generic }} may not have void as a type argument.'
	'invalidVoidNotReturn':                     'void is only valid as a return type.'
	'invalidVoidNotReturnOrGeneric':            'void is only valid as a return type or generic type argument.'
	'invalidVoidNotReturnOrThisParam':          'void is only valid as return type or type of `this` parameter.'
	'invalidVoidNotReturnOrThisParamOrGeneric': 'void is only valid as a return type or generic type argument or the type of a `this` parameter.'
	'invalidVoidUnionConstituent':              'void is not valid as a constituent in a union type'
}

struct NivtOptions {
	allow_as_this_parameter bool
	// allowInGenericTypeArguments: `allow_in_generic` is its truth, and `generic_list` the names
	// when it is a list.
	allow_in_generic bool
	is_list          bool
	generic_list     []string
}

fn nivt_options(options []json2.Any) !NivtOptions {
	o := option_object(no_invalid_void_type, options, ['allowAsThisParameter',
		'allowInGenericTypeArguments'])!
	generic := o.values['allowInGenericTypeArguments'] or { json2.Any(true) }
	if generic is []json2.Any {
		return NivtOptions{
			allow_as_this_parameter: o.bool_value('allowAsThisParameter')!
			allow_in_generic:        true
			is_list:                 true
			generic_list:            generic.map(it.str().replace(' ', ''))
		}
	}
	return NivtOptions{
		allow_as_this_parameter: o.bool_value('allowAsThisParameter')!
		allow_in_generic:        o.bool_value('allowInGenericTypeArguments')!
	}
}

// NivtParent is the ESTree type of the parent of a `void`, as far as the rule tells them apart.
enum NivtParent {
	other
	type_annotation
	instantiation
	type_parameter
	union_type
}

// NivtPlace is where a `void` is in ESTree: its parent (`node`, the tree-sitter node that stands for
// it) and the type of its grandparent (`grand`: 'TSTypeReference', 'Identifier', 'CallExpression',
// 'TSPropertySignature', 'PropertyDefinition', 'AccessorProperty', or '' for the others), and
// whether that is the Identifier of a `this` parameter.
struct NivtPlace {
	parent         NivtParent
	node           C.TSNode
	grand          string
	this_parameter bool
}

fn (mut c Checker) lint_no_invalid_void_type(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nivt_options(c.rule_options(no_invalid_void_type))!
	mut findings := []Finding{}
	mut checked := 0
	for node in c.nodes_of_kind(root, c'predefined_type') {
		if c.text(node) != 'void' {
			continue
		}
		checked++
		message_id, data := c.nivt_check(node, o) or { continue }
		findings << Finding{
			stmt:       position_of(node)
			message_id: message_id
			data:       data
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nivt_check ports the TSVoidKeyword visitor: the message (and its data) to report, if any.
fn (mut c Checker) nivt_check(node C.TSNode, o NivtOptions) ?(string, map[string]string) {
	place := nivt_place(node)
	// T<..., void, ...>: allowed, or checked against the list.
	if place.parent == .instantiation && place.grand == 'TSTypeReference' {
		if o.is_list {
			name := node_field(node_parent(place.node)?, 'name')?
			qualified := c.text(name).replace(' ', '')
			if qualified !in o.generic_list {
				return 'invalidVoidForGeneric', {
					'generic': qualified
				}
			}
			return none
		}
		if !o.allow_in_generic {
			return if o.allow_as_this_parameter {
				'invalidVoidNotReturnOrThisParam'
			} else {
				'invalidVoidNotReturn'
			}, map[string]string{}
		}
		return none
	}
	// `<T = void>`: the default is allowed, a constraint next to it is not.
	if o.allow_in_generic && place.parent == .type_parameter {
		if default_type := nivt_default(place.node) {
			if nivt_is_keyword(default_type, 'void') {
				if node_key(default_type) != node_key(node) {
					return nivt_not_return_or_generic(place), map[string]string{}
				}
				return none
			}
		}
	}
	if place.parent == .union_type {
		// A union of void, never and T<..., void, ...> is allowed, and so is a union in the return
		// type of the implementation of an overloaded function.
		if c.nivt_is_valid_union(place.node) {
			return none
		}
		if function := nivt_parent_function_declaration(place.node) {
			if c.nivt_has_overload_signatures(function) {
				return none
			}
		}
	}
	if o.allow_as_this_parameter && place.parent == .type_annotation && place.this_parameter {
		return none
	}
	valid_parent := place.parent == .type_annotation
		|| (o.allow_in_generic && !o.is_list && place.parent == .instantiation)
	if valid_parent && place.grand !in ['TSPropertySignature', 'CallExpression', 'PropertyDefinition',
		'AccessorProperty', 'Identifier'] {
		return none
	}
	message_id := if o.allow_in_generic && o.allow_as_this_parameter {
		'invalidVoidNotReturnOrThisParamOrGeneric'
	} else if o.allow_in_generic {
		nivt_not_return_or_generic(place)
	} else if o.allow_as_this_parameter {
		'invalidVoidNotReturnOrThisParam'
	} else {
		'invalidVoidNotReturn'
	}
	return message_id, map[string]string{}
}

fn nivt_not_return_or_generic(place NivtPlace) string {
	return if place.parent == .union_type {
		'invalidVoidUnionConstituent'
	} else {
		'invalidVoidNotReturnOrGeneric'
	}
}

fn nivt_is_keyword(n C.TSNode, keyword string) bool {
	return node_kind(n) == 'predefined_type' && children(n).any(node_kind(it) == keyword)
}

// nivt_default is the default of a type parameter (without parentheses), if any.
fn nivt_default(type_parameter C.TSNode) ?C.TSNode {
	default_type := node_field(type_parameter, 'value')?
	return unwrap_type_parens(first_named(default_type)?)
}

// nivt_place finds the ESTree parent of a type (parentheses are not nodes in ESTree) and its
// grandparent.
fn nivt_place(n C.TSNode) NivtPlace {
	parent := type_parent(n) or { return NivtPlace{} }
	match node_kind(parent) {
		'type_arguments' {
			// TSTypeParameterInstantiation: of a TSTypeReference, or of a call, a `new`, a class's
			// superclass, a TSClassImplements or a TSInterfaceHeritage. The `<T>` of `<T>x` is the
			// type of a TSTypeAssertion.
			owner := node_parent(parent) or { return NivtPlace{} }
			if node_kind(owner) == 'type_assertion' {
				return NivtPlace{
					node: owner
				}
			}
			grand := match node_kind(owner) {
				'generic_type' {
					// In a heritage clause it is a TSClassImplements or a TSInterfaceHeritage.
					if node_kind(node_parent(owner) or { owner }) in [
						'implements_clause',
						'extends_type_clause',
					] {
						''
					} else {
						'TSTypeReference'
					}
				}
				'call_expression' {
					'CallExpression'
				}
				else {
					''
				}
			}
			return NivtPlace{
				parent: .instantiation
				node:   parent
				grand:  grand
			}
		}
		'constraint', 'default_type' {
			owner := node_parent(parent) or { return NivtPlace{} }
			if node_kind(owner) == 'type_parameter' {
				return NivtPlace{
					parent: .type_parameter
					node:   owner
				}
			}
			return NivtPlace{
				node: parent
			}
		}
		'union_type' {
			// The outermost of the unions nested without parentheses: ESTree has one TSUnionType.
			mut outermost := parent
			for {
				outer := node_parent(outermost) or { break }
				if node_kind(outer) != 'union_type' {
					break
				}
				outermost = outer
			}
			return NivtPlace{
				parent: .union_type
				node:   outermost
			}
		}
		'type_annotation' {
			holder := node_parent(parent) or { return NivtPlace{} }
			// The type of a mapped type (`[K in keyof T]: X`) is that of the TSMappedType.
			if node_kind(holder) == 'index_signature'
				&& children_of_kind(holder, 'mapped_type_clause').len > 0 {
				return NivtPlace{
					node: holder
				}
			}
			mut grand := ''
			mut this_parameter := false
			match node_kind(holder) {
				'required_parameter', 'optional_parameter' {
					// The Identifier of the parameter (a `this` too); a pattern or a rest element is
					// another type.
					pattern := node_field(holder, 'pattern') or { holder }
					if node_kind(pattern) == 'identifier' {
						grand = 'Identifier'
					} else if node_kind(pattern) == 'this' {
						grand = 'Identifier'
						this_parameter = true
					}
				}
				'variable_declarator' {
					name := node_field(holder, 'name') or { holder }
					if node_kind(name) == 'identifier' {
						grand = 'Identifier'
					}
				}
				'catch_clause' {
					grand = 'Identifier'
				}
				'public_field_definition' {
					grand = if children_of_kind(holder, 'accessor').len > 0 {
						'AccessorProperty'
					} else {
						'PropertyDefinition'
					}
				}
				'property_signature' {
					grand = 'TSPropertySignature'
				}
				else {}
			}
			return NivtPlace{
				parent:         .type_annotation
				node:           parent
				grand:          grand
				this_parameter: this_parameter
			}
		}
		'function_type', 'constructor_type', 'type_predicate' {
			// The return type of a TSFunctionType and the type of a TSTypePredicate are a
			// TSTypeAnnotation in ESTree.
			return NivtPlace{
				parent: .type_annotation
				node:   parent
			}
		}
		else {
			return NivtPlace{
				node: parent
			}
		}
	}
}

// nivt_union_members are the types of the TSUnionType of a union_type: the ones of the unions
// nested in it without parentheses.
fn nivt_union_members(union_node C.TSNode, mut out []C.TSNode) {
	for child in named_children(union_node) {
		if node_kind(child) == 'union_type' {
			nivt_union_members(child, mut out)
		} else if node_kind(child) != 'comment' {
			out << child
		}
	}
}

// nivt_is_valid_union ports isValidUnionType: every member is void, never or a TSTypeReference
// with a void type argument.
fn (c &Checker) nivt_is_valid_union(union_node C.TSNode) bool {
	mut members := []C.TSNode{}
	nivt_union_members(union_node, mut members)
	for member in members {
		m := unwrap_type_parens(member)
		if nivt_is_keyword(m, 'void') || nivt_is_keyword(m, 'never') {
			continue
		}
		if node_kind(m) == 'generic_type' {
			arguments := node_field(m, 'type_arguments') or { return false }
			if named_children(arguments).any(nivt_is_keyword(unwrap_type_parens(it), 'void')) {
				continue
			}
		}
		return false
	}
	return true
}

// nivt_parent_function_declaration ports getParentFunctionDeclarationNode: the closest
// FunctionDeclaration (`export default function () {}` too) or MethodDefinition with a body around
// the node.
fn nivt_parent_function_declaration(n C.TSNode) ?C.TSNode {
	mut node := n
	for {
		node = node_parent(node)?
		match node_kind(node) {
			'function_declaration', 'generator_function_declaration', 'method_definition' {
				return node
			}
			'function_expression', 'generator_function' {
				parent := node_parent(node) or { continue }
				if node_kind(parent) == 'export_statement' && children_of_kind(parent, 'default').len > 0 {
					return node
				}
			}
			else {}
		}
	}
	return none
}

// nivt_has_overload_signatures ports hasOverloadSignatures: a TSDeclareFunction (a function
// signature) or a MethodDefinition without a body (a method signature) with the same name next to
// the function, or for a default export another default export of a function signature.
fn (mut c Checker) nivt_has_overload_signatures(function C.TSNode) bool {
	parent := node_parent(function) or { return false }
	if node_kind(parent) == 'export_statement' {
		container := node_parent(parent) or { return false }
		default_export := children_of_kind(parent, 'default').len > 0
		name := c.nivt_function_name(function)
		for member in named_children(container) {
			if node_kind(member) != 'export_statement'
				|| (children_of_kind(member, 'default').len > 0) != default_export {
				continue
			}
			declaration := node_field(member, 'declaration') or { continue }
			if node_kind(declaration) != 'function_signature' {
				continue
			}
			if default_export || c.nivt_function_name(declaration) == name {
				return true
			}
		}
		return false
	}
	name := c.nivt_function_name(function)
	for member in named_children(parent) {
		if node_kind(member) in ['function_signature', 'method_signature']
			&& c.nivt_function_name(member) == name {
			return true
		}
	}
	return false
}

// nivt_function_name ports getFunctionDeclarationName: the name of a function, or the static name
// of a method ('' when there is none).
fn (mut c Checker) nivt_function_name(n C.TSNode) string {
	if node_kind(n) in ['method_definition', 'method_signature'] {
		return c.static_member_name(n) or { '' }
	}
	name := node_field(n, 'name') or { return '' }
	return c.text(name)
}
