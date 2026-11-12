module rules

import json2
import time
import tsgo { TypeResponse }
import treesitter { Ident, has_child_kind, node_end, node_field, node_kind, node_start, nodes_of_kinds, position_of }

// Port of the `strict-boolean-expressions` rule of typescript-eslint 8.62.0, with its options
// and its suggestions.

const sbe_messages = {
	'conditionErrorAny':                     'Unexpected any value in {{context}}. An explicit comparison or type conversion is required.'
	'conditionErrorNullableBoolean':         'Unexpected nullable boolean value in {{context}}. Please handle the nullish case explicitly.'
	'conditionErrorNullableEnum':            'Unexpected nullable enum value in {{context}}. Please handle the nullish/zero/NaN cases explicitly.'
	'conditionErrorNullableNumber':          'Unexpected nullable number value in {{context}}. Please handle the nullish/zero/NaN cases explicitly.'
	'conditionErrorNullableObject':          'Unexpected nullable object value in {{context}}. An explicit null check is required.'
	'conditionErrorNullableString':          'Unexpected nullable string value in {{context}}. Please handle the nullish/empty cases explicitly.'
	'conditionErrorNullish':                 'Unexpected nullish value in conditional. The condition is always false.'
	'conditionErrorNumber':                  'Unexpected number value in {{context}}. An explicit zero/NaN check is required.'
	'conditionErrorObject':                  'Unexpected object value in {{context}}. The condition is always true.'
	'conditionErrorOther':                   'Unexpected value in conditional. A boolean expression is required.'
	'conditionErrorString':                  'Unexpected string value in {{context}}. An explicit empty string check is required.'
	'conditionFixCastBoolean':               'Explicitly convert value to a boolean (`Boolean(value)`)'
	'conditionFixCompareArrayLengthNonzero': "Change condition to check array's length (`value.length > 0`)"
	'conditionFixCompareArrayLengthZero':    "Change condition to check array's length (`value.length === 0`)"
	'conditionFixCompareEmptyString':        'Change condition to check for empty string (`value !== ""`)'
	'conditionFixCompareFalse':              'Change condition to check if false (`value === false`)'
	'conditionFixCompareNaN':                'Change condition to check for NaN (`!Number.isNaN(value)`)'
	'conditionFixCompareNullish':            'Change condition to check for null/undefined (`value != null`)'
	'conditionFixCompareStringLength':       "Change condition to check string's length (`value.length !== 0`)"
	'conditionFixCompareTrue':               'Change condition to check if true (`value === true`)'
	'conditionFixCompareZero':               'Change condition to check for 0 (`value !== 0`)'
	'conditionFixDefaultEmptyString':        'Explicitly treat nullish value the same as an empty string (`value ?? ""`)'
	'conditionFixDefaultFalse':              'Explicitly treat nullish value the same as false (`value ?? false`)'
	'conditionFixDefaultZero':               'Explicitly treat nullish value the same as 0 (`value ?? 0`)'
	'explicitBooleanReturnType':             'Add an explicit `boolean` return type annotation.'
	'noStrictNullCheck':                     'This rule requires the `strictNullChecks` compiler option to be turned on to function correctly.'
	'predicateCannotBeAsync':                "Predicate function should not be 'async'; expected a boolean return type."
}

// TypeFlags.EnumLike (EnumLiteral | Enum) and TypeFlags.Boolean.
const sbe_type_flags_enum_like = u32(98304)
const sbe_type_flag_boolean = u32(256)

struct SbeOptions {
	allow_any              bool
	allow_nullable_boolean bool
	allow_nullable_enum    bool
	allow_nullable_number  bool
	allow_nullable_object  bool
	allow_nullable_string  bool
	allow_number           bool
	allow_string           bool
	allow_without_strict   bool
}

