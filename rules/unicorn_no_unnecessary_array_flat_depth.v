module rules

import time

// Port of the `unicorn/no-unnecessary-array-flat-depth` rule of eslint-plugin-unicorn 79.0.0 (it
// has no options), with its fix.

const unuafd_messages = {
	'no-unnecessary-array-flat-depth': 'Passing `1` as the `depth` argument is unnecessary.'
}

fn (mut c Checker) lint_unicorn_no_unnecessary_array_flat_depth(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := &UnbTypeContext{
		root:     root
		abs_path: abs_path
		stats:    unsafe { &stats }
	}
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !un_is_method_call(t, node, methods: ['flat'], arguments_length: 1, optional_call: false) {
			continue
		}
		one := (t.list(node, .arguments) or { continue })[0]
		value := t.get(one, .value)
		if t.typ(one) != .literal || !(value is f64 && value == 1) {
			continue
		}
		if c.unb_should_skip_known_non_array_receiver(t, t.node(t.node(node, .callee) or { continue }, .object) or {
			continue
		}, mut ctx) {
			continue
		}
		// `flat()` defaults to a depth of 1: the whole argument list goes, unless a comment in it
		// has to stay, and then only the argument goes.
		call_tokens := c.un_call_tokens(t, tokens, node) or { continue }
		fix := if tokens.comments_inside(call_tokens.opening.start, call_tokens.closing.end).len > 0 {
			c.unb_remove_argument(t, tokens, one) or { continue }
		} else {
			fix_replace_range(call_tokens.opening.start, call_tokens.closing.end, '()')
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, one)
			message_id: 'no-unnecessary-array-flat-depth'
			has_fix:    true
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
