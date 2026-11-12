module rules

import os
import time
import treesitter { named_children, node_field, node_kind, position_of }

// Port of the `no-deep-imports` rule of @slipher/eslint-plugin 1.1.0 (it has no options): a named
// import from `seyfert/lib` or a path under it of a name the root of the package (`seyfert`, as it
// resolves from the file) exports. When every specifier of the import is such a name, the first
// report fixes the source into 'seyfert'.

const sy_ndi_messages = {
	'preferRoot': "'{{name}}' is exported from 'seyfert'; import it from the package root, not '{{source}}'."
}

fn (mut c Checker) lint_seyfert_no_deep_imports(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	mut root_exports := []string{}
	mut asked := false
	for declaration in c.nodes_of_kind(root, c'import_statement') {
		source_node := node_field(declaration, 'source') or { continue }
		source := c.literal_string_value(source_node) or { continue }
		if source != 'seyfert/lib' && !source.starts_with('seyfert/lib/') {
			continue
		}
		checked++
		if !asked {
			asked = true
			resolved := c.client.resolve_module_name(c.project, 'seyfert', os.dir(abs_path))!
			if resolved != '' {
				root_exports = c.client.module_export_names(c.snapshot, c.project, resolved)!
			}
		}
		if root_exports.len == 0 {
			continue
		}
		specifiers := sy_ndi_specifiers(declaration)
		named := specifiers.filter(node_kind(it) == 'import_specifier')
		offending := named.filter(c.sy_ndi_imported_name(it) in root_exports)
		if offending.len == 0 {
			continue
		}
		all_root := specifiers.len == named.len && offending.len == named.len
		for i, specifier in offending {
			data := {
				'name':   c.sy_ndi_imported_name(specifier)
				'source': source
			}
			findings << if all_root && i == 0 {
				Finding{
					stmt:       position_of(specifier)
					message_id: 'preferRoot'
					data:       data
					has_fix:    true
					fix:        fix_replace(source_node, "'seyfert'")
				}
			} else {
				Finding{
					stmt:       position_of(specifier)
					message_id: 'preferRoot'
					data:       data
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// sy_ndi_specifiers are the ESTree specifiers of an import: its default import, its namespace
// import and its named imports, in order.
fn sy_ndi_specifiers(declaration C.TSNode) []C.TSNode {
	mut out := []C.TSNode{}
	for child in named_children(declaration) {
		if node_kind(child) != 'import_clause' {
			continue
		}
		for part in named_children(child) {
			match node_kind(part) {
				'named_imports' {
					out << named_children(part).filter(node_kind(it) == 'import_specifier')
				}
				'identifier', 'namespace_import' {
					out << part
				}
				else {}
			}
		}
	}
	return out
}

// sy_ndi_imported_name ports importedName: the imported name of a specifier, an identifier's or
// the value of a string.
fn (c &Checker) sy_ndi_imported_name(specifier C.TSNode) string {
	name := node_field(specifier, 'name') or { return '' }
	if node_kind(name) == 'string' {
		return c.literal_string_value(name) or { '' }
	}
	return c.identifier_name(name)
}
