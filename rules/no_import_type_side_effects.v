module rules

import time
import treesitter { has_child_kind, named_children, node_field, node_kind, node_start, position_of }

// Port of the `no-import-type-side-effects` rule of typescript-eslint 8.62.0 (it has no options),
// with its fix.

const nitse_messages = {
	'useTopLevelQualifier': 'TypeScript will only remove the inline type specifiers which will leave behind a side effect import at runtime. Convert this to a top-level type qualifier to properly remove the entire import.'
}

fn (mut c Checker) lint_no_import_type_side_effects(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	// `ImportDeclaration[importKind!="type"]`: an import without its own `type` (`import x =
	// require()` is a TSImportEqualsDeclaration, which has no import_clause).
	for node in c.nodes_of_kind(root, c'import_statement') {
		if has_child_kind(node, 'type') {
			continue
		}
		checked++
		specifiers := nitse_type_specifiers(node) or { continue }
		// The `type` of each specifier goes, with what follows it up to the imported name, and the
		// import gets one after its `import` keyword.
		mut fixes := []Fix{}
		for specifier in specifiers {
			qualifier := c.node_tokens(specifier).filter(it.kind == .identifier
				&& c.token_text(it) == 'type')
			imported := node_field(specifier, 'name') or { continue }
			if qualifier.len == 0 {
				continue
			}
			fixes << fix_remove_range(qualifier[0].start, node_start(imported))
		}
		keyword := c.node_tokens(node).filter(it.kind == .keyword && c.token_text(it) == 'import')
		if keyword.len > 0 {
			fixes << fix_insert_at(keyword[0].end, ' type')
		}
		findings << c.with_fixes(Finding{
			stmt:       position_of(node)
			message_id: 'useTopLevelQualifier'
		}, fixes)!
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nitse_type_specifiers are the specifiers of an import when it has some and every one is an
// ImportSpecifier with its own `type` (a default or namespace import is not one); none otherwise.
fn nitse_type_specifiers(node C.TSNode) ?[]C.TSNode {
	mut specifiers := []C.TSNode{}
	for clause in named_children(node) {
		if node_kind(clause) != 'import_clause' {
			continue
		}
		for part in named_children(clause) {
			if node_kind(part) != 'named_imports' {
				return none
			}
			for specifier in named_children(part) {
				if node_kind(specifier) != 'import_specifier' || !has_child_kind(specifier, 'type') {
					return none
				}
				specifiers << specifier
			}
		}
	}
	if specifiers.len == 0 {
		return none
	}
	return specifiers
}
