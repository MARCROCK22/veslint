module rules

import json2
import treesitter { Parser, nodes_of_kinds, node_start, root_node, token_ends }

fn scope_test_tree(src string) (&ScopeTree, C.TSNode) {
	parser := treesitter.new_parser() or { panic(err) }
	tree := parser.parse(src) or { panic(err) }
	root := root_node(tree)
	return build_scope_tree(root, src, token_ends(root)), root
}

// scope_test_node is the identifier-like node of `src` that starts at the i-th occurrence of
// `name` (0-based).
fn scope_test_node(root C.TSNode, src string, name string, occurrence int) C.TSNode {
	mut seen := 0
	for n in nodes_of_kinds(root, ['identifier', 'type_identifier', 'property_identifier',
		'shorthand_property_identifier', 'shorthand_property_identifier_pattern', 'undefined',
		'private_property_identifier'], []string{}) {
		if src[node_start(n)..treesitter.node_end(n)] == name {
			if seen == occurrence {
				return n
			}
			seen++
		}
	}
	panic('no ${name} #${occurrence}')
}

fn scope_test_refs(t &ScopeTree, name string) []ScopeReference {
	return t.references.filter(it.name == name)
}

// getScope: the program is the global scope, any other top-level node the module scope; functions,
// blocks, classes and their parts follow ESLint (a method's name is outside its function).
fn test_get_scope() {
	src := 'const a = 1;\nfunction f(p = a) { { let b = p; } }\nclass C { m(q) { return q; } [a] = () => a; }\n@dec export class D {}\n'
	t, root := scope_test_tree(src)
	assert t.get_scope(root) == 0
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'a', 0))].kind == .esmodule
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'f', 0))].kind == .function
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'p', 0))].kind == .function
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'b', 0))].kind == .block
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'm', 0))].kind == .class_scope
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'q', 0))].kind == .function
	// `[a]` is a computed key (class scope); the arrow of its value is a function.
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'a', 2))].kind == .class_scope
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'a', 3))].kind == .function
	// The decorator before `export` belongs to the class.
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'dec', 0))].kind == .class_scope
}

// find_variable from the global scope with a location reaches the same scope as getScope.
fn test_find_variable_and_own_variable() {
	src := 'const x = 1;\nfunction f() { const x = 2; return [x, String, undefined, Nope]; }\n'
	t, root := scope_test_tree(src)
	inner := scope_test_node(root, src, 'x', 2)
	v := t.find_variable(0, 'x', node_start(inner))
	assert v >= 0 && t.scopes[t.variables[v].scope].kind == .function
	outer := t.find_variable(0, 'x', -1)
	assert outer < 0 // no descent: the global scope does not declare x
	assert t.variables[t.find_variable(1, 'x', -1)].scope == 1
	// ECMAScript globals are variables without definitions; undeclared names have none.
	s := t.find_variable(0, 'String', node_start(scope_test_node(root, src, 'String', 0)))
	assert s >= 0 && t.variables[s].scope == 0 && t.variables[s].defs.len == 0
	assert t.find_variable(0, 'undefined', -1) >= 0
	assert t.find_variable(0, 'Nope', -1) == -1
	f := t.get_scope(inner)
	assert t.own_variable(f, 'x') >= 0
	assert t.own_variable(f, 'f') == -1
	assert t.own_variable(1, 'f') >= 0
}

// Definitions: kind, parent kind, declarator id and init (none for `let x;`, `declare` and for-of
// heads, which still are variable definitions).
fn test_definitions() {
	src := 'let a;\ndeclare const b: number;\nconst { c } = obj;\nfor (const d of []) {}\nfunction g(...e: number[]) {}\nimport f from "m";\ntry {} catch (h) {}\n'
	t, root := scope_test_tree(src)
	def := fn [t, root, src] (name string) ScopeDefinition {
		v := t.declared_variable(scope_test_node(root, src, name, 0))
		assert v >= 0
		return t.variables[v].defs[0]
	}
	a := def('a')
	assert a.kind == .variable && a.parent_kind == 'let' && a.init == none
	b := def('b')
	assert b.kind == .variable && b.parent_kind == 'const' && b.init == none
	c := def('c')
	assert c.parent_kind == 'const' && c.init != none
	if id := c.decl_id {
		assert treesitter.node_kind(id) == 'object_pattern'
	} else {
		assert false
	}
	d := def('d')
	assert d.kind == .variable && d.parent_kind == 'const' && d.init == none
	e := def('e')
	assert e.kind == .parameter && e.rest
	assert def('f').kind == .import_binding
	assert def('h').kind == .catch_clause
}

