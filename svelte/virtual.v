module svelte

import estree
import strings

// The virtual TypeScript code svelte-eslint-parser hands typescript-eslint for a component
// (src/parser/typescript/analyze/index.ts analyzeTypeScriptInSvelte, analyze/component.ts,
// context.ts): the pre-virtual code with declarations of the stores, `$$` variables and runes
// it uses, its `$:` statements and `$derived(…)` arguments wrapped in functions, its template
// part in `export function $_renderN(){…}`, and a default export typing the component. This
// is the code a type checker must see for the .svelte file (typescript-eslint type-checks it
// as the file's content). Offsets are UTF-16 offsets of svelte-eslint-parser's pre-virtual
// code (Document.pre_u16) and of the virtual code, as RestoreContext records them.

// VOffset is an entry of the offset table: the virtual code from `dist` on is the pre-virtual
// code from `original` on.
pub struct VOffset {
pub:
	original int
	dist     int
}

// VRange is a fragment of the virtual code that is not in the pre-virtual code.
pub struct VRange {
pub mut:
	start int
	end   int
}

struct VirtualCtx {
	original string // pre_u16
	oindex   TextIndex
mut:
	script    strings.Builder
	script16  int
	consumed  int
	offsets   []VOffset
	fragments []VRange
	unique    UniqueIds
}

fn (mut v VirtualCtx) append_original(i int) {
	if v.consumed >= i {
		return
	}
	v.offsets << VOffset{v.consumed, v.script16}
	piece := v.original[v.oindex.to_byte(v.consumed)..v.oindex.to_byte(i)]
	v.script.write_string(piece)
	v.script16 += i - v.consumed
	v.consumed = i
}

fn (mut v VirtualCtx) append_virtual(s string) {
	start := v.script16
	v.script.write_string(s)
	v.script16 += u16_len_of(s)
	if v.fragments.len > 0 && v.fragments.last().end == start {
		v.fragments[v.fragments.len - 1].end = v.script16
		return
	}
	v.fragments << VRange{start, v.script16}
}

fn (mut v VirtualCtx) skip_original(n int) {
	v.consumed += n
}

fn (mut v VirtualCtx) skip_until(i int) {
	if i > v.consumed {
		v.consumed = i
	}
}

fn (mut v VirtualCtx) unique_id(base string) string {
	return v.unique.generate(base, [v.original, v.script.bytestr()])
}

// Transform is a TransformInfo: a node's range (UTF-16 of the pre-virtual code) and what to do.
struct Transform {
	start int
	end   int
	kind  u8  // 0 reactive var, 1 reactive statement, 2 $derived, 3 bindable props
	node  int // the ESTree node (pre)
	left  int // reactive var: the left side; bindable: unused
	keys  []string
}

// Virt is the analysis state.
struct Virt {
mut:
	doc   &Document      = unsafe { nil }
	es    &estree.EsTree = unsafe { nil }
	an    Analyzer
	v     VirtualCtx
	runes RunesMode
	toks  []SnipToken
	comms []SnipToken
	// through: the names of the global scope's unresolved references, in order, with their
	// identifiers.
	through []int
}

// RunesMode is svelteParseContext.runes while parsing: unknown (undefined), on or off.
pub enum RunesMode as u8 {
	unknown
	on
	off
}

fn (x &Virt) u(p int) int {
	return pre_u16_offset(x.doc, p)
}

fn (x &Virt) name(n int) string {
	return x.es.string_of(n, .name) or { '' }
}

fn (x &Virt) through_has(name string) bool {
	for r in x.through {
		if x.name(x.an.refs[r].id) == name {
			return true
		}
	}
	return false
}

