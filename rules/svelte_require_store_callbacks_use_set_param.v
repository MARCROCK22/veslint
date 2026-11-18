module rules

// Port of the `svelte/require-store-callbacks-use-set-param` rule of eslint-plugin-svelte 3.24.1:
// the callback of `readable` and `writable` of `svelte/store` must have a first parameter named
// `set` (one that is not an identifier is left alone); the suggestion renames it (and its
// references), or adds `set` when there is none, unless `set` is referenced or declared in the
// callback's scope. It has no conditions: it lints every file.

const svrscusp_messages = {
	'unexpected':  'Store callbacks must use `set` param.'
	'updateParam': 'Rename parameter from {{oldName}} to `set`.'
	'addParam':    'Add a `set` parameter.'
}

fn (mut c Checker) lint_svelte_require_store_callbacks_use_set_param(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	calls := c.svsc_store_calls(root, abs_path, ['readable', 'writable'])
	if calls.len == 0 {
		return []
	}
	t := c.es_tree(root, abs_path) or { return [] }
	mut findings := []Finding{}
	for call in calls {
		args := t.list(call.node, .arguments) or { continue }
		if args.len < 2 || args[1] < 0 {
			continue
		}
		fn_node := args[1]
		if t.typ(fn_node) !in [.arrow_function_expression, .function_expression] {
			continue
		}
		params := t.list(fn_node, .params) or { []int{} }
		param := if params.len > 0 { params[0] } else { -1 }
		if param >= 0 && (t.typ(param) != .identifier
			|| (t.string_of(param, .name) or { '' }) == 'set') {
			continue
		}
		body := t.node(fn_node, .body) or { continue }
		body_ts := t.ts_node(body) or { continue }
		param_name := if param >= 0 { t.string_of(param, .name) or { '' } } else { '' }
		has_conflict, variable := c.svsc_find_variable_for_replacement(root, body_ts,
			if param >= 0 { param_name } else { '\x00' }, 'set')
		mut suggestions := []Suggestion{}
		if !has_conflict {
			if param >= 0 {
				// The parameter's own range: an identifier's annotation is part of it.
				if fix := c.svsc_rename_fix(root, t.nodes[param].start, t.nodes[param].end,
					variable, 'set')
				{
					suggestions << Suggestion{
						message_id: 'updateParam'
						data:       {
							'oldName': param_name
						}
						fix:        fix
					}
				}
			} else {
				tokens := c.source_tokens(root)
				mut at := t.nodes[body].start
				for {
					token := tokens.before(at, false) or { break }
					if token.kind == .punctuator && c.src[token.start..token.end] == '(' {
						suggestions << Suggestion{
							message_id: 'addParam'
							fix:        fix_insert_at(token.end, 'set')
						}
						break
					}
					at = token.start
				}
			}
		}
		findings << Finding{
			stmt:        c.es_tree_position(t, fn_node)
			message_id:  'unexpected'
			suggestions: suggestions
		}
	}
	return c.svsc_moved(findings)
}
