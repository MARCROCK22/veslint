module rules

import time
import treesitter { first_named_child, node_field, node_kind, nodes_of_kind, position_of }

// Port of the `no-unsafe-call` rule of typescript-eslint 8.62.0 (it has no options). Limits of the
// port: internals.md, "Rules" section.

const nuc_messages = {
	'errorCall':         'Unsafe call of a type that could not be resolved.'
	'errorCallThis':     'Unsafe call of a `this` type that could not be resolved.'
	'errorNew':          'Unsafe construction of a type that could not be resolved.'
	'errorTemplateTag':  'Unsafe use of a template tag whose type could not be resolved.'
	'unsafeCall':        'Unsafe call of {{type}} typed value.'
	'unsafeCallThis':    'Unsafe call of {{type}} typed value. `this` is typed as {{type}}.\nYou can try to fix this by turning on the `noImplicitThis` compiler option, or adding a `this` parameter to the function.'
	'unsafeNew':         'Unsafe construction of {{type}} typed value.'
	'unsafeTemplateTag': 'Unsafe use of {{type}} typed template tag.'
}

// UnsafeCall is a checked callee: the node whose type counts, where to report and which messages
// apply.
struct UnsafeCall {
	callee    C.TSNode
	reporting C.TSNode
	unsafe_id string
	error_id  string
}

fn (mut c Checker) lint_no_unsafe_call(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut calls := []UnsafeCall{}
	// `CallExpression > *.callee` and `TaggedTemplateExpression > *.tag` (in tree-sitter, a call whose
	// arguments are a template).
	for call in c.nodes_of_kind(root, c'call_expression') {
		callee := unwrap_parens(node_field(call, 'function') or { continue })
		// `import(…)` is an ImportExpression in ESTree, not a call.
		if node_kind(callee) == 'import' {
			continue
		}
		args := node_field(call, 'arguments') or { continue }
		tagged := node_kind(args) == 'template_string'
		calls << UnsafeCall{
			callee:    callee
			reporting: callee
			unsafe_id: if tagged { 'unsafeTemplateTag' } else { 'unsafeCall' }
			error_id:  if tagged { 'errorTemplateTag' } else { 'errorCall' }
		}
	}
	// NewExpression: reported at the whole `new`.
	for node in c.nodes_of_kind(root, c'new_expression') {
		calls << UnsafeCall{
			callee:    unwrap_parens(node_field(node, 'constructor') or { continue })
			reporting: node
			unsafe_id: 'unsafeNew'
			error_id:  'errorNew'
		}
	}
	// `await (x)` and `` await `x` `` outside an async function: TypeScript reads a call or a tagged
	// template on the `await` identifier (see await_reading).
	mut awaits := []C.TSNode{}
	for node in c.nodes_of_kind(root, c'await_expression') {
		operand := first_named_child(node) or { continue }
		if node_kind(operand) in ['parenthesized_expression', 'template_string'] {
			awaits << node
		}
	}
	mut spans := calls.map(node_span(it.callee))
	spans << c.this_spans(calls.map(it.callee))
	for node in awaits {
		spans << node_span(node)
		spans << await_keyword_span(node) or { continue }
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	for node in awaits {
		reading := c.await_reading(node)
		if reading != .call && reading != .tagged_template {
			continue
		}
		keyword := await_keyword(node) or { continue }
		tagged := reading == .tagged_template
		calls << UnsafeCall{
			callee:    keyword
			reporting: keyword
			unsafe_id: if tagged { 'unsafeTemplateTag' } else { 'unsafeCall' }
			error_id:  if tagged { 'errorTemplateTag' } else { 'errorCall' }
		}
	}
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for call in calls {
		t := c.node_type(call.callee) or { continue }
		typ := c.constrained(t)!
		if c.is_any(typ)! {
			this_any := c.this_is_any(call.callee)!
			unsafe_id := if this_any { 'unsafeCallThis' } else { call.unsafe_id }
			error_id := if this_any { 'errorCallThis' } else { call.error_id }
			findings << Finding{
				stmt:       position_of(call.reporting)
				message_id: if is_error_type(typ) { error_id } else { unsafe_id }
				data:       {
					'type': 'an `any`'
				}
			}
			continue
		}
		// A `Function` (or a subtype) is safe if it has construct signatures or, to call it, call
		// signatures (for `new`, one that does not return void).
		if !c.builtin_symbol_like(typ, 'Function', 0)! {
			continue
		}
		if c.signatures_of(typ, signature_kind_construct)!.len > 0 {
			continue
		}
		mut safe := false
		for sig in c.signatures_of(typ, signature_kind_call)! {
			if call.unsafe_id != 'unsafeNew' || c.return_type(sig.id)!.flags & type_flag_void == 0 {
				safe = true
				break
			}
		}
		if !safe {
			findings << Finding{
				stmt:       position_of(call.reporting)
				message_id: call.unsafe_id
				data:       {
					'type': 'a `Function`'
				}
			}
		}
	}
	findings.sort_with_compare(compare_findings)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += calls.len
	return findings
}
