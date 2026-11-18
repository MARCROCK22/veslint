module svelte

// The scope manager svelte-eslint-parser gives ESLint for a component, as far as ported: the
// scopes, variables and references of typescript-eslint's analysis of the pre-virtual code
// (scope.v; the virtual code's render function, declarations and `$:`/`$derived` wrappers are
// merged away upstream, which gives the same tree), without what the restore removes (the
// wrappers' `__$ctx__` and `Array`, the typings of block params and snippet params, the
// snippets' `return`, the preparation scripts of `{:then}`), with the scopes of the blocks
// registered to the Svelte nodes, and the edits of src/parser/analyze-scope.ts and index.ts:
// the Svelte globals in the global scope, `$store` references resolved to the store variable,
// `$: x = …` variables. Not ported: the props' virtual references (analyzePropsScope), the
// snippets' references (analyzeSnippetsScope), the scopes of conditional/function/mapped
// types of the typings (removed upstream).

pub struct SScope {
pub mut:
	typ        string
	block      Ref // a Svelte node (a block, the Program) or an ESTree node
	upper      int = -1
	children   []int
	variables  []int
	references []int
	through    []int
}

pub struct SDef {
pub:
	name     int // the ESTree identifier
	is_type  bool
	is_value bool
	computed bool // a `$: x = …` ComputedVariable
}

pub struct SVariable {
pub mut:
	name       string
	scope      int
	defs       []SDef
	references []int
	// global: a Svelte global or an implicit lib variable (no definition).
	global bool
}

pub struct SReference {
pub mut:
	identifier int // ESTree node
	from       int
	resolved   int = -1 // a variable index, -1: unresolved, -2: an implicit lib variable
	read       bool
	write      bool
	is_type    bool
	is_value   bool
}

pub struct ScopeInfo {
pub mut:
	scopes     []SScope
	variables  []SVariable
	references []SReference
}

const scope_type_names = ['global', 'module', 'function', 'block', 'for', 'catch', 'class',
	'class-field-initializer', 'class-static-block', 'conditionalType',
	'function-expression-name', 'functionType', 'mappedType', 'switch', 'tsEnum', 'tsModule',
	'type']

// in_user_text tells whether a byte offset of the pre-virtual code is code of the file (the
// script, or a template expression copied from the file), as opposed to text the parser made.
fn (c &Conv) in_user_text(p int) bool {
	if !c.started || p < c.trimmed_len {
		return true
	}
	for s in c.doc.segments {
		if s.pre_start <= p && p < s.pre_start + s.len {
			return true
		}
	}
	return false
}

