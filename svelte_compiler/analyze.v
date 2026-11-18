module svelte_compiler

// phases/2-analyze/index.js: analyze_component and the warnings it emits, and the parts of
// compile() (index.js) before it. What only feeds code generation (expression metadata other
// than its presence, blockers, binding groups…) is not ported.

// Options are the compile options eslint-plugin-svelte gives (svelte.config.js is not read):
// `runes` undefined, `customElement` when <svelte:options> has `tag` or `customElement`,
// experimental.async off, generate false.
pub struct Options {
pub:
	custom_element bool
	// transpiled: the scripts were transpiled by TypeScript first (see Builder).
	transpiled bool
	// runes: the `runes` compiler option (-1 not given, 0 false, 1 true); async:
	// experimental.async.
	runes int = -1
	async bool
}

// Warning is a warning of the compiler: code, message and range (no_pos: none).
pub struct Warning {
pub:
	code    string
	message string
	start   int = no_pos
	end     int = no_pos
}

// Result is what compile() gives: its warnings, or the error it throws, and the mode.
pub struct Result {
pub:
	warnings []Warning
	error    ?CompileError
	runes    bool
}

struct StateField {
	node  int
	typ   string
	value int
}

struct ReactiveStatement {
mut:
	assignments  []int
	dependencies []int
}

// State is the analysis state of a walk (AnalysisState). JavaScript copies it with `{...state}`
// and mutates `has_props_rune` in place: that flag lives in a box (`props_box`) a copy gets anew.
struct State {
mut:
	scope                  int
	ast_type               string
	fragment               int = -1
	parent_element         string
	has_parent_element     bool
	in_declaration_tag     bool
	props_box              int
	component_slots        int
	expression             bool
	state_fields           int
	function_depth         int
	reactive_statement     int = -1
	derived_function_depth int = -1
}

@[heap]
pub struct Analyzer {
pub mut:
	t        &Tree
	c        &Component
	s        &Scopes
	sw       &ScopeWalk = unsafe { nil }
	opts     Options
	warnings []Warning
	// ignore_stack: the sets of ignored codes (only the top matters); ignore_map: the top when a
	// node was visited.
	ignore_stack [][]string
	ignore_map   map[int][]string
	path         []int
	// positions: the position of a node in a fragment (key: fragment << 32 | node), for the
	// fragments in positions_done (position_in).
	positions      map[u64]int
	positions_done map[int]bool
	// analysis
	runes                 bool
	maybe_runes           bool
	custom_element        bool
	custom_element_props  bool
	module_scope          int
	instance_scope        int
	template_scope        int
	module_ast            int
	instance_ast          int
	component_scopes      map[int]map[string]int
	props_boxes           []bool
	slot_sets             []map[string]bool
	state_field_maps      []map[string]StateField
	reactive_statements   []ReactiveStatement
	reactive_nodes        []int
	snippets              []int
	snippet_renderers     []int
	snippet_resolved      []bool
	event_directive_node  int = -1
	uses_event_attributes bool
	uses_slots            bool
	uses_render_tags      bool
	slot_names            map[string]int
	props_id              int = -1
	exports               []string
	elements              []int
	// element metadata
	meta_path   map[int][]int
	meta_svg    map[int]bool
	scoped      map[int]bool
	snippets_of map[int][]int
	sites       map[int][]int
	each_keyed  map[int]bool
	// CSS
	css_keyframes      []string
	css_used           map[int]bool
	css_rule           map[int]int
	css_parent         map[int]int
	css_global_block   map[int]bool
	css_has_global_sel map[int]bool
	css_has_local_sel  map[int]bool
	sel_global         map[int]bool
	sel_global_like    map[int]bool
	sel_scoped         map[int]bool
	cplx_global        map[int]bool
}

fn (mut z Analyzer) error_at(node int, d Diag) IError {
	if node < 0 {
		return compile_err(d, no_pos, no_pos)
	}
	return compile_err(d, z.t.nodes[node].start, z.t.nodes[node].end)
}

