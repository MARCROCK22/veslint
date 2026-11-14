module rules

import json2
import os
import tsgo { TypeResponse, handle_index, handle_path }

// Type specifiers of the options (`allow`, `ignoredTypeNames`…): ports of
// typeMatchesSomeSpecifier, valueMatchesSomeSpecifier, specifierSourceMatches and
// matchesTypeOrBaseType from @typescript-eslint/type-utils 8.72.2, with the three kinds of
// TypeOrValueSpecifier. Two of them read ESLint's program:
// - `from: "file"` compares with program.getCurrentDirectory(). With typescript-eslint's project
//   service (`parserOptions.projectService`) that is the directory of the tsconfig, the
//   Checker's project_directory. With `parserOptions.project`, typescript-estree makes the
//   programs with TypeScript's own compiler hosts (createProgramFromConfigFile, or
//   createWatchCompilerHost outside a single run), whose current directory is the one of the
//   process: the directory ESLint runs in, which the configuration of the file then gives
//   (program_directory). Since typescript-estree 8.72, a single run (the eslint command without
//   --fix) takes the files of the project service from such a program too, made for the closest
//   tsconfig (useSingleRunProgramForProjectService; single_run_program_root in eslint_config.v);
// - `from: "package"` reads program.sourceFileToPackageName, the name TypeScript 6 gives a file
//   it resolved inside a package of node_modules; package_id_name rebuilds it from the path and
//   the package.json of the package, and resolve_package_id_name is typescript-eslint's own
//   fallback without one. The name is compared with the `package` by whole path components.

// TypeScript 7.1.0-beta SyntaxKind values (dist/enums/syntaxKind.enum.js).
const specifier_kind_string_literal = u32(10)
const specifier_kind_module_declaration = u32(269)
const specifier_kind_source_file = u32(308)
// TypeScript 7.1.0-beta SymbolFlags values (dist/enums/symbolFlags.enum.js).
const specifier_symbol_flag_value_module = 512
const specifier_symbol_flag_alias = u32(2097152)

// TypeSpecifier ports TypeOrValueSpecifier: a bare name (from == '') or names from a file (in
// `path` if has_path), from the standard library or from a package (`pkg`).
struct TypeSpecifier {
	names    []string
	from     string
	path     string
	has_path bool
	pkg      string
}

fn type_specifier(item json2.Any) !TypeSpecifier {
	if item is string {
		return TypeSpecifier{
			names: [item]
		}
	}
	if item !is map[string]json2.Any {
		return error('each specifier is a name or an object with `from` and `name`')
	}
	values := item.as_map()
	from_value := values['from'] or { json2.Any(json2.null) }
	if from_value !is string || (from_value as string) !in ['file', 'lib', 'package'] {
		return error('`from` must be "file", "lib" or "package"')
	}
	from := from_value as string
	known := match from {
		'file' { ['from', 'name', 'path'] }
		'package' { ['from', 'name', 'package'] }
		else { ['from', 'name'] }
	}
	for key, _ in values {
		if key !in known {
			return error('a `from: "${from}"` specifier has no `${key}`')
		}
	}
	mut path := ''
	mut has_path := false
	if from == 'file' {
		if value := values['path'] {
			if value !is string {
				return error('`path` must be a string')
			}
			path = value as string
			has_path = true
		}
	}
	mut pkg := ''
	if from == 'package' {
		value := values['package'] or {
			return error('missing `package` in a `from: "package"` specifier')
		}
		if value !is string {
			return error('`package` must be a package name')
		}
		pkg = value as string
	}
	name := values['name'] or { return error('missing `name` in a specifier') }
	mut listed := []string{}
	if name is string {
		listed << name
	} else if name is []json2.Any && name.len > 0 {
		// The schema asks for distinct names, as far as ajv tells them apart.
		for n in name {
			if n !is string {
				return error('`name` must be a name or a list of names')
			}
			listed << n as string
		}
	} else {
		return error('`name` must be a name or a list of names')
	}
	return TypeSpecifier{
		names:    listed
		from:     from
		path:     path
		has_path: has_path
		pkg:      pkg
	}
}

