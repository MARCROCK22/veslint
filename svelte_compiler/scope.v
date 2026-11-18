module svelte_compiler

// phases/scope.js: Scope, Binding and create_scopes (the Evaluation class only feeds code
// generation and is not ported).

// Reference is a reference to a name: the Identifier and the path of nodes above it.
pub struct Reference {
pub:
	node int
	path []int
}

pub struct Assignment {
pub:
	value int
	scope int
}

pub struct Binding {
pub mut:
	scope            int
	node             int
	kind             string
	declaration_kind string
	initial          int = -1
	references       []Reference
	assignments      []Assignment
	// legacy_dependencies: bindings (indexes) a `legacy_reactive` binding depends on.
	legacy_dependencies []int
	prop_alias          string
	has_prop_alias      bool
	// metadata
	has_metadata            bool
	inside_rest             bool
	is_template_declaration bool
	mutated                 bool
	reassigned              bool
}

fn (b &Binding) updated() bool {
	return b.mutated || b.reassigned
}

pub struct Scope {
pub mut:
	parent         int = -1
	porous         bool
	declarations   map[string]int
	declarators    map[int][]int
	references     map[string][]Reference
	function_depth int
}

// Scopes holds every scope and binding of a component (ScopeRoot and the Scope objects).
@[heap]
pub struct Scopes {
pub mut:
	scopes    []Scope
	bindings  []Binding
	conflicts map[string]bool
	counters  map[string]int
	// of: the scope of a node (create_scopes' `scopes` maps, merged: they hold different nodes).
	of map[int]int
}

fn (mut s Scopes) new_scope(parent int, porous bool) int {
	depth := if parent >= 0 {
		s.scopes[parent].function_depth + if porous { 0 } else { 1 }
	} else {
		0
	}
	s.scopes << Scope{
		parent:         parent
		porous:         porous
		function_depth: depth
	}
	return s.scopes.len - 1
}

fn (s &Scopes) get(scope int, name string) int {
	mut sc := scope
	for sc >= 0 {
		if b := s.scopes[sc].declarations[name] {
			return b
		}
		sc = s.scopes[sc].parent
	}
	return -1
}

fn (s &Scopes) owner(scope int, name string) int {
	mut sc := scope
	for sc >= 0 {
		if name in s.scopes[sc].declarations {
			return sc
		}
		sc = s.scopes[sc].parent
	}
	return -1
}

// reference records a reference in the scope and the scopes up to the one declaring the name.
fn (mut s Scopes) reference(scope int, node int, path []int, t &Tree) {
	name := t.name(node)
	mut sc := scope
	for {
		r := Reference{
			node: node
			path: path.clone()
		}
		if name !in s.scopes[sc].references {
			s.scopes[sc].references[name] = []Reference{}
		}
		s.scopes[sc].references[name] << r
		if b := s.scopes[sc].declarations[name] {
			s.bindings[b].references << r
			return
		}
		if s.scopes[sc].parent >= 0 {
			sc = s.scopes[sc].parent
		} else {
			s.conflicts[name] = true
			return
		}
	}
}

