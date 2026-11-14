module rules

import estree
import json2
import time

// Port of the `unicorn/prefer-export-from` rule of eslint-plugin-unicorn 79.0.0 (option
// `checkUsedVariables`), with its fix and its suggestion.

const upef_messages = {
	'error':      'Use `export…from` to re-export `{{exported}}`.'
	'suggestion': 'Switch to `export…from`.'
}

fn upef_options(options []json2.Any) !bool {
	o := option_object(unicorn_prefer_export_from, options, ['checkUsedVariables'])!
	return o.bool_value('checkUsedVariables')!
}

// UpefNameKind tells the three kinds of names of the rule: `Symbol.for(name)` of an identifier
// (`default` is DEFAULT_SPECIFIER_NAME), the value of a string literal, and
// NAMESPACE_SPECIFIER_NAME.
enum UpefNameKind {
	symbol
	string_
	namespace
}

struct UpefName {
	kind  UpefNameKind
	value string
}

fn (a UpefName) same(b UpefName) bool {
	return a.kind == b.kind && a.value == b.value
}

const upef_default_name = UpefName{
	kind:  .symbol
	value: 'default'
}

struct UpefImported {
	node        int // the specifier
	declaration int // the ImportDeclaration
	variable    int
	is_type     bool
	name        UpefName
	text        string
}

struct UpefExported {
	node     int // the ExportSpecifier, ExportDefaultDeclaration or ExportNamedDeclaration
	name     UpefName
	text     string
	is_type  bool
	is_jsdoc bool
}

struct UpefVariable {
	variable int
	imported UpefImported
	exports  []UpefExported
}