// build_virtual builds the virtual code (Document.virtual_code and its maps).
fn (mut c Conv) build_virtual(toks []SnipToken, comms []SnipToken) {
	mut doc := c.doc
	pre16 := doc.pre_u16
	mut x := Virt{
		doc:   doc
		es:    &doc.es
		an:    analyze_snippet(&doc.es)
		v:     VirtualCtx{
			original: pre16
			oindex:   new_text_index(pre16)
		}
		runes: c.runes
		toks:  toks
		comms: comms
	}
	if x.an.scopes.len > 0 {
		x.through = x.an.scopes[0].through.clone()
	}
	// The script part (`trimmedRaw + "\n;"`), render and root scope parts, in UTF-16.
	script_len, render_len := c.virtual_parts()
	lead := js_trim_start_len_u16(pre16, script_len)
	x.v.append_original(lead)
	x.store_references()
	x.dollar_dollar_variables(c.slots)
	x.rune_variables()
	lang := doc.lang
	is_js := lang == '' || lang == 'js' || lang == 'javascript'
	if is_js {
		x.v.append_virtual('\n')
	}
	mut script_tr := x.reactive_transforms()
	mut render_tr := []Transform{}
	mut root_tr := []Transform{}
	mut others := x.derived_transforms()
	others << x.bindable_transforms()
	for t in others {
		if t.start < script_len {
			script_tr << t
		} else if t.start < script_len + render_len {
			render_tr << t
		} else {
			root_tr << t
		}
	}
	x.apply(mut script_tr)
	x.v.append_original(script_len)
	render_name := x.v.unique_id('render')
	x.v.append_virtual('export function ${render_name}(){')
	x.apply(mut render_tr)
	x.v.append_original(script_len + render_len)
	x.v.append_virtual('}')
	if !x.has_export_declaration() {
		x.v.append_virtual('export namespace SvelteEslintParserModuleMarker {}')
	}
	x.apply(mut root_tr)
	x.v.append_original(x.v.oindex.u16_len)
	x.component_default_export(c)
	c.an = x.an
	doc.virtual_code = x.v.script.bytestr()
	doc.virtual_offsets = x.v.offsets
	doc.virtual_fragments = x.v.fragments
}

// virtual_parts gives the UTF-16 lengths of the script part and of the render part.
fn (c &Conv) virtual_parts() (int, int) {
	doc := c.doc
	if !c.started {
		return u16_len_of(doc.pre_u16), 0
	}
	script := doc.index.to_u16(c.trimmed_len) + 2
	// render = beforeSpaces + render lets; the root scope = snippet + generics lets.
	before := u16_len_of(c.before_spaces_u16())
	return script, before + u16_len_of(c.render.bytestr())
}

// before_spaces_u16 is ScriptsSourceCode's beforeSpaces (JavaScript blanks).
fn (c &Conv) before_spaces_u16() string {
	raw := c.sc.script_u16
	lu := c.doc.index.to_u16(c.trimmed_len)
	after := u16_byte_offset(raw, lu + 2)
	return raw[after..]
}

// js_trim_start_len_u16 is `/^\s*/u.exec(s)[0].length` within the first `limit` units.
fn js_trim_start_len_u16(s string, limit int) int {
	mut i := 0
	mut units := 0
	for i < s.len && units < limit {
		if !is_space_at(s, i) {
			break
		}
		_, n := code_point_at(s, i)
		units += if n == 4 { 2 } else { 1 }
		i += n
	}
	return units
}

fn (x &Virt) svelte_globals() []string {
	mut g := ['\$\$slots', '\$\$props', '\$\$restProps']
	if x.runes != .off {
		g << rune_globals
	}
	return g
}

const rune_globals = ['\$state', '\$derived', '\$effect', '\$props', '\$bindable', '\$inspect',
	'\$host']

fn (x &Virt) module_declares(name string) bool {
	if x.an.scopes.len < 2 {
		return false
	}
	for v in x.an.scopes[1].variables {
		if x.an.vars[v].name == name {
			return true
		}
	}
	return false
}

