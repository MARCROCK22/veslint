module svelte

import estree { EsTree, Key }

// A copy of vue/scope.v (with imports and exports) for the pre-virtual code of a .svelte file.
// The references and variables vue-eslint-parser takes from the scope manager typescript-eslint's
// parser gives for a template snippet (src/script/scope-analyzer.ts): a port of
// @typescript-eslint/scope-manager 8.72.2's Referencer (with its PatternVisitor, TypeVisitor and
// ClassVisitor) over the snippet's ESTree, analyzed as a module with the lib `esnext`.
// What a snippet cannot hold is left out: implicit globals (a module is strict), `with` (an error
// in strict code), imports and exports, the JSX pragma (no lib defines React).

enum ScopeType {
	global
	module
	function
	block
	for_
	catch_
	class
	class_field_initializer
	class_static_block
	conditional_type
	function_expression_name
	function_type
	mapped_type
	switch_
	ts_enum
	ts_module
	type_
}

struct AScope {
	typ       ScopeType
	block     int
	upper     int
	var_scope int
mut:
	left      []int // references left to resolve
	closed    bool
	set       map[string]int
	variables []int
	through   []int
	children  []int
}

struct ADef {
	name     int // the node of the name (an Identifier, or a Literal for an enum member)
	is_type  bool
	is_value bool
}

struct AVar {
	name  string
	scope int
mut:
	defs       []ADef
	references []int
}

const ref_read = u8(1)
const ref_write = u8(2)
const ref_rw = u8(3)

struct ARef {
	id    int
	flag  u8
	type_ bool
	value bool
mut:
	from     int
	resolved int = -1 // a variable, -2 for an implicit lib variable
}

struct Analyzer {
	es &EsTree = unsafe { nil }
mut:
	scopes []AScope
	cur    int = -1
	vars   []AVar
	refs   []ARef
	// did_visit_annotation: visit_function_type's pattern callback visited an annotation.
	did_visit_annotation bool
}

// analyze runs the Referencer on the snippet's program.
fn analyze_snippet(es &EsTree) Analyzer {
	mut a := Analyzer{
		es: unsafe { es }
	}
	a.visit(es.root)
	return a
}

// external_references are vue-eslint-parser's references of the snippet: the global scope's
// `through`, without a reference whose identifier is the previous one's.
fn (a &Analyzer) external_references() []ARef {
	mut out := []ARef{}
	if a.scopes.len == 0 {
		return out
	}
	mut last := -1
	for r in a.scopes[0].through {
		ref := a.refs[r]
		if ref.id == last {
			continue
		}
		last = ref.id
		out << ref
	}
	return out
}

// for_scope_variables are the names (their nodes) of the variables with a definition of
// getForScope: the first scope inside the module scope.
fn (a &Analyzer) for_scope_variables() []int {
	if a.scopes.len == 0 || a.scopes[0].children.len == 0 {
		return []int{}
	}
	mut child := a.scopes[0].children[0]
	if a.scopes[child].block == a.scopes[0].block {
		if a.scopes[child].children.len == 0 {
			return []int{}
		}
		child = a.scopes[child].children[0]
	}
	mut out := []int{}
	for v in a.scopes[child].variables {
		if a.vars[v].defs.len > 0 {
			out << a.vars[v].defs[0].name
		}
	}
	return out
}

// ---- Scopes ----

fn (mut a Analyzer) nest(typ ScopeType, block int) {
	upper := a.cur
	var_scope := if typ in [.class_field_initializer, .class_static_block, .function, .global,
		.module, .ts_module] {
		a.scopes.len
	} else {
		a.scopes[upper].var_scope
	}
	a.scopes << AScope{
		typ:       typ
		block:     block
		upper:     upper
		var_scope: var_scope
	}
	idx := a.scopes.len - 1
	if upper >= 0 {
		a.scopes[upper].children << idx
	}
	a.cur = idx
	if typ == .function && a.es.typ(block) != .arrow_function_expression {
		a.define_variable(idx, 'arguments', ADef{
			name: -1
		}, false)
	}
}

