module rules

import json2
import time
import tsgo { TypeResponse, handle_index, handle_kind, handle_path }
import treesitter { Ident, children, has_child_kind, named_children, node_end, node_field, node_kind, node_parent, node_start, nodes_of_kinds, position_of }

// Port of the `no-useless-default-assignment` rule of typescript-eslint 8.62.0, with its option
// and its fixes.

const nuda_messages = {
	'noStrictNullCheck':        'This rule requires the `strictNullChecks` compiler option to be turned on to function correctly.'
	'preferOptionalSyntax':     'Using `= undefined` to make a parameter optional adds unnecessary runtime logic. Use the `?` optional syntax instead.'
	'uselessDefaultAssignment': 'Default value is useless because the {{ type }} is not optional.'
	'uselessUndefined':         'Default value is useless because it is undefined. Optional {{ type }}s are already undefined by default.'
}

// SymbolFlags.Optional of TypeScript 7.1.0-beta.
const nuda_symbol_flag_optional = u32(16777216)

// The tree-sitter kinds of ESTree's isFunction (ArrowFunctionExpression, FunctionDeclaration,
// FunctionExpression; a method's FunctionExpression is its method_definition).
const nuda_function_kinds = ['function_declaration', 'generator_function_declaration',
	'function_expression', 'generator_function', 'arrow_function', 'method_definition']

// The tree-sitter kinds whose parameters belong to an ESTree ArrowFunctionExpression or
// FunctionExpression.
const nuda_function_expression_kinds = ['function_expression', 'generator_function', 'arrow_function',
	'method_definition']

struct NudaOptions {
	allow_without_strict_null_checks bool
}

fn nuda_options(options []json2.Any) !NudaOptions {
	o := option_object(no_useless_default_assignment, options, [
		'allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing',
	])!
	return NudaOptions{
		allow_without_strict_null_checks: o.bool_value('allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing')!
	}
}

// NudaParent is the ESTree parent of an AssignmentPattern.
enum NudaParent {
	function       // a parameter of a function or function-like (FunctionDeclaration…)
	param_property // a parameter with modifiers: TSParameterProperty
	property       // Property of an ObjectPattern
	array_pattern  // ArrayPattern
	other
}

// NudaPattern is an ESTree AssignmentPattern: a parameter with a default value, an
// `assignment_pattern` or an `object_assignment_pattern` (`{ a = 1 }`).
struct NudaPattern {
	node   C.TSNode
	right  C.TSNode // without parentheses
	parent NudaParent
}