// build_scope builds Document.scope from the analysis of the pre-virtual code (pre_starts: the
// pre offsets of the ESTree nodes before the restore moved them to the file).
fn (mut c Conv) build_scope(an &Analyzer, pre_starts []int, typed_lets []ScriptLet) {
	mut doc := c.doc
	mut info := ScopeInfo{}
	// Scopes made by the parser's own text are removed with their content, but those of the
	// lets (registered to the Svelte blocks) and of the typings of typed expressions.
	mut block_of := map[int]int{} // es block node -> Svelte node
	for l in c.lets {
		if l.matched < 0 {
			continue
		}
		match l.kind {
			.block {
				block_of[l.matched] = l.target
			}
			.block_params, .each_block {
				block_of[l.scope_node] = l.target
			}
			.if_block {
				block_of[l.scope_node] = l.target
			}
			.snippet_block {
				block_of[l.matched] = l.target
			}
			else {}
		}
	}
	mut keep := []bool{len: an.scopes.len, init: true}
	mut new_index := []int{len: an.scopes.len, init: -1}
	for k, s in an.scopes {
		if k < 2 {
			continue
		}
		if s.upper >= 0 && !keep[s.upper] {
			keep[k] = false
			continue
		}
		start := pre_starts[s.block]
		if !c.in_user_text(start) && s.block !in block_of && !c.in_typing(start, typed_lets) {
			keep[k] = false
		}
	}
	for k, s in an.scopes {
		if !keep[k] {
			continue
		}
		new_index[k] = info.scopes.len
		block := if k == 0 {
			eref(doc.es.root)
		} else if k == 1 {
			sref(0)
		} else if svelte := block_of[s.block] {
			sref(svelte)
		} else {
			eref(s.block)
		}
		info.scopes << SScope{
			typ:   scope_type_names[int(s.typ)]
			block: block
			upper: if s.upper >= 0 { new_index[s.upper] } else { -1 }
		}
		if s.upper >= 0 && new_index[s.upper] >= 0 {
			info.scopes[new_index[s.upper]].children << info.scopes.len - 1
		}
	}
	// Variables (the made-up ones go: `__$ctx__`, the generics' default aliases, the prep
	// scripts' declarations).
	mut var_index := []int{len: an.vars.len, init: -1}
	for k, v in an.vars {
		si := new_index[v.scope]
		if si < 0 {
			continue
		}
		mut defs := []SDef{}
		for d in v.defs {
			if d.name >= 0 && !c.in_user_text(pre_starts[d.name]) {
				continue
			}
			defs << SDef{
				name:     d.name
				is_type:  d.is_type
				is_value: d.is_value
			}
		}
		if v.defs.len > 0 && defs.len == 0 {
			continue
		}
		var_index[k] = info.variables.len
		info.variables << SVariable{
			name:  v.name
			scope: si
			defs:  defs
		}
		info.scopes[si].variables << info.variables.len - 1
	}
	// References: those of the parser's text go (`Array`, typings of params), but those of
	// the typings of typed expressions (kept upstream, at shifted positions).
	mut ref_index := []int{len: an.refs.len, init: -1}
	for k, r in an.refs {
		from := new_index[r.from]
		if from < 0 {
			continue
		}
		p := pre_starts[r.id]
		if !c.in_user_text(p) && !c.in_typing(p, typed_lets) {
			continue
		}
		ref_index[k] = info.references.len
		resolved := if r.resolved >= 0 { var_index[r.resolved] } else { r.resolved }
		info.references << SReference{
			identifier: r.id
			from:       from
			resolved:   resolved
			read:       r.flag & ref_read != 0
			write:      r.flag & ref_write != 0
			is_type:    r.type_
			is_value:   r.value
		}
		info.scopes[from].references << info.references.len - 1
		if resolved >= 0 {
			info.variables[resolved].references << info.references.len - 1
		}
	}
	for k, s in an.scopes {
		si := new_index[k]
		if si < 0 {
			continue
		}
		for r in s.through {
			if ref_index[r] >= 0 {
				info.scopes[si].through << ref_index[r]
			}
		}
	}
	doc.scope = info
	c.scope_edits()
}

// in_typing: the offset is in the typing of a typed expression (`(e)as (typing);`).
fn (c &Conv) in_typing(p int, typed []ScriptLet) bool {
	for l in typed {
		s := l.segments[0]
		if p >= s.pre_start + s.len && p < l.end {
			return true
		}
	}
	return false
}

// scope_edits are svelte-eslint-parser's edits after the restore (index.ts parseAsSvelte):
// stores, `$:` variables, Svelte globals.
fn (mut c Conv) scope_edits() {
	c.store_scope()
	c.reactive_scope()
	c.store_scope()
	c.add_global_variables()
}

fn (c &Conv) ref_name(r int) string {
	return c.doc.es.string_of(c.doc.scope.references[r].identifier, .name) or { '' }
}

fn (c &Conv) svelte_globals() []string {
	mut g := ['\$\$slots', '\$\$props', '\$\$restProps']
	if c.runes != .off {
		g << rune_globals
	}
	return g
}

// remove_through takes a reference out of the through lists of a scope and of those above.
fn (mut c Conv) remove_through(r int, from int) {
	mut s := from
	for s >= 0 {
		c.doc.scope.scopes[s].through = c.doc.scope.scopes[s].through.filter(it != r)
		s = c.doc.scope.scopes[s].upper
	}
}

