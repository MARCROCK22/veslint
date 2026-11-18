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
	// eslint_used: a `$bindable()` prop (svelte-eslint-parser marks it used).
	eslint_used bool
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
	// virtual: made by svelte-eslint-parser (a prop's sveltePropReference: read and write,
	// in the variable's references only).
	virtual bool
	prop    bool
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
	// The scopes of the conditional, function, mapped and constructor types of the typings go
	// with their references (extractTypeNodeScopes + removeScope).
	mut scope_of_block := map[int]int{}
	for k, sc in an.scopes {
		if sc.block !in scope_of_block {
			scope_of_block[sc.block] = k
		}
	}
	for l in typed_lets {
		if l.matched < 0 {
			continue
		}
		tsas := c.es_node(l.matched, .expression)
		c.mark_type_scopes(c.es_node(tsas, .type_annotation), scope_of_block, mut keep)
	}
	for k, s in an.scopes {
		if k < 2 {
			continue
		}
		if !keep[k] || (s.upper >= 0 && !keep[s.upper]) {
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
	// The implicit lib variables that are used, in the global scope's order.
	mut lib_refs := map[string][]int{}
	for k, r in info.references {
		if r.resolved == -2 {
			name := doc.es.string_of(r.identifier, .name) or { '' }
			lib_refs[name] << k
		}
	}
	if lib_refs.len > 0 && info.scopes.len > 0 {
		for name in lib_global_order {
			refs := lib_refs[name] or { continue }
			v := info.variables.len
			info.variables << SVariable{
				name:       name
				scope:      0
				references: refs
				global:     true
			}
			info.scopes[0].variables << v
			for r in refs {
				info.references[r].resolved = v
			}
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
	c.merge_order(pre_starts)
	c.scope_edits()
	// References are kept sorted by position (merged scopes are, upstream).
	for mut v in doc.scope.variables {
		v.references.sort_with_compare(fn [doc] (a &int, b &int) int {
			return doc.es.nodes[doc.scope.references[*a].identifier].start - doc.es.nodes[doc.scope.references[*b].identifier].start
		})
	}
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
	c.snippets_scope()
	c.add_global_variables()
}

// snippets_scope is analyzeSnippetsScope: the name of a snippet given to a component (or
// svelte:component / svelte:boundary) is not a variable unless used, then it gets a virtual
// read reference.
fn (mut c Conv) snippets_scope() {
	for sb in c.snippets {
		parent := c.doc.nodes[sb].parent
		pn := c.doc.nodes[parent]
		if pn.typ != .element {
			continue
		}
		if pn.kind != 'component' {
			if pn.kind != 'special' {
				continue
			}
			name := c.element_name_of(parent)
			if name != 'svelte:component' && name != 'svelte:boundary' {
				continue
			}
		}
		id := c.doc.nodes[sb].id.idx
		if id < 0 {
			continue
		}
		mut scope := -1
		for k, s in c.doc.scope.scopes {
			if !s.block.es && s.block.idx == sb {
				scope = k
				break
			}
		}
		if scope < 0 {
			continue
		}
		upper := c.doc.scope.scopes[scope].upper
		if upper < 0 {
			continue
		}
		name := c.doc.es.string_of(id, .name) or { '' }
		for k, vi in c.doc.scope.scopes[upper].variables {
			v := c.doc.scope.variables[vi]
			if v.name != name {
				continue
			}
			def_ids := v.defs.map(it.name)
			refs := v.references.filter(c.doc.scope.references[it].identifier !in def_ids)
			if refs.len == 0 {
				c.doc.scope.scopes[upper].variables.delete(k)
			} else {
				c.doc.scope.references << SReference{
					identifier: id
					from:       upper
					resolved:   vi
					read:       true
					is_value:   true
					virtual:    true
				}
				c.add_reference_sorted(vi, c.doc.scope.references.len - 1)
			}
			break
		}
	}
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

// remove_through is removeReferenceFromThrough: the reference leaves the through lists of its
// scope and of those above; the other references of the same name there resolve to the same
// variable (added to its references).
fn (mut c Conv) remove_through(r int, from int) {
	name := c.ref_name(r)
	v := c.doc.scope.references[r].resolved
	mut s := from
	for s >= 0 {
		mut kept := []int{}
		for x in c.doc.scope.scopes[s].through {
			if x == r {
				continue
			}
			if c.ref_name(x) == name {
				if c.doc.scope.references[x].resolved != v {
					c.doc.scope.references[x].resolved = v
					if v >= 0 {
						c.add_reference_sorted(v, x)
					}
				}
				continue
			}
			kept << x
		}
		c.doc.scope.scopes[s].through = kept
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
			// addVariable: sorted by the first identifier.
			vars := c.doc.scope.scopes[1].variables.clone()
			c.doc.scope.scopes[1].variables = c.sorted_insert(vars, [v], fn [c] (i int) int {
				return c.var_position(i)
			})
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

// mark_type_scopes is extractTypeNodeScopes: the scopes a typing's type nodes make.
fn (c &Conv) mark_type_scopes(n int, scope_of_block map[int]int, mut keep []bool) {
	if n < 0 {
		return
	}
	typ := c.doc.es.nodes[n].typ
	match typ {
		.ts_conditional_type {
			if s := scope_of_block[n] {
				keep[s] = false
			}
			c.mark_type_scopes(c.es_node(n, .false_type), scope_of_block, mut keep)
		}
		.ts_function_type, .ts_mapped_type, .ts_constructor_type {
			if s := scope_of_block[n] {
				keep[s] = false
			}
		}
		else {
			for ch in c.doc.es.children(n) {
				c.mark_type_scopes(ch, scope_of_block, mut keep)
			}
		}
	}
}

// props_scope is analyzePropsScope for a script element: a virtual reference to each exported
// variable and `$bindable()` prop.
fn (mut c Conv) props_scope(script int) {
	if c.doc.scope.scopes.len < 2 {
		return
	}
	for st in c.doc.nodes[script].body {
		typ := c.doc.es.nodes[st].typ
		if typ == .export_named_declaration {
			decl := c.es_node(st, .declaration)
			if decl >= 0 {
				if c.doc.es.nodes[decl].typ == .variable_declaration {
					for d in c.es_list(decl, .declarations) {
						for p in c.extract_pattern(c.es_node(d, .id)) {
							if c.doc.es.nodes[p].typ == .identifier {
								c.add_prop_reference(p)
							}
						}
					}
				}
			} else {
				for sp in c.es_list(st, .specifiers) {
					local := c.es_node(sp, .local)
					if local >= 0 && c.doc.es.nodes[local].typ != .literal {
						c.add_prop_reference(local)
					}
				}
			}
		} else if typ == .variable_declaration && c.runes != .off {
			for d in c.es_list(st, .declarations) {
				mut init := c.es_node(d, .init)
				for init >= 0 && c.doc.es.nodes[init].typ in [.ts_non_null_expression, .ts_as_expression,
					.ts_satisfies_expression, .ts_type_assertion] {
					init = c.es_node(init, .expression)
				}
				if init < 0 || c.doc.es.nodes[init].typ != .call_expression {
					continue
				}
				callee := c.es_node(init, .callee)
				id := c.es_node(d, .id)
				if callee < 0 || c.doc.es.nodes[callee].typ != .identifier
					|| (c.doc.es.string_of(callee, .name) or { '' }) != '\$props'
					|| c.doc.es.nodes[id].typ != .object_pattern {
					continue
				}
				for p in c.extract_pattern(id) {
					if c.doc.es.nodes[p].typ != .assignment_pattern {
						continue
					}
					left := c.es_node(p, .left)
					right := c.es_node(p, .right)
					if left < 0 || c.doc.es.nodes[left].typ != .identifier || right < 0
						|| c.doc.es.nodes[right].typ != .call_expression {
						continue
					}
					rc := c.es_node(right, .callee)
					if rc < 0 || c.doc.es.nodes[rc].typ != .identifier
						|| (c.doc.es.string_of(rc, .name) or { '' }) != '\$bindable' {
						continue
					}
					c.add_prop_reference(left)
					name := c.doc.es.string_of(left, .name) or { '' }
					for vi in c.doc.scope.scopes[1].variables {
						if c.doc.scope.variables[vi].name == name {
							c.doc.scope.variables[vi].eslint_used = true
							break
						}
					}
				}
			}
		}
	}
}

// extract_pattern yields a pattern and its sub-patterns (extractPattern).
fn (c &Conv) extract_pattern(n int) []int {
	if n < 0 {
		return []int{}
	}
	mut out := [n]
	match c.doc.es.nodes[n].typ {
		.object_pattern {
			for p in c.es_list(n, .properties) {
				if c.doc.es.nodes[p].typ == .property {
					out << c.extract_pattern(c.es_node(p, .value))
				} else {
					out << c.extract_pattern(p)
				}
			}
		}
		.array_pattern {
			for e in c.es_list(n, .elements) {
				if e >= 0 {
					out << c.extract_pattern(e)
				}
			}
		}
		.assignment_pattern {
			out << c.extract_pattern(c.es_node(n, .left))
		}
		.rest_element {
			out << c.extract_pattern(c.es_node(n, .argument))
		}
		else {}
	}
	return out
}

// add_prop_reference is addPropReference: a read-write virtual reference to every module
// variable of that name that has none yet.
fn (mut c Conv) add_prop_reference(id int) {
	name := c.doc.es.string_of(id, .name) or { return }
	for vi in c.doc.scope.scopes[1].variables {
		if c.doc.scope.variables[vi].name != name {
			continue
		}
		if c.doc.scope.variables[vi].references.any(c.doc.scope.references[it].prop) {
			continue
		}
		c.doc.scope.references << SReference{
			identifier: id
			from:       1
			resolved:   vi
			read:       true
			write:      true
			is_value:   true
			virtual:    true
			prop:       true
		}
		c.add_reference_sorted(vi, c.doc.scope.references.len - 1)
	}
}

fn (c &Conv) var_position(v int) int {
	variable := c.doc.scope.variables[v]
	if variable.defs.len > 0 && variable.defs[0].name >= 0 {
		return c.doc.es.nodes[variable.defs[0].name].start
	}
	if variable.references.len > 0 {
		return c.doc.es.nodes[c.doc.scope.references[variable.references[0]].identifier].start
	}
	return 0
}

// sorted_insert is addElementsToSortedArray: each element goes after the items whose position
// is not greater than its own (the list is taken as sorted).
fn (c &Conv) sorted_insert(list []int, elements []int, pos fn (i int) int) []int {
	mut out := list.clone()
	for e in elements {
		p := pos(e)
		mut lo := 0
		mut hi := out.len
		for lo < hi {
			mid := (lo + hi) / 2
			if pos(out[mid]) <= p {
				lo = mid + 1
			} else {
				hi = mid
			}
		}
		out.insert(lo, e)
	}
	return out
}

// merge_order puts the module scope's references and variables in the order the TypeScript
// path gives: those that were in the render function, in a `$:` statement's function or in a
// `$derived` argument's function were merged in (removeFunctionScope) at their sorted
// positions; the others keep the analysis order.
fn (mut c Conv) merge_order(pre_starts []int) {
	if c.doc.scope.scopes.len < 2 || !c.started {
		// Without template expressions the render function is empty; `$:` and `$derived`
		// still merge.
	}
	render_start := c.trimmed_len + 2
	render_end := if c.started { c.code.len + c.render.len } else { -1 }
	mut wrapped := [][]int{} // pre ranges of `$:` bodies / right sides and `$derived` arguments
	for st in c.doc.reactive.keys() {
		body := c.es_node(st, .body)
		if body >= 0 {
			wrapped << [pre_starts[body], pre_starts[body] + (c.doc.es.nodes[body].end - c.doc.es.nodes[body].start)]
		}
	}
	merged := fn [c, pre_starts, render_start, render_end, wrapped] (id int) bool {
		p := pre_starts[id]
		if c.started && p >= render_start && p < render_end {
			return true
		}
		for w in wrapped {
			if p >= w[0] && p < w[1] {
				return true
			}
		}
		return false
	}
	// (References keep the analysis order: what the TypeScript path gives.)
	mut vbase := []int{}
	mut vextra := []int{}
	for v in c.doc.scope.scopes[1].variables {
		variable := c.doc.scope.variables[v]
		if variable.defs.len > 0 && variable.defs[0].name >= 0 && merged(variable.defs[0].name) {
			vextra << v
		} else {
			vbase << v
		}
	}
	if vextra.len > 0 {
		c.doc.scope.scopes[1].variables = c.sorted_insert(vbase, vextra, fn [c] (i int) int {
			return c.var_position(i)
		})
	}
}
