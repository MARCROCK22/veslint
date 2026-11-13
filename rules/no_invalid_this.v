module rules

import json2
import jsregexp
import offsets
import time
import treesitter { children, named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-invalid-this` rule of ESLint 10.6.0, with astUtils.isDefaultThisBinding.

const nith_messages = {
	'unexpectedThis': "Unexpected 'this'."
}

fn nith_options(options []json2.Any) !bool {
	o := option_object(no_invalid_this, options, ['capIsConstructor'])!
	if 'capIsConstructor' in o.values {
		return o.bool_value('capIsConstructor')!
	}
	return true
}

fn (mut c Checker) lint_no_invalid_this(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	cap_is_constructor := nith_options(c.rule_options(no_invalid_this))!
	tree := c.scope_tree(root)
	mut findings := []Finding{}
	mut valid_cache := map[u64]bool{}
	for node in c.nodes_of_kinds(root, ['this'], []) {
		stats.checked++
		if parent := node_parent(node) {
			// `this` as a parameter or in a type predicate is not a ThisExpression.
			if node_kind(parent) in ['required_parameter', 'optional_parameter', 'type_predicate',
				'asserts', 'type_predicate_annotation', 'this_type'] {
				continue
			}
		}
		// The code path the `this` is in: the closest function that is not an arrow, static
		// block, class field initializer or accessor property value; the program otherwise.
		mut child := node
		mut current := node_parent(node) or { continue }
		mut owner := ?C.TSNode(none)
		mut accessor_value := false
		for {
			kind := node_kind(current)
			if kind in ['function_declaration', 'generator_function_declaration', 'function_expression',
				'generator_function'] || kind == 'class_static_block' {
				owner = current
				break
			}
			if kind == 'method_definition' && nith_in_method_function(current, child) {
				owner = current
				break
			}
			if kind == 'public_field_definition' {
				if value := node_field(current, 'value') {
					if node_key(value) == node_key(child) {
						if children(current).any(node_kind(it) == 'accessor') {
							accessor_value = true
						} else {
							owner = current
						}
						break
					}
				}
			}
			child = current
			current = node_parent(current) or { break }
		}
		if accessor_value {
			// An AccessorProperty's value is valid (and `this` as the value itself is skipped).
			continue
		}
		mut valid := true
		if o := owner {
			key := node_key(o)
			if cached := valid_cache[key] {
				valid = cached
			} else {
				scope := match node_kind(o) {
					'public_field_definition' { tree.get_scope(node_field(o, 'value') or { o }) }
					'class_static_block' { tree.get_scope(o) }
					else { tree.function_scope_of(o) }
				}
				valid = if !tree.is_strict(scope) {
					true
				} else if node_kind(o) in ['public_field_definition', 'class_static_block'] {
					true
				} else {
					!c.nith_is_default_this_binding(root, o, cap_is_constructor)
				}
				valid_cache[key] = valid
			}
		} else {
			// The program: `this` is undefined in a module, or in the function of a strict
			// CommonJS script.
			global_return_strict := c.scope_setup.global_return && tree.scopes.len > 1
				&& tree.is_strict(tree.scopes[0].children[0] or { 0 })
			valid = !(!c.scope_setup.script || global_return_strict)
		}
		if !valid {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unexpectedThis'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nith_in_method_function: `from` (a child of the method) is part of its function: the type
// parameters, the parameters, the return type or the body.
fn nith_in_method_function(method C.TSNode, from C.TSNode) bool {
	for field in ['type_parameters', 'parameters', 'return_type', 'body'] {
		if part := node_field(method, field) {
			if node_key(part) == node_key(from) && node_kind(part) == node_kind(from) {
				return true
			}
		}
	}
	return false
}

// nith_starts_with_upper ports startsWithUpperCase: the first UTF-16 unit changes when lowercased.
fn nith_starts_with_upper(name string) bool {
	units := utf16_units(name)
	if units.len == 0 {
		return false
	}
	return jsregexp.js_to_lower(units[..1]) != units[..1]
}

// nith_estree_parent is the ESTree parent of a node (parentheses are not nodes).
fn nith_estree_parent(n C.TSNode) ?(C.TSNode, C.TSNode) {
	return es_estree_parent(n)
}

fn (c &Checker) nith_is_null_or_undefined(n C.TSNode) bool {
	node := unwrap_parens(n)
	kind := node_kind(node)
	return kind == 'null' || (kind in ['identifier', 'undefined'] && c.text(node) == 'undefined')
		|| (kind == 'unary_expression' && operator_of(node) == 'void')
}

// nith_member_name is the static property name of a member expression and the name of its object
// when it is an identifier.
fn (c &Checker) nith_member(n C.TSNode) ?(string, string) {
	node := unwrap_parens(n)
	if node_kind(node) !in ['member_expression', 'subscript_expression'] {
		return none
	}
	name := c.es_static_property_name(node)?
	object := unwrap_parens(node_field(node, 'object')?)
	object_name := if node_kind(object) in ['identifier', 'undefined'] {
		c.identifier_name(object)
	} else {
		''
	}
	return name, object_name
}

fn (c &Checker) nith_call_args(call C.TSNode) []C.TSNode {
	arguments := node_field(call, 'arguments') or { return []C.TSNode{} }
	if node_kind(arguments) != 'arguments' {
		return []C.TSNode{}
	}
	return named_children(arguments).filter(node_kind(it) != 'comment')
}

// nith_is_callee ports isCallee: the node is the callee of a CallExpression.
fn nith_is_callee(n C.TSNode) bool {
	parent, child := es_estree_parent(n) or { return false }
	if node_kind(parent) != 'call_expression' {
		return false
	}
	arguments := node_field(parent, 'arguments') or { return false }
	if node_kind(arguments) == 'template_string' {
		return false
	}
	callee := node_field(parent, 'function') or { return false }
	return node_key(callee) == node_key(child)
}

// nith_is_default_this_binding ports astUtils.isDefaultThisBinding for a function.
fn (mut c Checker) nith_is_default_this_binding(root C.TSNode, f C.TSNode, cap_is_constructor bool) bool {
	if node_kind(f) == 'method_definition' {
		// Its FunctionExpression is the value of a MethodDefinition or Property.
		return false
	}
	if parent := node_parent(f) {
		if node_kind(parent) == 'public_field_definition' {
			if value := node_field(parent, 'value') {
				if node_key(unwrap_parens(value)) == node_key(f) {
					return false
				}
			}
		}
	}
	if parameters := node_field(f, 'parameters') {
		for p in named_children(parameters) {
			if pattern := node_field(p, 'pattern') {
				if node_kind(pattern) == 'this' {
					return false
				}
			}
		}
	}
	id := node_field(f, 'name')
	if name := id {
		if cap_is_constructor && nith_starts_with_upper(c.identifier_name(name)) {
			return false
		}
	}
	if c.nith_has_jsdoc_this_tag(root, f) {
		return false
	}
	anonymous := id == none
	mut current := f
	for {
		parent, child := es_estree_parent(current) or { return true }
		_ = child
		match node_kind(parent) {
			'ternary_expression' {
				current = parent
			}
			'binary_expression' {
				if operator_of(parent) !in ['&&', '||', '??'] {
					return true
				}
				current = parent
			}
			'return_statement' {
				// getUpperFunction
				mut func := parent
				for node_kind(func) !in ['function_declaration', 'generator_function_declaration',
					'function_expression', 'generator_function', 'arrow_function', 'method_definition'] {
					func = node_parent(func) or { return true }
				}
				if node_kind(func) == 'method_definition' || !nith_is_callee(func) {
					return true
				}
				call, _ := es_estree_parent(func) or { return true }
				current = call
			}
			'arrow_function' {
				body := node_field(parent, 'body') or { return true }
				if node_key(unwrap_parens(body)) != node_key(current) || !nith_is_callee(parent) {
					return true
				}
				call, _ := es_estree_parent(parent) or { return true }
				current = call
			}
			'pair' {
				value := node_field(parent, 'value') or { return true }
				return node_key(unwrap_parens(value)) != node_key(current)
			}
			'public_field_definition' {
				value := node_field(parent, 'value') or { return true }
				return node_key(unwrap_parens(value)) != node_key(current)
			}
			'assignment_expression', 'augmented_assignment_expression', 'assignment_pattern',
			'required_parameter', 'optional_parameter' {
				// A parameter with a default value is an AssignmentPattern.
				left := unwrap_parens(node_field(parent, if node_kind(parent).ends_with('_parameter') {
					'pattern'
				} else {
					'left'
				}) or { return true })
				if node_kind(left) in ['member_expression', 'subscript_expression'] {
					return false
				}
				if cap_is_constructor && anonymous && node_kind(left) in ['identifier', 'undefined']
					&& nith_starts_with_upper(c.identifier_name(left)) {
					return false
				}
				return true
			}
			'variable_declarator' {
				name := node_field(parent, 'name') or { return true }
				value := node_field(parent, 'value') or { return true }
				return !(cap_is_constructor && anonymous
					&& node_key(unwrap_parens(value)) == node_key(current)
					&& node_kind(name) in ['identifier', 'undefined']
					&& nith_starts_with_upper(c.identifier_name(name)))
			}
			'member_expression', 'subscript_expression' {
				object := node_field(parent, 'object') or { return true }
				if node_key(unwrap_parens(object)) == node_key(current) {
					if name, _ := c.nith_member(parent) {
						if name in ['bind', 'call', 'apply'] {
							if !nith_is_callee(parent) {
								return true
							}
							call, _ := es_estree_parent(parent) or { return true }
							args := c.nith_call_args(call)
							return !(args.len >= 1 && !c.nith_is_null_or_undefined(args[0]))
						}
					}
				}
				return true
			}
			'arguments' {
				call := node_parent(parent) or { return true }
				if node_kind(call) != 'call_expression' {
					return true
				}
				callee := node_field(call, 'function') or { return true }
				args := named_children(parent).filter(node_kind(it) != 'comment')
				index := args.map(node_key(unwrap_parens(it))).index(node_key(current))
				if name, object := c.nith_member(callee) {
					if object == 'Reflect' && name == 'apply' {
						return args.len != 3 || index != 0 || c.nith_is_null_or_undefined(args[1])
					}
					if (object.ends_with('Array') && name == 'from')
						|| (object == 'Array' && name == 'fromAsync') {
						return args.len != 3 || index != 1 || c.nith_is_null_or_undefined(args[2])
					}
					if name in ['every', 'filter', 'find', 'findLast', 'findIndex', 'findLastIndex',
						'flatMap', 'forEach', 'map', 'some'] {
						return args.len != 2 || index != 0 || c.nith_is_null_or_undefined(args[1])
					}
				}
				return true
			}
			else {
				return true
			}
		}
	}
	return true
}

// nith_has_jsdoc_this_tag ports hasJSDocThisTag: a `@this` tag in the function's JSDoc comment or
// in a comment right before it.
fn (mut c Checker) nith_has_jsdoc_this_tag(root C.TSNode, f C.TSNode) bool {
	tokens := c.source_tokens(root)
	if jsdoc := c.nith_jsdoc_comment(root, f) {
		if nith_has_this_tag(c.src[jsdoc.start + 2..jsdoc.end - 2]) {
			return true
		}
	}
	for comment in tokens.comments_before(node_start(f)) {
		value := if comment.kind == .block_comment {
			c.src[comment.start + 2..comment.end - 2]
		} else {
			c.src[comment.start + 2..comment.end]
		}
		if nith_has_this_tag(value) {
			return true
		}
	}
	return false
}

// nith_has_this_tag ports /^[\s*]*@this/mu: a line that starts with `@this` after white space and
// asterisks.
fn nith_has_this_tag(value string) bool {
	for line in value.split_any('\n\r  ') {
		trimmed := line.trim_left(' \t\v\f* ﻿')
		if trimmed.starts_with('@this') {
			return true
		}
	}
	return false
}

// nith_jsdoc_comment ports getJSDocComment for a function.
fn (mut c Checker) nith_jsdoc_comment(root C.TSNode, f C.TSNode) ?SourceToken {
	kind := node_kind(f)
	if kind in ['function_declaration', 'generator_function_declaration'] {
		mut target := f
		if parent := node_parent(f) {
			if node_kind(parent) == 'export_statement' {
				target = parent
			}
		}
		return c.nith_find_jsdoc(root, target)
	}
	parent, _ := es_estree_parent(f)?
	if node_kind(parent) !in ['call_expression', 'new_expression', 'arguments'] {
		tokens := c.source_tokens(root)
		mut p := ?C.TSNode(parent)
		for {
			node := p or { break }
			if tokens.comments_before(node_start(node)).len > 0 {
				break
			}
			pk := node_kind(node)
			if pk in function_kinds || pk == 'pair' {
				break
			}
			p = node_parent(node)
		}
		if node := p {
			if node_kind(node) !in ['function_declaration', 'generator_function_declaration', 'program'] {
				return c.nith_find_jsdoc(root, node)
			}
		}
	}
	return c.nith_find_jsdoc(root, f)
}

// nith_find_jsdoc ports findJSDocComment: a `/** */` comment right before the node, on its line or
// the one before.
fn (mut c Checker) nith_find_jsdoc(root C.TSNode, node C.TSNode) ?SourceToken {
	tokens := c.source_tokens(root)
	before := tokens.before(node_start(node), true)?
	if before.kind != .block_comment || before.end - before.start < 4
		|| c.src[before.start + 2] != `*` {
		return none
	}
	lines := offsets.line_starts(c.src)
	if lines.line_index(node_start(node)) - lines.line_index(before.end) <= 1 {
		return before
	}
	_ = node_end
	return none
}
