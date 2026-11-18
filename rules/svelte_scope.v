module rules

import svelte
import treesitter { named_children, node_field, node_kind, node_parent, node_start }

// What svelte-eslint-parser adds to the scopes of a .svelte file (src/parser/analyze-scope.ts and
// addGlobalVariables of src/parser/index.ts), before ESLint adds the globals of the configuration,
// on the scope tree of the lint code (whose template statements are at the module level, as the
// render function is merged into the module scope upstream):
//   - a `$x` reference whose `x` is a module variable reads `x` (stores; twice, around the next);
//   - `$: x = …` at the top level defines `x` in the module scope (a ComputedVariable);
//   - the name of a snippet given to a component is dropped, or used when referenced;
//   - the Svelte globals ($$slots, $$props, $$restProps, and the runes unless runes are off)
//     are variables of the global scope;
//   - each prop (`export let x`, `let { x = $bindable() } = $props()`) gets a virtual reference
//     that writes and reads it.

const svelte_rune_globals = ['\$state', '\$derived', '\$effect', '\$props', '\$bindable', '\$inspect',
	'\$host']

// SvelteScopeSetup is what the scope tree needs of the document.
pub struct SvelteScopeSetup {
pub:
	on        bool
	runes_off bool
	// scripts are the <script> elements (offsets of the lint code, which are the file's there).
	scripts []svelte.ScriptRange
	// snippet_names are the lint code offsets of the names of the snippets given to components.
	snippet_names []int
}

fn (c &Checker) svelte_scope_setup() SvelteScopeSetup {
	doc := c.svelte.doc
	return SvelteScopeSetup{
		on:            true
		runes_off:     doc.runes == .off
		scripts:       doc.script_ranges()
		snippet_names: doc.component_snippet_names().map(c.svelte_file_to_lint(it, false)).filter(it >= 0)
	}
}

// svelte_scope runs the edits, in svelte-eslint-parser's order.
fn (mut b ScopeBuilder) svelte_scope(setup SvelteScopeSetup) {
	mut globals := ['\$\$slots', '\$\$props', '\$\$restProps']
	if !setup.runes_off {
		globals << svelte_rune_globals
	}
	module := b.svelte_module_scope()
	if module >= 0 {
		b.svelte_store_scope(module, globals)
		b.svelte_reactive_scope(module)
		b.svelte_store_scope(module, globals)
	}
	b.svelte_snippets_scope(setup.snippet_names)
	b.svelte_add_globals(globals)
	if module >= 0 {
		for script in setup.scripts {
			if !script.context_module {
				b.svelte_props_scope(module, script, setup.runes_off)
			}
		}
	}
}

fn (b &ScopeBuilder) svelte_module_scope() int {
	if b.tree.scopes.len == 0 {
		return -1
	}
	for child in b.tree.scopes[0].children {
		if b.tree.scopes[child].kind == .esmodule {
			return child
		}
	}
	return -1
}

// svelte_add_reference_sorted is addReference: into a variable's references, by the position of
// the identifier.
fn (mut b ScopeBuilder) svelte_add_reference_sorted(v int, r int) {
	start := node_start(b.tree.references[r].identifier)
	mut refs := b.tree.variables[v].references.clone()
	mut at := refs.len
	for k, x in refs {
		if node_start(b.tree.references[x].identifier) > start {
			at = k
			break
		}
	}
	refs.insert(at, r)
	b.tree.variables[v].references = refs
}

// svelte_remove_through is removeReferenceFromThrough: the reference leaves the through lists of
// its scope and of those above; the other references of the same name there resolve to the same
// variable.
fn (mut b ScopeBuilder) svelte_remove_through(r int, from int) {
	name := b.tree.references[r].name
	v := b.tree.references[r].resolved
	mut s := from
	for s >= 0 {
		mut kept := []int{}
		for x in b.tree.scopes[s].through {
			if x == r {
				continue
			}
			if b.tree.references[x].name == name {
				b.tree.references[x].resolved = v
				if v >= 0 && x !in b.tree.variables[v].references {
					b.svelte_add_reference_sorted(v, x)
				}
				continue
			}
			kept << x
		}
		b.tree.scopes[s].through = kept
		s = b.tree.scopes[s].upper
	}
	b.tree.through = b.tree.scopes[0].through.clone()
}

// svelte_store_scope is analyzeStoreScope.
fn (mut b ScopeBuilder) svelte_store_scope(module int, globals []string) {
	mut write_only := []int{}
	for r in b.tree.scopes[0].through.clone() {
		ref := b.tree.references[r]
		if !ref.name.starts_with('\$') || ref.name in globals {
			continue
		}
		v := b.tree.scopes[module].set[ref.name[1..]] or { continue }
		if ref.write && !ref.read {
			write_only << r
		}
		// It does not write the store variable: it reads it.
		b.tree.references[r] = ScopeReference{
			...ref
			read:     true
			write:    false
			init:     false
			resolved: v
		}
		b.svelte_add_reference_sorted(v, r)
		b.svelte_remove_through(r, module)
	}
	mut done := map[int]bool{}
	for r in write_only {
		v := b.tree.references[r].resolved
		if v < 0 || v in done {
			continue
		}
		done[v] = true
		variable := b.tree.variables[v]
		first := if variable.identifiers.len > 0 {
			node_key(variable.identifiers[0])
		} else {
			u64(0)
		}
		if variable.references.any(it !in write_only
			&& node_key(b.tree.references[it].identifier) != first) {
			continue
		}
		if variable.identifiers.len == 0 {
			continue
		}
		// A virtual reference that reads it.
		b.tree.references << ScopeReference{
			identifier: variable.identifiers[0]
			name:       variable.name
			from:       module
			read:       true
			value_ref:  true
			virtual:    true
			resolved:   v
		}
		b.svelte_add_reference_sorted(v, b.tree.references.len - 1)
	}
}

