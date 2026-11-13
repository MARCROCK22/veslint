module rules

import time

// Port of the `unicorn/new-for-builtins` rule of eslint-plugin-unicorn 64.0.0 (it has no options),
// with its fixes and its suggestion, on the ReferenceTracker of eslint_utils.v.

const unfb_messages = {
	'enforce':         'Use `new {{name}}()` instead of `{{name}}()`.'
	'disallow':        'Use `{{name}}()` instead of `new {{name}}()`.'
	'error-date':      'Use `String(new Date())` instead of `Date()`.'
	'suggestion-date': 'Switch to `String(new Date())`.'
}

// unfb_enforce_new and unfb_disallow_new are enforceNew and disallowNew of utils/builtins.js.
const unfb_enforce_new = ['Object', 'Array', 'ArrayBuffer', 'DataView', 'Date', 'Error', 'Function',
	'Map', 'WeakMap', 'Set', 'WeakSet', 'Promise', 'RegExp', 'SharedArrayBuffer', 'Proxy', 'WeakRef',
	'FinalizationRegistry', 'Int8Array', 'Uint8Array', 'Uint8ClampedArray', 'Int16Array', 'Uint16Array',
	'Int32Array', 'Uint32Array', 'Float16Array', 'Float32Array', 'Float64Array', 'BigInt64Array',
	'BigUint64Array']
const unfb_disallow_new = ['BigInt', 'Boolean', 'Number', 'String', 'Symbol']

fn (mut c Checker) lint_unicorn_new_for_builtins(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut construct := map[string]EsTrace{}
	for name in unfb_disallow_new {
		construct[name] = EsTrace{
			construct: true
		}
	}
	for traced in c.es_global_references(root, construct) {
		stats.checked++
		node := c.es_index_of(t, traced.node) or { continue }
		name := traced.path[0]
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
	mut call := map[string]EsTrace{}
	for name in unfb_enforce_new {
		call[name] = EsTrace{
			call: true
		}
	}
	for traced in c.es_global_references(root, call) {
		stats.checked++
		node := c.es_index_of(t, traced.node) or { continue }
		name := traced.path[0]
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
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
