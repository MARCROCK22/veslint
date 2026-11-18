module rules

import estree
import jsregexp
import os
import sync
import treesitter

// svelte.config.js as svelte-eslint-parser 1.10.1 reads it (src/svelte-config/): without running
// it. From the linted file's directory up (the root excluded), the first `svelte.config.js` is
// parsed and its `export default` evaluated statically: literals, identifiers bound by a `const`
// (destructuring and defaults included) and object literals (spreads included); anything else is
// unknown. Only two things are taken from it: compilerOptions.runes (as a boolean) and kit.files
// (when wholly static), whose `routes` getSvelteContext reads. parserOptions.svelteConfig, when
// given, replaces the file (which is then not read). svelte-eslint-parser hands the result to the
// rules in svelteParseContext.svelteConfig: getSvelteContext's routes, the compiler options of
// valid-compile, and svelteParseContext.runes (after svelteFeatures.runes and <svelte:options>).
//
// A config file with a syntax error makes svelte-eslint-parser throw for every component (espree
// rejects it); veslint reads such a file as no config.

// SvelteConfigValues is what the rules read of svelteParseContext.svelteConfig.
struct SvelteConfigValues {
	// runes: compilerOptions.runes (-1 unset, 0 false, 1 true); routes: kit.files.routes ('' when
	// not a string); async: compilerOptions.experimental.async (parserOptions.svelteConfig only).
	runes  int = -1
	routes string
	async  bool
}

struct SvcfgCached {
	mtime  i64
	values SvelteConfigValues
}

struct SvcfgCache {
mut:
	mutex &sync.Mutex = sync.new_mutex()
	files map[string]SvcfgCached
}

const svcfg_cache = &SvcfgCache{}

// svelte_config is svelteParseContext.svelteConfig of a file svelte-eslint-parser parses (a
// component or a `.svelte.[js|ts]` module; `path` is the file's own path): parserOptions'
// svelteConfig when given, else the static reading of svelte.config.js.
fn (c &Checker) svelte_config(path string) SvelteConfigValues {
	if c.language.svelte_config_given {
		return SvelteConfigValues{
			runes:  c.language.svelte_config_runes
			routes: c.language.svelte_kit_routes
			async:  c.language.svelte_config_async
		}
	}
	file := svcfg_find(path) or { return SvelteConfigValues{} }
	mtime := os.file_last_mod_unix(file)
	unsafe {
		mut cache := svcfg_cache
		cache.mutex.lock()
		defer {
			cache.mutex.unlock()
		}
		if cached := cache.files[file] {
			if cached.mtime == mtime {
				return cached.values
			}
		}
		values := svcfg_read(file)
		cache.files[file] = SvcfgCached{
			mtime:  mtime
			values: values
		}
		return values
	}
	return SvelteConfigValues{}
}

// svcfg_find is findConfigFilePath: from the file's directory (the current one when the file
// does not exist) up, the root excluded.
fn svcfg_find(path string) ?string {
	// path.resolve: absolute, symbolic links kept.
	mut dir := os.abs_path(if path != '' && os.exists(path) { os.dir(path) } else { os.getwd() })
	for {
		parent := os.dir(dir)
		if parent == dir || dir == '' {
			return none
		}
		target := os.join_path(dir, 'svelte.config.js')
		if os.is_file(target) {
			return target
		}
		dir = parent
	}
	return none
}

// svcfg_read is parseConfig of the file (no values when it cannot be read or parsed).
fn svcfg_read(file string) SvelteConfigValues {
	src := os.read_file(file) or { return SvelteConfigValues{} }
	return svcfg_parse(src)
}

