module rules

// Port of the `svelte/require-event-dispatcher-types` rule of eslint-plugin-svelte 3.24.1. Its only
// condition is `{ svelteVersions: ['3/4'] }`: createRule gives ESLint no listeners when the Svelte
// the plugin loads is another major, and eslint-plugin-svelte 3.24.1 runs with Svelte 5 (the one
// veslint reads), so the rule reports nothing. With Svelte 3 or 4 it would report the calls of
// `createEventDispatcher` imported from `svelte` without type arguments in a component with a
// TypeScript script.

const svredt_messages = {
	'missingTypeParameter': 'Type parameters missing for the `createEventDispatcher` function call.'
}

fn (mut c Checker) lint_svelte_require_event_dispatcher_types(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	return []
}
