module rules

import json2
import time
import treesitter { named_children, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `preserve-caught-error` rule of ESLint 10.15.0, with its options and its suggestions.

const pce_messages = {
	'missingCause':           'There is no `cause` attached to the symptom error being thrown.'
	'incorrectCause':         'The symptom error is being thrown with an incorrect `cause`.'
	'includeCause':           'Include the original caught error as the `cause` of the symptom error.'
	'missingCatchErrorParam': 'The caught error is not accessible because the catch clause lacks the error parameter. Start referencing the caught error using the catch parameter.'
	'partiallyLostError':     'Re-throws cannot preserve the caught error as a part of it is being lost due to destructuring.'
	'caughtErrorShadowed':    'The caught error is being attached as `cause`, but is shadowed by a closer scoped redeclaration.'
}

const pce_error_types = ['Error', 'EvalError', 'RangeError', 'ReferenceError', 'SyntaxError',
	'TypeError', 'URIError', 'AggregateError']

// PceOptions are requireCatchParameter and errorClassNames (each class name with the 1-based
// position of its options argument: 2 for a name alone).
struct PceOptions {
	require_parameter bool
	error_classes     map[string]int
}

fn pce_options(options []json2.Any) !PceOptions {
	o := option_object(preserve_caught_error, options, ['requireCatchParameter', 'errorClassNames'])!
	mut classes := map[string]int{}
	if list := o.values['errorClassNames'] {
		if list !is []json2.Any {
			return error('option `errorClassNames` of `${preserve_caught_error}` must be a list')
		}
		for item in list.as_array() {
			if item is string {
				classes[item] = 2
			} else if item is map[string]json2.Any {
				name := item['name'] or { json2.Any('') }
				position := item['argumentPosition'] or { json2.Any(0) }
				classes[name.str()] = position.int()
			} else {
				return error('option `errorClassNames` of `${preserve_caught_error}` holds names or {name, argumentPosition}')
			}
		}
	}
	return PceOptions{
		require_parameter: o.bool_value('requireCatchParameter')!
		error_classes:     classes
	}
}

// pce_require_parameter reads requireCatchParameter (check_options).
fn pce_require_parameter(options []json2.Any) !bool {
	return pce_options(options)!.require_parameter
}

// PceCause is what getErrorCause finds: no options, options it cannot read, or the last `cause`.
struct PceCause {
	unknown  bool
	found    bool
	property C.TSNode // the Property
	value    C.TSNode
	multiple bool
}

fn (mut c Checker) lint_preserve_caught_error(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := pce_options(c.rule_options(preserve_caught_error))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['throw_statement'], []) {
		catch := pce_parent_catch(node) or { continue }
		expression := unwrap_parens(first_named(node) or { continue })
		kind := node_kind(expression)
		if kind !in ['new_expression', 'call_expression'] {
			continue
		}
		if kind == 'call_expression' {
			args_node := node_field(expression, 'arguments') or { continue }
			if node_kind(args_node) != 'arguments' || estree_type(expression) != 'CallExpression' {
				continue
			}
		}
		callee := unwrap_parens(node_field(expression, if kind == 'new_expression' {
			'constructor'
		} else {
			'function'
		}) or { continue })
		// isThrowingNewError: a built-in global error, or a class of errorClassNames (an identifier,
		// or the property of a non-computed member expression).
		built_in := node_kind(callee) == 'identifier' && c.text(callee) in pce_error_types
			&& c.es_is_global_reference(root, callee)
		target := if node_kind(callee) == 'member_expression' {
			node_field(callee, 'property') or { callee }
		} else {
			callee
		}
		class_name := c.text(target)
		if !built_in && !(node_kind(target) in ['identifier', 'property_identifier']
			&& class_name in o.error_classes) {
			continue
		}
		stats.checked++
		parameter := node_field(catch, 'parameter') or {
			if o.require_parameter {
				findings << Finding{
					stmt:       position_of(node)
					message_id: 'missingCatchErrorParam'
				}
			}
			continue
		}
		if node_kind(parameter) != 'identifier' {
			findings << Finding{
				stmt:       position_of(catch)
				message_id: 'partiallyLostError'
			}
			continue
		}
		caught := c.text(parameter)
		args := (call_arguments(expression) or { []C.TSNode{} }).filter(node_kind(it) != 'comment')
		options_index := if built_in {
			if class_name == 'AggregateError' { 2 } else { 1 }
		} else {
			o.error_classes[class_name] - 1
		}
		cause := c.pce_cause(options_index, args)
		if cause.unknown {
			continue
		}
		if !cause.found {
			mut suggestions := []Suggestion{}
			if fix := c.pce_missing_fix(root, expression, callee, args, caught, built_in, class_name,
				options_index)
			{
				_, suggestion := c.suggestion('includeCause', map[string]string{}, [fix])!
				suggestions << suggestion
			}
			findings << Finding{
				stmt:        position_of(node)
				message_id:  'missingCause'
				suggestions: suggestions
			}
			continue
		}
		value := unwrap_parens(cause.value)
		if !(node_kind(value) == 'identifier' && c.text(value) == caught) {
			mut suggestions := []Suggestion{}
			if !cause.multiple {
				property := cause.property
				fix := if node_kind(property) != 'pair' {
					fix_replace_range(node_start(property), c.es_end(property), 'cause: ${caught}')
				} else {
					fix_replace_range(node_start(value), c.es_end(value), caught)
				}
				_, suggestion := c.suggestion('includeCause', map[string]string{}, [fix])!
				suggestions << suggestion
			}
			// The ESTree value of a method is its FunctionExpression, from its parameters.
			at := if node_kind(value) == 'method_definition' {
				c.position_range(ner_function_start(value), c.es_end(value))
			} else {
				position_of(value)
			}
			findings << Finding{
				stmt:        at
				message_id:  'incorrectCause'
				suggestions: suggestions
			}
			continue
		}
		// The `cause` names the caught error unless a closer scope declares that name too.
		tree := c.scope_tree(root)
		mut scope := tree.get_scope(node)
		for scope >= 0 {
			if caught in tree.scopes[scope].set {
				break
			}
			scope = tree.scopes[scope].upper
		}
		if scope < 0 || node_key(tree.scopes[scope].block) != node_key(catch) {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'caughtErrorShadowed'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// pce_parent_catch ports findParentCatch: the catch clause around the node, not across a function
// or a static block.
fn pce_parent_catch(n C.TSNode) ?C.TSNode {
	mut current := n
	for {
		current = node_parent(current)?
		match node_kind(current) {
			'catch_clause' {
				return current
			}
			'function_declaration', 'function_expression', 'generator_function',
			'generator_function_declaration', 'arrow_function', 'method_definition',
			'class_static_block' {
				return none
			}
			else {}
		}
	}
	return none
}

// pce_cause ports getErrorCause: the `cause` of the options argument, at `index`.
fn (c &Checker) pce_cause(index int, args []C.TSNode) PceCause {
	for i, arg in args {
		if node_kind(arg) == 'spread_element' && i <= index {
			return PceCause{
				unknown: true
			}
		}
	}
	if index >= args.len {
		return PceCause{}
	}
	options := unwrap_parens(args[index])
	if node_kind(options) != 'object' {
		return PceCause{
			unknown: true
		}
	}
	properties := named_children(options).filter(node_kind(it) != 'comment')
	if properties.any(node_kind(it) == 'spread_element') {
		return PceCause{
			unknown: true
		}
	}
	causes := properties.filter((c.es_static_key_name(it) or { '' }) == 'cause')
	if causes.len == 0 {
		return PceCause{}
	}
	last := causes.last()
	value := if node_kind(last) == 'pair' { node_field(last, 'value') or { last } } else { last }
	return PceCause{
		found:    true
		property: last
		value:    value
		multiple: causes.len > 1
	}
}

// pce_insertion_after_parens ports findInsertionTokenAfterParens: from `first`, past the `)` that
// follow it and end at `last_end` or before; the end of the last one.
fn (c &Checker) pce_insertion_after_parens(tokens &SourceTokens, first SourceToken, last_end int) int {
	mut token := first
	for {
		next := tokens.after(token.end, false) or { break }
		if next.end > last_end || c.src[next.start..next.end] != ')' {
			break
		}
		token = next
	}
	return token.end
}

// pce_add_to_empty_call ports addArgumentsToEmptyCall: inside the `()` after the callee, or a new
// `(…)` after the callee and the parentheses around it.
fn (c &Checker) pce_add_to_empty_call(tokens &SourceTokens, expression C.TSNode, callee C.TSNode, text string) ?Fix {
	end := c.es_end(expression)
	callee_last := tokens.before(c.es_end(callee), false)?
	mut token := tokens.after(callee_last.end, false)?
	for token.end < end {
		if c.src[token.start..token.end] == '(' {
			return fix_insert_at(token.end, text)
		}
		token = tokens.after(token.end, false)?
	}
	return fix_insert_at(c.pce_insertion_after_parens(tokens, callee_last, end), '(${text})')
}

// pce_append_arguments ports appendArguments: after the last argument and the parentheses around
// it, before the token ahead of the closing `)`.
fn (c &Checker) pce_append_arguments(tokens &SourceTokens, expression C.TSNode, args []C.TSNode, text string) ?Fix {
	last_argument := tokens.before(c.es_end(unwrap_parens(args.last())), false)?
	closing := tokens.before(c.es_end(expression), false)?
	before_closing := tokens.before(closing.start, false)?
	return fix_insert_at(c.pce_insertion_after_parens(tokens, last_argument, before_closing.end),
		text)
}

// pce_existing_options ports fixExistingOptions (insertCauseIntoOptions for an object).
fn (c &Checker) pce_existing_options(tokens &SourceTokens, argument C.TSNode, caught string) ?Fix {
	options := unwrap_parens(argument)
	if node_kind(options) != 'object' {
		return none
	}
	properties := named_children(options).filter(node_kind(it) != 'comment')
	if properties.len == 0 {
		open := tokens.after(node_start(options), false)?
		return fix_insert_at(open.end, 'cause: ${caught}')
	}
	return fix_insert_at(c.es_end(properties.last()), ', cause: ${caught}')
}

// pce_missing_fix is the fix of the suggestion for a missing `cause`.
fn (mut c Checker) pce_missing_fix(root C.TSNode, expression C.TSNode, callee C.TSNode, args []C.TSNode, caught string, built_in bool, class_name string, options_index int) ?Fix {
	tokens := c.source_tokens(root)
	cause := '{ cause: ${caught} }'
	if built_in {
		// AggregateError: errors, message, options
		aggregate := class_name == 'AggregateError'
		if args.len == 0 {
			return c.pce_add_to_empty_call(tokens, expression, callee, if aggregate {
				'[], "", ${cause}'
			} else {
				'"", ${cause}'
			})
		}
		if aggregate && args.len == 1 {
			return c.pce_append_arguments(tokens, expression, args, ', "", ${cause}')
		}
		message_index := if aggregate { 1 } else { 0 }
		if args.len == message_index + 1 {
			return c.pce_append_arguments(tokens, expression, args, ', ${cause}')
		}
		return c.pce_existing_options(tokens, args[message_index + 1], caught)
	}
	// Custom error types: their signature is unknown, so no placeholders for missing arguments.
	if args.len < options_index {
		return none
	}
	if options_index >= args.len {
		if args.len > 0 {
			return c.pce_append_arguments(tokens, expression, args, ', ${cause}')
		}
		return c.pce_add_to_empty_call(tokens, expression, callee, cause)
	}
	return c.pce_existing_options(tokens, args[options_index], caught)
}