fn (mut a Analyzer) close(node int) {
	for a.cur >= 0 && a.scopes[a.cur].block == node {
		a.close_scope(a.cur)
		a.cur = a.scopes[a.cur].upper
	}
}

fn (mut a Analyzer) close_scope(s int) {
	left := a.scopes[s].left.clone()
	a.scopes[s].left = []int{}
	a.scopes[s].closed = true
	for r in left {
		if !a.resolve(s, r) {
			upper := a.scopes[s].upper
			if upper >= 0 && !a.scopes[upper].closed {
				a.scopes[upper].left << r
			}
			a.scopes[s].through << r
		}
	}
}

// resolve is staticCloseRef's resolution in the scope `s`.
fn (mut a Analyzer) resolve(s int, r int) bool {
	ref := a.refs[r]
	name := a.name_of(ref.id)
	if s == 0 {
		flags := lib_globals[name] or { return false }
		is_type := flags & 1 != 0
		is_value := flags & 2 != 0
		ok := (ref.type_ && is_type) || (ref.value && is_value)
		if ok {
			a.refs[r].resolved = -2
		}
		return ok
	}
	v := a.lookup(s, name)
	if v < 0 {
		return false
	}
	variable := a.vars[v]
	if a.scopes[s].typ == .function {
		block := a.scopes[s].block
		if a.es.typ(block) != .program {
			body_start := if body := a.es.node(block, .body) { a.es.nodes[body].start } else { -1 }
			ref_start := a.es.nodes[ref.id].start
			if ref_start < body_start && variable.defs.all(it.name >= 0
				&& a.es.nodes[it.name].start >= body_start) {
				return false
			}
		}
	}
	mut is_type := true
	mut is_value := true
	if variable.defs.len > 0 {
		is_type = variable.defs.any(it.is_type)
		is_value = variable.defs.any(it.is_value)
	}
	ok := (ref.type_ && is_type) || (ref.value && is_value)
	if ok {
		a.refs[r].resolved = v
		a.vars[v].references << r
	}
	return ok
}

fn (a &Analyzer) name_of(node int) string {
	if a.es.typ(node) == .literal {
		return a.es.string_of(node, .value) or { '' }
	}
	return a.es.string_of(node, .name) or { '' }
}

// lookup is the variable of that name of the scope (its `set`), or -1. Scopes of template
// expressions hold a few variables: a scan beats a map.
fn (a &Analyzer) lookup(s int, name string) int {
	return a.scopes[s].set[name] or { -1 }
}

fn (mut a Analyzer) define_variable(s int, name string, def ADef, with_def bool) {
	mut v := a.lookup(s, name)
	if v < 0 {
		a.vars << AVar{
			name:  name
			scope: s
		}
		v = a.vars.len - 1
		a.scopes[s].variables << v
		a.scopes[s].set[name] = v
	}
	if with_def {
		a.vars[v].defs << def
	}
}

// define is defineIdentifier in the current scope (or `s`).
fn (mut a Analyzer) define_in(s int, node int, is_type bool, is_value bool) {
	a.define_variable(s, a.name_of(node), ADef{
		name:     node
		is_type:  is_type
		is_value: is_value
	}, true)
}

fn (mut a Analyzer) define(node int, is_type bool, is_value bool) {
	a.define_in(a.cur, node, is_type, is_value)
}

fn (mut a Analyzer) reference(node int, flag u8, type_ bool, value bool) {
	if node < 0 || a.cur < 0 {
		return
	}
	a.refs << ARef{
		id:    node
		flag:  flag
		type_: type_
		value: value
		from:  a.cur
	}
	r := a.refs.len - 1
	if !a.scopes[a.cur].closed {
		a.scopes[a.cur].left << r
	}
}

@[inline]
fn (mut a Analyzer) reference_value(node int, flag u8) {
	a.reference(node, flag, false, true)
}

// ---- Tree access ----

@[inline]
fn (a &Analyzer) typ(n int) estree.NodeType {
	return a.es.typ(n)
}

