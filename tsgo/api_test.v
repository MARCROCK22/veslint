module tsgo

import json2
import os
import time

// Requests of the API against the real tsgo, on a small project.

const api_test_source = 'namespace N {
  export const x = 1;
  const y = x;
}
import A = N;
function f(this: object, a: number, ...rest: string[]) {}
function g<T>(a?: T) {}
'

// api_test_handle is the handle of the innermost node of `kind` (0: any) that spans `text` at the
// end of the first `context`, with pos at the end of the previous token (ASCII source).
fn api_test_handle(ast SourceFileAst, context string, text string, kind u32) string {
	start := (api_test_source.index(context) or { panic('no `${context}`') }) + context.len - text.len
	mut pos := start
	for pos > 0 && api_test_source[pos - 1] in [` `, `\n`] {
		pos--
	}
	return ast.handle(pos, start + text.len, kind) or { panic('no node for `${text}`') }
}

fn test_symbol_and_signature_requests() {
	bin := os.join_path(@VMODROOT, rel_path)
	if !os.is_file(bin) {
		eprintln('skipped: ${bin} is missing')
		return
	}
	dir := os.join_path(os.temp_dir(), 'veslint-api-test-${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	tsconfig := os.join_path(dir, 'tsconfig.json')
	file := os.join_path(dir, 'a.ts')
	os.write_file(tsconfig, '{"compilerOptions":{"strict":true,"noEmit":true},"include":["*.ts"]}') or {
		panic(err)
	}
	os.write_file(file, api_test_source) or { panic(err) }
	mut c := start(bin, dir, 20 * time.second) or { panic(err) }
	defer {
		c.shutdown()
	}
	c.initialize() or { panic(err) }
	snap := c.create_snapshot([tsconfig]) or { panic(err) }
	project := snap.projects[0].id
	s := snap.snapshot
	ast := c.source_file_ast(s, project, file) or { panic(err) }

	// resolveName from a node: inside the namespace, `x` is the exported constant. With the Value
	// meaning it is the export symbol (of N); with ExportValue too, the local symbol, whose export
	// symbol is that one.
	x_use := api_test_handle(ast, 'const y = x', 'x', 0)
	x := c.resolve_name_at(s, project, 'x', 111551, x_use, false) or { panic(err) }
	assert x.name == 'x' && x.export_symbol == 0
	local := c.resolve_name_at(s, project, 'x', 111551 | 1048576, x_use, false) or { panic(err) }
	assert local.name == 'x'
	assert local.export_symbol != 0
	assert local.id != x.id
	exported := c.export_symbol_of_symbol(s, project, local) or { panic(err) }
	assert exported.id == x.id
	assert c.resolve_name_at(s, project, 'missing', 111551, x_use, false) or { panic(err) }.is_null()
	// A symbol without an export symbol is its own.
	y := c.resolve_name_at(s, project, 'y', 111551, x_use, false) or { panic(err) }
	assert y.name == 'y' && y.export_symbol == 0
	assert c.export_symbol_of_symbol(s, project, y) or { panic(err) }.id == y.id

	// getAliasedSymbol of `import A = N`.
	a_use := api_test_handle(ast, 'function f', 'f', 0)
	alias := c.resolve_name_at(s, project, 'A', 1920, a_use, false) or { panic(err) }
	assert alias.name == 'A'
	assert alias.flags & 2097152 != 0 // SymbolFlags.Alias
	aliased := c.aliased_symbol(s, project, alias.id) or { panic(err) }
	assert aliased.name == 'N'

	// getSignatureFromDeclaration: its declaration, `this` parameter, type parameters and the
	// flags and value declarations of its parameters.
	f_decl := api_test_handle(ast, 'function f(this: object, a: number, ...rest: string[]) {}',
		'function f(this: object, a: number, ...rest: string[]) {}', 264)
	f_sig := c.signature_from_declaration(s, project, f_decl) or { panic(err) }
	assert f_sig.id != 0
	assert f_sig.declaration == f_decl
	assert f_sig.this_parameter != 0
	assert f_sig.type_parameters.len == 0
	f_params := c.parameters_of_signature(s, project, f_sig.id) or { panic(err) }
	assert f_params.map(it.name) == ['a', 'rest']
	assert handle_kind(f_params[1].value_declaration) == 171 // SyntaxKind.Parameter
	g_decl := api_test_handle(ast, 'function g<T>(a?: T) {}', 'function g<T>(a?: T) {}', 264)
	g_sig := c.signature_from_declaration(s, project, g_decl) or { panic(err) }
	assert g_sig.type_parameters.len == 1
	assert g_sig.this_parameter == 0
	// A declared parameter is a FunctionScopedVariable; TypeScript only marks Optional the
	// parameters of the signatures it synthesizes, not a declared `a?`.
	g_params := c.parameters_of_signature(s, project, g_sig.id) or { panic(err) }
	assert g_params[0].flags & 1 != 0
	assert g_params[0].flags & 16777216 == 0
	// tsgo fails (a Go nil dereference it reports as an error) on a node that is not a
	// function-like declaration: callers must not send one.
	if _ := c.signature_from_declaration(s, project, x_use) {
		assert false
	}
	assert c.signature_from_declaration(s, project, g_decl) or { panic(err) }.id == g_sig.id
}

const api_test_types_source = 'type Box<T> = { value: T };
declare const box: Box<string>;
declare const pair: readonly [string, number];
declare const table: { readonly [key: string]: number };
declare function constant<const T>(value: T): T;
const inferred = constant({ x: 1 });
'

// Alias type arguments, readonly tuple targets and index signatures, and the void type.
fn test_type_details() {
	bin := os.join_path(@VMODROOT, rel_path)
	if !os.is_file(bin) {
		eprintln('skipped: ${bin} is missing')
		return
	}
	dir := os.join_path(os.temp_dir(), 'veslint-api-types-test-${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	tsconfig := os.join_path(dir, 'tsconfig.json')
	file := os.join_path(dir, 'a.ts')
	os.write_file(tsconfig, '{"compilerOptions":{"strict":true,"noEmit":true},"include":["*.ts"]}') or {
		panic(err)
	}
	os.write_file(file, api_test_types_source) or { panic(err) }
	mut c := start(bin, dir, 20 * time.second) or { panic(err) }
	defer {
		c.shutdown()
	}
	c.initialize() or { panic(err) }
	snap := c.create_snapshot([tsconfig]) or { panic(err) }
	project := snap.projects[0].id
	s := snap.snapshot
	ast := c.source_file_ast(s, project, file) or { panic(err) }
	mut handles := []string{}
	for name in ['box', 'pair', 'table', 'inferred'] {
		start := api_test_types_source.index('const ${name}') or { panic(name) } + 6
		handles << ast.handle(start - 1, start + name.len, 0) or { panic('no node for ${name}') }
	}
	types := c.types_at_locations(s, project, handles) or { panic(err) }
	box, pair, table, inferred := types[0], types[1], types[2], types[3]
	assert box.alias_type_arguments.len == 1
	args := c.alias_type_arguments_of_type(s, project, box.id) or { panic(err) }
	assert args.len == 1 && args[0].intrinsic_name == 'string'
	assert pair.alias_type_arguments.len == 0
	assert c.alias_type_arguments_of_type(s, project, pair.id) or { panic(err) }.len == 0
	target := c.target_of_type(s, project, pair.id) or { panic(err) }
	assert target.readonly
	infos := c.index_infos_of_type(s, project, table.id) or { panic(err) }
	assert infos.len == 1 && infos[0].is_readonly
	// The property a const type parameter infers is readonly: CheckFlags.Readonly (8).
	props := c.properties_of_type(s, project, inferred.id) or { panic(err) }
	assert props.len == 1 && props[0].check_flags & 8 != 0
	void := c.void_type(s, project) or { panic(err) }
	assert void.flags == 16 && void.intrinsic_name == 'void'
}

fn test_exact_optional_property_types_option() {
	on := json2.decode[CompilerOptions]('{"exactOptionalPropertyTypes":true}') or { panic(err) }
	assert on.exact_optional_property_types_enabled()
	off := json2.decode[CompilerOptions]('{"strict":true}') or { panic(err) }
	assert !off.exact_optional_property_types_enabled()
}

// The libs typescript-eslint's scope manager takes (getLib), from the options as tsgo sends them.
fn test_lib_names() {
	for text, want in {
		'{"lib":["lib.es2022.d.ts","lib.dom.d.ts"],"target":9}':      ['es2022', 'dom']
		'{"lib":["LIB.ES5.D.TS","es2015","lib.d.ts","lib.x.d.mts"]}': ['es5', 'x']
		'{"lib":[]}':                                                 []string{}
		'{"target":9}':                                               ['es2022.full']
		'{"target":2}':                                               ['es6']
		'{"target":3}':                                               ['es2016.full']
		'{"target":12}':                                              ['es2025.full']
		'{"target":99}':                                              ['esnext.full']
		'{"target":1}':                                               ['lib']
		'{"target":100}':                                             ['lib']
		'{"strict":true}':                                            ['es2025.full']
	} {
		options := json2.decode[CompilerOptions](text) or { panic(err) }
		assert options.lib_names() == want, text
	}
}

// What the real tsgo sends for `lib`, `target` and the JSX factories.
fn test_lib_and_target_of_a_project() {
	bin := os.join_path(@VMODROOT, rel_path)
	if !os.is_file(bin) {
		eprintln('skipped: ${bin} is missing')
		return
	}
	dir := os.join_path(os.temp_dir(), 'veslint-api-lib-test-${os.getpid()}')
	os.mkdir_all(os.join_path(dir, 'target')) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	with_lib := os.join_path(dir, 'tsconfig.json')
	with_target := os.join_path(dir, 'target', 'tsconfig.json')
	os.write_file(with_lib, '{"compilerOptions":{"noEmit":true,"target":"es2022","lib":["ES2020","dom.iterable"],"jsx":"react","jsxFactory":"h.create","jsxFragmentFactory":"Frag"},"include":["*.ts"]}') or {
		panic(err)
	}
	os.write_file(with_target, '{"compilerOptions":{"noEmit":true,"target":"es2021"},"include":["*.ts"]}') or {
		panic(err)
	}
	os.write_file(os.join_path(dir, 'a.ts'), 'export const a = 1;\n') or { panic(err) }
	os.write_file(os.join_path(dir, 'target', 'b.ts'), 'export const b = 1;\n') or { panic(err) }
	mut c := start(bin, dir, 20 * time.second) or { panic(err) }
	defer {
		c.shutdown()
	}
	c.initialize() or { panic(err) }
	snap := c.create_snapshot([with_lib, with_target]) or { panic(err) }
	assert snap.projects.len == 2
	for project in snap.projects {
		if project.config_file_name == with_lib {
			assert project.compiler_options().lib_names() == ['es2020', 'dom.iterable']
			assert project.compiler_options().jsx_factory or { '' } == 'h.create'
			assert project.compiler_options().jsx_fragment_factory or { '' } == 'Frag'
		} else {
			assert project.compiler_options().lib_names() == ['es2021.full']
			assert project.compiler_options().jsx_factory == none
			assert project.compiler_options().jsx_fragment_factory == none
		}
	}
}

// parseConfigFile gives the parsed tsconfig as the project of a snapshot has it (the command line
// takes it when no rule needs types): the options of an `extends` chain and the root files.
fn test_parse_config_file() {
	bin := os.join_path(@VMODROOT, rel_path)
	if !os.is_file(bin) {
		eprintln('skipped: ${bin} is missing')
		return
	}
	dir := os.join_path(os.temp_dir(), 'veslint-api-config-test-${os.getpid()}')
	os.mkdir_all(os.join_path(dir, 'src')) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	tsconfig := os.join_path(dir, 'tsconfig.json')
	os.write_file(os.join_path(dir, 'tsconfig.base.json'), '{"compilerOptions":{"strict":true,"lib":["ES2021","DOM"],"jsx":"react","jsxFactory":"h"}}') or {
		panic(err)
	}
	os.write_file(tsconfig, '{"extends":"./tsconfig.base.json","compilerOptions":{"noEmit":true,"experimentalDecorators":true,"emitDecoratorMetadata":true,"jsxFragmentFactory":"Frag"},"include":["src"]}') or {
		panic(err)
	}
	os.write_file(os.join_path(dir, 'src', 'a.ts'), 'export const a = 1;\n') or { panic(err) }
	os.write_file(os.join_path(dir, 'src', 'b.tsx'), 'export const b = <div />;\n') or {
		panic(err)
	}
	mut c := start(bin, dir, 20 * time.second) or { panic(err) }
	defer {
		c.shutdown()
	}
	c.initialize() or { panic(err) }
	parsed := c.parse_config_file(tsconfig) or { panic(err) }
	snap := c.create_snapshot([tsconfig]) or { panic(err) }
	assert snap.projects.len == 1
	assert json2.encode(parsed) == json2.encode(snap.projects[0].parsed_command_line)
	assert parsed.options.lib_names() == ['es2021', 'dom']
	assert parsed.options.jsx_factory or { '' } == 'h'
	assert parsed.options.jsx_fragment_factory or { '' } == 'Frag'
	assert parsed.options.experimental_decorators or { false }
	assert parsed.options.emit_decorator_metadata or { false }
	assert parsed.file_names.len == 2
}

const api_test_alias_source = 'const base = 1;
export { base as first };
const shorthand = 1;
export const literal = { shorthand, long: shorthand };
'

// Imports `first` (an alias of an alias) and a name a.ts does not export.
const api_test_alias_importer = "import { first, missing } from './a';
void first;
void missing;
"

// api_test_identifier is the handle of the first Identifier named `name` in a preorder walk.
fn api_test_identifier(tree AstTree, index int, name string) ?string {
	if tree.node_kind(index) == kind_identifier && tree.node_text(index) == name {
		return tree.node_handle(index)
	}
	for child in tree.node_children(index) {
		if handle := api_test_identifier(tree, child, name) {
			return handle
		}
	}
	return none
}

// getImmediateAliasedSymbol (one step of a chain of aliases, null without a target) and
// getShorthandAssignmentValueSymbol.
fn test_alias_and_shorthand_requests() {
	bin := os.join_path(@VMODROOT, rel_path)
	if !os.is_file(bin) {
		eprintln('skipped: ${bin} is missing')
		return
	}
	dir := os.join_path(os.temp_dir(), 'veslint-api-alias-test-${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	tsconfig := os.join_path(dir, 'tsconfig.json')
	file := os.join_path(dir, 'a.ts')
	importer := os.join_path(dir, 'b.ts')
	os.write_file(tsconfig, '{"compilerOptions":{"strict":true,"noEmit":true},"include":["*.ts"]}') or {
		panic(err)
	}
	os.write_file(file, api_test_alias_source) or { panic(err) }
	os.write_file(importer, api_test_alias_importer) or { panic(err) }
	mut c := start(bin, dir, 20 * time.second) or { panic(err) }
	defer {
		c.shutdown()
	}
	c.initialize() or { panic(err) }
	snap := c.create_snapshot([tsconfig]) or { panic(err) }
	project := snap.projects[0].id
	s := snap.snapshot
	tree := c.source_file_ast(s, project, file) or { panic(err) }.tree
	imports := c.source_file_ast(s, project, importer) or { panic(err) }.tree
	symbols := c.symbols_at_locations(s, project, [
		api_test_identifier(tree, 1, 'base') or { panic('no base') },
		api_test_identifier(imports, 1, 'first') or { panic('no first') },
		api_test_identifier(imports, 1, 'missing') or { panic('no missing') },
	]) or { panic(err) }
	base, first, missing := symbols[0], symbols[1], symbols[2]
	// The import of `first` refers to the export `first` of a.ts, itself an alias of `base`.
	assert first.flags & 2097152 != 0 // SymbolFlags.Alias
	export_alias := c.immediate_aliased_symbol(s, project, first.id) or { panic(err) }
	assert export_alias.name == 'first' && export_alias.id != first.id
	assert export_alias.flags & 2097152 != 0
	assert (c.immediate_aliased_symbol(s, project, export_alias.id) or { panic(err) }).id == base.id
	assert (c.aliased_symbol(s, project, first.id) or { panic(err) }).id == base.id
	// An import of a name the module does not export has no target.
	assert missing.flags & 2097152 != 0
	assert c.immediate_aliased_symbol(s, project, missing.id) or { panic(err) }.is_null()
	// The symbol of the value of a shorthand property, from its declaration.
	properties := c.properties_of_type(s, project, (c.types_at_locations(s, project, [
		api_test_identifier(tree, 1, 'literal') or { panic('no literal') },
	]) or { panic(err) })[0].id) or { panic(err) }
	shorthand_property := properties.filter(it.name == 'shorthand')[0]
	value := c.shorthand_assignment_value_symbol(s, project, shorthand_property.value_declaration) or {
		panic(err)
	}
	assert value.name == 'shorthand' && value.id != shorthand_property.id
	long_property := properties.filter(it.name == 'long')[0]
	assert c.shorthand_assignment_value_symbol(s, project, long_property.value_declaration) or {
		panic(err)
	}.is_null()
}