// store_references is analyzeStoreReferenceNames.
fn (mut x Virt) store_references() {
	globals := x.svelte_globals()
	mut names := []string{}
	for r in x.through {
		nm := x.name(x.an.refs[r].id)
		if nm.starts_with('\$') && nm !in globals && !x.module_declares(nm) && nm !in names {
			names << nm
		}
	}
	if names.len == 0 {
		return
	}
	t := x.v.unique_id('StoreValueType')
	x.v.append_virtual('type ${t}<T> = T extends null | undefined\n? T\n: T extends object & { subscribe(run: infer F, ...args: any): any }\n? F extends (value: infer V, ...args: any) => any\n? V\n: never\n: T;')
	for nm in names {
		x.v.append_virtual('declare let ${nm}: ${t}<typeof ${nm[1..]}>;')
	}
}

// dollar_dollar_variables is analyzeDollarDollarVariables.
fn (mut x Virt) dollar_dollar_variables(slots []int) {
	for g in ['\$\$slots', '\$\$props', '\$\$restProps'] {
		if !x.through_has(g) {
			continue
		}
		if g == '\$\$slots' {
			mut types := []string{}
			for slot in slots {
				st := x.doc.nodes[x.doc.nodes[slot].start_tag]
				mut name_attr := -1
				for a in st.attributes {
					an := x.doc.nodes[a]
					if an.typ == .attribute && !an.key.es && an.key.idx >= 0
						&& x.doc.nodes[an.key.idx].name == 'name' {
						name_attr = a
						break
					}
				}
				mut t := ''
				if name_attr < 0 || x.doc.nodes[name_attr].values.len == 0 {
					t = '"default"'
				} else if x.doc.nodes[name_attr].values.len == 1 {
					v := x.doc.nodes[x.doc.nodes[name_attr].values[0]]
					t = if v.typ == .literal { json_quote_u16(v.value) } else { 'string' }
				} else {
					mut parts := []string{}
					for vi in x.doc.nodes[name_attr].values {
						v := x.doc.nodes[vi]
						if v.typ == .literal {
							parts << v.value.replace('\$', '\\\$').replace('`', '\\`')
						} else {
							parts << '\${string}'
						}
					}
					t = '`${parts.join('')}`'
				}
				if t !in types {
					types << t
				}
			}
			x.v.append_virtual('declare let ${g}: Record<${if types.len > 0 {
				types.join(' | ')
			} else {
				'any'
			}}, boolean>;')
			continue
		}
		x.v.append_virtual('declare let ${g}: { [index: string]: any };')
	}
}

// json_quote_u16 is JSON.stringify of a string (non-ASCII kept as is).
fn json_quote_u16(s string) string {
	return json_quote(s)
}

// rune_variables is analyzeRuneVariables.
fn (mut x Virt) rune_variables() {
	if x.runes == .off {
		return
	}
	for g in rune_globals {
		if !x.through_has(g) {
			continue
		}
		x.v.append_virtual(rune_declarations(g))
	}
}

// rune_declarations are the declarations analyzeRuneVariables gives a rune the code references.
fn rune_declarations(g string) string {
	mut out := ''
	{
		mut fns := []string{}
		mut nss := []string{}
		match g {
			'\$state' {
				fns = ['<T>(initial: T): T', '<T>(): T | undefined']
				nss = ['export function eager<T>(value: T): T', 'export function raw<T>(initial: T): T;',
					'export function raw<T>(): T | undefined;',
					'export function snapshot<T>(state: T): T;']
			}
			'\$derived' {
				fns = ['<T>(expression: T): T']
				nss = ['export function by<T>(fn: () => T): T;']
			}
			'\$effect' {
				fns = ['(fn: () => void | (() => void)): void']
				nss = ['export function pre(fn: () => void | (() => void)): void;',
					'export function pending(): number;', 'export function tracking(): boolean;',
					'export function root(fn: () => void | (() => void)): () => void;']
			}
			'\$props' {
				fns = ['<T>(): T',
					'<T, K extends string>(...bindableKeys: K[]): { [P in keyof T]: T[P] | (P extends K ? undefined : never) }']
				nss = ['export function id(): string;']
			}
			'\$bindable' {
				fns = ['<T>(fallback?: T): T']
			}
			'\$inspect' {
				fns = ["<T extends any[]>(...values: T): { with: (fn: (type: 'init' | 'update', ...values: T) => void) => void }"]
				nss = ['export function trace(name?: string): void;']
			}
			'\$host' {
				fns = ['<El extends HTMLElement = HTMLElement>(): El']
			}
			else {}
		}
		for f in fns {
			out += 'declare function ${g}${f};'
		}
		for ns in nss {
			out += 'declare namespace ${g} { ${ns} }'
		}
	}
	return out
}

