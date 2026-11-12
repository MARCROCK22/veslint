module rules

import json2
import time
import treesitter { has_child_kind, named_children, node_field, node_kind, node_parent, position_of }

// Port of the `class-literal-property-style` rule of typescript-eslint 8.62.0, with its option
// ('fields', the default, or 'getters') and its suggestions.

const clps_messages = {
	'preferFieldStyle':            'Literals should be exposed using readonly fields.'
	'preferFieldStyleSuggestion':  'Replace the literals with readonly fields.'
	'preferGetterStyle':           'Literals should be exposed using getters.'
	'preferGetterStyleSuggestion': 'Replace the literals with getters.'
}

fn clps_options(options []json2.Any) !string {
	if options.len == 0 {
		return 'fields'
	}
	style := options[0]
	if style is string && style in ['fields', 'getters'] {
		return style
	}
	return error('the option of `${class_literal_property_style}` must be "fields" or "getters"')
}

fn (mut c Checker) lint_class_literal_property_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	style := clps_options(c.rule_options(class_literal_property_style))!
	mut findings := []Finding{}
	mut checked := 0
	if style == 'fields' {
		for node in c.nodes_of_kind(root, c'method_definition') {
			checked++
			c.clps_check_getter(node, mut findings)!
		}
	} else {
		excluded := c.clps_assigned_in_constructors(root)
		for body in c.nodes_of_kind(root, c'class_body') {
			checked++
			c.clps_check_fields(body, excluded[node_key(body)] or { []string{} }, mut findings)!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// clps_check_getter ports the MethodDefinition visitor of 'fields': a getter, not `override`, whose
// first statement returns a literal, and that has no setter with the same static name.
fn (mut c Checker) clps_check_getter(node C.TSNode, mut findings []Finding) ! {
	holder := node_parent(node) or { return }
	if node_kind(holder) != 'class_body' || c.cm_method_kind(node) != 'get'
		|| has_child_kind(node, 'override_modifier') {
		return
	}
	body := node_field(node, 'body') or { return }
	statements := named_children(body)
	if statements.len == 0 || node_kind(statements[0]) != 'return_statement' {
		return
	}
	argument := cr_argument(statements[0]) or { return }
	if !clps_is_supported_literal(argument) {
		return
	}
	name := c.clps_member_key(node)
	if name != '' {
		for element in cm_members(holder) {
			if cm_type(element) == 'MethodDefinition' && c.cm_method_kind(element) == 'set'
				&& c.clps_member_key(element) == name {
				return
			}
		}
	}
	key, computed := clps_key(node) or { return }
	text := '${c.clps_modifiers(node, 'readonly')}${if computed {
		'[${c.cm_node_text(key)}]'
	} else {
		c.cm_node_text(key)
	}} = ${c.cm_node_text(argument)};'
	_, suggestion := c.suggestion('preferFieldStyleSuggestion', map[string]string{}, [
		fix_replace_range(cm_start(node), c.cm_node_end(node), text),
	])!
	findings << Finding{
		stmt:        position_of(key)
		message_id:  'preferFieldStyle'
		suggestions: [suggestion]
	}
}

// clps_check_fields ports the exit of a ClassBody for 'getters': its readonly fields (not
// `declare`, not `override`) initialized with a literal, but those with a static name the
// constructor assigns.
fn (mut c Checker) clps_check_fields(body C.TSNode, excluded []string, mut findings []Finding) ! {
	for node in cm_members(body) {
		if cm_type(node) != 'PropertyDefinition' || !has_child_kind(node, 'readonly')
			|| has_child_kind(node, 'declare') || has_child_kind(node, 'override_modifier') {
			continue
		}
		value := unwrap_parens(node_field(node, 'value') or { continue })
		if !clps_is_supported_literal(value) {
			continue
		}
		name := c.clps_member_key(node)
		if name != '' && name in excluded {
			continue
		}
		key, computed := clps_key(node) or { continue }
		text := '${c.clps_modifiers(node, 'get')}${if computed {
			'[${c.cm_node_text(key)}]'
		} else {
			c.cm_node_text(key)
		}}() { return ${c.cm_node_text(value)}; }'
		_, suggestion := c.suggestion('preferGetterStyleSuggestion', map[string]string{}, [
			fix_replace_range(cm_start(node), c.cm_end(node), text),
		])!
		findings << Finding{
			stmt:        position_of(key)
			message_id:  'preferGetterStyle'
			suggestions: [suggestion]
		}
	}
}

