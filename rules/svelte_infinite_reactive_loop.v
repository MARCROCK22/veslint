module rules

import estree

// Port of the `svelte/infinite-reactive-loop` rule of eslint-plugin-svelte 3.24.1: in a `$:`
// statement (and the functions it calls, followed through their declarations), an assignment to
// a top-level variable the statement reads, made in another microtask than the statement's
// (after an `await`, in a `.then`/`.catch` callback, inside `tick()` of `svelte` or
// `setTimeout`/`setInterval`/`queueMicrotask`), is reported, and so is each call on the way to
// it. Its conditions leave runes mode out. It runs on the lint code (ReferenceTracker, scopes).

const svirl_messages = {
	'unexpected':     'Possibly it may occur an infinite reactive loop.'
	'unexpectedCall': 'Possibly it may occur an infinite reactive loop because this function may update `{{variableName}}`.'
}

struct SvirlContext {
	t         &estree.EsTree = unsafe { nil }
	calls     []int        // the calls of tick and of the task functions
	reactive  map[int]bool // getReactiveVariableReferences (identifiers)
	tracked   []string     // the names of those in the statement
	statement int
mut:
	processed map[int]bool
	findings  []Finding
}

// svirl_is_function_call is isFunctionCall: an identifier whose parent is a call of a callee with
// its name.
fn svirl_is_function_call(t &estree.EsTree, node int) bool {
	if t.typ(node) != .identifier {
		return false
	}
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .call_expression {
		return false
	}
	callee := t.node(parent, .callee) or { return false }
	return t.typ(callee) == .identifier && t.string_of(callee, .name) or { '' } == t.string_of(node,
		.name) or { '' }
}

// svirl_is_child is isChildNode: `ancestor` is a strict ancestor of `node`.
fn svirl_is_child(t &estree.EsTree, ancestor int, node int) bool {
	mut parent := t.nodes[node].parent
	for parent >= 0 {
		if parent == ancestor {
			return true
		}
		parent = t.nodes[parent].parent
	}
	return false
}

// svirl_declaration_body is getDeclarationBody without a function name.
fn svirl_declaration_body(t &estree.EsTree, node int) int {
	match t.typ(node) {
		.variable_declarator {
			id := t.node(node, .id) or { return -1 }
			init := t.node(node, .init) or { return -1 }
			if t.typ(id) == .identifier
				&& t.typ(init) in [.arrow_function_expression, .function_expression] {
				return t.node(init, .body) or { -1 }
			}
		}
		.function_declaration {
			id := t.node(node, .id) or { return -1 }
			if t.typ(id) == .identifier {
				return t.node(node, .body) or { -1 }
			}
		}
		.arrow_function_expression {
			return t.node(node, .body) or { -1 }
		}
		else {}
	}
	return -1
}

// svirl_is_then_or_catch_body is isPromiseThenOrCatchBody.
fn svirl_is_then_or_catch_body(t &estree.EsTree, node int) bool {
	if svirl_declaration_body(t, node) < 0 {
		return false
	}
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .call_expression {
		return false
	}
	callee := t.node(parent, .callee) or { return false }
	if t.typ(callee) != .member_expression {
		return false
	}
	property := t.node(callee, .property) or { return false }
	return t.typ(property) == .identifier
		&& (t.string_of(property, .name) or { '' }) in ['then', 'catch']
}

// svirl_is_node_for_assign is isNodeForAssign.
fn svirl_is_node_for_assign(t &estree.EsTree, node int) bool {
	name := t.string_of(node, .name) or { '' }
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	if t.typ(parent) == .assignment_expression {
		left := t.node(parent, .left) or { return false }
		return t.typ(left) == .identifier && (t.string_of(left, .name) or { '' }) == name
	}
	if t.typ(parent) != .member_expression {
		return false
	}
	assignment := t.nodes[parent].parent
	if assignment < 0 || t.typ(assignment) != .assignment_expression {
		return false
	}
	left := t.node(assignment, .left) or { return false }
	if t.typ(left) != .member_expression {
		return false
	}
	object := t.node(left, .object) or { return false }
	return t.typ(object) == .identifier && (t.string_of(object, .name) or { '' }) == name
}

// svirl_is_inside_of_function is isInsideOfFunction.
fn svirl_is_inside_of_function(t &estree.EsTree, node int) bool {
	mut parent := t.nodes[node].parent
	for parent >= 0 {
		if t.typ(parent) == .function_declaration && (t.flag(parent, .async) or { false }) {
			return true
		}
		if t.typ(parent) == .variable_declarator {
			if init := t.node(parent, .init) {
				if t.typ(init) in [.function_expression, .arrow_function_expression]
					&& (t.flag(init, .async) or { false }) {
					return true
				}
			}
		}
		parent = t.nodes[parent].parent
	}
	return false
}