// set_project_directory tells the Checker the directory of the tsconfig of its project, which is
// what `from: "file"` specifiers are relative to.
pub fn (mut c Checker) set_project_directory(directory string) {
	c.project_directory = directory
}

fn (mut c Checker) type_matches_some_specifier(t TypeResponse, specifiers []TypeSpecifier) !bool {
	for s in specifiers {
		if c.type_matches_specifier(t, s)! {
			return true
		}
	}
	return false
}

// type_matches_specifier ports typeMatchesSpecifier: a union matches if all its parts match; an
// intersection, if it matches as a whole or any of its parts does.
fn (mut c Checker) type_matches_specifier(t TypeResponse, s TypeSpecifier) !bool {
	if t.flags & type_flag_union != 0 {
		for part in c.members_of(t)! {
			if !c.type_matches_specifier(part, s)! {
				return false
			}
		}
		return true
	}
	if c.whole_type_matches(t, s)! {
		return true
	}
	if t.flags & type_flag_intersection != 0 {
		for part in c.members_of(t)! {
			if c.type_matches_specifier(part, s)! {
				return true
			}
		}
	}
	return false
}

fn (mut c Checker) whole_type_matches(t TypeResponse, s TypeSpecifier) !bool {
	if is_error_type(t) || !c.specifier_name_matches(t, s.names)! {
		return false
	}
	if s.from == '' {
		return true
	}
	// specifierSourceMatches
	symbol := c.specifier_symbol(t)!
	declarations := symbol.declarations
	if s.from == 'file' {
		return c.declared_in_file(s, declarations)!
	}
	if s.from == 'package' {
		return c.declared_in_package(s.pkg, symbol, declarations)!
	}
	// typeDeclaredInLib: without declarations (an intrinsic type) it counts as from the library.
	if declarations.len == 0 {
		return true
	}
	for declaration in declarations {
		if c.is_default_library(handle_path(declaration))! {
			return true
		}
	}
	return false
}

// specifier_symbol is the symbol of the type or, without one, its alias symbol (the null one
// without either): `type.getSymbol() ?? type.aliasSymbol`, whose declarations (tsgo handles) are
// the ones the specifiers look at.
fn (mut c Checker) specifier_symbol(t TypeResponse) !tsgo.SymbolResponse {
	if t.symbol != 0 {
		return c.symbol_of(t)!
	}
	if t.alias_symbol != 0 {
		return c.alias_symbol_of(t)!
	}
	return tsgo.SymbolResponse{}
}

// value_matches_some_specifier ports valueMatchesSomeSpecifier: `static_name` (the name of an
// identifier or of a private name, or the value of a string literal; '' for any other node) is one
// of the names of a specifier. A `from: "package"` one also asks for a declaration of the type of
// the node in that package.
fn (mut c Checker) value_matches_some_specifier(static_name string, specifiers []TypeSpecifier, t TypeResponse) !bool {
	if static_name == '' {
		return false
	}
	for s in specifiers {
		if static_name !in s.names {
			continue
		}
		if s.from != 'package' {
			return true
		}
		symbol := c.specifier_symbol(t)!
		if c.declared_in_package(s.pkg, symbol, symbol.declarations)! {
			return true
		}
	}
	return false
}

// declared_in_file ports typeDeclaredInFile: with a path, some declaration is in that file of the
// project directory; without one, in a file whose path starts with that directory (compared as
// text, like the original, so the node_modules under it count too).
fn (c &Checker) declared_in_file(s TypeSpecifier, declarations []string) !bool {
	directory := if c.program_directory != '' { c.program_directory } else { c.project_directory }
	if directory == '' {
		return error('internal: the Checker has no project directory for `from: "file"` specifiers')
	}
	// tsgo.path_key: on Windows tsgo may write the file in lower case.
	wanted := tsgo.path_key(if s.has_path {
		os.norm_path(os.join_path_single(directory, s.path))
	} else {
		os.norm_path(directory)
	})
	for declaration in declarations {
		file := tsgo.path_key(os.norm_path(handle_path(declaration)))
		if (s.has_path && file == wanted) || (!s.has_path && file.starts_with(wanted)) {
			return true
		}
	}
	return false
}