// svelte_reactive_scope is analyzeReactiveScope.
fn (mut b ScopeBuilder) svelte_reactive_scope(module int) {
	for r in b.tree.scopes[0].through.clone() {
		ref := b.tree.references[r]
		if ref.from != module || !ref.write {
			continue
		}
		assign := svelte_assignment_of_target(ref.identifier) or { continue }
		mut statement := node_parent(assign) or { continue }
		for node_kind(statement) == 'parenthesized_expression' {
			statement = node_parent(statement) or { break }
		}
		if node_kind(statement) != 'expression_statement' {
			continue
		}
		label := node_parent(statement) or { continue }
		if !b.svelte_is_reactive_statement(label) {
			continue
		}
		mut v := b.tree.scopes[module].set[ref.name] or { -1 }
		if v < 0 {
			v = b.tree.variables.len
			b.tree.variables << ScopeVariable{
				name:  ref.name
				scope: module
				defs:  [
					ScopeDefinition{
						kind:        .svelte_computed
						name:        ref.identifier
						node:        assign
						parent_kind: 'SvelteReactiveStatement'
					},
				]
			}
			b.tree.scopes[module].set[ref.name] = v
			// addVariable: sorted by the first identifier.
			start := node_start(ref.identifier)
			mut vars := b.tree.scopes[module].variables.clone()
			mut at := vars.len
			for k, x in vars {
				ids := b.tree.variables[x].identifiers
				if ids.len > 0 && node_start(ids[0]) > start {
					at = k
					break
				}
			}
			vars.insert(at, v)
			b.tree.scopes[module].variables = vars
		}
		// The identifier, sorted.
		mut ids := b.tree.variables[v].identifiers.clone()
		mut at := ids.len
		for k, id in ids {
			if node_start(id) > node_start(ref.identifier) {
				at = k
				break
			}
		}
		ids.insert(at, ref.identifier)
		b.tree.variables[v].identifiers = ids
		b.tree.declared[node_key(ref.identifier)] = v
		b.tree.references[r].resolved = v
		b.svelte_remove_through(r, module)
	}
}

// svelte_assignment_of_target is the assignment expression whose left side has the identifier
// (the parent of the reference's writeExpr), through the patterns of a destructuring.
fn svelte_assignment_of_target(ident C.TSNode) ?C.TSNode {
	mut child := ident
	mut node := node_parent(ident)?
	for {
		match node_kind(node) {
			'assignment_expression' {
				left := node_field(node, 'left')?
				return if node_key(left) == node_key(child) { node } else { none }
			}
			'object_pattern', 'array_pattern', 'pair_pattern', 'object_assignment_pattern',
			'assignment_pattern', 'rest_pattern', 'parenthesized_expression', 'object', 'array',
			'pair', 'spread_element' {
				child = node
				node = node_parent(node)?
			}
			else {
				return none
			}
		}
	}
	return none
}

// svelte_is_reactive_statement: a top-level `$:` statement of a script (a SvelteReactiveStatement).
fn (b &ScopeBuilder) svelte_is_reactive_statement(n C.TSNode) bool {
	if node_kind(n) != 'labeled_statement' {
		return false
	}
	label := node_field(n, 'label') or { return false }
	if b.name_of(label) != '$' {
		return false
	}
	parent := node_parent(n) or { return false }
	return node_kind(parent) == 'program'
}

// svelte_snippets_scope is analyzeSnippetsScope.
fn (mut b ScopeBuilder) svelte_snippets_scope(names []int) {
	if names.len == 0 {
		return
	}
	for v, variable in b.tree.variables {
		if variable.defs.len == 0 {
			continue
		}
		def := variable.defs.filter(it.kind == .function_name && node_start(it.name) in names)
		if def.len == 0 {
			continue
		}
		name := def[0].name
		def_ids := variable.defs.map(node_key(it.name))
		refs := variable.references.filter(node_key(b.tree.references[it].identifier) !in def_ids)
		scope := variable.scope
		if refs.len == 0 {
			// removeIdentifierVariable: without definitions left, the variable goes.
			defs := variable.defs.filter(node_key(it.name) != node_key(name))
			if defs.len == 0 {
				b.tree.scopes[scope].variables = b.tree.scopes[scope].variables.filter(it != v)
				if b.tree.scopes[scope].set[variable.name] or { -1 } == v {
					b.tree.scopes[scope].set.delete(variable.name)
				}
				b.tree.variables[v].defs = []
				b.tree.variables[v].identifiers = []
			} else {
				b.tree.variables[v].defs = defs
				b.tree.variables[v].identifiers = variable.identifiers.filter(node_key(it) != node_key(name))
			}
			continue
		}
		b.tree.references << ScopeReference{
			identifier: name
			name:       variable.name
			from:       scope
			read:       true
			value_ref:  true
			virtual:    true
			resolved:   v
		}
		b.svelte_add_reference_sorted(v, b.tree.references.len - 1)
	}
}