fn (mut z Analyzer) error_range(start int, end int, d Diag) IError {
	return compile_err(d, start, end)
}

// warn is warnings.js' w(node, …): ignored when the top of the ignore stack the node was
// visited with (or the current one) has the code.
fn (mut z Analyzer) warn(node int, d Diag) {
	mut top := if z.ignore_stack.len > 0 { z.ignore_stack.last() } else { []string{} }
	if node >= 0 {
		if snap := z.ignore_map[node] {
			top = snap.clone()
		}
	}
	if d.code in top {
		return
	}
	if node < 0 {
		z.warnings << Warning{
			code:    d.code
			message: d.message
		}
		return
	}
	n := z.t.nodes[node]
	z.warnings << Warning{
		code:    d.code
		message: d.message
		start:   n.start
		end:     if n.start == no_pos { no_pos } else { n.end }
	}
}

// warn_range warns at a range that is not a node (the current ignore stack applies).
fn (mut z Analyzer) warn_range(start int, end int, d Diag) {
	top := if z.ignore_stack.len > 0 { z.ignore_stack.last() } else { []string{} }
	if d.code in top {
		return
	}
	z.warnings << Warning{
		code:    d.code
		message: d.message
		start:   start
		end:     end
	}
}

fn (mut z Analyzer) push_ignore(ignores []string) {
	mut next := if z.ignore_stack.len > 0 { z.ignore_stack.last().clone() } else { []string{} }
	for i in ignores {
		if i !in next {
			next << i
		}
	}
	z.ignore_stack << next
}

fn (mut z Analyzer) pop_ignore() {
	z.ignore_stack.pop()
}

// extract_svelte_ignore is utils/extract_svelte_ignore.js: the codes a `svelte-ignore` comment
// names (warning about unknown and legacy codes in runes mode).
fn (mut z Analyzer) extract_svelte_ignore(offset int, text string, runes bool) []string {
	// /^\s*svelte-ignore\s/
	mut i := 0
	for i < text.len && is_js_space(text, i) {
		i += js_space_len(text, i)
	}
	if !text[i..].starts_with('svelte-ignore') {
		return []
	}
	i += 'svelte-ignore'.len
	if i >= text.len || !is_js_space(text, i) {
		return []
	}
	i += js_space_len(text, i)
	length := i
	start_offset := offset + length
	rest := text[length..]
	mut ignores := []string{}
	if runes {
		// /([\w$-]+)(,)?/gm: the codes up to the first one not followed by a comma.
		mut k := 0
		for k < rest.len {
			if !is_code_char(rest[k]) {
				k++
				continue
			}
			mut e := k
			for e < rest.len && is_code_char(rest[e]) {
				e++
			}
			code := rest[k..e]
			if code in warning_codes || code in ignorable_runtime_warnings {
				ignores << code
			} else {
				replacement := legacy_replacements[code] or { code.replace('-', '_') }
				start := start_offset + k
				end := start + code.len
				if replacement in warning_codes || replacement in ignorable_runtime_warnings {
					z.warn_range(start, end, w_legacy_code(code, replacement))
				} else {
					mut all := warning_codes.clone()
					all << ignorable_runtime_warnings
					z.warn_range(start, end, w_unknown_code(code, fuzzymatch(code, all)))
				}
			}
			if e >= rest.len || rest[e] != `,` {
				break
			}
			k = e + 1
		}
	} else {
		mut k := 0
		for k < rest.len {
			if !is_code_char(rest[k]) {
				k++
				continue
			}
			mut e := k
			for e < rest.len && is_code_char(rest[e]) {
				e++
			}
			code := rest[k..e]
			ignores << code
			if code !in warning_codes && code !in ignorable_runtime_warnings {
				replacement := legacy_replacements[code] or { code.replace('-', '_') }
				if replacement in warning_codes || replacement in ignorable_runtime_warnings {
					ignores << replacement
				}
			}
			k = e
		}
	}
	return ignores
}

