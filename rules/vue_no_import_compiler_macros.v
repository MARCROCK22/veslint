module rules

import time

// Port of the `vue/no-import-compiler-macros` rule of eslint-plugin-vue 10.12.1 (no options): an
// import of a compiler macro from `vue`, `@vue/runtime-core` or `@vue/runtime-dom`, with the fix
// that removes it (the declaration when it is its only specifier, else the specifier and a comma).

const vue_no_import_compiler_macros_messages = {
	'noImportCompilerMacros': "'{{name}}' is a compiler macro and doesn't need to be imported."
	'onlyValidInScriptSetup': "'{{name}}' is a compiler macro and can only be used inside <script setup>."
}

const vue_import_compiler_macros = ['defineProps', 'defineEmits', 'defineExpose', 'withDefaults',
	'defineModel', 'defineOptions', 'defineSlots']

fn (mut c Checker) lint_vue_no_import_compiler_macros(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .import_declaration {
			continue
		}
		specifiers := t.list(node, .specifiers) or { []int{} }
		source := t.node(node, .source) or { continue }
		module := t.get(source, .value)
		if specifiers.len == 0 || module !is string
			|| (module as string) !in ['@vue/runtime-core', '@vue/runtime-dom', 'vue'] {
			continue
		}
		for specifier in specifiers {
			if t.typ(specifier) != .import_specifier {
				continue
			}
			imported := t.node(specifier, .imported) or { continue }
			name := if t.typ(imported) == .identifier {
				t.string_of(imported, .name) or { '' }
			} else {
				''
			}
			if name !in vue_import_compiler_macros {
				continue
			}
			stats.checked++
			mut fix := Fix{}
			start, end := t.nodes[specifier].start, t.nodes[specifier].end
			if specifiers.len == 1 {
				fix = fix_remove_range(t.nodes[node].start, t.nodes[node].end)
			} else if specifier == specifiers.last() {
				mut from := start
				for i := tokens.tokens.len - 1; i >= 0; i-- {
					token := tokens.tokens[i]
					if token.end <= start && c.src[token.start..token.end] == ',' {
						from = token.start
						break
					}
				}
				fix = fix_remove_range(from, end)
			} else {
				mut to := end
				for token in tokens.tokens {
					if token.start >= end && c.src[token.start..token.end] == ',' {
						to = token.end
						break
					}
				}
				fix = fix_remove_range(start, to)
			}
			findings << Finding{
				stmt:       c.es_tree_position(t, specifier)
				message_id: if s.has_setup {
					'noImportCompilerMacros'
				} else {
					'onlyValidInScriptSetup'
				}
				data:       {
					'name': name
				}
				has_fix:    true
				fix:        fix
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
