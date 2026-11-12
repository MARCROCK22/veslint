module rules

import json2
import time
import tsgo { SymbolResponse }
import treesitter { children, has_child_kind, named_children, node_end, node_field, node_kind, node_start, nodes_of_kind, position_of }

// Port of the `consistent-type-exports` rule of typescript-eslint 8.62.0, with its option and its
// fixers.

const cte_messages = {
	'multipleExportsAreTypes': 'Type exports {{exportNames}} are not values and should be exported using `export type`.'
	'singleExportIsType':      'Type export {{exportNames}} is not a value and should be exported using `export type`.'
	'typeOverValue':           'All exports in the declaration are only used as types. Use `export type`.'
}

// SymbolFlags.Alias, SymbolFlags.Property (the flags of TypeScript's unknown symbol) and the kind
// of a SourceFile.
const cte_symbol_flag_alias = u32(2097152)
const cte_symbol_flag_property = u32(4)
const cte_kind_source_file = u32(308)

struct CteOptions {
	fix_mixed_exports_with_inline_type_specifier bool
}

fn cte_options(options []json2.Any) !CteOptions {
	o := option_object(consistent_type_exports, options, ['fixMixedExportsWithInlineTypeSpecifier'])!
	return CteOptions{
		fix_mixed_exports_with_inline_type_specifier: o.bool_value('fixMixedExportsWithInlineTypeSpecifier')!
	}
}

// CteSpecifier is an ExportSpecifier: its local name, its exported name (the same node without an
// `as`) and whether it is an inline `type` specifier.
struct CteSpecifier {
	node        C.TSNode
	local       C.TSNode
	exported    C.TSNode
	inline_type bool
}

// CteExport is an ExportNamedDeclaration with specifiers that is not an `export type`.
struct CteExport {
	node       C.TSNode
	clause     C.TSNode
	source     ?C.TSNode
	specifiers []CteSpecifier
}

