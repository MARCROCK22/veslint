module rules

import time
import tsgo { SignatureResponse, TypeResponse }
import treesitter { first_named_child, has_child_kind, node_end, node_field, node_kind, node_parent, nodes_of_kind, position_of }

// Port of the `no-unsafe-return` rule of typescript-eslint 8.62.0 (it has no options). Limits of
// the port: internals.md, "Rules" section.

const nur_messages = {
	'unsafeReturn':           'Unsafe return of a value of type {{type}}.'
	'unsafeReturnAssignment': 'Unsafe return of type `{{sender}}` from function with return type `{{receiver}}`.'
	'unsafeReturnThis':       'Unsafe return of a value of type `{{type}}`. `this` is typed as `any`.\nYou can try to fix this by turning on the `noImplicitThis` compiler option, or adding a `this` parameter to the function.'
}

// ReturnValue is a value a function returns: the ESTree node (without parentheses), where to
// report (the `return`, or the body of an arrow) and the function.
struct ReturnValue {
	node      C.TSNode
	reporting C.TSNode
	func      C.TSNode
}

// Functions whose type, for typescript-eslint, is the contextual one: TypeScript's
// FunctionExpression and ArrowFunction.
const function_expression_kinds = ['function_expression', 'generator_function', 'arrow_function']

fn (mut c Checker) lint_no_unsafe_return(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut values := []ReturnValue{}
	for ret in c.nodes_of_kind(root, c'return_statement') {
		arg := first_named_child(ret) or { continue }
		f := enclosing_function(ret) or { continue }
		values << ReturnValue{
			node:      unwrap_parens(arg)
			reporting: ret
			func:      f
		}
	}
	// `ArrowFunctionExpression > :not(BlockStatement).body`
	for f in c.nodes_of_kind(root, c'arrow_function') {
		body := node_field(f, 'body') or { continue }
		if node_kind(body) != 'statement_block' {
			node := unwrap_parens(body)
			values << ReturnValue{
				node:      node
				reporting: node
				func:      f
			}
		}
	}
	mut spans := []Span{}
	for v in values {
		spans << node_span(v.node)
		spans << function_span(v.func)
		if node_kind(v.func) in function_expression_kinds {
			spans << c.util_contextual_spans(v.func)
		}
	}
	spans << c.this_spans(values.map(it.node))
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for v in values {
		findings << c.check_return(v)!
	}
	findings.sort_with_compare(compare_findings)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += values.len
	return findings
}

// function_span is the TypeScript node of a function: `export` and `export default` are modifiers
// of a function declaration (also of the anonymous one, which tree-sitter reads as an
// expression), and the decorators of a method are part of the member.
fn function_span(f C.TSNode) Span {
	kind := node_kind(f)
	if kind == 'method_definition' {
		return member_span(f)
	}
	if kind in ['function_declaration', 'generator_function_declaration', 'function_expression',
		'generator_function'] {
		if parent := node_parent(f) {
			if node_kind(parent) == 'export_statement' {
				return Span{
					key:   node_key(f)
					first: parent
					end:   node_end(f)
				}
			}
		}
	}
	return node_span(f)
}

// check_return ports checkReturn; returns the finding, if any.
fn (mut c Checker) check_return(v ReturnValue) ![]Finding {
	t := c.node_type(v.node) or { return []Finding{} }
	any_type := c.discriminate_any(t, c.symbol_location(v.node))!
	// The type of a function expression does not change with the type its receiver expects
	// (`const f: () => Set<string> = () => new Set<any>()`): the contextual one is used.
	mut function_type := TypeResponse{}
	if node_kind(v.func) in function_expression_kinds {
		function_type = c.util_contextual_type(v.func)!
	}
	if function_type.is_null() {
		function_type = c.node_type(v.func) or { return []Finding{} }
	}
	call_signatures := c.call_signatures_of(function_type)!
	is_async := has_child_kind(v.func, 'async')
	// With an annotated return type that matches the returned one, the `any` is intentional.
	if _ := node_field(v.func, 'return_type') {
		for sig in call_signatures {
			sig_return := c.return_type(sig.id)!
			if t.id == sig_return.id
				|| c.type_flags(sig_return)! & (type_flag_any | type_flag_unknown) != 0 {
				return []Finding{}
			}
			if is_async {
				awaited_sig := c.awaited_type(sig_return)!
				awaited_return := c.awaited_type(t)!
				if c.awaited_same(awaited_return, awaited_sig)! || (awaited_sig.found
					&& c.awaited_flags(awaited_sig)! & (type_flag_any | type_flag_unknown) != 0) {
					return []Finding{}
				}
			}
		}
	}
	if any_type != .safe {
		// Returning `any` or `any[]` is allowed if the function returns `unknown` or `unknown[]`.
		for sig in call_signatures {
			function_return := c.return_type(sig.id)!
			if any_type == .any && c.is_unknown(function_return)! {
				return []Finding{}
			}
			if any_type == .any_array && c.is_unknown_array(function_return)! {
				return []Finding{}
			}
			awaited := c.awaited_type(function_return)!
			if any_type == .promise_any && awaited.found
				&& c.awaited_flags(awaited)! & type_flag_unknown != 0 {
				return []Finding{}
			}
		}
		if any_type == .promise_any && !is_async {
			return []Finding{}
		}
		constrained := c.constrained(t)!
		type_text := if is_error_type(constrained) {
			'error'
		} else {
			match any_type {
				.any { '`any`' }
				.promise_any { '`Promise<any>`' }
				else { '`any[]`' }
			}
		}
		return [
			Finding{
				stmt:       position_of(v.reporting)
				message_id: if c.this_is_any(v.node)! { 'unsafeReturnThis' } else { 'unsafeReturn' }
				data:       {
					'type': type_text
				}
			},
		]
	}
	signatures := c.signatures_of(function_type, signature_kind_call)!
	if signatures.len == 0 {
		return []Finding{}
	}
	pair := c.unsafe_assignment(t, c.return_type(signatures[0].id)!, v.node)!
	if !pair.found {
		return []Finding{}
	}
	return [
		Finding{
			stmt:       position_of(v.reporting)
			message_id: 'unsafeReturnAssignment'
			data:       {
				'sender':   c.client.type_to_string(c.snapshot, c.project, pair.sender.id)!
				'receiver': c.client.type_to_string(c.snapshot, c.project, pair.receiver.id)!
			}
		},
	]
}

// call_signatures_of ports getCallSignaturesOfType from ts-api-utils: for a union, the signatures
// of all the parts; for an intersection, those of the only part that has some.
fn (mut c Checker) call_signatures_of(t TypeResponse) ![]SignatureResponse {
	if t.flags & type_flag_union != 0 {
		mut out := []SignatureResponse{}
		for member in c.members_of(t)! {
			out << c.call_signatures_of(member)!
		}
		return out
	}
	if t.flags & type_flag_intersection != 0 {
		mut found := []SignatureResponse{}
		for member in c.members_of(t)! {
			sigs := c.call_signatures_of(member)!
			if sigs.len != 0 {
				if found.len != 0 {
					return []SignatureResponse{}
				}
				found = sigs.clone()
			}
		}
		return found
	}
	return c.signatures_of(t, signature_kind_call)!
}