fn (x &Virt) has_export_declaration() bool {
	for st in x.es.list(x.es.root, .body) or { []int{} } {
		if x.es.nodes[st].typ in [.export_named_declaration, .export_default_declaration] {
			return true
		}
	}
	return false
}

fn (x &Virt) node(i int, key estree.Key) int {
	if i < 0 {
		return -1
	}
	return x.es.node(i, key) or { -1 }
}

fn (x &Virt) list(i int, key estree.Key) []int {
	if i < 0 {
		return []int{}
	}
	return x.es.list(i, key) or { []int{} }
}

fn (x &Virt) typ(i int) estree.NodeType {
	return x.es.nodes[i].typ
}

// in_through: an identifier of the global scope's through references.
fn (x &Virt) through_ids() []int {
	return x.through.map(x.an.refs[it].id)
}

// reactive_transforms is analyzeReactiveScopes.
fn (x &Virt) reactive_transforms() []Transform {
	mut out := []Transform{}
	ids := x.through_ids()
	for st in x.list(x.es.root, .body) {
		if x.typ(st) != .labeled_statement || x.name(x.node(st, .label)) != '\$' {
			continue
		}
		body := x.node(st, .body)
		if body >= 0 && x.typ(body) == .expression_statement {
			expr := x.node(body, .expression)
			if expr >= 0 && x.typ(expr) == .assignment_expression
				&& (x.es.string_of(expr, .operator) or { '' }) == '=' {
				left := x.node(expr, .left)
				if left >= 0 && x.typ(left) in [.identifier, .array_pattern, .object_pattern] {
					ln := x.es.nodes[left]
					if ids.any(ln.start <= x.es.nodes[it].start && x.es.nodes[it].end <= ln.end) {
						out << Transform{
							start: x.u(x.es.nodes[st].start)
							end:   x.u(x.es.nodes[st].end)
							kind:  0
							node:  st
							left:  left
						}
						continue
					}
				}
			}
		}
		out << Transform{
			start: x.u(x.es.nodes[st].start)
			end:   x.u(x.es.nodes[st].end)
			kind:  1
			node:  st
		}
	}
	return out
}

// derived_transforms is analyzeDollarDerivedScopes.
fn (x &Virt) derived_transforms() []Transform {
	mut out := []Transform{}
	if x.runes == .off {
		return out
	}
	for r in x.through {
		id := x.an.refs[r].id
		if x.name(id) != '\$derived' {
			continue
		}
		call := x.es.nodes[id].parent
		if call < 0 || x.typ(call) != .call_expression || x.node(call, .callee) != id {
			continue
		}
		args := x.list(call, .arguments)
		if args.len == 0 || x.typ(args[0]) == .spread_element {
			continue
		}
		out << Transform{
			start: x.u(x.es.nodes[call].start)
			end:   x.u(x.es.nodes[call].end)
			kind:  2
			node:  call
		}
	}
	return out
}