// clps_assigned_in_constructors ports excludeAssignedProperty on every
// `MethodDefinition[kind="constructor"] ThisExpression`: a member access on `this` whose closest
// function is a constructor and that is assigned, deleted or updated excludes its static name from
// the fields of the innermost class around the `this` (the top of the rule's stack), by the key of
// that class_body.
fn (mut c Checker) clps_assigned_in_constructors(root C.TSNode) map[u64][]string {
	mut excluded := map[u64][]string{}
	for this in c.nodes_of_kind(root, c'this') {
		member := estree_parent(this) or { continue }
		if node_kind(member) !in ['member_expression', 'subscript_expression'] {
			continue
		}
		function := clps_closest_function(member) or { continue }
		if node_kind(function) != 'method_definition'
			|| node_kind(node_parent(function) or { continue }) != 'class_body'
			|| c.cm_method_kind(function) != 'constructor' || !clps_is_assignee(member) {
			continue
		}
		name := c.clps_member_key(member)
		if name == '' {
			continue
		}
		mut body := this
		for node_kind(body) != 'class_body' {
			body = node_parent(body) or { break }
		}
		if node_kind(body) == 'class_body' {
			excluded[node_key(body)] << name
		}
	}
	return excluded
}

// clps_closest_function is the closest ancestor that is a function (isFunction: an arrow function,
// a function declaration or a function expression, which a method is in ESTree).
fn clps_closest_function(n C.TSNode) ?C.TSNode {
	mut node := n
	for {
		node = node_parent(node)?
		if node_kind(node) in ['arrow_function', 'function_declaration',
			'generator_function_declaration', 'function_expression', 'generator_function',
			'method_definition'] {
			return node
		}
	}
	return none
}

// clps_is_assignee ports isAssignee: the node is the left side of an assignment, the argument of
// `delete` or of `++`/`--`, an element or a rest element of an array pattern, the value of a
// Property of an ObjectExpression that is an assignee, or inside a `!`, `as`, `<T>` or `satisfies`
// that is.
fn clps_is_assignee(n C.TSNode) bool {
	mut child := n
	mut parent := node_parent(child) or { return false }
	for node_kind(parent) == 'parenthesized_expression' {
		child = parent
		parent = node_parent(parent) or { return false }
	}
	match node_kind(parent) {
		'assignment_expression', 'augmented_assignment_expression' {
			left := node_field(parent, 'left') or { return false }
			return node_key(unwrap_parens(left)) == node_key(n)
		}
		'unary_expression' {
			argument := node_field(parent, 'argument') or { return false }
			return operator_of(parent) == 'delete' && node_key(unwrap_parens(argument)) == node_key(n)
		}
		'update_expression' {
			return true
		}
		'array_pattern', 'rest_pattern' {
			return true
		}
		'pair' {
			value := node_field(parent, 'value') or { return false }
			object := node_parent(parent) or { return false }
			return node_key(unwrap_parens(value)) == node_key(n) && node_kind(object) == 'object'
				&& clps_is_assignee(object)
		}
		'non_null_expression', 'as_expression', 'type_assertion', 'satisfies_expression' {
			return clps_is_assignee(parent)
		}
		else {
			return false
		}
	}
}

// clps_is_supported_literal ports isSupportedLiteral: a Literal, a template without expressions, or
// a tagged template whose template has none.
fn clps_is_supported_literal(n C.TSNode) bool {
	match node_kind(n) {
		'string', 'number', 'true', 'false', 'null', 'regex' {
			return true
		}
		'template_string' {
			return !named_children(n).any(node_kind(it) == 'template_substitution')
		}
		'call_expression' {
			template := node_field(n, 'arguments') or { return false }
			return node_kind(template) == 'template_string'
				&& !named_children(template).any(node_kind(it) == 'template_substitution')
		}
		else {
			return false
		}
	}
}

// clps_key is the ESTree key of a member (the expression of a computed key, without its
// parentheses) and whether it is computed.
fn clps_key(member C.TSNode) ?(C.TSNode, bool) {
	name := node_field(member, 'name')?
	if node_kind(name) == 'computed_property_name' {
		return unwrap_parens(first_named(name)?), true
	}
	return name, false
}

// clps_modifiers ports printNodeModifiers: the accessibility, `static` and the final keyword.
fn (c &Checker) clps_modifiers(member C.TSNode, final string) string {
	accessibility := c.cm_accessibility(member)
	is_static := cm_is_static(member)
	return '${accessibility}${if is_static { ' static' } else { '' }} ${final} '.trim_left(' ')
}

// clps_member_key ports getStaticMemberAccessValue as a key to compare names with: `s` and the
// name, or `y` and the identity of a symbol (a well-known one, or one of Symbol.for); '' when it is
// not static or is the empty string, which is falsy.
fn (mut c Checker) clps_member_key(n C.TSNode) string {
	key, computed := stv_member_key(n) or { return '' }
	if !computed && node_kind(key) in ['property_identifier', 'identifier',
		'shorthand_property_identifier', 'private_property_identifier'] {
		name := c.static_member_name(n) or { return '' }
		return if name == '' { '' } else { 's${name}' }
	}
	result := c.get_static_value(key)
	if !result.found {
		return ''
	}
	if result.value.kind == .symbol_ {
		return if result.value.registered {
			'yr${stv_units_string(result.value.units)}'
		} else {
			'yw${result.value.name}'
		}
	}
	name := js_any_string_value(result.value) or { return '' }
	return if name == '' { '' } else { 's${name}' }
}
