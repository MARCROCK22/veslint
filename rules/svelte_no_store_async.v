module rules

// Port of the `svelte/no-store-async` rule of eslint-plugin-svelte 3.24.1: the callback (second
// argument) of a store function of `svelte/store` must not be an async function; the report covers
// the five columns of its `async`. It has no conditions: it lints every file.

const svnsa_messages = {
	'unexpected': 'Do not pass async functions to svelte stores.'
}

fn (mut c Checker) lint_svelte_no_store_async(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	calls := c.svsc_store_calls(root, abs_path, ['writable', 'readable', 'derived'])
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
		if t.typ(fn_node) !in [.arrow_function_expression, .function_expression]
			|| !(t.flag(fn_node, .async) or { false }) {
			continue
		}
		start := t.nodes[fn_node].start
		findings << Finding{
			stmt:       c.position_range(start, start + 5)
			message_id: 'unexpected'
		}
	}
	return c.svsc_moved(findings)
}
