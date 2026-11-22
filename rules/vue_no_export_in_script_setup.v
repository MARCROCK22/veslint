module rules

import time

// Port of the `vue/no-export-in-script-setup` rule of eslint-plugin-vue 10.12.1 (no options): an
// export of `<script setup>` that is not type-only, reported at the statement (at its `export`
// token when it exports a declaration).

const vue_no_export_in_script_setup_messages = {
	'forbidden': '`<script setup>` cannot contain ES module exports.'
}

fn (mut c Checker) lint_vue_no_export_in_script_setup(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	if !s.has_setup {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		typ := t.typ(node)
		if typ !in [.export_all_declaration, .export_default_declaration, .export_named_declaration]
			|| !s.in_script_setup(t, node) {
			continue
		}
		stats.checked++
		if (t.string_of(node, .export_kind) or { '' }) == 'type' {
			continue
		}
		if typ == .export_named_declaration {
			specifiers := t.list(node, .specifiers) or { []int{} }
			if specifiers.len > 0
				&& specifiers.all((t.string_of(it, .export_kind) or { '' }) == 'type') {
				continue
			}
			if t.node(node, .declaration) != none {
				// export let foo = 'foo', export class Foo {}, export function foo() {}
				first := un_first_token(t, tokens, node, 0) or { continue }
				findings << Finding{
					stmt:       c.position_range(first.start, first.end)
					message_id: 'forbidden'
				}
				continue
			}
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'forbidden'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