fn (mut c Checker) lint_unicorn_prefer_export_from(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	check_used_variables := upef_options(c.rule_options(unicorn_prefer_export_from))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	tree := c.scope_tree(root)
	mut import_declarations := []int{}
	mut export_declarations := []int{}
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.import_declaration {
				if (t.list(node, .specifiers) or { []int{} }).len > 0 {
					import_declarations << node
				}
			}
			.export_named_declaration {
				// `ExportAllDeclaration` and `ExportDefaultDeclaration` can't be reused.
				if source := t.node(node, .source) {
					if t.typ(source) == .literal && t.get(source, .value) is string {
						export_declarations << node
					}
				}
			}
			else {}
		}
	}
	// In the order of the traversal.
	import_declarations.sort_with_compare(fn [t] (a &int, b &int) int {
		return t.nodes[*a].start - t.nodes[*b].start
	})
	export_declarations.sort_with_compare(fn [t] (a &int, b &int) int {
		return t.nodes[*a].start - t.nodes[*b].start
	})
	for import_declaration in import_declarations {
		stats.checked++
		specifiers := t.list(import_declaration, .specifiers) or { continue }
		// sourceCode.getDeclaredVariables(importDeclaration): a variable for each specifier, in order.
		mut declared := []int{}
		mut skip := false
		for specifier in specifiers {
			local := t.node(specifier, .local) or {
				skip = true
				break
			}
			ts := t.ts_node(local) or {
				skip = true
				break
			}
			v := tree.declared_variable(ts)
			if v < 0 {
				skip = true
				break
			}
			if v in declared {
				continue
			}
			declared << v
		}
		if skip || declared.any(tree.variables[it].defs.len != 1
			|| tree.variables[it].defs[0].kind != .import_binding) {
			continue
		}
		mut variables := []UpefVariable{}
		for v in declared {
			imported := c.upef_imported(t, tree, v, specifiers) or {
				skip = true
				break
			}
			variables << UpefVariable{
				variable: v
				imported: imported
				exports:  c.upef_exports(t, tree, tokens, imported)
			}
		}
		if skip {
			continue
		}
		if !check_used_variables
			&& variables.any(tree.variables[it.variable].references.len != it.exports.len) {
			continue
		}
		should_use_suggestion := !check_used_variables
			&& variables.any(tree.variables[it.variable].references.len == 0)
		for item in variables {
			for exported in item.exports {
				if exported.is_jsdoc {
					continue
				}
				mut finding := Finding{
					stmt:       c.es_tree_position(t, exported.node)
					message_id: 'error'
					data:       {
						'exported': exported.text
					}
				}
				// The fix removes the import and export declarations, a comment in them would be
				// dropped.
				export_declaration := if t.typ(exported.node) == .export_specifier {
					t.nodes[exported.node].parent
				} else {
					exported.node
				}
				would_remove_comment := [item.imported.declaration, export_declaration].any(tokens.comments_inside(t.nodes[it].start,
					t.nodes[it].end).len > 0)
				if !would_remove_comment {
					fixes := c.upef_fix(t, tree, tokens, item.imported, exported, export_declarations)
					has_fix, fix := c.merge_fixes(fixes)!
					if has_fix {
						if !should_use_suggestion {
							finding = Finding{
								...finding
								has_fix: true
								fix:     fix
							}
						} else {
							finding = Finding{
								...finding
								suggestions: [
									Suggestion{
										message_id: 'suggestion'
										fix:        fix
									},
								]
							}
						}
					}
				}
				findings << finding
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// upef_specifier_name ports getSpecifierName.
fn upef_specifier_name(t &estree.EsTree, node int) UpefName {
	if t.typ(node) == .literal {
		value := t.get(node, .value)
		return UpefName{
			kind:  .string_
			value: if value is string { value } else { '' }
		}
	}
	return UpefName{
		kind:  .symbol
		value: t.string_of(node, .name) or { '' }
	}
}

// upef_is_type_kind tells whether `node`'s `key` (importKind or exportKind) is `type`.
fn upef_is_type_kind(t &estree.EsTree, node int, key estree.Key) bool {
	return (t.string_of(node, key) or { '' }) == 'type'
}

// upef_imported ports getImported: the variable's specifier (variable.defs[0].node).
fn (c &Checker) upef_imported(t &estree.EsTree, tree &ScopeTree, v int, specifiers []int) ?UpefImported {
	identifier := tree.variables[v].defs[0].name
	mut specifier := -1
	for s in specifiers {
		local := t.node(s, .local) or { continue }
		ts := t.ts_node(local) or { continue }
		if node_key(ts) == node_key(identifier) {
			specifier = s
			break
		}
	}
	if specifier < 0 {
		return none
	}
	declaration := t.nodes[specifier].parent
	// isTypeImportSpecifier
	is_type := upef_is_type_kind(t, specifier, .import_kind)
		|| upef_is_type_kind(t, declaration, .import_kind)
	match t.typ(specifier) {
		.import_default_specifier {
			return UpefImported{
				node:        specifier
				declaration: declaration
				variable:    v
				is_type:     is_type
				name:        upef_default_name
				text:        'default'
			}
		}
		.import_specifier {
			imported := t.node(specifier, .imported)?
			return UpefImported{
				node:        specifier
				declaration: declaration
				variable:    v
				is_type:     is_type
				name:        upef_specifier_name(t, imported)
				text:        c.src[t.nodes[imported].start..t.nodes[imported].end]
			}
		}
		.import_namespace_specifier {
			return UpefImported{
				node:        specifier
				declaration: declaration
				variable:    v
				is_type:     is_type
				name:        UpefName{
					kind: .namespace
				}
				text:        '*'
			}
		}
		else {
			return none
		}
	}
}

// upef_exports ports getExports.
fn (mut c Checker) upef_exports(t &estree.EsTree, tree &ScopeTree, tokens &SourceTokens, imported UpefImported) []UpefExported {
	mut exports := []UpefExported{}
	for r in tree.variables[imported.variable].references {
		identifier := c.es_index_of(t, tree.references[r].identifier) or { continue }
		exported := c.upef_exported(t, tree, tokens, identifier) or { continue }
		// There is no substitution for `import * as foo from 'foo'; export default foo;`.
		if imported.name.kind == .namespace && exported.name.same(upef_default_name) {
			continue
		}
		exports << exported
	}
	return exports
}

// upef_is_type_export ports isTypeExport.
fn upef_is_type_export(t &estree.EsTree, specifier int) bool {
	parent := t.nodes[specifier].parent
	return upef_is_type_kind(t, specifier, .export_kind)
		|| (parent >= 0 && upef_is_type_kind(t, parent, .export_kind))
}

// upef_exported ports getExported.
fn (c &Checker) upef_exported(t &estree.EsTree, tree &ScopeTree, tokens &SourceTokens, identifier int) ?UpefExported {
	parent := t.nodes[identifier].parent
	if parent < 0 {
		return none
	}
	match t.typ(parent) {
		.export_default_declaration {
			return UpefExported{
				node:    parent
				name:    upef_default_name
				text:    'default'
				is_type: upef_is_type_export(t, parent)
			}
		}
		.export_specifier {
			exported := t.node(parent, .exported)?
			return UpefExported{
				node:    parent
				name:    upef_specifier_name(t, exported)
				text:    c.src[t.nodes[exported].start..t.nodes[exported].end]
				is_type: upef_is_type_export(t, parent)
			}
		}
		.variable_declarator {
			declaration := t.nodes[parent].parent
			if declaration < 0 {
				return none
			}
			export_declaration := t.nodes[declaration].parent
			id := t.node(parent, .id)?
			if (t.node(parent, .init) or { -1 }) == identifier && t.typ(id) == .identifier
				&& t.node(id, .type_annotation) == none
				&& t.typ(declaration) == .variable_declaration
				&& (t.string_of(declaration, .kind) or { '' }) == 'const'
				&& (t.list(declaration, .declarations) or { []int{} }) == [parent]
				&& export_declaration >= 0
				&& t.typ(export_declaration) == .export_named_declaration
				&& upef_is_variable_unused(t, tree, id) {
				return UpefExported{
					node:     export_declaration
					name:     UpefName{
						kind:  .symbol
						value: t.string_of(id, .name) or { '' }
					}
					text:     c.src[t.nodes[id].start..t.nodes[id].end]
					is_jsdoc: c.upef_has_attached_jsdoc(t, tokens, export_declaration)
				}
			}
			return none
		}
		else {
			return none
		}
	}
}

// upef_is_variable_unused ports isVariableUnused for the declarator whose id is `id`.
fn upef_is_variable_unused(t &estree.EsTree, tree &ScopeTree, id int) bool {
	ts := t.ts_node(id) or { return false }
	v := tree.declared_variable(ts)
	if v < 0 {
		return false
	}
	variable := tree.variables[v]
	return variable.identifiers.len == 1 && node_key(variable.identifiers[0]) == node_key(ts)
		&& variable.references.len == 1
		&& node_key(tree.references[variable.references[0]].identifier) == node_key(ts)
}

// upef_has_attached_jsdoc ports hasAttachedJSDocumentComment.
fn (c &Checker) upef_has_attached_jsdoc(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	start := t.nodes[node].start
	comment := tokens.before(start, true) or { return false }
	if comment.kind != .block_comment {
		return false
	}
	value := c.src[comment.start + 2..comment.end - 2]
	if !value.starts_with('*') || value.starts_with('**') {
		return false
	}
	comment_start_line, _ := t.line_column(comment.start)
	comment_end_line, _ := t.line_column(comment.end)
	node_start_line, _ := t.line_column(start)
	if previous := tokens.before(comment.start, false) {
		previous_end_line, _ := t.line_column(previous.end)
		if previous_end_line >= comment_start_line {
			return false
		}
	}
	return comment_end_line == node_start_line || comment_end_line == node_start_line - 1
}

// upef_remove_import_or_export ports removeImportOrExport.
fn (c &Checker) upef_remove_import_or_export(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	match t.typ(node) {
		.import_specifier, .export_specifier, .import_default_specifier,
		.import_namespace_specifier {
			return c.un_remove_specifier(t, tokens, node, false)
		}
		.export_default_declaration, .export_named_declaration {
			needs := c.unb_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false),
				none)
			return [
				fix_replace_range(t.nodes[node].start, t.nodes[node].end, if needs {
					';'
				} else {
					''
				}),
			]
		}
		else {
			return []
		}
	}
}

// upef_source_and_assertions ports getSourceAndAssertionsText: from the `from` before the source
// to the end of the declaration.
fn (c &Checker) upef_source_and_assertions(t &estree.EsTree, tokens &SourceTokens, declaration int) string {
	source := t.node(declaration, .source) or { return '' }
	mut at := t.nodes[source].start
	for {
		token := tokens.before(at, false) or { return '' }
		if token.kind == .identifier && c.src[token.start..token.end] == 'from' {
			return c.src[token.start..t.nodes[declaration].end]
		}
		at = token.start
	}
	return ''
}

// upef_source_value is `declaration.source.value`.
fn upef_source_value(t &estree.EsTree, declaration int) ?string {
	source := t.node(declaration, .source)?
	value := t.get(source, .value)
	if value is string {
		return value
	}
	return none
}

// upef_fix ports the fix function of getFixFunction.
fn (c &Checker) upef_fix(t &estree.EsTree, tree &ScopeTree, tokens &SourceTokens, imported UpefImported, exported UpefExported, export_declarations []int) []Fix {
	source_value := upef_source_value(t, imported.declaration) or { return [] }
	should_export_as_type := imported.is_type || exported.is_type
	mut export_declaration := -1
	if should_export_as_type {
		// If a type export declaration already exists, reuse it, else use a value export
		// declaration with an inline type specifier.
		for declaration in export_declarations {
			if upef_is_type_kind(t, declaration, .export_kind)
				&& (upef_source_value(t, declaration) or { continue }) == source_value {
				export_declaration = declaration
				break
			}
		}
	}
	if export_declaration < 0 {
		for declaration in export_declarations {
			if !upef_is_type_kind(t, declaration, .export_kind)
				&& (upef_source_value(t, declaration) or { continue }) == source_value {
				export_declaration = declaration
				break
			}
		}
	}
	mut fixes := []Fix{}
	program_end := t.nodes[t.root].end
	if imported.name.kind == .namespace {
		fixes << fix_insert_at(program_end, '${un_linebreak(c.src)}export ${if should_export_as_type {
			'type '
		} else {
			''
		}}* as ${exported.text} ${c.upef_source_and_assertions(t, tokens, imported.declaration)}')
	} else {
		mut specifier_text := if exported.name.same(imported.name) {
			exported.text
		} else {
			'${imported.text} as ${exported.text}'
		}
		// Add an inline type specifier if the value is a type and the export declaration is a
		// value declaration.
		if should_export_as_type && (export_declaration < 0
			|| !upef_is_type_kind(t, export_declaration, .export_kind)) {
			specifier_text = 'type ${specifier_text}'
		}
		if export_declaration >= 0 {
			specifiers := t.list(export_declaration, .specifiers) or { []int{} }
			if specifiers.len > 0 {
				fixes << fix_insert_at(t.nodes[specifiers.last()].end, ', ${specifier_text}')
			} else {
				// `export {} from 'foo';`
				for token in tokens.inside(t.nodes[export_declaration].start, t.nodes[export_declaration].end,
					false) {
					if c.token_is(token, '{') {
						fixes << fix_insert_at(token.end, specifier_text)
						break
					}
				}
			}
		} else {
			fixes << fix_insert_at(program_end, '${un_linebreak(c.src)}export {${specifier_text}} ${c.upef_source_and_assertions(t, tokens, imported.declaration)}')
		}
	}
	import_has_side_effects := exported.is_type && !imported.is_type
	if tree.variables[imported.variable].references.len == 1 && !import_has_side_effects {
		fixes << c.upef_remove_import_or_export(t, tokens, imported.node)
	}
	fixes << c.upef_remove_import_or_export(t, tokens, exported.node)
	return fixes
}
