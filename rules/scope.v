module rules

import json2
import math
import tsgo { CompilerOptions }
import treesitter { TokenEnds, children, has_child_kind, named_children, next_sibling, node_end, node_field, node_kind, node_parent, node_start }

// Lexical scopes of a file, like the scope manager of typescript-eslint 8.62.0 (scope-manager:
// Referencer, ClassVisitor, TypeVisitor, PatternVisitor, ExportVisitor and ImportVisitor) as ESLint
// 10 leaves it for a rule (SourceCode#finalize), built on the tree-sitter tree: scopes, the
// variables each one declares with their definitions, and the identifier references with the
// variable they resolve to. Rules use it for ESLint's getScope, findVariable and
// getDeclaredVariables. Scopes, variables and references are indexes into the ScopeTree arrays.
//
// The global scope has what ESLint's has (ScopeSetup): the implicit variables of the libs
// typescript-eslint's parser takes from the project, then the globals ESLint adds for the
// ecmaVersion, the `globals` of the configuration and the `/* global */` comments. References
// resolve when their scope closes, as in ScopeBase.close, so a variable holds its references in
// ESLint's order. tests/scope_cases.json (tools/gen_scope_cases.mjs) has what the real scope
// manager gives for the programs of tests/scope/, and scope_oracle_test.v requires the same.
//
// Known differences with ESLint: where typescript-eslint fails (an unknown lib, the JSX pragma
// naming a variable without identifiers, an import in a script), veslint goes on without that lib
// or reference.

// ScopeKind is the `type` of an ESLint scope.
pub enum ScopeKind {
	global
	esmodule
	function
	function_expression_name
	block
	catch_clause
	for_statement
	switch_statement
	with_statement
	class_scope
	class_field_initializer
	class_static_block
	ts_enum
	ts_module
	type_scope
	function_type
	conditional_type
	mapped_type
}

// DefKind is the `type` of a definition.
pub enum DefKind {
	catch_clause
	class_name
	function_name
	import_binding
	parameter
	ts_enum_member
	ts_enum_name
	ts_module_name
	type_definition
	variable
}

// is_variable_definition ports Definition.isVariableDefinition.
pub fn (k DefKind) is_variable_definition() bool {
	return k != .type_definition
}

// is_type_definition ports Definition.isTypeDefinition.
pub fn (k DefKind) is_type_definition() bool {
	return k in [.class_name, .import_binding, .ts_enum_member, .ts_enum_name, .ts_module_name,
		.type_definition]
}

// Scope is an ESLint scope. `block` is the node that creates it and [start, end) the byte range
// of its ESTree block (getInnermostScope).
pub struct Scope {
pub:
	kind           ScopeKind
	block          C.TSNode
	start          int
	end            int
	upper          int // -1 for the global scope
	variable_scope int
	body_start     int // start of the body of a function scope (-1 without body)
pub mut:
	children   []int
	set        map[string]int // own variables by name
	variables  []int          // own variables, in definition order
	references []int          // references created in this scope, in creation order
	through    []int          // the references it left to the upper scope, in that order (scope.through)
}

// ScopeVariable is an ESLint variable. `lib` marks an implicit variable of a lib
// (typescript-eslint's ImplicitLibVariable), which is a type, a value or both by its lib and not
// by its definitions, as it has none. The last four fields are what ESLint sets on the globals it
// declares (addDeclaredGlobals) and on the names of `/* exported */` comments.
pub struct ScopeVariable {
pub:
	name      string
	scope     int
	lib       bool
	lib_type  bool
	lib_value bool
pub mut:
	defs        []ScopeDefinition // in order
	identifiers []C.TSNode        // the names of its definitions
	references  []int             // the references that resolve to it, in resolution order
	// eslint_implicit_global_setting is the value of the configuration for the global
	// ('readonly', 'writable' or 'off'; '' without one), and `writeable` (ESLint's spelling) that
	// its final value is 'writable'.
	writeable                      bool
	eslint_explicit_global         bool // a `/* global */` comment names it
	eslint_implicit_global_setting string
	eslint_used                    bool // a `/* exported */` comment names it
}

// is_type_variable ports Variable.isTypeVariable and ImplicitLibVariable.isTypeVariable.
pub fn (v &ScopeVariable) is_type_variable() bool {
	if v.lib {
		return v.lib_type
	}
	return v.defs.len == 0 || v.defs.any(it.kind.is_type_definition())
}

// is_value_variable ports Variable.isValueVariable and ImplicitLibVariable.isValueVariable.
pub fn (v &ScopeVariable) is_value_variable() bool {
	if v.lib {
		return v.lib_value
	}
	return v.defs.len == 0 || v.defs.any(it.kind.is_variable_definition())
}

// ScopeDefinition is an ESLint definition: `name` is def.name (the identifier, or the string of a
// quoted enum member) and `node` is def.node (the declarator, the function of a parameter, the
// class, the catch clause, the import specifier, the enum, the enum member, the module, the type
// declaration or type parameter…). For variables, `parent_kind` is def.parent.kind ('var', 'let',
// 'const'), `decl_id` is def.node.id and `init` def.node.init. The head of a for-in/of loop has no
// declarator node in tree-sitter: `node` is then its binding pattern.
pub struct ScopeDefinition {
pub:
	kind        DefKind
	name        C.TSNode
	node        C.TSNode
	parent_kind string
	decl_id     ?C.TSNode
	init        ?C.TSNode
	rest        bool // a rest parameter
}

// ScopeReference is an ESLint reference: `init` marks the write of a declarator's initializer, a
// default value or a for-in/of head.
pub struct ScopeReference {
pub:
	identifier C.TSNode
	name       string
	from       int
	read       bool
	write      bool
	init       bool
	type_ref   bool
	value_ref  bool
pub mut:
	resolved int = -1
	// implicit is the node of maybeImplicitGlobal: the `=` assignment or for-in/of statement that
	// writes it outside strict code.
	implicit ?C.TSNode
}

// is_read_only ports Reference.isReadOnly.
pub fn (r ScopeReference) is_read_only() bool {
	return r.read && !r.write
}

// ImplicitGlobal is an implicit global variable: the name assigned and, for each assignment, the
// identifier and def.node (the assignment expression or for-in/of statement).
pub struct ImplicitGlobal {
pub:
	name string
pub mut:
	defs []ImplicitGlobalDef
}

pub struct ImplicitGlobalDef {
pub:
	name C.TSNode
	node C.TSNode
}

// ScopeTree holds the scopes of a file. The global scope is 0 and, in a module, the module
// scope 1. `through` are the references that resolve to no variable (globalScope.through).
pub struct ScopeTree {
pub mut:
	scopes     []Scope
	variables  []ScopeVariable
	references []ScopeReference
	through    []int
	strict     []bool // scope.isStrict of each scope
	// implicit are globalScope.implicit.variables, by first assignment.
	implicit     []ImplicitGlobal
	implicit_set map[string]int
mut:
	by_block map[string][]int // scopes created by each block node (scope_block_key)
	declared map[u64]int      // variable of each definition name node
}

// scope_tree is the scope tree of the file being linted, built on first use. A Checker that got
// no setup for the file (lint_file gives it) takes the default one.
fn (mut c Checker) scope_tree(root C.TSNode) &ScopeTree {
	if c.file_scopes == unsafe { nil } {
		if c.scope_setup.libs == unsafe { nil } {
			c.scope_setup = default_scope_setup()
		}
		c.file_scopes = build_scope_tree_with(root, c.src, c.tokens, c.scope_setup)
	}
	return c.file_scopes
}

// scope_libs are the implicit variables of a list of libs, built once per run.
fn (mut c Checker) scope_libs(libs []string) &ScopeLibs {
	key := libs.join('\n')
	if cached := c.scope_libs_cache[key] {
		return cached
	}
	built := new_scope_libs(libs)
	c.scope_libs_cache[key] = built
	return built
}

// file_scope_setup is the setup of the file being linted: the project, the configuration of
// the file and what its comments declare.
fn (mut c Checker) file_scope_setup(config LintConfig, inline InlineConfig) ScopeSetup {
	libs := c.scope_libs(scope_libs_of(c.scope_project, config.language))
	return new_scope_setup(c.scope_project, config.language, inline.globals, inline.exported,
		libs)
}

// OptionState tells an option that is not set from one set to null.
pub enum OptionState {
	unset
	null
	set
}

// LanguageOptions is what the `languageOptions` of an ESLint configuration say about the scopes
// of a file: the normalized ecmaVersion (whose globals ESLint adds to the global scope), the
// sourceType, `globals` with its values normalized ('readonly', 'writable' or 'off') and in its
// order, and the `parserOptions` typescript-eslint's parser gives its scope manager (sourceType,
// lib, jsxPragma, jsxFragmentName and ecmaFeatures.globalReturn).
pub struct LanguageOptions {
pub:
	ecma_version            int    = scope_latest_ecma_version
	source_type             string = 'module'
	globals                 map[string]string
	parser_source_type      string // '' when not set
	has_lib                 bool
	lib                     []string
	jsx_pragma_state        OptionState
	jsx_pragma              string
	jsx_fragment_name_state OptionState
	jsx_fragment_name       string
	global_return           bool
	implied_strict          bool // ecmaFeatures.impliedStrict, which the strict rule reads
	// parserOptions.isolatedDeclarations (truthy), which consistent-generic-constructors reads
	isolated_declarations bool
}

// parse_language_options reads the `languageOptions` of a configuration (as ESLint resolved it,
// or as written in a JSON). Without an ecmaVersion it is the latest and without a sourceType
// "module", the defaults of a flat configuration for a TypeScript file.
pub fn parse_language_options(value json2.Any) LanguageOptions {
	if value !is map[string]json2.Any {
		return LanguageOptions{}
	}
	options := value.as_map()
	mut globals := map[string]string{}
	declared := options['globals'] or { json2.Any(map[string]json2.Any{}) }
	if declared is map[string]json2.Any {
		for name, global in declared {
			if normalized := normalize_global_value(global) {
				globals[name] = normalized
			}
		}
	}
	source_type := options['sourceType'] or { json2.Any('module') }
	mut parser := map[string]json2.Any{}
	if parser_options := options['parserOptions'] {
		if parser_options is map[string]json2.Any {
			parser = parser_options.as_map().clone()
		}
	}
	mut lib := []string{}
	mut has_lib := false
	if libs := parser['lib'] {
		// `analyzeOptions.lib == null` leaves the libs to the program.
		if libs is []json2.Any {
			has_lib = true
			for item in libs {
				if item is string {
					lib << item
				}
			}
		}
	}
	pragma_state, pragma := scope_name_option(parser, 'jsxPragma')
	fragment_state, fragment := scope_name_option(parser, 'jsxFragmentName')
	mut global_return := false
	mut implied_strict := false
	if features := parser['ecmaFeatures'] {
		if features is map[string]json2.Any {
			global_return = (features.as_map()['globalReturn'] or { json2.Any(false) }).json_str() == 'true'
			implied_strict = (features.as_map()['impliedStrict'] or { json2.Any(false) }).json_str() == 'true'
		}
	}
	parser_source_type := parser['sourceType'] or { json2.Any('') }
	isolated := parser['isolatedDeclarations'] or { json2.Any(false) }
	return LanguageOptions{
		ecma_version:            normalize_ecma_version(options['ecmaVersion'] or {
			json2.Any('latest')
		})
		source_type:             if source_type is string { source_type } else { 'module' }
		globals:                 globals
		parser_source_type:      if parser_source_type is string { parser_source_type } else { '' }
		has_lib:                 has_lib
		lib:                     lib
		implied_strict:          implied_strict
		jsx_pragma_state:        pragma_state
		jsx_pragma:              pragma
		jsx_fragment_name_state: fragment_state
		jsx_fragment_name:       fragment
		global_return:           global_return
		isolated_declarations:   isolated.json_str() !in ['false', 'null', '0', '""']
	}
}

