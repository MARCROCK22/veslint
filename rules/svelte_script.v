module rules

import estree
import svelte
import treesitter { node_field, node_kind }

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
// lint_file does with the other rules' findings), one by one: two equal reports of the rule are
// both ESLint's (svelte_move_findings keeps one of a list's duplicates, for the rules that read
// the template's copy of the text).
fn (c &Checker) svsc_moved(findings []Finding) []Finding {
	if !c.is_svelte() {
		return findings
	}
	mut out := []Finding{cap: findings.len}
	for f in findings {
		out << c.svelte_move_findings([f])
	}
	return out
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

// SvscToken is a token of the view: its range and whether it is a punctuator.
struct SvscToken {
	start      int
	end        int
	punctuator bool
}

// svsc_token_after is sourceCode.getTokenAfter of a node or token that ends at `offset` (comments
// left out).
fn (mut c Checker) svsc_token_after(root C.TSNode, e &SvscEs, offset int) ?SvscToken {
	if e.svelte {
		token := c.sv_token_after(offset, false)?
		return SvscToken{token.start, token.end, token.typ == 'Punctuator'}
	}
	token := c.source_tokens(root).after(offset, false)?
	return SvscToken{token.start, token.end, token.kind == .punctuator}
}

// svsc_token_before is sourceCode.getTokenBefore of a node or token that starts at `offset`
// (comments left out).
fn (mut c Checker) svsc_token_before(root C.TSNode, e &SvscEs, offset int) ?SvscToken {
	if e.svelte {
		token := c.sv_token_before(offset, false)?
		return SvscToken{token.start, token.end, token.typ == 'Punctuator'}
	}
	token := c.source_tokens(root).before(offset, false)?
	return SvscToken{token.start, token.end, token.kind == .punctuator}
}

// svsc_reactive_statements are the SvelteReactiveStatement nodes of a .svelte file (the top-level
// `$:` statements of doc.es) in traversal order.
fn (mut c Checker) svsc_reactive_statements() []int {
	if !c.is_svelte() || c.svelte.doc.reactive.len == 0 {
		return []
	}
	doc := c.svelte.doc
	mut out := []int{}
	for step in c.sv_steps() {
		if step.node.es && !step.leave && step.node.idx in doc.reactive {
			out << step.node.idx
		}
	}
	return out
}

// svsc_is_function: the node is a function (the `:function` selector).
fn svsc_is_function(t &estree.EsTree, i int) bool {
	return t.typ(i) in [.function_declaration, .function_expression, .arrow_function_expression]
}

// svsc_script_of is the `<script>` element (a child of the Program) the ESTree node of the
// document at `offset` is in, -1 for the template: what the rules that track `Program >
// SvelteScriptElement` and its `:exit` know.
fn (c &Checker) svsc_script_of(offset int) int {
	doc := c.svelte.doc
	for ch in doc.nodes[0].children {
		n := &doc.nodes[ch]
		if n.typ == .script_element && n.start <= offset && offset < n.end {
			return ch
		}
	}
	return -1
}

// svsc_kit_version_in: the file is in a SvelteKit project of one of these versions (the
// condition `svelteKitVersions`).
fn (c &Checker) svsc_kit_version_in(abs_path string, versions []string) bool {
	return c.sv_kit_context(c.sv_file_path(abs_path)).version in versions
}

// svsc_kit_file_type is svelteKitFileType of the file.
fn (c &Checker) svsc_kit_file_type(abs_path string) SvelteKitFileType {
	return c.sv_kit_context(c.sv_file_path(abs_path)).file_type
}

// svsc_import_variable is the variable an import specifier found by ReferenceTracker declares
// (findVariable of its `local`), -1 for another node.
fn (mut c Checker) svsc_import_variable(root C.TSNode, specifier C.TSNode) int {
	if node_kind(specifier) != 'import_specifier' {
		return -1
	}
	local := node_field(specifier, 'alias') or { node_field(specifier, 'name') or { return -1 } }
	return c.scope_tree(root).declared_variable(local)
}

// SvscDefKind is the `type` of a definition of the document's scope manager, as far as the rules
// tell them apart.
enum SvscDefKind {
	other
	variable       // `Variable`: node is the VariableDeclarator
	import_binding // `ImportBinding`
	function_name  // `FunctionName`: node is the function
	computed       // svelte-eslint-parser's `ComputedVariable` (`$: x = …`): node is the assignment
}

// svsc_def is the type and node of a definition of doc.scope (from its name's place).
fn (c &Checker) svsc_def(def svelte.SDef) (SvscDefKind, int) {
	es := &c.svelte.doc.es
	parent := es.nodes[def.name].parent
	if def.computed {
		return SvscDefKind.computed, parent
	}
	if parent >= 0 {
		match es.typ(parent) {
			.import_specifier, .import_default_specifier, .import_namespace_specifier {
				return SvscDefKind.import_binding, parent
			}
			.function_declaration, .function_expression {
				if (es.node(parent, .id) or { -1 }) == def.name {
					return SvscDefKind.function_name, parent
				}
			}
			else {}
		}
	}
	declarator := c.sv_def_declarator(def.name)
	if declarator >= 0 {
		return SvscDefKind.variable, declarator
	}
	return SvscDefKind.other, -1
}

// svsc_toplevel_scope is the module scope of the document's scope manager (else the global one).
fn (c &Checker) svsc_toplevel_scope() int {
	info := &c.svelte.doc.scope
	for child in info.scopes[0].children {
		if info.scopes[child].typ == 'module' {
			return child
		}
	}
	return 0
}

// svsc_property_name is getPropertyName of eslint-utils for a MemberExpression of the document
// (without a scope: a computed key is a constant string).
fn (c &Checker) svsc_property_name(member int) ?string {
	es := &c.svelte.doc.es
	property := es.node(member, .property)?
	if es.flag(member, .computed) or { false } {
		return c.sv_string_if_constant(property)
	}
	if es.typ(property) == .private_identifier {
		return none
	}
	return es.string_of(property, .name)
}

// svsc_in_range: [start, end) of the node is inside [from, to).
fn svsc_in_range(t &estree.EsTree, i int, from int, to int) bool {
	return from <= t.nodes[i].start && t.nodes[i].end <= to
}

// svsc_pattern_identifiers is iterateIdentifiers of a destructuring pattern, in its order.
fn svsc_pattern_identifiers(t &estree.EsTree, pattern int) []int {
	mut out := []int{}
	mut buffer := [pattern]
	for buffer.len > 0 {
		p := buffer[0]
		buffer.delete(0)
		match t.typ(p) {
			.identifier {
				out << p
			}
			.array_pattern {
				for element in t.list(p, .elements) or { []int{} } {
					if element >= 0 {
						buffer << element
					}
				}
			}
			.object_pattern {
				for property in t.list(p, .properties) or { []int{} } {
					if t.typ(property) == .property {
						buffer << t.node(property, .value) or { continue }
					} else if t.typ(property) == .rest_element {
						buffer << property
					}
				}
			}
			.assignment_pattern {
				buffer << t.node(p, .left) or { continue }
			}
			.rest_element {
				buffer << t.node(p, .argument) or { continue }
			}
			else {}
		}
	}
	return out
}