// store_scope is analyzeStoreScope: a `$x` reference whose `x` is a module variable reads it.
fn (mut c Conv) store_scope() {
	if c.doc.scope.scopes.len < 2 {
		return
	}
	globals := c.svelte_globals()
	module := 1
	for r in c.doc.scope.scopes[0].through.clone() {
		name := c.ref_name(r)
		if !name.starts_with('\$') || name in globals {
			continue
		}
		mut v := -1
		for vi in c.doc.scope.scopes[module].variables {
			if c.doc.scope.variables[vi].name == name[1..] {
				v = vi
				break
			}
		}
		if v < 0 {
			continue
		}
		c.doc.scope.references[r].read = true
		c.doc.scope.references[r].write = false
		c.doc.scope.references[r].resolved = v
		c.add_reference_sorted(v, r)
		c.remove_through(r, module)
	}
}

fn (mut c Conv) add_reference_sorted(v int, r int) {
	start := c.doc.es.nodes[c.doc.scope.references[r].identifier].start
	mut refs := c.doc.scope.variables[v].references.clone()
	mut at := refs.len
	for k, x in refs {
		if c.doc.es.nodes[c.doc.scope.references[x].identifier].start > start {
			at = k
			break
		}
	}
	refs.insert(at, r)
	c.doc.scope.variables[v].references = refs
}

// reactive_scope is analyzeReactiveScope: `$: x = …` at the top level defines x (a
// ComputedVariable) in the module scope.
fn (mut c Conv) reactive_scope() {
	if c.doc.scope.scopes.len < 2 {
		return
	}
	for r in c.doc.scope.scopes[0].through.clone() {
		ref := c.doc.scope.references[r]
		if ref.from != 1 || !ref.write {
			continue
		}
		id := ref.identifier
		assign := c.doc.es.nodes[id].parent
		if assign < 0 || c.doc.es.nodes[assign].typ != .assignment_expression {
			continue
		}
		stmt := c.doc.es.nodes[assign].parent
		if stmt < 0 || c.doc.es.nodes[stmt].typ != .expression_statement {
			continue
		}
		label := c.doc.es.nodes[stmt].parent
		if label < 0 || label !in c.doc.reactive {
			continue
		}
		name := c.ref_name(r)
		mut v := -1
		for vi in c.doc.scope.scopes[1].variables {
			if c.doc.scope.variables[vi].name == name {
				v = vi
				break
			}
		}
		if v < 0 {
			c.doc.scope.variables << SVariable{
				name:  name
				scope: 1
				defs:  [SDef{
					name:     id
					is_value: true
					computed: true
				}]
			}
			v = c.doc.scope.variables.len - 1
			c.doc.scope.scopes[1].variables << v
		}
		c.doc.scope.references[r].resolved = v
		c.remove_through(r, 1)
	}
}

// add_global_variables is addGlobalVariables: the Svelte globals in the global scope (references
// resolved, out of the global scope's through only).
fn (mut c Conv) add_global_variables() {
	if c.doc.scope.scopes.len == 0 {
		return
	}
	for g in c.svelte_globals() {
		mut exists := false
		for vi in c.doc.scope.scopes[0].variables {
			if c.doc.scope.variables[vi].name == g {
				exists = true
			}
		}
		if exists {
			continue
		}
		c.doc.scope.variables << SVariable{
			name:   g
			scope:  0
			global: true
		}
		v := c.doc.scope.variables.len - 1
		c.doc.scope.scopes[0].variables << v
		mut through := []int{}
		for r in c.doc.scope.scopes[0].through {
			if c.ref_name(r) == g {
				c.doc.scope.references[r].resolved = v
				c.doc.scope.variables[v].references << r
				continue
			}
			through << r
		}
		c.doc.scope.scopes[0].through = through
	}
}
