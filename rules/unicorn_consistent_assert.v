module rules

import estree
import time

// Port of the `unicorn/consistent-assert` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fix.

const uca_messages = {
	'consistent-assert/error': 'Prefer `{{name}}.ok(…)` over `{{name}}(…)`.'
}

// uca_value_import ports isValueImport.
fn uca_value_import(t &estree.EsTree, node int) bool {
	kind := t.string_of(node, .import_kind) or { 'value' }
	return kind == 'value'
}

// uca_assert_function ports isAssertFunction: the default import, `default` or (of `assert`)
// `strict`.
fn uca_assert_function(t &estree.EsTree, specifier int, module_name string) bool {
	if t.typ(specifier) == .import_default_specifier {
		return true
	}
	if t.typ(specifier) != .import_specifier {
		return false
	}
	imported := t.node(specifier, .imported) or { return false }
	if t.typ(imported) != .identifier {
		return false
	}
	name := t.string_of(imported, .name) or { '' }
	return name == 'default' || (module_name == 'assert' && name == 'strict')
}

fn (mut c Checker) lint_unicorn_consistent_assert(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tree := c.scope_tree(root)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .import_declaration {
			continue
		}
		stats.checked++
		if !uca_value_import(t, node) {
			continue
		}
		source := t.node(node, .source) or { continue }
		value := t.get(source, .value)
		mut module_name := if value is string { value } else { continue }
		module_name = module_name.trim_string_left('node:')
		if module_name !in ['assert', 'assert/strict'] {
			continue
		}
		for specifier in t.list(node, .specifiers) or { []int{} } {
			if !uca_value_import(t, specifier) || !uca_assert_function(t, specifier, module_name) {
				continue
			}
			local := t.node(specifier, .local) or { continue }
			v := tree.declared_variable(t.ts_node(local) or { continue })
			if v < 0 {
				continue
			}
			for r in tree.variables[v].references {
				identifier := c.es_index_of(t, tree.references[r].identifier) or { continue }
				parent := t.nodes[identifier].parent
				if t.typ(parent) != .call_expression || t.node(parent, .callee) or { -1 } != identifier {
					continue
				}
				findings << Finding{
					stmt:       c.es_tree_position(t, identifier)
					message_id: 'consistent-assert/error'
					data:       {
						'name': t.string_of(identifier, .name) or { '' }
					}
					has_fix:    true
					fix:        fix_insert_at(t.nodes[identifier].end, '.ok')
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
