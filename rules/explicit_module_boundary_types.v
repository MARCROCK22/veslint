module rules

import estree
import json2
import time

// Port of the `@typescript-eslint/explicit-module-boundary-types` rule of typescript-eslint
// 8.72.2, with all its options (util/explicitReturnTypeUtils.ts in
// rules/ts_explicit_return_type_utils.v). Like the rule, it checks the exports when it leaves them
// in ESLint's traversal, with the return statements of the functions it has entered so far, and
// the higher-order functions at the end of the program.

const embt_messages = {
	'anyTypedArg':           "Argument '{{name}}' should be typed with a non-any type."
	'anyTypedArgUnnamed':    '{{type}} argument should be typed with a non-any type.'
	'missingArgType':        "Argument '{{name}}' should be typed."
	'missingArgTypeUnnamed': '{{type}} argument should be typed.'
	'missingReturnType':     'Missing return type on function.'
}

struct EmbtOptions {
	allow_arguments_explicitly_typed_as_any bool
	allowed_names                           []string
	allow_overload_functions                bool
	ert                                     ErtOptions
}

fn embt_options(options []json2.Any) !EmbtOptions {
	o := option_object(explicit_module_boundary_types, options, [
		'allowArgumentsExplicitlyTypedAsAny', 'allowDirectConstAssertionInArrowFunctions',
		'allowedNames', 'allowHigherOrderFunctions', 'allowOverloadFunctions',
		'allowTypedFunctionExpressions'])!
	return EmbtOptions{
		allow_arguments_explicitly_typed_as_any: o.bool_value('allowArgumentsExplicitlyTypedAsAny') or {
			false
		}
		allowed_names:                           o.string_list('allowedNames') or { []string{} }
		allow_overload_functions:                o.bool_value('allowOverloadFunctions') or {
			false
		}
		ert:                                     ErtOptions{
			allow_direct_const_assertion_in_arrow_functions: o.bool_value('allowDirectConstAssertionInArrowFunctions') or {
				true
			}
			allow_higher_order_functions:                    o.bool_value('allowHigherOrderFunctions') or {
				true
			}
			allow_typed_function_expressions:                o.bool_value('allowTypedFunctionExpressions') or {
				true
			}
		}
	}
}

// EmbtState is what the rule remembers while ESLint traverses the file.
struct EmbtState {
	root C.vt_node
	t    &estree.EsTree
	o    EmbtOptions
mut:
	checked_functions map[int]bool
	already_visited   map[int]bool
	// The functions entered so far, in that order, and their return statements so far.
	function_order   []int
	function_returns map[int][]int
	findings         []Finding
}