// scope_name_option reads `jsxPragma` or `jsxFragmentName` of the parser options: not set, null
// (a value that names nothing counts as null) or a name.
fn scope_name_option(parser map[string]json2.Any, key string) (OptionState, string) {
	value := parser[key] or { return OptionState.unset, '' }
	if value is string {
		return OptionState.set, value
	}
	return OptionState.null, ''
}

// ScopeProject is what typescript-eslint's parser takes from the compiler options of the program
// for its scope manager: the libs (getLib) and the JSX factories.
pub struct ScopeProject {
pub:
	libs                 []string
	jsx_factory          ?string
	jsx_fragment_factory ?string
}

pub fn new_scope_project(options CompilerOptions) ScopeProject {
	return ScopeProject{
		libs:                 options.lib_names()
		jsx_factory:          options.jsx_factory
		jsx_fragment_factory: options.jsx_fragment_factory
	}
}

// ScopeGlobal is a global ESLint declares in the global scope (addDeclaredGlobals): `config` is
// the value the configuration gives it ('' when only a comment names it), `explicit` that a
// `/* global */` comment names it.
pub struct ScopeGlobal {
pub:
	name     string
	writable bool
	config   string
	explicit bool
}

// ScopeSetup is what decides the scopes of a file besides its code: the implicit variables of
// the libs, the globals ESLint declares (in its order), the names of the `/* exported */`
// comments, the JSX pragma and fragment name the Referencer references ('' for none), and whether
// the file is a script (no module scope), with a function scope for the program (globalReturn).
pub struct ScopeSetup {
pub:
	libs              &ScopeLibs = unsafe { nil }
	declared          []ScopeGlobal
	exported          []string
	jsx_pragma        string
	jsx_fragment_name string
	script            bool
	global_return     bool
	// not about scopes: parserOptions.isolatedDeclarations, for consistent-generic-constructors
	isolated_decls bool
}

// ScopeLibs are the implicit variables a list of libs gives the global scope
// (Referencer.populateGlobalsFromLib), with typescript-eslint's implicit `const` of `as const`
// and `<const>` at the end.
@[heap]
pub struct ScopeLibs {
pub:
	variables []ScopeVariable
	set       map[string]int
}

// scope_lib_order ports Referencer.resolveLibDefinitions: the libs (in lower case, as analyze()
// leaves them) followed by the ones they include, each once. typescript-eslint throws for a lib
// it does not know; here it is left out.
pub fn scope_lib_order(libs []string) []string {
	mut included := map[string]bool{}
	mut queue := []string{}
	for lib in libs {
		name := lib.to_lower()
		if name in scope_lib_variables && !included[name] {
			included[name] = true
			queue << name
		}
	}
	for i := 0; i < queue.len; i++ {
		for dependency in scope_lib_references[queue[i]] or { []string{} } {
			if !included[dependency] {
				included[dependency] = true
				queue << dependency
			}
		}
	}
	return queue
}

// new_scope_libs defines the variables of the libs in order: the first lib that has a name
// decides whether it is a type, a value or both (ScopeBase.defineVariable keeps the first).
pub fn new_scope_libs(libs []string) &ScopeLibs {
	mut variables := []ScopeVariable{}
	mut set := map[string]int{}
	for lib in scope_lib_order(libs) {
		for entry in scope_lib_variables[lib].split(' ') {
			if entry.len < 2 || entry[1..] in set {
				continue
			}
			set[entry[1..]] = variables.len
			variables << ScopeVariable{
				name:                           entry[1..]
				lib:                            true
				lib_type:                       entry[0] != `v`
				lib_value:                      entry[0] != `t`
				eslint_implicit_global_setting: 'readonly'
			}
		}
	}
	if 'const' !in set {
		set['const'] = variables.len
		variables << ScopeVariable{
			name:                           'const'
			lib:                            true
			lib_type:                       true
			eslint_implicit_global_setting: 'readonly'
		}
	}
	return &ScopeLibs{
		variables: variables
		set:       set
	}
}

// default_scope_setup is the setup of a file of a project without compiler options, linted
// without a configuration.
pub fn default_scope_setup() ScopeSetup {
	project := new_scope_project(CompilerOptions{})
	return new_scope_setup(project, LanguageOptions{}, map[string]string{}, []string{},
		new_scope_libs(project.libs))
}

// new_scope_setup is the setup of a file: `inline` are the values its `/* global */` comments
// give ('readonly', 'writable' or 'off', in the order of the comments), `exported` the names of
// its `/* exported */` comments, and `libs` the variables of scope_libs_of(project, language).
pub fn new_scope_setup(project ScopeProject, language LanguageOptions, inline map[string]string, exported []string, libs &ScopeLibs) ScopeSetup {
	pragma, fragment := scope_jsx_names(project, language)
	// ESLint gives the parser its sourceType unless the parser options have their own, and the
	// parser takes anything but "module" as a script.
	source_type := if language.parser_source_type != '' {
		language.parser_source_type
	} else {
		language.source_type
	}
	return ScopeSetup{
		libs:              libs
		declared:          declared_globals(language, inline)
		exported:          exported
		jsx_pragma:        pragma
		jsx_fragment_name: fragment
		script:            source_type != 'module'
		global_return:     language.global_return
		isolated_decls:    language.isolated_declarations
	}
}

// scope_libs_of are the libs of a file: those of the parser options or, without them, those of
// the program (the parser's getLib).
pub fn scope_libs_of(project ScopeProject, language LanguageOptions) []string {
	return if language.has_lib { language.lib } else { project.libs }
}

// scope_jsx_names ports how typescript-eslint's parser and analyze() choose the names a JSX
// element references: the parser options `jsxPragma` and `jsxFragmentName`; when one is not set,
// the first name of the compiler option `jsxFactory` or `jsxFragmentFactory` ("preact.h" gives
// `preact`); otherwise `React` for the pragma and nothing for the fragment. '' is no name.
pub fn scope_jsx_names(project ScopeProject, language LanguageOptions) (string, string) {
	mut pragma := 'React'
	if language.jsx_pragma_state != .unset {
		pragma = language.jsx_pragma
	} else if factory := project.jsx_factory {
		pragma = js_trim(factory.all_before('.'))
	}
	mut fragment := ''
	if language.jsx_fragment_name_state != .unset {
		fragment = language.jsx_fragment_name
	} else if factory := project.jsx_fragment_factory {
		fragment = js_trim(factory.all_before('.'))
	}
	return pragma, fragment
}

// declared_globals ports SourceCode#applyLanguageOptions and addDeclaredGlobals: the globals of
// the ecmaVersion, of CommonJS and of `languageOptions.globals`, with the values the `/* global */`
// comments give them, except the ones that end up "off". They come in the order of the keys of
// ESLint's object: integer names first, in ascending order, and then the others as added.
pub fn declared_globals(language LanguageOptions, inline map[string]string) []ScopeGlobal {
	mut order := []string{}
	mut values := map[string]string{}
	for name in scope_es_globals {
		if ecma_version_has_global(language.ecma_version, name) {
			order << name
			values[name] = 'readonly'
		}
	}
	mut additions := []map[string]string{}
	if language.source_type == 'commonjs' {
		additions << scope_commonjs_globals
	}
	additions << language.globals
	for addition in additions {
		for name, value in addition {
			if name !in values {
				order << name
			}
			values[name] = value
		}
	}
	config := values.clone()
	for name, value in inline {
		if name !in values {
			order << name
		}
		values[name] = value
	}
	mut indexes := order.filter(is_array_index_key(it))
	indexes.sort_with_compare(fn (a &string, b &string) int {
		return int(a.u64() > b.u64()) - int(a.u64() < b.u64())
	})
	indexes << order.filter(!is_array_index_key(it))
	mut out := []ScopeGlobal{cap: indexes.len}
	for name in indexes {
		if values[name] == 'off' {
			continue
		}
		out << ScopeGlobal{
			name:     name
			writable: values[name] == 'writable'
			config:   config[name] or { '' }
			explicit: name in inline
		}
	}
	return out
}

// normalize_ecma_version ports normalizeEcmaVersionForLanguageOptions on the `ecmaVersion` of a
// configuration: 3, 5, a year, or the latest version for anything that is not a number.
pub fn normalize_ecma_version(value json2.Any) int {
	number := match value {
		i64 { f64(value) }
		f64 { value }
		int { f64(value) }
		else { return scope_latest_ecma_version }
	}
	if number != math.floor(number) || number < 0 || number > 1000000 {
		// Not a version with globals.
		return -1
	}
	version := int(number)
	return if version == 3 || version == 5 || version >= 2015 { version } else { version + 2009 }
}

// normalize_global_value ports normalizeConfigGlobal on a value of `languageOptions.globals`;
// none for a value ESLint rejects.
pub fn normalize_global_value(value json2.Any) ?string {
	return match value.json_str() {
		'"off"' { 'off' }
		'true', '"true"', '"writeable"', '"writable"' { 'writable' }
		'null', 'false', '"false"', '"readable"', '"readonly"' { 'readonly' }
		else { none }
	}
}

// ecma_version_has_global: ESLint adds the global for that (normalized) ecmaVersion
// (getGlobalsForEcmaVersion, which has no globals for a version it does not know).
fn ecma_version_has_global(version int, name string) bool {
	if version !in scope_ecma_versions {
		return false
	}
	first := scope_es_global_versions[name] or { return false }
	return first <= version
}

// is_reference_to_global_function ports isReferenceToGlobalFunction (util/scopeUtils): the first
// reference named `name` created in the scope of `node` (not necessarily the one of `node`) does
// not resolve to a variable with a definition, a declared one.
fn is_reference_to_global_function(t &ScopeTree, node C.TSNode, name string) bool {
	scope := t.get_scope(node)
	for r in t.scopes[scope].references {
		ref := t.references[r]
		if ref.name == name {
			return ref.resolved < 0 || t.variables[ref.resolved].defs.len == 0
		}
	}
	return true
}

pub fn (t &ScopeTree) global_scope() int {
	return 0
}

// get_scope ports ESLint's SourceCode#getScope: the innermost scope whose block is `n` or its
// closest ancestor. The program gives the global scope; any other node at the top level, the
// innermost scope of the program: the module scope or, in a script, the global scope or the
// function scope of `globalReturn`.
pub fn (t &ScopeTree) get_scope(n C.TSNode) int {
	if node_kind(n) == 'program' {
		return 0
	}
	mut node := n
	mut from := ?C.TSNode(none)
	for _ in 0 .. 100000 {
		// The decorators of `@dec export class C {}` belong to the class.
		if node_kind(node) == 'decorator' {
			if parent := node_parent(node) {
				if node_kind(parent) == 'export_statement' {
					if declaration := node_field(parent, 'declaration') {
						from = node
						node = declaration
						continue
					}
				}
			}
		}
		if scopes := t.by_block[scope_block_key(node)] {
			mut candidates := scopes.clone()
			// A method is not the function: its name and decorators belong to the outer scope.
			if scope_is_method(node) && !scope_in_method_function(node, from) {
				candidates = candidates.filter(t.scopes[it].kind != .function)
			}
			if candidates.len > 0 {
				scope := candidates.last()
				if t.scopes[scope].kind == .function_expression_name {
					return t.scopes[scope].children[0]
				}
				return scope
			}
		}
		from = node
		node = node_parent(node) or { break }
	}
	return 0
}