fn (a &Analyzer) child(n int, key Key) int {
	if n < 0 {
		return -1
	}
	return a.es.node(n, key) or { -1 }
}

fn (a &Analyzer) items(n int, key Key) []int {
	if n < 0 {
		return []int{}
	}
	return a.es.list(n, key) or { []int{} }
}

fn (a &Analyzer) flag(n int, key Key) bool {
	return a.es.flag(n, key) or { false }
}

// visit_children visits the children of a node by its visitor keys, but the excluded key.
fn (mut a Analyzer) visit_children(n int, exclude Key, has_exclude bool) {
	if n < 0 {
		return
	}
	for key in estree.keys_of(a.typ(n)) {
		if has_exclude && key == exclude {
			continue
		}
		p := a.es.prop(n, key) or { continue }
		match p.kind {
			.node {
				a.visit(p.idx)
			}
			.list {
				for item in a.es.lists[p.idx] {
					if item >= 0 {
						a.visit(item)
					}
				}
			}
			else {}
		}
	}
}

fn (mut a Analyzer) visit_all(n int, key Key) {
	for item in a.items(n, key) {
		if item >= 0 {
			a.visit(item)
		}
	}
}

// ---- Referencer ----

fn (mut a Analyzer) visit(n int) {
	if n < 0 {
		return
	}
	match a.typ(n) {
		.arrow_function_expression, .function_declaration, .function_expression,
		.ts_declare_function,
		.ts_empty_body_function_expression {
			a.visit_function(n)
		}
		.assignment_expression {
			a.assignment_expression(n)
		}
		.block_statement {
			a.nest(.block, n)
			a.visit_children(n, .body, false)
			a.close(n)
		}
		.break_statement, .continue_statement, .export_all_declaration, .import_attribute,
		.meta_property, .private_identifier {
		}
		.import_declaration {
			// ImportVisitor: every specifier's local name is an ImportBinding (a type and a value).
			for spec in a.items(n, .specifiers) {
				local := a.child(spec, .local)
				if local >= 0 {
					a.define(local, true, true)
				}
			}
		}
		.call_expression, .new_expression, .ts_instantiation_expression {
			a.visit_children(n, .type_arguments, true)
			a.visit_type(a.child(n, .type_arguments))
		}
		.catch_clause {
			a.nest(.catch_, n)
			param := a.child(n, .param)
			if param >= 0 {
				a.visit_pattern(param, true, fn (mut a Analyzer, pattern int, assignments []int, rest bool) {
					a.define(pattern, false, true)
					a.referencing_default_value(pattern, assignments)
				})
			}
			a.visit(a.child(n, .body))
			a.close(n)
		}
		.class_declaration, .class_expression {
			a.visit_class(n)
		}
		.export_default_declaration {
			a.visit(a.child(n, .declaration))
		}
		.export_named_declaration {
			a.visit(a.child(n, .declaration))
			// ExportVisitor: `export { a }` (without `from`) references the local names.
			if a.child(n, .source) < 0 {
				for spec in a.items(n, .specifiers) {
					local := a.child(spec, .local)
					if local >= 0 && a.typ(local) == .identifier {
						a.reference(local, ref_read, true, true)
					}
				}
			}
		}
		.for_in_statement, .for_of_statement {
			a.visit_for_in(n)
		}
		.for_statement {
			init := a.child(n, .init)
			nested := init >= 0 && a.typ(init) == .variable_declaration
				&& (a.es.string_of(init, .kind) or { '' }) != 'var'
			if nested {
				a.nest(.for_, n)
			}
			a.visit_children(n, .body, false)
			a.close(n)
		}
		.identifier {
			a.reference_value(n, ref_read)
			a.visit_type(a.child(n, .type_annotation))
		}
		.jsx_attribute {
			a.visit(a.child(n, .value))
		}
		.jsx_closing_element {
			a.visit_jsx_element(n)
		}
		.jsx_identifier {
			a.reference_value(n, ref_read)
		}
		.jsx_member_expression {
			object := a.child(n, .object)
			if !(a.typ(object) == .jsx_identifier
				&& (a.es.string_of(object, .name) or { '' }) == 'this') {
				a.visit(object)
			}
		}
		.jsx_opening_element {
			a.visit_jsx_element(n)
			a.visit_type(a.child(n, .type_arguments))
			a.visit_all(n, .attributes)
		}
		.labeled_statement {
			a.visit(a.child(n, .body))
		}
		.member_expression {
			a.visit(a.child(n, .object))
			if a.flag(n, .computed) {
				a.visit(a.child(n, .property))
			}
		}
		.program {
			a.nest(.global, n)
			a.nest(.module, n)
			a.visit_children(n, .body, false)
			a.close(n)
		}
		.property {
			if a.flag(n, .computed) {
				a.visit(a.child(n, .key))
			}
			a.visit(a.child(n, .value))
		}
		.switch_statement {
			a.visit(a.child(n, .discriminant))
			a.nest(.switch_, n)
			a.visit_all(n, .cases)
			a.close(n)
		}
		.tagged_template_expression {
			a.visit(a.child(n, .tag))
			a.visit(a.child(n, .quasi))
			a.visit_type(a.child(n, .type_arguments))
		}
		.ts_as_expression, .ts_satisfies_expression, .ts_type_assertion {
			a.visit(a.child(n, .expression))
			a.visit_type(a.child(n, .type_annotation))
		}
		.ts_enum_declaration {
			a.ts_enum_declaration(n)
		}
		.ts_export_assignment {
			expr := a.child(n, .expression)
			if a.typ(expr) == .identifier {
				a.reference(expr, ref_read, true, true)
			} else {
				a.visit(expr)
			}
		}
		.ts_import_equals_declaration {
			a.define(a.child(n, .id), true, true)
			mut module_ref := a.child(n, .module_reference)
			if a.typ(module_ref) == .ts_qualified_name {
				mut left := a.child(module_ref, .left)
				for a.typ(left) == .ts_qualified_name {
					left = a.child(left, .left)
				}
				a.visit(left)
			} else {
				a.visit(module_ref)
			}
		}
		.ts_interface_declaration, .ts_type_alias_declaration {
			a.visit_type(n)
		}
		.ts_module_declaration {
			id := a.child(n, .id)
			if a.typ(id) == .identifier && (a.es.string_of(n, .kind) or { '' }) != 'global' {
				a.define(id, true, true)
			}
			a.nest(.ts_module, n)
			a.visit(a.child(n, .body))
			a.close(n)
		}
		.update_expression {
			argument := a.visit_expression_target(a.child(n, .argument))
			if is_pattern(a.typ(argument)) {
				a.visit_pattern(argument, false, fn (mut a Analyzer, pattern int, assignments []int, rest bool) {
					a.reference_value(pattern, ref_rw)
				})
			} else {
				a.visit_children(n, .body, false)
			}
		}
		.variable_declaration {
			a.variable_declaration(n)
		}
		.with_statement {
			a.visit(a.child(n, .object))
			a.visit(a.child(n, .body))
		}
		.jsx_fragment {
			a.visit_children(n, .body, false)
		}
		else {
			a.visit_children(n, .body, false)
		}
	}
}

