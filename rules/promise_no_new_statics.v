module rules

import time

// Port of the `promise/no-new-statics` rule of eslint-plugin-promise 7.3.0 (it has no options),
// with its fix.

const prm_no_new_statics_messages = {
	'avoidNewStatic': "Avoid calling 'new' on 'Promise.{{ name }}()'"
}

fn (mut c Checker) lint_promise_no_new_statics(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .new_expression || !t.visits(node) {
			continue
		}
		stats.checked++
		callee := prm_child(t, node, .callee)
		if callee < 0 || t.typ(callee) != .member_expression
			|| prm_name(t, prm_child(t, callee, .object)) != 'Promise' {
			continue
		}
		name := prm_name(t, prm_child(t, callee, .property))
		if name !in prm_promise_statics {
			continue
		}
		start := t.nodes[node].start
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'avoidNewStatic'
			data:       {
				'name': name
			}
			has_fix:    true
			// The range [node.range[0], node.range[0] + 'new '.length]: `new` and the UTF-16 unit
			// after it.
			fix:        fix_remove_range(start, start + 3 + prm_utf8_len(t.src, start + 3))
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// prm_utf8_len is the length in bytes of the character at `offset` (0 at the end of the text).
fn prm_utf8_len(src string, offset int) int {
	if offset >= src.len {
		return 0
	}
	b := src[offset]
	return if b < 0x80 {
		1
	} else if b >= 0xf0 {
		4
	} else if b >= 0xe0 {
		3
	} else {
		2
	}
}