// svcfg_parse is parseConfig of a config's code.
fn svcfg_parse(src string) SvelteConfigValues {
	parser := treesitter.new_parser() or { return SvelteConfigValues{} }
	defer {
		parser.close()
	}
	tree := parser.parse(src) or { return SvelteConfigValues{} }
	defer {
		treesitter.tree_delete(tree)
	}
	if treesitter.tree_has_error(tree) {
		return SvelteConfigValues{}
	}
	mut t := estree.convert_with(treesitter.root_node(tree), src, false, estree.Options{
		module:       true
		regexp_valid: fn (pattern string, flags string) bool {
			return jsregexp.regexp_new(estree.utf16_units(pattern), flags) != none
		}
	}) or { return SvelteConfigValues{} }
	mut ev := SvcfgEvaluator{
		t: &t
	}
	return ev.config()
}

// --- the static evaluation (Evaluated, EvaluatedLiteral, EvaluatedObject of parser.ts) ---

enum SvcfgKind {
	undefined
	null
	boolean
	number
	string
	bigint // `s`: its decimal digits
	regexp // `s`: its source text
	object
}

// SvcfgValue is a JavaScript value of the static result.
struct SvcfgValue {
	kind SvcfgKind
	b    bool
	n    f64
	s    string
	// An object's own properties, in order.
	keys   []string
	values []SvcfgValue
}

// truthy is Boolean(value).
fn (v SvcfgValue) truthy() bool {
	return match v.kind {
		.undefined, .null { false }
		.boolean { v.b }
		.number { v.n != 0 && v.n == v.n }
		.string { v.s != '' }
		.bigint { v.s.trim_left('-') != '0' }
		.regexp, .object { true }
	}
}

// key_string is String(value), a property key.
fn (v SvcfgValue) key_string() string {
	return match v.kind {
		.undefined { 'undefined' }
		.null { 'null' }
		.boolean { if v.b { 'true' } else { 'false' } }
		.number { js_number_to_string(v.n) }
		.string, .bigint, .regexp { v.s }
		.object { '[object Object]' }
	}
}

fn (v SvcfgValue) get(key string) ?SvcfgValue {
	for k, name in v.keys {
		if name == key {
			return v.values[k]
		}
	}
	return none
}

// SvcfgEval is an Evaluated: a literal (`value`) or an object literal (its node).
struct SvcfgEval {
	is_object bool
	value     SvcfgValue
	node      int = -1
}

// SvcfgDef is a definition of a name in the config's scopes: a `Variable` one has its declarator
// and the kind of its declaration; the others (imports, functions, classes, parameters) are
// `other`.
struct SvcfgDef {
	variable   bool
	declarator int = -1
	kind       string
	name       int = -1
}

struct SvcfgCacheEntry {
	found bool
	value SvcfgEval
}

struct SvcfgEvaluator {
mut:
	t &estree.EsTree = unsafe { nil }
	// cached: EvaluatedObject's cache, by object node and key (a null result included).
	cached map[string]SvcfgCacheEntry
	// tracked: getIdentifierDefinitions' map.
	tracked map[int][]SvcfgDef
	depth   int
}

// config is parseAst and parseSvelteConfigExpression.
fn (mut ev SvcfgEvaluator) config() SvelteConfigValues {
	t := ev.t
	body := t.list(t.root, .body) or { return SvelteConfigValues{} }
	mut declaration := -1
	for st in body {
		if st >= 0 && t.typ(st) == .export_default_declaration {
			declaration = t.node(st, .declaration) or { -1 }
			break
		}
	}
	if declaration < 0 || t.typ(declaration) in [.class_declaration, .function_declaration] {
		return SvelteConfigValues{}
	}
	evaluated := ev.expression(declaration) or { return SvelteConfigValues{} }
	if !evaluated.is_object {
		return SvelteConfigValues{}
	}
	mut runes := -1
	if compiler := ev.property(evaluated, 'compilerOptions') {
		if compiler.is_object {
			if r := ev.property(compiler, 'runes') {
				if value := ev.static_of(r) {
					if value.kind !in [.undefined, .null] {
						runes = if value.truthy() { 1 } else { 0 }
					}
				}
			}
		}
	}
	mut routes := ''
	if kit := ev.property(evaluated, 'kit') {
		if kit.is_object {
			if files := ev.property(kit, 'files') {
				if value := ev.static_of(files) {
					if r := value.get('routes') {
						if value.kind == .object && r.kind == .string {
							routes = r.s
						}
					}
				}
			}
		}
	}
	return SvelteConfigValues{
		runes:  runes
		routes: routes
	}
}