fn (mut c Checker) lint_explicit_module_boundary_types(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := embt_options(c.rule_options(explicit_module_boundary_types))!
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut s := EmbtState{
		root: root
		t:    t
		o:    o
	}
	mut function_stack := []int{}
	for step in t.steps() {
		node := step.node
		typ := t.typ(node)
		if !step.leave {
			if ert_is_function(t, node) {
				stats.checked++
				function_stack << node
				s.function_order << node
				s.function_returns[node] = []int{}
			} else if typ == .return_statement && function_stack.len > 0 {
				s.function_returns[function_stack.last()] << node
			}
			continue
		}
		match typ {
			.arrow_function_expression, .function_declaration, .function_expression {
				function_stack.pop()
			}
			.export_default_declaration {
				c.embt_check_node(mut s, t.node(node, .declaration) or { -1 })
			}
			.export_named_declaration {
				if t.node(node, .source) != none {
					continue
				}
				if declaration := t.node(node, .declaration) {
					c.embt_check_node(mut s, declaration)
				} else {
					for specifier in t.list(node, .specifiers) or { []int{} } {
						c.embt_follow_reference(mut s, t.node(specifier, .local) or { continue })
					}
				}
			}
			.ts_export_assignment {
				c.embt_check_node(mut s, t.node(node, .expression) or { -1 })
			}
			.program {
				for f in s.function_order {
					if embt_is_exported_higher_order_function(s, f) {
						c.embt_check_node(mut s, f)
					}
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return s.findings
}

// embt_report_param reports a parameter (report in checkParameter).
fn (mut c Checker) embt_report_param(mut s EmbtState, param int, named string, unnamed string) {
	t := s.t
	mut message_id := ''
	mut data := map[string]string{}
	match t.typ(param) {
		.identifier {
			message_id = named
			data['name'] = t.string_of(param, .name) or { '' }
		}
		.array_pattern {
			message_id = unnamed
			data['type'] = 'Array pattern'
		}
		.object_pattern {
			message_id = unnamed
			data['type'] = 'Object pattern'
		}
		.rest_element {
			argument := t.node(param, .argument) or { -1 }
			if argument >= 0 && t.typ(argument) == .identifier {
				message_id = named
				data['name'] = t.string_of(argument, .name) or { '' }
			} else {
				message_id = unnamed
				data['type'] = 'Rest'
			}
		}
		else {
			return
		}
	}
	s.findings << Finding{
		stmt:       c.es_tree_position(t, param)
		message_id: message_id
		data:       data
	}
}

// embt_check_parameter ports checkParameter.
fn (mut c Checker) embt_check_parameter(mut s EmbtState, param int) {
	t := s.t
	match t.typ(param) {
		.array_pattern, .identifier, .object_pattern, .rest_element {
			annotation := t.node(param, .type_annotation) or {
				c.embt_report_param(mut s, param, 'missingArgType', 'missingArgTypeUnnamed')
				return
			}
			if !s.o.allow_arguments_explicitly_typed_as_any
				&& t.typ(t.node(annotation, .type_annotation) or { return }) == .ts_any_keyword {
				c.embt_report_param(mut s, param, 'anyTypedArg', 'anyTypedArgUnnamed')
			}
		}
		.ts_parameter_property {
			c.embt_check_parameter(mut s, t.node(param, .parameter) or { return })
		}
		else {}
	}
}

// embt_check_parameters ports checkParameters.
fn (mut c Checker) embt_check_parameters(mut s EmbtState, node int) {
	for param in s.t.list(node, .params) or { []int{} } {
		c.embt_check_parameter(mut s, param)
	}
}

// embt_member_key ports getStaticMemberAccessValue of a member with a key: none for undefined,
// `s` and the string, or `y` and the symbol (a well-known one by its name, one of Symbol.for by
// its key), so that equal values give equal keys.
fn (mut c Checker) embt_member_key(t &estree.EsTree, node int) ?string {
	key := t.node(node, .key)?
	computed := t.flag(node, .computed) or { false }
	if !computed && t.typ(key) in [.identifier, .private_identifier] {
		return 's' + (t.string_of(key, .name) or { '' })
	}
	ts := t.ts_node(node)?
	key_ts, _ := stv_member_key(ts)?
	result := c.get_static_value(key_ts)
	if !result.found {
		return none
	}
	if result.value.kind == .symbol_ {
		if result.value.registered {
			return 'yr' + stv_units_string(result.value.units)
		}
		return 'yw' + result.value.name
	}
	return 's' + js_any_string_value(result.value)?
}

// embt_is_allowed_name ports isAllowedName.
fn (mut c Checker) embt_is_allowed_name(s &EmbtState, node int) bool {
	t := s.t
	if node < 0 || s.o.allowed_names.len == 0 {
		return false
	}
	typ := t.typ(node)
	if typ in [.variable_declarator, .function_declaration] {
		id := t.node(node, .id) or { return false }
		return t.typ(id) == .identifier && (t.string_of(id, .name) or { '' }) in s.o.allowed_names
	}
	if typ in [.method_definition, .ts_abstract_method_definition, .property_definition,
		.accessor_property] || (typ == .property && (t.flag(node, .method) or { false })) {
		key := c.embt_member_key(t, node) or { return false }
		return key.starts_with('s') && key[1..] in s.o.allowed_names
	}
	return false
}

// embt_is_exported_higher_order_function ports isExportedHigherOrderFunction.
fn embt_is_exported_higher_order_function(s &EmbtState, node int) bool {
	t := s.t
	mut current := t.nodes[node].parent
	for current >= 0 {
		if t.typ(current) == .return_statement {
			// the parent of a return will always be a block statement, so we can skip over it
			parent := t.nodes[current].parent
			current = if parent >= 0 { t.nodes[parent].parent } else { -1 }
			continue
		}
		if !ert_is_function(t, current) {
			return false
		}
		returns := s.function_returns[current] or { []int{} }
		if !ert_does_immediately_return_function_expression(t, current, returns) {
			return false
		}
		if s.checked_functions[current] {
			return true
		}
		current = t.nodes[current].parent
	}
	return false
}

// embt_follow_reference ports followReference.
fn (mut c Checker) embt_follow_reference(mut s EmbtState, node int) {
	t := s.t
	ts := t.ts_node(node) or { return }
	tree := c.scope_tree(s.root)
	scope := tree.get_scope(ts)
	v := tree.set_get(scope, t.string_of(node, .name) or { return }) or { return }
	variable := tree.variables[v]
	for def in variable.defs {
		if def.kind in [.catch_clause, .import_binding, .parameter] {
			continue
		}
		c.embt_check_node(mut s, c.es_index_of(t, def.node) or { continue })
	}
	for r in variable.references {
		reference := tree.references[r]
		if reference.init || !reference.write {
			continue
		}
		id := c.es_index_of(t, reference.identifier) or { continue }
		write_expr := rau_reference_write_expr(t, id)
		if write_expr >= 0 {
			c.embt_check_node(mut s, write_expr)
		}
	}
}

// embt_check_node ports checkNode.
fn (mut c Checker) embt_check_node(mut s EmbtState, node int) {
	t := s.t
	if node < 0 || s.already_visited[node] {
		return
	}
	s.already_visited[node] = true
	match t.typ(node) {
		.arrow_function_expression, .function_expression {
			c.embt_check_function_expression(mut s, node)
		}
		.array_expression {
			for element in t.list(node, .elements) or { []int{} } {
				c.embt_check_node(mut s, element)
			}
		}
		.property_definition, .accessor_property, .method_definition,
		.ts_abstract_method_definition {
			key := t.node(node, .key) or { -1 }
			if (t.string_of(node, .accessibility) or { '' }) == 'private'
				|| (key >= 0 && t.typ(key) == .private_identifier) {
				return
			}
			c.embt_check_node(mut s, t.node(node, .value) or { -1 })
		}
		.class_declaration, .class_expression {
			body := t.node(node, .body) or { return }
			for element in t.list(body, .body) or { []int{} } {
				c.embt_check_node(mut s, element)
			}
		}
		.function_declaration {
			c.embt_check_function(mut s, node)
		}
		.identifier {
			c.embt_follow_reference(mut s, node)
		}
		.object_expression {
			for property in t.list(node, .properties) or { []int{} } {
				c.embt_check_node(mut s, property)
			}
		}
		.property {
			c.embt_check_node(mut s, t.node(node, .value) or { -1 })
		}
		.ts_empty_body_function_expression {
			c.embt_check_empty_body_function_expression(mut s, node)
		}
		.variable_declaration {
			for declaration in t.list(node, .declarations) or { []int{} } {
				c.embt_check_node(mut s, declaration)
			}
		}
		.variable_declarator {
			c.embt_check_node(mut s, t.node(node, .init) or { -1 })
		}
		else {}
	}
}

// embt_check_empty_body_function_expression ports checkEmptyBodyFunctionExpression.
fn (mut c Checker) embt_check_empty_body_function_expression(mut s EmbtState, node int) {
	t := s.t
	parent := t.nodes[node].parent
	kind := t.string_of(parent, .kind) or { '' }
	is_constructor := t.typ(parent) == .method_definition && kind == 'constructor'
	is_set_accessor := t.typ(parent) in [.ts_abstract_method_definition, .method_definition]
		&& kind == 'set'
	if !is_constructor && !is_set_accessor && t.node(node, .return_type) == none {
		s.findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'missingReturnType'
		}
	}
	c.embt_check_parameters(mut s, node)
}

// embt_check_function_expression ports checkFunctionExpression.
fn (mut c Checker) embt_check_function_expression(mut s EmbtState, node int) {
	t := s.t
	if s.checked_functions[node] {
		return
	}
	s.checked_functions[node] = true
	parent := t.nodes[node].parent
	if c.embt_is_allowed_name(s, parent) || ert_is_typed_function_expression(t, node, s.o.ert)
		|| ert_ancestor_has_return_type(t, node) {
		return
	}
	if s.o.allow_overload_functions && t.typ(parent) == .method_definition
		&& c.embt_has_overload_signatures(s, parent) {
		return
	}
	returns := s.function_returns[node] or { []int{} }
	if head := c.ert_check_function_expression_return_type(t, node, returns, s.o.ert) {
		s.findings << Finding{
			stmt:       head
			message_id: 'missingReturnType'
		}
	}
	c.embt_check_parameters(mut s, node)
}

// embt_check_function ports checkFunction.
fn (mut c Checker) embt_check_function(mut s EmbtState, node int) {
	t := s.t
	if s.checked_functions[node] {
		return
	}
	s.checked_functions[node] = true
	if c.embt_is_allowed_name(s, node) || ert_ancestor_has_return_type(t, node) {
		return
	}
	if s.o.allow_overload_functions && c.embt_has_overload_signatures(s, node) {
		return
	}
	returns := s.function_returns[node] or { []int{} }
	if head := c.ert_check_function_return_type(t, node, returns, s.o.ert) {
		s.findings << Finding{
			stmt:       head
			message_id: 'missingReturnType'
		}
	}
	c.embt_check_parameters(mut s, node)
}

// embt_function_declaration_name ports getFunctionDeclarationName (none for undefined).
fn (mut c Checker) embt_function_declaration_name(t &estree.EsTree, node int) ?string {
	if t.typ(node) in [.function_declaration, .ts_declare_function] {
		id := t.node(node, .id)?
		return 's' + (t.string_of(id, .name) or { '' })
	}
	return c.embt_member_key(t, node)
}

// embt_same_name compares two names of getFunctionDeclarationName (`===`).
fn embt_same_name(a ?string, b ?string) bool {
	if x := a {
		if y := b {
			return x == y
		}
		return false
	}
	return b == none
}

// embt_has_overload_signatures ports hasOverloadSignatures for a function declaration or a
// method.
fn (mut c Checker) embt_has_overload_signatures(s &EmbtState, node int) bool {
	t := s.t
	parent := t.nodes[node].parent
	if t.typ(parent) == .export_default_declaration {
		for member in t.list(t.nodes[parent].parent, .body) or { []int{} } {
			if t.typ(member) == .export_default_declaration {
				declaration := t.node(member, .declaration) or { continue }
				if t.typ(declaration) == .ts_declare_function {
					return true
				}
			}
		}
		return false
	}
	if t.typ(parent) == .export_named_declaration {
		name := c.embt_function_declaration_name(t, node)
		for member in t.list(t.nodes[parent].parent, .body) or { []int{} } {
			if t.typ(member) != .export_named_declaration {
				continue
			}
			declaration := t.node(member, .declaration) or { continue }
			if t.typ(declaration) == .ts_declare_function
				&& embt_same_name(c.embt_function_declaration_name(t, declaration), name) {
				return true
			}
		}
		return false
	}
	name := c.embt_function_declaration_name(t, node)
	for member in t.list(parent, .body) or { []int{} } {
		is_signature := t.typ(member) == .ts_declare_function
			|| (t.typ(member) == .method_definition
			&& t.node(t.node(member, .value) or { continue }, .body) == none)
		if is_signature && embt_same_name(name, c.embt_function_declaration_name(t, member)) {
			return true
		}
	}
	return false
}
