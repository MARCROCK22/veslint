module rules

import time
import treesitter { children, has_child_kind, named_children, node_kind, node_start, position_of }

// Port of the `no-useless-empty-export` rule of typescript-eslint 8.62.0 (it has no options),
// with its fix.

const nuee_messages = {
	'uselessExport': 'Empty export does nothing and can be removed.'
}

fn (mut c Checker) lint_no_useless_empty_export(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	// In a definition file `export {}` makes the file a module even with other exports.
	if is_definition_file(abs_path) {
		return findings
	}
	// Only the Program is checked: the rule also visits TSModuleDeclaration, but its body is a
	// TSModuleBlock and not a list of statements.
	mut empty_exports := []C.TSNode{}
	mut found_other_export := false
	for statement in named_children(root) {
		match node_kind(statement) {
			'export_statement' {
				if nuee_is_empty_export(statement) {
					empty_exports << statement
				} else if !(has_child_kind(statement, 'as')
					&& has_child_kind(statement, 'namespace')) {
					// Any export but `export as namespace X` (TSNamespaceExportDeclaration).
					found_other_export = true
				}
			}
			'import_statement', 'import_alias' {
				// ImportDeclaration and TSImportEqualsDeclaration.
				found_other_export = true
			}
			else {}
		}
	}
	if found_other_export {
		for statement in empty_exports {
			findings << Finding{
				stmt:       position_of(statement)
				message_id: 'uselessExport'
				has_fix:    true
				fix:        fix_remove_range(node_start(statement), c.cm_node_end(statement))
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += empty_exports.len
	return findings
}

// nuee_is_empty_export ports isEmptyExport: an ExportNamedDeclaration without specifiers nor
// declaration (`export {}`, `export type {}`, `export {} from 'x'`).
fn nuee_is_empty_export(statement C.TSNode) bool {
	for child in children(statement) {
		if node_kind(child) == 'export_clause' {
			return named_children(child).len == 0
		}
	}
	return false
}