// function_scope_of is the function scope a function or method creates, -1 if none.
pub fn (t &ScopeTree) function_scope_of(n C.TSNode) int {
	scopes := t.by_block[scope_block_key(n)] or { return -1 }
	for i := scopes.len - 1; i >= 0; i-- {
		if t.scopes[scopes[i]].kind == .function {
			return scopes[i]
		}
	}
	return -1
}

// find_variable ports eslint-utils findVariable: from `scope` (descending first, if `location` is a
// byte offset, into the innermost child scope whose block contains it, like getInnermostScope), the
// first scope upward that declares `name`; -1 if none.
pub fn (t &ScopeTree) find_variable(scope int, name string, location int) int {
	mut s := scope
	if location >= 0 {
		for {
			mut found := false
			for child in t.scopes[s].children {
				if t.scopes[child].start <= location && location < t.scopes[child].end {
					s = child
					found = true
					break
				}
			}
			if !found {
				break
			}
		}
	}
	for s >= 0 {
		if v := t.scopes[s].set[name] {
			return v
		}
		s = t.scopes[s].upper
	}
	return -1
}

// own_variable ports scope.set.get(name): only the variables of that scope.
pub fn (t &ScopeTree) own_variable(scope int, name string) int {
	return t.scopes[scope].set[name] or { -1 }
}

// declared_variable is the variable a definition name node declares (getDeclaredVariables(…).find(v
// => v.identifiers.includes(node))), -1 if none.
pub fn (t &ScopeTree) declared_variable(name_node C.TSNode) int {
	return t.declared[node_key(name_node)] or { -1 }
}

fn scope_block_key(n C.TSNode) string {
	return '${node_start(n)}-${node_end(n)}-${node_kind(n)}'
}

// scope_is_method: the node is a class or object method, whose function (an ESTree
// FunctionExpression or TSEmptyBodyFunctionExpression) is not a tree-sitter node.
fn scope_is_method(n C.TSNode) bool {
	kind := node_kind(n)
	if kind in ['method_definition', 'abstract_method_signature'] {
		return true
	}
	if kind == 'method_signature' {
		parent := node_parent(n) or { return false }
		return node_kind(parent) == 'class_body'
	}
	return false
}

// scope_in_method_function: `from` (a child of the method) is part of its function: the type
// parameters, the parameters, the return type or the body.
fn scope_in_method_function(method C.TSNode, from ?C.TSNode) bool {
	child := from or { return false }
	for field in ['type_parameters', 'parameters', 'return_type', 'body'] {
		if part := node_field(method, field) {
			if node_key(part) == node_key(child) && node_kind(part) == node_kind(child) {
				return true
			}
		}
	}
	return false
}

// ScopeTarget is an identifier a pattern binds (PatternVisitor's callback): the default values
// around it (outermost first) and whether it is the argument of a rest element.
struct ScopeTarget {
	ident    C.TSNode
	defaults []C.TSNode
	rest     bool
}

struct ScopeBuilder {
	src    string
	tokens TokenEnds
	// The names a JSX element references (ScopeSetup).
	jsx_pragma        string
	jsx_fragment_name string
mut:
	tree    ScopeTree
	current int
	// left has, for each scope, the references it has yet to resolve (ScopeBase.leftToResolve).
	left [][]int
	// Referencer's #hasReferencedJsxFactory and #hasReferencedJsxFragmentFactory.
	referenced_jsx_pragma   bool
	referenced_jsx_fragment bool
}

// build_scope_tree analyzes a file (its tree and source) with default_scope_setup.
fn build_scope_tree(root C.TSNode, src string, tokens TokenEnds) &ScopeTree {
	return build_scope_tree_with(root, src, tokens, default_scope_setup())
}

// build_scope_tree_with ports Referencer.Program and what ESLint does with the scope manager the
// parser returns (SourceCode#finalize: addDeclaredGlobals and markExportedVariables).
fn build_scope_tree_with(root C.TSNode, src string, tokens TokenEnds, setup ScopeSetup) &ScopeTree {
	mut b := &ScopeBuilder{
		src:               src
		tokens:            tokens
		jsx_pragma:        setup.jsx_pragma
		jsx_fragment_name: setup.jsx_fragment_name
	}
	// Program: its range starts at the first token.
	mut start := src.len
	for child in children(root) {
		if node_kind(child) !in ['comment', 'hash_bang_line', 'html_comment'] {
			start = node_start(child)
			break
		}
	}
	b.tree.scopes << Scope{
		kind:           .global
		block:          root
		start:          start
		end:            src.len
		upper:          -1
		variable_scope: 0
		body_start:     -1
	}
	b.tree.by_block[scope_block_key(root)] << 0
	b.left << []int{}
	b.tree.strict << b.is_strict_scope(0)
	// populateGlobalsFromLib: the implicit variables of the libs and `const`.
	if setup.libs != unsafe { nil } {
		b.tree.variables = setup.libs.variables.clone()
		b.tree.scopes[0].set = setup.libs.set.clone()
		b.tree.scopes[0].variables = []int{len: setup.libs.variables.len, init: index}
	}
	b.current = 0
	if setup.global_return {
		// `globalReturn`: the program is the body of a function (Node's module wrapper).
		b.nest_function(.function, root, start, src.len, -1)
		b.define_variable(b.current, 'arguments')
	}
	if !setup.script {
		b.nest(.esmodule, root, start, src.len)
	}
	b.visit_children(root)
	for b.current >= 0 {
		b.close()
	}
	b.implicit_globals()
	b.add_globals(setup.declared)
	// markExportedVariables: only the variables of the global scope.
	for name in setup.exported {
		if v := b.tree.scopes[0].set[name] {
			b.tree.variables[v].eslint_used = true
		}
	}
	return &b.tree
}

// is_strict_scope ports isStrictScope of typescript-eslint's ScopeBase, when the scope is created
// (its upper scopes are done). Only a class method's function is a method definition there, and
// its upper class scope is strict anyway.
fn (b &ScopeBuilder) is_strict_scope(s int) bool {
	scope := b.tree.scopes[s]
	if scope.upper >= 0 && b.tree.strict[scope.upper] {
		return true
	}
	match scope.kind {
		.class_scope, .conditional_type, .function_type, .mapped_type, .esmodule, .ts_enum,
		.ts_module, .type_scope {
			return true
		}
		.function {
			if node_kind(scope.block) == 'program' {
				return b.has_use_strict(scope.block)
			}
			body := node_field(scope.block, 'body') or { return false }
			if node_kind(body) != 'statement_block' {
				return false
			}
			return b.has_use_strict(body)
		}
		.global {
			return b.has_use_strict(scope.block)
		}
		else {
			return false
		}
	}
}

// has_use_strict: the directive prologue of a program or function body has 'use strict' (the raw
// text between the quotes, as ESTree's `directive`).
fn (b &ScopeBuilder) has_use_strict(body C.TSNode) bool {
	for stmt in named_children(body) {
		kind := node_kind(stmt)
		if kind in ['comment', 'hash_bang_line', 'html_comment'] {
			continue
		}
		if kind != 'expression_statement' {
			return false
		}
		expr := named_children(stmt).filter(node_kind(it) != 'comment')
		if expr.len == 0 || node_kind(expr[0]) != 'string' {
			return false
		}
		text := b.text(expr[0])
		if text.len >= 2 && text[1..text.len - 1] == 'use strict' {
			return true
		}
	}
	return false
}

// is_strict is scope.isStrict.
pub fn (t &ScopeTree) is_strict(s int) bool {
	return s >= 0 && s < t.strict.len && t.strict[s]
}

// implicit_globals ports what GlobalScope.close does with the references it has left: an
// assignment to an undeclared name outside strict code defines an implicit global variable
// (globalScope.implicit.variables), one per name, with a definition per assignment.
fn (mut b ScopeBuilder) implicit_globals() {
	for r in b.tree.through {
		ref := b.tree.references[r]
		node := ref.implicit or { continue }
		if ref.name in b.tree.scopes[0].set {
			continue
		}
		if i := b.tree.implicit_set[ref.name] {
			b.tree.implicit[i].defs << ImplicitGlobalDef{ref.identifier, node}
		} else {
			b.tree.implicit_set[ref.name] = b.tree.implicit.len
			b.tree.implicit << ImplicitGlobal{
				name: ref.name
				defs: [ImplicitGlobalDef{ref.identifier, node}]
			}
		}
	}
}

// add_globals ports GlobalScope.addVariables and the rest of ESLint's addDeclaredGlobals: each
// global gets a variable unless the scope has one with its name, the references nothing resolved
// that have one of those names resolve to it, and the variable takes the values of the global.
fn (mut b ScopeBuilder) add_globals(declared []ScopeGlobal) {
	mut variables := map[string]int{}
	for global in declared {
		variables[global.name] = b.define_variable(0, global.name)
	}
	if b.tree.implicit.len > 0 {
		b.tree.implicit = b.tree.implicit.filter(it.name !in variables)
		b.tree.implicit_set = map[string]int{}
		for i, g in b.tree.implicit {
			b.tree.implicit_set[g.name] = i
		}
	}
	mut through := []int{cap: b.tree.through.len}
	for r in b.tree.through {
		if v := variables[b.tree.references[r].name] {
			b.tree.references[r].resolved = v
			b.tree.variables[v].references << r
		} else {
			through << r
		}
	}
	b.tree.through = through
	if declared.len > 0 {
		b.tree.scopes[0].through = b.tree.scopes[0].through.filter(b.tree.references[it].name !in variables)
	}
	for global in declared {
		v := variables[global.name]
		b.tree.variables[v].eslint_implicit_global_setting = global.config
		b.tree.variables[v].eslint_explicit_global = global.explicit
		b.tree.variables[v].writeable = global.writable
	}
}

// nest creates a scope inside the current one and enters it.
fn (mut b ScopeBuilder) nest(kind ScopeKind, block C.TSNode, start int, end int) int {
	return b.nest_function(kind, block, start, end, -1)
}

// block_start and block_end are the ESTree range of a node: a `declare` is part of the declaration
// and the end is that of its last token (tree-sitter may include a trailing comment).
fn (b &ScopeBuilder) block_start(n C.TSNode) int {
	if parent := node_parent(n) {
		if node_kind(parent) == 'ambient_declaration' {
			return node_start(parent)
		}
	}
	return node_start(n)
}

fn (b &ScopeBuilder) block_end(n C.TSNode) int {
	return b.tokens.last_end(node_end(n))
}

fn (mut b ScopeBuilder) nest_function(kind ScopeKind, block C.TSNode, start int, end int, body_start int) int {
	index := b.tree.scopes.len
	upper := b.current
	variable_scope := if kind in [.class_field_initializer, .class_static_block, .function, .global,
		.esmodule, .ts_module] {
		index
	} else {
		b.tree.scopes[upper].variable_scope
	}
	b.tree.scopes << Scope{
		kind:           kind
		block:          block
		start:          start
		end:            end
		upper:          upper
		variable_scope: variable_scope
		body_start:     body_start
	}
	b.tree.scopes[upper].children << index
	b.tree.by_block[scope_block_key(block)] << index
	b.left << []int{}
	b.tree.strict << b.is_strict_scope(index)
	b.current = index
	return index
}