// bindable_transforms is analyzeBindableProps (TypeScript scripts: no JSDoc).
fn (x &Virt) bindable_transforms() []Transform {
	mut out := []Transform{}
	if x.runes == .off {
		return out
	}
	is_js := x.doc.lang == '' || x.doc.lang == 'js' || x.doc.lang == 'javascript'
	for st in x.list(x.es.root, .body) {
		if x.typ(st) != .variable_declaration {
			continue
		}
		for decl in x.list(st, .declarations) {
			id := x.node(decl, .id)
			if id < 0 || x.typ(id) != .object_pattern {
				continue
			}
			mut call := x.node(decl, .init)
			if call >= 0 && x.typ(call) == .ts_non_null_expression {
				call = x.node(call, .expression)
			}
			if call < 0 || x.typ(call) != .call_expression {
				continue
			}
			callee := x.node(call, .callee)
			if callee < 0 || x.typ(callee) != .identifier || x.name(callee) != '\$props'
				|| x.list(call, .arguments).len > 0 || x.node(call, .type_arguments) >= 0 {
				continue
			}
			if x.node(id, .type_annotation) < 0 && !(is_js && x.has_jsdoc_type(st)) {
				continue
			}
			mut keys := []string{}
			for prop in x.list(id, .properties) {
				if x.typ(prop) != .property {
					continue
				}
				value := x.node(prop, .value)
				if value < 0 || x.typ(value) != .assignment_pattern {
					continue
				}
				right := x.node(value, .right)
				if right < 0 || x.typ(right) != .call_expression {
					continue
				}
				rc := x.node(right, .callee)
				if rc < 0 || x.typ(rc) != .identifier || x.name(rc) != '\$bindable' {
					continue
				}
				if k := x.static_property_key(prop) {
					keys << k
				}
			}
			if keys.len == 0 {
				continue
			}
			out << Transform{
				start: x.u(x.es.nodes[call].start)
				end:   x.u(x.es.nodes[call].end)
				kind:  3
				node:  call
				keys:  keys
			}
		}
	}
	return out
}

// has_jsdoc_type is hasJSDocTypeComment: a `/** … @type {…} */` comment before the statement,
// with only comments between.
fn (x &Virt) has_jsdoc_type(st int) bool {
	pre := x.doc.pre
	mut end := x.es.nodes[st].start
	for k := x.comms.len - 1; k >= 0; k-- {
		cm := x.comms[k]
		if cm.end > end {
			continue
		}
		if !is_blank(pre[cm.end..end]) {
			return false
		}
		if cm.typ == 'Block' {
			value := pre[cm.start + 2..cm.end - 2]
			if value.starts_with('*') && has_type_tag(value) {
				return true
			}
		}
		end = cm.start
	}
	return false
}

// has_type_tag is /(?:^|[\s*])@type\s*\{/u.
fn has_type_tag(v string) bool {
	mut i := 0
	for {
		at := v.index_after('@type', i) or { return false }
		if at == 0 || is_space_at(v, at - 1) || v[at - 1] == `*` {
			mut k := at + 5
			for k < v.len && is_space_at(v, k) {
				_, n := code_point_at(v, k)
				k += n
			}
			if k < v.len && v[k] == `{` {
				return true
			}
		}
		i = at + 1
	}
	return false
}

fn (x &Virt) static_property_key(prop int) ?string {
	key := x.node(prop, .key)
	computed := x.es.flag(prop, .computed) or { false }
	match x.typ(key) {
		.identifier {
			if computed {
				return none
			}
			return x.name(key)
		}
		.literal {
			v := x.es.get(key, .value)
			if v is string {
				return v
			}
			if v is f64 {
				return js_number_string(v)
			}
			return none
		}
		.template_literal {
			quasis := x.list(key, .quasis)
			if x.list(key, .expressions).len == 0 && quasis.len == 1 {
				v := x.es.get(quasis[0], .value)
				if v is estree.TemplateValue {
					if v.has_cooked {
						return v.cooked
					}
				}
			}
			return none
		}
		else {
			return none
		}
	}
}

fn js_number_string(f f64) string {
	if f == f64(i64(f)) && f < 1e21 && f > -1e21 {
		return i64(f).str()
	}
	return f.str()
}

