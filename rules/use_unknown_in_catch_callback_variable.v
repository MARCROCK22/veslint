module rules

import time
import tsgo { SignatureResponse, TypeResponse }
import treesitter { Ident, children, named_children, node_end, node_field, node_kind, nodes_of_kind, position_of }

// Port of the `use-unknown-in-catch-callback-variable` rule of typescript-eslint 8.62.0 (it has no
// options), with its suggestions.
//
// Deviation: for a handler whose only parameter is a rest of an empty tuple, `(...args: []) => …`,
// typescript-eslint throws (it reads the flags of the tuple's missing first element) and lints
// nothing; veslint reports the handler.

const uuiccv_messages = {
	'addUnknownRestTypeAnnotationSuggestion': 'Add an explicit `: [unknown]` type annotation to the rejection callback rest variable.'
	'addUnknownTypeAnnotationSuggestion':     'Add an explicit `: unknown` type annotation to the rejection callback variable.'
	'useUnknown':                             'Prefer the safe `: unknown` for a `{{method}}`{{append}} callback variable.'
	'useUnknownArrayDestructuringPattern':    'Prefer the safe `: unknown` for a `{{method}}`{{append}} callback variable. The thrown error may not be iterable.'
	'useUnknownObjectDestructuringPattern':   'Prefer the safe `: unknown` for a `{{method}}`{{append}} callback variable. The thrown error may be nullable, or may not have the expected shape.'
	'wrongRestTypeAnnotationSuggestion':      'Change existing type annotation to `: [unknown]`.'
	'wrongTypeAnnotationSuggestion':          'Change existing type annotation to `: unknown`.'
}

// UuiccvCall is a `x.catch(handler)` or `x.then(…, handler)` call: the object of its callee and the
// functions collectFlaggedNodes finds in the handler argument.
struct UuiccvCall {
	callee    C.TSNode
	object    C.TSNode
	method    string
	functions []C.TSNode
}