// close ports ScopeBase.close: each reference the scope has left resolves to its variable of that
// name, when that is a valid resolution; the others are left to the upper scope, and past the
// global scope they are `through`. A `with` scope resolves nothing (WithScope.close).
fn (mut b ScopeBuilder) close() {
	scope := b.current
	upper := b.tree.scopes[scope].upper
	dynamic := b.tree.scopes[scope].kind == .with_statement
	pending := b.left[scope]
	b.left[scope] = []int{}
	for r in pending {
		if !dynamic && b.resolve_in(scope, r) {
			continue
		}
		b.tree.scopes[scope].through << r
		if upper >= 0 {
			b.left[upper] << r
		} else {
			b.tree.through << r
		}
	}
	b.current = upper
}

// resolve_in ports the static close of a reference in a scope.
fn (mut b ScopeBuilder) resolve_in(s int, r int) bool {
	ref := b.tree.references[r]
	v := b.tree.scopes[s].set[ref.name] or { return false }
	if !b.valid_resolution(b.tree.scopes[s], ref, v) {
		return false
	}
	b.tree.references[r].resolved = v
	b.tree.variables[v].references << r
	return true
}

// valid_resolution ports FunctionScope.isValidResolution (a reference in the parameters does not
// see a variable declared only in the body) and the check that a type reference resolves to a
// type variable and a value reference to a value variable.
fn (b &ScopeBuilder) valid_resolution(scope Scope, ref ScopeReference, v int) bool {
	variable := b.tree.variables[v]
	if scope.kind == .function && scope.body_start >= 0
		&& node_start(ref.identifier) < scope.body_start
		&& variable.defs.all(node_start(it.name) >= scope.body_start) {
		return false
	}
	return (ref.type_ref && variable.is_type_variable())
		|| (ref.value_ref && variable.is_value_variable())
}

fn (b &ScopeBuilder) text(n C.TSNode) string {
	return b.src[node_start(n)..node_end(n)]
}

// name_of is the ESTree name of an identifier (escapes applied).
fn (b &ScopeBuilder) name_of(n C.TSNode) string {
	text := b.text(n)
	if !text.contains('\\') {
		return text
	}
	return cooked_string(text, false) or { text }
}

// define_variable gets or creates the variable `name` of a scope.
fn (mut b ScopeBuilder) define_variable(scope int, name string) int {
	if v := b.tree.scopes[scope].set[name] {
		return v
	}
	v := b.tree.variables.len
	b.tree.variables << ScopeVariable{
		name:  name
		scope: scope
	}
	b.tree.scopes[scope].set[name] = v
	b.tree.scopes[scope].variables << v
	return v
}

// define ports defineIdentifier: a definition named by an identifier.
fn (mut b ScopeBuilder) define(scope int, ident C.TSNode, def ScopeDefinition) {
	v := b.define_variable(scope, b.name_of(ident))
	b.tree.variables[v].defs << def
	b.tree.variables[v].identifiers << ident
	b.tree.declared[node_key(ident)] = v
}

fn (mut b ScopeBuilder) reference(ident C.TSNode, name string, read bool, write bool, init bool, type_ref bool, value_ref bool) {
	b.reference_from(b.current, ident, name, read, write, init, type_ref, value_ref)
}

// reference_from creates a reference in a scope (ScopeBase.referenceValue, referenceType and
// referenceDualValueType).
fn (mut b ScopeBuilder) reference_from(scope int, ident C.TSNode, name string, read bool, write bool, init bool, type_ref bool, value_ref bool) {
	// A MISSING node of tree-sitter's error recovery is not an identifier.
	if node_start(ident) == node_end(ident) {
		return
	}
	r := b.tree.references.len
	b.tree.references << ScopeReference{
		identifier: ident
		name:       name
		from:       scope
		read:       read
		write:      write
		init:       write && init
		type_ref:   type_ref
		value_ref:  value_ref
	}
	b.tree.scopes[scope].references << r
	b.left[scope] << r
}

fn (mut b ScopeBuilder) read_value(ident C.TSNode) {
	b.reference(ident, b.name_of(ident), true, false, false, false, true)
}

fn (mut b ScopeBuilder) write_value(ident C.TSNode, read bool, init bool) {
	b.reference(ident, b.name_of(ident), read, true, init, false, true)
}

// write_implicit is a write with maybeImplicitGlobal: by `node` when the scope is not strict.
fn (mut b ScopeBuilder) write_implicit(ident C.TSNode, node C.TSNode) {
	before := b.tree.references.len
	b.write_value(ident, false, false)
	if b.tree.references.len > before && !b.tree.strict[b.current] {
		b.tree.references[before].implicit = node
	}
}

fn (mut b ScopeBuilder) read_type(ident C.TSNode) {
	b.reference(ident, b.name_of(ident), true, false, false, true, false)
}

fn (mut b ScopeBuilder) read_dual(ident C.TSNode) {
	b.reference(ident, b.name_of(ident), true, false, false, true, true)
}

// reference_in_upper_scope ports referenceInSomeUpperScope: the closest variable called `name`,
// from the current scope outwards and among those defined so far, gets a read reference from its
// own scope, whose identifier is the first one of the variable.
fn (mut b ScopeBuilder) reference_in_upper_scope(name string) bool {
	mut s := b.current
	for s >= 0 {
		if v := b.tree.scopes[s].set[name] {
			identifiers := b.tree.variables[v].identifiers
			// A variable without identifiers (an implicit lib variable, a quoted enum member):
			// typescript-eslint references `undefined` and fails when the scope closes.
			if identifiers.len > 0 {
				b.reference_from(s, identifiers[0], name, true, false, false, false, true)
			}
			return true
		}
		s = b.tree.scopes[s].upper
	}
	return false
}

// reference_jsx_pragma ports referenceJsxPragma: the first JSX element or fragment in whose scopes
// there is a variable with the name of the pragma references it.
fn (mut b ScopeBuilder) reference_jsx_pragma() {
	if b.jsx_pragma == '' || b.referenced_jsx_pragma {
		return
	}
	b.referenced_jsx_pragma = b.reference_in_upper_scope(b.jsx_pragma)
}

// reference_jsx_fragment ports referenceJsxFragment.
fn (mut b ScopeBuilder) reference_jsx_fragment() {
	if b.jsx_fragment_name == '' || b.referenced_jsx_fragment {
		return
	}
	b.referenced_jsx_fragment = b.reference_in_upper_scope(b.jsx_fragment_name)
}

fn (mut b ScopeBuilder) visit_children(n C.TSNode) {
	for child in named_children(n) {
		b.visit(child)
	}
}

fn (mut b ScopeBuilder) visit_opt(n ?C.TSNode) {
	if node := n {
		b.visit(node)
	}
}

// visit ports Referencer.visit on statements and expressions.
fn (mut b ScopeBuilder) visit(n C.TSNode) {
	match node_kind(n) {
		'identifier', 'undefined', 'shorthand_property_identifier' {
			b.read_value(n)
		}
		'jsx_element' {
			// JSXFragment (`<>…</>`: an element whose tags have no name): the pragma and the
			// fragment name.
			if open := node_field(n, 'open_tag') {
				if _ := node_field(open, 'name') {
				} else {
					b.reference_jsx_pragma()
					b.reference_jsx_fragment()
				}
			}
			b.visit_children(n)
		}
		'jsx_opening_element', 'jsx_self_closing_element' {
			// JSXOpeningElement: the pragma, the name, the type arguments and the attributes.
			name := node_field(n, 'name') or { return }
			b.reference_jsx_pragma()
			b.visit_jsx_name(name)
			b.visit_type_opt(node_field(n, 'type_arguments'))
			for child in named_children(n) {
				match node_kind(child) {
					'jsx_attribute' {
						// JSXAttribute: its value, not its name.
						for part in named_children(child) {
							if node_kind(part) !in ['property_identifier', 'jsx_namespace_name'] {
								b.visit(part)
							}
						}
					}
					'jsx_expression' {
						b.visit(child)
					}
					else {}
				}
			}
		}
		'jsx_closing_element' {
			// JSXClosingElement: its name is visited like that of the opening element.
			if name := node_field(n, 'name') {
				b.visit_jsx_name(name)
			}
		}
		'statement_block' {
			b.nest(.block, n, b.block_start(n), b.block_end(n))
			b.visit_children(n)
			b.close()
		}
		'lexical_declaration', 'variable_declaration' {
			b.visit_variable_declaration(n)
		}
		'function_declaration', 'generator_function_declaration', 'function_signature',
		'function_expression', 'generator_function', 'arrow_function' {
			b.visit_function(n)
		}
		'class_declaration', 'abstract_class_declaration', 'class' {
			b.visit_class(n, []C.TSNode{})
		}
		'interface_declaration', 'type_alias_declaration' {
			b.visit_type(n)
		}
		'enum_declaration' {
			b.visit_enum(n)
		}
		'internal_module', 'module' {
			b.visit_module(n)
		}
		'ambient_declaration' {
			if has_child_kind(n, 'global') {
				// `declare global { … }`: a TSModuleDeclaration whose name is not a variable.
				b.nest(.ts_module, n, b.block_start(n), b.block_end(n))
				for child in named_children(n) {
					if node_kind(child) == 'statement_block' {
						b.visit_children(child)
					}
				}
				b.close()
			} else {
				b.visit_children(n)
			}
		}
		'import_statement' {
			b.visit_import(n)
		}
		'import_alias' {
			b.visit_import_alias(n)
		}
		'export_statement' {
			b.visit_export(n)
		}
		'for_statement' {
			initializer := node_field(n, 'initializer')
			lexical := if init := initializer {
				node_kind(init) == 'lexical_declaration'
			} else {
				false
			}
			if lexical {
				b.nest(.for_statement, n, b.block_start(n), b.block_end(n))
			}
			b.visit_children(n)
			if lexical {
				b.close()
			}
		}
		'for_in_statement' {
			b.visit_for_in(n)
		}
		'switch_statement' {
			b.visit_opt(node_field(n, 'value'))
			b.nest(.switch_statement, n, b.block_start(n), b.block_end(n))
			if body := node_field(n, 'body') {
				for case in named_children(body) {
					b.visit_children(case)
				}
			}
			b.close()
		}
		'catch_clause' {
			b.visit_catch(n)
		}
		'with_statement' {
			b.visit_opt(node_field(n, 'object'))
			b.nest(.with_statement, n, b.block_start(n), b.block_end(n))
			b.visit_opt(node_field(n, 'body'))
			b.close()
		}
		'labeled_statement' {
			b.visit_opt(node_field(n, 'body'))
		}
		'member_expression' {
			b.visit_opt(node_field(n, 'object'))
		}
		'subscript_expression' {
			b.visit_opt(node_field(n, 'object'))
			b.visit_opt(node_field(n, 'index'))
		}
		'call_expression', 'new_expression' {
			b.visit_opt(node_field(n, 'function'))
			b.visit_opt(node_field(n, 'constructor'))
			b.visit_opt(node_field(n, 'arguments'))
			b.visit_type_opt(node_field(n, 'type_arguments'))
		}
		'assignment_expression', 'augmented_assignment_expression' {
			b.visit_assignment(n)
		}
		'update_expression' {
			b.visit_update(n)
		}
		'object' {
			b.visit_object(n)
		}
		'as_expression', 'satisfies_expression' {
			parts := named_children(n)
			if parts.len > 0 {
				b.visit(parts[0])
			}
			if parts.len > 1 {
				b.visit_type(parts.last())
			} else {
				b.visit_const_type(n)
			}
		}
		'await_expression' {
			// Outside an async function TypeScript reads `await (x)`, `await [x]` and `` await `…` `` as
			// a call, an element access and a tagged template on an `await` identifier.
			if operand := first_named(n) {
				first := b.src[node_start(operand)]
				if (first == `(` || first == `[` || first == `\``) && scope_outside_async(n) {
					if keyword := await_keyword(n) {
						b.read_value(keyword)
					}
				}
				b.visit(operand)
			}
		}
		'type_assertion' {
			// `<T>x`: the expression, then the type.
			for part in named_children(n) {
				if node_kind(part) != 'type_arguments' {
					b.visit(part)
				}
			}
			for part in named_children(n) {
				if node_kind(part) == 'type_arguments' {
					b.visit_type(part)
					b.visit_const_type(part)
				}
			}
		}
		'instantiation_expression' {
			for part in named_children(n) {
				if node_kind(part) != 'type_arguments' {
					b.visit(part)
				}
			}
			b.visit_type_opt(node_field(n, 'type_arguments'))
		}
		'break_statement', 'continue_statement', 'meta_property', 'this', 'super', 'number', 'regex',
		'true', 'false', 'null', 'import', 'property_identifier', 'private_property_identifier',
		'statement_identifier', 'string', 'comment', 'hash_bang_line', 'html_comment',
		'debugger_statement', 'empty_statement', 'type_annotation', 'type_arguments' {
		}
		else {
			b.visit_children(n)
		}
	}
}

