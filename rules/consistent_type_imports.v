module rules

import json2
import time
import treesitter { has_child_kind, named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `consistent-type-imports` rule of typescript-eslint 8.62.0, with its options
// `prefer`, `fixStyle` and `disallowTypeAnnotations`, and its fixes. As in typescript-eslint with
// a program, a file with a decorator is left alone when the project sets both
// `experimentalDecorators` and `emitDecoratorMetadata`.

const cti_messages = {
	'avoidImportType':         'Use an `import` instead of an `import type`.'
	'noImportTypeAnnotations': '`import()` type annotations are forbidden.'
	'someImportsAreOnlyTypes': 'Imports {{typeImports}} are only used as type.'
	'typeOverValue':           'All imports in the declaration are only used as types. Use `import type`.'
}

struct CtiOptions {
	prefer_type_imports       bool
	inline_type_imports       bool
	disallow_type_annotations bool
}

fn cti_options(options []json2.Any) !CtiOptions {
	o := option_object(consistent_type_imports, options, ['disallowTypeAnnotations', 'fixStyle',
		'prefer'])!
	prefer := o.string_value('prefer', ['type-imports', 'no-type-imports', ''])!
	fix_style := o.string_value('fixStyle', ['separate-type-imports', 'inline-type-imports', ''])!
	// `disallowTypeAnnotations !== false`
	mut disallow := true
	if value := o.values['disallowTypeAnnotations'] {
		disallow = o.bool_value('disallowTypeAnnotations')! || value !is bool
	}
	return CtiOptions{
		prefer_type_imports:       prefer != 'no-type-imports'
		inline_type_imports:       fix_style == 'inline-type-imports'
		disallow_type_annotations: disallow
	}
}

enum CtiSpecifierKind {
	default_
	namespace
	named
}

// CtiSpecifier is a specifier of an ImportDeclaration: `node` is its ESTree node (the identifier
// of a default import, the namespace_import, the import_specifier) and `local` its local name.
struct CtiSpecifier {
	node        C.TSNode
	local       C.TSNode
	kind        CtiSpecifierKind
	inline_type bool // an ImportSpecifier with `type`
}

fn (s CtiSpecifier) same(other CtiSpecifier) bool {
	return node_key(s.node) == node_key(other.node) && s.kind == other.kind
}

// CtiImport is an ImportDeclaration (not an `import x = require()`).
struct CtiImport {
	node       C.TSNode
	source     C.TSNode
	type_only  bool // importKind 'type'
	specifiers []CtiSpecifier
	attributes int
}

// CtiReport is ReportValueImport.
struct CtiReport {
	declaration       CtiImport
	type_specifiers   []CtiSpecifier
	value_specifiers  []CtiSpecifier
	unused_specifiers []CtiSpecifier
	inline_specifiers []CtiSpecifier
}

// CtiSource is SourceImports: the imports of one module source (index into the imports).
struct CtiSource {
mut:
	reports                 []CtiReport
	type_only_named_import  int = -1
	value_import            int = -1
	value_only_named_import int = -1
}

fn (mut c Checker) lint_consistent_type_imports(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := cti_options(c.rule_options(consistent_type_imports))!
	mut findings := []Finding{}
	mut checked := 0
	if o.disallow_type_annotations {
		// TSImportType
		for node in c.nodes_of_kind(root, c'import_type') {
			checked++
			// The TSImportType has the type arguments: `import('x').A<T>` is a generic_type around
			// the import_type for tree-sitter.
			mut whole := node
			if parent := node_parent(node) {
				if node_kind(parent) == 'generic_type' {
					if name := node_field(parent, 'name') {
						if node_key(name) == node_key(node) {
							whole = parent
						}
					}
				}
			}
			findings << Finding{
				stmt:       c.position_range(node_start(node), c.es_end(whole))
				message_id: 'noImportTypeAnnotations'
			}
		}
	}
	mut imports := []CtiImport{}
	for node in c.nodes_of_kind(root, c'import_statement') {
		if declaration := c.cti_import(node) {
			imports << declaration
		}
	}
	if !o.prefer_type_imports {
		for declaration in imports {
			checked++
			if declaration.type_only {
				mut fixes := []Fix{}
				if fix := c.cti_remove_type_from_declaration(declaration) {
					fixes << fix
				}
				findings << c.with_fixes(Finding{
					stmt:       position_of(declaration.node)
					message_id: 'avoidImportType'
				}, fixes)!
			}
			for specifier in declaration.specifiers {
				if specifier.inline_type {
					mut fixes := []Fix{}
					if fix := c.cti_remove_type_from_specifier(specifier) {
						fixes << fix
					}
					findings << c.with_fixes(Finding{
						stmt:       position_of(specifier.node)
						message_id: 'avoidImportType'
					}, fixes)!
				}
			}
		}
		stats.eval_ms += ms(sw.elapsed())
		stats.checked += checked
		return findings
	}
	// With decorator metadata, a file with a decorator is not checked.
	if c.decorator_metadata && c.nodes_of_kind(root, c'decorator').len > 0 {
		stats.eval_ms += ms(sw.elapsed())
		return findings
	}
	tree := c.scope_tree(root)
	mut sources := map[string]CtiSource{}
	mut order := []string{}
	for index, declaration in imports {
		checked++
		key := c.nsh_string_value(declaration.source)
		if key !in sources {
			sources[key] = CtiSource{}
			order << key
		}
		mut source := sources[key]
		named_only := declaration.specifiers.all(it.kind == .named)
		if declaration.type_only {
			if source.type_only_named_import < 0 && named_only {
				source.type_only_named_import = index
			}
		} else if source.value_only_named_import < 0 && declaration.specifiers.len > 0 && named_only {
			source.value_only_named_import = index
			source.value_import = index
		} else if source.value_import < 0 && declaration.specifiers.any(it.kind == .default_) {
			source.value_import = index
		}
		mut type_specifiers := []CtiSpecifier{}
		mut value_specifiers := []CtiSpecifier{}
		mut unused_specifiers := []CtiSpecifier{}
		mut inline_specifiers := []CtiSpecifier{}
		for specifier in declaration.specifiers {
			if specifier.inline_type {
				inline_specifiers << specifier
				continue
			}
			v := tree.declared_variable(specifier.local)
			if v < 0 {
				continue
			}
			references := tree.variables[v].references
			if references.len == 0 {
				unused_specifiers << specifier
			} else if references.all(cti_is_type_reference(tree.references[it], declaration.type_only)) {
				type_specifiers << specifier
			} else {
				value_specifiers << specifier
			}
		}
		if !declaration.type_only && type_specifiers.len > 0 {
			source.reports << CtiReport{
				declaration:       declaration
				type_specifiers:   type_specifiers
				value_specifiers:  value_specifiers
				unused_specifiers: unused_specifiers
				inline_specifiers: inline_specifiers
			}
		}
		sources[key] = source
	}
	// Program:exit
	for key in order {
		source := sources[key]
		for report in source.reports {
			declaration := report.declaration
			if report.value_specifiers.len == 0 && report.unused_specifiers.len == 0 {
				// With import attributes it is not reported.
				if declaration.attributes == 0 {
					fixes := c.cti_fix_to_type_import(report, source, imports, o)
					findings << c.with_fixes(Finding{
						stmt:       position_of(declaration.node)
						message_id: 'typeOverValue'
					}, fixes)!
				}
				continue
			}
			type_names := report.type_specifiers.map('"${tree.variables[tree.declared_variable(it.local)].name}"')
			fixes := c.cti_fix_to_type_import(report, source, imports, o)
			findings << c.with_fixes(Finding{
				stmt:       position_of(declaration.node)
				message_id: 'someImportsAreOnlyTypes'
				data:       {
					'typeImports': cti_word_list(type_names)
				}
			}, fixes)!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// cti_word_list ports formatWordList: `a`, `a and b`, `a, b and c`.
fn cti_word_list(words []string) string {
	if words.len == 0 {
		return ''
	}
	if words.len == 1 {
		return words[0]
	}
	return [words[..words.len - 1].join(', '), words.last()].join(' and ')
}

// cti_import reads an ImportDeclaration: none for an `import x = require()`.
fn (c &Checker) cti_import(node C.TSNode) ?CtiImport {
	if has_child_kind(node, 'import_require_clause') {
		return none
	}
	source := node_field(node, 'source')?
	mut specifiers := []CtiSpecifier{}
	mut attributes := 0
	for part in named_children(node) {
		match node_kind(part) {
			'import_clause' {
				for clause in named_children(part) {
					match node_kind(clause) {
						'identifier' {
							specifiers << CtiSpecifier{
								node:  clause
								local: clause
								kind:  .default_
							}
						}
						'namespace_import' {
							if local := first_named(clause) {
								specifiers << CtiSpecifier{
									node:  clause
									local: local
									kind:  .namespace
								}
							}
						}
						'named_imports' {
							for specifier in named_children(clause) {
								if node_kind(specifier) != 'import_specifier' {
									continue
								}
								name := node_field(specifier, 'name') or { continue }
								local := node_field(specifier, 'alias') or { name }
								specifiers << CtiSpecifier{
									node:        specifier
									local:       local
									kind:        .named
									inline_type: node_start(name) != node_start(specifier)
								}
							}
						}
						else {}
					}
				}
			}
			'import_attribute' {
				if object := first_named(part) {
					attributes = named_children(object).filter(node_kind(it) != 'comment').len
				}
			}
			else {}
		}
	}
	return CtiImport{
		node:       node
		source:     source
		type_only:  has_child_kind(node, 'type')
		specifiers: specifiers
		attributes: attributes
	}
}

// cti_estree_parent is the ESTree parent of an identifier: its parent without parentheses.
fn cti_estree_parent(n C.TSNode) ?C.TSNode {
	mut parent := node_parent(n)?
	for node_kind(parent) == 'parenthesized_expression' {
		parent = node_parent(parent)?
	}
	return parent
}

// cti_is_type_reference is the test of onlyHasTypeReferences for one reference: an export of the
// name keeps the kind of the import; a value reference counts as a type one inside `typeof` and
// in the computed key of a property signature; any other reference by its kind.
fn cti_is_type_reference(reference ScopeReference, type_only bool) bool {
	identifier := reference.identifier
	if reference.value_ref && reference.type_ref {
		if parent := cti_estree_parent(identifier) {
			kind := node_kind(parent)
			// ExportSpecifier, ExportDefaultDeclaration and TSExportAssignment.
			if kind == 'export_specifier' || (kind == 'export_statement'
				&& (has_child_kind(parent, 'default') || has_child_kind(parent, '='))) {
				return type_only
			}
		}
	}
	if !reference.value_ref {
		return reference.type_ref
	}
	mut child := identifier
	mut parent := node_parent(identifier) or { return false }
	for {
		match node_kind(parent) {
			'type_query' {
				return true
			}
			'member_expression', 'subscript_expression', 'nested_identifier' {
				// TSQualifiedName or MemberExpression: only through its left side or object.
				object := node_field(parent, 'object') or {
					node_field(parent, 'module') or { return false }
				}
				if node_key(object) != node_key(child) {
					return false
				}
			}
			'instantiation_expression' {
				// `typeof f<T>`: the name of a TSTypeQuery with type arguments.
				if node_kind(child) == 'type_arguments' {
					return false
				}
			}
			'computed_property_name' {}
			'property_signature' {
				// TSPropertySignature: the reference is (in) its computed key.
				name := node_field(parent, 'name') or { return false }
				return node_key(name) == node_key(child)
			}
			else {
				return false
			}
		}
		child = parent
		parent = node_parent(parent) or { return false }
	}
	return false
}

// cti_matches tells the tokens the fixers look for: a punctuator, or the `import` keyword, or
// the `type` identifier (isImportKeyword, isTypeKeyword).
fn (c &Checker) cti_matches(t SourceToken, want string) bool {
	return match want {
		'import' { t.kind == .keyword && c.token_text(t) == want }
		'type' { t.kind == .identifier && c.token_text(t) == want }
		else { c.token_is(t, want) }
	}
}

// cti_token_before ports getTokenBefore(offset, filter): the last token before `offset` that is
// `want`.
fn (mut c Checker) cti_token_before(n C.TSNode, offset int, want string) ?SourceToken {
	tokens := c.source_tokens(n).tokens
	mut i := source_tokens_index(tokens, offset) - 1
	for i >= 0 {
		if c.cti_matches(tokens[i], want) {
			return tokens[i]
		}
		i--
	}
	return none
}

// cti_token_after ports getTokenAfter(offset, filter): the first token from `offset` on that is
// `want`.
fn (mut c Checker) cti_token_after(n C.TSNode, offset int, want string) ?SourceToken {
	tokens := c.source_tokens(n).tokens
	for i in source_tokens_index(tokens, offset) .. tokens.len {
		if c.cti_matches(tokens[i], want) {
			return tokens[i]
		}
	}
	return none
}

// cti_token_between ports getFirstTokenBetween(left, right, filter) for what ends at `start` and
// what starts at `end` (and getFirstToken(node, filter) for the range of a node).
fn (mut c Checker) cti_token_between(n C.TSNode, start int, end int, want string) ?SourceToken {
	for token in c.source_tokens(n).inside(start, end, false) {
		if c.cti_matches(token, want) {
			return token
		}
	}
	return none
}

// cti_end is the end of the ESTree range of a statement: its last token (tree-sitter may take a
// comment after a statement without `;`).
fn (c &Checker) cti_end(n C.TSNode) int {
	return c.tokens.last_end(node_end(n))
}

// cti_remove_type_from_declaration ports fixRemoveTypeSpecifierFromImportDeclaration: the `type`
// of `import type` and the space up to the next token or comment.
fn (mut c Checker) cti_remove_type_from_declaration(declaration CtiImport) ?Fix {
	node := declaration.node
	import_token := c.cti_token_between(node, node_start(node), c.cti_end(node), 'import')?
	limit := if declaration.specifiers.len > 0 {
		node_start(declaration.specifiers[0].local)
	} else {
		node_start(declaration.source)
	}
	type_token := c.cti_token_between(node, import_token.end, limit, 'type')?
	after := c.source_tokens(node).after(type_token.end, true)?
	return fix_remove_range(type_token.start, after.start)
}

// cti_remove_type_from_specifier ports fixRemoveTypeSpecifierFromImportSpecifier: the `type` of an
// import specifier and the space after it.
fn (mut c Checker) cti_remove_type_from_specifier(specifier CtiSpecifier) ?Fix {
	node := specifier.node
	type_token := c.cti_token_between(node, node_start(node), node_end(node), 'type')?
	after := c.source_tokens(node).after(type_token.end, true)?
	return fix_remove_range(type_token.start, after.start)
}

// cti_fix_insert_type ports fixInsertTypeSpecifierForImportDeclaration: `import type …`, moving
// the named specifiers of `import Foo, {…}` to an import of their own, and removing the `type`
// of the specifiers.
fn (mut c Checker) cti_fix_insert_type(declaration CtiImport, is_default bool) []Fix {
	node := declaration.node
	mut fixes := []Fix{}
	import_token := c.cti_token_between(node, node_start(node), c.cti_end(node), 'import') or {
		return fixes
	}
	fixes << fix_insert_at(import_token.end, ' type')
	if is_default {
		if opening := c.cti_token_between(node, import_token.end, node_start(declaration.source),
			'{')
		{
			comma := c.cti_token_before(node, opening.start, ',') or { return fixes }
			closing := c.cti_token_between(node, opening.end, node_start(declaration.source),
				'}') or { return fixes }
			fixes << fix_remove_range(comma.start, closing.end)
			specifiers_text := c.src[comma.end..closing.end]
			if declaration.specifiers.len > 1 {
				fixes << fix_insert_at(c.cti_end(node), '\nimport type${specifiers_text} from ${c.text(declaration.source)};')
			}
		}
	}
	for specifier in declaration.specifiers {
		if specifier.inline_type {
			if fix := c.cti_remove_type_from_specifier(specifier) {
				fixes << fix
			}
		}
	}
	return fixes
}

// cti_named_specifier_ranges ports getNamedSpecifierRanges: what to remove for a group of
// consecutive named specifiers, and the text they take.
fn (mut c Checker) cti_named_specifier_ranges(group []CtiSpecifier, all []CtiSpecifier) ?(int, int, int, int) {
	first := group[0]
	last := group.last()
	mut remove_start := node_start(first.node)
	mut remove_end := node_end(last.node)
	before := c.source_tokens(first.node).before(node_start(first.node), false)?
	text_start := before.end
	remove_start = if c.token_is(before, ',') { before.start } else { before.end }
	is_first := all[0].same(first)
	is_last := all.last().same(last)
	after := c.source_tokens(last.node).after(node_end(last.node), false)?
	text_end := after.start
	if (is_first || is_last) && c.token_is(after, ',') {
		remove_end = after.end
	}
	return remove_start, remove_end, text_start, text_end
}

// cti_named_fixes ports getFixesNamedSpecifiers: the fixes that remove the type specifiers among
// the named ones, and their text for a type import.
fn (mut c Checker) cti_named_fixes(declaration CtiImport, subset []CtiSpecifier, all []CtiSpecifier) ([]Fix, string) {
	if all.len == 0 {
		return []Fix{}, ''
	}
	node := declaration.node
	mut texts := []string{}
	mut removes := []Fix{}
	if subset.len == all.len {
		// `import Foo, {Type1, Type2} from 'foo'`: the comma and the braces go.
		opening := c.cti_token_before(node, node_start(subset[0].node), '{') or {
			return removes, ''
		}
		comma := c.cti_token_before(node, opening.start, ',') or { return removes, '' }
		closing := c.cti_token_between(node, opening.end, node_start(declaration.source),
			'}') or { return removes, '' }
		removes << fix_remove_range(comma.start, closing.end)
		texts << c.src[opening.end..closing.start]
	} else {
		mut groups := [][]CtiSpecifier{}
		mut group := []CtiSpecifier{}
		for specifier in all {
			if subset.any(it.same(specifier)) {
				group << specifier
			} else if group.len > 0 {
				groups << group
				group = []CtiSpecifier{}
			}
		}
		if group.len > 0 {
			groups << group
		}
		for specifiers in groups {
			remove_start, remove_end, text_start, text_end := c.cti_named_specifier_ranges(specifiers,
				all) or { continue }
			removes << fix_remove_range(remove_start, remove_end)
			texts << c.src[text_start..text_end]
		}
	}
	return removes, texts.join(',')
}

// cti_fix_insert_named ports fixInsertNamedSpecifiersInNamedSpecifierList: the text goes before
// the `}` of the target import, after a comma when it needs one.
fn (mut c Checker) cti_fix_insert_named(target CtiImport, text string) ?Fix {
	node := target.node
	first := c.first_token(node)?
	closing := c.cti_token_between(node, first.end, node_start(target.source), '}')?
	before := c.source_tokens(node).before(closing.start, false)?
	insert := if !c.token_is(before, ',') && !c.token_is(before, '{') { ',${text}' } else { text }
	return fix_insert_at(closing.start, insert)
}

// cti_fix_inline_type_keywords ports fixInsertTypeKeywordInNamedSpecifierList: `type` before each
// specifier.
fn (c &Checker) cti_fix_inline_type_keywords(specifiers []CtiSpecifier) []Fix {
	return specifiers.map(fix_replace(it.node, 'type ${c.text(it.node)}'))
}

// cti_fix_inline ports fixInlineTypeImportDeclaration: the type named specifiers get `type` when
// the source has a value import with named specifiers.
fn (c &Checker) cti_fix_inline(report CtiReport, source CtiSource, imports []CtiImport) []Fix {
	named := report.declaration.specifiers.filter(it.kind == .named)
	type_named := named.filter(cti_has(report.type_specifiers, it))
	if source.value_import >= 0 {
		value_named := imports[source.value_import].specifiers.filter(it.kind == .named)
		if source.value_only_named_import >= 0 || value_named.len > 0 {
			return c.cti_fix_inline_type_keywords(type_named)
		}
	}
	return []Fix{}
}

fn cti_has(list []CtiSpecifier, specifier CtiSpecifier) bool {
	return list.any(it.same(specifier))
}

// cti_fix_to_type_import ports fixToTypeImportDeclaration.
fn (mut c Checker) cti_fix_to_type_import(report CtiReport, source CtiSource, imports []CtiImport, o CtiOptions) []Fix {
	declaration := report.declaration
	node := declaration.node
	mut default_specifier := ?CtiSpecifier(none)
	if declaration.specifiers.len > 0 && declaration.specifiers[0].kind == .default_ {
		default_specifier = declaration.specifiers[0]
	}
	mut namespace_specifier := ?CtiSpecifier(none)
	for specifier in declaration.specifiers {
		if specifier.kind == .namespace {
			namespace_specifier = specifier
			break
		}
	}
	named := declaration.specifiers.filter(it.kind == .named)
	if _ := namespace_specifier {
		if default_specifier == none {
			// import * as types from 'foo'
			if declaration.attributes == 0 {
				return c.cti_fix_insert_type(declaration, false)
			}
			return []Fix{}
		}
	}
	if default_ := default_specifier {
		if cti_has(report.type_specifiers, default_) && named.len == 0 && namespace_specifier == none {
			// import Type from 'foo'
			return c.cti_fix_insert_type(declaration, true)
		}
		if o.inline_type_imports && !cti_has(report.type_specifiers, default_) && named.len > 0
			&& namespace_specifier == none {
			// import AValue, {BValue, Type1, Type2} from 'foo'
			return c.cti_fix_inline(report, source, imports)
		}
	} else if namespace_specifier == none {
		if o.inline_type_imports && named.any(cti_has(report.type_specifiers, it)) {
			// import {AValue, Type1, Type2} from 'foo'
			return c.cti_fix_inline(report, source, imports)
		}
		if named.all(cti_has(report.type_specifiers, it)) {
			// import {Type1, Type2} from 'foo'
			return c.cti_fix_insert_type(declaration, false)
		}
	}
	type_named := named.filter(cti_has(report.type_specifiers, it))
	removes, type_named_text := c.cti_named_fixes(declaration, type_named, named)
	mut fixes := []Fix{}
	mut after_fixes := []Fix{}
	source_text := c.text(declaration.source)
	if type_named.len > 0 {
		if source.type_only_named_import >= 0 {
			target := imports[source.type_only_named_import]
			if insert := c.cti_fix_insert_named(target, type_named_text) {
				if c.cti_end(target.node) <= node_start(node) {
					fixes << insert
				} else {
					after_fixes << insert
				}
			}
		} else if o.inline_type_imports {
			// The import is both default and named: the named types go to a new line.
			fixes << fix_insert_at(node_start(node), 'import {${type_named.map('type ${c.text(it.node)}').join(', ')}} from ${source_text};\n')
		} else {
			fixes << fix_insert_at(node_start(node), 'import type {${type_named_text}} from ${source_text};\n')
		}
	}
	mut remove_namespace := []Fix{}
	if namespace := namespace_specifier {
		if cti_has(report.type_specifiers, namespace) {
			// import Foo, * as Type from 'foo'
			if comma := c.cti_token_before(node, node_start(namespace.node), ',') {
				remove_namespace << fix_remove_range(comma.start, node_end(namespace.node))
			}
			fixes << fix_insert_at(node_start(node), 'import type ${c.text(namespace.node)} from ${source_text};\n')
		}
	}
	if default_ := default_specifier {
		if cti_has(report.type_specifiers, default_) {
			if report.type_specifiers.len == declaration.specifiers.len {
				// import type Type from 'foo'
				if import_token := c.cti_token_between(node, node_start(node), c.cti_end(node),
					'import')
				{
					fixes << fix_insert_at(import_token.end, ' type')
				}
			} else if comma := c.cti_token_after(node, node_end(default_.node), ',') {
				// import Type , {...} from 'foo'
				default_text := js_trim(c.src[node_start(default_.node)..comma.start])
				fixes << fix_insert_at(node_start(node), 'import type ${default_text} from ${source_text};\n')
				if after := c.source_tokens(node).after(comma.end, true) {
					fixes << fix_remove_range(node_start(default_.node), after.start)
				}
			}
		}
	}
	fixes << removes
	fixes << remove_namespace
	fixes << after_fixes
	return fixes
}
