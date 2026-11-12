module rules

import json2
import time
import treesitter { has_child_kind, node_end, node_field, node_kind, node_parent, node_start }

// Port of the `consistent-generic-constructors` rule of typescript-eslint 8.62.0, with its option
// ('constructor' or 'type-annotation') and its fixes. Like the original, it reads the parser
// option `isolatedDeclarations` of the configuration.

const cgc_messages = {
	'preferConstructor':    'The generic type arguments should be specified as part of the constructor type arguments.'
	'preferTypeAnnotation': 'The generic type arguments should be specified as part of the type annotation.'
}

const cgc_builtin_arrays = ['Float32Array', 'Float64Array', 'Int16Array', 'Int32Array', 'Int8Array',
	'Uint16Array', 'Uint32Array', 'Uint8Array', 'Uint8ClampedArray']

// The functions whose parameters the selector `:matches(FunctionDeclaration,FunctionExpression) >
// AssignmentPattern` takes: not an arrow function, not a TSDeclareFunction.
const cgc_function_kinds = ['function_declaration', 'generator_function_declaration',
	'function_expression', 'generator_function', 'method_definition']

fn cgc_option(options []json2.Any) !string {
	option := if options.len > 0 { options[0] } else { json2.Any('constructor') }
	if option is string && option in ['constructor', 'type-annotation'] {
		return option
	}
	return error('the option of `${consistent_generic_constructors}` must be "constructor" or "type-annotation"')
}

// CgcSite is a VariableDeclarator, a PropertyDefinition or AccessorProperty, or an
// AssignmentPattern of a function: its tree-sitter node, where it starts in ESTree, its type
// annotation and its value.
struct CgcSite {
	node       C.TSNode
	start      int
	annotation ?C.TSNode
	value      C.TSNode
}

