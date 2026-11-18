module rules

import estree

// Port of the `svelte/derived-has-same-inputs-outputs` rule of eslint-plugin-svelte 3.24.1: the
// callback of `derived` of `svelte/store` names its parameter after the store it gets, with a `$`
// (`derived(a, ($a) => …)`, `derived([a, b], ([$a, $b]) => …)`); the report is on the parameter,
// with a suggestion that renames it and its references unless the new name is referenced or
// declared in the callback's scope. It has no conditions: it lints every file.

const svdhsio_messages = {
	'unexpected':  "The argument name should be '{{name}}'."
	'renameParam': 'Rename the parameter from {{oldName}} to {{newName}}.'
}

// svdhsio_check reports a parameter `param` (an Identifier) that should be named `expected`.
fn (mut c Checker) svdhsio_check(root C.TSNode, t &estree.EsTree, body C.TSNode, param int, expected string, mut findings []Finding) {
	name := t.string_of(param, .name) or { return }
	if name == expected {
		return
	}
	has_conflict, variable := c.svsc_find_variable_for_replacement(root, body, name, expected)
	mut suggestions := []Suggestion{}
	if !has_conflict {
		if fix := c.svsc_rename_fix(root, t.nodes[param].start, t.nodes[param].end, variable,
			expected)
		{
			suggestions << Suggestion{
				message_id: 'renameParam'
				data:       {
					'oldName': name
					'newName': expected
				}
				fix:        fix
			}
		}
	}
	findings << Finding{
		stmt:        c.es_tree_position(t, param)
		message_id:  'unexpected'
		data:        {
			'name': expected
		}
		suggestions: suggestions
	}
}

fn (mut c Checker) lint_svelte_derived_has_same_inputs_outputs(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	calls := c.svsc_store_calls(root, abs_path, ['derived'])
	if calls.len == 0 {
		return []
	}
	t := c.es_tree(root, abs_path) or { return [] }
	mut findings := []Finding{}
	for call in calls {
		args := t.list(call.node, .arguments) or { continue }
		if args.len < 2 || args[0] < 0 || args[1] < 0 {
			continue
		}
		input := args[0]
		fn_node := args[1]
		if t.typ(input) !in [.identifier, .array_expression]
			|| t.typ(fn_node) !in [.arrow_function_expression, .function_expression] {
			continue
		}
		params := t.list(fn_node, .params) or { continue }
		if params.len == 0 {
			continue
		}
		body := t.node(fn_node, .body) or { continue }
		body_ts := t.ts_node(body) or { continue }
		param := params[0]
		if t.typ(input) == .identifier {
			if t.typ(param) != .identifier {
				continue
			}
			c.svdhsio_check(root, t, body_ts, param, '$' + (t.string_of(input, .name) or { '' }), mut
				findings)
			continue
		}
		if t.typ(param) != .array_pattern {
			continue
		}
		elements := t.list(input, .elements) or { []int{} }
		for index, element in t.list(param, .elements) or { []int{} } {
			if element < 0 || t.typ(element) != .identifier || index >= elements.len {
				continue
			}
			arg := elements[index]
			if arg < 0 || t.typ(arg) != .identifier {
				continue
			}
			c.svdhsio_check(root, t, body_ts, element, '$' + (t.string_of(arg, .name) or { '' }), mut
				findings)
		}
	}
	return c.svsc_moved(findings)
}
