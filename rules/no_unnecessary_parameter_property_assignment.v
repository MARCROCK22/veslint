module rules

import time
import treesitter { named_children, node_field, node_kind, node_parent, position_of }

// Port of the `no-unnecessary-parameter-property-assignment` rule of typescript-eslint 8.62.0 (it
// has no options).

const nuppa_messages = {
	'unnecessaryAssign': 'This assignment is unnecessary since it is already assigned by a parameter property.'
}

// NuppaAssignment is an assignment of the constructor that may be reported when its class body
// ends (unnecessaryAssignments): `frame` is the class body the rule's stack had on top.
struct NuppaAssignment {
	frame u64
	name  string
	node  C.TSNode
}

fn (mut c Checker) lint_no_unnecessary_parameter_property_assignment(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	// The rule keeps a stack with an entry per ClassBody being visited, so the entry an assignment
	// uses is that of the innermost class body around it. Its sets are keyed by `frame/name`.
	mut before_constructor := map[string]bool{} // assignedBeforeConstructor
	mut before_unnecessary := map[string]bool{} // assignedBeforeUnnecessary
	mut unnecessary := []NuppaAssignment{}
	for node in c.nodes_of_kinds(root, ['assignment_expression', 'augmented_assignment_expression'],
		[]) {
		body := nuppa_class_body(node) or { continue }
		frame := node_key(body)
		name := c.nuppa_property_name(node_field(node, 'left') or { continue }) or { continue }
		checked++
		// 'PropertyDefinition AssignmentExpression': directly in the initializer of a field, or in
		// an arrow function the initializer calls right away.
		if property := nuppa_parent_property(node) {
			mut counts := true
			if function := nuppa_parent_function(node) {
				counts = false
				if call := nuppa_iife_call(function) {
					if value := node_field(property, 'value') {
						counts = node_key(unwrap_parens(value)) == node_key(call)
					}
				}
			}
			if counts {
				before_constructor['${frame}/${name}'] = true
			}
		}
		// "MethodDefinition[kind='constructor'] > FunctionExpression AssignmentExpression": in the
		// constructor itself, or in an arrow function it calls right away.
		mut function := nuppa_parent_function(node) or { continue }
		if call := nuppa_iife_call(function) {
			function = nuppa_parent_function(call) or { continue }
		}
		if !c.nuppa_is_constructor(function) {
			continue
		}
		operator := node_kind(node_field(node, 'operator') or { node })
		if node_kind(node) == 'augmented_assignment_expression'
			&& operator !in ['??=', '&&=', '||='] {
			before_unnecessary['${frame}/${name}'] = true
			continue
		}
		right := nuppa_identifier(node_field(node, 'right') or { continue }) or { continue }
		if name != c.identifier_name(right) || !c.nuppa_is_parameter_reference(root, right) {
			continue
		}
		parameters := node_field(function, 'parameters') or { continue }
		has_property := named_children(parameters).any(c.nuppa_is_parameter_property(it, name))
		if has_property && !before_unnecessary['${frame}/${name}'] {
			unnecessary << NuppaAssignment{
				frame: frame
				name:  name
				node:  node
			}
		}
	}
	// 'ClassBody:exit': the assignments of a property that a field initializer does not assign.
	for assignment in unnecessary {
		if before_constructor['${assignment.frame}/${assignment.name}'] {
			continue
		}
		findings << Finding{
			stmt:       position_of(assignment.node)
			message_id: 'unnecessaryAssign'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nuppa_property_name ports getPropertyName: the name of `this.x`, `this[x]` (the name of the
// identifier, even computed) or `this['x']` (getStaticStringValue).
fn (c &Checker) nuppa_property_name(left C.TSNode) ?string {
	node := unwrap_parens(left)
	if !is_member(node) || node_kind(unwrap_parens(node_field(node, 'object')?)) != 'this' {
		return none
	}
	property := member_property(node)?
	if estree_type(property) == 'Identifier' {
		return c.identifier_name(property)
	}
	if node_kind(node) != 'subscript_expression' {
		return none
	}
	return c.literal_name(property)
}

// nuppa_identifier ports getIdentifier: the identifier, also inside `as` and `!`.
fn nuppa_identifier(n C.TSNode) ?C.TSNode {
	node := unwrap_parens(n)
	match node_kind(node) {
		'as_expression', 'non_null_expression' {
			return nuppa_identifier(first_named(node)?)
		}
		else {
			if estree_type(node) == 'Identifier' {
				return node
			}
			return none
		}
	}
}

// nuppa_class_body is the innermost class body around a node.
fn nuppa_class_body(n C.TSNode) ?C.TSNode {
	mut node := node_parent(n)?
	for node_kind(node) != 'class_body' {
		node = node_parent(node)?
	}
	return node
}

// nuppa_parent_property ports findParentPropertyDefinition: the closest field around a node
// (not an `accessor`, which is an AccessorProperty).
fn nuppa_parent_property(n C.TSNode) ?C.TSNode {
	mut node := node_parent(n)?
	for node_kind(node) != 'public_field_definition' || children_of_kind(node, 'accessor').len > 0 {
		node = node_parent(node)?
	}
	return node
}

// nuppa_parent_function ports findParentFunction from the node itself: the closest function
// declaration or expression, arrow function, or function of a method, around it.
fn nuppa_parent_function(n C.TSNode) ?C.TSNode {
	mut node := n
	mut from := ?C.TSNode(none)
	for {
		kind := node_kind(node)
		if kind in ['function_declaration', 'generator_function_declaration', 'function_expression',
			'generator_function', 'arrow_function'] {
			return node
		}
		// A method is the function only for its parameters and body, not for its name.
		if kind == 'method_definition' && scope_in_method_function(node, from) {
			return node
		}
		from = node
		node = node_parent(node)?
	}
	return none
}

// nuppa_iife_call ports isArrowIIFE: the call an arrow function is in (its callee or an argument).
fn nuppa_iife_call(function C.TSNode) ?C.TSNode {
	if node_kind(function) != 'arrow_function' {
		return none
	}
	parent := es_inner(function).parent()?
	if node_kind(parent.node) != 'call_expression' || parent.chain {
		return none
	}
	call_arguments(parent.node)?
	return parent.node
}

// nuppa_is_constructor ports isConstructorFunctionExpression: the function of a class
// constructor.
fn (c &Checker) nuppa_is_constructor(function C.TSNode) bool {
	if node_kind(function) != 'method_definition' {
		return false
	}
	body := node_parent(function) or { return false }
	return node_kind(body) == 'class_body' && c.pfa_is_constructor(function)
}

// nuppa_is_parameter_reference ports isReferenceFromParameter: the first reference of that name
// created in the scope of the identifier resolves to a variable whose first definition is a
// parameter.
fn (mut c Checker) nuppa_is_parameter_reference(root C.TSNode, id C.TSNode) bool {
	tree := c.scope_tree(root)
	name := c.identifier_name(id)
	for r in tree.scopes[tree.get_scope(id)].references {
		reference := tree.references[r]
		if reference.name != name {
			continue
		}
		if reference.resolved < 0 {
			return false
		}
		defs := tree.variables[reference.resolved].defs
		return defs.len > 0 && defs[0].kind == .parameter
	}
	return false
}

// nuppa_is_parameter_property ports isParameterPropertyWithName: `public foo` or `public foo = 1`
// (a parameter with a modifier is a TSParameterProperty).
fn (c &Checker) nuppa_is_parameter_property(parameter C.TSNode, name string) bool {
	if node_kind(parameter) !in ['required_parameter', 'optional_parameter'] {
		return false
	}
	if children_of_kind(parameter, 'accessibility_modifier').len == 0
		&& children_of_kind(parameter, 'override_modifier').len == 0
		&& children_of_kind(parameter, 'readonly').len == 0 {
		return false
	}
	pattern := node_field(parameter, 'pattern') or { return false }
	return node_kind(pattern) == 'identifier' && c.identifier_name(pattern) == name
}
