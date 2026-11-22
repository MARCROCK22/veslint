module rules

import time

// Port of the `unicorn/throw-new-error` rule of eslint-plugin-unicorn 79.0.0 (it has no options),
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

fn (mut c Checker) lint_unicorn_throw_new_error(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		// Decorators, template tags, and calls used as callees rely on the return value; `new`
		// produces the constructed instance instead.
		parent := t.nodes[node].parent
		if parent >= 0 && (t.typ(parent) == .decorator
			|| (t.typ(parent) == .tagged_template_expression && t.node(parent, .tag) or { -1 } == node)
			|| (t.typ(parent) == .call_expression && t.node(parent, .callee) or { -1 } == node)) {
			continue
		}
		callee := t.node(node, .callee) or { continue }
		// `new` cannot be applied to an optional-chained call (`Error?.()`, `lib?.Error()`).
		if (t.flag(node, .optional) or { false }) || unb_has_optional_chain_element(t, callee) {
			continue
		}
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
		if type_ := c.unb_type_of(t, node, abs_path, mut stats) {
			if c.signatures_of(type_, signature_kind_call)!.len > 0
				|| c.signatures_of(type_, signature_kind_construct)!.len > 0 {
				continue
			}
		}
		has_fix, fix := c.merge_fixes(c.unb_switch_call_to_new(t, tokens, node))!
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
