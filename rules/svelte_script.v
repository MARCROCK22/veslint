module rules

import estree
import svelte

// What the svelte/* rules that read the script share (eslint-plugin-svelte 3.24.1's rules on the
// ESTree nodes of the script and of the template expressions). Several of them also lint
// `.ts` and `.svelte.ts` files, as upstream does when ESLint runs them there (their `conditions`
// say where; getSvelteContext with Svelte 5 installed): they read the ESTree through SvscEs, the
// same for the three kinds of file.
//
// Two views of a .svelte file:
//   - SvscEs (c.svsc_es): the document's own ESTree (doc.es: svelte-eslint-parser's, with the
//     offsets of the file and the parents of the template expressions in the Svelte nodes,
//     svsc_parent), walked in ESLint's order; for any other file the ESTree of the file
//     (c.es_tree). Reports on it are offsets of the file: c.svsc_report.
//   - the lint code (c.es_tree, c.scope_tree, the types of tsgo), for the rules that need the
//     scope manager's references, ReferenceTracker or types, which veslint has on that tree: the
//     same code as for a .ts file; their findings are moved to the file with c.svsc_moved before
//     the rule returns them (lint_file keeps the svelte/* ones as they are).

// SvscEs is the ESTree a rule reads: the document's for a .svelte file, the file's otherwise.
struct SvscEs {
	t      &estree.EsTree = unsafe { nil }
	svelte bool
	// steps: enter and leave events of ESLint's traversal (ESTree nodes only).
	steps []estree.Step
}

// svsc_es is the ESTree of the file a rule reads (none when the file has syntax errors).
fn (mut c Checker) svsc_es(root C.TSNode, abs_path string) ?SvscEs {
	if c.is_svelte() {
		mut steps := []estree.Step{}
		for step in c.sv_steps() {
			if step.node.es {
				steps << estree.Step{step.node.idx, step.leave}
			}
		}
		return SvscEs{
			t:      &c.svelte.doc.es
			svelte: true
			steps:  steps
		}
	}
	t := c.es_tree(root, abs_path)?
	return SvscEs{
		t:     t
		steps: t.steps()
	}
}

// entered are the nodes in the order the traversal enters them.
fn (e &SvscEs) entered() []int {
	mut out := []int{cap: e.steps.len / 2}
	for step in e.steps {
		if !step.leave {
			out << step.node
		}
	}
	return out
}

// type_name is a node's `type`.
fn (e &SvscEs) type_name(c &Checker, i int) string {
	if e.svelte {
		return c.svelte.doc.es_type_name(i)
	}
	if name := e.t.foreign[i] {
		return name
	}
	return e.t.nodes[i].typ.type_name()
}

// svsc_parent is a node's `parent` when it is an ESTree node (-1 for a Svelte node or none).
fn (c &Checker) svsc_parent(e &SvscEs, i int) int {
	if e.svelte {
		p := c.sv_parent(sv_es_ref(i)) or { return -1 }
		return if p.es { p.idx } else { -1 }
	}
	p := e.t.nodes[i].parent
	if p >= 0 && p in e.t.foreign {
		return -1
	}
	return p
}

// svsc_parent_ref is a node's `parent` as a Svelte reference (an ESTree node or a Svelte node)
// for a .svelte file.
fn (c &Checker) svsc_parent_ref(e &SvscEs, i int) ?svelte.Ref {
	if e.svelte {
		return c.sv_parent(sv_es_ref(i))
	}
	p := e.t.nodes[i].parent
	if p < 0 || p in e.t.foreign {
		return none
	}
	return sv_es_ref(p)
}

// svsc_text is sourceCode.getText of an ESTree node of the view.
fn (c &Checker) svsc_text(e &SvscEs, i int) string {
	n := &e.t.nodes[i]
	if e.svelte {
		return c.sv_text(n.start, n.end)
	}
	return c.src[n.start..n.end]
}

// svsc_report is a report on an ESTree node of the view.
fn (c &Checker) svsc_report(e &SvscEs, i int, message_id string, data map[string]string) Finding {
	n := &e.t.nodes[i]
	return c.sv_report(n.start, n.end, message_id, data)
}

