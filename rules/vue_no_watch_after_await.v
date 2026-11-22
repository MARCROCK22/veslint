module rules

import estree
import time

// Port of the `vue/no-watch-after-await` rule of eslint-plugin-vue 10.12.1 (no options): a call
// of `watch` or `watchEffect` of the composition API in a `setup` function after an `await` of
// that function, unless its stop handle may be used.

const vue_no_watch_after_await_messages = {
	'forbidden': '`watch` is forbidden after an `await` expression.'
}

fn (mut c Checker) lint_vue_no_watch_after_await(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
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
	watches := c.vue_composition_api_calls(root, t, ['watch', 'watchEffect']).map(it.call)
	for call in calls {
		stats.checked++
		if call !in watches || vnwaa_is_maybe_used_stop_handle(t, call) {
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

// vnwaa_is_maybe_used_stop_handle ports isMaybeUsedStopHandle.
fn vnwaa_is_maybe_used_stop_handle(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	return match t.typ(parent) {
		.variable_declarator, .assignment_expression, .call_expression, .property,
		.array_expression {
			true
		}
		.chain_expression {
			vnwaa_is_maybe_used_stop_handle(t, parent)
		}
		else {
			false
		}
	}
}