// Read and write flags as typescript-eslint's Referencer sets them (checked against its scope
// manager): one `as`/`<T>`/`!` around an assignment or update target is unwrapped.
fn test_reference_flags() {
	src := 'let x = 1;\nx!++;\n(x as any) = 2;\n(x satisfies number);\nx += 1;\n[x] = [1];\nfor (x of []) {}\nx++;\n({ a: x } = {});\nx! = 4;\ntypeof x;\nexport { x };\n'
	t, _ := scope_test_tree(src)
	flags := scope_test_refs(t, 'x').map('${if it.read { 'R' } else { '' }}${if it.write {
		'W'
	} else {
		''
	}}${if it.init { 'i' } else { '' }}')
	assert flags == ['Wi', 'RW', 'W', 'R', 'RW', 'W', 'W', 'RW', 'W', 'W', 'R', 'R']
	refs := scope_test_refs(t, 'x')
	assert refs.last().type_ref && refs.last().value_ref // export { x } is a type and value reference
	assert refs.all(it.resolved >= 0)
	assert refs.filter(it.is_read_only()).len == 3
}

// A reference in the parameters does not see a variable declared only in the body; a type
// reference does not resolve to a value-only variable.
fn test_resolution() {
	src := 'const v = 1;\nfunction f(p = v) { const v = 2; }\ntype T = typeof v;\nlet w: w;\n'
	t, _ := scope_test_tree(src)
	v_refs := scope_test_refs(t, 'v').filter(!it.write)
	assert v_refs.len == 2
	for r in v_refs {
		assert t.variables[r.resolved].scope == 1
	}
	w_type := scope_test_refs(t, 'w').filter(it.type_ref)
	assert w_type.len == 1 && w_type[0].resolved == -1
}

// Scopes created for classes, fields, static blocks, enums, namespaces and types.
fn test_scope_kinds() {
	src := 'class K<T> { f = 1; static { } }\nenum E { A }\nnamespace N {}\ntype M<U> = { [P in keyof U]: U[P] };\ntype C<V> = V extends Array<infer I> ? I : never;\nswitch (1) {}\nfor (let i = 0; ; ) {}\n'
	t, _ := scope_test_tree(src)
	kinds := t.scopes.map(it.kind)
	assert kinds == [.global, .esmodule, .class_scope, .class_field_initializer, .class_static_block,
		.ts_enum, .ts_module, .type_scope, .mapped_type, .type_scope, .conditional_type,
		.switch_statement, .for_statement, .block]
}

// The implicit variables of the libs: the libs and the ones they include in typescript-eslint's
// order, where the first one that has a name decides whether it is a type, a value or both.
fn test_scope_libs() {
	assert scope_lib_order(['ES2015', 'dom', 'es2015', 'no-such-lib'])[..5] == [
		'es2015',
		'dom',
		'es5',
		'es2015.core',
		'es2015.collection',
	]
	es5 := new_scope_libs(['es5'])
	symbol := es5.variables[es5.set['Symbol']]
	assert symbol.lib && symbol.lib_type && !symbol.lib_value
	number := es5.variables[es5.set['Number']]
	assert number.lib && number.lib_type && number.lib_value
	assert 'Map' !in es5.set && 'parseInt' !in es5.set && 'Partial' in es5.set
	assert es5.variables.last().name == 'const' && !es5.variables.last().lib_value
	full := new_scope_libs(['ES2022.Full'])
	assert 'NodeListOf' in full.set && 'BigInt' in full.set && 'Float16Array' !in full.set
	assert 'Float16Array' in new_scope_libs(['esnext.full']).set
	assert new_scope_libs([]string{}).variables.map(it.name) == ['const']
	assert new_scope_libs(['no-such-lib']).variables.len == 1
	// Every lib typescript-eslint's getLib takes from a target exists, and so does every lib
	// another one includes.
	for name in ['es6', 'es2016.full', 'es2025.full', 'esnext.full', 'lib'] {
		assert name in scope_lib_variables, name
	}
	for name, included in scope_lib_references {
		assert name in scope_lib_variables, name
		for lib in included {
			assert lib in scope_lib_variables, lib
		}
	}
}

