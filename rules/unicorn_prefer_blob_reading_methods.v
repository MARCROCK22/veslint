module rules

import time

// Port of the `unicorn/prefer-blob-reading-methods` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options).

const upbrm_messages = {
	'error': 'Prefer `Blob#{{replacement}}()` over `FileReader#{{method}}(blob)`.'
}

fn (mut c Checker) lint_unicorn_prefer_blob_reading_methods(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !un_is_method_call(t, node,
			methods:          ['readAsText', 'readAsArrayBuffer']
			arguments_length: 1
			optional_call:    false
			optional_member:  false
		) {
			continue
		}
		method := t.node(t.node(node, .callee) or { continue }, .property) or { continue }
		name := t.string_of(method, .name) or { continue }
		findings << Finding{
			stmt:       c.es_tree_position(t, method)
			message_id: 'error'
			data:       {
				'method':      name
				'replacement': if name == 'readAsArrayBuffer' { 'arrayBuffer' } else { 'text' }
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