fn (mut c Checker) lint_consistent_generic_constructors(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mode := cgc_option(c.rule_options(consistent_generic_constructors))!
	mut findings := []Finding{}
	mut checked := 0
	for node in c.nodes_of_kinds(root, ['variable_declarator', 'public_field_definition',
		'required_parameter', 'optional_parameter'], []) {
		site := cgc_site(node) or { continue }
		rhs := unwrap_parens(site.value)
		if node_kind(rhs) != 'new_expression' {
			continue
		}
		callee := unwrap_parens(node_field(rhs, 'constructor') or { continue })
		if node_kind(callee) != 'identifier' {
			continue
		}
		checked++
		// The annotation, if any, names the class: a TSTypeReference with an Identifier, which is
		// not one of the global typed arrays.
		mut has_annotation := false
		mut lhs := callee
		if annotation := site.annotation {
			type_node := unwrap_type_parens(first_named(annotation) or { continue })
			name := c.cgc_reference_name(type_node) or { continue }
			if c.identifier_name(name) != c.identifier_name(callee)
				|| c.cgc_is_builtin_array(root, name) {
				continue
			}
			has_annotation = true
			lhs = type_node
		}
		mut rhs_has_arguments := false
		if _ := node_field(rhs, 'type_arguments') {
			rhs_has_arguments = true
		}
		if mode == 'type-annotation' {
			if has_annotation {
				continue
			}
			type_arguments := node_field(rhs, 'type_arguments') or { continue }
			text := c.text(callee) + c.text(type_arguments)
			findings << c.with_fixes(Finding{
				stmt:       c.position_at(site.start)
				message_id: 'preferTypeAnnotation'
			}, [fix_remove(type_arguments), fix_insert_at(c.cgc_annotation_offset(site), ': ${text}')])!
			continue
		}
		if c.scope_setup.isolated_decls || rhs_has_arguments || !has_annotation {
			continue
		}
		annotation := site.annotation or { continue }
		type_arguments := node_field(lhs, 'type_arguments') or { continue }
		findings << c.with_fixes(Finding{
			stmt:       c.position_at(site.start)
			message_id: 'preferConstructor'
		}, c.cgc_constructor_fixes(annotation, type_arguments, callee))!
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// cgc_site reads a node of the selector; none for the others (an abstract property, a parameter
// without default, of an arrow function or with modifiers, which a TSParameterProperty holds).
fn cgc_site(node C.TSNode) ?CgcSite {
	value := node_field(node, 'value')?
	annotation := node_field(node, 'type')
	match node_kind(node) {
		'variable_declarator' {
			return CgcSite{
				node:       node
				start:      node_start(node)
				annotation: annotation
				value:      value
			}
		}
		'public_field_definition' {
			if has_child_kind(node, 'abstract') {
				return none
			}
			return CgcSite{
				node:       node
				start:      node_start(node)
				annotation: annotation
				value:      value
			}
		}
		else {
			list := node_parent(node)?
			function := node_parent(list)?
			if node_kind(list) != 'formal_parameters' || node_kind(function) !in cgc_function_kinds
				|| has_child_kind(node, 'accessibility_modifier')
				|| has_child_kind(node, 'override_modifier') || has_child_kind(node, 'readonly') {
				return none
			}
			pattern := node_field(node, 'pattern') or { node_field(node, 'name')? }
			return CgcSite{
				node:       node
				start:      node_start(pattern)
				annotation: annotation
				value:      value
			}
		}
	}
}

// cgc_reference_name is the name of a TSTypeReference whose typeName is an Identifier (`Foo` or
// `Foo<T>`); none for any other type (`bigint` is a keyword for TypeScript).
fn (c &Checker) cgc_reference_name(type_node C.TSNode) ?C.TSNode {
	name := if node_kind(type_node) == 'generic_type' {
		node_field(type_node, 'name')?
	} else {
		type_node
	}
	if node_kind(name) != 'type_identifier' || c.text(name) == 'bigint' {
		return none
	}
	return name
}

// cgc_is_builtin_array ports isBuiltInArray: one of the global typed arrays, not declared in the
// file (isReferenceToGlobalFunction).
fn (mut c Checker) cgc_is_builtin_array(root C.TSNode, name C.TSNode) bool {
	text := c.identifier_name(name)
	if text !in cgc_builtin_arrays {
		return false
	}
	return is_reference_to_global_function(c.scope_tree(root), name, text)
}

// cgc_annotation_offset ports getIDToAttachAnnotation: after the id or the pattern (after its `?`
// for an optional parameter, which the ESTree pattern includes), after the key of a property, or
// after the token that follows a computed key.
fn (mut c Checker) cgc_annotation_offset(site CgcSite) int {
	node := site.node
	match node_kind(node) {
		'public_field_definition' {
			key := node_field(node, 'name') or { return node_end(node) }
			if node_kind(key) != 'computed_property_name' {
				return node_end(key)
			}
			expression := unwrap_parens(first_named(key) or { return node_end(key) })
			token := c.source_tokens(node).after(node_end(expression), false) or {
				return node_end(key)
			}
			return token.end
		}
		'variable_declarator' {
			id := node_field(node, 'name') or { return node_end(node) }
			return node_end(id)
		}
		else {
			pattern := node_field(node, 'pattern') or {
				node_field(node, 'name') or { return node_end(node) }
			}
			if node_kind(node) == 'optional_parameter' {
				if question := c.source_tokens(node).after(node_end(pattern), false) {
					if c.token_is(question, '?') {
						return question.end
					}
				}
			}
			return node_end(pattern)
		}
	}
}

// cgc_constructor_fixes: the annotation goes; its comments outside the type arguments, the type
// arguments and, when the `new` has no parentheses, `()` follow the callee.
fn (mut c Checker) cgc_constructor_fixes(annotation C.TSNode, type_arguments C.TSNode, callee C.TSNode) []Fix {
	tokens := c.source_tokens(annotation)
	mut has_parens := false
	if next := tokens.after(node_end(callee), false) {
		has_parens = c.token_text(next) == '('
	}
	mut fixes := [fix_remove(annotation)]
	for comment in tokens.comments_inside(node_start(annotation), node_end(annotation)) {
		if comment.start >= node_start(type_arguments) && comment.end <= node_end(type_arguments) {
			continue
		}
		fixes << fix_insert_after(callee, c.token_text(comment))
	}
	fixes << fix_insert_after(callee, c.text(type_arguments))
	if !has_parens {
		fixes << fix_insert_after(callee, '()')
	}
	return fixes
}
