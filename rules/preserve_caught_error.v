module rules

import json2
import time
import treesitter { named_children, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `preserve-caught-error` rule of ESLint 10.6.0, with its option and its suggestions.

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

// pce_require_parameter reads requireCatchParameter.
fn pce_require_parameter(options []json2.Any) !bool {
	o := option_object(preserve_caught_error, options, ['requireCatchParameter'])!
	return o.bool_value('requireCatchParameter')!
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
	require_parameter := pce_require_parameter(c.rule_options(preserve_caught_error))!
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
		if node_kind(callee) != 'identifier' || c.text(callee) !in pce_error_types
			|| !c.es_is_global_reference(root, callee) {
			continue
		}
		stats.checked++
		parameter := node_field(catch, 'parameter') or {
			if require_parameter {
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
		cause := c.pce_cause(callee, args)
		if cause.unknown {
			continue
		}
		if !cause.found {
			mut suggestions := []Suggestion{}
			if fix := c.pce_missing_fix(root, expression, callee, args, caught) {
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

// pce_cause ports getErrorCause: the `cause` of the options argument.
fn (c &Checker) pce_cause(callee C.TSNode, args []C.TSNode) PceCause {
	index := if c.text(callee) == 'AggregateError' { 2 } else { 1 }
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

// pce_missing_fix is the fix of the suggestion for a missing `cause`.
fn (mut c Checker) pce_missing_fix(root C.TSNode, expression C.TSNode, callee C.TSNode, args []C.TSNode, caught string) ?Fix {
	tokens := c.source_tokens(root)
	paren := fn [mut c, tokens, expression, callee] () ?SourceToken {
		mut token := tokens.after(c.es_end(callee), false)?
		end := c.es_end(expression)
		for token.start < end {
			if c.src[token.start..token.end] == '(' {
				return token
			}
			token = tokens.after(token.end, false)?
		}
		return none
	}
	aggregate := c.text(callee) == 'AggregateError'
	first := if aggregate { '[], "", ' } else { '"", ' }
	if args.len == 0 {
		if token := paren() {
			return fix_insert_at(token.end, '${first}{ cause: ${caught} }')
		}
		return fix_insert_at(c.es_end(callee), '(${first}{ cause: ${caught} })')
	}
	message_index := if aggregate { 1 } else { 0 }
	if aggregate && args.len == 1 {
		return fix_insert_at(c.es_end(unwrap_parens(args[0])), ', "", { cause: ${caught} }')
	}
	if args.len == message_index + 1 {
		return fix_insert_at(c.es_end(unwrap_parens(args[message_index])), ', { cause: ${caught} }')
	}
	options := unwrap_parens(args[message_index + 1])
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
