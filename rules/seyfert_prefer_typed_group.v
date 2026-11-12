module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `prefer-typed-group` rule of @slipher/eslint-plugin 1.1.0 (it has no options): a
// seyfert `@Group(name)` with a single argument that is not a spread.

const sy_ptg_messages = {
	'preferTypedGroup': 'Prefer the two-argument `@Group(groups, name)` overload so the group name is validated against the declared groups.'
}

fn (mut c Checker) lint_seyfert_prefer_typed_group(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut decorators := []C.TSNode{}
	mut callees := []C.TSNode{}
	for decorator in c.nodes_of_kind(root, c'decorator') {
		call := sy_decorator_call(decorator) or { continue }
		arguments := call_arguments(call) or { continue }
		if arguments.len != 1 || node_kind(arguments[0]) == 'spread_element' {
			continue
		}
		callee := node_field(call, 'function') or { continue }
		decorators << decorator
		callees << callee
	}
	c.resolve_node_types(callees, abs_path, mut stats)!
	c.sy_prefetch_symbols(callees)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for i, decorator in decorators {
		if c.sy_is_seyfert(c.sy_symbol_at(callees[i])!, 'Group')! {
			findings << Finding{
				stmt:       position_of(decorator)
				message_id: 'preferTypedGroup'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += decorators.len
	return findings
}