const legacy_replacements = {
	'non-top-level-reactive-declaration': 'reactive_declaration_invalid_placement'
	'module-script-reactive-declaration': 'reactive_declaration_module_script'
	'empty-block':                        'block_empty'
	'avoid-is':                           'attribute_avoid_is'
	'invalid-html-attribute':             'attribute_invalid_property_name'
	'a11y-structure':                     'a11y_figcaption_parent'
	'illegal-attribute-character':        'attribute_illegal_colon'
	'invalid-rest-eachblock-binding':     'bind_invalid_each_rest'
	'unused-export-let':                  'export_let_unused'
}

fn is_code_char(c u8) bool {
	return (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`) || c == `_`
		|| c == `$` || c == `-`
}

// is_js_space: JavaScript's \s at a byte offset (ASCII white space, NBSP, BOM, the Unicode
// space separators, line and paragraph separators).
fn is_js_space(s string, i int) bool {
	c := s[i]
	if c in [` `, `\t`, `\n`, `\r`, `\v`, `\f`] {
		return true
	}
	if c < 0x80 {
		return false
	}
	r := utf8_rune_at(s, i)
	return r in [rune(0xa0), 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff]
		|| (r >= 0x2000 && r <= 0x200a)
}

fn js_space_len(s string, i int) int {
	return if s[i] < 0x80 { 1 } else { utf8_char_len(s[i]) }
}

fn utf8_rune_at(s string, i int) rune {
	n := utf8_char_len(s[i])
	if i + n > s.len {
		return rune(s[i])
	}
	return s[i..i + n].runes()[0]
}

// ---------------------------------------------------------------------------------------------

fn new_state(scope int, ast_type string) State {
	return State{
		scope:    scope
		ast_type: ast_type
	}
}

// copy_state is `{ ...state }`: has_props_rune gets a box of its own.
fn (mut z Analyzer) copy_state(st State) State {
	mut s := st
	z.props_boxes << z.props_boxes[st.props_box]
	s.props_box = z.props_boxes.len - 1
	return s
}

// analyze is compile() with `generate: false`: the warnings, or the error.
pub fn analyze(c &Component, opts Options) Result {
	mut z := &Analyzer{
		t:    &c.t
		c:    unsafe { c }
		s:    &Scopes{}
		opts: opts
	}
	for w in c.parse_warnings {
		d := match w.code {
			'element_implicitly_closed' { w_element_implicitly_closed(w.args[0], w.args[1]) }
			'svelte_element_invalid_this' { w_svelte_element_invalid_this() }
			else { w_script_unknown_attribute() }
		}
		z.warnings << Warning{
			code:    d.code
			message: d.message
			start:   w.start
			end:     w.end
		}
	}
	z.analyze_component() or {
		if err is CompileError {
			return Result{
				warnings: z.warnings
				error:    err
				runes:    z.runes
			}
		}
		return Result{
			warnings: z.warnings
			error:    CompileError{
				diag: Diag{
					code:    'internal'
					message: err.msg()
				}
			}
		}
	}
	return Result{
		warnings: z.warnings
		runes:    z.runes
	}
}

fn (mut z Analyzer) program_of(script int) int {
	if script < 0 {
		// An empty Program (start/end -1).
		p := z.t.new_node('Program', -1, -1)
		z.t.set_list(p, .body, [])
		return p
	}
	return z.t.get(script, .content)
}

fn (mut z Analyzer) analyze_component() ! {
	c := z.c
	z.module_ast = z.program_of(c.module)
	z.instance_ast = z.program_of(c.instance)
	m := z.create_scopes(z.module_ast, false, -1)!
	inst := z.create_scopes(z.instance_ast, true, m.scope)!
	z.module_scope = m.scope
	z.instance_scope = inst.scope
	tmpl := z.create_scopes(c.fragment, false, inst.scope)!
	z.template_scope = tmpl.scope

	runes_option := if z.options_runes() >= 0 { z.options_runes() } else { z.opts.runes }
	mut synthetic_checks := []int{}
	// create synthetic bindings for store subscriptions
	module_refs := z.s.scopes[m.scope].references.clone()
	for name, references in module_refs {
		if name.len == 0 || name[0] != `$` || name in ['$$props', '$$restProps', '$$slots'] {
			continue
		}
		if name == '$' || name[1] == `$` {
			return z.error_at(references[0].node, e_global_reference_invalid(name))
		}
		store_name := name[1..]
		declaration := z.s.get(inst.scope, store_name)
		init := if declaration >= 0 { z.s.bindings[declaration].initial } else { -1 }
		mut subscription := runes_option == 0 || !is_rune(name)
		if !subscription && declaration >= 0 {
			rname := z.get_rune(init, inst.scope)
			subscription = (rname == '' || (store_name != 'props' && rname == '$props'))
				&& !(name == '$derived' && z.t.typ(init) == 'ImportDeclaration'
					&& z.lit_value_str(z.t.get(init, .source)) == 'svelte/store')
		}
		if !subscription {
			continue
		}
		mut nested := -1
		search: for reference in references {
			for i := reference.path.len - 1; i >= 0; i-- {
				if scope := z.s.of[reference.path[i]] {
					owner := z.s.owner(scope, store_name)
					if owner >= 0 && owner != m.scope && owner != inst.scope {
						nested = reference.node
						break search
					}
					break
				}
			}
		}
		if nested >= 0 {
			return z.error_at(nested, e_store_invalid_scoped_subscription())
		}
		if runes_option != 0 {
			if declaration < 0 && store_name.len > 0 && store_name[0] >= `a` && store_name[0] <= `z` {
				return z.error_at(references[0].node, e_global_reference_invalid(name))
			} else if declaration >= 0 && is_rune(name) {
				for r in references {
					if r.path.len > 0 && z.t.typ(r.path.last()) == 'CallExpression' {
						z.warn(r.node, w_store_rune_conflict(store_name))
					}
				}
			}
		}
		if c.module >= 0 {
			mod_start := z.t.nodes[z.module_ast].start
			mod_end := z.t.nodes[z.module_ast].end
			for r in references {
				n := z.t.nodes[r.node]
				if n.start > mod_start && n.end < mod_end
					&& z.get_rune(if r.path.len > 0 { r.path.last() } else { -1 }, m.scope) == '' {
					return z.error_at(r.node, e_store_invalid_subscription())
				}
			}
		}
		if declaration >= 0 {
			synthetic_checks << declaration
		}
		binding := z.declare(inst.scope, z.t.id(name), 'store_sub', 'synthetic', -1)!
		z.s.bindings[binding].references = references
		z.s.scopes[inst.scope].references[name] = references
		z.s.scopes[m.scope].references.delete(name)
	}

	mut has_rune_ref := false
	for name, _ in z.s.scopes[m.scope].references {
		if is_rune(name) {
			has_rune_ref = true
			break
		}
	}
	runes := if runes_option >= 0 {
		runes_option == 1
	} else {
		m.has_await || inst.has_await || has_rune_ref
	}
	z.runes = runes
	if !runes {
		for d in synthetic_checks {
			b := z.s.bindings[d]
			if b.kind == 'normal' && b.declaration_kind == 'let' && b.reassigned {
				z.s.bindings[d].kind = 'state'
			}
		}
	}
	if runes && c.module >= 0 {
		for a in z.t.list(c.module, .attributes) {
			if z.t.name(a) == 'context' {
				z.warn(a, w_script_context_deprecated())
				break
			}
		}
	}
	ce_options := z.custom_element_options()
	z.custom_element = z.opts.custom_element || ce_options
	// Scope.generate for the component name: it only reserves a name.
	z.s.generate(m.scope, 'Component')

	// ignore_stack and ignore_map are reset (state.adjust).
	z.ignore_stack = []
	z.ignore_map = map[int][]string{}

	z.maybe_runes = !runes && runes_option != 0 && '\$\$props' !in z.s.scopes[m.scope].references
		&& '\$\$restProps' !in z.s.scopes[m.scope].references && !z.instance_has_legacy()

	if !runes {
		z.legacy_props()
		z.legacy_state()!
	}
	if c.options >= 0 {
		for a in z.t.list(c.options, .attributes) {
			name := z.t.name(a)
			if name == 'accessors' && runes {
				z.warn(a, w_options_deprecated_accessors())
			}
			if name == 'customElement' && !z.opts.custom_element {
				z.warn(a, w_options_missing_custom_element())
			}
			if name == 'immutable' && runes {
				z.warn(a, w_options_deprecated_immutable())
			}
		}
	}
	if runes {
		if refs := z.s.scopes[m.scope].references['\$\$props'] {
			return z.error_at(refs[0].node, e_legacy_props_invalid())
		}
		if refs := z.s.scopes[m.scope].references['\$\$restProps'] {
			return z.error_at(refs[0].node, e_legacy_rest_props_invalid())
		}
		z.walk_all()!
		// warn on any nonstate declarations that are a) reassigned and b) referenced in the template
		for scope in [m.scope, inst.scope] {
			decls := z.s.scopes[scope].declarations.clone()
			outer: for name, b in decls {
				binding := z.s.bindings[b]
				if binding.kind != 'normal' || !binding.reassigned {
					continue
				}
				inner: for r in binding.references {
					if r.path.len == 0 || z.t.typ(r.path[0]) != 'Fragment' {
						continue
					}
					for i := 1; i < r.path.len; i++ {
						typ := z.t.typ(r.path[i])
						if typ in ['FunctionDeclaration', 'FunctionExpression',
							'ArrowFunctionExpression'] {
							continue inner
						}
						if typ == 'BindDirective' && z.t.name(r.path[i]) == 'this' {
							for j := i - 1; j >= 0; j-- {
								if z.t.typ(r.path[j]) in ['IfBlock', 'EachBlock', 'AwaitBlock',
									'KeyBlock'] {
									z.warn(binding.node, w_non_reactive_update(name))
									continue outer
								}
							}
							continue inner
						}
					}
					z.warn(binding.node, w_non_reactive_update(name))
					continue outer
				}
			}
		}
	} else {
		z.declare(inst.scope, z.t.id('\$\$props'), 'rest_prop', 'synthetic', -1)!
		z.declare(inst.scope, z.t.id('\$\$restProps'), 'rest_prop', 'synthetic', -1)!
		z.walk_all()!
		decls := z.s.scopes[inst.scope].declarations.clone()
		for name, b in decls {
			binding := z.s.bindings[b]
			if (binding.kind == 'prop' || binding.kind == 'bindable_prop')
				&& z.t.name(binding.node) != '\$\$props' {
				mut used := false
				for r in binding.references {
					if r.node != binding.node
						&& (r.path.len == 0 || z.t.typ(r.path.last()) != 'ExportSpecifier') {
						used = true
						break
					}
				}
				if !used && '\$${name}' !in z.s.scopes[inst.scope].declarations {
					z.warn(binding.node, w_export_let_unused(name))
				}
			}
		}
		z.order_reactive_statements()!
	}
	for node in z.t.list(z.module_ast, .body) {
		if z.t.typ(node) == 'ExportNamedDeclaration' && z.t.get(node, .source) < 0 {
			for spec in z.t.list(node, .specifiers) {
				local := z.t.get(spec, .local)
				if z.t.typ(local) != 'Identifier' {
					continue
				}
				name := z.t.name(local)
				if z.s.get(m.scope, name) < 0 {
					for snippet in z.snippets {
						if z.t.name(z.t.get(snippet, .expression)) == name {
							return z.error_at(spec, e_snippet_invalid_export())
						}
					}
					return z.error_at(spec, e_export_undefined(name))
				}
			}
		}
	}
	if z.event_directive_node >= 0 && z.uses_event_attributes {
		return z.error_at(z.event_directive_node, e_mixed_event_handler_syntaxes(z.t.name(z.event_directive_node)))
	}
	for k, node in z.snippet_renderers {
		if !z.snippet_resolved[k] {
			z.snippets_of[node] = z.snippets.clone()
		}
		for snippet in z.snippets_of[node] or { []int{} } {
			mut sites := z.sites[snippet] or { []int{} }
			if node !in sites {
				sites << node
			}
			z.sites[snippet] = sites
		}
	}
	if z.uses_render_tags && (z.uses_slots || (!z.custom_element && z.slot_names.len > 0)) {
		for _, v in z.slot_names {
			return z.error_at(v, e_slot_snippet_conflict())
		}
		pos := z.c.src.index('\$\$slot') or { -1 }
		return z.error_range(pos, pos, e_slot_snippet_conflict())
	}
	if c.css >= 0 {
		z.analyze_css()!
		z.prune()
		if !z.css_ignored() {
			z.warn_unused()
		}
	}
}

// options_runes: <svelte:options runes> (1 true, 0 false, -1 not given).
fn (z &Analyzer) options_runes() int {
	if z.c.options < 0 {
		return -1
	}
	for a in z.t.list(z.c.options, .attributes) {
		if z.t.typ(a) == 'Attribute' && z.t.name(a) == 'runes' {
			if z.t.attr_is_true(a) {
				return 1
			}
			e := z.t.get_attribute_expression(a)
			if z.t.typ(e) == 'Literal' && z.t.lit_kind(e) == .boolean {
				return if z.t.flag(e, .value) { 1 } else { 0 }
			}
			return 1
		}
	}
	return -1
}

// custom_element_options: <svelte:options customElement> gives customElementOptions (and
// whether they have `props`).
fn (mut z Analyzer) custom_element_options() bool {
	if z.c.options < 0 {
		return false
	}
	for a in z.t.list(z.c.options, .attributes) {
		if z.t.typ(a) != 'Attribute' || z.t.name(a) != 'customElement' {
			continue
		}
		if z.t.is_text_attribute(a) {
			return true
		}
		e := z.t.get_attribute_expression(a)
		if z.t.typ(e) == 'ObjectExpression' {
			for p in z.t.list(e, .properties) {
				if z.t.typ(p) == 'Property' && z.t.name(z.t.get(p, .key)) == 'props' {
					z.custom_element_props = true
				}
			}
			return true
		}
		return false
	}
	return false
}

fn (z &Analyzer) lit_value_str(n int) string {
	if z.t.typ(n) == 'Literal' && z.t.lit_kind(n) == .string {
		return z.t.text(n, .value)
	}
	return ''
}

// instance_has_legacy: a `$:` or an `export let` in the instance script (maybe_runes).
fn (z &Analyzer) instance_has_legacy() bool {
	for node in z.t.list(z.instance_ast, .body) {
		typ := z.t.typ(node)
		if typ == 'LabeledStatement' {
			return true
		}
		if typ == 'ExportNamedDeclaration' {
			decl := z.t.get(node, .declaration)
			if decl >= 0 && z.t.typ(decl) == 'VariableDeclaration' && z.t.text(decl, .kind) == 'let' {
				return true
			}
			for spec in z.t.list(node, .specifiers) {
				local := z.t.get(spec, .local)
				if z.t.typ(local) == 'Identifier' {
					b := z.s.get(z.instance_scope, z.t.name(local))
					if b >= 0 && z.s.bindings[b].declaration_kind == 'let' {
						return true
					}
				}
			}
		}
	}
	return false
}

// legacy_props: every exported `let` or `var` declaration becomes a prop.
fn (mut z Analyzer) legacy_props() {
	for node in z.t.list(z.instance_ast, .body) {
		if z.t.typ(node) != 'ExportNamedDeclaration' {
			continue
		}
		decl := z.t.get(node, .declaration)
		if decl >= 0 {
			if z.t.typ(decl) == 'VariableDeclaration' && z.t.text(decl, .kind) != 'const' {
				for d in z.t.list(decl, .declarations) {
					for id in z.t.extract_identifiers(z.t.get(d, .id)) {
						b := z.s.get(z.instance_scope, z.t.name(id))
						if b >= 0 {
							z.s.bindings[b].kind = 'bindable_prop'
						}
					}
				}
			}
		} else {
			for spec in z.t.list(node, .specifiers) {
				local := z.t.get(spec, .local)
				exported := z.t.get(spec, .exported)
				if z.t.typ(local) != 'Identifier' || z.t.typ(exported) != 'Identifier' {
					continue
				}
				b := z.s.get(z.instance_scope, z.t.name(local))
				if b >= 0 && z.s.bindings[b].declaration_kind in ['var', 'let'] {
					z.s.bindings[b].kind = 'bindable_prop'
					if z.t.name(exported) != z.t.name(local) {
						z.s.bindings[b].prop_alias = z.t.name(exported)
						z.s.bindings[b].has_prop_alias = true
					}
				}
			}
		}
	}
}

// legacy_state: reassigned/mutated bindings referenced in `$:` blocks or the template become
// state; so do the bindings an `each` block's expression reads when its items are updated.
fn (mut z Analyzer) legacy_state() ! {
	decls := z.s.scopes[z.instance_scope].declarations.clone()
	for _, b in decls {
		binding := z.s.bindings[b]
		if binding.kind != 'normal' {
			continue
		}
		for r in binding.references {
			if r.node == binding.node {
				continue
			}
			if binding.updated() {
				mut in_fragment := false
				for p in r.path {
					if z.t.typ(p) == 'Fragment' {
						in_fragment = true
						break
					}
				}
				if (r.path.len > 0 && z.t.typ(r.path.last()) == 'StyleDirective') || in_fragment
					|| (r.path.len > 1 && z.t.typ(r.path[1]) == 'LabeledStatement'
						&& z.t.name(z.t.get(r.path[1], .label)) == '$') {
					z.s.bindings[b].kind = 'state'
				}
			}
		}
	}
	z.legacy_each(z.c.fragment)
}

fn (mut z Analyzer) legacy_each(node int) {
	if z.t.typ(node) == 'EachBlock' {
		scope := z.s.of[node]
		for _, b in z.s.scopes[scope].declarations {
			if z.s.bindings[b].updated() {
				z.legacy_each_mark(z.t.get(node, .expression), -1, z.s.scopes[scope].parent)
				break
			}
		}
	}
	for ch in z.t.children(node) {
		z.legacy_each(ch)
	}
}

fn (mut z Analyzer) legacy_each_mark(node int, parent int, scope int) {
	mut sc := scope
	if s := z.s.of[node] {
		sc = s
	}
	if z.t.typ(node) == 'Identifier' {
		if parent < 0 || z.t.is_reference(node, parent) {
			b := z.s.get(sc, z.t.name(node))
			if b >= 0 && z.s.bindings[b].kind == 'normal'
				&& z.s.bindings[b].declaration_kind !in ['import', 'function'] {
				z.s.bindings[b].kind = 'state'
				z.s.bindings[b].mutated = true
			}
		}
		return
	}
	for ch in z.t.children(node) {
		z.legacy_each_mark(ch, node, sc)
	}
}

// css_ignored: a `svelte-ignore css_unused_selector` comment before the <style>.
fn (mut z Analyzer) css_ignored() bool {
	cm := z.c.style_comment
	if cm < 0 {
		return false
	}
	return 'css_unused_selector' in z.extract_svelte_ignore(z.t.nodes[cm].start, z.t.text(cm,
		.data), z.runes)
}