fn is_pattern(t estree.NodeType) bool {
	return t in [.identifier, .object_pattern, .array_pattern, .spread_element, .rest_element,
		.assignment_pattern]
}

fn (mut a Analyzer) visit_expression_target(left_ int) int {
	mut left := left_
	match a.typ(left) {
		.ts_as_expression, .ts_type_assertion {
			a.visit_type(a.child(left, .type_annotation))
			left = a.child(left, .expression)
		}
		.ts_non_null_expression {
			left = a.child(left, .expression)
		}
		else {}
	}
	return left
}

fn (mut a Analyzer) referencing_default_value(pattern int, assignments []int) {
	for _ in assignments {
		a.reference_value(pattern, ref_write)
	}
}

fn (mut a Analyzer) assignment_expression(n int) {
	left := a.visit_expression_target(a.child(n, .left))
	if is_pattern(a.typ(left)) {
		operator := a.es.string_of(n, .operator) or { '=' }
		if operator == '=' {
			a.visit_pattern(left, true, fn (mut a Analyzer, pattern int, assignments []int, rest bool) {
				a.referencing_default_value(pattern, assignments)
				a.reference_value(pattern, ref_write)
			})
		} else if a.typ(left) == .identifier {
			a.reference_value(left, ref_rw)
		}
	} else {
		a.visit(left)
	}
	a.visit(a.child(n, .right))
}