// svsc_moved moves the findings a rule made on the lint code of a .svelte file to the file (as
// lint_file does with the other rules' findings).
fn (c &Checker) svsc_moved(findings []Finding) []Finding {
	if c.is_svelte() {
		return c.svelte_move_findings(findings)
	}
	return findings
}

// SvscRunes is the `runes` of getSvelteContext: null for a file that is neither a component nor a
// `.svelte.[js|ts]` module.
enum SvscRunes {
	null
	no
	yes
}

// svsc_runes is the file's `runes`: a component's from svelte-eslint-parser's parse context, a
// module's true (svelte-eslint-parser parses `.svelte.ts` files as modules in runes mode).
fn (c &Checker) svsc_runes(abs_path string) SvscRunes {
	return match sv_file_type(c.sv_file_path(abs_path)) {
		.component {
			if c.sv_runes() { .yes } else { .no }
		}
		.module { .yes }
		.none { .null }
	}
}

// svsc_runes_on is the condition `{ svelteVersions: ['5'], runes: [true, 'undetermined'] }`.
fn (c &Checker) svsc_runes_on(abs_path string) bool {
	return c.svsc_runes(abs_path) == .yes
}

// svsc_runes_off is the conditions `{ svelteVersions: ['3/4'] }, { svelteVersions: ['5'], runes:
// [false, 'undetermined'] }` of the `$:` rules, with Svelte 5 installed.
fn (c &Checker) svsc_runes_off(abs_path string) bool {
	return c.svsc_runes(abs_path) == .no
}

// svsc_string_literal is the value of a string Literal of the view.
fn svsc_string_literal(t &estree.EsTree, i int) ?string {
	if i < 0 || t.typ(i) != .literal {
		return none
	}
	value := t.get(i, .value)
	if value is string {
		return value
	}
	return none
}

// SvscStoreCall is a call of a store function of `svelte/store` (extractStoreReferences): the
// CallExpression (an ESTree node of the lint code) and the function's name.
struct SvscStoreCall {
	node int
	name string
}

// svsc_store_calls ports extractStoreReferences: the calls of `writable`, `readable` and `derived`
// (those of `names`) imported from `svelte/store`, found by ReferenceTracker on the lint code.
fn (mut c Checker) svsc_store_calls(root C.TSNode, abs_path string, names []string) []SvscStoreCall {
	if !c.src.contains('svelte/store') {
		return []
	}
	t := c.es_tree(root, abs_path) or { return [] }
	mut children := map[string]EsTrace{}
	for name in ['writable', 'readable', 'derived'] {
		children[name] = EsTrace{
			call: name in names
		}
	}
	mut out := []SvscStoreCall{}
	for traced in c.es_esm_references(root, {
		'svelte/store': EsTrace{
			esm:      true
			children: children
		}
	}) {
		node := c.es_index_of(t, traced.node) or { continue }
		out << SvscStoreCall{
			node: node
			name: traced.path.last()
		}
	}
	return out
}

// svsc_find_variable_for_replacement ports findVariableForReplacement (ast-utils.ts) on the lint
// code: whether `replacement` is referenced or declared in the scope of `node` (a conflict), and
// else the variable of that scope named `name` (-1 for none).
fn (mut c Checker) svsc_find_variable_for_replacement(root C.TSNode, node C.TSNode, name string, replacement string) (bool, int) {
	tree := c.scope_tree(root)
	scope := tree.get_scope(node)
	for r in tree.scopes[scope].references {
		if tree.references[r].name == replacement {
			return true, -1
		}
	}
	mut variable := -1
	for v in tree.scopes[scope].variables {
		if tree.variables[v].name == replacement {
			return true, -1
		}
		if tree.variables[v].name == name {
			variable = v
		}
	}
	return false, variable
}

// svsc_rename_fix is the fix of a suggestion that renames a parameter and the references of its
// variable (one fix: ESLint merges a fixer's fixes).
fn (mut c Checker) svsc_rename_fix(root C.TSNode, start int, end int, variable int, name string) ?Fix {
	mut fixes := [fix_replace_range(start, end, name)]
	if variable >= 0 {
		tree := c.scope_tree(root)
		for r in tree.variables[variable].references {
			fixes << fix_replace(tree.references[r].identifier, name)
		}
	}
	has, fix := c.merge_fixes(fixes) or { return none }
	return if has { fix } else { none }
}
