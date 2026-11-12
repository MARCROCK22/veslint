module rules

import json2
import time
import tsgo { AstTree, SymbolResponse, TypeResponse, handle_index, handle_kind, handle_path }
import treesitter { children, has_child_kind, named_children, node_end, node_field, node_kind, node_parent, node_start, nodes_of_kinds, position_of }

// Port of the `no-unnecessary-type-assertion` rule of typescript-eslint 8.62.0, with its options
// and its fixes.
//
// In ts-api-utils' isPropertyReadonlyInType (hasSameProperties), isReadonlyPropertyFromMappedType
// reads the modifiersType of a mapped type without a readonly token, which the tsgo API does not
// expose: see nuta_readonly_from_mapped_type for what veslint does instead, and the one case
// where it can still differ.
//
// The CallExpression branch of isInConstContext reads the internal `links` of transient symbols:
// a symbol has them when the checker created it (SymbolFlags.Transient), and their checkFlags and
// type are the symbol's checkFlags and getTypeOfSymbol.

const nuta_messages = {
	'contextuallyUnnecessary': 'This assertion is unnecessary since the receiver accepts the original type of the expression.'
	'unnecessaryAssertion':    'This assertion is unnecessary since it does not change the type of the expression.'
}

// SyntaxKind of TypeScript 7.1.0-beta.
const nuta_kind_minus_token = u32(40)
const nuta_kind_declare_keyword = u32(137)
const nuta_kind_readonly_keyword = u32(148)
const nuta_kind_type_reference = u32(185)
const nuta_kind_array_literal = u32(211)
const nuta_kind_object_literal = u32(212)
const nuta_kind_type_assertion = u32(218)
const nuta_kind_parenthesized = u32(219)
const nuta_kind_prefix_unary = u32(226)
const nuta_kind_template_expression = u32(230)
const nuta_kind_as_expression = u32(236)
const nuta_kind_variable_statement = u32(245)
const nuta_kind_variable_declaration = u32(262)
const nuta_kind_variable_declaration_list = u32(263)
const nuta_kind_shorthand_property_assignment = u32(305)
const nuta_kind_numeric_literal = u32(8)
const nuta_kind_call_expression = u32(215)

// SymbolFlags, ObjectFlags and NodeFlags of TypeScript 7.1.0-beta.
const nuta_symbol_value_module = u32(512)
const nuta_symbol_get_accessor = u32(32768)
const nuta_symbol_accessor = u32(98304)
const nuta_symbol_transient = u32(33554432)
const nuta_object_flag_mapped = u32(32)
const nuta_node_flag_const = u32(2)
// CheckFlags.Readonly (1 << 3) of TypeScript 7.1.0-beta (dist/enums/checkFlags.enum.js; 7.0.2 had
// no CheckFlags enum), also checked against tsgo by the `constant<const T>` lines of the readonly
// fixture.
const nuta_check_flag_readonly = u32(8)

// TypeFlags of isNullableType and of containsTypeVariable.
const nuta_nullable_flags = type_flag_any | type_flag_unknown | type_flag_null | type_flag_undefined | type_flag_void
const nuta_type_variable_or_index = type_flag_type_variable | u32(2097152)
const nuta_flag_non_primitive = u32(131072)
const nuta_flag_string = u32(32)

struct NutaOptions {
	check_literal_const_assertions bool
	types_to_ignore                []string
}

fn nuta_options(options []json2.Any) !NutaOptions {
	o := option_object(no_unnecessary_type_assertion, options, [
		'checkLiteralConstAssertions',
		'typesToIgnore',
	])!
	mut ignore := []string{}
	if value := o.values['typesToIgnore'] {
		if value !is []json2.Any {
			return error('option `typesToIgnore` of `${no_unnecessary_type_assertion}` must be a list of type names')
		}
		for item in value.as_array() {
			if item !is string {
				return error('option `typesToIgnore` of `${no_unnecessary_type_assertion}` must be a list of type names')
			}
			ignore << item as string
		}
	}
	return NutaOptions{
		check_literal_const_assertions: o.bool_value('checkLiteralConstAssertions')!
		types_to_ignore:                ignore
	}
}

// NutaAssertion is a TSAsExpression or TSTypeAssertion.
struct NutaAssertion {
	node       C.TSNode
	expression C.TSNode // without parentheses
	type_node  C.TSNode // the type annotation, without parentheses (the `const` token of a const assertion)
	is_const   bool     // isConstAssertion
	type_text  string   // sourceCode.getText(node.typeAnnotation)
}

// NutaCache keeps the results of the type walks of a file.
struct NutaCache {
mut:
	alias_args map[int][]TypeResponse
	contains   map[string]bool
	void_type  TypeResponse
}