fn (mut a Analyzer) visit_for_in(n int) {
	left := a.child(n, .left)
	is_decl := a.typ(left) == .variable_declaration
	if is_decl && (a.es.string_of(left, .kind) or { '' }) != 'var' {
		a.nest(.for_, n)
	}
	if is_decl {
		a.visit(left)
		decls := a.items(left, .declarations)
		if decls.len > 0 {
			a.visit_pattern(a.child(decls[0], .id), false, fn (mut a Analyzer, pattern int, assignments []int, rest bool) {
				a.reference_value(pattern, ref_write)
			})
		}
	} else {
		a.visit_pattern(left, true, fn (mut a Analyzer, pattern int, assignments []int, rest bool) {
			a.referencing_default_value(pattern, assignments)
			a.reference_value(pattern, ref_write)
		})
	}
	a.visit(a.child(n, .right))
	a.visit(a.child(n, .body))
	a.close(n)
}

fn (mut a Analyzer) visit_function(n int) {
	if a.typ(n) == .function_expression {
		if a.child(n, .id) >= 0 {
			a.nest(.function_expression_name, n)
			a.define(a.child(n, .id), false, true)
		}
	} else if a.child(n, .id) >= 0 {
		a.define(a.child(n, .id), false, true)
	}
	a.nest(.function, n)
	a.visit_params(n)
	a.visit_type(a.child(n, .return_type))
	a.visit_type(a.child(n, .type_parameters))
	body := a.child(n, .body)
	if body >= 0 {
		if a.typ(body) == .block_statement {
			a.visit_children(body, .body, false)
		} else {
			a.visit(body)
		}
	}
	a.close(n)
}

fn (mut a Analyzer) visit_params(n int) {
	for param in a.items(n, .params) {
		if param < 0 {
			continue
		}
		a.visit_pattern(param, true, fn (mut a Analyzer, pattern int, assignments []int, rest bool) {
			a.define(pattern, false, true)
			a.referencing_default_value(pattern, assignments)
		})
		a.visit_param_type_annotation(param)
		a.visit_all(param, .decorators)
	}
}

fn (mut a Analyzer) visit_param_type_annotation(n int) {
	match a.typ(n) {
		.assignment_pattern {
			a.visit_type(a.child(a.child(n, .left), .type_annotation))
		}
		.ts_parameter_property {
			a.visit_param_type_annotation(a.child(n, .parameter))
		}
		else {
			a.visit_type(a.child(n, .type_annotation))
		}
	}
}

fn (mut a Analyzer) visit_jsx_element(n int) {
	name := a.child(n, .name)
	if a.typ(name) == .jsx_identifier {
		s := a.es.string_of(name, .name) or { '' }
		if s.len > 0 && (s[..1].to_upper() == s[..1] || s == 'this') {
			a.visit(name)
		}
	} else {
		a.visit(name)
	}
}

fn (mut a Analyzer) variable_declaration(n int) {
	target := if (a.es.string_of(n, .kind) or { '' }) == 'var' {
		a.scopes[a.cur].var_scope
	} else {
		a.cur
	}
	for decl in a.items(n, .declarations) {
		init := a.child(decl, .init)
		id := a.child(decl, .id)
		has_init := init >= 0
		a.visit_pattern(id, true, fn [target, has_init] (mut a Analyzer, pattern int, assignments []int, rest bool) {
			a.define_in(target, pattern, false, true)
			a.referencing_default_value(pattern, assignments)
			if has_init {
				a.reference_value(pattern, ref_write)
			}
		})
		a.visit(init)
		a.visit_type(a.child(id, .type_annotation))
	}
}