// visit_jsx_name ports Referencer.visitJSXElement on the name of a JSX element: an identifier
// that starts with a lower-case letter is an intrinsic element, not a reference (unless it is
// `this`); of a member name, the leftmost object (unless it is `this`); of a namespaced name,
// both parts (the visitor has no method for JSXNamespacedName, so it visits its children).
fn (mut b ScopeBuilder) visit_jsx_name(name C.TSNode) {
	match node_kind(name) {
		'jsx_identifier' {
			text := b.text(name)
			// `name[0].toUpperCase() === name[0]`
			units := utf16_units(text)
			if text == 'this' || (units.len > 0 && js_to_upper(units[..1]) == units[..1]) {
				b.read_value(name)
			}
		}
		'jsx_member_expression' {
			mut head := name
			for node_kind(head) == 'jsx_member_expression' {
				head = node_field(head, 'object') or { return }
			}
			if node_kind(head) == 'jsx_identifier' && b.text(head) != 'this' {
				b.read_value(head)
			}
		}
		'jsx_namespace_name' {
			for part in named_children(name) {
				if node_kind(part) == 'jsx_identifier' {
					b.read_value(part)
				}
			}
		}
		else {}
	}
}

// visit_const_type references the `const` of `as const` or `<const>`: a type reference to the
// implicit global `const`.
fn (mut b ScopeBuilder) visit_const_type(n C.TSNode) {
	for child in children(n) {
		if node_kind(child) == 'const' {
			b.read_type(child)
		}
	}
}

// scope_outside_async: the closest enclosing function of `n` exists and is not async.
fn scope_outside_async(n C.TSNode) bool {
	mut node := node_parent(n) or { return false }
	for _ in 0 .. 100000 {
		if node_kind(node) in ['function_declaration', 'generator_function_declaration',
			'function_expression', 'generator_function', 'arrow_function', 'method_definition'] {
			return !has_child_kind(node, 'async')
		}
		node = node_parent(node) or { return false }
	}
	return false
}

// visit_variable_declaration ports Referencer.VariableDeclaration.
fn (mut b ScopeBuilder) visit_variable_declaration(n C.TSNode) {
	kind := if node_kind(n) == 'variable_declaration' {
		'var'
	} else {
		b.text(node_field(n, 'kind') or { return })
	}
	target := if kind == 'var' { b.tree.scopes[b.current].variable_scope } else { b.current }
	for declarator in named_children(n) {
		if node_kind(declarator) != 'variable_declarator' {
			continue
		}
		id := node_field(declarator, 'name') or { continue }
		init := node_field(declarator, 'value')
		mut targets := []ScopeTarget{}
		mut rhs := []C.TSNode{}
		b.collect_pattern(id, []C.TSNode{}, -1, mut targets, mut rhs)
		for t in targets {
			b.define(target, t.ident, ScopeDefinition{
				kind:        .variable
				name:        t.ident
				node:        declarator
				parent_kind: kind
				decl_id:     id
				init:        init
			})
			for _ in t.defaults {
				b.write_value(t.ident, false, true)
			}
			if _ := init {
				b.write_value(t.ident, false, true)
			}
		}
		for r in rhs {
			b.visit(r)
		}
		b.visit_opt(init)
		b.visit_type_opt(node_field(declarator, 'type'))
	}
}

// collect_pattern ports PatternVisitor on the ESTree node a tree-sitter node stands for: the
// identifiers a pattern binds (in order) and its right hand nodes (default values, computed keys
// and the objects of member targets). PatternVisitor only has methods for the nodes of a pattern,
// a member access and a call; of any other node it visits every child as a pattern, so each
// identifier inside is a target too: those of the type of an assertion (`[(x as T)] = a` writes
// `x` and `T`), see collect_pattern_type. An array or object expression is walked like a
// pattern: it is what tree-sitter reads where it has no pattern for a target (scope_recovered_pattern).
fn (b &ScopeBuilder) collect_pattern(n C.TSNode, defaults []C.TSNode, rest_key i64, mut targets []ScopeTarget, mut rhs []C.TSNode) {
	match node_kind(n) {
		'identifier', 'undefined', 'shorthand_property_identifier_pattern',
		'shorthand_property_identifier' {
			targets << ScopeTarget{
				ident:    n
				defaults: defaults.clone()
				rest:     rest_key == i64(node_key(n))
			}
		}
		'this' {
			// The `this` parameter is an Identifier in ESTree; a `this` expression names nothing.
			if parent := node_parent(n) {
				if node_kind(parent) in ['required_parameter', 'optional_parameter'] {
					targets << ScopeTarget{
						ident:    n
						defaults: defaults.clone()
					}
				}
			}
		}
		'parenthesized_expression' {
			if inner := first_named(n) {
				b.collect_pattern(inner, defaults, rest_key, mut targets, mut rhs)
			}
		}
		'non_null_expression' {
			// TSNonNullExpression: its expression.
			if inner := first_named(n) {
				b.collect_pattern(inner, defaults, -1, mut targets, mut rhs)
			}
		}
		'as_expression', 'satisfies_expression' {
			// TSAsExpression and TSSatisfiesExpression: the expression, then the type.
			parts := named_children(n)
			if parts.len > 0 {
				b.collect_pattern(parts[0], defaults, -1, mut targets, mut rhs)
			}
			if parts.len > 1 {
				b.collect_pattern_type(parts.last(), defaults, mut targets, mut rhs)
			} else {
				b.collect_const_type(n, defaults, mut targets)
			}
		}
		'type_assertion' {
			// TSTypeAssertion: the type, then the expression.
			for part in named_children(n) {
				if node_kind(part) == 'type_arguments' {
					b.collect_pattern_type(part, defaults, mut targets, mut rhs)
					b.collect_const_type(part, defaults, mut targets)
				}
			}
			for part in named_children(n) {
				if node_kind(part) != 'type_arguments' {
					b.collect_pattern(part, defaults, -1, mut targets, mut rhs)
				}
			}
		}
		'object_pattern', 'object' {
			for property in named_children(n) {
				match node_kind(property) {
					'pair_pattern', 'pair' {
						// Property: a computed key is a right hand node.
						if key := node_field(property, 'key') {
							if node_kind(key) == 'computed_property_name' {
								if expression := first_named(key) {
									rhs << expression
								}
							}
						}
						if value := node_field(property, 'value') {
							b.collect_pattern(value, defaults, -1, mut targets, mut rhs)
						}
					}
					'object_assignment_pattern' {
						left := node_field(property, 'left') or { continue }
						right := node_field(property, 'right') or { continue }
						mut inner := defaults.clone()
						inner << right
						b.collect_pattern(left, inner, -1, mut targets, mut rhs)
						rhs << right
					}
					else {
						b.collect_pattern(property, defaults, -1, mut targets, mut rhs)
					}
				}
			}
		}
		'array_pattern', 'array' {
			for element in named_children(n) {
				b.collect_pattern(element, defaults, -1, mut targets, mut rhs)
			}
		}
		'assignment_pattern', 'assignment_expression' {
			left := node_field(n, 'left') or { return }
			right := node_field(n, 'right') or { return }
			mut inner := defaults.clone()
			inner << right
			b.collect_pattern(left, inner, -1, mut targets, mut rhs)
			rhs << right
		}
		'rest_pattern', 'spread_element' {
			argument := unwrap_parens(first_named(n) or { return })
			b.collect_pattern(argument, defaults, i64(node_key(argument)), mut targets, mut
				rhs)
		}
		'member_expression' {
			if object := node_field(n, 'object') {
				rhs << object
			}
		}
		'subscript_expression' {
			if index := node_field(n, 'index') {
				rhs << index
			}
			if object := node_field(n, 'object') {
				rhs << object
			}
		}
		'call_expression' {
			// CallExpression: the arguments are right hand nodes, the callee a pattern.
			if arguments := node_field(n, 'arguments') {
				for argument in named_children(arguments) {
					rhs << argument
				}
			}
			if function := node_field(n, 'function') {
				b.collect_pattern(function, defaults, -1, mut targets, mut rhs)
			}
		}
		'type_arguments' {
			b.collect_pattern_type(n, defaults, mut targets, mut rhs)
		}
		'type_annotation', 'opting_type_annotation', 'omitting_type_annotation',
		'adding_type_annotation', 'type_predicate_annotation', 'asserts_annotation', 'decorator',
		'property_identifier', 'private_property_identifier', 'statement_identifier', 'string',
		'number', 'regex' {
			// TSTypeAnnotation and Decorator have a method that does nothing; the rest name no
			// variable.
		}
		else {
			// Any other node: every child is visited as a pattern.
			for child in named_children(n) {
				b.collect_pattern(child, defaults, -1, mut targets, mut rhs)
			}
		}
	}
}

// collect_const_type adds the `const` of `as const` or `<const>` in a pattern: the identifier of
// a TSTypeReference like any other.
fn (b &ScopeBuilder) collect_const_type(n C.TSNode, defaults []C.TSNode, mut targets []ScopeTarget) {
	for child in children(n) {
		if node_kind(child) == 'const' {
			targets << ScopeTarget{
				ident:    child
				defaults: defaults.clone()
			}
		}
	}
}