fn (mut c Checker) lint_no_unnecessary_type_assertion(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := nuta_options(c.rule_options(no_unnecessary_type_assertion))!
	mut assertions := []NutaAssertion{}
	mut non_nulls := []C.TSNode{}
	mut spans := []Span{}
	for node in c.nodes_of_kinds(root, ['as_expression', 'type_assertion', 'non_null_expression'],
		[]string{}) {
		if node_kind(node) == 'non_null_expression' {
			expression := unwrap_parens(first_named(node) or { continue })
			non_nulls << node
			spans << node_span(expression)
			spans << c.util_contextual_spans(node)
			continue
		}
		a := c.nuta_assertion(node) or { continue }
		c.nuta_assertion_spans(a, mut spans)
		assertions << a
	}
	// The `var` declarators, to find the one of a declaration (isPossiblyUsedBeforeAssigned).
	mut declarators := []C.TSNode{}
	for declaration in c.nodes_of_kinds(root, ['variable_declaration'], []string{}) {
		for declarator in named_children(declaration) {
			if node_kind(declarator) == 'variable_declarator' {
				declarators << declarator
				spans << node_span(declarator)
			}
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut cache := NutaCache{}
	mut findings := []Finding{}
	if non_nulls.len > 0 {
		c.scope_tree(root)
	}
	for node in non_nulls {
		c.nuta_check_non_null(node, declarators, mut cache, mut findings)!
	}
	for a in assertions {
		c.nuta_check_assertion(a, o, mut cache, mut findings)!
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += non_nulls.len + assertions.len
	return findings
}

// nuta_assertion reads `x as T` or `<T>x`.
fn (c &Checker) nuta_assertion(node C.TSNode) ?NutaAssertion {
	if node_kind(node) == 'as_expression' {
		parts := named_children(node)
		if parts.len == 0 {
			return none
		}
		expression := unwrap_parens(parts[0])
		if parts.len < 2 {
			// `x as const`: the `const` is an anonymous token.
			for child in children(node) {
				if node_kind(child) == 'const' {
					return NutaAssertion{
						node:       node
						expression: expression
						type_node:  child
						is_const:   true
						type_text:  'const'
					}
				}
			}
			return none
		}
		type_node := unwrap_type_parens(parts[1])
		return NutaAssertion{
			node:       node
			expression: expression
			type_node:  type_node
			type_text:  c.text(type_node)
		}
	}
	parts := named_children(node)
	if parts.len < 2 || node_kind(parts[0]) != 'type_arguments' {
		return none
	}
	expression := unwrap_parens(parts[1])
	if has_child_kind(parts[0], 'const') {
		return NutaAssertion{
			node:       node
			expression: expression
			type_node:  parts[0]
			is_const:   true
			type_text:  'const'
		}
	}
	type_node := unwrap_type_parens(first_named(parts[0])?)
	return NutaAssertion{
		node:       node
		expression: expression
		type_node:  type_node
		type_text:  c.text(type_node)
	}
}

// nuta_assertion_spans requests the nodes the checks of an assertion may need.
fn (c &Checker) nuta_assertion_spans(a NutaAssertion, mut spans []Span) {
	spans << node_span(a.node)
	spans << node_span(a.expression)
	original := nuta_original_expression(a.node)
	spans << node_span(original)
	if node_kind(a.expression) == 'call_expression' {
		if callee := node_field(a.expression, 'function') {
			spans << node_span(unwrap_parens(callee))
		}
	}
	// Callees of the calls around it (isInGenericContext, isArgumentToOverloadedFunction).
	mut n := a.node
	for depth := 0; depth < max_expression_depth; depth++ {
		parent := node_parent(n) or { break }
		if callee := nuta_callee(parent) {
			spans << node_span(callee)
		}
		n = parent
	}
	// The object of a property (isPropertyInProblematicContext).
	if parent := estree_parent(a.node) {
		if node_kind(parent) == 'pair' {
			if object := node_parent(parent) {
				spans << node_span(object)
			}
		}
	}
}

// nuta_callee is the callee of a call (not a tagged template) or of a `new`, without parentheses.
fn nuta_callee(n C.TSNode) ?C.TSNode {
	match node_kind(n) {
		'call_expression' {
			call_arguments(n)?
			return unwrap_parens(node_field(n, 'function')?)
		}
		'new_expression' {
			return unwrap_parens(node_field(n, 'constructor')?)
		}
		else {
			return none
		}
	}
}

// nuta_original_expression ports getOriginalExpression: the expression under all the nested
// assertions.
fn nuta_original_expression(node C.TSNode) C.TSNode {
	mut current := nuta_expression_of(node) or { return node }
	for depth := 0; depth < max_expression_depth; depth++ {
		if node_kind(current) !in ['as_expression', 'type_assertion'] {
			break
		}
		current = nuta_expression_of(current) or { break }
	}
	return current
}

// nuta_expression_of is the expression of an assertion, without parentheses.
fn nuta_expression_of(node C.TSNode) ?C.TSNode {
	parts := named_children(node)
	if parts.len == 0 {
		return none
	}
	if node_kind(node) == 'type_assertion' {
		if parts.len < 2 {
			return none
		}
		return unwrap_parens(parts[1])
	}
	return unwrap_parens(parts[0])
}

// --- TSNonNullExpression

fn (mut c Checker) nuta_check_non_null(node C.TSNode, declarators []C.TSNode, mut cache NutaCache, mut findings []Finding) ! {
	expression := unwrap_parens(first_named(node) or { return })
	if parent := estree_parent(node) {
		if node_kind(parent) == 'assignment_expression' {
			left := node_field(parent, 'left') or { return }
			if node_key(unwrap_parens(left)) == node_key(node) {
				findings << c.with_fixes(Finding{
					stmt:       position_of(node)
					message_id: 'contextuallyUnnecessary'
				}, c.nuta_remove_exclamation(node))!
			}
			return
		}
	}
	actual := c.node_type(expression) or { return }
	constrained := c.constrained(actual)!
	constrained_nullable := c.type_flags(constrained)! & nuta_nullable_flags != 0
	actual_nullable := c.type_flags(actual)! & nuta_nullable_flags != 0
	if !constrained_nullable && !actual_nullable {
		if node_kind(expression) in ['identifier', 'undefined']
			&& c.nuta_possibly_used_before_assigned(expression, constrained, declarators, mut cache)! {
			return
		}
		findings << c.with_fixes(Finding{
			stmt:       position_of(node)
			message_id: 'unnecessaryAssertion'
		}, c.nuta_remove_exclamation(node))!
		return
	}
	if constrained.id != actual.id {
		return
	}
	contextual := c.util_contextual_type(node)!
	if contextual.is_null() {
		return
	}
	contextual_flags := c.type_flags(contextual)!
	flags := c.type_flags(constrained)!
	if flags & type_flag_unknown != 0 && contextual_flags & type_flag_unknown == 0 {
		return
	}
	// The parent must accept the same nullish types.
	for flag in [type_flag_undefined, type_flag_null, type_flag_void] {
		if flags & flag != 0 && contextual_flags & flag == 0 {
			return
		}
	}
	findings << c.with_fixes(Finding{
		stmt:       position_of(node)
		message_id: 'contextuallyUnnecessary'
	}, c.nuta_remove_exclamation(node))!
}

// nuta_remove_exclamation ports removeExclamationFix: the last `!` token of the node goes.
fn (mut c Checker) nuta_remove_exclamation(node C.TSNode) []Fix {
	tokens := c.node_tokens(node)
	for i := tokens.len - 1; i >= 0; i-- {
		if c.token_text(tokens[i]) == '!' {
			return [fix_remove_range(tokens[i].start, tokens[i].end)]
		}
	}
	return []Fix{}
}

// nuta_possibly_used_before_assigned ports isPossiblyUsedBeforeAssigned.
fn (mut c Checker) nuta_possibly_used_before_assigned(identifier C.TSNode, constrained TypeResponse, declarators []C.TSNode, mut cache NutaCache) !bool {
	handle := c.node_handles[node_key(identifier)] or { return true }
	symbols := c.client.symbols_at_locations(c.snapshot, c.project, [handle])!
	if symbols.len != 1 || symbols[0].is_null() || symbols[0].declarations.len == 0 {
		return true
	}
	declaration := symbols[0].declarations[0]
	if !c.strict_null_checks || handle_kind(declaration) != nuta_kind_variable_declaration {
		return false
	}
	tree := c.nuta_tree(handle_path(declaration), mut cache)!
	index := handle_index(declaration)
	list := tree.node_parent(index)
	if tree.node_kind(list) == nuta_kind_variable_declaration_list && tree.node_flags(list) == 0 {
		// A `var` of this file: used outside a scope its declarator is nested in.
		for declarator in declarators {
			if c.node_handles[node_key(declarator)] or { '' } == declaration {
				if c.nuta_scope_is_ancestor(identifier, declarator) {
					return true
				}
				break
			}
		}
	}
	if tree.node_child(index, 'initializer') == 0 && tree.node_child(index, 'exclamationToken') == 0 {
		type_node := tree.node_child(index, 'type')
		if type_node != 0 {
			types := c.client.types_at_locations(c.snapshot, c.project, [
				tree.node_handle(type_node),
			])!
			if types.len == 1 && types[0].id == constrained.id && !nuta_is_declare(tree, list) {
				return true
			}
		}
	}
	return false
}

// nuta_scope_is_ancestor: the scope of `identifier` is a strict ancestor of the scope of the
// declarator (ESLint scopes, getScope).
fn (c &Checker) nuta_scope_is_ancestor(identifier C.TSNode, declarator C.TSNode) bool {
	t := c.file_scopes
	if t == unsafe { nil } {
		return false
	}
	scope := t.get_scope(identifier)
	mut s := t.scopes[t.get_scope(declarator)].upper
	for s >= 0 {
		if s == scope {
			return true
		}
		s = t.scopes[s].upper
	}
	return false
}

// nuta_is_declare: the declaration list is in a `declare` variable statement.
fn nuta_is_declare(tree AstTree, list int) bool {
	if tree.node_kind(list) != nuta_kind_variable_declaration_list {
		return false
	}
	statement := tree.node_parent(list)
	if tree.node_kind(statement) != nuta_kind_variable_statement {
		return false
	}
	for child in tree.node_children(statement) {
		if tree.node_kind(child) == nuta_kind_declare_keyword {
			return true
		}
	}
	return false
}

fn (mut c Checker) nuta_tree(path string, mut cache NutaCache) !AstTree {
	return c.declaration_ast(path)!
}

// --- TSAsExpression and TSTypeAssertion

fn (mut c Checker) nuta_check_assertion(a NutaAssertion, o NutaOptions, mut cache NutaCache, mut findings []Finding) ! {
	if a.type_text in o.types_to_ignore {
		return
	}
	cast := c.node_type(a.node) or { return }
	cast_is_literal := nuta_is_type_literal(cast)
	if !o.check_literal_const_assertions && cast_is_literal && a.is_const {
		return
	}
	uncast := c.nuta_uncast_type(a, mut cache)!
	if uncast.is_null() {
		return
	}
	unchanged := c.nuta_type_unchanged(a, a.expression, uncast, cast, mut cache)!
	same_inferred := if cast_is_literal {
		c.nuta_implicitly_narrowed_literal(a)
	} else {
		!a.is_const
	}
	if unchanged && same_inferred {
		findings << c.with_fixes(Finding{
			stmt:       position_of(a.node)
			message_id: 'unnecessaryAssertion'
		}, c.nuta_assertion_fixes(a))!
		return
	}
	parent := estree_parent(a.node) or { return }
	cast_is_any := c.type_flags(cast)! & type_flag_any != 0 && !nuta_is_skip_parent(parent)
	mut contextual := TypeResponse{}
	if !c.nuta_skip_contextual(a, parent, cast_is_any, mut cache)! {
		contextual = c.contextual_type(a.node)!
	}
	if !contextual.is_null() {
		contextual_is_any := c.type_flags(contextual)! & type_flag_any != 0
		is_call_argument := nuta_argument_index(a.node) >= 0
		any_involved := if contextual_is_any {
			is_call_argument && !c.nuta_contains_any(cast, mut cache)!
		} else {
			!c.nuta_contains_any(contextual, mut cache)!
		}
		nullish_literal_to_union := cast.flags & type_flag_union != 0
			&& (node_kind(a.expression) in ['null', 'undefined']
				|| (node_kind(a.expression) == 'identifier' && c.text(a.expression) == 'undefined'))
		if !a.is_const && !c.nuta_contains_any(uncast, mut cache)! && any_involved
			&& !c.nuta_phantom_mismatch(a, uncast, contextual, mut cache)!
			&& (cast_is_any || !c.nuta_generics_mismatch(uncast, contextual)!)
			&& (contextual_is_any || c.nuta_assignable(uncast, contextual)!)
			&& !nullish_literal_to_union {
			findings << c.with_fixes(Finding{
				stmt:       position_of(a.node)
				message_id: 'contextuallyUnnecessary'
			}, c.nuta_assertion_fixes(a))!
			return
		}
	}
	// reportDoubleAssertionIfUnnecessary.
	message_id := c.nuta_double_assertion(a, contextual, mut cache)!
	if message_id != '' {
		findings << c.with_fixes(Finding{
			stmt:       position_of(a.node)
			message_id: message_id
		}, c.nuta_double_assertion_fixes(a))!
	}
}

// nuta_node_end is the end of a node in ESTree: the end of its last token.
fn (mut c Checker) nuta_node_end(node C.TSNode) int {
	token := c.last_token(node) or { return node_end(node) }
	return token.end
}

// nuta_is_arrow_body tells whether the assertion is the body of an arrow function.
fn nuta_is_arrow_body(node EsNode) bool {
	parent := node.parent() or { return false }
	return !parent.chain && node_kind(parent.node) == 'arrow_function'
		&& parent.has_child('body', node)
}

// nuta_assertion_fixes ports createAssertionFixer. `<T>x` loses from its `<` to its `>`, and gets
// parentheses if that leaves an object literal where `{` would open a block (the body of an arrow
// function or the start of an expression statement). `x as T` loses from the end of the token or
// comment before `as` to its own end.
fn (mut c Checker) nuta_assertion_fixes(a NutaAssertion) []Fix {
	node := es_child(a.node)
	end := c.nuta_node_end(a.node)
	if node_kind(a.node) == 'type_assertion' {
		// `<` … `>`: tree-sitter's type_arguments.
		brackets := first_named(a.node) or { return []Fix{} }
		mut needs_parens := false
		if node_kind(a.expression) == 'object' {
			mut in_statement := false
			if parent := node.parent() {
				in_statement = !parent.chain && node_kind(parent.node) == 'expression_statement'
			}
			needs_parens = (nuta_is_arrow_body(node) || in_statement) && !c.is_parenthesized(node)
				&& !c.is_parenthesized(es_child(a.expression))
		}
		mut fixes := []Fix{}
		if needs_parens {
			fixes << fix_insert_at(node_start(a.node), '(')
		}
		fixes << fix_remove_range(node_start(brackets), node_end(brackets))
		if needs_parens {
			fixes << fix_insert_at(end, ')')
		}
		return fixes
	}
	for child in children(a.node) {
		if node_kind(child) == 'as' {
			before := c.source_tokens(a.node).before(node_start(child), true) or { return []Fix{} }
			return [fix_remove_range(before.end, end)]
		}
	}
	return []Fix{}
}

// nuta_double_assertion_fixes ports the fixer of a double assertion: the original expression takes
// the place of the whole, in parentheses if it is an object literal that becomes the body of an
// arrow function.
fn (mut c Checker) nuta_double_assertion_fixes(a NutaAssertion) []Fix {
	original := nuta_original_expression(a.node)
	mut text := c.text(original)
	if node_kind(original) == 'object' && nuta_is_arrow_body(es_child(a.node)) {
		text = '(${text})'
	}
	return [fix_replace_range(node_start(a.node), c.nuta_node_end(a.node), text)]
}

// nuta_double_assertion ports isDoubleAssertionUnnecessary: the messageId, or '' when it is
// necessary.
fn (mut c Checker) nuta_double_assertion(a NutaAssertion, contextual TypeResponse, mut cache NutaCache) !string {
	inner := a.expression
	if node_kind(inner) !in ['as_expression', 'type_assertion'] {
		return ''
	}
	original := nuta_original_expression(a.node)
	original_type := c.node_type(original) or { return '' }
	cast := c.node_type(a.node) or { return '' }
	if c.nuta_type_unchanged(a, inner, original_type, cast, mut cache)!
		&& c.type_flags(cast)! & type_flag_any == 0 {
		return 'unnecessaryAssertion'
	}
	if !contextual.is_null() {
		intermediate := c.node_type(inner) or { return '' }
		if c.type_flags(intermediate)! & (type_flag_any | type_flag_unknown) != 0
			&& c.nuta_assignable(original_type, contextual)! {
			return 'contextuallyUnnecessary'
		}
	}
	return ''
}

// nuta_uncast_type ports getUncastType: the return type of an IIFE (void when an unannotated
// function returns undefined), or the type of the expression.
fn (mut c Checker) nuta_uncast_type(a NutaAssertion, mut cache NutaCache) !TypeResponse {
	if node_kind(a.expression) == 'call_expression' {
		if callee := nuta_callee(a.expression) {
			if node_kind(callee) in ['arrow_function', 'function_expression', 'generator_function'] {
				if function_type := c.node_type(callee) {
					signatures := c.signatures_of(function_type, signature_kind_call)!
					if signatures.len > 0 {
						return_type := c.return_type(signatures[0].id)!
						if _ := node_field(callee, 'return_type') {
							return return_type
						}
						if c.type_flags(return_type)! & type_flag_undefined != 0 {
							if cache.void_type.is_null() {
								cache.void_type = c.client.void_type(c.snapshot, c.project)!
							}
							return cache.void_type
						}
						return return_type
					}
				}
			}
		}
	}
	return c.node_type(a.expression) or { TypeResponse{} }
}

// nuta_is_type_literal ports isTypeLiteral: a string, number or BigInt literal, or a boolean
// literal (own flags).
fn nuta_is_type_literal(t TypeResponse) bool {
	return t.flags & (type_flag_literal_value | type_flag_boolean_literal) != 0
}

// nuta_is_skip_parent: SKIP_PARENT_TYPES (TSAsExpression, TSTypeAssertion, SpreadElement,
// TSSatisfiesExpression).
fn nuta_is_skip_parent(parent C.TSNode) bool {
	return node_kind(parent) in ['as_expression', 'type_assertion', 'spread_element',
		'satisfies_expression']
}

// nuta_implicitly_narrowed_literal ports isImplicitlyNarrowedLiteralDeclaration.
fn (c &Checker) nuta_implicitly_narrowed_literal(a NutaAssertion) bool {
	if nuta_is_template_with_expressions(a.expression) {
		return false
	}
	parent := estree_parent(a.node) or { return false }
	if node_kind(parent) == 'variable_declarator' {
		if declaration := node_parent(parent) {
			if node_kind(declaration) == 'lexical_declaration' {
				kind := node_field(declaration, 'kind') or { return false }
				return node_kind(kind) == 'const'
			}
		}
		return false
	}
	if node_kind(parent) == 'public_field_definition' {
		return has_child_kind(parent, 'readonly')
	}
	return false
}

fn nuta_is_template_with_expressions(n C.TSNode) bool {
	return node_kind(n) == 'template_string' && has_child_kind(n, 'template_substitution')
}

// nuta_is_conceptually_literal: CONCEPTUALLY_LITERAL_TYPES.
fn nuta_is_conceptually_literal(n C.TSNode) bool {
	return node_kind(n) in ['string', 'number', 'true', 'false', 'null', 'regex', 'array', 'object',
		'template_string', 'class', 'function_expression', 'generator_function', 'arrow_function',
		'jsx_element', 'jsx_self_closing_element']
}

// nuta_type_unchanged ports isTypeUnchanged.
fn (mut c Checker) nuta_type_unchanged(a NutaAssertion, expression C.TSNode, uncast TypeResponse, cast TypeResponse, mut cache NutaCache) !bool {
	if uncast.id == cast.id {
		return true
	}
	if node_kind(a.type_node) == 'intersection_type' && c.nuta_contains_type_variable(cast, mut cache)! {
		return false
	}
	uncast_flags := c.type_flags(uncast)!
	cast_flags := c.type_flags(cast)!
	if uncast_flags & type_flag_undefined != 0 && cast_flags & type_flag_undefined != 0
		&& c.exact_optional_property_types {
		return c.nuta_parts_equivalent_ignoring_undefined(uncast, cast)!
	}
	if (uncast_flags & nuta_flag_non_primitive != 0 && cast_flags & nuta_flag_non_primitive == 0)
		|| (c.nuta_has_index_signature(uncast)! && !c.nuta_has_index_signature(cast)!)
		|| c.nuta_contains_any(uncast, mut cache)! || c.nuta_contains_any(cast, mut cache)!
		|| (c.nuta_contains_type_variable(cast, mut cache)!
			&& !c.nuta_contains_type_variable(uncast, mut cache)!) {
		return false
	}
	if nuta_is_conceptually_literal(expression) {
		if node_kind(expression) != 'object' || named_children(expression).len == 0 {
			return false
		}
		for prop in c.properties(cast)! {
			if nuta_is_type_literal(c.symbol_type(prop.id)!) {
				return false
			}
		}
	}
	if cast.flags & type_flag_intersection != 0 && uncast.flags & type_flag_intersection == 0 {
		parts := c.members_of(cast)!
		if uncast.flags & type_flag_type_parameter != 0 && parts.len == 2
			&& parts.any(it.id == uncast.id) {
			other := parts.filter(it.id != uncast.id)
			if other.len > 0 && c.nuta_is_empty_object_type(other[0])!
				&& !c.nuta_contains_type_variable(other[0], mut cache)! {
				constraint := c.base_constraint(uncast)!
				if !constraint.is_null() && c.type_flags(constraint)! & nuta_nullable_flags == 0 {
					return true
				}
			}
		}
		return false
	}
	if !c.nuta_same_properties(uncast, cast, mut cache)!
		|| !c.nuta_same_type_arguments(uncast, cast, mut cache)! {
		return false
	}
	return c.nuta_assignable(uncast, cast)! && c.nuta_assignable(cast, uncast)!
}

fn (mut c Checker) nuta_assignable(source TypeResponse, target TypeResponse) !bool {
	return c.assignable(source.id, target.id)!
}

// nuta_parts_equivalent_ignoring_undefined ports areUnionPartsEquivalentIgnoringUndefined.
fn (mut c Checker) nuta_parts_equivalent_ignoring_undefined(uncast TypeResponse, cast TypeResponse) !bool {
	mut uncast_parts := []int{}
	for part in c.constituents(uncast)! {
		if c.type_flags(part)! & type_flag_undefined == 0 {
			uncast_parts << part.id
		}
	}
	mut cast_parts := []int{}
	for part in c.constituents(cast)! {
		if c.type_flags(part)! & type_flag_undefined == 0 {
			cast_parts << part.id
		}
	}
	return uncast_parts.len == cast_parts.len && cast_parts.all(it in uncast_parts)
}

// nuta_has_index_signature: some union part has an index signature.
fn (mut c Checker) nuta_has_index_signature(t TypeResponse) !bool {
	for part in c.constituents(t)! {
		if c.index_infos(part.id)!.len > 0 {
			return true
		}
	}
	return false
}

// nuta_type_arguments ports getTypeArguments: the alias type arguments or, for a type reference,
// its type arguments.
fn (mut c Checker) nuta_type_arguments(t TypeResponse, mut cache NutaCache) ![]TypeResponse {
	if t.alias_type_arguments.len > 0 {
		if t.id !in cache.alias_args {
			cache.alias_args[t.id] = c.client.alias_type_arguments_of_type(c.snapshot,
				c.project, t.id)!
		}
		return cache.alias_args[t.id]
	}
	if is_type_reference(t) {
		return c.type_args(t)!
	}
	return []TypeResponse{}
}

// nuta_contains ports typeContains with the predicate `flags` (the union-aware isTypeFlagSet).
fn (mut c Checker) nuta_contains(t TypeResponse, flags u32, mut seen map[int]bool, mut cache NutaCache) !bool {
	if t.id in seen {
		return false
	}
	seen[t.id] = true
	if c.type_flags(t)! & flags != 0 {
		return true
	}
	if t.flags & (type_flag_union | type_flag_intersection) != 0 {
		for part in c.members_of(t)! {
			if c.nuta_contains(part, flags, mut seen, mut cache)! {
				return true
			}
		}
		return false
	}
	mut nested := c.nuta_type_arguments(t, mut cache)!
	for sig in c.signatures_of(t, signature_kind_call)! {
		nested << c.return_type(sig.id)!
		for param in c.signature_parameters(sig)! {
			nested << c.symbol_type(param.id)!
		}
	}
	for n in nested {
		if !n.is_null() && c.nuta_contains(n, flags, mut seen, mut cache)! {
			return true
		}
	}
	return false
}

fn (mut c Checker) nuta_contains_any(t TypeResponse, mut cache NutaCache) !bool {
	key := '${t.id}:any'
	if key !in cache.contains {
		mut seen := map[int]bool{}
		cache.contains[key] = c.nuta_contains(t, type_flag_any, mut seen, mut cache)!
	}
	return cache.contains[key]
}

fn (mut c Checker) nuta_contains_type_variable(t TypeResponse, mut cache NutaCache) !bool {
	key := '${t.id}:variable'
	if key !in cache.contains {
		mut seen := map[int]bool{}
		cache.contains[key] = c.nuta_contains(t, nuta_type_variable_or_index, mut seen, mut
			cache)!
	}
	return cache.contains[key]
}

// nuta_is_empty_object_type ports isEmptyObjectType.
fn (mut c Checker) nuta_is_empty_object_type(t TypeResponse) !bool {
	if c.type_flags(t)! & nuta_flag_non_primitive != 0 {
		return true
	}
	return c.properties(t)!.len == 0 && c.signatures_of(t, signature_kind_call)!.len == 0
		&& c.signatures_of(t, signature_kind_construct)!.len == 0
		&& c.index_infos(t.id)!.len == 0
}

// nuta_same_type_arguments ports haveSameTypeArguments.
fn (mut c Checker) nuta_same_type_arguments(a TypeResponse, b TypeResponse, mut cache NutaCache) !bool {
	a_args := c.nuta_type_arguments(a, mut cache)!
	b_args := c.nuta_type_arguments(b, mut cache)!
	return a_args.len == b_args.len && a_args.map(it.id) == b_args.map(it.id)
}

// nuta_same_properties ports hasSameProperties: the same property names, each as readonly in
// both.
fn (mut c Checker) nuta_same_properties(uncast TypeResponse, cast TypeResponse, mut cache NutaCache) !bool {
	uncast_props := c.properties(uncast)!
	cast_props := c.properties(cast)!
	if uncast_props.len != cast_props.len {
		return false
	}
	cast_names := cast_props.map(it.name)
	for prop in uncast_props {
		if prop.name !in cast_names {
			return false
		}
		if c.nuta_readonly_in_type(uncast, prop.name, mut cache, 0)! !=
			c.nuta_readonly_in_type(cast, prop.name, mut cache, 0)! {
			return false
		}
	}
	return true
}

// nuta_readonly_in_type ports isPropertyReadonlyInType of ts-api-utils.
fn (mut c Checker) nuta_readonly_in_type(t TypeResponse, name string, mut cache NutaCache, depth int) !bool {
	if depth > max_type_depth {
		return false
	}
	mut seen_property := false
	mut seen_readonly_signature := false
	for sub in c.constituents(t)! {
		prop := c.nuta_property_of(sub, name)!
		if prop.is_null() {
			if c.nuta_readonly_index(sub, name)! {
				if seen_property {
					return true
				}
				seen_readonly_signature = true
			}
		} else if seen_readonly_signature
			|| c.nuta_readonly_intersection(sub, name, mut cache, depth)! {
			return true
		} else {
			seen_property = true
		}
	}
	return false
}

// nuta_property_of ports ts-api-utils' getPropertyOfType (by escaped name).
fn (mut c Checker) nuta_property_of(t TypeResponse, name string) !SymbolResponse {
	for prop in c.properties(t)! {
		if prop.name == name {
			return prop
		}
	}
	return SymbolResponse{}
}

// nuta_readonly_index: the index signature that applies to the name (number for a numeric name,
// else string) is readonly.
fn (mut c Checker) nuta_readonly_index(t TypeResponse, name string) !bool {
	infos := c.index_infos(t.id)!
	if nuta_is_numeric_name(name) {
		for info in infos {
			if info.key_type.flags & type_flag_number != 0 {
				return info.is_readonly
			}
		}
	}
	for info in infos {
		if info.key_type.flags & nuta_flag_string != 0 {
			return info.is_readonly
		}
	}
	return false
}

// nuta_is_numeric_name ports isNumericPropertyName: String(+name) === name.
fn nuta_is_numeric_name(name string) bool {
	value := js_string_to_number(name)
	return js_number_to_string(value) == name
}

// nuta_readonly_intersection ports isReadonlyPropertyIntersection.
fn (mut c Checker) nuta_readonly_intersection(t TypeResponse, name string, mut cache NutaCache, depth int) !bool {
	for part in c.nuta_intersection_parts(t)! {
		prop := c.nuta_property_of(part, name)!
		if prop.is_null() {
			continue
		}
		if prop.flags & nuta_symbol_transient != 0 {
			if nuta_is_index_name(name) && is_type_reference(part) && c.is_tuple(part)! {
				if c.target_of(part)!.readonly {
					return true
				}
				continue
			}
			mapped := c.nuta_readonly_from_mapped_type(part, name, prop, mut cache, depth)!
			if mapped == 1 {
				return true
			}
			if mapped == 0 {
				continue
			}
		}
		if prop.flags & nuta_symbol_value_module != 0 || c.nuta_readonly_declaration(prop, mut
			cache)! {
			return true
		}
	}
	return false
}

fn (mut c Checker) nuta_intersection_parts(t TypeResponse) ![]TypeResponse {
	if t.flags & type_flag_intersection != 0 {
		return c.members_of(t)!
	}
	return [t]
}

// nuta_is_index_name: /^(?:[1-9]\d*|0)$/.
fn nuta_is_index_name(name string) bool {
	if name == '0' {
		return true
	}
	return name.len > 0 && name[0] >= `1` && name[0] <= `9` && name.bytes().all(it.is_digit())
}

// nuta_readonly_from_mapped_type ports isReadonlyPropertyFromMappedType for `prop`, the property
// `name` of `t`: 1 true, 0 false, -1 undefined. Without a readonly token the original asks whether
// the property is readonly in the modifiersType of the mapped type (the `T` of `keyof T`), which
// the tsgo API does not expose:
// - veslint reads it from the declaration of the mapped type and the type arguments of the type
//   (mapped_parts), and asks the same: for the type its declaration declares and for a type with
//   an alias (`Partial<T>`, `Pick<T, K>`, `Omit<T, K>`…);
// - for an instance without an alias (what a generic function returns, a member of a generic
//   class) the type arguments are not known: it reads the CheckFlags.Readonly of the property,
//   which TypeScript sets from the same modifiersType. The flag is unset where the original still
//   answers true (a property that is readonly in only some parts of an intersection, or one that
//   is a namespace) and set where it answers false (the `length` of a readonly tuple).
fn (mut c Checker) nuta_readonly_from_mapped_type(t TypeResponse, name string, prop SymbolResponse, mut cache NutaCache, depth int) !int {
	if t.flags & type_flag_object == 0 || t.object_flags & nuta_object_flag_mapped == 0 {
		return -1
	}
	symbol := c.symbol_of(t)!
	if symbol.declarations.len == 0 {
		return 0
	}
	declaration := symbol.declarations[0]
	tree := c.nuta_tree(handle_path(declaration), mut cache)!
	token := tree.node_child(handle_index(declaration), 'readonlyToken')
	if token != 0 && !(name.len > 3 && name.starts_with('__@') && !name[3..].contains('@')) {
		return if tree.node_kind(token) != nuta_kind_minus_token { 1 } else { 0 }
	}
	parts := c.mapped_parts(t)!
	if parts.known {
		// The unknown type has no properties.
		if parts.modifiers.is_null() {
			return 0
		}
		return if c.nuta_readonly_in_type(parts.modifiers, name, mut cache, depth + 1)! {
			1
		} else {
			0
		}
	}
	return if prop.check_flags & nuta_check_flag_readonly != 0 { 1 } else { 0 }
}

// nuta_readonly_declaration ports symbolHasReadonlyDeclaration.
fn (mut c Checker) nuta_readonly_declaration(symbol SymbolResponse, mut cache NutaCache) !bool {
	if symbol.flags & nuta_symbol_accessor == nuta_symbol_get_accessor {
		return true
	}
	for declaration in symbol.declarations {
		tree := c.nuta_tree(handle_path(declaration), mut cache)!
		index := handle_index(declaration)
		kind := tree.node_kind(index)
		if nuta_has_readonly_modifier(tree, index) {
			return true
		}
		if kind == nuta_kind_variable_declaration {
			list := tree.node_parent(index)
			if tree.node_flags(list) & nuta_node_flag_const != 0 {
				return true
			}
		}
		if kind == syntax_kind_enum_member {
			return true
		}
		if kind in [syntax_kind_property_assignment, nuta_kind_shorthand_property_assignment]
			&& c.nuta_in_const_context(tree, index)! {
			return true
		}
	}
	return false
}

// nuta_has_readonly_modifier: isModifierFlagSet(node, ModifierFlags.Readonly).
fn nuta_has_readonly_modifier(tree AstTree, index int) bool {
	modifiers := tree.node_child(index, 'modifiers')
	if modifiers == 0 {
		return false
	}
	for m in tree.node_children(modifiers) {
		if tree.node_kind(m) == nuta_kind_readonly_keyword {
			return true
		}
	}
	return false
}

// nuta_in_const_context ports isInConstContext.
fn (mut c Checker) nuta_in_const_context(tree AstTree, node int) !bool {
	mut current := node
	for depth := 0; depth < max_expression_depth; depth++ {
		parent := tree.node_parent(current)
		if parent == 0 {
			return false
		}
		match tree.node_kind(parent) {
			nuta_kind_array_literal, nuta_kind_object_literal, nuta_kind_parenthesized,
			nuta_kind_template_expression {
				current = parent
			}
			nuta_kind_as_expression, nuta_kind_type_assertion {
				type_node := tree.node_child(parent, 'type')
				if tree.node_kind(type_node) != nuta_kind_type_reference {
					return false
				}
				name := tree.node_child(type_node, 'typeName')
				return tree.node_kind(name) == syntax_kind_identifier
					&& tree.node_text(name) == 'const'
			}
			nuta_kind_call_expression {
				return c.nuta_const_call_argument(tree, parent, current)!
			}
			nuta_kind_prefix_unary {
				if tree.node_kind(current) != nuta_kind_numeric_literal {
					return false
				}
				operator := tree.node_source_text(parent)
				if !operator.starts_with('-') && !operator.starts_with('+') {
					return false
				}
				current = parent
			}
			syntax_kind_property_assignment {
				if tree.node_child(parent, 'initializer') != current {
					return false
				}
				current = tree.node_parent(parent)
			}
			nuta_kind_shorthand_property_assignment {
				current = tree.node_parent(parent)
			}
			else {
				return false
			}
		}
	}
	return false
}

// nuta_const_call_argument ports the CallExpression branch of isInConstContext: the property of
// the (instantiated) parameter type at the argument's index is readonly.
fn (mut c Checker) nuta_const_call_argument(tree AstTree, call int, argument int) !bool {
	signature := c.client.resolved_signature(c.snapshot, c.project, tree.node_handle(call))!
	if signature.id == 0 {
		return false
	}
	list := tree.node_child(call, 'arguments')
	if list == 0 {
		return false
	}
	index := tree.node_children(list).index(argument)
	if index < 0 {
		return false
	}
	params := c.signature_parameters(signature)!
	if index >= params.len || params[index].flags & nuta_symbol_transient == 0 {
		return false
	}
	param_type := c.symbol_type(params[index].id)!
	if param_type.is_null() {
		return false
	}
	props := c.properties(param_type)!
	if index >= props.len || props[index].flags & nuta_symbol_transient == 0 {
		return false
	}
	return props[index].check_flags & nuta_check_flag_readonly != 0
}

// --- contextual type fallback

// nuta_skip_contextual ports shouldSkipContextualTypeFallback.
fn (mut c Checker) nuta_skip_contextual(a NutaAssertion, parent C.TSNode, cast_is_any bool, mut cache NutaCache) !bool {
	if cast_is_any {
		return estree_binary_kind(parent) == 'LogicalExpression' || c.nuta_in_generic_context(a.node)!
	}
	if nuta_is_template_with_expressions(a.expression) {
		return true
	}
	if nuta_is_skip_parent(parent) || node_kind(a.expression) == 'array'
		|| nuta_in_destructuring_declaration(a.node, parent)
		|| c.nuta_property_in_problematic_context(a, parent)!
		|| nuta_assignment_in_non_statement_context(a.node, parent)
		|| nuta_right_of_logical_assignment(a.node, parent)
		|| c.nuta_argument_to_overloaded_function(a, mut cache)! {
		return true
	}
	if c.nuta_in_generic_context(a.node)! {
		original := nuta_original_expression(a.node)
		return !nuta_is_conceptually_literal(original) && node_kind(parent) != 'pair'
	}
	return false
}

// nuta_argument_index is the index of the node in the arguments of the call or `new` it is an
// argument of, or -1.
fn nuta_argument_index(node C.TSNode) int {
	parent := estree_parent(node) or { return -1 }
	if node_kind(parent) != 'arguments' {
		return -1
	}
	call := node_parent(parent) or { return -1 }
	if node_kind(call) !in ['call_expression', 'new_expression'] {
		return -1
	}
	for i, arg in named_children(parent) {
		if node_key(unwrap_parens(arg)) == node_key(node) {
			return i
		}
	}
	return -1
}

// nuta_in_destructuring_declaration ports isInDestructuringDeclaration.
fn nuta_in_destructuring_declaration(node C.TSNode, parent C.TSNode) bool {
	if node_kind(parent) != 'variable_declarator' {
		return false
	}
	value := node_field(parent, 'value') or { return false }
	if node_key(unwrap_parens(value)) != node_key(node) {
		return false
	}
	name := node_field(parent, 'name') or { return false }
	return node_kind(name) in ['object_pattern', 'array_pattern']
}

// nuta_property_in_problematic_context ports isPropertyInProblematicContext.
fn (mut c Checker) nuta_property_in_problematic_context(a NutaAssertion, parent C.TSNode) !bool {
	if node_kind(parent) != 'pair' {
		return false
	}
	value := node_field(parent, 'value') or { return false }
	if node_key(unwrap_parens(value)) != node_key(a.node) {
		return false
	}
	object := node_parent(parent) or { return false }
	if node_kind(object) != 'object' {
		return false
	}
	object_contextual := c.contextual_type(object)!
	if !object_contextual.is_null() && object_contextual.flags & type_flag_union != 0 {
		property_contextual := c.contextual_type(a.node)!
		if property_contextual.is_null() {
			return true
		}
		non_nullable := c.client.non_nullable_type(c.snapshot, c.project, property_contextual.id)!
		if non_nullable.flags & type_flag_union != 0 {
			return true
		}
		uncast := c.node_type(a.expression) or { return true }
		return !c.nuta_assignable(uncast, non_nullable)!
	}
	object_parent := estree_parent(object) or { return false }
	if node_kind(object_parent) == 'satisfies_expression' {
		return true
	}
	if node_kind(object_parent) == 'arguments' {
		call := node_parent(object_parent) or { return false }
		if node_kind(call) == 'call_expression' {
			call_parent := estree_parent(call) or { return false }
			return node_kind(call_parent) == 'satisfies_expression'
		}
	}
	return false
}

// nuta_assignment_in_non_statement_context ports isAssignmentInNonStatementContext.
fn nuta_assignment_in_non_statement_context(node C.TSNode, parent C.TSNode) bool {
	if node_kind(parent) !in ['assignment_expression', 'augmented_assignment_expression'] {
		return false
	}
	right := node_field(parent, 'right') or { return false }
	if node_key(unwrap_parens(right)) != node_key(node) {
		return false
	}
	grand := estree_parent(parent) or { return true }
	return node_kind(grand) != 'expression_statement'
}

// nuta_right_of_logical_assignment ports isRightHandSideOfLogicalAssignment.
fn nuta_right_of_logical_assignment(node C.TSNode, parent C.TSNode) bool {
	if node_kind(parent) != 'augmented_assignment_expression'
		|| operator_of(parent) !in ['&&=', '||=', '??='] {
		return false
	}
	right := node_field(parent, 'right') or { return false }
	return node_key(unwrap_parens(right)) == node_key(node)
}

// nuta_argument_to_overloaded_function ports isArgumentToOverloadedFunction.
fn (mut c Checker) nuta_argument_to_overloaded_function(a NutaAssertion, mut cache NutaCache) !bool {
	index := nuta_argument_index(a.node)
	if index < 0 {
		return false
	}
	args := estree_parent(a.node) or { return false }
	call := node_parent(args) or { return false }
	callee := nuta_callee(call) or { return false }
	callee_type := c.node_type(callee) or { return false }
	signatures := c.signatures_of(callee_type, signature_kind_call)!
	if signatures.len <= 1 {
		return false
	}
	mut param_types := []TypeResponse{}
	for sig in signatures {
		params := c.signature_parameters(sig)!
		if index >= params.len {
			return true
		}
		param := params[index]
		mut param_type := c.symbol_type(param.id)!
		if c.nuta_is_rest_parameter(param.value_declaration, mut cache)! {
			type_args := c.nuta_type_arguments(param_type, mut cache)!
			if type_args.len > 0 {
				param_type = type_args[0]
			}
		}
		param_types << param_type
	}
	if param_types.all(it.id == param_types[0].id) {
		return false
	}
	uncast := c.node_type(a.expression) or { return false }
	for t in param_types {
		if !c.nuta_assignable(uncast, t)! {
			return true
		}
	}
	return false
}

fn (mut c Checker) nuta_is_rest_parameter(handle string, mut cache NutaCache) !bool {
	if handle == '' || handle_kind(handle) != syntax_kind_parameter {
		return false
	}
	tree := c.nuta_tree(handle_path(handle), mut cache)!
	return tree.node_child(handle_index(handle), 'dotDotDotToken') != 0
}

// nuta_in_generic_context ports isInGenericContext: the node is (through at most one arrow
// function with an expression body) an argument of a call or `new` of a generic function without
// explicit type arguments.
fn (mut c Checker) nuta_in_generic_context(node C.TSNode) !bool {
	mut seen_function := false
	mut current := node
	for depth := 0; depth < max_expression_depth; depth++ {
		current = node_parent(current) or { return false }
		match node_kind(current) {
			'function_declaration', 'generator_function_declaration', 'function_expression',
			'generator_function', 'method_definition' {
				return false
			}
			'arrow_function' {
				body := node_field(current, 'body') or { return false }
				if node_kind(body) == 'statement_block' || seen_function {
					return false
				}
				seen_function = true
			}
			'call_expression', 'new_expression' {
				callee := nuta_callee(current) or { continue }
				if _ := node_field(current, 'type_arguments') {
					continue
				}
				if node_kind(current) == 'call_expression' && is_member(callee)
					&& nuta_argument_index(node) >= 0 {
					if args := estree_parent(node) {
						if call := node_parent(args) {
							if node_key(call) == node_key(current) {
								continue
							}
						}
					}
				}
				callee_type := c.node_type(callee) or { continue }
				for sig in c.signatures_of(callee_type, signature_kind_call)! {
					if sig.type_parameters.len > 0 {
						return true
					}
				}
			}
			else {}
		}
	}
	return false
}

// nuta_phantom_mismatch ports hasPhantomTypeArgumentMismatch.
fn (mut c Checker) nuta_phantom_mismatch(a NutaAssertion, uncast TypeResponse, contextual TypeResponse, mut cache NutaCache) !bool {
	if !c.nuta_in_generic_context(a.node)! {
		return false
	}
	if !c.nuta_phantom_arguments(uncast, mut cache)! && !c.nuta_phantom_arguments(contextual, mut
		cache)! {
		return false
	}
	return !c.nuta_same_type_arguments(uncast, contextual, mut cache)!
}

// nuta_phantom_arguments ports hasPhantomTypeArguments.
fn (mut c Checker) nuta_phantom_arguments(t TypeResponse, mut cache NutaCache) !bool {
	return c.nuta_is_empty_object_type(t)! && c.nuta_type_arguments(t, mut cache)!.len > 0
}

// nuta_generics_mismatch ports genericsMismatch.
fn (mut c Checker) nuta_generics_mismatch(uncast TypeResponse, contextual TypeResponse) !bool {
	for prop in c.properties(contextual)! {
		contextual_sigs := c.signatures(c.symbol_type(prop.id)!.id, signature_kind_call)!
		if !contextual_sigs.any(it.type_parameters.len > 0) {
			continue
		}
		// uncast.getProperty(escapedName) escapes the name again: a name with two leading
		// underscores is never found.
		uncast_prop := if prop.name.starts_with('__') {
			SymbolResponse{}
		} else {
			c.nuta_property_of(uncast, prop.name)!
		}
		if uncast_prop.is_null() {
			return true
		}
		uncast_sigs := c.signatures(c.symbol_type(uncast_prop.id)!.id, signature_kind_call)!
		if !uncast_sigs.any(it.type_parameters.len > 0) {
			return true
		}
	}
	return false
}