fn (mut a Analyzer) ts_enum_declaration(n int) {
	a.define(a.child(n, .id), true, true)
	a.nest(.ts_enum, n)
	body := a.child(n, .body)
	for member in a.items(body, .members) {
		id := a.child(member, .id)
		if a.typ(id) == .literal && (a.es.prop(id, .value) or { estree.Prop{} }).kind == .string {
			a.define(id, true, true)
		} else if a.typ(id) == .identifier {
			a.define(id, true, true)
		}
		a.visit(a.child(member, .initializer))
	}
	a.close(n)
}

// ---- PatternVisitor ----

type PatternCallback = fn (mut a Analyzer, pattern int, assignments []int, rest bool)

struct PatternState {
mut:
	assignments []int
	rest        []int
	right       []int
}

// visit_pattern is Visitor.visitPattern: calls back for each identifier of the pattern, then
// (with process_right) visits the right-hand nodes it collected.
fn (mut a Analyzer) visit_pattern(node int, process_right bool, callback PatternCallback) {
	mut st := PatternState{}
	a.pattern_visit(node, mut st, callback)
	if process_right {
		for r in st.right {
			a.visit(r)
		}
	}
}

fn (mut a Analyzer) pattern_visit(n int, mut st PatternState, callback PatternCallback) {
	if n < 0 {
		return
	}
	match a.typ(n) {
		.array_expression, .array_pattern {
			for e in a.items(n, .elements) {
				a.pattern_visit(e, mut st, callback)
			}
		}
		.assignment_expression, .assignment_pattern {
			st.assignments << n
			a.pattern_visit(a.child(n, .left), mut st, callback)
			st.right << a.child(n, .right)
			st.assignments.pop()
		}
		.call_expression {
			for arg in a.items(n, .arguments) {
				st.right << arg
			}
			a.pattern_visit(a.child(n, .callee), mut st, callback)
		}
		.decorator, .ts_type_annotation {}
		.identifier {
			rest := st.rest.len > 0 && a.child(st.rest.last(), .argument) == n
			callback(mut a, n, st.assignments, rest)
		}
		.member_expression {
			if a.flag(n, .computed) {
				st.right << a.child(n, .property)
			}
			st.right << a.child(n, .object)
		}
		.property {
			if a.flag(n, .computed) {
				st.right << a.child(n, .key)
			}
			a.pattern_visit(a.child(n, .value), mut st, callback)
		}
		.rest_element {
			st.rest << n
			a.pattern_visit(a.child(n, .argument), mut st, callback)
			st.rest.pop()
		}
		.spread_element {
			a.pattern_visit(a.child(n, .argument), mut st, callback)
		}
		else {
			for key in estree.keys_of(a.typ(n)) {
				p := a.es.prop(n, key) or { continue }
				if p.kind == .node {
					a.pattern_visit(p.idx, mut st, callback)
				} else if p.kind == .list {
					for item in a.es.lists[p.idx] {
						if item >= 0 {
							a.pattern_visit(item, mut st, callback)
						}
					}
				}
			}
		}
	}
}

// ---- TypeVisitor ----

fn (mut a Analyzer) visit_type(n int) {
	if n < 0 {
		return
	}
	a.type_visit(n)
}

fn (mut a Analyzer) type_visit_children(n int, exclude Key, has_exclude bool) {
	for key in estree.keys_of(a.typ(n)) {
		if has_exclude && key == exclude {
			continue
		}
		p := a.es.prop(n, key) or { continue }
		if p.kind == .node {
			a.type_visit(p.idx)
		} else if p.kind == .list {
			for item in a.es.lists[p.idx] {
				if item >= 0 {
					a.type_visit(item)
				}
			}
		}
	}
}