// collect_pattern_type is collect_pattern on a type, which PatternVisitor walks child by child in
// the order of typescript-eslint's visitor keys: every identifier is a target (the names of a
// type reference, of a qualified name, of a `typeof`, of a member of a type literal, of a tuple
// label, of a parameter, of a type parameter), and only a TSTypeAnnotation stops it (the type of a
// property or of a parameter and the return type of a signature).
fn (b &ScopeBuilder) collect_pattern_type(n C.TSNode, defaults []C.TSNode, mut targets []ScopeTarget, mut rhs []C.TSNode) {
	match node_kind(n) {
		'type_identifier' {
			// tree-sitter reads the `bigint` keyword as a name.
			if b.text(n) != 'bigint' {
				targets << ScopeTarget{
					ident:    n
					defaults: defaults.clone()
				}
			}
		}
		'identifier', 'property_identifier' {
			targets << ScopeTarget{
				ident:    n
				defaults: defaults.clone()
			}
		}
		'nested_type_identifier', 'nested_identifier', 'member_expression' {
			// TSQualifiedName (also the qualifier of an import type): left, right. By position:
			// in the member expressions of a type query or of an import type, tree-sitter
			// answers the `property` field of the outer one with that of the inner one.
			for child in named_children(n) {
				b.collect_pattern_type(child, defaults, mut targets, mut rhs)
			}
		}
		'call_expression' {
			// TSImportType: `import('m')` names no variable; its type arguments are types.
			if type_arguments := node_field(n, 'type_arguments') {
				b.collect_pattern_type(type_arguments, defaults, mut targets, mut rhs)
			}
		}
		'type_query', 'instantiation_expression', 'generic_type' {
			// TSTypeQuery (exprName, typeArguments), TSTypeReference (typeName, typeArguments).
			for child in named_children(n) {
				b.collect_pattern_type(child, defaults, mut targets, mut rhs)
			}
		}
		'object_type' {
			if clause := scope_mapped_clause(n) {
				// TSMappedType: key, constraint, nameType, typeAnnotation.
				for field in ['name', 'type', 'alias'] {
					if part := node_field(clause, field) {
						b.collect_pattern_type(part, defaults, mut targets, mut rhs)
					}
				}
				if signature := first_named(n) {
					if annotation := node_field(signature, 'type') {
						for child in named_children(annotation) {
							b.collect_pattern_type(child, defaults, mut targets, mut rhs)
						}
					}
				}
			} else {
				for member in named_children(n) {
					b.collect_pattern_type(member, defaults, mut targets, mut rhs)
				}
			}
		}
		'property_signature' {
			// TSPropertySignature: key (its type is a TSTypeAnnotation).
			b.collect_pattern_key(n, defaults, mut targets, mut rhs)
		}
		'method_signature' {
			// TSMethodSignature: key, typeParameters, params (returnType is a TSTypeAnnotation).
			b.collect_pattern_key(n, defaults, mut targets, mut rhs)
			b.collect_pattern_signature(n, defaults, mut targets, mut rhs)
		}
		'call_signature', 'construct_signature', 'function_type', 'constructor_type' {
			b.collect_pattern_signature(n, defaults, mut targets, mut rhs)
		}
		'index_signature' {
			// TSIndexSignature: its parameter (the types are TSTypeAnnotations).
			if name := node_field(n, 'name') {
				b.collect_pattern_type(name, defaults, mut targets, mut rhs)
			}
		}
		'type_parameter' {
			// TSTypeParameter: name, constraint, default.
			for field in ['name', 'constraint', 'value'] {
				if part := node_field(n, field) {
					b.collect_pattern_type(part, defaults, mut targets, mut rhs)
				}
			}
		}
		'conditional_type' {
			for field in ['left', 'right', 'consequence', 'alternative'] {
				if part := node_field(n, field) {
					b.collect_pattern_type(part, defaults, mut targets, mut rhs)
				}
			}
		}
		'tuple_type' {
			for element in named_children(n) {
				if node_kind(element) in ['required_parameter', 'optional_parameter'] {
					// TSNamedTupleMember: label, elementType.
					if label := node_field(element, 'name') {
						b.collect_pattern(label, defaults, -1, mut targets, mut rhs)
					}
					if annotation := node_field(element, 'type') {
						for child in named_children(annotation) {
							b.collect_pattern_type(child, defaults, mut targets, mut rhs)
						}
					}
				} else {
					b.collect_pattern_type(element, defaults, mut targets, mut rhs)
				}
			}
		}
		'predefined_type', 'this_type', 'this', 'literal_type', 'existential_type', 'import',
		'string', 'number', 'string_fragment', 'type_annotation', 'opting_type_annotation',
		'omitting_type_annotation', 'adding_type_annotation', 'type_predicate_annotation',
		'asserts_annotation', 'type_predicate', 'asserts', 'arguments' {
		}
		else {
			// TSArrayType, TSTypeOperator, TSUnionType, TSIntersectionType, TSIndexedAccessType,
			// TSOptionalType, TSRestType, TSInferType, TSTemplateLiteralType, type arguments and
			// type parameters: their children, in order.
			for child in named_children(n) {
				b.collect_pattern_type(child, defaults, mut targets, mut rhs)
			}
		}
	}
}

// collect_pattern_key is the key of a member of a type literal in a pattern: an identifier is a
// target, and a computed key is visited as a pattern.
fn (b &ScopeBuilder) collect_pattern_key(member C.TSNode, defaults []C.TSNode, mut targets []ScopeTarget, mut rhs []C.TSNode) {
	key := node_field(member, 'name') or { return }
	match node_kind(key) {
		'property_identifier' {
			targets << ScopeTarget{
				ident:    key
				defaults: defaults.clone()
			}
		}
		'computed_property_name' {
			if expression := first_named(key) {
				b.collect_pattern(expression, defaults, -1, mut targets, mut rhs)
			}
		}
		else {}
	}
}

// collect_pattern_signature is the type parameters and the parameters of a signature or of a
// function type in a pattern; its return type is a TSTypeAnnotation.
fn (b &ScopeBuilder) collect_pattern_signature(n C.TSNode, defaults []C.TSNode, mut targets []ScopeTarget, mut rhs []C.TSNode) {
	if type_parameters := node_field(n, 'type_parameters') {
		b.collect_pattern_type(type_parameters, defaults, mut targets, mut rhs)
	}
	parameters := node_field(n, 'parameters') or { return }
	for p in named_children(parameters) {
		if node_kind(p) !in ['required_parameter', 'optional_parameter'] {
			continue
		}
		if pattern := node_field(p, 'pattern') {
			b.collect_pattern(pattern, defaults, -1, mut targets, mut rhs)
		} else if pattern := node_field(p, 'name') {
			b.collect_pattern(pattern, defaults, -1, mut targets, mut rhs)
		}
	}
}

// scope_recovered_pattern is the array or object of a destructuring target that tree-sitter has
// no pattern for, because an element is in parentheses or is an assertion (`[(x)] = a`,
// `[x as T] = a`, `({ k: <T>x } = o)`): it reads an array or object expression and puts after it
// a `!` that is not in the source.
fn scope_recovered_pattern(n C.TSNode) ?C.TSNode {
	if node_kind(n) != 'non_null_expression' {
		return none
	}
	inner := first_named(n) or { return none }
	if node_kind(inner) in ['array', 'object'] && node_end(inner) == node_end(n) {
		return inner
	}
	return none
}

// visit_function ports Referencer.visitFunction (functions, arrows, `declare function`, object
// methods, and class methods without a body).
fn (mut b ScopeBuilder) visit_function(n C.TSNode) {
	kind := node_kind(n)
	name := node_field(n, 'name')
	mut name_scope := false
	if kind in ['function_expression', 'generator_function'] {
		if id := name {
			b.nest(.function_expression_name, n, b.block_start(n), b.block_end(n))
			b.define(b.current, id, ScopeDefinition{
				kind: .function_name
				name: id
				node: n
			})
			name_scope = true
		}
	} else if kind in ['function_declaration', 'generator_function_declaration', 'function_signature'] {
		if id := name {
			b.define(b.current, id, ScopeDefinition{
				kind: .function_name
				name: id
				node: n
			})
		}
	}
	b.nest_function_scope(n)
	b.visit_parameters(n, true)
	b.visit_type_opt(node_field(n, 'return_type'))
	b.visit_type_opt(node_field(n, 'type_parameters'))
	if body := node_field(n, 'body') {
		if node_kind(body) == 'statement_block' {
			b.visit_children(body)
		} else {
			b.visit(body)
		}
	}
	b.close()
	if name_scope {
		b.close()
	}
}

// nest_function_scope enters the function scope of a function or method (`arguments` included,
// except in arrows). The block of a method's function starts at its type parameters or its `(`.
fn (mut b ScopeBuilder) nest_function_scope(n C.TSNode) {
	mut start := b.block_start(n)
	if scope_is_method(n) {
		if type_parameters := node_field(n, 'type_parameters') {
			start = node_start(type_parameters)
		} else if parameters := node_field(n, 'parameters') {
			start = node_start(parameters)
		}
	}
	mut body_start := -1
	if body := node_field(n, 'body') {
		body_start = node_start(unwrap_parens(body))
	}
	mut end := b.block_end(n)
	if body_start < 0 && scope_is_method(n) {
		// A method without body ends with its `;`.
		if next := next_sibling(n) {
			if node_kind(next) == ';' {
				end = node_end(next)
			}
		}
	}
	b.nest_function(.function, n, start, end, body_start)
	if node_kind(n) != 'arrow_function' {
		b.define_variable(b.current, 'arguments')
	}
}

// visit_parameters defines the parameters of a function in the current scope, with their default
// values, type annotations and (if `decorators`) decorators.
fn (mut b ScopeBuilder) visit_parameters(function C.TSNode, decorators bool) {
	if parameter := node_field(function, 'parameter') {
		// `x => …`
		b.define(b.current, parameter, ScopeDefinition{
			kind: .parameter
			name: parameter
			node: function
		})
		return
	}
	parameters := node_field(function, 'parameters') or { return }
	for p in named_children(parameters) {
		if node_kind(p) !in ['required_parameter', 'optional_parameter'] {
			continue
		}
		pattern := node_field(p, 'pattern') or { node_field(p, 'name') or { continue } }
		mut targets := []ScopeTarget{}
		mut rhs := []C.TSNode{}
		if value := node_field(p, 'value') {
			b.collect_pattern(pattern, [value], -1, mut targets, mut rhs)
			rhs << value
		} else {
			b.collect_pattern(pattern, []C.TSNode{}, -1, mut targets, mut rhs)
		}
		for t in targets {
			b.define(b.current, t.ident, ScopeDefinition{
				kind: .parameter
				name: t.ident
				node: function
				rest: t.rest
			})
			for _ in t.defaults {
				b.write_value(t.ident, false, true)
			}
		}
		for r in rhs {
			b.visit(r)
		}
		b.visit_type_opt(node_field(p, 'type'))
		if decorators {
			b.visit_decorators(p)
		}
	}
}

fn (mut b ScopeBuilder) visit_decorators(n C.TSNode) {
	for child in named_children(n) {
		if node_kind(child) == 'decorator' {
			b.visit_children(child)
		}
	}
}

// visit_class ports ClassVisitor.visitClass; `outer_decorators` are those tree-sitter puts before
// `export`.
fn (mut b ScopeBuilder) visit_class(n C.TSNode, outer_decorators []C.TSNode) {
	name := node_field(n, 'name')
	if node_kind(n) != 'class' {
		if id := name {
			b.define(b.current, id, ScopeDefinition{
				kind: .class_name
				name: id
				node: n
			})
		}
	}
	for decorator in outer_decorators {
		b.visit_children(decorator)
	}
	b.visit_decorators(n)
	b.nest(.class_scope, n, b.block_start(n), b.block_end(n))
	if id := name {
		b.define(b.current, id, ScopeDefinition{
			kind: .class_name
			name: id
			node: n
		})
	}
	mut extends := []C.TSNode{}
	mut implements := []C.TSNode{}
	for child in named_children(n) {
		if node_kind(child) != 'class_heritage' {
			continue
		}
		for clause in named_children(child) {
			if node_kind(clause) == 'extends_clause' {
				extends << clause
			} else if node_kind(clause) == 'implements_clause' {
				implements << clause
			}
		}
	}
	for clause in extends {
		for part in named_children(clause) {
			if node_kind(part) != 'type_arguments' {
				b.visit(part)
			}
		}
	}
	b.visit_type_opt(node_field(n, 'type_parameters'))
	for clause in extends {
		for part in named_children(clause) {
			if node_kind(part) == 'type_arguments' {
				b.visit_type(part)
			}
		}
	}
	for clause in implements {
		b.visit_type(clause)
	}
	if body := node_field(n, 'body') {
		b.visit_class_body(body)
	}
	b.close()
}

