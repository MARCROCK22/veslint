module rules

import time
import tsgo { TypeResponse }
import treesitter { named_children, node_field, node_kind, nodes_of_kinds, position_of }

// Port of the `no-implied-eval` rule of typescript-eslint 8.62.0 (it has no options).

const nie_messages = {
	'noFunctionConstructor': 'Implied eval. Do not use the Function constructor to create functions.'
	'noImpliedEvalError':    'Implied eval. Consider passing a function.'
}

const nie_global_candidates = ['global', 'globalThis', 'window']
const nie_eval_like_functions = ['execScript', 'setImmediate', 'setInterval', 'setTimeout']

// SymbolFlags Function | Method of TypeScript 7.1.0-beta.
const nie_function_or_method = u32(16 | 8192)

// NieCall is a CallExpression or NewExpression whose callee has a name the rule checks.
struct NieCall {
	node    C.TSNode
	callee  C.TSNode
	name    string
	handler ?C.TSNode // the first argument
}

fn (mut c Checker) lint_no_implied_eval(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut calls := []NieCall{}
	mut spans := []Span{}
	for node in c.nodes_of_kinds(root, ['call_expression', 'new_expression'], []string{}) {
		callee_field := if node_kind(node) == 'call_expression' {
			'function'
		} else {
			'constructor'
		}
		callee := unwrap_parens(node_field(node, callee_field) or { continue })
		// Tagged templates and `import(…)` are not calls in ESTree.
		args := node_field(node, 'arguments')
		if a := args {
			if node_kind(a) != 'arguments' {
				continue
			}
		}
		if node_kind(callee) == 'import' {
			continue
		}
		name := c.nie_callee_name(callee) or { continue }
		mut handler := ?C.TSNode(none)
		if a := args {
			list := named_children(a)
			if list.len > 0 {
				handler = unwrap_parens(list[0])
			}
		}
		calls << NieCall{
			node:    node
			callee:  callee
			name:    name
			handler: handler
		}
		if name == 'Function' {
			spans << node_span(callee)
		}
		if h := handler {
			if name in nie_eval_like_functions {
				spans << node_span(h)
			}
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	scopes := c.scope_tree(root)
	for call in calls {
		if call.name == 'Function' {
			t := c.node_type(call.callee) or { TypeResponse{} }
			// Without a symbol (or without a type) it is reported; with one, if it is the
			// standard library FunctionConstructor.
			mut report := t.symbol == 0
			if !report {
				report = c.builtin_symbol_like(t, 'FunctionConstructor', 0)!
			}
			if report {
				findings << Finding{
					stmt:       position_of(call.node)
					message_id: 'noFunctionConstructor'
				}
				continue
			}
		}
		handler := call.handler or { continue }
		if call.name in nie_eval_like_functions && !c.nie_is_function(handler)!
			&& is_reference_to_global_function(scopes, call.node, call.name) {
			findings << Finding{
				stmt:       position_of(handler)
				message_id: 'noImpliedEvalError'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += calls.len
	return findings
}

// nie_callee_name ports getCalleeName: an identifier, or a property of `global`, `globalThis` or
// `window` that is an identifier (even computed, `window[x]`) or a string literal.
fn (c &Checker) nie_callee_name(callee C.TSNode) ?string {
	if estree_type(callee) == 'Identifier' {
		return c.identifier_name(callee)
	}
	if estree_type(callee) != 'MemberExpression' {
		return none
	}
	object := unwrap_parens(node_field(callee, 'object')?)
	if estree_type(object) != 'Identifier' || c.identifier_name(object) !in nie_global_candidates {
		return none
	}
	property := member_property(callee)?
	match node_kind(property) {
		'property_identifier', 'identifier', 'undefined' {
			return c.identifier_name(property)
		}
		'string' {
			text := c.text(property)
			return cooked_string(text[1..text.len - 1], false)
		}
		else {
			return none
		}
	}
}

// nie_is_function ports isFunction: function nodes are; literals and templates are not; a call is
// if it is a `.bind` or its type is a function; anything else by its type.
fn (mut c Checker) nie_is_function(n C.TSNode) !bool {
	match node_kind(n) {
		'arrow_function', 'function_expression', 'generator_function' {
			return true
		}
		'string', 'number', 'regex', 'true', 'false', 'null', 'template_string' {
			return false
		}
		else {}
	}
	if estree_type(n) == 'CallExpression' {
		if callee := node_field(n, 'function') {
			if c.nie_is_bind(unwrap_parens(callee)) {
				return true
			}
		}
	}
	return c.nie_is_function_type(n)!
}

// nie_is_bind ports isBind: the callee is `bind` or a member access whose property is.
fn (c &Checker) nie_is_bind(n C.TSNode) bool {
	if estree_type(n) == 'MemberExpression' {
		property := member_property(n) or { return false }
		return c.nie_is_bind(property)
	}
	return node_kind(n) in ['identifier', 'property_identifier'] && c.identifier_name(n) == 'bind'
}

// nie_is_function_type ports isFunctionType: the symbol of the type is a function or a method, the
// type is the standard library Function, or it has call signatures.
fn (mut c Checker) nie_is_function_type(n C.TSNode) !bool {
	t := c.node_type(n) or { return false }
	if t.symbol != 0 {
		symbol := c.symbol_of(t)!
		if !symbol.is_null() && symbol.flags & nie_function_or_method != 0 {
			return true
		}
	}
	if c.builtin_symbol_like(t, 'Function', 0)! {
		return true
	}
	return c.signatures_of(t, signature_kind_call)!.len > 0
}