fn (mut a Analyzer) type_visit(n int) {
	if n < 0 {
		return
	}
	match a.typ(n) {
		.identifier {
			a.reference(n, ref_read, true, false)
		}
		.member_expression {
			a.type_visit(a.child(n, .object))
		}
		.ts_call_signature_declaration, .ts_constructor_type, .ts_construct_signature_declaration,
		.ts_function_type {
			a.visit_function_type(n)
		}
		.ts_conditional_type {
			a.nest(.conditional_type, n)
			a.type_visit_children(n, .false_type, true)
			a.close(n)
			a.type_visit(a.child(n, .false_type))
		}
		.ts_import_type {
			a.type_visit(a.child(n, .type_arguments))
		}
		.ts_index_signature {
			for param in a.items(n, .parameters) {
				if a.typ(param) == .identifier {
					a.type_visit(a.child(param, .type_annotation))
				}
			}
			a.type_visit(a.child(n, .type_annotation))
		}
		.ts_infer_type {
			tp := a.child(n, .type_parameter)
			mut scope := a.cur
			if a.scopes[scope].typ in [.function_type, .mapped_type] {
				mut s := a.scopes[scope].upper
				for s >= 0 {
					if a.scopes[s].typ in [.function_type, .mapped_type] {
						s = a.scopes[s].upper
						continue
					}
					if a.scopes[s].typ == .conditional_type {
						scope = s
					}
					break
				}
			}
			a.define_in(scope, a.child(tp, .name), true, false)
			a.type_visit(a.child(tp, .constraint))
		}
		.ts_interface_declaration {
			a.define(a.child(n, .id), true, false)
			tps := a.child(n, .type_parameters)
			if tps >= 0 {
				a.nest(.type_, n)
				a.type_visit(tps)
			}
			for e in a.items(n, .extends_) {
				a.type_visit(e)
			}
			a.type_visit(a.child(n, .body))
			if tps >= 0 {
				a.close(n)
			}
		}
		.ts_mapped_type {
			a.nest(.mapped_type, n)
			a.define(a.child(n, .key), true, false)
			a.type_visit(a.child(n, .constraint))
			a.type_visit(a.child(n, .name_type))
			a.type_visit(a.child(n, .type_annotation))
			a.close(n)
		}
		.ts_method_signature {
			if a.flag(n, .computed) {
				a.visit(a.child(n, .key))
			}
			a.visit_function_type(n)
		}
		.ts_named_tuple_member {
			a.type_visit(a.child(n, .element_type))
		}
		.ts_property_signature {
			if a.flag(n, .computed) {
				a.visit(a.child(n, .key))
			}
			a.type_visit(a.child(n, .type_annotation))
		}
		.ts_qualified_name {
			a.type_visit(a.child(n, .left))
		}
		.ts_type_alias_declaration {
			a.define(a.child(n, .id), true, false)
			tps := a.child(n, .type_parameters)
			if tps >= 0 {
				a.nest(.type_, n)
				a.type_visit(tps)
			}
			a.type_visit(a.child(n, .type_annotation))
			if tps >= 0 {
				a.close(n)
			}
		}
		.ts_type_parameter {
			a.define(a.child(n, .name), true, false)
			a.type_visit(a.child(n, .constraint))
			a.type_visit(a.child(n, .default_))
		}
		.ts_type_predicate {
			pn := a.child(n, .parameter_name)
			if a.typ(pn) != .ts_this_type {
				a.reference_value(pn, ref_read)
			}
			a.type_visit(a.child(n, .type_annotation))
		}
		.ts_type_query {
			expr_name := a.child(n, .expr_name)
			mut entity := expr_name
			if a.typ(expr_name) == .ts_qualified_name {
				mut iter := expr_name
				for a.typ(a.child(iter, .left)) == .ts_qualified_name {
					iter = a.child(iter, .left)
				}
				entity = a.child(iter, .left)
			} else if a.typ(expr_name) == .ts_import_type {
				a.type_visit(expr_name)
			}
			if a.typ(entity) == .identifier {
				a.reference_value(entity, ref_read)
			}
			a.type_visit(a.child(n, .type_arguments))
		}
		else {
			a.type_visit_children(n, .body, false)
		}
	}
}