// svirl_function_body is getFunctionDeclarationNode: the body of the function a called identifier
// names (a function declaration, or a variable initialized with a function), -1 for none.
fn (mut c Checker) svirl_function_body(root C.TSNode, t &estree.EsTree, identifier int) int {
	ts := t.ts_node(identifier) or { return -1 }
	tree := c.scope_tree(root)
	name := t.string_of(identifier, .name) or { return -1 }
	scope := tree.get_scope(ts)
	mut v := tree.find_variable(scope, name, t.nodes[identifier].start)
	if v < 0 && name.starts_with('\$') {
		v = tree.find_variable(scope, name[1..], t.nodes[identifier].start)
	}
	if v < 0 {
		return -1
	}
	for def in tree.variables[v].defs {
		if def.kind == .function_name {
			node := c.es_index_of(t, def.node) or { continue }
			if t.typ(node) == .function_declaration {
				return t.node(node, .body) or { -1 }
			}
		}
		if def.kind == .variable {
			declarator := c.es_index_of(t, def.node) or { continue }
			if t.typ(declarator) != .variable_declarator {
				continue
			}
			init := t.node(declarator, .init) or { continue }
			if t.typ(init) in [.function_expression, .arrow_function_expression] {
				return t.node(init, .body) or { -1 }
			}
		}
	}
	return -1
}

// svirl_verify is verifyInternal.
fn (mut c Checker) svirl_verify(root C.TSNode, mut ctx SvirlContext, ast int, call_identifiers []int, same_task bool) {
	if ctx.processed[ast] {
		return
	}
	ctx.processed[ast] = true
	t := ctx.t
	mut is_same := same_task
	mut different := map[int]bool{}
	// traverseNodes: enter and leave each node of the subtree, `ast` included.
	mut stack := [ast]
	for stack.len > 0 {
		top := stack.pop()
		if top < -1 {
			node := -2 - top
			if t.typ(node) == .await_expression {
				if t.nodes[ast].parent == ctx.statement {
					if !svirl_is_inside_of_function(t, node) {
						is_same = false
					}
				} else {
					is_same = false
				}
			}
			if different[node] {
				is_same = true
			}
			continue
		}
		node := top
		if svirl_is_then_or_catch_body(t, node) {
			different[node] = true
			is_same = false
		}
		for call in ctx.calls {
			if svirl_is_child(t, call, node) {
				different[node] = true
				is_same = false
			}
		}
		parent := t.nodes[node].parent
		if parent >= 0 && t.typ(parent) == .assignment_expression
			&& (t.node(parent, .left) or { -1 }) == node {
			right := t.node(parent, .right) or { -1 }
			if right >= 0 && t.typ(right) == .await_expression {
				different[node] = true
				is_same = false
			}
		}
		if t.typ(node) == .identifier && svirl_is_function_call(t, node) {
			body := c.svirl_function_body(root, t, node)
			if body >= 0 {
				mut next := call_identifiers.clone()
				next << node
				c.svirl_verify(root, mut ctx, body, next, is_same)
			}
		}
		if !is_same && t.typ(node) == .identifier && ctx.reactive[node] {
			name := t.string_of(node, .name) or { '' }
			if name in ctx.tracked && svirl_is_node_for_assign(t, node) {
				ctx.findings << Finding{
					stmt:       c.es_tree_position(t, node)
					message_id: 'unexpected'
				}
				for call_identifier in call_identifiers {
					ctx.findings << Finding{
						stmt:       c.es_tree_position(t, call_identifier)
						message_id: 'unexpectedCall'
						data:       {
							'variableName': name
						}
					}
				}
			}
		}
		stack << -2 - node
		kids := t.children(node)
		for k := kids.len - 1; k >= 0; k-- {
			stack << kids[k]
		}
	}
}

fn (mut c Checker) lint_svelte_infinite_reactive_loop(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.svsc_runes_off(abs_path) || c.svelte.doc.reactive.len == 0 {
		return []
	}
	t := c.es_tree(root, abs_path) or { return [] }
	tree := c.scope_tree(root)
	mut calls := []int{}
	for traced in c.es_esm_references(root, {
		'svelte': EsTrace{
			esm:      true
			children: {
				'tick': EsTrace{
					call: true
				}
			}
		}
	}) {
		calls << c.es_index_of(t, traced.node) or { continue }
	}
	for traced in c.es_global_references(root, {
		'setTimeout':     EsTrace{
			call: true
		}
		'setInterval':    EsTrace{
			call: true
		}
		'queueMicrotask': EsTrace{
			call: true
		}
	}) {
		calls << c.es_index_of(t, traced.node) or { continue }
	}
	// The variables of the module scope (the global one in a script).
	toplevel := if tree.scopes.len > 1 && tree.scopes[1].kind == .esmodule { 1 } else { 0 }
	mut reactive := map[int]bool{}
	for v in tree.scopes[toplevel].variables {
		for r in tree.variables[v].references {
			id := c.es_index_of(t, tree.references[r].identifier) or { continue }
			if t.typ(id) == .identifier && !svirl_is_function_call(t, id) {
				reactive[id] = true
			}
		}
	}
	mut findings := []Finding{}
	for statement in t.list(t.root, .body) or { []int{} } {
		ts := t.ts_node(statement) or { continue }
		if !c.is_svelte_reactive_statement(ts) {
			continue
		}
		start := t.nodes[statement].start
		end := t.nodes[statement].end
		mut tracked := []string{}
		for id, _ in reactive {
			if start <= t.nodes[id].start && t.nodes[id].end <= end {
				tracked << t.string_of(id, .name) or { '' }
			}
		}
		body := t.node(statement, .body) or { continue }
		mut ctx := SvirlContext{
			t:         t
			calls:     calls
			reactive:  reactive
			tracked:   tracked
			statement: statement
		}
		c.svirl_verify(root, mut ctx, body, []int{}, true)
		findings << ctx.findings
	}
	return c.svsc_moved(findings)
}
