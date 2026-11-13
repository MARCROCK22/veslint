module rules

import time

// Port of the `unicorn/throw-new-error` rule of eslint-plugin-unicorn 64.0.0 (it has no options),
// with its fix.

const utne_messages = {
	'throw-new-error': 'Use `new` when creating an error.'
}

// utne_is_error_name tests /^(?:[A-Z][\da-z]*)*Error$/.
fn utne_is_error_name(name string) bool {
	if !name.ends_with('Error') {
		return false
	}
	prefix := name[..name.len - 5]
	return prefix == ''
		|| (prefix[0].is_capital() && prefix.bytes().all(it.is_letter() || it.is_digit()))
}

fn (mut c Checker) lint_unicorn_throw_new_error(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		callee := t.node(node, .callee) or { continue }
		name := match t.typ(callee) {
			.identifier {
				t.string_of(callee, .name) or { '' }
			}
			.member_expression {
				property := t.node(callee, .property) or { continue }
				if (t.flag(callee, .computed) or { false }) || t.typ(property) != .identifier {
					continue
				}
				t.string_of(property, .name) or { '' }
			}
			else {
				continue
			}
		}
		if !utne_is_error_name(name) {
			continue
		}
		// Effect's `Data.TaggedError`.
		if un_is_member(t, callee, objects: ['Data'], properties: ['TaggedError'], computed: false) {
			continue
		}
		has_fix, fix := c.merge_fixes(c.un_switch_call_to_new(t, tokens, node))!
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'throw-new-error'
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