fn sbe_options(options []json2.Any) !SbeOptions {
	o := option_object(strict_boolean_expressions, options, ['allowAny', 'allowNullableBoolean',
		'allowNullableEnum', 'allowNullableNumber', 'allowNullableObject', 'allowNullableString',
		'allowNumber', 'allowString', 'allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing'])!
	return SbeOptions{
		allow_any:              o.bool_value('allowAny')!
		allow_nullable_boolean: o.bool_value('allowNullableBoolean')!
		allow_nullable_enum:    o.bool_value('allowNullableEnum')!
		allow_nullable_number:  o.bool_value('allowNullableNumber')!
		allow_nullable_object:  o.bool_value('allowNullableObject')!
		allow_nullable_string:  o.bool_value('allowNullableString')!
		allow_number:           o.bool_value('allowNumber')!
		allow_string:           o.bool_value('allowString')!
		allow_without_strict:   o.bool_value('allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing')!
	}
}

struct SbeState {
mut:
	traversed map[u64]bool
	checks    []C.TSNode // the nodes of checkNode, in the order they are found
}

fn (mut c Checker) lint_strict_boolean_expressions(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	options := sbe_options(c.rule_options(strict_boolean_expressions))!
	mut sw := time.new_stopwatch()
	nodes := c.nodes_of_kinds(root, ['call_expression', 'ternary_expression', 'do_statement',
		'for_statement', 'if_statement', 'binary_expression', 'unary_expression', 'while_statement'],
		type_name_kinds)
	// What the calls need: their signature, for the argument an assertion function asserts, and
	// the type of the array of a call with a predicate.
	mut spans := []Span{}
	for node in nodes {
		if node_kind(node) != 'call_expression' {
			continue
		}
		args := call_args(node) or { continue }
		if args.len == 0 {
			continue
		}
		spans << node_span(node)
		function := node_field(node, 'function') or { continue }
		// The type of the callee tells whether the call may assert (sbe_may_assert).
		spans << Span{
			key:      node_key(function)
			first:    function
			end:      node_end(function)
			optional: true
		}
		callee := unwrap_parens(function)
		if is_member(callee) {
			if object := node_field(callee, 'object') {
				spans << node_span(object)
			}
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	// The traversal, in the order ESLint visits the nodes: the first context that reaches a node
	// decides whether it is a condition.
	mut state := SbeState{}
	mut predicates := []C.TSNode{}
	for node in nodes {
		match node_kind(node) {
			'call_expression' {
				for argument in c.sbe_asserted_argument(node)! {
					sbe_traverse_node(argument, true, mut state)
				}
				predicates << c.sbe_predicate(node)!
			}
			'ternary_expression', 'do_statement', 'if_statement', 'while_statement' {
				if test := node_field(node, 'condition') {
					sbe_traverse_node(test, true, mut state)
				}
			}
			'for_statement' {
				// The test, or an empty statement when there is none.
				condition := node_field(node, 'condition') or { continue }
				if node_kind(condition) != 'empty_statement' {
					sbe_traverse_node(condition, true, mut state)
				}
			}
			'binary_expression' {
				if operator_of(node) in ['&&', '||'] {
					sbe_traverse_logical(node, false, mut state)
				}
			}
			'unary_expression' {
				if operator_of(node) == '!' {
					if argument := node_field(node, 'argument') {
						sbe_traverse_node(argument, true, mut state)
					}
				}
			}
			else {}
		}
	}
	spans = []Span{}
	for node in state.checks {
		spans << node_span(node)
		if object := sbe_length_object(node) {
			spans << node_span(object)
		}
	}
	for predicate in predicates {
		spans << node_span(predicate)
		// An arrow predicate with an expression body gets the suggestions of a condition, and
		// `array.length` there needs the type of `array` (isArrayLengthExpression).
		if body := node_field(predicate, 'body') {
			if object := sbe_length_object(unwrap_parens(body)) {
				spans << node_span(object)
			}
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	if !c.strict_null_checks && !options.allow_without_strict {
		findings << Finding{
			stmt:       Ident{
				row: -1
			}
			message_id: 'noStrictNullCheck'
		}
	}
	for node in state.checks {
		// checkNode
		node_type := c.node_type(node) or { continue }
		constrained := c.constrained(node_type)!
		report_type := sbe_report_type(c.sbe_variant_types(c.constituents(constrained)!)!, options)
		if report_type == '' {
			continue
		}
		findings << Finding{
			stmt:        position_of(node)
			message_id:  report_type
			data:        {
				'context': 'conditional'
			}
			suggestions: c.sbe_suggestions(node, report_type)!
		}
	}
	for predicate in predicates {
		findings << c.sbe_check_predicate(predicate, options)!
	}
	findings.sort_with_compare(compare_findings)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += state.checks.len + predicates.len
	return findings
}

// sbe_traverse_node ports traverseNode: a logical expression gives its operands; any other node
// is checked if it is a condition. A node is only looked at once.
fn sbe_traverse_node(raw C.TSNode, is_condition bool, mut state SbeState) {
	node := unwrap_parens(raw)
	key := node_key(node)
	if state.traversed[key] {
		return
	}
	state.traversed[key] = true
	if node_kind(node) == 'binary_expression' && operator_of(node) in ['&&', '||'] {
		sbe_traverse_logical(node, is_condition, mut state)
		return
	}
	if !is_condition {
		return
	}
	state.checks << node
}

// sbe_traverse_logical ports traverseLogicalExpression: the left operand is always a condition;
// the right one only if the expression is.
fn sbe_traverse_logical(node C.TSNode, is_condition bool, mut state SbeState) {
	if left := node_field(node, 'left') {
		sbe_traverse_node(left, true, mut state)
	}
	if right := node_field(node, 'right') {
		sbe_traverse_node(right, is_condition, mut state)
	}
}

// sbe_asserted_argument ports findTruthinessAssertedArgument: the argument that the signature of
// the call asserts (`asserts x`, without a type), among those before any spread; an empty list
// if there is none.
fn (mut c Checker) sbe_asserted_argument(call C.TSNode) ![]C.TSNode {
	// `import(…)` is an ImportExpression in ESTree, or a type, not a call.
	if function := node_field(call, 'function') {
		if node_kind(unwrap_parens(function)) == 'import' {
			return []C.TSNode{}
		}
	}
	mut checkable := []C.TSNode{}
	for arg in call_args(call) or { return []C.TSNode{} } {
		if node_kind(arg) == 'spread_element' {
			break
		}
		checkable << arg
	}
	if checkable.len == 0 || !c.sbe_may_assert(call)! {
		return []C.TSNode{}
	}
	signature := c.resolved_signature(call)!
	if signature.id == 0 {
		return []C.TSNode{}
	}
	predicate := c.type_predicate(signature.id)!
	if !predicate.found || predicate.kind != predicate_asserts_identifier || !predicate.typ.is_null() {
		return []C.TSNode{}
	}
	if predicate.parameter_index < 0 || predicate.parameter_index >= checkable.len {
		return []C.TSNode{}
	}
	return [checkable[predicate.parameter_index]]
}

const sbe_syntax_kind_type_predicate = u32(184)

// sbe_may_assert tells whether the signature a call resolves to may be an assertion (`asserts x`).
// When the callee has an object type with call signatures, the call resolves to one of them with
// the type arguments applied, which keeps its predicate, or, if no overload fits, to one made
// from the first of them: if none can assert, the call is not resolved, which most calls are
// spared. Any other callee (a union, a type parameter, `any`, an optional chain, a node tsgo has
// no counterpart for) is left to the resolved signature.
fn (mut c Checker) sbe_may_assert(call C.TSNode) !bool {
	callee := c.node_type(node_field(call, 'function') or { return true }) or { return true }
	if callee.flags != type_flag_object || callee.object_flags & object_flag_mapped != 0 {
		return true
	}
	if node_key(call) in c.resolved_cache
		&& '${callee.id}:${signature_kind_call}' !in c.sig_cache {
		// Another rule has resolved the call already, and the signatures of the callee would
		// have to be asked.
		return true
	}
	signatures := c.signatures_of(callee, signature_kind_call)!
	for signature in signatures {
		if c.sbe_signature_may_assert(signature)! {
			return true
		}
	}
	return signatures.len == 0
}

// sbe_signature_may_assert: the declaration of the signature has an `asserts` predicate as its
// return type, which is the only way for it to assert (TypeScript infers `x is T`, never
// `asserts x`). A signature without a declaration, or declared in JavaScript, where the predicate
// may come from JSDoc, is taken as one that may.
fn (mut c Checker) sbe_signature_may_assert(signature tsgo.SignatureResponse) !bool {
	if signature.declaration == '' {
		return true
	}
	path := tsgo.handle_path(signature.declaration)
	if path.ends_with('.js') || path.ends_with('.jsx') || path.ends_with('.mjs')
		|| path.ends_with('.cjs') {
		return true
	}
	tree := c.declaration_ast(path)!
	return_type := tree.node_child(tsgo.handle_index(signature.declaration), 'type')
	return return_type != 0 && tree.node_kind(return_type) == sbe_syntax_kind_type_predicate
		&& tree.node_child(return_type, 'assertsModifier') != 0
}

// sbe_predicate ports isArrayMethodCallWithPredicate and gives the first argument of such a call
// (`array.filter(…)` and the like), which may be a spread.
fn (mut c Checker) sbe_predicate(call C.TSNode) ![]C.TSNode {
	callee := unwrap_parens(node_field(call, 'function') or { return []C.TSNode{} })
	if !is_member(callee) || is_estree_chain_root(callee) {
		return []C.TSNode{}
	}
	name := c.static_member_string(callee) or { return []C.TSNode{} }
	if name !in array_predicate_methods {
		return []C.TSNode{}
	}
	return c.array_predicate_callback(call)!
}

// sbe_length_object: the object of `object.length`, when the node is that member access.
fn sbe_length_object(node C.TSNode) ?C.TSNode {
	if node_kind(node) != 'member_expression' || is_estree_chain_root(node) {
		return none
	}
	property := node_field(node, 'property')?
	if node_kind(property) != 'property_identifier' {
		return none
	}
	object := node_field(node, 'object')?
	return unwrap_parens(object)
}

// sbe_variant_types ports inspectVariantTypes: the kinds of value the parts of a type are.
fn (mut c Checker) sbe_variant_types(types []TypeResponse) ![]string {
	mut variants := []string{}
	nullish := type_flag_null | type_flag_undefined | type_flag_void
	if types.any(it.flags & nullish != 0) {
		variants << 'nullish'
	}
	booleans := types.filter(it.flags & type_flag_boolean_like != 0)
	if booleans.len == 1 {
		variants << if is_true_literal(booleans[0]) { 'truthy boolean' } else { 'boolean' }
	} else if booleans.len == 2 {
		variants << 'boolean'
	}
	strings := types.filter(it.flags & type_flag_string_like != 0)
	if strings.len > 0 {
		variants << if strings.all(sbe_is_truthy_string(it)) { 'truthy string' } else { 'string' }
	}
	numbers := types.filter(it.flags & (type_flag_number_like | type_flag_bigint_like) != 0)
	if numbers.len > 0 {
		variants << if numbers.all(sbe_is_truthy_number(it)) { 'truthy number' } else { 'number' }
	}
	if types.any(it.flags & sbe_type_flags_enum_like != 0) {
		variants << 'enum'
	}
	known := nullish | type_flag_boolean_like | type_flag_string_like | type_flag_number_like | type_flag_bigint_like | type_flag_type_parameter | type_flag_any | type_flag_unknown | type_flag_never
	if types.any(it.flags & known == 0) {
		// A branded boolean (`boolean & { __brand: … }`) is a boolean.
		mut branded := false
		for t in types {
			if t.flags & type_flag_intersection != 0 {
				for part in c.members_of(t)! {
					if part.flags & (sbe_type_flag_boolean | type_flag_boolean_literal) != 0 {
						branded = true
					}
				}
			}
		}
		kind := if branded { 'boolean' } else { 'object' }
		if kind !in variants {
			variants << kind
		}
	}
	if types.any(it.flags & (type_flag_type_parameter | type_flag_any | type_flag_unknown) != 0) {
		variants << 'any'
	}
	if types.any(it.flags & type_flag_never != 0) {
		variants << 'never'
	}
	return variants
}

// sbe_is_truthy_string: a string literal type that is not the empty string.
fn sbe_is_truthy_string(t TypeResponse) bool {
	if t.flags & type_flag_string_literal == 0 {
		return false
	}
	value := t.value
	return value is string && value != ''
}

// sbe_is_truthy_number: a number literal type that is not zero.
fn sbe_is_truthy_number(t TypeResponse) bool {
	return t.flags & type_flag_number_literal != 0 && t.has_value() && t.value.f64() != 0
}

fn sbe_is(variants []string, wanted []string) bool {
	return variants.len == wanted.len && wanted.all(it in variants)
}

// sbe_report_type ports determineReportType: the message for a set of kinds of value, or '' when
// it is allowed.
fn sbe_report_type(variants []string, options SbeOptions) string {
	if sbe_is(variants, ['boolean']) || sbe_is(variants, ['truthy boolean']) {
		return ''
	}
	if sbe_is(variants, ['never']) {
		return ''
	}
	if sbe_is(variants, ['nullish']) {
		return 'conditionErrorNullish'
	}
	if sbe_is(variants, ['nullish', 'truthy boolean']) {
		return ''
	}
	if sbe_is(variants, ['nullish', 'boolean']) {
		return if !options.allow_nullable_boolean { 'conditionErrorNullableBoolean' } else { '' }
	}
	if (options.allow_number && sbe_is(variants, ['nullish', 'truthy number']))
		|| (options.allow_string && sbe_is(variants, ['nullish', 'truthy string'])) {
		return ''
	}
	if sbe_is(variants, ['string']) || sbe_is(variants, ['truthy string']) {
		return if !options.allow_string { 'conditionErrorString' } else { '' }
	}
	if sbe_is(variants, ['nullish', 'string']) {
		return if !options.allow_nullable_string { 'conditionErrorNullableString' } else { '' }
	}
	if sbe_is(variants, ['number']) || sbe_is(variants, ['truthy number']) {
		return if !options.allow_number { 'conditionErrorNumber' } else { '' }
	}
	if sbe_is(variants, ['nullish', 'number']) {
		return if !options.allow_nullable_number { 'conditionErrorNullableNumber' } else { '' }
	}
	if sbe_is(variants, ['object']) {
		return 'conditionErrorObject'
	}
	if sbe_is(variants, ['nullish', 'object']) {
		return if !options.allow_nullable_object { 'conditionErrorNullableObject' } else { '' }
	}
	if sbe_is(variants, ['nullish', 'number', 'enum'])
		|| sbe_is(variants, ['nullish', 'string', 'enum'])
		|| sbe_is(variants, ['nullish', 'truthy number', 'enum'])
		|| sbe_is(variants, ['nullish', 'truthy string', 'enum'])
		|| sbe_is(variants, ['nullish', 'truthy number', 'truthy string', 'enum'])
		|| sbe_is(variants, ['nullish', 'truthy number', 'string', 'enum'])
		|| sbe_is(variants, ['nullish', 'truthy string', 'number', 'enum'])
		|| sbe_is(variants, ['nullish', 'number', 'string', 'enum']) {
		return if !options.allow_nullable_enum { 'conditionErrorNullableEnum' } else { '' }
	}
	if sbe_is(variants, ['any']) {
		return if !options.allow_any { 'conditionErrorAny' } else { '' }
	}
	return 'conditionErrorOther'
}

// SbeWrap is one suggestion: its message, whether it replaces the `!` expression around the node
// and the code that goes in its place, with `{}` for the code of the node.
struct SbeWrap {
	message_id string
	on_parent  bool
	template   string
}

// sbe_suggestions ports getSuggestionsForConditionError.
fn (mut c Checker) sbe_suggestions(node C.TSNode, report_type string) ![]Suggestion {
	inner := es_child(node)
	mut negation := ?EsNode(none)
	if parent := inner.parent() {
		if !parent.chain && node_kind(parent.node) == 'unary_expression'
			&& operator_of(parent.node) == '!' {
			negation = parent
		}
	}
	negated := negation != none
	wraps := match report_type {
		'conditionErrorAny' {
			[SbeWrap{'conditionFixCastBoolean', false, 'Boolean({})'}]
		}
		'conditionErrorNullableBoolean' {
			if negated {
				[SbeWrap{'conditionFixDefaultFalse', false, '{} ?? false'},
					SbeWrap{'conditionFixCompareFalse', true, '{} === false'}]
			} else {
				[SbeWrap{'conditionFixDefaultFalse', false, '{} ?? false'},
					SbeWrap{'conditionFixCompareTrue', false, '{} === true'}]
			}
		}
		'conditionErrorNullableEnum', 'conditionErrorNullableObject' {
			if negated {
				[SbeWrap{'conditionFixCompareNullish', true, '{} == null'}]
			} else {
				[SbeWrap{'conditionFixCompareNullish', false, '{} != null'}]
			}
		}
		'conditionErrorNullableNumber' {
			if negated {
				[SbeWrap{'conditionFixCompareNullish', true, '{} == null'},
					SbeWrap{'conditionFixDefaultZero', false, '{} ?? 0'},
					SbeWrap{'conditionFixCastBoolean', true, '!Boolean({})'}]
			} else {
				[SbeWrap{'conditionFixCompareNullish', false, '{} != null'},
					SbeWrap{'conditionFixDefaultZero', false, '{} ?? 0'},
					SbeWrap{'conditionFixCastBoolean', false, 'Boolean({})'}]
			}
		}
		'conditionErrorNullableString' {
			if negated {
				[SbeWrap{'conditionFixCompareNullish', true, '{} == null'},
					SbeWrap{'conditionFixDefaultEmptyString', false, '{} ?? ""'},
					SbeWrap{'conditionFixCastBoolean', true, '!Boolean({})'}]
			} else {
				[SbeWrap{'conditionFixCompareNullish', false, '{} != null'},
					SbeWrap{'conditionFixDefaultEmptyString', false, '{} ?? ""'},
					SbeWrap{'conditionFixCastBoolean', false, 'Boolean({})'}]
			}
		}
		'conditionErrorNumber' {
			if c.sbe_is_array_length(node)! {
				if negated {
					[SbeWrap{'conditionFixCompareArrayLengthZero', true, '{} === 0'}]
				} else {
					[SbeWrap{'conditionFixCompareArrayLengthNonzero', false, '{} > 0'}]
				}
			} else if negated {
				[SbeWrap{'conditionFixCompareZero', true, '{} === 0'},
					SbeWrap{'conditionFixCompareNaN', true, 'Number.isNaN({})'},
					SbeWrap{'conditionFixCastBoolean', true, '!Boolean({})'}]
			} else {
				[SbeWrap{'conditionFixCompareZero', false, '{} !== 0'},
					SbeWrap{'conditionFixCompareNaN', false, '!Number.isNaN({})'},
					SbeWrap{'conditionFixCastBoolean', false, 'Boolean({})'}]
			}
		}
		'conditionErrorString' {
			if negated {
				[SbeWrap{'conditionFixCompareStringLength', true, '{}.length === 0'},
					SbeWrap{'conditionFixCompareEmptyString', true, '{} === ""'},
					SbeWrap{'conditionFixCastBoolean', true, '!Boolean({})'}]
			} else {
				[SbeWrap{'conditionFixCompareStringLength', false, '{}.length > 0'},
					SbeWrap{'conditionFixCompareEmptyString', false, '{} !== ""'},
					SbeWrap{'conditionFixCastBoolean', false, 'Boolean({})'}]
			}
		}
		else {
			[]SbeWrap{}
		}
	}
	mut suggestions := []Suggestion{}
	for wrap in wraps {
		mut target := inner
		if wrap.on_parent {
			target = negation or { inner }
		}
		code := c.wrapping_inner_code(target, inner)
		fix := c.wrapping_fix(target, wrap.template.replace('{}', code))
		_, suggestion := c.suggestion(wrap.message_id, map[string]string{}, [fix])!
		suggestions << suggestion
	}
	return suggestions
}

// sbe_is_array_length ports isArrayLengthExpression: `array.length`, of an array or of a union of
// arrays.
fn (mut c Checker) sbe_is_array_length(node C.TSNode) !bool {
	object := sbe_length_object(node) or { return false }
	property := node_field(node, 'property') or { return false }
	if c.identifier_name(property) != 'length' {
		return false
	}
	object_type := c.node_type(object) or { return false }
	return c.rasc_is_array_or_union_of_arrays(c.constrained(object_type)!)!
}

// sbe_check_predicate ports checkArrayMethodCallPredicate: the predicate of an array method must
// return a boolean.
fn (mut c Checker) sbe_check_predicate(predicate C.TSNode, options SbeOptions) ![]Finding {
	kind := node_kind(predicate)
	is_function := kind in ['arrow_function', 'function_expression', 'generator_function']
	// The message for a function that is `async` by accident.
	if is_function && has_child_kind(predicate, 'async') {
		return [finding_at(predicate, 'predicateCannotBeAsync')]
	}
	mut return_types := []TypeResponse{}
	if predicate_type := c.node_type(predicate) {
		for signature in c.signatures_of(predicate_type, signature_kind_call)! {
			mut return_type := c.return_type(signature.id)!
			if return_type.flags & type_flag_type_parameter != 0 {
				constraint := c.base_constraint(return_type)!
				if !constraint.is_null() {
					return_type = constraint
				}
			}
			return_types << return_type
		}
	}
	mut flattened := []TypeResponse{}
	for return_type in return_types {
		flattened << c.constituents(return_type)!
	}
	report_type := sbe_report_type(c.sbe_variant_types(unique_types(flattened))!, options)
	if report_type == '' {
		return []Finding{}
	}
	mut suggestions := []Suggestion{}
	if is_function {
		if body := node_field(predicate, 'body') {
			if node_kind(body) != 'statement_block' {
				suggestions << c.sbe_suggestions(unwrap_parens(body), report_type)!
			}
		}
		if _ := node_field(predicate, 'return_type') {
		} else {
			if fixes := c.sbe_return_type_fixes(predicate) {
				_, suggestion := c.suggestion('explicitBooleanReturnType', map[string]string{},
					fixes)!
				suggestions << suggestion
			}
		}
	}
	return [
		Finding{
			stmt:        position_of(predicate)
			message_id:  report_type
			data:        {
				'context': 'array predicate return type'
			}
			suggestions: suggestions
		},
	]
}

// sbe_return_type_fixes ports the fixer of `explicitBooleanReturnType`: `: boolean` after the
// parameters, in parentheses if the only parameter of an arrow function has none.
fn (mut c Checker) sbe_return_type_fixes(function C.TSNode) ?[]Fix {
	if node_kind(function) == 'arrow_function' {
		// isParenlessArrowFunction
		if parameter := node_field(function, 'parameter') {
			return [fix_insert_at(node_start(parameter), '('),
				fix_insert_at(node_end(parameter), '): boolean')]
		}
	}
	parameters := node_field(function, 'parameters')?
	// The `)` that closes the parameters.
	return [fix_insert_at(node_end(parameters), ': boolean')]
}
