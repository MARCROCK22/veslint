module rules

import estree
import time

// Port of the `unicorn/require-module-specifiers` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fixes and suggestions.

const urms_messages = {
	'error':                            '{{type}} statement without specifiers is not allowed.'
	'suggestion/remove-declaration':    'Remove this {{type}} statement.'
	'suggestion/to-side-effect-import': 'Switch to side effect import.'
}

fn (mut c Checker) lint_unicorn_require_module_specifiers(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	is_declaration_file := abs_path.ends_with('.d.ts') || abs_path.ends_with('.d.mts')
		|| abs_path.ends_with('.d.cts')
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.import_declaration {
				stats.checked++
				if f := c.urms_import(t, tokens, node) {
					findings << f
				}
			}
			.export_named_declaration {
				stats.checked++
				if f := c.urms_export(t, tokens, node, is_declaration_file) {
					findings << f
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn urms_kind(t &estree.EsTree, node int, key estree.Key) string {
	return t.string_of(node, key) or { '' }
}

// urms_remove_declaration ports removeDeclaration.
fn (c &Checker) urms_remove_declaration(t &estree.EsTree, tokens &SourceTokens, node int) Fix {
	needs := c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false), none)
	return fix_replace_range(t.nodes[node].start, t.nodes[node].end, if needs { ';' } else { '' })
}

fn (c &Checker) urms_import(t &estree.EsTree, tokens &SourceTokens, declaration int) ?Finding {
	specifiers := t.list(declaration, .specifiers) or { []int{} }
	if specifiers.any(t.typ(it) in [.import_specifier, .import_namespace_specifier]) {
		return none
	}
	source := t.node(declaration, .source)?
	from := tokens.before(t.nodes[source].start, false)?
	if !(from.kind == .identifier && c.src[from.start..from.end] == 'from') {
		return none
	}
	closing := tokens.before(from.start, false)?
	if !c.token_is(closing, '}') {
		return none
	}
	opening := tokens.before(closing.start, false)?
	base := Finding{
		stmt:       c.position_range(opening.start, closing.end)
		message_id: 'error'
		data:       {
			'type': 'import'
		}
	}
	// Removing the whole declaration would remove a comment in it.
	has_comments := tokens.comments_inside(t.nodes[declaration].start, t.nodes[declaration].end).len > 0
	has_default := specifiers.len == 1
	if urms_kind(t, declaration, .import_kind) == 'type' && !has_default {
		if has_comments {
			return base
		}
		return Finding{
			...base
			has_fix: true
			fix:     c.urms_remove_declaration(t, tokens, declaration)
		}
	}
	if has_default {
		comma := tokens.before(opening.start, false)?
		mut fixes := [fix_remove_range(closing.start, closing.end),
			fix_remove_range(opening.start, opening.end), fix_remove_range(comma.start, comma.end)]
		if closing.end == from.start {
			fixes << fix_insert_at(from.start, ' ')
		}
		has_fix, fix := c.merge_fixes(fixes) or { return base }
		return Finding{
			...base
			has_fix: has_fix
			fix:     fix
		}
	}
	mut suggestions := []Suggestion{}
	if !has_comments {
		suggestions << Suggestion{
			message_id: 'suggestion/remove-declaration'
			data:       {
				'type': 'import'
			}
			fix:        c.urms_remove_declaration(t, tokens, declaration)
		}
	}
	_, side_effect := c.merge_fixes([fix_remove_range(opening.start, opening.end),
		fix_remove_range(closing.start, closing.end), fix_remove_range(from.start, from.end)]) or {
		return base
	}
	suggestions << Suggestion{
		message_id: 'suggestion/to-side-effect-import'
		fix:        side_effect
	}
	return Finding{
		...base
		suggestions: suggestions
	}
}

// urms_is_runtime_import ports isRuntimeImportDeclaration.
fn urms_is_runtime_import(t &estree.EsTree, declaration int) bool {
	if urms_kind(t, declaration, .import_kind) == 'type' {
		return false
	}
	specifiers := t.list(declaration, .specifiers) or { []int{} }
	return specifiers.len == 0 || specifiers.any(urms_kind(t, it, .import_kind) != 'type')
}

// urms_is_bare_module_marker ports isBareModuleMarker: `export {}`.
fn urms_is_bare_module_marker(t &estree.EsTree, node int) bool {
	return t.typ(node) == .export_named_declaration && t.node(node, .source) == none
		&& urms_kind(t, node, .export_kind) != 'type' && t.node(node, .declaration) == none
		&& (t.list(node, .specifiers) or { []int{} }).len == 0
}

// urms_is_runtime_export ports isRuntimeExportDeclaration.
fn urms_is_runtime_export(t &estree.EsTree, node int) bool {
	if urms_kind(t, node, .export_kind) == 'type' {
		return false
	}
	if t.typ(node) in [.export_default_declaration, .export_all_declaration] {
		return true
	}
	specifiers := t.list(node, .specifiers) or { []int{} }
	return t.node(node, .declaration) != none
		|| (t.node(node, .source) != none && specifiers.len == 0)
		|| specifiers.any(urms_kind(t, it, .export_kind) != 'type')
}

// urms_has_conflicting_marker ports hasConflictingModuleMarker: another statement makes the file
// a module already.
fn urms_has_conflicting_marker(t &estree.EsTree, declaration int) bool {
	program := t.nodes[declaration].parent
	body := t.list(program, .body) or { return false }
	index := body.index(declaration)
	for i, node in body {
		if node == declaration {
			continue
		}
		if t.typ(node) == .import_declaration {
			if urms_is_runtime_import(t, node) {
				return true
			}
			continue
		}
		if t.typ(node).type_name().starts_with('Export') {
			if urms_is_bare_module_marker(t, node) {
				if i < index {
					return true
				}
			} else if urms_is_runtime_export(t, node) {
				return true
			}
		}
	}
	return false
}

fn (c &Checker) urms_export(t &estree.EsTree, tokens &SourceTokens, declaration int, is_declaration_file bool) ?Finding {
	if t.node(declaration, .declaration) != none
		|| (t.list(declaration, .specifiers) or { []int{} }).len > 0 {
		return none
	}
	source := t.node(declaration, .source) or { -1 }
	kind := urms_kind(t, declaration, .export_kind)
	// In a declaration file a bare `export {}` is never useless.
	if source < 0 && kind != 'type'
		&& (is_declaration_file || !urms_has_conflicting_marker(t, declaration)) {
		return none
	}
	from := if source >= 0 { tokens.before(t.nodes[source].start, false) } else { none }
	closing := if f := from {
		tokens.before(f.start, false)?
	} else {
		mut found := ?SourceToken(none)
		for token in tokens.inside(t.nodes[declaration].start, t.nodes[declaration].end, false) {
			if c.token_is(token, '}') {
				found = token
			}
		}
		found?
	}
	opening := tokens.before(closing.start, false)?
	base := Finding{
		stmt:       c.position_range(opening.start, closing.end)
		message_id: 'error'
		data:       {
			'type': 'export'
		}
	}
	has_comments := tokens.comments_inside(t.nodes[declaration].start, t.nodes[declaration].end).len > 0
	if source < 0 || kind == 'type' {
		if has_comments {
			return base
		}
		return Finding{
			...base
			has_fix: true
			fix:     c.urms_remove_declaration(t, tokens, declaration)
		}
	}
	mut suggestions := []Suggestion{}
	if !has_comments {
		suggestions << Suggestion{
			message_id: 'suggestion/remove-declaration'
			data:       {
				'type': 'export'
			}
			fix:        c.urms_remove_declaration(t, tokens, declaration)
		}
	}
	export_token := un_first_token(t, tokens, declaration, 0)?
	from_token := from?
	_, side_effect := c.merge_fixes([
		fix_replace_range(export_token.start, export_token.end, 'import'),
		fix_remove_range(opening.start, opening.end),
		fix_remove_range(closing.start, closing.end),
		fix_remove_range(from_token.start, from_token.end),
	]) or { return base }
	suggestions << Suggestion{
		message_id: 'suggestion/to-side-effect-import'
		fix:        side_effect
	}
	return Finding{
		...base
		suggestions: suggestions
	}
}
