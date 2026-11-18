module rules

import time

// Port of the `vue/no-lifecycle-after-await` rule of eslint-plugin-vue 10.12.1 (no options): a
// call of a lifecycle hook of the composition API (imported from `vue` and its kin, or the global)
// in a `setup` function after an `await` of that function, unless it passes a target instance.

const vue_no_lifecycle_after_await_messages = {
	'forbidden': 'Lifecycle hooks are forbidden after an `await` expression.'
}

const vnlaa_hooks = ['onBeforeMount', 'onBeforeUnmount', 'onBeforeUpdate', 'onErrorCaptured',
	'onMounted', 'onRenderTracked', 'onRenderTriggered', 'onUnmounted', 'onUpdated', 'onActivated',
	'onDeactivated']

fn (mut c Checker) lint_vue_no_lifecycle_after_await(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	if s.objects.len == 0 {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	scopes := vaa_scopes(t)
	calls := c.vaa_setup_calls_after_await(t, s, &scopes)
	if calls.len == 0 {
		return findings
	}
	hooks := c.vue_composition_api_calls(root, t, vnlaa_hooks).map(it.call)
	for call in calls {
		stats.checked++
		if call !in hooks || (t.list(call, .arguments) or { []int{} }).len >= 2 {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, call)
			message_id: 'forbidden'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
