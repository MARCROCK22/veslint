module rules

import time

// Port of the `unicorn/new-for-builtins` rule of eslint-plugin-unicorn 79.0.0 (it has no options),
// with its fixes and its suggestion, on the ReferenceTracker of eslint_utils.v.

const unfb_messages = {
	'enforce':         'Use `new {{name}}()` instead of `{{name}}()`.'
	'disallow':          'Use `{{name}}()` instead of `new {{name}}()`.'
	'disallowCallOrNew': '`{{name}}` is not a function or constructor.'
	'error-date':      'Use `String(new Date())` instead of `Date()`.'
	'suggestion-date': 'Switch to `String(new Date())`.'
}

// unfb_enforce_new, unfb_disallow_new and unfb_disallow_call_or_new are enforceNew, disallowNew and
// disallowCallOrNew of utils/builtins.js.
const unfb_enforce_new = ['Object', 'Array', 'ArrayBuffer', 'DataView', 'Date', 'Function', 'Map',
	'WeakMap', 'Set', 'WeakSet', 'Promise', 'RegExp', 'SharedArrayBuffer', 'Proxy', 'WeakRef',
	'FinalizationRegistry', 'DisposableStack', 'AsyncDisposableStack', 'Error', 'EvalError',
	'RangeError', 'ReferenceError', 'SyntaxError', 'TypeError', 'URIError', 'AggregateError',
	'SuppressedError', 'Intl.Collator', 'Intl.DateTimeFormat', 'Intl.DisplayNames',
	'Intl.DurationFormat', 'Intl.ListFormat', 'Intl.Locale', 'Intl.NumberFormat', 'Intl.PluralRules',
	'Intl.RelativeTimeFormat', 'Intl.Segmenter', 'Temporal.Duration', 'Temporal.Instant',
	'Temporal.PlainDate', 'Temporal.PlainDateTime', 'Temporal.PlainMonthDay', 'Temporal.PlainTime',
	'Temporal.PlainYearMonth', 'Temporal.ZonedDateTime', 'WebAssembly.Module', 'WebAssembly.Instance',
	'WebAssembly.Memory', 'WebAssembly.Table', 'WebAssembly.Global', 'WebAssembly.Tag',
	'WebAssembly.Exception', 'WebAssembly.CompileError', 'WebAssembly.LinkError',
	'WebAssembly.RuntimeError', 'Int8Array', 'Uint8Array', 'Uint8ClampedArray', 'Int16Array',
	'Uint16Array', 'Int32Array', 'Uint32Array', 'Float16Array', 'Float32Array', 'Float64Array',
	'BigInt64Array', 'BigUint64Array']
const unfb_disallow_new = ['BigInt', 'Boolean', 'Number', 'String', 'Symbol']
const unfb_disallow_call_or_new = ['Temporal.Now', 'WebAssembly', 'WebAssembly.JSTag']

fn (mut c Checker) lint_unicorn_new_for_builtins(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for traced in c.es_global_references(root, un_trace_map(unfb_disallow_new, 'construct')) {
		stats.checked++
		node := c.es_index_of(t, traced.node) or { continue }
		name := traced.path.join('.')
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'disallow'
			data:       {
				'name': name
			}
		}
		if name !in ['String', 'Boolean', 'Number'] {
			has_fix, fix := c.merge_fixes(c.un_switch_new_to_call(t, tokens, node))!
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
		findings << finding
	}
	for traced in c.es_global_references(root, un_trace_map(unfb_enforce_new, 'call')) {
		stats.checked++
		node := c.es_index_of(t, traced.node) or { continue }
		// An optional chain (`Array?.()`, `Intl?.DateTimeFormat()`) can not become a `new`
		// expression, which can not be optional.
		if (t.flag(node, .optional) or { false })
			|| un_has_optional_chain_element(t, t.node(node, .callee) or { -1 }) {
			continue
		}
		name := traced.path.join('.')
		if name == 'Object' {
			parent := t.nodes[node].parent
			if t.typ(parent) == .binary_expression
				&& (t.string_of(parent, .operator) or { '' }) in ['===', '!==']
				&& (t.node(parent, .left) or { -1 } == node || t.node(parent, .right) or { -1 } == node) {
				continue
			}
		}
		if name == 'Date' {
			mut fixes := [fix_replace_range(t.nodes[node].start, t.nodes[node].end, 'String(new Date())')]
			fixes << c.un_fix_space_around_keyword(t, tokens, node)
			has_fix, fix := c.merge_fixes(fixes)!
			no_comments := tokens.comments_inside(t.nodes[node].start, t.nodes[node].end).len == 0
			if no_comments && (t.list(node, .arguments) or { []int{} }).len == 0 {
				findings << Finding{
					stmt:       c.es_tree_position(t, node)
					message_id: 'error-date'
					has_fix:    has_fix
					fix:        fix
				}
			} else {
				findings << Finding{
					stmt:        c.es_tree_position(t, node)
					message_id:  'error-date'
					suggestions: [
						Suggestion{
							message_id: 'suggestion-date'
							fix:        fix
						},
					]
				}
			}
			continue
		}
		has_fix, fix := c.merge_fixes(c.un_switch_call_to_new(t, tokens, node))!
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'enforce'
			data:       {
				'name': name
			}
			has_fix:    has_fix
			fix:        fix
		}
	}
	for kind in ['call', 'construct'] {
		for traced in c.es_global_references(root, un_trace_map(unfb_disallow_call_or_new, kind)) {
			stats.checked++
			node := c.es_index_of(t, traced.node) or { continue }
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'disallowCallOrNew'
				data:       {
					'name': traced.path.join('.')
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