// visit_class_body ports the ClassVisitor members. tree-sitter puts the decorators of a method
// before it, as siblings.
fn (mut b ScopeBuilder) visit_class_body(body C.TSNode) {
	mut pending := []C.TSNode{}
	for member in named_children(body) {
		match node_kind(member) {
			'decorator' {
				pending << member
				continue
			}
			'method_definition' {
				b.visit_computed_key(member)
				b.visit_method_function(member)
			}
			'method_signature', 'abstract_method_signature' {
				b.visit_computed_key(member)
				b.visit_function(member)
			}
			'public_field_definition' {
				b.visit_computed_key(member)
				if value := node_field(member, 'value') {
					block := unwrap_parens(value)
					b.nest(.class_field_initializer, block, b.block_start(block), b.block_end(block))
					b.visit(value)
					b.close()
				}
				b.visit_decorators(member)
			}
			'class_static_block' {
				b.nest(.class_static_block, member, b.block_start(member), b.block_end(member))
				if block := node_field(member, 'body') {
					b.visit_children(block)
				}
				b.close()
			}
			'index_signature' {
				b.visit_type(member)
			}
			else {}
		}
		for decorator in pending {
			b.visit_children(decorator)
		}
		pending.clear()
		if node_kind(member) == 'public_field_definition' {
			b.visit_type_opt(node_field(member, 'type'))
		}
	}
}

fn (mut b ScopeBuilder) visit_computed_key(member C.TSNode) {
	key := node_field(member, 'name') or { return }
	if node_kind(key) == 'computed_property_name' {
		b.visit_children(key)
	}
}

// visit_method_function ports ClassVisitor.visitMethodFunction: the decorators of the parameters
// first, in the class scope.
fn (mut b ScopeBuilder) visit_method_function(n C.TSNode) {
	if parameters := node_field(n, 'parameters') {
		for p in named_children(parameters) {
			b.visit_decorators(p)
		}
	}
	b.nest_function_scope(n)
	b.visit_parameters(n, false)
	b.visit_type_opt(node_field(n, 'return_type'))
	b.visit_type_opt(node_field(n, 'type_parameters'))
	if body := node_field(n, 'body') {
		b.visit_children(body)
	}
	b.close()
}

// visit_object ports the Property visits of an ObjectExpression.
fn (mut b ScopeBuilder) visit_object(n C.TSNode) {
	for property in named_children(n) {
		match node_kind(property) {
			'pair' {
				if key := node_field(property, 'key') {
					if node_kind(key) == 'computed_property_name' {
						b.visit_children(key)
					}
				}
				b.visit_opt(node_field(property, 'value'))
			}
			'method_definition' {
				b.visit_computed_key(property)
				b.visit_function(property)
			}
			else {
				b.visit(property)
			}
		}
	}
}

// visit_enum ports Referencer.TSEnumDeclaration.
fn (mut b ScopeBuilder) visit_enum(n C.TSNode) {
	if id := node_field(n, 'name') {
		b.define(b.current, id, ScopeDefinition{
			kind: .ts_enum_name
			name: id
			node: n
		})
	}
	b.nest(.ts_enum, n, b.block_start(n), b.block_end(n))
	if body := node_field(n, 'body') {
		for member in named_children(body) {
			name := if node_kind(member) == 'enum_assignment' {
				node_field(member, 'name') or { continue }
			} else {
				member
			}
			match node_kind(name) {
				'property_identifier' {
					b.define(b.current, name, ScopeDefinition{
						kind: .ts_enum_member
						name: name
						node: member
					})
				}
				'string' {
					// A literal name defines a variable without identifier.
					text := b.text(name)
					value := cooked_string(text[1..text.len - 1], false) or { text }
					v := b.define_variable(b.current, value)
					b.tree.variables[v].defs << ScopeDefinition{
						kind: .ts_enum_member
						name: name
						node: member
					}
				}
				else {}
			}
			if node_kind(member) == 'enum_assignment' {
				b.visit_opt(node_field(member, 'value'))
			}
		}
	}
	b.close()
}

// visit_module ports Referencer.TSModuleDeclaration (`namespace N {}`, `module 'm' {}`).
fn (mut b ScopeBuilder) visit_module(n C.TSNode) {
	if id := node_field(n, 'name') {
		if node_kind(id) == 'identifier' {
			b.define(b.current, id, ScopeDefinition{
				kind: .ts_module_name
				name: id
				node: n
			})
		}
	}
	mut end := b.block_end(n)
	body := node_field(n, 'body')
	if body == none {
		// `declare module 'm';` ends with its `;`, which tree-sitter reads as an empty statement.
		mut statement := n
		if parent := node_parent(n) {
			if node_kind(parent) == 'ambient_declaration' {
				statement = parent
			}
		}
		if next := next_sibling(statement) {
			if node_kind(next) in [';', 'empty_statement'] {
				end = node_end(next)
			}
		}
	}
	b.nest(.ts_module, n, b.block_start(n), end)
	if block := body {
		b.visit_children(block)
	}
	b.close()
}

// visit_import ports ImportVisitor and TSImportEqualsDeclaration (`import x = require('m')`).
fn (mut b ScopeBuilder) visit_import(n C.TSNode) {
	for part in named_children(n) {
		match node_kind(part) {
			'import_clause' {
				for clause in named_children(part) {
					match node_kind(clause) {
						'identifier' {
							b.define_import(clause, clause)
						}
						'namespace_import' {
							if id := first_named(clause) {
								b.define_import(id, clause)
							}
						}
						'named_imports' {
							for specifier in named_children(clause) {
								local := node_field(specifier, 'alias') or {
									node_field(specifier, 'name') or { continue }
								}
								if node_kind(local) == 'identifier' {
									b.define_import(local, specifier)
								}
							}
						}
						else {}
					}
				}
			}
			'import_require_clause' {
				if id := first_named(part) {
					if node_kind(id) == 'identifier' {
						b.define_import(id, n)
					}
				}
			}
			else {}
		}
	}
}

fn (mut b ScopeBuilder) define_import(id C.TSNode, node C.TSNode) {
	b.define(b.current, id, ScopeDefinition{
		kind: .import_binding
		name: id
		node: node
	})
}

// visit_import_alias ports TSImportEqualsDeclaration with an entity name (`import A = B.C`): the
// leftmost name is a value reference.
fn (mut b ScopeBuilder) visit_import_alias(n C.TSNode) {
	parts := named_children(n)
	if parts.len < 2 {
		return
	}
	b.define_import(parts[0], n)
	mut reference := parts[1]
	for node_kind(reference) in ['nested_identifier', 'member_expression'] {
		reference = node_field(reference, 'object') or { return }
	}
	if node_kind(reference) == 'identifier' {
		b.read_value(reference)
	}
}

// visit_export ports ExportNamedDeclaration, ExportDefaultDeclaration, TSExportAssignment and
// ExportVisitor.
fn (mut b ScopeBuilder) visit_export(n C.TSNode) {
	if declaration := node_field(n, 'declaration') {
		if node_kind(declaration) in ['class_declaration', 'abstract_class_declaration'] {
			b.visit_class(declaration, named_children(n).filter(node_kind(it) == 'decorator'))
		} else {
			b.visit(declaration)
		}
		return
	}
	if value := node_field(n, 'value') {
		// `export default …`
		expression := unwrap_parens(value)
		if node_kind(expression) == 'identifier' {
			b.read_dual(expression)
		} else if node_kind(expression) == 'class' {
			b.visit_class(expression, named_children(n).filter(node_kind(it) == 'decorator'))
		} else {
			b.visit(value)
		}
		return
	}
	if _ := node_field(n, 'source') {
		return
	}
	type_only := has_child_kind(n, 'type')
	for part in named_children(n) {
		match node_kind(part) {
			'export_clause' {
				for specifier in named_children(part) {
					local := node_field(specifier, 'name') or { continue }
					if node_kind(local) != 'identifier' {
						continue
					}
					if type_only || has_child_kind(specifier, 'type') {
						b.read_type(local)
					} else {
						b.read_dual(local)
					}
				}
			}
			'identifier' {
				if has_child_kind(n, '=') {
					// `export = x`
					b.read_dual(part)
				} else {
					// `export as namespace X` (TSNamespaceExportDeclaration)
					b.read_value(part)
				}
			}
			'decorator' {}
			else {
				b.visit(part)
			}
		}
	}
}

// scope_expression_target ports visitExpressionTarget: one `as`, `<T>` or `!` around an assignment
// target is unwrapped (the type of an assertion is visited).
fn (mut b ScopeBuilder) expression_target(n C.TSNode) C.TSNode {
	node := unwrap_parens(n)
	match node_kind(node) {
		'as_expression' {
			parts := named_children(node)
			if parts.len > 1 {
				b.visit_type(parts.last())
			} else {
				b.visit_const_type(node)
			}
			return unwrap_parens(parts[0])
		}
		'type_assertion' {
			mut expression := node
			for part in named_children(node) {
				if node_kind(part) == 'type_arguments' {
					b.visit_type(part)
					b.visit_const_type(part)
				} else {
					expression = part
				}
			}
			return unwrap_parens(expression)
		}
		'non_null_expression' {
			return unwrap_parens(first_named(node) or { return node })
		}
		else {
			return node
		}
	}
}

// scope_is_pattern ports PatternVisitor.isPattern.
fn scope_is_pattern(n C.TSNode) bool {
	return node_kind(n) in ['identifier', 'undefined', 'object_pattern', 'array_pattern', 'rest_pattern',
		'assignment_pattern']
}

// visit_assignment ports Referencer.AssignmentExpression.
fn (mut b ScopeBuilder) visit_assignment(n C.TSNode) {
	left0 := node_field(n, 'left') or { return }
	recovered := scope_recovered_pattern(unwrap_parens(left0))
	left := recovered or { b.expression_target(left0) }
	if recovered != none || scope_is_pattern(left) {
		if node_kind(n) == 'assignment_expression' {
			mut targets := []ScopeTarget{}
			mut rhs := []C.TSNode{}
			b.collect_pattern(left, []C.TSNode{}, -1, mut targets, mut rhs)
			for t in targets {
				for _ in t.defaults {
					b.write_implicit(t.ident, n)
				}
				b.write_implicit(t.ident, n)
			}
			for r in rhs {
				b.visit(r)
			}
		} else if node_kind(left) in ['identifier', 'undefined'] {
			b.write_value(left, true, false)
		}
	} else {
		b.visit(left)
	}
	b.visit_opt(node_field(n, 'right'))
}

// visit_update ports Referencer.UpdateExpression.
fn (mut b ScopeBuilder) visit_update(n C.TSNode) {
	argument := node_field(n, 'argument') or { return }
	target := b.expression_target(argument)
	if scope_is_pattern(target) {
		mut targets := []ScopeTarget{}
		mut rhs := []C.TSNode{}
		b.collect_pattern(target, []C.TSNode{}, -1, mut targets, mut rhs)
		for t in targets {
			b.write_value(t.ident, true, false)
		}
	} else {
		b.visit(argument)
	}
}