// apply is applyTransforms: by start, skipping a transform that starts inside the previous one.
fn (mut x Virt) apply(mut list []Transform) {
	list.sort_with_compare(fn (a &Transform, b &Transform) int {
		return a.start - b.start
	})
	mut offset := 0
	for t in list {
		if offset <= t.start {
			match t.kind {
				0 { x.transform_reactive_var(t) }
				1 { x.transform_reactive_statement(t) }
				2 { x.transform_derived(t) }
				else { x.transform_bindable(t) }
			}
		}
		offset = t.end
	}
}

fn (x &Virt) s(i int) int {
	return x.u(x.es.nodes[i].start)
}

fn (x &Virt) e(i int) int {
	return x.u(x.es.nodes[i].end)
}

// transform_reactive_var is transformForDeclareReactiveVar.
fn (mut x Virt) transform_reactive_var(t Transform) {
	st := t.node
	body := x.node(st, .body)
	expr := x.node(body, .expression)
	right := x.node(expr, .right)
	left := x.node(expr, .left)
	id := t.left
	mut open_parens := []SnipToken{}
	mut eq_end := -1
	mut close_parens := []SnipToken{}
	sn := x.es.nodes[st]
	for tok in x.toks {
		if tok.start >= sn.end {
			break
		}
		if tok.end <= sn.start {
			continue
		}
		text := x.doc.pre[tok.start..tok.end]
		if text == '(' && tok.end <= x.es.nodes[expr].start {
			open_parens << tok
		}
		if text == '=' && x.es.nodes[left].end <= tok.start && tok.end <= x.es.nodes[right].start {
			eq_end = tok.end
		}
		if text == ')' && x.es.nodes[expr].end <= tok.start {
			close_parens << tok
		}
	}
	function_id := x.v.unique_id('reactiveVariableScopeFunction')
	tmp_id := x.v.unique_id('tmpVar')
	for tok in open_parens {
		x.v.append_original(x.u(tok.start))
		x.v.skip_original(x.u(tok.end) - x.u(tok.start))
	}
	x.v.append_original(x.s(expr))
	x.v.skip_until(x.s(id))
	x.v.append_virtual('let ')
	x.v.append_original(if eq_end >= 0 { x.u(eq_end) } else { x.s(right) })
	x.v.append_virtual('${function_id}();\nfunction ${function_id}(){let ${tmp_id};return (${tmp_id} = ')
	x.v.append_original(x.e(right))
	x.v.append_virtual(')')
	for tok in close_parens {
		x.v.append_original(x.u(tok.start))
		x.v.skip_original(x.u(tok.end) - x.u(tok.start))
	}
	x.v.append_original(x.e(st))
	x.v.append_virtual('}')
}

// transform_reactive_statement is transformForReactiveStatement.
fn (mut x Virt) transform_reactive_statement(t Transform) {
	function_id := x.v.unique_id('reactiveStatementScopeFunction')
	body := x.node(t.node, .body)
	x.v.append_original(x.s(body))
	x.v.append_virtual('export function ${function_id}(){')
	x.v.append_original(x.e(body))
	x.v.append_virtual('}')
	x.v.append_original(x.e(t.node))
}

// transform_derived is transformForDollarDerived.
fn (mut x Virt) transform_derived(t Transform) {
	function_id := x.v.unique_id('\$derivedArgument')
	this_id := x.v.unique_id('\$This')
	arg := x.list(t.node, .arguments)[0]
	x.v.append_original(x.s(arg))
	x.v.append_virtual('(()=>{type ${this_id} = typeof this; return ${function_id}();function ${function_id}(this: ${this_id}){return ')
	x.v.append_original(x.e(arg))
	x.v.append_virtual('}})()')
}

// transform_bindable is transformForBindableProps.
fn (mut x Virt) transform_bindable(t Transform) {
	args := t.keys.map(json_quote(it)).join(',')
	x.v.append_original(x.e(t.node) - 1)
	x.v.append_virtual(args)
}
