module rules

import estree
import time
import x.json2
import tsgo { TypeResponse }
import treesitter { node_end, node_start }

// Port of the `unicorn/prefer-default-parameters` rule of eslint-plugin-unicorn 79.0.0, with its
// `checkFallbackExpressions` option and its suggestions. Like unicorn's, it reads the types of
// TypeScript (here tsgo's) when the parser has a program, to tell whether a default value keeps
// what the fallback gives (isDefaultValueCompatible).

const updp_messages = {
	'preferDefaultParameters':                'Prefer default parameters over reassignment.'
	'preferDefaultParametersSuggest':         'Replace reassignment with a default parameter. This changes fallback behavior to apply only to undefined.'
	'preferDefaultParameterOverFallback':     'Prefer a default parameter over fallback expressions.'
	'preferDestructuringDefaultOverFallback': 'Prefer a destructuring default over fallback expressions.'
	'moveDefaultToDeclaration':               'Move the default value to the declaration. This changes fallback behavior to apply only to undefined.'
}

fn updp_options(options []json2.Any) !bool {
	o := option_object(unicorn_prefer_default_parameters, options, ['checkFallbackExpressions'])!
	return o.bool_value('checkFallbackExpressions')!
}

fn (mut c Checker) lint_unicorn_prefer_default_parameters(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	check_fallback_expressions := updp_options(c.rule_options(unicorn_prefer_default_parameters))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .assignment_expression {
			continue
		}
		stats.checked++
		parent := t.nodes[node].parent
		if parent >= 0 && t.typ(parent) == .expression_statement
			&& (t.node(parent, .expression) or { -1 }) == node {
			if finding := c.updp_default_parameter_problem(mut ctx, parent) {
				findings << finding
			}
		}
	}
	if check_fallback_expressions {
		tree := c.scope_tree(root)
		for v in 0 .. tree.variables.len {
			if tree.variables[v].defs.len != 1 {
				continue
			}
			def := tree.variables[v].defs[0]
			if def.kind !in [.parameter, .variable] {
				continue
			}
			mut node := c.es_index_of(t, def.node) or { continue }
			// The declarator of `for (const [a] of …)` shares its node with its pattern.
			for def.kind == .variable && t.typ(node) != .variable_declarator
				&& t.nodes[node].parent >= 0 {
				parent := t.nodes[node].parent
				parent_ts := t.ts_node(parent) or { break }
				if node_key(parent_ts) != node_key(def.node) {
					break
				}
				node = parent
			}
			if t.typ(node) !in [.function_declaration, .function_expression,
				.arrow_function_expression, .variable_declarator] {
				continue
			}
			stats.checked++
			if finding := c.updp_default_read_problem(mut ctx, v, node) {
				findings << finding
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// updp_is_static_default_value ports isStaticDefaultValue: a literal, a static string, or a
// negated numeric literal.
fn updp_is_static_default_value(t &estree.EsTree, node int) bool {
	if t.typ(node) == .literal || un_static_string_value(t, node) != none {
		return true
	}
	if t.typ(node) != .unary_expression || (t.string_of(node, .operator) or { '' }) != '-' {
		return false
	}
	argument := t.node(node, .argument) or { return false }
	if t.typ(argument) != .literal {
		return false
	}
	return t.get(argument, .value) is f64 || t.string_of(argument, .bigint) != none
}

// updp_static_default_value ports getStaticDefaultValue for Object.is: the value of a static
// default value.
fn updp_static_default_value(t &estree.EsTree, node int) ?JsValue {
	if t.typ(node) == .unary_expression {
		return un_primitive_literal_value(t, node)
	}
	if text := un_static_string_value(t, node) {
		return JsValue{
			kind: .string_
			text: text
		}
	}
	return un_literal_js_value(t, node)
}

// updp_object_is ports Object.is of two static default values (none: `undefined`).
fn updp_object_is(a ?JsValue, b ?JsValue) bool {
	x := a or { return b == none }
	y := b or { return false }
	if x.kind != y.kind {
		return false
	}
	return match x.kind {
		.number_ { un_js_object_is(x.number, y.number) }
		.string_, .bigint_ { x.text == y.text }
		.boolean_ { x.boolean == y.boolean }
		.null_ { true }
		else { false }
	}
}

// updp_default_value ports getDefaultValue: the fallback of `a = a || b`, `a ||= b` or `a ??= b`.
fn updp_default_value(t &estree.EsTree, assignment int) int {
	left := t.node(assignment, .left) or { return -1 }
	right := t.node(assignment, .right) or { return -1 }
	operator := t.string_of(assignment, .operator) or { return -1 }
	if t.typ(left) != .identifier {
		return -1
	}
	if operator == '=' && t.typ(right) == .logical_expression
		&& (t.string_of(right, .operator) or { '' }) in ['||', '??'] {
		right_left := t.node(right, .left) or { return -1 }
		if t.typ(right_left) == .identifier {
			// Parameter is reassigned to a different identifier
			if t.string_of(left, .name) or { '' } != t.string_of(right_left, .name) or { '' } {
				return -1
			}
			return t.node(right, .right) or { -1 }
		}
	}
	if operator in ['||=', '??='] {
		return right
	}
	return -1
}

// updp_contains_call_expression ports containsCallExpression.
fn updp_contains_call_expression(t &estree.EsTree, node int) bool {
	if t.typ(node) in [.call_expression, .new_expression, .import_expression,
		.tagged_template_expression] {
		return true
	}
	return t.children(node).any(updp_contains_call_expression(t, it))
}

// updp_has_side_effects ports hasSideEffects: a statement before the node calls something.
fn updp_has_side_effects(t &estree.EsTree, function int, node int) bool {
	body := t.node(function, .body) or { return false }
	for element in t.list(body, .body) or { []int{} } {
		if element == node {
			break
		}
		// Function call before default-assignment
		if updp_contains_call_expression(t, element) {
			return true
		}
	}
	return false
}

// updp_needs_parentheses ports needsParentheses: the only parameter of an arrow function without
// parentheses.
fn (c &Checker) updp_needs_parentheses(t &estree.EsTree, tokens &SourceTokens, function int) bool {
	params := t.list(function, .params) or { return false }
	if t.typ(function) != .arrow_function_expression || params.len > 1 || params.len == 0 {
		return false
	}
	before := tokens.before(t.nodes[params[0]].start, false) or { return true }
	return c.token_text(before) != '('
}

// updp_has_use_strict: a `'use strict'` directive in the body.
fn updp_has_use_strict(t &estree.EsTree, body int) bool {
	if t.typ(body) != .block_statement {
		return false
	}
	return (t.list(body, .body) or { []int{} }).any((t.string_of(it, .directive) or { '' }) == 'use strict')
}

// updp_is_setter: the function is the value of a `set` accessor.
fn updp_is_setter(t &estree.EsTree, function int) bool {
	parent := t.nodes[function].parent
	return parent >= 0 && (t.string_of(parent, .kind) or { '' }) == 'set'
}

// updp_fix_default_expression ports fixDefaultExpression: removes the statement.
fn (c &Checker) updp_fix_default_expression(t &estree.EsTree, tokens &SourceTokens, node int) Fix {
	start := t.nodes[node].start
	end := t.nodes[node].end
	if c.unb_needs_semicolon(t, tokens, tokens.before(start, false), none) {
		return fix_replace_range(start, end, ';')
	}
	line_start := c.unim_line_start(start)
	line_end := c.unim_line_end(start)
	if js_trim(c.src[line_start..line_end]) == c.src[start..end] {
		return fix_remove_range(line_start, line_end + c.unim_terminator_length(line_end))
	}
	if end < c.src.len && c.src[end] == ` ` {
		return fix_remove_range(start, end + 1)
	}
	return fix_remove_range(start, end)
}

// updp_es_name is the ESTree Identifier of a definition name, -1 if none.
fn (mut c Checker) updp_es_name(t &estree.EsTree, name C.TSNode) int {
	mut node := c.es_index_of(t, name) or { return -1 }
	// The key of a shorthand property of an object pattern shares its node with the binding: its
	// value, or the left side of the default of its value.
	parent := t.nodes[node].parent
	if parent >= 0 && t.typ(parent) == .property && (t.node(parent, .key) or { -1 }) == node {
		value := t.node(parent, .value) or { return -1 }
		node = if t.typ(value) == .assignment_pattern { t.node(value, .left) or { -1 } } else { value }
	}
	return if node >= 0 && t.typ(node) == .identifier { node } else { -1 }
}

// updp_is_earlier_binding ports isEarlierBinding: the fallback is a binding of the same
// declaration as the variable, declared before it and never reassigned.
fn (mut c Checker) updp_is_earlier_binding(ctx &UnCtx, fallback int, v int) bool {
	t := ctx.t
	tree := c.scope_tree(ctx.root)
	if t.typ(fallback) != .identifier || tree.variables[v].defs.len != 1 {
		return false
	}
	fallback_variable := c.un_find_variable(ctx, fallback)
	if fallback_variable < 0 || tree.variables[fallback_variable].defs.len != 1 {
		return false
	}
	definition := tree.variables[fallback_variable].defs[0]
	variable_definition := tree.variables[v].defs[0]
	return definition.kind == variable_definition.kind
		&& node_key(definition.node) == node_key(variable_definition.node)
		&& node_start(definition.name) < node_start(variable_definition.name)
		&& tree.variables[fallback_variable].references.all(!tree.references[it].write
		|| tree.references[it].init)
}

// updp_default_parameter_problem ports getDefaultParameterProblem: `foo = foo || 123;` in the
// body of the function whose last parameter is `foo`.
fn (mut c Checker) updp_default_parameter_problem(mut ctx UnCtx, node int) ?Finding {
	t := ctx.t
	tokens := ctx.tokens
	expression := t.node(node, .expression)?
	default_value := updp_default_value(t, expression)
	body := t.nodes[node].parent
	if default_value < 0 || body < 0 || t.typ(body) != .block_statement {
		return none
	}
	current_function := t.nodes[body].parent
	if current_function < 0 || t.typ(current_function) !in [.function_declaration,
		.function_expression, .arrow_function_expression]
		|| (t.node(current_function, .body) or { -1 }) != body || updp_has_use_strict(t, body) {
		return none
	}
	left := t.node(expression, .left)?
	parameter_name := t.string_of(left, .name)?
	ts := t.ts_node(node)?
	tree := c.scope_tree(ctx.root)
	v := tree.find_variable(tree.get_scope(ts), parameter_name, -1)
	if v < 0 {
		return none
	}
	references := tree.variables[v].references
	params := t.list(current_function, .params)?
	if params.len == 0 {
		return none
	}
	parameter := params.last()
	if t.typ(parameter) != .identifier || (t.string_of(parameter, .name) or { '' }) != parameter_name
		|| tree.variables[v].defs.len != 1
		|| node_start(tree.variables[v].defs[0].name) != t.nodes[parameter].start
		|| (!updp_is_static_default_value(t, default_value)
		&& !c.updp_is_earlier_binding(ctx, default_value, v)) || updp_is_setter(t, current_function)
		|| !c.updp_is_default_value_compatible(mut ctx, tree.variables[v].defs[0].name, parameter,
		default_value, expression) {
		return none
	}
	// Parameter is referenced prior to default-assignment
	if updp_has_side_effects(t, current_function, node) || references.len == 0
		|| node_start(tree.references[references[0]].identifier) != t.nodes[left].start {
		return none
	}
	mut parameter_text := parameter_name
	if annotation := t.node(parameter, .type_annotation) {
		parameter_text += c.src[t.nodes[annotation].start..t.nodes[annotation].end]
	}
	default_value_text := c.src[t.nodes[default_value].start..t.nodes[default_value].end]
	replacement := if c.updp_needs_parentheses(t, tokens, current_function) {
		'(${parameter_text} = ${default_value_text})'
	} else {
		'${parameter_text} = ${default_value_text}'
	}
	mut suggestions := []Suggestion{}
	if tokens.comments_inside(t.nodes[node].start, t.nodes[node].end).len == 0
		&& tokens.comments_inside(t.nodes[parameter].start, t.nodes[parameter].end).len == 0 {
		fixes := [
			fix_replace_range(t.nodes[parameter].start, t.nodes[parameter].end, replacement),
			c.updp_fix_default_expression(t, tokens, node),
		]
		if has_fix, fix := c.merge_fixes(fixes) {
			if has_fix {
				suggestions << Suggestion{
					message_id: 'preferDefaultParametersSuggest'
					fix:        fix
				}
			}
		}
	}
	return Finding{
		stmt:        c.es_tree_position(t, node)
		message_id:  'preferDefaultParameters'
		suggestions: suggestions
	}
}

// updp_default_read_problem ports getDefaultReadProblem: every read of the variable (a parameter
// or a destructured binding) is `variable ?? value` (or `||`) with the same value.
fn (mut c Checker) updp_default_read_problem(mut ctx UnCtx, v int, node int) ?Finding {
	t := ctx.t
	tokens := ctx.tokens
	tree := c.scope_tree(ctx.root)
	definition := tree.variables[v].defs[0]
	if definition.kind == .variable {
		declaration := t.nodes[node].parent
		if declaration < 0 || (t.string_of(declaration, .kind) or { '' }) == 'var' {
			return none
		}
		export := t.nodes[declaration].parent
		if export >= 0 && t.typ(export) == .export_named_declaration {
			return none
		}
	}
	binding := c.updp_es_name(t, definition.name)
	if binding < 0 {
		return none
	}
	binding_parent := t.nodes[binding].parent
	if binding_parent < 0 {
		return none
	}
	is_destructuring := t.typ(binding_parent) == .array_pattern
		|| (t.typ(binding_parent) == .property && t.nodes[binding_parent].parent >= 0
		&& t.typ(t.nodes[binding_parent].parent) == .object_pattern)
	if !is_destructuring {
		if definition.kind != .parameter {
			return none
		}
		params := t.list(node, .params) or { return none }
		if params.len == 0 || params.last() != binding {
			return none
		}
		if body := t.node(node, .body) {
			if updp_has_use_strict(t, body) {
				return none
			}
		}
		if updp_is_setter(t, node) {
			return none
		}
	}
	references := tree.variables[v].references.filter(!tree.references[it].init)
	if references.len == 0 || references.any(!tree.references[it].is_read_only()) {
		return none
	}
	// Keep local declarations and parameter names so defaults cannot capture outer variables.
	// The binding must only be referenced through fallback expressions.
	mut identifiers := []int{}
	mut expressions := []int{}
	for r in references {
		identifier := c.es_index_of(t, tree.references[r].identifier) or { return none }
		identifiers << identifier
		expressions << t.nodes[identifier].parent
	}
	first_expression := expressions[0]
	if first_expression < 0 {
		return none
	}
	first_right := t.node(first_expression, .right) or { -1 }
	first_operator := t.string_of(first_expression, .operator) or { '' }
	for index, expression in expressions {
		if expression < 0 || t.typ(expression) != .logical_expression {
			return none
		}
		operator := t.string_of(expression, .operator) or { '' }
		if operator !in ['??', '||'] || (t.node(expression, .left) or { -1 }) != identifiers[index] {
			return none
		}
		right := t.node(expression, .right) or { return none }
		if (!updp_is_static_default_value(t, right) && !c.updp_is_earlier_binding(ctx, right, v))
			|| t.prop(right, .regex) != none || operator != first_operator
			|| (t.typ(right) == .identifier) != (t.typ(first_right) == .identifier) {
			return none
		}
		if t.typ(right) == .identifier {
			if t.string_of(right, .name) or { '' } != t.string_of(first_right, .name) or { '' } {
				return none
			}
		} else if !updp_object_is(updp_static_default_value(t, right), updp_static_default_value(t,
			first_right)) {
			return none
		}
		if !c.updp_is_default_value_compatible(mut ctx, definition.name, binding, right, expression) {
			return none
		}
	}
	mut suggestions := []Suggestion{}
	if tokens.comments_inside(t.nodes[binding].start, t.nodes[binding].end).len == 0
		&& !expressions.any(tokens.comments_inside(t.nodes[it].start, t.nodes[it].end).len > 0) {
		mut type_annotation_text := ''
		if annotation := t.node(binding, .type_annotation) {
			type_annotation_text = c.src[t.nodes[annotation].start..t.nodes[annotation].end]
		}
		name := t.string_of(binding, .name) or { '' }
		mut replacement := '${name}${type_annotation_text} = ${c.src[t.nodes[first_right].start..t.nodes[first_right].end]}'
		if !is_destructuring && c.updp_needs_parentheses(t, tokens, node) {
			replacement = '(${replacement})'
		}
		mut fixes := [fix_replace_range(t.nodes[binding].start, t.nodes[binding].end, replacement)]
		for expression in expressions {
			left := t.node(expression, .left) or { continue }
			fixes << fix_replace_range(t.nodes[expression].start, t.nodes[expression].end,
				c.src[t.nodes[left].start..t.nodes[left].end])
		}
		if has_fix, fix := c.merge_fixes(fixes) {
			if has_fix {
				suggestions << Suggestion{
					message_id: 'moveDefaultToDeclaration'
					fix:        fix
				}
			}
		}
	}
	return Finding{
		stmt:        c.es_tree_position(t, binding)
		message_id:  if is_destructuring {
			'preferDestructuringDefaultOverFallback'
		} else {
			'preferDefaultParameterOverFallback'
		}
		suggestions: suggestions
	}
}

// UpdpFalsy is one of the falsy literal types of isDefaultValueCompatible: `false`, `0`, `''` and
// `0n` (checker.getFalseType(), getNumberLiteralType(0), getStringLiteralType('') and
// getBigIntLiteralType(0n), which tsgo's API does not give).
enum UpdpFalsy {
	false_
	zero
	empty_string
	zero_bigint
}

// updp_number_value is the value of a number literal type.
fn updp_number_value(typ TypeResponse) ?f64 {
	value := typ.value
	return match value {
		f64 { value }
		i64 { f64(value) }
		int { f64(value) }
		else { none }
	}
}

// updp_is_falsy_literal: the type is the literal type of the falsy value (or an enum literal with
// its value).
fn updp_is_falsy_literal(typ TypeResponse, falsy UpdpFalsy) bool {
	return match falsy {
		.false_ {
			is_false_literal(typ)
		}
		.zero {
			typ.flags & type_flag_number_literal != 0 && (updp_number_value(typ) or { 1 }) == 0
		}
		.empty_string {
			value := typ.value
			typ.flags & type_flag_string_literal != 0 && value is string && value == ''
		}
		.zero_bigint {
			value := typ.value
			typ.flags & type_flag_bigint_literal != 0 && value is string
				&& value.trim_right('n') in ['0', '-0']
		}
	}
}

const updp_type_flag_string = u32(32)
const updp_type_flag_bigint = u32(128)
const updp_type_flag_boolean = u32(256)
const updp_type_flag_enum_literal = u32(32768)
const updp_type_flag_template_literal = u32(4194304)
const updp_type_flag_string_mapping = u32(8388608)

// updp_falsy_assignable_to ports checker.isTypeAssignableTo(falsyType, target) for a target that
// is not a union, without the falsy type: a literal target takes it if it is that literal, a
// primitive one if it is of its kind, an object type if the primitive type of the value is
// assignable to it (both go through the same apparent type); type variables take no literal.
fn (mut c Checker) updp_falsy_assignable_to(falsy UpdpFalsy, target TypeResponse) !bool {
	flags := target.flags
	if flags & (type_flag_any | type_flag_unknown) != 0 {
		return true
	}
	if flags & type_flag_union != 0 {
		for member in c.members_of(target)! {
			if c.updp_falsy_assignable_to(falsy, member)! {
				return true
			}
		}
		return false
	}
	if flags & type_flag_intersection != 0 {
		for member in c.members_of(target)! {
			if !c.updp_falsy_assignable_to(falsy, member)! {
				return false
			}
		}
		return true
	}
	if flags & (type_flag_boolean_literal | type_flag_number_literal | type_flag_bigint_literal) != 0 {
		return updp_is_falsy_literal(target, falsy)
	}
	if flags & type_flag_string_literal != 0 {
		return flags & updp_type_flag_enum_literal == 0 && updp_is_falsy_literal(target, falsy)
	}
	match falsy {
		.false_ {
			if flags & updp_type_flag_boolean != 0 {
				return true
			}
		}
		.zero {
			if flags & type_flag_number != 0 {
				return true
			}
		}
		.empty_string {
			if flags & updp_type_flag_string != 0 {
				return true
			}
			if flags & (updp_type_flag_template_literal | updp_type_flag_string_mapping) != 0 {
				return c.assignable(c.intrinsic('getStringType')!.id, target.id)!
			}
		}
		.zero_bigint {
			if flags & updp_type_flag_bigint != 0 {
				return true
			}
		}
	}
	if flags & (type_flag_object | type_flag_intersection) == 0 {
		return false
	}
	primitive := match falsy {
		.false_ { 'getBooleanType' }
		.zero { 'getNumberType' }
		.empty_string { 'getStringType' }
		.zero_bigint { 'getBigIntType' }
	}
	return c.assignable(c.intrinsic(primitive)!.id, target.id)!
}

// updp_assignable_to_falsy ports checker.isTypeAssignableTo(source, falsyType): only that literal
// (or an enum literal with its value) and never are, through unions.
fn (mut c Checker) updp_assignable_to_falsy(source TypeResponse, falsy UpdpFalsy) !bool {
	if source.flags & (type_flag_never | type_flag_any) != 0 {
		return true
	}
	if source.flags & type_flag_union != 0 {
		for member in c.members_of(source)! {
			if !c.updp_assignable_to_falsy(member, falsy)! {
				return false
			}
		}
		return true
	}
	if source.flags & type_flag_intersection != 0 {
		for member in c.members_of(source)! {
			if c.updp_assignable_to_falsy(member, falsy)! {
				return true
			}
		}
		return false
	}
	return updp_is_falsy_literal(source, falsy)
}

// updp_types resolves the types of the nodes and gives them, none if tsgo has no type for one.
fn (mut c Checker) updp_types(ctx &UnCtx, spans []Span) ?[]TypeResponse {
	mut stats := Stats{}
	c.resolve_spans(spans, ctx.abs_path, mut stats) or { return none }
	mut out := []TypeResponse{}
	for s in spans {
		out << c.span_type(s)?
	}
	return out
}

// updp_is_default_value_compatible ports isDefaultValueCompatible: without a program, or when
// TypeScript cannot tell (getTypeAtLocation or the checker throws), the default is compatible.
fn (mut c Checker) updp_is_default_value_compatible(mut ctx UnCtx, binding_name C.TSNode, binding int, default_value int, expression int) bool {
	if !c.scope_setup.type_information {
		return true
	}
	return c.updp_is_default_value_compatible_with_types(mut ctx, binding_name, binding,
		default_value, expression) or { true }
}

fn (mut c Checker) updp_is_default_value_compatible_with_types(mut ctx UnCtx, binding_name C.TSNode, binding int, default_value int, expression int) !bool {
	t := ctx.t
	tree := c.scope_tree(ctx.root)
	// `binding.typeAnnotation?.typeAnnotation ?? binding`
	mut type_span := node_span(binding_name)
	if annotation := t.node(binding, .type_annotation) {
		if type_node := t.node(annotation, .type_annotation) {
			type_span = c.type_node_span(t.ts_node(type_node) or { return error('no node') })
		}
	}
	mut default_value_declaration := t.ts_node(default_value) or { return error('no node') }
	if t.typ(default_value) == .identifier {
		v := c.un_find_variable(ctx, default_value)
		if v < 0 || tree.variables[v].defs.len == 0 {
			return error('no variable')
		}
		default_value_declaration = tree.variables[v].defs[0].name
	}
	expression_ts := t.ts_node(expression) or { return error('no node') }
	default_value_ts := t.ts_node(default_value) or { return error('no node') }
	types := c.updp_types(ctx, [type_span, node_span(default_value_declaration),
		node_span(binding_name), node_span(expression_ts), node_span(default_value_ts)]) or {
		return error('no type')
	}
	typ, default_value_type, binding_type := types[0], types[1], types[2]
	expression_type, default_value_location_type := types[3], types[4]
	// Defaults can narrow inferred signatures when a binding or fallback has type any.
	if binding_type.intrinsic_name == 'any' || default_value_type.intrinsic_name == 'any' {
		return false
	}
	binding_types := c.constituents(binding_type)!
	binding_constraint := c.constrained(binding_type)!
	binding_constraint_types := c.constituents(binding_constraint)!
	operator := if (t.string_of(expression, .operator) or { '' }) == '=' {
		t.string_of(t.node(expression, .right) or { -1 }, .operator) or { '' }
	} else {
		t.string_of(expression, .operator) or { '' }
	}
	// Defaults retain falsy values that logical OR can replace with a different value.
	if operator in ['||', '||='] {
		number_type := c.intrinsic('getNumberType')!
		mut members := binding_types.clone()
		members << binding_constraint_types
		for member in members {
			// NaN has no literal type, so check any type that admits arbitrary numbers.
			if c.assignable(number_type.id, member.id)!
				|| member.intrinsic_name in ['string', 'bigint'] {
				return false
			}
			for falsy in [UpdpFalsy.false_, .zero, .empty_string, .zero_bigint] {
				if c.updp_falsy_assignable_to(falsy, member)!
					&& !c.updp_assignable_to_falsy(default_value_type, falsy)! {
					return false
				}
			}
		}
	}
	// A nullable fallback can keep null in the result type even though it replaces the binding's
	// null.
	if default_value_type.intrinsic_name != 'null'
		&& (binding_types.any(it.intrinsic_name in ['null', 'unknown'])
		|| binding_constraint_types.any(it.intrinsic_name == 'null')) {
		return false
	}
	// A declaration default cannot rely on type narrowing at a fallback read.
	if !c.assignable(default_value_type.id, typ.id)!
		|| !c.assignable(default_value_type.id, default_value_location_type.id)!
		|| !c.assignable(default_value_type.id, expression_type.id)! {
		return false
	}
	// Defaults replace undefined, but retain other values narrowed away by the fallback.
	for member in binding_types {
		if member.intrinsic_name != 'undefined' && !c.assignable(member.id, expression_type.id)! {
			return false
		}
	}
	return true
}