// svelte_add_globals is addGlobalVariables: out of the global scope's through only.
fn (mut b ScopeBuilder) svelte_add_globals(globals []string) {
	for g in globals {
		if g in b.tree.scopes[0].set {
			continue
		}
		v := b.define_variable(0, g)
		mut through := []int{}
		for r in b.tree.scopes[0].through {
			if b.tree.references[r].name == g {
				b.tree.references[r].resolved = v
				b.tree.variables[v].references << r
				continue
			}
			through << r
		}
		b.tree.scopes[0].through = through
		b.tree.through = b.tree.through.filter(b.tree.references[it].name != g)
	}
}

// svelte_props_scope is analyzePropsScope for a script element.
fn (mut b ScopeBuilder) svelte_props_scope(module int, script svelte.ScriptRange, runes_off bool) {
	root := b.tree.scopes[0].block
	mut done := map[int]bool{}
	for st in named_children(root) {
		if node_start(st) < script.start || node_start(st) >= script.end {
			continue
		}
		match node_kind(st) {
			'export_statement' {
				if decl := node_field(st, 'declaration') {
					if node_kind(decl) in ['lexical_declaration', 'variable_declaration'] {
						for d in named_children(decl) {
							if node_kind(d) != 'variable_declarator' {
								continue
							}
							name := node_field(d, 'name') or { continue }
							for t in b.svelte_pattern_targets(name) {
								b.svelte_add_prop_reference(module, t.ident, mut done)
							}
						}
					}
					continue
				}
				for clause in named_children(st) {
					if node_kind(clause) != 'export_clause' {
						continue
					}
					for spec in named_children(clause) {
						if node_kind(spec) != 'export_specifier' {
							continue
						}
						local := node_field(spec, 'name') or { continue }
						if node_kind(local) != 'string' {
							b.svelte_add_prop_reference(module, local, mut done)
						}
					}
				}
			}
			'lexical_declaration', 'variable_declaration' {
				if runes_off {
					continue
				}
				for d in named_children(st) {
					if node_kind(d) != 'variable_declarator' {
						continue
					}
					name := node_field(d, 'name') or { continue }
					mut init := node_field(d, 'value') or { continue }
					for node_kind(init) in ['non_null_expression', 'as_expression',
						'satisfies_expression', 'type_assertion'] {
						parts := named_children(init).filter(node_kind(it) != 'type_arguments')
						if parts.len == 0 {
							break
						}
						init = parts[0]
					}
					if node_kind(name) != 'object_pattern'
						|| !b.svelte_is_call_of(unwrap_parens(init), '\$props') {
						continue
					}
					for t in b.svelte_pattern_targets(name) {
						if t.defaults.len == 0 {
							continue
						}
						right := t.defaults.last()
						pattern := node_parent(right) or { continue }
						left := node_field(pattern, 'left') or { continue }
						if node_key(left) != node_key(t.ident)
							|| !b.svelte_is_call_of(unwrap_parens(right), '\$bindable') {
							continue
						}
						b.svelte_add_prop_reference(module, t.ident, mut done)
						if v := b.tree.scopes[module].set[b.name_of(t.ident)] {
							b.tree.variables[v].eslint_used = true
						}
					}
				}
			}
			else {}
		}
	}
}

fn (b &ScopeBuilder) svelte_pattern_targets(pattern C.TSNode) []ScopeTarget {
	mut targets := []ScopeTarget{}
	mut rhs := []C.TSNode{}
	b.collect_pattern(pattern, []C.TSNode{}, -1, mut targets, mut rhs)
	return targets
}

// svelte_is_call_of: a call of the identifier `name`.
fn (b &ScopeBuilder) svelte_is_call_of(n C.TSNode, name string) bool {
	if node_kind(n) != 'call_expression' {
		return false
	}
	callee := node_field(n, 'function') or { return false }
	return node_kind(callee) == 'identifier' && b.name_of(callee) == name
}

// svelte_add_prop_reference is addPropReference: a virtual reference that writes and reads each
// module variable of that name that has none yet.
fn (mut b ScopeBuilder) svelte_add_prop_reference(module int, ident C.TSNode, mut done map[int]bool) {
	name := b.name_of(ident)
	for v in b.tree.scopes[module].variables {
		if b.tree.variables[v].name != name || v in done {
			continue
		}
		done[v] = true
		b.tree.references << ScopeReference{
			identifier: ident
			name:       name
			from:       module
			read:       true
			write:      true
			value_ref:  true
			virtual:    true
			resolved:   v
		}
		b.svelte_add_reference_sorted(v, b.tree.references.len - 1)
	}
}