// visit_for_in ports Referencer.visitForIn (for-in and for-of).
fn (mut b ScopeBuilder) visit_for_in(n C.TSNode) {
	left := node_field(n, 'left') or { return }
	if kind_node := node_field(n, 'kind') {
		kind := b.text(kind_node)
		if kind != 'var' {
			b.nest(.for_statement, n, b.block_start(n), b.block_end(n))
		}
		// The declaration (without a declarator node in tree-sitter).
		target := if kind == 'var' { b.tree.scopes[b.current].variable_scope } else { b.current }
		init := node_field(n, 'value')
		mut targets := []ScopeTarget{}
		mut rhs := []C.TSNode{}
		b.collect_pattern(left, []C.TSNode{}, -1, mut targets, mut rhs)
		for t in targets {
			b.define(target, t.ident, ScopeDefinition{
				kind:        .variable
				name:        t.ident
				node:        left
				parent_kind: kind
				decl_id:     left
				init:        init
			})
			for _ in t.defaults {
				b.write_value(t.ident, false, true)
			}
			if _ := init {
				b.write_value(t.ident, false, true)
			}
		}
		for r in rhs {
			b.visit(r)
		}
		b.visit_opt(init)
		// The write of each iteration.
		for t in targets {
			b.write_value(t.ident, false, true)
		}
		b.visit_opt(node_field(n, 'right'))
		b.visit_opt(node_field(n, 'body'))
		if kind != 'var' {
			b.close()
		}
		return
	}
	mut targets := []ScopeTarget{}
	mut rhs := []C.TSNode{}
	b.collect_pattern(unwrap_parens(left), []C.TSNode{}, -1, mut targets, mut rhs)
	for t in targets {
		for _ in t.defaults {
			b.write_implicit(t.ident, n)
		}
		b.write_implicit(t.ident, n)
	}
	for r in rhs {
		b.visit(r)
	}
	b.visit_opt(node_field(n, 'right'))
	b.visit_opt(node_field(n, 'body'))
}

// visit_catch ports Referencer.CatchClause (the type annotation of the parameter is not visited).
fn (mut b ScopeBuilder) visit_catch(n C.TSNode) {
	b.nest(.catch_clause, n, b.block_start(n), b.block_end(n))
	if parameter := node_field(n, 'parameter') {
		mut targets := []ScopeTarget{}
		mut rhs := []C.TSNode{}
		b.collect_pattern(parameter, []C.TSNode{}, -1, mut targets, mut rhs)
		for t in targets {
			b.define(b.current, t.ident, ScopeDefinition{
				kind: .catch_clause
				name: t.ident
				node: n
			})
			for _ in t.defaults {
				b.write_value(t.ident, false, true)
			}
		}
		for r in rhs {
			b.visit(r)
		}
	}
	b.visit_opt(node_field(n, 'body'))
	b.close()
}

fn (mut b ScopeBuilder) visit_type_opt(n ?C.TSNode) {
	if node := n {
		b.visit_type(node)
	}
}

// visit_type ports TypeVisitor.
fn (mut b ScopeBuilder) visit_type(n C.TSNode) {
	match node_kind(n) {
		'type_identifier' {
			// tree-sitter reads the `bigint` keyword, and `intrinsic` as the whole value of a type alias
			// (a keyword of the standard library), as names.
			text := b.text(n)
			if text != 'bigint' && !(text == 'intrinsic' && scope_is_alias_value(n)) {
				b.read_type(n)
			}
		}
		'identifier' {
			b.read_type(n)
		}
		'nested_type_identifier', 'nested_identifier', 'member_expression' {
			// TSQualifiedName (and an ESTree MemberExpression in heritage clauses): the leftmost name.
			mut left := n
			for node_kind(left) in ['nested_type_identifier', 'nested_identifier', 'member_expression'] {
				left = node_field(left, 'module') or { node_field(left, 'object') or { return } }
			}
			if node_kind(left) == 'identifier' {
				b.read_type(left)
			}
		}
		'type_query' {
			b.visit_type_query(n)
		}
		'type_predicate' {
			if name := node_field(n, 'name') {
				if node_kind(name) == 'identifier' {
					b.read_value(name)
				}
			}
			b.visit_type_opt(node_field(n, 'type'))
		}
		'asserts' {
			if part := first_named(n) {
				if node_kind(part) == 'identifier' {
					b.read_value(part)
				} else if node_kind(part) == 'type_predicate' {
					b.visit_type(part)
				}
			}
		}
		'function_type', 'constructor_type', 'call_signature', 'construct_signature' {
			b.visit_function_type(n)
		}
		'method_signature' {
			b.visit_computed_key(n)
			b.visit_function_type(n)
		}
		'property_signature' {
			b.visit_computed_key(n)
			b.visit_type_opt(node_field(n, 'type'))
		}
		'index_signature' {
			b.visit_type_opt(node_field(n, 'index_type'))
			b.visit_type_opt(node_field(n, 'type'))
		}
		'object_type' {
			if clause := scope_mapped_clause(n) {
				b.visit_mapped_type(n, clause)
			} else {
				for member in named_children(n) {
					b.visit_type(member)
				}
			}
		}
		'conditional_type' {
			b.nest(.conditional_type, n, b.block_start(n), b.block_end(n))
			b.visit_type_opt(node_field(n, 'left'))
			b.visit_type_opt(node_field(n, 'right'))
			b.visit_type_opt(node_field(n, 'consequence'))
			b.close()
			b.visit_type_opt(node_field(n, 'alternative'))
		}
		'infer_type' {
			b.visit_infer(n)
		}
		'type_parameter' {
			if name := node_field(n, 'name') {
				b.define(b.current, name, ScopeDefinition{
					kind: .type_definition
					name: name
					node: n
				})
			}
			b.visit_type_opt(node_field(n, 'constraint'))
			b.visit_type_opt(node_field(n, 'value'))
		}
		'interface_declaration', 'type_alias_declaration' {
			b.visit_type_declaration(n)
		}
		'tuple_type' {
			for element in named_children(n) {
				if node_kind(element) in ['required_parameter', 'optional_parameter'] {
					// A named member: its label is not a reference.
					b.visit_type_opt(node_field(element, 'type'))
				} else {
					b.visit_type(element)
				}
			}
		}
		'predefined_type', 'this_type', 'literal_type', 'existential_type', 'this',
		'call_expression',
		'string', 'number', 'string_fragment', 'comment' {
		}
		else {
			for child in named_children(n) {
				b.visit_type(child)
			}
		}
	}
}

fn scope_is_alias_value(n C.TSNode) bool {
	parent := node_parent(n) or { return false }
	value := node_field(parent, 'value') or { return false }
	return node_kind(parent) == 'type_alias_declaration' && node_key(value) == node_key(n)
}

// visit_type_query ports TypeVisitor.TSTypeQuery: `typeof x.y` references the value x.
fn (mut b ScopeBuilder) visit_type_query(n C.TSNode) {
	mut expression := first_named(n) or { return }
	mut type_arguments := ?C.TSNode(none)
	if node_kind(expression) == 'instantiation_expression' {
		type_arguments = node_field(expression, 'type_arguments')
		expression = node_field(expression, 'function') or {
			named_children(expression).filter(node_kind(it) != 'type_arguments')[0] or { return }
		}
	}
	for node_kind(expression) in ['member_expression', 'subscript_expression'] {
		expression = node_field(expression, 'object') or { return }
	}
	if node_kind(expression) == 'identifier' {
		b.read_value(expression)
	}
	b.visit_type_opt(type_arguments)
}

// visit_function_type ports TypeVisitor.visitFunctionType: parameters only visible inside.
fn (mut b ScopeBuilder) visit_function_type(n C.TSNode) {
	// The ESTree range of a member of an interface or a type literal includes its `;` or `,`.
	mut end := b.block_end(n)
	if node_kind(n) in ['call_signature', 'construct_signature', 'method_signature'] {
		if next := next_sibling(n) {
			if node_kind(next) in [';', ','] {
				end = node_end(next)
			}
		}
	}
	b.nest(.function_type, n, node_start(n), end)
	b.visit_type_opt(node_field(n, 'type_parameters'))
	if parameters := node_field(n, 'parameters') {
		for p in named_children(parameters) {
			if node_kind(p) !in ['required_parameter', 'optional_parameter'] {
				continue
			}
			pattern := node_field(p, 'pattern') or { node_field(p, 'name') or { continue } }
			mut targets := []ScopeTarget{}
			mut rhs := []C.TSNode{}
			b.collect_pattern(pattern, []C.TSNode{}, -1, mut targets, mut rhs)
			for t in targets {
				b.define(b.current, t.ident, ScopeDefinition{
					kind: .parameter
					name: t.ident
					node: n
					rest: t.rest
				})
			}
			b.visit_type_opt(node_field(p, 'type'))
		}
	}
	b.visit_type_opt(node_field(n, 'return_type'))
	if node_kind(n) in ['construct_signature', 'constructor_type'] {
		b.visit_type_opt(node_field(n, 'type'))
	}
	b.close()
}

// scope_mapped_clause is the mapped_type_clause of an object type that is a mapped type
// (`{ [K in T]: U }`, a TSMappedType in ESTree).
fn scope_mapped_clause(n C.TSNode) ?C.TSNode {
	members := named_children(n)
	if members.len != 1 || node_kind(members[0]) != 'index_signature' {
		return none
	}
	for child in named_children(members[0]) {
		if node_kind(child) == 'mapped_type_clause' {
			return child
		}
	}
	return none
}

// visit_mapped_type ports TypeVisitor.TSMappedType.
fn (mut b ScopeBuilder) visit_mapped_type(n C.TSNode, clause C.TSNode) {
	b.nest(.mapped_type, n, b.block_start(n), b.block_end(n))
	if name := node_field(clause, 'name') {
		b.define(b.current, name, ScopeDefinition{
			kind: .type_definition
			name: name
			node: n
		})
	}
	b.visit_type_opt(node_field(clause, 'type'))
	b.visit_type_opt(node_field(clause, 'alias'))
	if signature := first_named(n) {
		b.visit_type_opt(node_field(signature, 'type'))
	}
	b.close()
}

// visit_infer ports TypeVisitor.TSInferType: the inferred name belongs to the conditional type
// that contains it (through function type and mapped type scopes).
fn (mut b ScopeBuilder) visit_infer(n C.TSNode) {
	parts := named_children(n)
	if parts.len == 0 {
		return
	}
	mut scope := b.current
	if b.tree.scopes[scope].kind in [.function_type, .mapped_type] {
		mut upper := b.tree.scopes[scope].upper
		for upper >= 0 {
			kind := b.tree.scopes[upper].kind
			if kind in [.function_type, .mapped_type] {
				upper = b.tree.scopes[upper].upper
				continue
			}
			if kind == .conditional_type {
				scope = upper
			}
			break
		}
	}
	b.define(scope, parts[0], ScopeDefinition{
		kind: .type_definition
		name: parts[0]
		node: n
	})
	if parts.len > 1 {
		b.visit_type(parts[1])
	}
}

// visit_type_declaration ports TSInterfaceDeclaration and TSTypeAliasDeclaration: the type
// parameters live in their own scope.
fn (mut b ScopeBuilder) visit_type_declaration(n C.TSNode) {
	if name := node_field(n, 'name') {
		b.define(b.current, name, ScopeDefinition{
			kind: .type_definition
			name: name
			node: n
		})
	}
	type_parameters := node_field(n, 'type_parameters')
	if _ := type_parameters {
		b.nest(.type_scope, n, b.block_start(n), b.block_end(n))
	}
	b.visit_type_opt(type_parameters)
	if node_kind(n) == 'interface_declaration' {
		for child in named_children(n) {
			if node_kind(child) == 'extends_type_clause' {
				b.visit_type(child)
			}
		}
		b.visit_type_opt(node_field(n, 'body'))
	} else {
		b.visit_type_opt(node_field(n, 'value'))
	}
	if _ := type_parameters {
		b.close()
	}
}