fn (mut c Checker) lint_consistent_type_exports(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	options := cte_options(c.rule_options(consistent_type_exports))!
	mut sw := time.new_stopwatch()
	mut named := []CteExport{}
	mut all := []C.TSNode{} // ExportAllDeclaration that is not `export type *`
	mut spans := []Span{}
	for node in c.nodes_of_kind(root, c'export_statement') {
		// exportKind === 'type'
		if has_child_kind(node, 'type') {
			continue
		}
		source := node_field(node, 'source')
		if has_child_kind(node, '*') || has_child_kind(node, 'namespace_export') {
			if module_name := source {
				all << node
				spans << node_span(module_name)
			}
			continue
		}
		clause := children_of_kind(node, 'export_clause')
		if clause.len != 1 {
			continue
		}
		mut specifiers := []CteSpecifier{}
		for specifier in named_children(clause[0]) {
			if node_kind(specifier) != 'export_specifier' {
				continue
			}
			local := node_field(specifier, 'name') or { continue }
			exported := node_field(specifier, 'alias') or { local }
			inline_type := node_start(local) != node_start(specifier)
			specifiers << CteSpecifier{
				node:        specifier
				local:       local
				exported:    exported
				inline_type: inline_type
			}
			if !inline_type {
				// Without an `as` the name has the range of the specifier: the innermost node
				// with that range is the name.
				spans << node_span(exported)
			}
		}
		named << CteExport{
			node:       node
			clause:     clause[0]
			source:     source
			specifiers: specifiers
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for node in all {
		module_name := node_field(node, 'source') or { continue }
		if c.cte_has_exported_value(module_name)! {
			continue
		}
		// `type ` before the asterisk.
		mut asterisk := node_start(node)
		for child in children(node) {
			kind := node_kind(child)
			if kind == '*' || kind == 'namespace_export' {
				asterisk = node_start(child)
				break
			}
		}
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'typeOverValue'
			has_fix:    true
			fix:        fix_insert_at(asterisk, 'type ')
		}
	}
	for item in named {
		mut type_based := []CteSpecifier{}
		mut inline_types := []CteSpecifier{}
		mut values := []CteSpecifier{}
		for specifier in item.specifiers {
			if specifier.inline_type {
				inline_types << specifier
				continue
			}
			match c.cte_is_type_based(specifier.exported)! {
				1 { type_based << specifier }
				0 { values << specifier }
				// A specifier that cannot be resolved is not reported.
				else {}
			}
		}
		if type_based.len == 0 {
			continue
		}
		if values.len == 0 {
			// Every specifier is a type: the whole export becomes an `export type`.
			findings << c.with_fixes(Finding{
				stmt:       position_of(item.node)
				message_id: 'typeOverValue'
			}, c.cte_fix_insert_type(item, inline_types))!
			continue
		}
		mut export_names := []string{}
		for specifier in type_based {
			export_names << c.literal_string_value(specifier.local) or {
				c.identifier_name(specifier.local)
			}
		}
		fixes := if options.fix_mixed_exports_with_inline_type_specifier {
			type_based.map(fix_insert_before(it.node, 'type '))
		} else {
			c.cte_fix_separate(item, type_based, inline_types, values)
		}
		findings << c.with_fixes(Finding{
			stmt:       position_of(item.node)
			message_id: if export_names.len == 1 {
				'singleExportIsType'
			} else {
				'multipleExportsAreTypes'
			}
			data:       {
				'exportNames': format_word_list(export_names)
			}
		}, fixes)!
	}
	findings.sort_with_compare(compare_findings)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += all.len + named.len
	return findings
}

// format_word_list ports formatWordList: 'a', 'a and b', 'a, b and c'.
fn format_word_list(words []string) string {
	if words.len < 2 {
		return words.join('')
	}
	return words[..words.len - 1].join(', ') + ' and ' + words.last()
}

// cte_symbol_at is the symbol at a name that resolve_spans has looked up (getSymbolAtLocation).
fn (mut c Checker) cte_symbol_at(name C.TSNode) !SymbolResponse {
	handle := c.node_handles[node_key(name)] or { return SymbolResponse{} }
	symbols := c.client.symbols_at_locations(c.snapshot, c.project, [handle])!
	if symbols.len != 1 {
		return SymbolResponse{}
	}
	return symbols[0]
}

// cte_is_type_based ports isSymbolTypeBased on the symbol of an exported name: 1 for a type, 0
// for a value and -1 when the specifier cannot be resolved.
fn (mut c Checker) cte_is_type_based(exported C.TSNode) !int {
	mut symbol := c.cte_symbol_at(exported)!
	// An alias chain ends at a declaration; the limit is for a chain that does not.
	for _ in 0 .. max_type_depth {
		// TypeScript's unknown symbol: a property named `unknown` that nothing declares.
		if symbol.is_null() || (symbol.name == 'unknown' && symbol.declarations.len == 0
			&& symbol.flags == cte_symbol_flag_property) {
			return -1
		}
		for declaration in symbol.declarations {
			tree := c.declaration_ast(tsgo.handle_path(declaration))!
			if tree.is_type_only_import_or_export(tsgo.handle_index(declaration)) {
				return 1
			}
		}
		if symbol.flags & u32(symbol_flags_value) != 0 {
			return 0
		}
		if symbol.flags & cte_symbol_flag_alias == 0 {
			return 1
		}
		symbol = c.client.immediate_aliased_symbol(c.snapshot, c.project, symbol.id)!
	}
	return -1
}

// cte_has_exported_value: the module that an `export *` names is a file with some export that is
// a value. Like the original, it looks at the properties of the type of the module, which are its
// value exports, and leaves out the ones getPropertyOfType does not find: those that reach the
// module through an `export type *`.
fn (mut c Checker) cte_has_exported_value(module_name C.TSNode) !bool {
	symbol := c.cte_symbol_at(module_name)!
	// Without a source file for the module (it does not resolve, or only a `declare module`
	// declares it), the original gives up.
	if symbol.is_null()
		|| !symbol.declarations.any(tsgo.handle_kind(it) == cte_kind_source_file) {
		return true
	}
	module_type := c.symbol_type(symbol.id)!
	for property in c.properties(module_type)! {
		if !c.property(module_type, property.name)!.is_null() {
			return true
		}
	}
	return false
}

// cte_fix_insert_type ports fixExportInsertType: ` type` after `export`, and the `type` of each
// inline type specifier removed, up to the next token or comment.
fn (mut c Checker) cte_fix_insert_type(item CteExport, inline_types []CteSpecifier) []Fix {
	tokens := c.source_tokens(item.node)
	mut fixes := []Fix{}
	if export_token := tokens.after(node_start(item.node), false) {
		fixes << fix_insert_at(export_token.end, ' type')
	}
	for specifier in inline_types {
		kind_token := tokens.after(node_start(specifier.node), false) or { continue }
		after := tokens.after(kind_token.end, true) or { continue }
		fixes << fix_remove_range(kind_token.start, after.start)
	}
	return fixes
}

// cte_specifier_text ports getSpecifierText: `local` or `local as exported`, without `type`.
fn (c &Checker) cte_specifier_text(specifier CteSpecifier) string {
	local := c.cte_name_text(specifier.local)
	exported := c.cte_name_text(specifier.exported)
	return if exported != local { '${local} as ${exported}' } else { local }
}

// cte_name_text is the `raw` of a string name or the `name` of an identifier.
fn (c &Checker) cte_name_text(name C.TSNode) string {
	return if node_kind(name) == 'string' { c.text(name) } else { c.identifier_name(name) }
}

// cte_fix_separate ports fixSeparateNamedExports: the value specifiers stay between the braces
// and the type ones go to an `export type` on a line before.
fn (mut c Checker) cte_fix_separate(item CteExport, type_based []CteSpecifier, inline_types []CteSpecifier, values []CteSpecifier) []Fix {
	mut type_specifiers := type_based.clone()
	type_specifiers << inline_types
	specifier_names := type_specifiers.map(c.cte_specifier_text(it)).join(', ')
	filtered_names := values.map(c.cte_specifier_text(it)).join(', ')
	mut from := ''
	if source := item.source {
		if value := c.literal_string_value(source) {
			from = " from '${value}'"
		}
	}
	// The first `{` and the last `}` of the declaration.
	mut open_end := node_start(item.clause) + 1
	mut close_start := node_end(item.clause) - 1
	for token in c.node_tokens(item.node) {
		if c.token_is(token, '{') {
			open_end = token.end
			break
		}
	}
	for token in c.node_tokens(item.node).reverse() {
		if c.token_is(token, '}') {
			close_start = token.start
			break
		}
	}
	return [
		fix_replace_range(open_end, close_start, ' ${filtered_names} '),
		fix_insert_at(node_start(item.node), 'export type { ${specifier_names} }${from};\n'),
	]
}
