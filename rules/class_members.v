module rules

import treesitter { children, has_child_kind, named_children, node_end, node_field, node_kind, node_parent, node_start, next_sibling, prev_sibling }

// The members of a class body as typescript-estree 8.62.0 has them, for the rules that look at
// their ESTree type, kind, modifiers and range. In tree-sitter the decorators of a method are its
// siblings, before it, and the `;` that ends a field, an overload or an index signature, which
// TypeScript counts in the member, follows it.

// cm_type is the ESTree type of a child of a class_body: MethodDefinition (a method_definition, or
// a method_signature: an overload, or a method of a declared class, whose value is a
// TSEmptyBodyFunctionExpression), TSAbstractMethodDefinition, PropertyDefinition, AccessorProperty,
// TSAbstractPropertyDefinition, TSAbstractAccessorProperty, TSIndexSignature or StaticBlock; ''
// for what is not a member (the decorators of the next method, comments, `;`).
fn cm_type(member C.TSNode) string {
	match node_kind(member) {
		'method_definition', 'method_signature' {
			return 'MethodDefinition'
		}
		'abstract_method_signature' {
			return 'TSAbstractMethodDefinition'
		}
		'public_field_definition' {
			is_abstract := has_child_kind(member, 'abstract')
			is_accessor := has_child_kind(member, 'accessor')
			return if is_abstract && is_accessor {
				'TSAbstractAccessorProperty'
			} else if is_abstract {
				'TSAbstractPropertyDefinition'
			} else if is_accessor {
				'AccessorProperty'
			} else {
				'PropertyDefinition'
			}
		}
		'index_signature' {
			return 'TSIndexSignature'
		}
		'class_static_block' {
			return 'StaticBlock'
		}
		else {
			return ''
		}
	}
}

// cm_members are the ESTree members of a class_body, in order.
fn cm_members(body C.TSNode) []C.TSNode {
	return named_children(body).filter(cm_type(it) != '')
}

// cm_method_kind is the `kind` of a MethodDefinition or TSAbstractMethodDefinition: 'get', 'set',
// 'constructor' or 'method'. TypeScript parses as a constructor a member named `constructor` or
// `'constructor'` that is not static; typescript-estree also gives that kind to a method named by
// the string, like `*'constructor'() {}`, but not to a generator named by the identifier.
fn (c &Checker) cm_method_kind(member C.TSNode) string {
	if has_child_kind(member, 'get') {
		return 'get'
	}
	if has_child_kind(member, 'set') {
		return 'set'
	}
	if has_child_kind(member, 'static') {
		return 'method'
	}
	name := node_field(member, 'name') or { return 'method' }
	is_constructor := match node_kind(name) {
		'property_identifier' {
			!has_child_kind(member, '*') && c.identifier_name(name) == 'constructor'
		}
		'string' {
			(c.literal_name(name) or { '' }) == 'constructor'
		}
		else {
			false
		}
	}
	return if is_constructor { 'constructor' } else { 'method' }
}

// cm_is_static: the member has the `static` modifier.
fn cm_is_static(member C.TSNode) bool {
	return has_child_kind(member, 'static')
}

// cm_accessibility is the `accessibility` of a member or a parameter: 'public', 'protected',
// 'private' or ''.
fn (c &Checker) cm_accessibility(n C.TSNode) string {
	for child in children(n) {
		if node_kind(child) == 'accessibility_modifier' {
			return c.text(child)
		}
	}
	return ''
}

// cm_decorators are the decorators of a member: those of a method are the siblings before it
// (with comments in between), those of a field its children.
fn cm_decorators(member C.TSNode) []C.TSNode {
	mut out := children(member).filter(node_kind(it) == 'decorator')
	if node_kind(member) in ['method_definition', 'method_signature', 'abstract_method_signature'] {
		mut before := []C.TSNode{}
		mut node := member
		for {
			node = prev_sibling(node) or { break }
			kind := node_kind(node)
			if kind == 'comment' {
				continue
			}
			if kind != 'decorator' {
				break
			}
			before.prepend(node)
		}
		out.prepend(before)
	}
	return out
}

// cm_start is where the ESTree member starts: at its first decorator.
fn cm_start(member C.TSNode) int {
	decorators := cm_decorators(member)
	return if decorators.len > 0 { node_start(decorators[0]) } else { node_start(member) }
}

// cm_end is where the ESTree member ends: after the `;` that closes a field, an overload, an
// abstract member or an index signature (a method with a body ends at its `}`), and never after a
// comment tree-sitter leaves at the end of the node.
fn (c &Checker) cm_end(member C.TSNode) int {
	if node_kind(member) in ['method_definition', 'class_static_block'] {
		return c.cm_node_end(member)
	}
	mut node := member
	for {
		node = next_sibling(node) or { break }
		kind := node_kind(node)
		if kind == 'comment' {
			continue
		}
		if kind == ';' && node_end(node) > node_start(node) {
			return node_end(node)
		}
		break
	}
	return c.cm_node_end(member)
}

// cm_node_end is where TypeScript ends a node: at the end of its last token, without the comments
// tree-sitter may leave at its end.
fn (c &Checker) cm_node_end(n C.TSNode) int {
	return c.tokens.last_end(node_end(n))
}

// cm_node_text is the text of a node as TypeScript ranges it (getText).
fn (c &Checker) cm_node_text(n C.TSNode) string {
	return c.src[node_start(n)..c.cm_node_end(n)]
}

// cm_super_class is the `superClass` of a class: the value of its `extends` clause.
fn cm_super_class(class C.TSNode) ?C.TSNode {
	for child in named_children(class) {
		if node_kind(child) == 'class_heritage' {
			for clause in named_children(child) {
				if node_kind(clause) == 'extends_clause' {
					return node_field(clause, 'value') or { return first_named(clause) }
				}
			}
		}
	}
	return none
}

// cm_class_decorators are the `decorators` of a class: its own, and those before the `export` of
// an exported class, which tree-sitter gives the export_statement.
fn cm_class_decorators(class C.TSNode) []C.TSNode {
	mut out := children(class).filter(node_kind(it) == 'decorator')
	if parent := node_parent(class) {
		if node_kind(parent) == 'export_statement' {
			out.prepend(children(parent).filter(node_kind(it) == 'decorator'))
		}
	}
	return out
}

// cm_parameters are the ESTree `params` of a function or method: its parameters, `this` included.
fn cm_parameters(function C.TSNode) []C.TSNode {
	parameters := node_field(function, 'parameters') or { return []C.TSNode{} }
	return named_children(parameters)
}

// cm_is_parameter_property: the parameter is a TSParameterProperty, a parameter with a modifier
// (an accessibility, `readonly` or `override`).
fn cm_is_parameter_property(parameter C.TSNode) bool {
	for child in children(parameter) {
		if node_kind(child) in ['accessibility_modifier', 'readonly', 'override_modifier'] {
			return true
		}
	}
	return false
}