// generate is Scope.generate (the names matter only for conflicts with later names).
fn (mut s Scopes) generate(scope int, preferred string) string {
	mut sc := scope
	for s.scopes[sc].porous {
		sc = s.scopes[sc].parent
	}
	mut pref := []u8{}
	for k, c in preferred.bytes() {
		if (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`) || c == `_`
			|| c == `$` {
			pref << if k == 0 && c >= `0` && c <= `9` { `_` } else { c }
		} else {
			pref << `_`
		}
	}
	p := pref.bytestr()
	mut n := s.counters[p] or { 0 }
	mut name := ''
	if n == 0 {
		name = p
		n = 1
	} else {
		name = '${p}_${n}'
		n++
	}
	for {
		if name !in s.scopes[sc].references && name !in s.scopes[sc].declarations
			&& name !in s.conflicts && !is_reserved(name) {
			break
		}
		name = '${p}_${n}'
		n++
	}
	s.counters[p] = n
	s.scopes[sc].references[name] = []Reference{}
	s.conflicts[name] = true
	return name
}

// ---------------------------------------------------------------------------------------------

// ScopeBuilder is create_scopes' walk.
struct ScopeBuilder {
mut:
	t                              &Tree
	s                              &Scopes
	allow_reactive_declarations    bool
	path                           []int
	references                     []ScopedRef
	updates                        []Update
	possible_implicit_declarations []int
	has_await                      bool
	err                            ?IError
	// component metadata filled here (Component.metadata.scopes, EachBlock declarations).
	component_scopes map[int]map[string]int
}

struct ScopedRef {
	scope int
	node  int
	path  []int
}

struct Update {
	scope int
	node  int
	value int
}

pub struct ScopesResult {
pub:
	scope     int
	has_await bool
}

// declare is Scope.declare.
fn (mut z Analyzer) declare(scope int, node int, kind string, declaration_kind string, initial int) !int {
	mut s := z.s
	if s.scopes[scope].parent >= 0 {
		if declaration_kind == 'var' && s.scopes[scope].porous {
			return z.declare(s.scopes[scope].parent, node, kind, declaration_kind, -1)!
		}
		if declaration_kind == 'import' {
			return z.declare(s.scopes[scope].parent, node, kind, declaration_kind, initial)!
		}
	}
	name := z.t.name(node)
	if existing := s.scopes[scope].declarations[name] {
		if s.bindings[existing].declaration_kind != 'var' && declaration_kind != 'var' {
			return z.error_at(node, e_declaration_duplicate(name))
		}
	}
	mut b := Binding{
		scope:            scope
		node:             node
		kind:             kind
		declaration_kind: declaration_kind
		initial:          initial
	}
	if initial >= 0 {
		b.assignments << Assignment{
			value: initial
			scope: scope
		}
	}
	s.bindings << b
	id := s.bindings.len - 1
	z.validate_identifier_name(id, s.scopes[scope].function_depth)!
	s.scopes[scope].declarations[name] = id
	s.conflicts[name] = true
	return id
}

// create_scopes walks `ast` and returns its scope (a child of `parent`).
fn (mut z Analyzer) create_scopes(ast int, allow_reactive bool, parent int) !ScopesResult {
	scope := z.s.new_scope(parent, false)
	z.s.of[ast] = scope
	mut w := ScopeWalk{
		allow_reactive: allow_reactive
	}
	z.sw = &w
	z.scope_visit(ast, scope)!
	for id in w.possible_implicit_declarations {
		if z.s.get(scope, z.t.name(id)) >= 0 {
			continue
		}
		z.declare(scope, id, 'legacy_reactive', 'let', -1)!
	}
	for r in w.references {
		z.s.reference(r.scope, r.node, r.path, z.t)
	}
	for u in w.updates {
		for expression in z.t.unwrap(u.node) {
			left := z.t.object(expression)
			if left < 0 {
				continue
			}
			binding := z.s.get(u.scope, z.t.name(left))
			if binding >= 0 && left != z.s.bindings[binding].node {
				if left == expression {
					z.s.bindings[binding].reassigned = true
					z.s.bindings[binding].assignments << Assignment{
						value: u.value
						scope: u.scope
					}
				} else {
					z.s.bindings[binding].mutated = true
				}
			}
		}
	}
	return ScopesResult{
		scope:     scope
		has_await: w.has_await
	}
}

@[heap]
struct ScopeWalk {
mut:
	allow_reactive                 bool
	path                           []int
	references                     []ScopedRef
	updates                        []Update
	possible_implicit_declarations []int
	has_await                      bool
}

fn (mut z Analyzer) scope_next(node int, scope int) ! {
	z.sw.path << node
	for ch in z.t.children(node) {
		z.scope_visit(ch, scope)!
	}
	z.sw.path.pop()
}

// scope_child visits `child` of `node` (context.visit): `node` is on the path meanwhile.
fn (mut z Analyzer) scope_child(node int, child int, scope int) ! {
	if child < 0 {
		return
	}
	z.sw.path << node
	z.scope_visit(child, scope)!
	z.sw.path.pop()
}

fn (mut z Analyzer) add_params(scope int, params []int) ! {
	for param in params {
		for id in z.t.extract_identifiers(param) {
			z.declare(scope, id, 'normal', if z.t.typ(param) == 'RestElement' {
				'rest_param'
			} else {
				'param'
			}, -1)!
		}
	}
}

fn (mut z Analyzer) scope_visit(node int, scope int) ! {
	t := z.t
	typ := t.typ(node)
	match typ {
		'AwaitExpression' {
			mut tla := true
			for p in z.sw.path {
				if t.typ(p) in ['ArrowFunctionExpression', 'FunctionExpression', 'FunctionDeclaration'] {
					tla = false
					break
				}
			}
			z.sw.has_await = z.sw.has_await || tla
			z.scope_next(node, scope)!
		}
		'Identifier' {
			if z.sw.path.len > 0 {
				parent := z.sw.path.last()
				if t.is_reference(node, parent) && !t.typ(parent).starts_with('TS') {
					z.sw.references << ScopedRef{
						scope: scope
						node:  node
						path:  z.sw.path.clone()
					}
				}
			}
		}
		'LabeledStatement' {
			if z.sw.path.len > 1 || !z.sw.allow_reactive || t.name(t.get(node, .label)) != '$' {
				z.scope_next(node, scope)!
				return
			}
			child := z.s.new_scope(scope, false)
			z.s.of[node] = child
			body := t.get(node, .body)
			if t.typ(body) == 'ExpressionStatement'
				&& t.typ(t.get(body, .expression)) == 'AssignmentExpression' {
				for id in t.extract_identifiers(t.get(t.get(body, .expression), .left)) {
					if !t.name(id).starts_with('$') {
						z.sw.possible_implicit_declarations << id
					}
				}
			}
			z.scope_next(node, child)!
		}
		'SvelteFragment', 'SlotElement', 'SvelteElement', 'RegularElement' {
			child := z.s.new_scope(scope, false)
			z.s.of[node] = child
			z.scope_next(node, child)!
		}
		'LetDirective' {
			mut bindings := []int{}
			expr := t.get(node, .expression)
			parent := z.sw.path.last()
			if expr >= 0 {
				mut ids := []int{}
				t.extract_identifiers_from_destructuring(expr, mut ids)
				for id in ids {
					b := z.declare(scope, id, 'template', 'const', -1)!
					z.s.reference(scope, id, [parent, node], t)
					bindings << b
				}
			} else {
				id := z.t.new_node('Identifier', t.nodes[node].start, t.nodes[node].end)
				z.t.set_str(id, .name, t.name(node))
				b := z.declare(scope, id, 'template', 'const', -1)!
				z.s.reference(scope, id, [parent, node], z.t)
				bindings << b
			}
			z.s.scopes[scope].declarators[node] = bindings
		}
		'Component', 'SvelteSelf', 'SvelteComponent' {
			if typ == 'Component' {
				name := t.name(node).all_before('.')
				z.s.reference(scope, z.t.id(name), z.sw.path, z.t)
			}
			z.scope_component(node, scope)!
		}
		'AssignmentExpression' {
			z.sw.updates << Update{
				scope: scope
				node:  t.get(node, .left)
				value: t.get(node, .right)
			}
			z.scope_next(node, scope)!
		}
		'UpdateExpression' {
			arg := t.get(node, .argument)
			z.sw.updates << Update{
				scope: scope
				node:  arg
				value: arg
			}
			z.scope_next(node, scope)!
		}
		'ImportDeclaration' {
			for spec in t.list(node, .specifiers) {
				z.declare(scope, t.get(spec, .local), 'normal', 'import', node)!
			}
		}
		'FunctionExpression' {
			child := z.s.new_scope(scope, true)
			z.s.of[node] = child
			id := t.get(node, .id)
			if id >= 0 {
				z.declare(child, id, 'normal', 'function', -1)!
			}
			z.add_params(child, t.list(node, .params))!
			z.scope_next(node, child)!
		}
		'FunctionDeclaration' {
			id := t.get(node, .id)
			if id >= 0 {
				z.declare(scope, id, 'normal', 'function', node)!
			}
			child := z.s.new_scope(scope, true)
			z.s.of[node] = child
			z.add_params(child, t.list(node, .params))!
			z.scope_next(node, child)!
		}
		'ArrowFunctionExpression' {
			child := z.s.new_scope(scope, true)
			z.s.of[node] = child
			z.add_params(child, t.list(node, .params))!
			z.scope_next(node, child)!
		}
		'ForStatement', 'ForInStatement', 'ForOfStatement', 'SwitchStatement' {
			child := z.s.new_scope(scope, true)
			z.s.of[node] = child
			z.scope_next(node, child)!
		}
		'BlockStatement' {
			parent := if z.sw.path.len > 0 { z.sw.path.last() } else { -1 }
			porous := t.typ(parent) !in ['FunctionDeclaration', 'FunctionExpression',
				'ArrowFunctionExpression']
			child := z.s.new_scope(scope, porous)
			z.s.of[node] = child
			z.scope_next(node, child)!
		}
		'ClassDeclaration' {
			id := t.get(node, .id)
			if id >= 0 {
				z.declare(scope, id, 'normal', 'let', node)!
			}
			z.scope_next(node, scope)!
		}
		'VariableDeclaration' {
			is_const_tag := z.sw.path.len > 0 && t.typ(z.sw.path.last()) == 'ConstTag'
			kind := t.text(node, .kind)
			for declarator in t.list(node, .declarations) {
				mut bindings := []int{}
				for id in t.extract_identifiers(t.get(declarator, .id)) {
					b := z.declare(scope, id, if is_const_tag { 'template' } else { 'normal' },
						kind, t.get(declarator, .init))!
					z.s.bindings[b].has_metadata = true
					z.s.bindings[b].is_template_declaration = true
					bindings << b
				}
				z.s.scopes[scope].declarators[declarator] = bindings
			}
			z.scope_next(node, scope)!
		}
		'CatchClause' {
			param := t.get(node, .param)
			if param >= 0 {
				child := z.s.new_scope(scope, true)
				z.s.of[node] = child
				for id in t.extract_identifiers(param) {
					z.declare(child, id, 'normal', 'let', -1)!
				}
				z.scope_next(node, child)!
			} else {
				z.scope_next(node, scope)!
			}
		}
		'EachBlock' {
			z.scope_child(node, t.get(node, .expression), scope)!
			child := z.s.new_scope(scope, false)
			z.s.of[node] = child
			context := t.get(node, .context)
			if context >= 0 {
				mut ids := []int{}
				mut rest := []bool{}
				t.extract_paths(context, mut ids, mut rest)
				for id in t.extract_identifiers(context) {
					b := z.declare(child, id, 'each', 'const', -1)!
					z.s.bindings[b].has_metadata = true
					z.s.bindings[b].inside_rest = z.inside_rest(context, id)
				}
				z.scope_child(node, context, child)!
			}
			if t.has(node, .index) {
				index := t.text(node, .index)
				key := t.get(node, .key)
				is_keyed := key >= 0 && (t.typ(key) != 'Identifier' || t.name(key) != index)
				z.declare(child, z.t.id(index), if is_keyed { 'template' } else { 'static' },
					'const', node)!
			}
			key := t.get(node, .key)
			if key >= 0 {
				z.scope_child(node, key, child)!
			}
			body := t.get(node, .body)
			for ch in t.list(body, .nodes) {
				z.scope_child(node, ch, child)!
			}
			fallback := t.get(node, .fallback)
			if fallback >= 0 {
				z.scope_child(node, fallback, child)!
			}
		}
		'AwaitBlock' {
			z.scope_child(node, t.get(node, .expression), scope)!
			pending := t.get(node, .pending)
			if pending >= 0 {
				z.scope_child(node, pending, scope)!
			}
			then := t.get(node, .then)
			if then >= 0 {
				z.scope_child(node, then, scope)!
				value := t.get(node, .value)
				if value >= 0 {
					then_scope := z.s.of[then]
					value_scope := z.s.new_scope(scope, false)
					z.s.of[value] = value_scope
					z.scope_child(node, value, value_scope)!
					for id in t.extract_identifiers(value) {
						z.declare(then_scope, id, 'template', 'const', -1)!
						z.declare(value_scope, id, 'normal', 'const', -1)!
					}
				}
			}
			catch_ := t.get(node, .catch_)
			if catch_ >= 0 {
				z.scope_child(node, catch_, scope)!
				error := t.get(node, .error)
				if error >= 0 {
					catch_scope := z.s.of[catch_]
					error_scope := z.s.new_scope(scope, false)
					z.s.of[error] = error_scope
					z.scope_child(node, error, error_scope)!
					for id in t.extract_identifiers(error) {
						z.declare(catch_scope, id, 'template', 'const', -1)!
						z.declare(error_scope, id, 'normal', 'const', -1)!
					}
				}
			}
		}
		'SnippetBlock' {
			z.declare(scope, t.get(node, .expression), 'normal', 'function', node)!
			child := z.s.new_scope(scope, false)
			z.s.of[node] = child
			for param in t.list(node, .parameters) {
				for id in t.extract_identifiers(param) {
					z.declare(child, id, 'snippet', 'let', -1)!
				}
			}
			z.scope_next(node, child)!
		}
		'Fragment' {
			child := z.s.new_scope(scope, t.flag(node, .transparent))
			z.s.of[node] = child
			z.scope_next(node, child)!
		}
		'BindDirective' {
			expr := t.get(node, .expression)
			if t.typ(expr) != 'SequenceExpression' {
				z.sw.updates << Update{
					scope: scope
					node:  expr
					value: expr
				}
			}
			z.scope_next(node, scope)!
		}
		'TransitionDirective', 'AnimateDirective', 'UseDirective' {
			z.s.reference(scope, z.t.id(t.name(node).all_before('.')), z.sw.path, z.t)
			expr := t.get(node, .expression)
			if expr >= 0 {
				z.scope_child(node, expr, scope)!
			}
		}
		'StyleDirective' {
			if t.attr_is_true(node) {
				mut path := z.sw.path.clone()
				path << node
				z.s.reference(scope, z.t.id(t.name(node)), path, z.t)
			}
			z.scope_next(node, scope)!
		}
		else {
			z.scope_next(node, scope)!
		}
	}
}

// inside_rest tells whether `id` is under a RestElement of the pattern.
fn (z &Analyzer) inside_rest(pattern int, id int) bool {
	return z.find_under_rest(pattern, id, false)
}

fn (z &Analyzer) find_under_rest(n int, id int, inside bool) bool {
	if n == id {
		return inside
	}
	in_rest := inside || z.t.typ(n) == 'RestElement'
	for ch in z.t.children(n) {
		if z.find_under_rest(ch, id, in_rest) {
			return true
		}
	}
	return false
}

// determine_slot (utils/slot.js): the static `slot` attribute of an element-like node.
fn (t &Tree) determine_slot(node int) ?string {
	if t.typ(node) !in ['SvelteElement', 'RegularElement', 'SvelteFragment', 'Component',
		'SvelteComponent', 'SvelteSelf', 'SlotElement'] {
		return none
	}
	for a in t.list(node, .attributes) {
		if t.typ(a) != 'Attribute' || t.name(a) != 'slot' || !t.is_text_attribute(a) {
			continue
		}
		return t.text_value(a)
	}
	return none
}

// scope_component is create_scopes' Component visitor.
fn (mut z Analyzer) scope_component(node int, scope int) ! {
	t := z.t
	default_scope := z.s.new_scope(scope, false)
	mut slot_scopes := map[string]int{}
	slot_scopes['default'] = default_scope
	if t.typ(node) == 'SvelteComponent' {
		z.scope_child(node, t.get(node, .expression), scope)!
	}
	is_slot := (t.determine_slot(node) or { '' }) != '' || t.determine_slot(node) != none
	default_state := if is_slot { scope } else { default_scope }
	for a in t.list(node, .attributes) {
		if t.typ(a) == 'LetDirective' {
			z.scope_child(node, a, default_state)!
		} else {
			z.scope_child(node, a, scope)!
		}
	}
	for ch in t.list(t.get(node, .fragment), .nodes) {
		mut st := default_state
		if slot_name := t.determine_slot(ch) {
			sc := z.s.new_scope(scope, false)
			slot_scopes[slot_name] = sc
			st = sc
		}
		z.scope_child(node, ch, st)!
	}
	z.component_scopes[node] = slot_scopes.clone()
}