// literal is an EvaluatedLiteral of a Literal node's value.
fn (ev &SvcfgEvaluator) literal(i int) SvcfgValue {
	value := ev.t.get(i, .value)
	return match value {
		string { SvcfgValue{
				kind: .string
				s:    value
			} }
		f64 { SvcfgValue{
				kind: .number
				n:    value
			} }
		bool { SvcfgValue{
				kind: .boolean
				b:    value
			} }
		estree.BigIntValue { SvcfgValue{
				kind: .bigint
				s:    value.digits
			} }
		estree.RegExpValue { SvcfgValue{
				kind: .regexp
				s:    ev.t.src[ev.t.nodes[i].start..ev.t.nodes[i].end]
			} }
		else { SvcfgValue{
				kind: .null
			} }
	}
}

// expression is parseExpression.
fn (mut ev SvcfgEvaluator) expression(i int) ?SvcfgEval {
	if i < 0 {
		return none
	}
	match ev.t.typ(i) {
		.literal {
			return SvcfgEval{
				value: ev.literal(i)
			}
		}
		.identifier {
			return ev.identifier(i)
		}
		.object_expression {
			return SvcfgEval{
				is_object: true
				node:      i
			}
		}
		else {
			return none
		}
	}
}

// with_cache is EvaluatedObject.withCache.
fn (mut ev SvcfgEvaluator) with_cache(object int, key string, value_node int) ?SvcfgEval {
	cache_key := '${object}:${key}'
	if entry := ev.cached[cache_key] {
		return if entry.found { entry.value } else { none }
	}
	result := ev.expression(value_node)
	ev.cached[cache_key] = if r := result {
		SvcfgCacheEntry{
			found: true
			value: r
		}
	} else {
		SvcfgCacheEntry{}
	}
	return result
}

// property is EvaluatedObject.getProperty: the value of the last property with that key (from
// spreads too), unknown when a key cannot be told, undefined when there is none.
fn (mut ev SvcfgEvaluator) property(object SvcfgEval, key string) ?SvcfgEval {
	cache_key := '${object.node}:${key}'
	if entry := ev.cached[cache_key] {
		return if entry.found { entry.value } else { none }
	}
	result := ev.property_uncached(object.node, key)
	ev.cached[cache_key] = if r := result {
		SvcfgCacheEntry{
			found: true
			value: r
		}
	} else {
		SvcfgCacheEntry{}
	}
	return result
}

fn (mut ev SvcfgEvaluator) property_uncached(node int, key string) ?SvcfgEval {
	ev.depth++
	defer {
		ev.depth--
	}
	if ev.depth > 200 {
		return none
	}
	t := ev.t
	properties := t.list(node, .properties) or { []int{} }
	mut unknown := false
	for k := properties.len - 1; k >= 0; k-- {
		prop := properties[k]
		match t.typ(prop) {
			.property {
				name := ev.key_of(prop) or {
					unknown = true
					continue
				}
				if name == key {
					return ev.expression(t.node(prop, .value) or { -1 })
				}
			}
			.spread_element {
				if evaluated := ev.expression(t.node(prop, .argument) or { -1 }) {
					if evaluated.is_object {
						if value := ev.property(evaluated, key) {
							return value
						}
					}
				}
				unknown = true
			}
			else {}
		}
	}
	if unknown {
		return none
	}
	return SvcfgEval{}
}

// key_of is EvaluatedObject.getKey.
fn (mut ev SvcfgEvaluator) key_of(prop int) ?string {
	t := ev.t
	key := t.node(prop, .key) or { return none }
	computed := t.flag(prop, .computed) or { false }
	if !computed && t.typ(key) == .identifier {
		return t.string_of(key, .name) or { '' }
	}
	evaluated := ev.expression(key)?
	value := ev.static_of(evaluated)?
	return value.key_string()
}