// declared_in_package ports typeDeclaredInPackageDeclarationFile: some declaration is inside a
// `declare module "<package>"`, or in a file of that package that TypeScript resolved in
// node_modules, or the symbol (`type.getSymbol() ?? type.aliasSymbol`, 0 without one) is an
// export of the ambient module of the package (typeExportedFromDeclareModule).
fn (mut c Checker) declared_in_package(pkg string, symbol tsgo.SymbolResponse, declarations []string) !bool {
	for declaration in declarations {
		if c.declared_in_declare_module(pkg, declaration)! {
			return true
		}
	}
	// typeDeclaredInDeclarationFile: the package id name of the file (a path inside its package,
	// `typescript/lib/typescript.d.ts` or `@types/semver/classes/semver.d.ts`) is in the package,
	// or in its @types package, by whole path components.
	types_name := types_package_name(pkg)
	for declaration in declarations {
		file := handle_path(declaration)
		if !c.file_metadata(file)!.is_from_external_library {
			continue
		}
		mut name := c.package_id_name(file)
		if name == '' {
			name = c.resolve_package_id_name(file)
		}
		if name == '' {
			continue
		}
		without_types := if name.starts_with('@types/') { name['@types/'.len..] } else { name }
		if path_is_in_package(name, pkg) || path_is_in_package(without_types, types_name) {
			return true
		}
	}
	return c.exported_from_declare_module(pkg, symbol)!
}

// path_is_in_package ports pathIsInPackage: the path is the package itself or something inside it,
// by whole path components (`semver` covers `semver/classes/semver.d.ts`, not `semver-compare`).
fn path_is_in_package(path string, pkg string) bool {
	return path == pkg || path.starts_with(pkg + '/')
}

// exported_from_declare_module ports typeExportedFromDeclareModule: the module `"<package>"` that
// checker.resolveName finds from the globals (ValueModule) exports the symbol, itself or through
// an alias.
fn (mut c Checker) exported_from_declare_module(pkg string, symbol tsgo.SymbolResponse) !bool {
	if symbol.is_null() {
		return false
	}
	module := c.client.resolve_name(c.snapshot, c.project, '"${pkg}"', specifier_symbol_flag_value_module)!
	if module.is_null() {
		return false
	}
	for exported in c.client.exports_of_symbol(c.snapshot, c.project, module.id)! {
		resolved := if exported.flags & specifier_symbol_flag_alias != 0 {
			c.client.aliased_symbol(c.snapshot, c.project, exported.id)!
		} else {
			exported
		}
		if !resolved.is_null() && resolved.id == symbol.id {
			return true
		}
	}
	return false
}

// resolve_package_id_name ports resolvePackageIdName, for a file TypeScript gives no package id
// name (one of a linked package reached by a relative import, or of a package.json without
// `version`): the `name` of the closest package.json that has one, from the directory of the file
// up, and the path of the file from there.
fn (mut c Checker) resolve_package_id_name(file string) string {
	mut directory := os.dir(file)
	for {
		if directory !in c.package_root_cache {
			c.package_root_cache[directory] = package_json_name_only(directory)
		}
		name := c.package_root_cache[directory]
		if name != '' {
			return name + file[directory.len..]
		}
		parent := os.dir(directory)
		if parent == directory {
			return ''
		}
		directory = parent
	}
	return ''
}

// package_json_name_only is the `name` of the package.json of a directory, when it is a string
// (ts.readConfigFile, which reads it as JSON with comments); '' otherwise.
fn package_json_name_only(directory string) string {
	text := os.read_file(os.join_path_single(directory, 'package.json')) or { return '' }
	content := json2.decode[json2.Any](text) or { return '' }
	if content !is map[string]json2.Any {
		return ''
	}
	name := content.as_map()['name'] or { return '' }
	return if name is string { name } else { '' }
}