// The globals ESLint declares: those of the ecmaVersion, of CommonJS and of the configuration,
// with the values of the comments, in the order of the keys of ESLint's object.
fn test_declared_globals() {
	language := parse_language_options(json2.decode[json2.Any]('{"ecmaVersion": 5, "sourceType": "commonjs", "globals": {"b": true, "a": "off", "7": "readonly", "JSON": "off", "exports": false}}') or {
		panic(err)
	})
	assert language.ecma_version == 5 && language.source_type == 'commonjs'
	assert language.globals.keys() == ['b', 'a', '7', 'JSON', 'exports']
	globals := declared_globals(language, {
		'a':   'writable'
		'NaN': 'off'
		'c':   'readonly'
		'3':   'readonly'
	})
	declared_names := globals.map(it.name)
	// Integer names first; then the globals of ES5 in ESLint's order (without NaN, off in a
	// comment, and JSON, off in the configuration), those of CommonJS and the others as added.
	assert declared_names[..3] == ['3', '7', 'Array']
	assert 'NaN' !in declared_names && 'JSON' !in declared_names && 'Map' !in declared_names
	assert declared_names[declared_names.len - 7..] == ['exports', 'global', 'module', 'require',
		'b', 'a', 'c']
	by_name := fn [globals] (name string) ScopeGlobal {
		return globals.filter(it.name == name)[0]
	}
	assert by_name('exports') == ScopeGlobal{'exports', false, 'readonly', false}
	assert by_name('b') == ScopeGlobal{'b', true, 'writable', false}
	assert by_name('a') == ScopeGlobal{'a', true, 'off', true}
	assert by_name('c') == ScopeGlobal{'c', false, '', true}
	assert by_name('3') == ScopeGlobal{'3', false, '', true}
	// Without options: the globals of the latest version.
	assert declared_globals(LanguageOptions{}, map[string]string{}).map(it.name) == scope_es_globals
}

// The options of typescript-eslint's parser, and how it chooses the names a JSX element references.
fn test_parser_options() {
	options := fn (text string) LanguageOptions {
		return parse_language_options(json2.decode[json2.Any](text) or { panic(err) })
	}
	project := ScopeProject{
		libs:                 ['es2022', 'dom']
		jsx_factory:          ' preact .h'
		jsx_fragment_factory: 'Fragment'
	}
	pragma, fragment := scope_jsx_names(project, options('{}'))
	assert pragma == 'preact' && fragment == 'Fragment'
	default_pragma, no_fragment := scope_jsx_names(ScopeProject{}, options('{}'))
	assert default_pragma == 'React' && no_fragment == ''
	null_pragma, own_fragment := scope_jsx_names(project, options('{"parserOptions": {"jsxPragma": null, "jsxFragmentName": "Frag"}}'))
	assert null_pragma == '' && own_fragment == 'Frag'
	own_pragma, null_fragment := scope_jsx_names(project, options('{"parserOptions": {"jsxPragma": "h", "jsxFragmentName": null}}'))
	assert own_pragma == 'h' && null_fragment == ''
	assert scope_libs_of(project, options('{}')) == ['es2022', 'dom']
	assert scope_libs_of(project, options('{"parserOptions": {"lib": ["ES5"]}}')) == ['ES5']
	assert scope_libs_of(project, options('{"parserOptions": {"lib": []}}')).len == 0
	assert scope_libs_of(project, options('{"parserOptions": {"lib": null}}')) == [
		'es2022',
		'dom',
	]
	libs := new_scope_libs([]string{})
	setup := fn [project, libs, options] (text string) ScopeSetup {
		return new_scope_setup(project, options(text), map[string]string{}, []string{},
			libs)
	}
	assert !setup('{}').script && !setup('{}').global_return
	assert setup('{"sourceType": "script"}').script && setup('{"sourceType": "commonjs"}').script
	assert !setup('{"sourceType": "commonjs", "parserOptions": {"sourceType": "module"}}').script
	assert setup('{"parserOptions": {"sourceType": "script", "ecmaFeatures": {"globalReturn": true}}}').global_return
	assert parse_language_options(json2.Any('not an object')) == LanguageOptions{}
}