fn (mut c Checker) lint_use_unknown_in_catch_callback_variable(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut calls := []UuiccvCall{}
	for node in c.nodes_of_kind(root, c'call_expression') {
		args := call_arguments(node) or { continue }
		callee := unwrap_parens(node_field(node, 'function') or { continue })
		// The callee must be a MemberExpression: a parenthesized optional chain is a ChainExpression.
		if !is_member(callee) || is_estree_chain_root(callee) {
			continue
		}
		method := c.static_member_name(callee) or { continue }
		index := match method {
			'catch' { 0 }
			'then' { 1 }
			else { continue }
		}
		// The argument to check and the ones before it must not be spreads.
		if args.len < index + 1 || args[..index + 1].any(node_kind(it) == 'spread_element') {
			continue
		}
		mut functions := []C.TSNode{}
		uuiccv_collect_functions(args[index], mut functions, 0)
		if functions.len == 0 {
			continue
		}
		object := node_field(callee, 'object') or { continue }
		calls << UuiccvCall{
			callee:    callee
			object:    unwrap_parens(object)
			method:    method
			functions: functions
		}
	}
	mut spans := []Span{}
	for call in calls {
		spans << node_span(call.object)
		spans << call.functions.map(node_span(it))
		// The callee is the node isThenableType is asked at.
		spans << Span{
			...node_span(call.callee)
			optional: true
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for call in calls {
		object_type := c.node_type(call.object) or { continue }
		if !c.is_thenable(object_type, c.symbol_location(call.callee))! {
			continue
		}
		for function in call.functions {
			t := c.node_type(function) or { continue }
			if !c.uuiccv_is_flaggable_handler(t)! {
				continue
			}
			report := uuiccv_refine_report(function)
			mut suggestions := []Suggestion{}
			if report.suggestion != '' {
				_, suggestion := c.suggestion(report.suggestion, map[string]string{}, report.fixes)!
				suggestions << suggestion
			}
			findings << Finding{
				stmt:        report.at
				message_id:  report.message_id
				data:        {
					'method': call.method
					'append': if call.method == 'then' { ' rejection' } else { '' }
				}
				suggestions: suggestions
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += calls.len
	return findings
}

// uuiccv_collect_functions ports collectFlaggedNodes without the type check: the function
// expressions the argument may evaluate to, through logical and conditional expressions and the
// last expression of a sequence.
fn uuiccv_collect_functions(n C.TSNode, mut out []C.TSNode, depth int) {
	if depth > max_expression_depth {
		return
	}
	node := unwrap_parens(n)
	match node_kind(node) {
		'binary_expression' {
			if estree_binary_kind(node) == 'LogicalExpression' {
				if left := node_field(node, 'left') {
					uuiccv_collect_functions(left, mut out, depth + 1)
				}
				if right := node_field(node, 'right') {
					uuiccv_collect_functions(right, mut out, depth + 1)
				}
			}
		}
		'sequence_expression' {
			expressions := named_children(node)
			if expressions.len > 0 {
				uuiccv_collect_functions(expressions.last(), mut out, depth + 1)
			}
		}
		'ternary_expression' {
			if consequence := node_field(node, 'consequence') {
				uuiccv_collect_functions(consequence, mut out, depth + 1)
			}
			if alternative := node_field(node, 'alternative') {
				uuiccv_collect_functions(alternative, mut out, depth + 1)
			}
		}
		'arrow_function', 'function_expression', 'generator_function' {
			out << node
		}
		else {}
	}
}

// uuiccv_is_flaggable_handler ports isFlaggableHandlerType: some call signature of the type has a
// first parameter (the element of a rest one) that is not `unknown`.
fn (mut c Checker) uuiccv_is_flaggable_handler(t TypeResponse) !bool {
	for part in c.constituents(t)! {
		for signature in c.uuiccv_call_signatures(part)! {
			params := c.signature_parameters(signature)!
			if params.len == 0 {
				continue
			}
			mut first := c.symbol_type(params[0].id)!
			// isRestParameterDeclaration: the first parameter is the rest one when it is the only one.
			if signature.flags & signature_flag_has_rest_parameter != 0 && params.len == 1 {
				if !c.is_array(first)! && !c.is_tuple(first)! {
					// A rest parameter that is not an array or a tuple.
					return true
				}
				elements := c.type_args(first)!
				if elements.len == 0 {
					// `...args: []`: typescript-eslint throws here (see the header).
					return true
				}
				first = elements[0]
			}
			if first.flags & type_flag_unknown == 0 {
				return true
			}
		}
	}
	return false
}

// uuiccv_call_signatures ports getCallSignaturesOfType of ts-api-utils for a union part: those of
// the type or, for an intersection, those of its only part with call signatures.
fn (mut c Checker) uuiccv_call_signatures(t TypeResponse) ![]SignatureResponse {
	if t.flags & type_flag_intersection == 0 {
		return c.signatures_of(t, signature_kind_call)!
	}
	mut found := []SignatureResponse{}
	for part in c.members_of(t)! {
		signatures := c.uuiccv_call_signatures(part)!
		if signatures.len != 0 {
			if found.len != 0 {
				// More than one part with call signatures: they cannot be merged.
				return []SignatureResponse{}
			}
			found = signatures.clone()
		}
	}
	return found
}

// UuiccvReport is what refineReportIfPossible overrides in a report: its node and messageId, and
// its suggestion ('' without one) with the fixes of its fixer.
struct UuiccvReport {
	at         Ident
	message_id string
	suggestion string
	fixes      []Fix
}

// uuiccv_refine_report ports refineReportIfPossible: the report goes to the first parameter of the
// function, with a more precise message for a destructuring pattern and, for an identifier or a
// rest element, the suggestion to annotate it as `unknown` (`[unknown]`) or to change its
// annotation.
fn uuiccv_refine_report(function C.TSNode) UuiccvReport {
	mut first := ?C.TSNode(none)
	// `e => …`: isParenlessArrowFunction.
	mut parenless := false
	if single := node_field(function, 'parameter') {
		first = single
		parenless = true
	} else if parameters := node_field(function, 'parameters') {
		params := named_children(parameters)
		if params.len > 0 {
			first = params[0]
		}
	}
	param := first or {
		return UuiccvReport{
			at:         position_of(function)
			message_id: 'useUnknown'
		}
	}
	// The inner variable: the pattern of the parameter (the left side of a default value).
	inner := node_field(param, 'pattern') or { param }
	annotation := node_field(param, 'type')
	match node_kind(inner) {
		'array_pattern' {
			return UuiccvReport{
				at:         position_of(param)
				message_id: 'useUnknownArrayDestructuringPattern'
			}
		}
		'object_pattern' {
			return UuiccvReport{
				at:         position_of(param)
				message_id: 'useUnknownObjectDestructuringPattern'
			}
		}
		'rest_pattern' {
			if type_annotation := annotation {
				return UuiccvReport{
					at:         position_of(param)
					message_id: 'useUnknown'
					suggestion: 'wrongRestTypeAnnotationSuggestion'
					fixes:      [fix_replace(type_annotation, ': [unknown]')]
				}
			}
			return UuiccvReport{
				at:         position_of(param)
				message_id: 'useUnknown'
				suggestion: 'addUnknownRestTypeAnnotationSuggestion'
				fixes:      [fix_insert_after(inner, ': [unknown]')]
			}
		}
		else {}
	}
	// An Identifier (`this` included).
	if type_annotation := annotation {
		return UuiccvReport{
			at:         position_of(param)
			message_id: 'useUnknown'
			suggestion: 'wrongTypeAnnotationSuggestion'
			fixes:      [fix_replace(type_annotation, ': unknown')]
		}
	}
	// The range of an optional Identifier includes its `?`.
	mut end := node_end(inner)
	for child in children(param) {
		if node_kind(child) == '?' {
			end = node_end(child)
		}
	}
	return UuiccvReport{
		at:         position_of(param)
		message_id: 'useUnknown'
		suggestion: 'addUnknownTypeAnnotationSuggestion'
		fixes:      if parenless {
			[fix_insert_before(inner, '('), fix_insert_at(end, ': unknown)')]
		} else {
			[fix_insert_at(end, ': unknown')]
		}
	}
}