// static_of is getStatic: the value, when the whole of it is static.
fn (mut ev SvcfgEvaluator) static_of(e SvcfgEval) ?SvcfgValue {
	if !e.is_object {
		return e.value
	}
	ev.depth++
	defer {
		ev.depth--
	}
	if ev.depth > 200 {
		return none
	}
	t := ev.t
	mut keys := []string{}
	mut values := []SvcfgValue{}
	for prop in t.list(e.node, .properties) or { []int{} } {
		match t.typ(prop) {
			.property {
				name := ev.key_of(prop)?
				evaluated := ev.with_cache(e.node, name, t.node(prop, .value) or { -1 })?
				value := ev.static_of(evaluated)?
				svcfg_assign(mut keys, mut values, name, value)
			}
			.spread_element {
				evaluated := ev.expression(t.node(prop, .argument) or { -1 })?
				value := ev.static_of(evaluated)?
				// Object.assign: an object's own properties; a string's characters.
				if value.kind == .object {
					for k, name in value.keys {
						svcfg_assign(mut keys, mut values, name, value.values[k])
					}
				} else if value.kind == .string {
					for k, ch in value.s.runes() {
						svcfg_assign(mut keys, mut values, k.str(), SvcfgValue{
							kind: .string
							s:    ch.str()
						})
					}
				}
			}
			else {}
		}
	}
	return SvcfgValue{
		kind:   .object
		keys:   keys
		values: values
	}
}

fn svcfg_assign(mut keys []string, mut values []SvcfgValue, key string, value SvcfgValue) {
	at := keys.index(key)
	if at >= 0 {
		values[at] = value
	} else {
		keys << key
		values << value
	}
}

// identifier is parseIdentifier.
fn (mut ev SvcfgEvaluator) identifier(i int) ?SvcfgEval {
	ev.depth++
	defer {
		ev.depth--
	}
	if ev.depth > 200 {
		return none
	}
	t := ev.t
	defs := ev.definitions(i)
	if defs.len != 1 {
		if defs.len == 0 && (t.string_of(i, .name) or { '' }) == 'undefined' {
			return SvcfgEval{}
		}
		return none
	}
	def := defs[0]
	if !def.variable || def.kind != 'const' {
		return none
	}
	init := t.node(def.declarator, .init) or { return none }
	mut result := ev.expression(init)?
	id := t.node(def.declarator, .id) or { return none }
	for step in ev.pattern_path(def.name, id) or { []SvcfgStep{} } {
		if !step.assignment {
			if !result.is_object {
				return none
			}
			result = ev.property(result, step.member)?
		} else if !result.is_object && result.value.kind == .undefined {
			result = ev.expression(t.node(step.node, .right) or { -1 })?
		}
	}
	return result
}

// SvcfgStep is a step of parsePatternAssign: a member (by name) or a default value (its
// AssignmentPattern node).
struct SvcfgStep {
	member     string
	assignment bool
	node       int = -1
}