fn (mut a Analyzer) visit_function_type(n int) {
	a.nest(.function_type, n)
	a.type_visit(a.child(n, .type_parameters))
	for param in a.items(n, .params) {
		saved := a.did_visit_annotation
		a.did_visit_annotation = false
		mut st := PatternState{}
		a.pattern_visit(param, mut st, fn (mut a Analyzer, pattern int, assignments []int, rest bool) {
			// A parameter name is a value variable (`typeof arg`).
			a.define(pattern, false, true)
			ann := a.child(pattern, .type_annotation)
			if ann >= 0 {
				a.type_visit(ann)
				a.did_visit_annotation = true
			}
		})
		// The type annotation of some parameters is the parameter's, not the pattern's.
		if !a.did_visit_annotation {
			a.type_visit(a.child(param, .type_annotation))
		}
		a.did_visit_annotation = saved
	}
	a.type_visit(a.child(n, .return_type))
	a.close(n)
}

// ---- ClassVisitor ----

fn (mut a Analyzer) visit_class(n int) {
	id := a.child(n, .id)
	if a.typ(n) == .class_declaration && id >= 0 {
		a.define(id, true, true)
	}
	a.visit_all(n, .decorators)
	a.nest(.class, n)
	if id >= 0 {
		a.define(id, true, true)
	}
	a.visit(a.child(n, .super_class))
	a.visit_type(a.child(n, .type_parameters))
	a.visit_type(a.child(n, .super_type_arguments))
	for imp in a.items(n, .implements_) {
		a.visit_type(imp)
	}
	a.class_visit(a.child(n, .body))
	a.close(n)
}

fn (mut a Analyzer) class_visit(n int) {
	if n < 0 {
		return
	}
	match a.typ(n) {
		.accessor_property, .property_definition, .ts_abstract_accessor_property,
		.ts_abstract_property_definition {
			a.visit_property_base(n)
			a.visit_type(a.child(n, .type_annotation))
		}
		.class_body {
			for key in estree.keys_of(a.typ(n)) {
				for item in a.items(n, key) {
					if item >= 0 {
						a.class_visit(item)
					}
				}
			}
		}
		.identifier {
			a.visit(n)
		}
		.method_definition {
			if a.flag(n, .computed) {
				a.visit(a.child(n, .key))
			}
			value := a.child(n, .value)
			if a.typ(value) == .function_expression {
				a.visit_method_function(value)
			} else {
				a.visit(value)
			}
			a.visit_all(n, .decorators)
		}
		.private_identifier {}
		.static_block {
			a.nest(.class_static_block, n)
			for b in a.items(n, .body) {
				a.class_visit(b)
			}
			a.close(n)
		}
		.ts_abstract_method_definition {
			a.visit_property_base(n)
		}
		.ts_index_signature {
			a.visit_type(n)
		}
		else {
			a.visit(n)
		}
	}
}

fn (mut a Analyzer) visit_property_base(n int) {
	if a.flag(n, .computed) {
		a.visit(a.child(n, .key))
	}
	value := a.child(n, .value)
	if value >= 0 {
		field := a.typ(n) in [.property_definition, .accessor_property]
		if field {
			a.nest(.class_field_initializer, value)
		}
		a.visit(value)
		if field {
			a.close(value)
		}
	}
	a.visit_all(n, .decorators)
}

fn (mut a Analyzer) visit_method_function(n int) {
	if a.child(n, .id) >= 0 {
		a.nest(.function_expression_name, n)
		a.define(a.child(n, .id), false, true)
	}
	for param in a.items(n, .params) {
		for d in a.items(param, .decorators) {
			a.class_visit(d)
		}
	}
	a.nest(.function, n)
	for param in a.items(n, .params) {
		if param < 0 {
			continue
		}
		a.visit_pattern(param, true, fn (mut a Analyzer, pattern int, assignments []int, rest bool) {
			a.define(pattern, false, true)
			a.referencing_default_value(pattern, assignments)
		})
		a.visit_param_type_annotation(param)
	}
	a.visit_type(a.child(n, .return_type))
	a.visit_type(a.child(n, .type_parameters))
	a.visit_children(a.child(n, .body), .body, false)
	a.close(n)
}