// declared_in_declare_module ports findParentModuleDeclaration: the closest ModuleDeclaration
// around the declaration that is not a `namespace` or `global {}` is `declare module "<package>"`.
fn (mut c Checker) declared_in_declare_module(pkg string, declaration string) !bool {
	tree := c.declaration_ast(handle_path(declaration))!
	mut node := handle_index(declaration)
	for _ in 0 .. max_type_depth * 100 {
		kind := tree.node_kind(node)
		if kind == specifier_kind_source_file || kind == 0 {
			return false
		}
		if kind == specifier_kind_module_declaration {
			name := tree.node_child(node, 'name')
			if tree.node_kind(name) == specifier_kind_string_literal {
				text := tree.node_source_text(name)
				return text.len >= 2 && text[1..text.len - 1] == pkg
			}
			// TypeScript 7 has no NodeFlags.Namespace: a `namespace` is told by its keyword, and the
			// inner declarations of `namespace A.B {}` have none. `global {}` (NodeFlags.
			// GlobalAugmentation, no keyword here) is passed over too.
			parent := tree.node_parent(node)
			nested := tree.node_kind(parent) == specifier_kind_module_declaration
			if !nested && module_keyword(tree.node_source_text(node)) !in ['namespace', ''] {
				return false
			}
		}
		node = tree.node_parent(node)
	}
	return false
}

// module_keyword is the keyword of a module declaration, from its text: 'namespace', 'module' or
// '' (`global`).
fn module_keyword(text string) string {
	mut rest := text.trim_space()
	for {
		mut end := 0
		for end < rest.len && (rest[end].is_letter() || rest[end] == `_`) {
			end++
		}
		word := rest[..end]
		if word in ['export', 'declare', 'default'] {
			rest = rest[end..].trim_space()
			continue
		}
		return if word in ['namespace', 'module'] { word } else { '' }
	}
	return ''
}

// types_package_name is the name of the @types package of a scoped package: `@scope/name` gives
// `scope__name`.
fn types_package_name(pkg string) string {
	if pkg.starts_with('@') {
		slash := pkg.index('/') or { return pkg }
		if slash > 1 {
			return pkg[1..slash] + '__' + pkg[slash + 1..]
		}
	}
	return pkg
}

// package_id_name rebuilds program.sourceFileToPackageName for a file: '' outside node_modules or
// in a package whose package.json has no name and version, and otherwise the name of the package
// and the path of the file inside it (packageIdToPackageName of TypeScript 6's withPackageId, with
// the package directory of parseNodeModuleFromPath).
fn (mut c Checker) package_id_name(file string) string {
	marker := '/node_modules/'
	found := file.last_index(marker) or { return '' }
	start := found + marker.len
	mut end := file.index_after_('/', start)
	if end >= 0 && file[start] == `@` {
		end = file.index_after_('/', end + 1)
	}
	if end < 0 {
		return ''
	}
	directory := file[..end]
	if directory !in c.package_name_cache {
		c.package_name_cache[directory] = package_json_name(directory)
	}
	name := c.package_name_cache[directory]
	return if name == '' { '' } else { name + '/' + file[end + 1..] }
}

// package_json_name is the `name` of the package.json of a directory if it also has a `version`
// (both strings), as TypeScript asks for a package id; '' otherwise.
fn package_json_name(directory string) string {
	text := os.read_file(os.join_path_single(directory, 'package.json')) or { return '' }
	content := json2.decode[json2.Any](text) or { return '' }
	if content !is map[string]json2.Any {
		return ''
	}
	values := content.as_map()
	name := values['name'] or { return '' }
	version := values['version'] or { return '' }
	if name !is string || version !is string {
		return ''
	}
	return name as string
}

// specifier_name_matches ports specifierNameMatches: the name of the alias symbol (or, without an
// alias, of the type) or the intrinsic name.
fn (mut c Checker) specifier_name_matches(t TypeResponse, wanted []string) !bool {
	symbol := if t.alias_symbol != 0 {
		c.alias_symbol_of(t)!
	} else if t.symbol != 0 {
		c.symbol_of(t)!
	} else {
		tsgo.SymbolResponse{}
	}
	for name in wanted {
		if (!symbol.is_null() && symbol.name == name)
			|| (t.intrinsic_name != '' && t.intrinsic_name == name) {
			return true
		}
	}
	return false
}