// pattern_path is parsePatternAssign: the path from the pattern `root` to the name `target`.
fn (ev &SvcfgEvaluator) pattern_path(target int, root int) ?[]SvcfgStep {
	t := ev.t
	if root == target {
		return []SvcfgStep{}
	}
	match t.typ(root) {
		.identifier {
			return none
		}
		.assignment_pattern {
			left := ev.pattern_path(target, t.node(root, .left) or { return none })?
			mut out := [SvcfgStep{
				assignment: true
				node:       root
			}]
			out << left
			return out
		}
		.object_pattern {
			for prop in t.list(root, .properties) or { []int{} } {
				if t.typ(prop) != .property {
					continue
				}
				key := t.node(prop, .key) or { continue }
				computed := t.flag(prop, .computed) or { false }
				name := if !computed && t.typ(key) == .identifier {
					t.string_of(key, .name) or { '' }
				} else if t.typ(key) == .literal {
					ev.literal(key).key_string()
				} else {
					''
				}
				if name == '' {
					continue
				}
				// The first property with a name decides (upstream returns from it).
				value := ev.pattern_path(target, t.node(prop, .value) or { -1 })?
				mut out := [SvcfgStep{
					member: name
				}]
				out << value
				return out
			}
			return none
		}
		.array_pattern {
			for index, element in t.list(root, .elements) or { []int{} } {
				if element < 0 {
					continue
				}
				value := ev.pattern_path(target, element)?
				mut out := [SvcfgStep{
					member: index.str()
				}]
				out << value
				return out
			}
			return none
		}
		else {
			return none
		}
	}
}

// definitions is getIdentifierDefinitions: the definitions of the variable a reference resolves
// to (none when it resolves to nothing), following `const a = b` when there are several.
fn (mut ev SvcfgEvaluator) definitions(i int) []SvcfgDef {
	if defs := ev.tracked[i] {
		return defs
	}
	ev.tracked[i] = []
	defs := ev.resolve(i)
	if defs.len == 0 {
		return []
	}
	ev.tracked[i] = defs
	if defs.len != 1 {
		def := defs[0]
		if def.variable && def.kind == 'const' {
			id := ev.t.node(def.declarator, .id) or { -1 }
			init := ev.t.node(def.declarator, .init) or { -1 }
			if id >= 0 && ev.t.typ(id) == .identifier && init >= 0 && ev.t.typ(init) == .identifier {
				new_defs := ev.definitions(init)
				ev.tracked[i] = new_defs
				return new_defs
			}
		}
	}
	return defs
}

// resolve is findVariable's definitions for a reference: the closest scope from the reference
// up that declares the name (blocks: let, const, class, function; functions: their parameters
// and `var`s; the module: its declarations, imports and the `var`s outside functions).
fn (ev &SvcfgEvaluator) resolve(i int) []SvcfgDef {
	t := ev.t
	name := t.string_of(i, .name) or { return [] }
	mut node := t.nodes[i].parent
	for node >= 0 {
		match t.typ(node) {
			.program {
				return ev.scope_defs(node, name, true)
			}
			.block_statement, .static_block, .switch_statement {
				defs := ev.scope_defs(node, name, false)
				if defs.len > 0 {
					return defs
				}
			}
			.for_statement, .for_in_statement, .for_of_statement {
				head := t.node(node, if t.typ(node) == .for_statement { .init } else { .left }) or {
					-1
				}
				if head >= 0 && t.typ(head) == .variable_declaration
					&& (t.string_of(head, .kind) or { '' }) != 'var' {
					defs := ev.declaration_defs(head, name)
					if defs.len > 0 {
						return defs
					}
				}
			}
			.catch_clause {
				param := t.node(node, .param) or { -1 }
				if param >= 0 && ev.pattern_names(param).contains(name) {
					return [SvcfgDef{}]
				}
			}
			.function_declaration, .function_expression, .arrow_function_expression {
				for param in t.list(node, .params) or { []int{} } {
					if param >= 0 && ev.pattern_names(param).contains(name) {
						return [SvcfgDef{}]
					}
				}
				mut defs := []SvcfgDef{}
				body := t.node(node, .body) or { -1 }
				if body >= 0 {
					ev.var_defs(body, name, mut defs)
				}
				if defs.len > 0 {
					return defs
				}
			}
			else {}
		}
		node = t.nodes[node].parent
	}
	return []
}

