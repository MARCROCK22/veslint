module rules

import estree
import time

// Port of the `unicorn/no-named-default` rule of eslint-plugin-unicorn 79.0.0 (it has no options),
// with its fix.

const unnd_messages = {
	'no-named-default': 'Prefer using the default {{type}} over named {{type}}.'
}

fn (mut c Checker) lint_unicorn_no_named_default(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		typ := t.typ(node)
		if typ !in [.import_specifier, .export_specifier] {
			continue
		}
		stats.checked++
		declaration := t.nodes[node].parent
		is_import := typ == .import_specifier
		kind_key := if is_import { estree.Key.import_kind } else { estree.Key.export_kind }
		named := t.node(node, if is_import { estree.Key.imported } else { estree.Key.exported }) or {
			continue
		}
		if !unnd_is_value(t, node, kind_key) || (t.string_of(named, .name) or { '' }) != 'default'
			|| !unnd_is_value(t, declaration, kind_key) {
			continue
		}
		if !is_import && t.node(declaration, .source) != none {
			continue
		}
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'no-named-default'
			data:       {
				'type': if is_import { 'import' } else { 'export' }
			}
		}
		// Skip the fix when it would drop a comment.
		fixes := if is_import {
			if c.unnd_import_removal_has_comment(t, tokens, node) {
				[]Fix{}
			} else {
				c.unnd_fix_import(t, tokens, node)
			}
		} else {
			removal := if (t.list(declaration, .specifiers) or { []int{} }).len == 1 {
				declaration
			} else {
				node
			}
			if tokens.comments_inside(t.nodes[removal].start, t.nodes[removal].end).len > 0 {
				[]Fix{}
			} else {
				c.unnd_fix_export(t, tokens, node)
			}
		}
		if fixes.len > 0 {
			has_fix, fix := c.merge_fixes(fixes)!
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unnd_is_value ports isValueImport and isValueExport: no `type` kind.
fn unnd_is_value(t &estree.EsTree, node int, key estree.Key) bool {
	kind := t.string_of(node, key) or { '' }
	return kind == '' || kind == 'value'
}

// unnd_token_before is getTokenBefore(node, token => token is `punctuator`).
fn (c &Checker) unnd_token_before(tokens &SourceTokens, offset int, punctuator string) ?SourceToken {
	mut at := offset
	for {
		token := tokens.before(at, false)?
		if c.token_is(token, punctuator) {
			return token
		}
		at = token.start
	}
	return none
}

// unnd_from_after is getTokenAfter(node, token => an identifier `from`).
fn (c &Checker) unnd_from_after(tokens &SourceTokens, offset int) ?SourceToken {
	mut at := offset
	for {
		token := tokens.after(at, false)?
		if token.kind == .identifier && c.src[token.start..token.end] == 'from' {
			return token
		}
		at = token.end
	}
	return none
}

// unnd_import_removal_has_comment ports hasCommentInImportRemovalRange.
fn (c &Checker) unnd_import_removal_has_comment(t &estree.EsTree, tokens &SourceTokens, specifier int) bool {
	declaration := t.nodes[specifier].parent
	specifiers := t.list(declaration, .specifiers) or { []int{} }
	only_named := specifiers.all(it == specifier || t.typ(it) != t.typ(specifier))
	if !only_named {
		return tokens.comments_inside(t.nodes[specifier].start, t.nodes[specifier].end).len > 0
	}
	has_default := specifiers.any(t.typ(it) == .import_default_specifier)
	start := c.unnd_token_before(tokens, t.nodes[specifier].start, if has_default {
		','
	} else {
		'{'
	}) or {
		return true
	}
	from := c.unnd_from_after(tokens, t.nodes[specifier].end) or { return true }
	return tokens.comments_exist_between(start.end, from.start)
}

// un_remove_specifier ports removeSpecifier (fix/remove-specifier.js).
fn (c &Checker) un_remove_specifier(t &estree.EsTree, tokens &SourceTokens, specifier int, keep_declaration bool) []Fix {
	declaration := t.nodes[specifier].parent
	specifiers := t.list(declaration, .specifiers) or { return [] }
	if specifiers.len == 1 && !keep_declaration {
		needs := c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[declaration].start, false), none)
		return [fix_replace_range(t.nodes[declaration].start, t.nodes[declaration].end, if needs {
			';'
		} else {
			''
		})]
	}
	if t.typ(specifier) == .import_specifier
		&& specifiers.all(it == specifier || t.typ(it) != .import_specifier) {
		from := c.unnd_from_after(tokens, t.nodes[specifier].end) or { return [] }
		has_default := specifiers.any(t.typ(it) == .import_default_specifier)
		start_token := c.unnd_token_before(tokens, t.nodes[specifier].start, if has_default {
			','
		} else {
			'{'
		}) or { return [] }
		before := tokens.before(start_token.start, false) or { return [] }
		insert_space := before.end == start_token.start
		return [fix_replace_range(start_token.start, from.start, if insert_space { ' ' } else { '' })]
	}
	mut fixes := [fix_remove_range(t.nodes[specifier].start, t.nodes[specifier].end)]
	if after := tokens.after(t.nodes[specifier].end, false) {
		if c.token_is(after, ',') {
			fixes << fix_remove_range(after.start, after.end)
		}
	}
	return fixes
}

// unnd_fix_import ports fixImportSpecifier.
fn (c &Checker) unnd_fix_import(t &estree.EsTree, tokens &SourceTokens, specifier int) []Fix {
	declaration := t.nodes[specifier].parent
	mut fixes := c.un_remove_specifier(t, tokens, specifier, true)
	local := t.node(specifier, .local) or { return [] }
	name := c.src[t.nodes[local].start..t.nodes[local].end]
	specifiers := t.list(declaration, .specifiers) or { return [] }
	if specifiers.any(t.typ(it) == .import_default_specifier) {
		// A new ImportDeclaration.
		source := t.node(declaration, .source) or { return [] }
		mut at := t.nodes[source].start
		mut from := tokens.before(at, false) or { return [] }
		for !(from.kind == .identifier && c.src[from.start..from.end] == 'from') {
			at = from.start
			from = tokens.before(at, false) or { return [] }
		}
		text := 'import ${name} ${c.src[from.start..t.nodes[declaration].end]}'
		fixes << fix_insert_at(t.nodes[declaration].start, text + un_linebreak(c.src))
		return fixes
	}
	import_token := un_first_token(t, tokens, declaration, 0) or { return [] }
	add_comma := specifiers.any(it != specifier && t.typ(it) == t.typ(specifier))
	fixes << fix_insert_at(import_token.end, ' ${name}${if add_comma { ',' } else { '' }}')
	return fixes
}

// unnd_fix_export ports fixExportSpecifier.
fn (c &Checker) unnd_fix_export(t &estree.EsTree, tokens &SourceTokens, specifier int) []Fix {
	declaration := t.nodes[specifier].parent
	mut fixes := c.un_remove_specifier(t, tokens, specifier, false)
	local := t.node(specifier, .local) or { return [] }
	text := 'export default ${c.src[t.nodes[local].start..t.nodes[local].end]};'
	fixes << fix_insert_at(t.nodes[declaration].start, text + un_linebreak(c.src))
	return fixes
}