fn (mut c Checker) lint_no_useless_default_assignment(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := nuda_options(c.rule_options(no_useless_default_assignment))!
	mut patterns := []NudaPattern{}
	mut spans := []Span{}
	for node in c.nodes_of_kinds(root, ['required_parameter', 'optional_parameter', 'assignment_pattern',
		'object_assignment_pattern'], []string{}) {
		pattern := nuda_pattern(node) or { continue }
		c.nuda_pattern_spans(pattern, mut spans)
		patterns << pattern
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	if !c.strict_null_checks && !o.allow_without_strict_null_checks {
		// ESLint reports it at line 0, column 0 (shown as 0:1).
		findings << Finding{
			stmt:       Ident{
				row: -1
			}
			message_id: 'noStrictNullCheck'
		}
	}
	for pattern in patterns {
		c.nuda_check(pattern, mut findings)!
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += patterns.len
	return findings
}

// nuda_pattern reads an AssignmentPattern and its ESTree parent.
fn nuda_pattern(node C.TSNode) ?NudaPattern {
	kind := node_kind(node)
	if kind in ['required_parameter', 'optional_parameter'] {
		value := node_field(node, 'value')?
		return NudaPattern{
			node:   node
			right:  unwrap_parens(value)
			parent: if nuda_has_modifiers(node) { .param_property } else { .function }
		}
	}
	right := node_field(node, 'right')?
	parent := node_parent(node)?
	return NudaPattern{
		node:   node
		right:  unwrap_parens(right)
		parent: if kind == 'object_assignment_pattern' || node_kind(parent) == 'pair_pattern' {
			NudaParent.property
		} else if node_kind(parent) == 'array_pattern' {
			NudaParent.array_pattern
		} else {
			NudaParent.other
		}
	}
}

// nuda_has_modifiers: a parameter property (`private a = 1`).
fn nuda_has_modifiers(parameter C.TSNode) bool {
	return has_child_kind(parameter, 'accessibility_modifier')
		|| has_child_kind(parameter, 'override_modifier') || has_child_kind(parameter, 'readonly')
}

// nuda_function is the function of a parameter (the parent of its formal_parameters).
fn nuda_function(parameter C.TSNode) ?C.TSNode {
	list := node_parent(parameter)?
	if node_kind(list) != 'formal_parameters' {
		return none
	}
	return node_parent(list)
}

// nuda_parameter_index is the index of a parameter in the ESTree `params` (a `this` parameter
// included).
fn nuda_parameter_index(parameter C.TSNode) int {
	list := node_parent(parameter) or { return -1 }
	for i, p in named_children(list) {
		if node_key(p) == node_key(parameter) {
			return i
		}
	}
	return -1
}

// nuda_pattern_spans requests what nuda_check may need for a pattern.
fn (c &Checker) nuda_pattern_spans(p NudaPattern, mut spans []Span) {
	if node_kind(p.right) == 'undefined' {
		if node_kind(p.node) in ['required_parameter', 'optional_parameter'] {
			if annotation := node_field(p.node, 'type') {
				if t := first_named(annotation) {
					spans << c.type_node_span(t)
				}
			}
		}
		return
	}
	match p.parent {
		.function {
			if f := nuda_function(p.node) {
				if node_kind(f) in nuda_function_expression_kinds {
					spans << function_span(f)
				}
			}
		}
		.property {
			property := if node_kind(p.node) == 'object_assignment_pattern' {
				p.node
			} else {
				node_parent(p.node) or { return }
			}
			if object := node_parent(property) {
				c.nuda_source_spans(object, mut spans, 0)
			}
		}
		.array_pattern {
			if array := node_parent(p.node) {
				c.nuda_source_spans(array, mut spans, 0)
			}
		}
		else {}
	}
}

// nuda_source_spans requests what nuda_source_type may need for a pattern.
fn (c &Checker) nuda_source_spans(p C.TSNode, mut spans []Span, depth int) {
	if depth > max_type_depth {
		return
	}
	if node_kind(p) in ['required_parameter', 'optional_parameter'] {
		if f := nuda_function(p) {
			if node_kind(f) in nuda_function_kinds {
				spans << function_span(f)
			}
		}
		return
	}
	parent := node_parent(p) or { return }
	match node_kind(parent) {
		'variable_declarator' {
			if value := node_field(parent, 'value') {
				spans << node_span(unwrap_parens(value))
			}
		}
		'required_parameter', 'optional_parameter' {
			c.nuda_source_spans(parent, mut spans, depth + 1)
		}
		'pair_pattern', 'assignment_pattern' {
			if node_kind(parent) == 'pair_pattern' {
				if object := node_parent(parent) {
					c.nuda_source_spans(object, mut spans, depth + 1)
				}
			} else {
				c.nuda_source_spans(parent, mut spans, depth + 1)
			}
		}
		'array_pattern' {
			c.nuda_source_spans(parent, mut spans, depth + 1)
		}
		else {}
	}
}

// nuda_check ports checkAssignmentPattern.
fn (mut c Checker) nuda_check(p NudaPattern, mut findings []Finding) ! {
	if node_kind(p.right) == 'undefined' {
		if node_kind(p.node) in ['required_parameter', 'optional_parameter'] {
			if annotation := node_field(p.node, 'type') {
				if type_node := first_named(annotation) {
					if t := c.node_type(type_node) {
						if c.nuda_can_be_undefined(t)! {
							findings << c.with_fixes(Finding{
								stmt:       position_of(p.right)
								message_id: 'preferOptionalSyntax'
							}, c.nuda_optional_fixes(p))!
							return
						}
					}
				}
			}
		}
		findings << Finding{
			stmt:       position_of(p.right)
			message_id: 'uselessUndefined'
			data:       {
				'type': if p.parent in [.property, .array_pattern] {
					'property'
				} else {
					'parameter'
				}
			}
			has_fix:    true
			fix:        c.nuda_remove_default(p)
		}
		return
	}
	match p.parent {
		.function {
			function := nuda_function(p.node) or { return }
			if node_kind(function) !in nuda_function_expression_kinds {
				return
			}
			index := nuda_parameter_index(p.node)
			if index < 0 {
				return
			}
			contextual := c.contextual_type(function)!
			if contextual.is_null() {
				return
			}
			signatures := c.signatures_of(contextual, signature_kind_call)!
			handle := c.node_handles[node_key(function)] or { return }
			if signatures.len == 0 || signatures[0].declaration == handle {
				return
			}
			params := c.signature_parameters(signatures[0])!
			if index >= params.len {
				return
			}
			param := params[index]
			if c.nuda_is_rest_parameter(param.value_declaration)! {
				return
			}
			if param.flags & nuda_symbol_flag_optional == 0 {
				param_type := c.symbol_type(param.id)!
				if param_type.flags & type_flag_type_parameter == 0
					&& !c.nuda_can_be_undefined(param_type)! {
					findings << c.nuda_useless(p, 'parameter')
				}
			}
		}
		.property {
			property := if node_kind(p.node) == 'object_assignment_pattern' {
				p.node
			} else {
				node_parent(p.node) or { return }
			}
			property_type := c.nuda_property_type(property, 0)!
			if !property_type.is_null() && !c.nuda_can_be_undefined(property_type)! {
				findings << c.nuda_useless(p, 'property')
			}
		}
		.array_pattern {
			array := node_parent(p.node) or { return }
			source := c.nuda_source_type(array, 0)!
			if source.is_null() || !c.is_tuple(source)! {
				return
			}
			args := c.type_args(source)!
			index := nuda_element_index(array, p.node)
			if index < 0 || index >= args.len {
				return
			}
			if !c.nuda_can_be_undefined(args[index])! {
				findings << c.nuda_useless(p, 'property')
			}
		}
		else {}
	}
}

fn (c &Checker) nuda_useless(p NudaPattern, kind string) Finding {
	return Finding{
		stmt:       position_of(p.right)
		message_id: 'uselessDefaultAssignment'
		data:       {
			'type': kind
		}
		has_fix:    true
		fix:        c.nuda_remove_default(p)
	}
}

// nuda_remove_default ports removeDefault: from the end of the left side (for a parameter, with
// its `?` and its type annotation, which the ESTree Identifier or pattern includes) to the end of
// the AssignmentPattern.
fn (c &Checker) nuda_remove_default(p NudaPattern) Fix {
	end := c.tokens.last_end(node_end(p.node))
	if left := node_field(p.node, 'left') {
		return fix_remove_range(node_end(unwrap_parens(left)), end)
	}
	for child in children(p.node) {
		if node_kind(child) == '=' {
			return fix_remove_range(c.tokens.last_end(node_start(child)), end)
		}
	}
	return fix_remove_range(end, end)
}

// nuda_optional_fixes ports the fixer of preferOptionalSyntax: the default goes and, if the
// parameter is an identifier, a `?` follows its name (`left.range[0] + left.name.length`, the
// length of the name without escapes).
fn (c &Checker) nuda_optional_fixes(p NudaPattern) []Fix {
	mut fixes := [c.nuda_remove_default(p)]
	pattern := node_field(p.node, 'pattern') or { return fixes }
	if node_kind(pattern) != 'identifier' {
		return fixes
	}
	mut offset := node_start(pattern)
	mut units := utf16_units(c.identifier_name(pattern)).len
	for units > 0 && offset < c.src.len {
		size := utf8_char_len(c.src[offset])
		units -= if size == 4 { 2 } else { 1 }
		offset += size
	}
	fixes << fix_insert_at(offset, '?')
	return fixes
}

// nuda_is_rest_parameter: the value declaration (a tsgo handle) is a Parameter with a `...`.
fn (mut c Checker) nuda_is_rest_parameter(handle string) !bool {
	if handle == '' || handle_kind(handle) != syntax_kind_parameter {
		return false
	}
	tree := c.declaration_ast(handle_path(handle))!
	return tree.node_child(handle_index(handle), 'dotDotDotToken') != 0
}

// nuda_can_be_undefined ports canBeUndefined.
fn (mut c Checker) nuda_can_be_undefined(t TypeResponse) !bool {
	if c.type_flags(t)! & (type_flag_any | type_flag_unknown) != 0 {
		return true
	}
	for part in c.constituents(t)! {
		if part.flags & type_flag_undefined != 0 {
			return true
		}
	}
	return false
}

// nuda_property_type ports getTypeOfProperty for a Property of an ObjectPattern (a pair_pattern or
// an object_assignment_pattern); the null type for null.
fn (mut c Checker) nuda_property_type(property C.TSNode, depth int) !TypeResponse {
	object := node_parent(property) or { return TypeResponse{} }
	source := c.nuda_source_type(object, depth + 1)!
	if source.is_null() {
		return TypeResponse{}
	}
	name := c.nuda_property_name(nuda_property_key(property) or { return TypeResponse{} }) or {
		return TypeResponse{}
	}
	symbol := c.property(source, name)!
	if symbol.is_null() {
		return TypeResponse{}
	}
	if symbol.flags & nuda_symbol_flag_optional != 0 {
		if declarator := node_parent(object) {
			if node_kind(declarator) == 'variable_declarator' {
				if value := node_field(declarator, 'value') {
					init := unwrap_parens(value)
					if nuda_is_conditional(init) && !c.nuda_in_all_branches(init, name, 0) {
						return TypeResponse{}
					}
				}
			}
		}
	}
	return c.symbol_type(symbol.id)!
}

// nuda_property_key is the ESTree key of a Property of an ObjectPattern.
fn nuda_property_key(property C.TSNode) ?C.TSNode {
	if node_kind(property) == 'object_assignment_pattern' {
		return node_field(property, 'left')
	}
	return node_field(property, 'key')
}

// nuda_is_conditional ports the test of hasConditionalInitializer: a ConditionalExpression or a
// LogicalExpression.
fn nuda_is_conditional(init C.TSNode) bool {
	return node_kind(init) == 'ternary_expression'
		|| estree_binary_kind(init) == 'LogicalExpression'
}

// nuda_in_all_branches ports hasPropertyInAllBranches.
fn (c &Checker) nuda_in_all_branches(expression C.TSNode, name string, depth int) bool {
	e := unwrap_parens(expression)
	if depth > max_expression_depth {
		return false
	}
	match node_kind(e) {
		'object' {
			for property in named_children(e) {
				key := match node_kind(property) {
					'pair', 'method_definition' {
						node_field(property, if node_kind(property) == 'pair' {
							'key'
						} else {
							'name'
						}) or { continue }
					}
					'shorthand_property_identifier' {
						property
					}
					else {
						continue
					}
				}
				if c.nuda_property_name(key) or { continue } == name {
					return true
				}
			}
			return false
		}
		'ternary_expression' {
			consequence := node_field(e, 'consequence') or { return false }
			alternative := node_field(e, 'alternative') or { return false }
			return c.nuda_in_all_branches(consequence, name, depth + 1)
				&& c.nuda_in_all_branches(alternative, name, depth + 1)
		}
		else {
			return false
		}
	}
}

// nuda_property_name ports the rule's getPropertyName: the name of an Identifier, String(value)
// of a Literal, the cooked text of a template without expressions; the key of a computed
// property is its expression.
fn (c &Checker) nuda_property_name(key C.TSNode) ?string {
	mut k := key
	if node_kind(k) == 'computed_property_name' {
		k = unwrap_parens(first_named(k)?)
	}
	text := c.text(k)
	match node_kind(k) {
		'property_identifier', 'shorthand_property_identifier_pattern',
		'shorthand_property_identifier', 'identifier', 'undefined' {
			return text
		}
		'string' {
			return cooked_string(text[1..text.len - 1], false)
		}
		'number' {
			return js_number_string(text)
		}
		'true', 'false', 'null', 'regex' {
			return text
		}
		'template_string' {
			for child in children(k) {
				if node_kind(child) == 'template_substitution' {
					return none
				}
			}
			return cooked_string(text[1..text.len - 1], true)
		}
		else {
			return none
		}
	}
}

// nuda_source_type ports getSourceTypeForPattern: the type destructured into a pattern (an
// object_pattern, an array_pattern, or an AssignmentPattern: an assignment_pattern or a parameter
// with a default value). The null type for null.
fn (mut c Checker) nuda_source_type(p C.TSNode, depth int) !TypeResponse {
	if depth > max_type_depth {
		return TypeResponse{}
	}
	if node_kind(p) in ['required_parameter', 'optional_parameter'] {
		return c.nuda_parameter_type(p)!
	}
	parent := node_parent(p) or { return TypeResponse{} }
	match node_kind(parent) {
		'variable_declarator' {
			name := node_field(parent, 'name') or { return TypeResponse{} }
			value := node_field(parent, 'value') or { return TypeResponse{} }
			if node_key(name) != node_key(p) {
				return TypeResponse{}
			}
			return c.node_type(unwrap_parens(value)) or { TypeResponse{} }
		}
		'required_parameter', 'optional_parameter' {
			// The pattern of a parameter: with a default value its parent is the AssignmentPattern.
			if _ := node_field(parent, 'value') {
				return c.nuda_source_type(parent, depth + 1)!
			}
			if nuda_has_modifiers(parent) {
				return TypeResponse{}
			}
			return c.nuda_parameter_type(parent)!
		}
		'pair_pattern' {
			value := node_field(parent, 'value') or { return TypeResponse{} }
			if node_key(value) != node_key(p) {
				return TypeResponse{}
			}
			return c.nuda_property_type(parent, depth + 1)!
		}
		'assignment_pattern' {
			left := node_field(parent, 'left') or { return TypeResponse{} }
			if node_key(left) != node_key(p) {
				return TypeResponse{}
			}
			return c.nuda_source_type(parent, depth + 1)!
		}
		'array_pattern' {
			source_array := c.nuda_source_type(parent, depth + 1)!
			if source_array.is_null() {
				return TypeResponse{}
			}
			index := nuda_element_index(parent, p)
			if c.is_tuple(source_array)! {
				args := c.type_args(source_array)!
				if index >= 0 && index < args.len {
					return args[index]
				}
			}
			return c.number_index_type(source_array)!
		}
		else {
			return TypeResponse{}
		}
	}
}

// nuda_parameter_type is the type of the parameter of a function at the ESTree index of `p` (an
// AssignmentPattern or a pattern parameter), from the signature of the function's declaration.
fn (mut c Checker) nuda_parameter_type(p C.TSNode) !TypeResponse {
	if nuda_has_modifiers(p) {
		return TypeResponse{}
	}
	function := nuda_function(p) or { return TypeResponse{} }
	if node_kind(function) !in nuda_function_kinds {
		return TypeResponse{}
	}
	handle := c.node_handles[node_key(function)] or { return TypeResponse{} }
	signature := c.client.signature_from_declaration(c.snapshot, c.project, handle)!
	if signature.id == 0 {
		return TypeResponse{}
	}
	mut index := nuda_parameter_index(p)
	if signature.this_parameter != 0 {
		index--
	}
	params := c.signature_parameters(signature)!
	if index < 0 || index >= params.len {
		return TypeResponse{}
	}
	return c.symbol_type(params[index].id)!
}

// nuda_element_index is the index of an element in the ESTree `elements` of an ArrayPattern,
// holes included: the commas before it.
fn nuda_element_index(array C.TSNode, element C.TSNode) int {
	mut commas := 0
	for child in children(array) {
		if node_key(child) == node_key(element) {
			return commas
		}
		if node_kind(child) == ',' {
			commas++
		}
	}
	return -1
}
