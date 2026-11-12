module rules

import time
import treesitter { has_child_kind, node_field, node_kind, position_of }

// Port of the `config-default-export` rule of @slipher/eslint-plugin 1.1.0 (it has no options): a
// call of `bot` or `http` on seyfert's `config` that is not the `export default` of the file.

const sy_cde_messages = {
	'mustDefaultExport': "The result of `config.{{method}}()` must be the file's `export default`."
}

fn (mut c Checker) lint_seyfert_config_default_export(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut calls := []C.TSNode{}
	mut methods := []string{}
	mut objects := []C.TSNode{}
	for call in c.nodes_of_kind(root, c'call_expression') {
		call_arguments(call) or { continue }
		callee := unwrap_parens(node_field(call, 'function') or { continue })
		if node_kind(callee) != 'member_expression' {
			continue
		}
		property := node_field(callee, 'property') or { continue }
		if node_kind(property) != 'property_identifier' {
			continue
		}
		method := c.identifier_name(property)
		if method != 'bot' && method != 'http' {
			continue
		}
		object := node_field(callee, 'object') or { continue }
		calls << call
		methods << method
		objects << unwrap_parens(object)
	}
	c.resolve_node_types(objects, abs_path, mut stats)!
	c.sy_prefetch_symbols(objects)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for i, call in calls {
		if !c.sy_is_seyfert(c.sy_symbol_at(objects[i])!, 'config')! {
			continue
		}
		if !sy_cde_is_default_export(call) {
			findings << Finding{
				stmt:       position_of(call)
				message_id: 'mustDefaultExport'
				data:       {
					'method': methods[i]
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += calls.len
	return findings
}

// sy_cde_is_default_export: the ESTree parent of the call, past `as`, `satisfies`, `!` and `<T>`,
// is an ExportDefaultDeclaration. The parent of the outermost element of an optional chain is its
// ChainExpression.
fn sy_cde_is_default_export(call C.TSNode) bool {
	mut current := call
	for {
		if is_chain_element(current) && is_estree_chain_root(current) {
			return false
		}
		parent := treesitter.node_parent(current) or { return false }
		match node_kind(parent) {
			'parenthesized_expression', 'as_expression', 'satisfies_expression',
			'non_null_expression', 'type_assertion' {
				current = parent
			}
			'export_statement' {
				return has_child_kind(parent, 'default')
			}
			else {
				return false
			}
		}
	}
	return false
}