// The names of an `/* exported */` comment (parseListConfig).
fn test_exported_names() {
	assert exported_names(' a, \'b\' ,"c", \'d, e\' , ,__proto__, a, \'f"') == ['a', 'b', 'c',
		"'d", "e'", '\'f"']
	assert exported_names('').len == 0
}

// A script has no module scope, and with globalReturn the program is the body of a function; the
// globals ESLint declares take the references nothing resolved, and an `/* exported */` comment
// marks a variable of the global scope.
fn test_scope_setup() {
	src := 'var top = Partial; function f() { return [top, declared, missing]; }'
	parser := treesitter.new_parser() or { panic(err) }
	tree := parser.parse(src) or { panic(err) }
	root := root_node(tree)
	setup := ScopeSetup{
		libs:          new_scope_libs(['es5'])
		declared:      [ScopeGlobal{'declared', true, 'writable', false},
			ScopeGlobal{'Partial', false, '', true}]
		exported:      ['top', 'declared', 'nothing']
		script:        true
		global_return: true
	}
	t := build_scope_tree_with(root, src, token_ends(root), setup)
	assert t.scopes.map(it.kind) == [.global, .function, .function]
	assert t.own_variable(1, 'arguments') >= 0 && t.own_variable(1, 'top') >= 0
	declared := t.variables[t.own_variable(0, 'declared')]
	assert !declared.lib && declared.writeable && declared.eslint_used
		&& declared.eslint_implicit_global_setting == 'writable' && declared.references.len == 1
	// `Partial` is a type of the lib: its value reference only resolves once ESLint declares it.
	partial := t.variables[t.own_variable(0, 'Partial')]
	assert partial.lib && partial.eslint_explicit_global && partial.references.len == 1
		&& partial.eslint_implicit_global_setting == ''
	assert t.through.map(t.references[it].name) == ['missing']
	script := build_scope_tree_with(root, src, token_ends(root), ScopeSetup{
		...setup
		global_return: false
	})
	assert script.scopes.map(it.kind) == [.global, .function]
	assert script.variables[script.own_variable(0, 'top')].eslint_used
	assert !script.variables[script.own_variable(0, 'f')].eslint_used
}

fn test_ecma_version_globals() {
	assert normalize_ecma_version(json2.Any('latest')) == scope_latest_ecma_version
	assert normalize_ecma_version(json2.Any(i64(3))) == 3
	assert normalize_ecma_version(json2.Any(i64(5))) == 5
	assert normalize_ecma_version(json2.Any(i64(6))) == 2015
	assert normalize_ecma_version(json2.Any(f64(2019))) == 2019
	assert normalize_ecma_version(json2.Any(f64(2019.5))) == -1
	assert ecma_version_has_global(3, 'parseInt') && ecma_version_has_global(5, 'NaN')
	assert !ecma_version_has_global(5, 'Proxy') && ecma_version_has_global(2015, 'Proxy')
	assert !ecma_version_has_global(2019, 'BigInt') && ecma_version_has_global(2020, 'BigInt')
	assert ecma_version_has_global(scope_latest_ecma_version, 'BigInt')
	// ESLint has no globals for a version it does not know.
	assert !ecma_version_has_global(2014, 'parseInt') && !ecma_version_has_global(2099, 'parseInt')
	assert !ecma_version_has_global(-1, 'parseInt')
	for name in scope_es_globals {
		assert name in scope_es_global_versions, name
	}
}

fn test_normalize_global_value() {
	assert normalize_global_value(json2.Any('off')) or { '' } == 'off'
	assert normalize_global_value(json2.Any(true)) or { '' } == 'writable'
	assert normalize_global_value(json2.Any('writeable')) or { '' } == 'writable'
	assert normalize_global_value(json2.Any(false)) or { '' } == 'readonly'
	assert normalize_global_value(json2.Any(json2.Null{})) or { '' } == 'readonly'
	assert normalize_global_value(json2.Any('readable')) or { '' } == 'readonly'
	assert normalize_global_value(json2.Any('on')) or { '' } == ''
}

fn test_global_entries() {
	entries := global_entries(' b : off , a b:writable,2:x 1 __proto__:off c: ,, a:readonly:z ')
	assert entries.map(it.name) == ['1', '2', 'b', 'a', 'c']
	assert entries.map(it.value) == ['', 'x', 'writable', 'readonly', '']
	assert entries.map(it.has_value) == [false, true, true, true, true]
	assert global_entries('').len == 0
}