// scope_defs are the definitions of a name in a block's (or the module's) own declarations; the
// module also has the `var`s outside functions.
fn (ev &SvcfgEvaluator) scope_defs(node int, name string, module bool) []SvcfgDef {
	t := ev.t
	statements := if t.typ(node) == .switch_statement {
		mut all := []int{}
		for case in t.list(node, .cases) or { []int{} } {
			all << t.list(case, .consequent) or { []int{} }
		}
		all
	} else {
		t.list(node, .body) or { []int{} }
	}
	mut defs := []SvcfgDef{}
	for st0 in statements {
		mut st := st0
		if module && st >= 0 && t.typ(st) in [.export_named_declaration, .export_default_declaration] {
			st = t.node(st, .declaration) or { continue }
		}
		if st < 0 {
			continue
		}
		match t.typ(st) {
			.variable_declaration {
				if (t.string_of(st, .kind) or { '' }) != 'var' {
					defs << ev.declaration_defs(st, name)
				}
			}
			.function_declaration, .class_declaration {
				id := t.node(st, .id) or { continue }
				if (t.string_of(id, .name) or { '' }) == name {
					defs << SvcfgDef{}
				}
			}
			.import_declaration {
				if module {
					for spec in t.list(st, .specifiers) or { []int{} } {
						local := t.node(spec, .local) or { continue }
						if (t.string_of(local, .name) or { '' }) == name {
							defs << SvcfgDef{}
						}
					}
				}
			}
			else {}
		}
	}
	if module {
		ev.var_defs(node, name, mut defs)
	}
	return defs
}

// var_defs adds the `var` declarations of a name under `node`, functions excluded.
fn (ev &SvcfgEvaluator) var_defs(node int, name string, mut defs []SvcfgDef) {
	t := ev.t
	mut stack := [node]
	for stack.len > 0 {
		n := stack.pop()
		if n < 0 {
			continue
		}
		typ := t.typ(n)
		if n != node && typ in [.function_declaration, .function_expression,
			.arrow_function_expression, .class_declaration, .class_expression] {
			continue
		}
		if typ == .variable_declaration && (t.string_of(n, .kind) or { '' }) == 'var' {
			defs << ev.declaration_defs(n, name)
			continue
		}
		kids := t.children(n)
		for k := kids.len - 1; k >= 0; k-- {
			stack << kids[k]
		}
	}
}

// declaration_defs are the definitions of a name by the declarators of a declaration.
fn (ev &SvcfgEvaluator) declaration_defs(declaration int, name string) []SvcfgDef {
	t := ev.t
	kind := t.string_of(declaration, .kind) or { '' }
	mut defs := []SvcfgDef{}
	for declarator in t.list(declaration, .declarations) or { []int{} } {
		id := t.node(declarator, .id) or { continue }
		for name_node in ev.pattern_identifiers(id) {
			if (t.string_of(name_node, .name) or { '' }) == name {
				defs << SvcfgDef{
					variable:   true
					declarator: declarator
					kind:       kind
					name:       name_node
				}
			}
		}
	}
	return defs
}

// pattern_identifiers are the names a pattern binds.
fn (ev &SvcfgEvaluator) pattern_identifiers(pattern int) []int {
	t := ev.t
	if pattern < 0 {
		return []
	}
	return match t.typ(pattern) {
		.identifier {
			[pattern]
		}
		.assignment_pattern {
			ev.pattern_identifiers(t.node(pattern, .left) or { -1 })
		}
		.rest_element {
			ev.pattern_identifiers(t.node(pattern, .argument) or { -1 })
		}
		.object_pattern {
			mut out := []int{}
			for prop in t.list(pattern, .properties) or { []int{} } {
				if t.typ(prop) == .property {
					out << ev.pattern_identifiers(t.node(prop, .value) or { -1 })
				} else {
					out << ev.pattern_identifiers(prop)
				}
			}
			out
		}
		.array_pattern {
			mut out := []int{}
			for element in t.list(pattern, .elements) or { []int{} } {
				out << ev.pattern_identifiers(element)
			}
			out
		}
		else {
			[]int{}
		}
	}
}

fn (ev &SvcfgEvaluator) pattern_names(pattern int) []string {
	return ev.pattern_identifiers(pattern).map(ev.t.string_of(it, .name) or { '' })
}