fn (mut c Checker) alias_symbol_of(t TypeResponse) !tsgo.SymbolResponse {
	if t.id in c.alias_symbol_cache {
		return c.alias_symbol_cache[t.id]
	}
	symbol := c.client.alias_symbol_of_type(c.snapshot, c.project, t.id)!
	c.alias_symbol_cache[t.id] = symbol
	return symbol
}

// is_default_library ports program.isSourceFileDefaultLibrary (lib.*.d.ts).
fn (mut c Checker) is_default_library(path string) !bool {
	return c.file_metadata(path)!.is_default_library
}

// file_metadata is what tsgo tells about a program file: whether it is a default library and
// whether it comes from an external library (program.isSourceFileFromExternalLibrary).
fn (mut c Checker) file_metadata(path string) !tsgo.SourceFileMetadata {
	if path !in c.file_metadata_cache {
		c.file_metadata_cache[path] = c.client.source_file_metadata(c.snapshot, c.project,
			path)!
	}
	return c.file_metadata_cache[path]
}

// matches_type_or_base_type ports matchesTypeOrBaseType with typeMatchesSomeSpecifier: the type or
// one of its base types (of the class or interface, or of the target of a reference) matches.
fn (mut c Checker) matches_type_or_base_type(t TypeResponse, specifiers []TypeSpecifier, mut seen map[int]bool) !bool {
	if t.id in seen {
		return false
	}
	seen[t.id] = true
	if c.type_matches_some_specifier(t, specifiers)! {
		return true
	}
	for base in c.base_types_for_type(t)! {
		if c.matches_type_or_base_type(base, specifiers, mut seen)! {
			return true
		}
	}
	return false
}

// base_types_for_type ports getBaseTypesForType from baseTypeUtils.
fn (mut c Checker) base_types_for_type(t TypeResponse) ![]TypeResponse {
	if t.flags & type_flag_object == 0 {
		return []TypeResponse{}
	}
	target := if is_type_reference(t) { c.target_of(t)! } else { t }
	if target.is_null() || target.object_flags & object_flags_class_or_interface == 0 {
		return []TypeResponse{}
	}
	if target.id !in c.base_types_cache {
		c.base_types_cache[target.id] = c.client.base_types(c.snapshot, c.project, target.id)!
	}
	return c.base_types_cache[target.id]
}

fn (mut c Checker) target_of(t TypeResponse) !TypeResponse {
	if t.id !in c.target_cache {
		c.target_cache[t.id] = c.client.target_of_type(c.snapshot, c.project, t.id)!
	}
	return c.target_cache[t.id]
}

// type_name ports getTypeName from type-utils: 'string' for what is (or ends up being) text, and
// otherwise typeToString. Its StringLike test is ts-api-utils' isTypeFlagSet, on the type's own
// flags (a union of a string and something else is not text).
fn (mut c Checker) type_name(t TypeResponse, depth int) !string {
	if t.flags & type_flag_string_like != 0 {
		return 'string'
	}
	if depth < max_type_depth && t.flags & type_flag_type_parameter != 0 && !t.is_this_type {
		constraint := c.constraint_of(t)!
		if !constraint.is_null() {
			return c.type_name(constraint, depth + 1)!
		}
	}
	if depth < max_type_depth && t.flags & type_flag_union != 0 {
		mut all := true
		for part in c.members_of(t)! {
			if c.type_name(part, depth + 1)! != 'string' {
				all = false
				break
			}
		}
		if all {
			return 'string'
		}
	}
	if depth < max_type_depth && t.flags & type_flag_intersection != 0 {
		for part in c.members_of(t)! {
			if c.type_name(part, depth + 1)! == 'string' {
				return 'string'
			}
		}
	}
	return c.type_string(t)!
}
