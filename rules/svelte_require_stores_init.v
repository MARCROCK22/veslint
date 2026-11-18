module rules

// Port of the `svelte/require-stores-init` rule of eslint-plugin-svelte 3.24.1: `writable` and
// `readable` of `svelte/store` need an initial value, `derived` three arguments, unless an argument
// is a spread. It has no conditions: it lints every file.

const svrsi_messages = {
	'storeDefaultValue': 'Always set a default value for svelte stores.'
}

fn (mut c Checker) lint_svelte_require_stores_init(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	calls := c.svsc_store_calls(root, abs_path, ['writable', 'readable', 'derived'])
	if calls.len == 0 {
		return []
	}
	t := c.es_tree(root, abs_path) or { return [] }
	mut findings := []Finding{}
	for call in calls {
		args := t.list(call.node, .arguments) or { continue }
		min_args := match call.name {
			'writable', 'readable' { 1 }
			'derived' { 3 }
			else { 0 }
		}
		if args.len >= min_args || args.any(it >= 0 && t.typ(it) == .spread_element) {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, call.node)
			message_id: 'storeDefaultValue'
		}
	}
	return c.svsc_moved(findings)
}
