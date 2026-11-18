module svelte_compiler

import estree
import svelte

// Component is a .svelte file as the compiler's analysis gets it: the template (a Fragment),
// the instance and module scripts (Script nodes whose `content` is a Program), the <style>
// (a StyleSheet, see css_parse.v) and <svelte:options>, in one Tree.
@[heap]
pub struct Component {
pub mut:
	t        Tree
	src      string
	fragment int = -1
	instance int = -1
	module   int = -1
	css      int = -1
	options  int = -1
	ts       bool
	// parse_warnings: the warnings of the parse phase (svelte/compiler.v).
	parse_warnings []svelte.CWarning
	// misses: template expressions without an ESTree node in the Document (a bug if not 0).
	misses int
	// style_comment: the Comment right before the <style> (content.comment), -1 if none.
	style_comment int = -1
	// css_content_start / css_content_end: the range of the <style>'s content.
	css_content_start int
	css_content_end   int
}

// CompileError is an error of the compiler (what `compile()` throws): its diagnostic and range
// (no_pos when it has none).
pub struct CompileError {
	Error
pub:
	diag  Diag
	start int = no_pos
	end   int = no_pos
}

pub fn (e CompileError) msg() string {
	return e.diag.message
}

fn compile_err(d Diag, start int, end int) IError {
	return CompileError{
		diag:  d
		start: start
		end:   end
	}
}

// Builder converts a svelte.Document (the compiler's template AST and the ESTree of the scripts
// and template expressions) into a Component.
struct Builder {
mut:
	c  &Component
	ca &svelte.CAst
	es &estree.EsTree
	// by_range: the ESTree nodes by their range (start << 32 | end).
	by_range map[u64][]int
	// transpiled: the scripts are what TypeScript's transpileModule gives (eslint-plugin-svelte
	// compiles that): TypeScript-only constructs are erased instead of rejected.
	transpiled bool
	// opaque: inside an import or `export default`/`export *` declaration, whose children
	// remove_typescript_nodes does not visit (no TypeScript error comes from them).
	opaque int
	// parse_errs: the errors of the parse phase found while building (the first in the source
	// wins, as the parser stops at it); ts_err: the first error of remove_typescript_nodes
	// (which runs after parsing).
	parse_errs []CompileError
	ts_err     ?CompileError
	// es5: the TypeScript target is ES5 (es5.v); in_script: building a <script>'s statements.
	es5       bool
	es5_temps int
	in_script bool
}

fn (mut b Builder) ts_fail(d Diag, start int, end int) {
	if b.ts_err == none {
		b.ts_err = CompileError{
			diag:  d
			start: start
			end:   end
		}
	}
}

fn (mut b Builder) parse_fail(e ?CompileError) {
	if err := e {
		b.parse_errs << err
	}
}

// build_component builds the Component of a parsed .svelte file. `transpiled`: see Builder.
pub fn build_component(doc &svelte.Document, transpiled bool) !&Component {
	return build_component_with(doc, transpiled, false)
}

// build_component_with: `es5`, the scripts are transpiled for an ES5 target (es5.v).
pub fn build_component_with(doc &svelte.Document, transpiled bool, es5 bool) !&Component {
	mut c := &Component{
		src: doc.src
		ts:  doc.cast.ts
	}
	c.parse_warnings = doc.cast.warnings
	mut b := Builder{
		c:          c
		ca:         &doc.cast
		es:         &doc.es
		transpiled: transpiled
		es5:        transpiled && es5
	}
	for i, n in doc.es.nodes {
		key := (u64(u32(n.start)) << 32) | u64(u32(n.end))
		b.by_range[key] << i
	}
	for cm in doc.comments {
		c.t.comments << Comment{
			block: cm.typ == 'Block'
			start: cm.start
			end:   cm.end
			value: cm.value
		}
	}
	ca := b.ca
	// A self-closing top-level <script /> or <style />: the compiler's parser wants `>` where
	// svelte-eslint-parser accepts the `/`.
	for blk in [ca.instance, ca.module, ca.css] {
		if blk < 0 {
			continue
		}
		bn := ca.nodes[blk]
		mut pos := bn.start + 1 + (if bn.typ == .script { 6 } else { 5 })
		if bn.attributes.len > 0 {
			pos = ca.nodes[bn.attributes.last()].end
		}
		for pos < c.src.len && c.src[pos] in [` `, `\t`, `\n`, `\r`] {
			pos++
		}
		if pos < c.src.len && c.src[pos] == `/` {
			b.parse_errs << CompileError{
				diag:  e_expected_token('>')
				start: pos
				end:   pos
			}
		}
	}
	c.fragment = b.fragment(ca.fragment, false)!
	for n in c.t.list(c.fragment, .nodes) {
		// svelte-eslint-parser hands the compiler a self-closing <script/> or <style/> renamed
		// (`<s---- />`): an element for svelte/.
		nname := c.t.name(n)
		if c.t.typ(n) == 'RegularElement' && nname.len >= 2 && nname[0] == `s`
			&& nname[1..].trim_left('-') == '' && (c.src[c.t.nodes[n].start + 1..].starts_with('script')
			|| c.src[c.t.nodes[n].start + 1..].starts_with('style')) && c.t.nodes[n].end >= 2
			&& c.src[c.t.nodes[n].end - 2] == `/` {
			pos := c.t.nodes[n].end - 2
			b.parse_errs << CompileError{
				diag:  e_expected_token('>')
				start: pos
				end:   pos
			}
		}
	}
	if ca.instance >= 0 {
		c.instance = b.script(ca.instance)!
	}
	if ca.module >= 0 {
		c.module = b.script(ca.module)!
	}
	if ca.options >= 0 {
		c.options = b.template_node(ca.options)!
	}
	if ca.css >= 0 {
		css := ca.nodes[ca.css]
		c.style_comment = b.prev_comment(css.start)
		c.css = b.stylesheet(css) or {
			if err is CompileError {
				b.parse_errs << err
				-1
			} else {
				return err
			}
		}
	}
	for script in [c.instance, c.module] {
		if script < 0 {
			continue
		}
		cm := b.prev_comment(c.t.nodes[script].start)
		if cm >= 0 {
			// The Program gets a fake leading comment with the HTML comment's data (element.js).
			c.t.comments << Comment{
				block: false
				start: no_pos
				end:   no_pos
				value: c.t.text(cm, .data)
			}
			prog := c.t.get(script, .content)
			c.t.nodes[prog].leading = [c.t.comments.len - 1]
		}
	}
	// The parser stops at its first error; read_options runs at its end; then
	// remove_typescript_nodes.
	if b.parse_errs.len > 0 {
		mut first := b.parse_errs[0]
		for e in b.parse_errs {
			if e.start < first.start {
				first = e
			}
		}
		return first
	}
	b.validate_options()!
	if e := b.ts_err {
		return e
	}
	return c
}

// prev_comment is the Comment that ends a run of white-space Text nodes right before a
// top-level <script> or <style> starting at `start` (element.js' prev_comment), -1 if none.
fn (b &Builder) prev_comment(start int) int {
	t := &b.c.t
	mut before := []int{}
	for n in t.list(b.c.fragment, .nodes) {
		if t.nodes[n].start < start {
			before << n
		}
	}
	for i := before.len - 1; i >= 0; i-- {
		n := before[i]
		if i == before.len - 1 && t.nodes[n].end != start {
			break
		}
		if t.typ(n) == 'Comment' {
			return n
		} else if t.typ(n) != 'Text' || t.text(n, .data).trim_space() != '' {
			break
		}
	}
	return -1
}

// ---------------------------------------------------------------------------------------------
// Template.

fn (mut b Builder) fragment(f int, transparent bool) !int {
	i := b.c.t.new_node('Fragment', no_pos, no_pos)
	mut nodes := []int{}
	for n in b.ca.fragments[f] {
		nodes << b.template_node(n)!
	}
	b.c.t.set_list(i, .nodes, nodes)
	b.c.t.set_flag(i, .transparent, transparent)
	return i
}

fn (mut b Builder) opt_fragment(f int) !int {
	return if f < 0 { -1 } else { b.fragment(f, false)! }
}

fn (mut b Builder) template_node(n int) !int {
	cn := b.ca.nodes[n]
	typ := cn.typ.name()
	i := b.c.t.new_node(typ, cn.start, cn.end)
	match cn.typ {
		.text {
			b.c.t.set_str(i, .data, cn.data)
			b.c.t.set_str(i, .raw, cn.raw)
		}
		.comment {
			b.c.t.set_str(i, .data, cn.data)
		}
		.expression_tag, .html_tag, .render_tag, .attach_tag, .spread_attribute {
			b.c.t.set_node(i, .expression, b.expr(cn.expression)!)
		}
		.debug_tag {
			mut ids := []int{}
			for e in cn.identifiers {
				ids << b.expr(e)!
			}
			b.c.t.set_list(i, .identifiers, ids)
		}
		.const_tag {
			id := b.expr(cn.decl_id)!
			init := b.expr(cn.decl_init)!
			decl := b.c.t.new_node('VariableDeclaration', cn.decl_start, cn.decl_end)
			b.c.t.set_str(decl, .kind, 'const')
			d := b.c.t.new_node('VariableDeclarator', b.c.t.nodes[id].start, b.c.t.nodes[init].end)
			b.c.t.set_node(d, .id, id)
			b.c.t.set_node(d, .init, init)
			b.c.t.set_list(decl, .declarations, [d])
			b.c.t.set_node(i, .declaration, decl)
		}
		.declaration_tag {
			b.c.t.set_node(i, .declaration, b.declaration(cn.decl_start, cn.decl_end)!)
		}
		.if_block {
			b.c.t.set_flag(i, .elseif, cn.elseif)
			b.c.t.set_node(i, .test, b.expr(cn.expression)!)
			b.c.t.set_node(i, .consequent, b.fragment(cn.consequent, false)!)
			b.c.t.set_node(i, .alternate, b.opt_fragment(cn.alternate)!)
		}
		.each_block {
			b.c.t.set_node(i, .expression, b.expr(cn.expression)!)
			b.c.t.set_node(i, .body, b.fragment(cn.body, false)!)
			context := if cn.context >= 0 { b.expr(cn.context)! } else { -1 }
			b.c.t.set_node(i, .context, context)
			if context >= 0 {
				b.parse_fail(b.check_pattern(context))
			}
			if cn.has_index {
				b.c.t.set_str(i, .index, cn.index)
			}
			if cn.key >= 0 {
				b.c.t.set_node(i, .key, b.expr(cn.key)!)
			}
			if cn.fallback >= 0 {
				b.c.t.set_node(i, .fallback, b.fragment(cn.fallback, false)!)
			}
		}
		.await_block {
			b.c.t.set_node(i, .expression, b.expr(cn.expression)!)
			value := if cn.await_value >= 0 { b.expr(cn.await_value)! } else { -1 }
			err_pat := if cn.await_error >= 0 { b.expr(cn.await_error)! } else { -1 }
			b.c.t.set_node(i, .value, value)
			b.c.t.set_node(i, .error, err_pat)
			for pat in [value, err_pat] {
				if pat >= 0 {
					b.parse_fail(b.check_pattern(pat))
				}
			}
			b.c.t.set_node(i, .pending, b.opt_fragment(cn.pending)!)
			b.c.t.set_node(i, .then, b.opt_fragment(cn.then)!)
			b.c.t.set_node(i, .catch_, b.opt_fragment(cn.catch_)!)
		}
		.key_block {
			b.c.t.set_node(i, .expression, b.expr(cn.expression)!)
			b.c.t.set_node(i, .fragment, b.fragment(cn.body, false)!)
		}
		.snippet_block {
			b.c.t.set_node(i, .expression, b.expr(cn.expression)!)
			mut params := []int{}
			for e in cn.parameters {
				pat := b.expr(e)!
				b.parse_fail(b.check_pattern(pat))
				params << pat
			}
			b.c.t.set_list(i, .parameters, params)
			b.c.t.set_node(i, .body, b.fragment(cn.body, false)!)
		}
		.attribute {
			b.c.t.set_str(i, .name, cn.name)
			b.attr_value(i, cn)!
		}
		.style_directive {
			b.c.t.set_str(i, .name, cn.name)
			b.attr_value(i, cn)!
			b.c.t.set(i, P{
				key:  .modifiers
				kind: .strs
				strs: cn.modifiers
			})
		}
		.bind_directive, .on_directive, .class_directive, .transition_directive,
		.animate_directive,
		.use_directive, .let_directive {
			b.c.t.set_str(i, .name, cn.name)
			b.c.t.set_node(i, .expression, if cn.expression >= 0 {
				b.expr(cn.expression)!
			} else {
				-1
			})
			b.c.t.set(i, P{
				key:  .modifiers
				kind: .strs
				strs: cn.modifiers
			})
			if cn.typ == .transition_directive {
				b.c.t.set_flag(i, .intro, cn.intro)
				b.c.t.set_flag(i, .outro, cn.outro)
			}
		}
		else {
			if cn.typ.is_element() || cn.typ == .svelte_options {
				b.c.t.set_str(i, .name, cn.name)
				if cn.typ == .svelte_element && cn.expression >= 0 {
					b.c.t.set_node(i, .tag, b.expr(cn.expression)!)
				}
				if cn.typ == .svelte_component && cn.expression >= 0 {
					b.c.t.set_node(i, .expression, b.expr(cn.expression)!)
				}
				mut attrs := []int{}
				for a in cn.attributes {
					attrs << b.template_node(a)!
				}
				b.c.t.set_list(i, .attributes, attrs)
				if cn.fragment >= 0 {
					b.c.t.set_node(i, .fragment, b.fragment(cn.fragment, cn.typ != .svelte_options)!)
				}
			}
		}
	}
	return i
}

// attr_value sets the `value` of an Attribute or StyleDirective: true, one ExpressionTag, or a
// list of Text and ExpressionTag nodes.
fn (mut b Builder) attr_value(i int, cn svelte.CNode) ! {
	match cn.value_kind {
		.true_ {
			b.c.t.set_flag(i, .value, true)
		}
		.node {
			b.c.t.set_node(i, .value, b.template_node(cn.value[0])!)
		}
		.array {
			mut vs := []int{}
			for v in cn.value {
				vs << b.template_node(v)!
			}
			b.c.t.set_list(i, .value, vs)
		}
		.none {}
	}
}

fn (mut b Builder) script(s int) !int {
	cn := b.ca.nodes[s]
	i := b.c.t.new_node('Script', cn.start, cn.end)
	b.c.t.set_str(i, .context, if cn.script_module { 'module' } else { 'default' })
	mut attrs := []int{}
	for a in cn.attributes {
		attrs << b.template_node(a)!
	}
	b.c.t.set_list(i, .attributes, attrs)
	prog := b.c.t.new_node('Program', cn.content_start, cn.content_end)
	mut body := []int{}
	b.in_script = true
	defer {
		b.in_script = false
	}
	if b.es.root >= 0 {
		for st in b.es.list(b.es.root, .body) or { []int{} } {
			n := b.es.nodes[st]
			if n.start >= cn.content_start && n.end <= cn.content_end {
				body << b.js(st)!
			}
		}
	}
	b.c.t.set_list(prog, .body, body)
	b.c.t.set_node(i, .content, prog)
	b.parse_fail(check_redeclarations(b.c.t, prog))
	b.attach_comments(prog, cn.content_start, cn.content_end, true)
	return i
}

// ---------------------------------------------------------------------------------------------
// Expressions: the ESTree node of a CExpr is the outermost expression or pattern of
// Document.es with its range.

fn (b &Builder) find_es(start int, end int, want string) int {
	key := (u64(u32(start)) << 32) | u64(u32(end))
	cands := b.by_range[key] or { return -1 }
	mut best := -1
	mut best_depth := 0
	for cand in cands {
		typ := b.es.nodes[cand].typ.type_name()
		if want != '' {
			if typ != want {
				continue
			}
		} else if typ == 'Program' || typ.ends_with('Statement') || typ.ends_with('Declaration')
			|| typ == 'VariableDeclarator' {
			continue
		}
		mut depth := 0
		mut p := b.es.nodes[cand].parent
		for p >= 0 {
			depth++
			p = b.es.nodes[p].parent
		}
		if best < 0 || depth < best_depth {
			best = cand
			best_depth = depth
		}
	}
	return best
}

fn (mut b Builder) expr(e int) !int {
	if e < 0 {
		return -1
	}
	ce := b.ca.exprs[e]
	if !ce.synthetic {
		mut found := b.find_es(ce.start, ce.end, '')
		if found < 0 && ce.ann_end > ce.end {
			// A pattern with a type annotation: typescript-estree's node covers it.
			found = b.find_es(ce.start, ce.ann_end, '')
		}
		if found >= 0 {
			i := b.js(found)!
			b.attach_comments(i, b.read_start(ce.start), ce.end, false)
			b.parse_fail(check_redeclarations(b.c.t, i))
			return i
		}
		b.c.misses++
	}
	// Made by the compiler (bind:x / class:x without value, this="…"), or not found.
	if ce.kind == .literal {
		i := b.c.t.new_node('Literal', ce.start, ce.end)
		b.c.t.set_str(i, .value, ce.name)
		b.c.t.set_str(i, .raw, ce.raw)
		return i
	}
	i := b.c.t.new_node('Identifier', ce.start, ce.end)
	b.c.t.set_str(i, .name, ce.name)
	return i
}

// read_start: where acorn starts reading an expression (the comments from there on are its):
// back over the white space and comments before it.
fn (b &Builder) read_start(start int) int {
	src := b.c.src
	mut i := start
	for i > 0 {
		c := src[i - 1]
		if c in [` `, `\t`, `\n`, `\r`] {
			i--
			continue
		}
		mut moved := false
		for cm in b.c.t.comments {
			if cm.end == i {
				i = cm.start
				moved = true
				break
			}
		}
		if !moved {
			break
		}
	}
	return i
}

fn (mut b Builder) declaration(start int, end int) !int {
	found := b.find_es(start, end, 'VariableDeclaration')
	if found >= 0 {
		return b.js(found)!
	}
	b.c.misses++
	i := b.c.t.new_node('VariableDeclaration', start, end)
	b.c.t.set_str(i, .kind, 'let')
	b.c.t.set_list(i, .declarations, [])
	return i
}

// ---------------------------------------------------------------------------------------------
// JavaScript: typescript-estree's nodes converted to acorn's, TypeScript removed as
// remove_typescript_nodes does.

const es_keys = {
	'alternate':    Key.alternate
	'argument':     Key.argument
	'arguments':    Key.arguments
	'block':        Key.block
	'body':         Key.body
	'callee':       Key.callee
	'cases':        Key.cases
	'consequent':   Key.consequent
	'declaration':  Key.declaration
	'declarations': Key.declarations
	'discriminant': Key.discriminant
	'elements':     Key.elements
	'exported':     Key.exported
	'expression':   Key.expression
	'expressions':  Key.expressions
	'finalizer':    Key.finalizer
	'handler':      Key.handler
	'id':           Key.id
	'imported':     Key.imported
	'init':         Key.init
	'key':          Key.key
	'label':        Key.label
	'left':         Key.left
	'local':        Key.local
	'meta':         Key.meta
	'object':       Key.object
	'options':      Key.options
	'param':        Key.param
	'params':       Key.params
	'properties':   Key.properties
	'property':     Key.property
	'quasi':        Key.quasi
	'quasis':       Key.quasis
	'right':        Key.right
	'source':       Key.source
	'specifiers':   Key.specifiers
	'superClass':   Key.super_class
	'tag':          Key.tag
	'test':         Key.test
	'update':       Key.update
	'value':        Key.value
	'name':         Key.name
	'operator':     Key.operator
	'kind':         Key.kind
	'computed':     Key.computed
	'shorthand':    Key.shorthand
	'method':       Key.method
	'static':       Key.static_
	'prefix':       Key.prefix
	'optional':     Key.optional
	'async':        Key.async
	'generator':    Key.generator
	'delegate':     Key.delegate
	'raw':          Key.raw
	'tail':         Key.tail
	'declare':      Key.declare
	'importKind':   Key.import_kind
	'exportKind':   Key.export_kind
	'abstract':     Key.abstract_
	'accessor':     Key.accessor
}

// quiet: TypeScript features are not rejected (see transpiled and opaque).
fn (b &Builder) quiet() bool {
	return b.transpiled || b.opaque > 0
}

fn (mut b Builder) empty() int {
	return b.c.t.new_node('EmptyStatement', no_pos, no_pos)
}

fn (b &Builder) es_type(i int) string {
	return b.es.nodes[i].typ.type_name()
}

fn (mut b Builder) js(e int) !int {
	if e < 0 {
		return -1
	}
	n := b.es.nodes[e]
	typ := n.typ.type_name()
	match typ {
		'TSAsExpression', 'TSSatisfiesExpression', 'TSNonNullExpression', 'TSTypeAssertion',
		'TSInstantiationExpression' {
			return b.js(b.es.node(e, .expression) or { -1 })!
		}
		'TSInterfaceDeclaration', 'TSTypeAliasDeclaration', 'TSDeclareFunction' {
			return b.empty()
		}
		'TSEnumDeclaration' {
			if !b.quiet() {
				b.ts_fail(e_typescript_invalid_feature('enums'), n.start, n.end)
				return b.empty()
			}
			if b.transpiled && b.in_script {
				return b.transpiled_enum(e)!
			}
			return b.empty()
		}
		'TSModuleDeclaration' {
			if !b.quiet() {
				body := b.es.node(e, .body) or { -1 }
				if body >= 0 {
					for st in b.es.list(body, .body) or { []int{} } {
						r := b.js(st)!
						if r >= 0 && b.c.t.typ(r) != 'EmptyStatement' {
							b.ts_fail(e_typescript_invalid_feature('namespaces with non-type nodes'), n.start, n.end)
						}
					}
				}
			}
			return b.empty()
		}
		'TSParameterProperty' {
			if !b.quiet() && (b.es.flag(e, .readonly) or { false }
				|| b.es.string_of(e, .accessibility) or { '' } != '') {
				b.ts_fail(e_typescript_invalid_feature('accessibility modifiers on constructor parameters'), n.start, n.end)
			}
			return b.js(b.es.node(e, .parameter) or { -1 })!
		}
		'TSAbstractMethodDefinition', 'TSIndexSignature', 'TSAbstractAccessorProperty' {
			return b.empty()
		}
		'Decorator' {
			if b.quiet() {
				return b.empty()
			}
			b.ts_fail(e_typescript_invalid_feature('decorators (related TSC proposal is not stage 4 yet)'),
				n.start, n.end)
			return b.empty()
		}
		'AccessorProperty' {
			if !b.quiet() {
				b.ts_fail(e_typescript_invalid_feature('accessor fields (related TSC proposal is not stage 4 yet)'),
					n.start, n.end)
			}
		}
		else {}
	}
	if typ == 'ImportDeclaration' && b.es.string_of(e, .import_kind) or { '' } == 'type' {
		return b.empty()
	}
	if typ in ['ExportNamedDeclaration', 'ExportDefaultDeclaration', 'ExportAllDeclaration']
		&& b.es.string_of(e, .export_kind) or { '' } == 'type' {
		return b.empty()
	}
	if typ in ['VariableDeclaration', 'ClassDeclaration'] && b.es.flag(e, .declare_) or { false } {
		return b.empty()
	}
	if typ == 'MethodDefinition' {
		value := b.es.node(e, .value) or { -1 }
		if value >= 0 && b.es_type(value) == 'TSEmptyBodyFunctionExpression' {
			// An overload signature: acorn-typescript does not keep it.
			return b.empty()
		}
	}
	opaque := typ in ['ImportDeclaration', 'ExportDefaultDeclaration', 'ExportAllDeclaration']
	if opaque {
		b.opaque++
	}
	defer {
		if opaque {
			b.opaque--
		}
	}
	mut start := n.start
	mut end := n.end
	if typ == 'TemplateElement' {
		// typescript-estree's TemplateElement includes its delimiters, acorn's does not.
		start++
		end -= if b.es.flag(e, .tail) or { false } { 1 } else { 2 }
	}
	out_typ := match typ {
		'TSAbstractPropertyDefinition', 'AccessorProperty' { 'PropertyDefinition' }
		else { typ }
	}
	i := b.c.t.new_node(out_typ, start, end)
	for p in n.props {
		name := p.key.key_name()
		if p.kind == .regex {
			b.c.t.set_null(i, .value)
			b.c.t.set_str(i, .regex, p.str + '/' + p.str2)
			continue
		}
		if p.kind == .bigint {
			b.c.t.set_str(i, .bigint, p.str)
			continue
		}
		if p.kind == .template {
			if p.b {
				b.c.t.set_null(i, .cooked)
			} else {
				b.c.t.set_str(i, .cooked, p.str)
			}
			b.c.t.set_str(i, .raw, p.str2)
			continue
		}
		if p.kind == .regexp {
			b.c.t.set_null(i, .value)
			continue
		}
		if name == 'decorators' && p.kind == .list && b.es.lists[p.idx].len > 0 && !b.quiet() {
			d := b.es.nodes[b.es.lists[p.idx][0]]
			b.ts_fail(e_typescript_invalid_feature('decorators (related TSC proposal is not stage 4 yet)'),
				d.start, d.end)
		}
		k := es_keys[name] or { continue }
		match p.kind {
			.null {
				b.c.t.set_null(i, k)
			}
			.bool {
				b.c.t.set_flag(i, k, p.b)
			}
			.number {
				b.c.t.set(i, P{
					key:  k
					kind: .num
					n:    p.num
				})
			}
			.string {
				b.c.t.set_str(i, k, p.str)
			}
			.node {
				b.c.t.set_node(i, k, b.js(p.idx)!)
			}
			.list {
				mut items := []int{}
				for item in b.es.lists[p.idx] {
					items << b.js(item)!
				}
				b.c.t.set_list(i, k, items)
			}
			else {}
		}
	}
	match out_typ {
		'FunctionExpression', 'FunctionDeclaration' {
			params := b.c.t.list(i, .params)
			if params.len > 0 && b.c.t.typ(params[0]) == 'Identifier'
				&& b.c.t.name(params[0]) == 'this' {
				b.c.t.set_list(i, .params, params[1..].clone())
			}
		}
		'ImportDeclaration' {
			specs := b.c.t.list(i, .specifiers)
			if specs.len > 0 {
				kept := specs.filter(b.c.t.text(it, .import_kind) != 'type')
				if kept.len == 0 {
					return b.empty()
				}
				b.c.t.set_list(i, .specifiers, kept)
			}
		}
		'ExportNamedDeclaration' {
			decl := b.c.t.get(i, .declaration)
			if decl >= 0 {
				if b.c.t.typ(decl) == 'EmptyStatement' {
					return b.empty()
				}
			} else {
				specs := b.c.t.list(i, .specifiers)
				kept := specs.filter(b.c.t.text(it, .export_kind) != 'type')
				if kept.len == 0 {
					return b.empty()
				}
				b.c.t.set_list(i, .specifiers, kept)
			}
		}
		'ClassBody' {
			kept := b.c.t.list(i, .body).filter(!(b.c.t.typ(it) == 'PropertyDefinition'
				&& b.c.t.flag(it, .declare)) && b.c.t.typ(it) != 'EmptyStatement')
			b.c.t.set_list(i, .body, kept)
		}
		'VariableDeclaration' {
			if b.es5 && b.in_script {
				b.es5_declaration(i)
			}
		}
		'PropertyDefinition' {
			if b.c.t.flag(i, .accessor) && !b.quiet() {
				b.ts_fail(e_typescript_invalid_feature('accessor fields (related TSC proposal is not stage 4 yet)'),
					start, end)
			}
		}
		'ExportSpecifier', 'ImportSpecifier' {
			// acorn gives `export { a }` / `import { a }` one node for both names.
			local := b.c.t.get(i, .local)
			other_key := if out_typ == 'ExportSpecifier' { Key.exported } else { Key.imported }
			other := b.c.t.get(i, other_key)
			if local >= 0 && other >= 0 && b.c.t.nodes[local].start == b.c.t.nodes[other].start
				&& b.c.t.nodes[local].end == b.c.t.nodes[other].end {
				b.c.t.set_node(i, other_key, local)
			}
		}
		else {}
	}
	return i
}

// transpiled_enum is what TypeScript emits for `enum E {…}`: `var E; (function (E) {…})(E || (E =
// {}));`, kept as far as the compiler sees it (a block: one node for two statements; a `var` in
// it belongs to the scope around it).
fn (mut b Builder) transpiled_enum(e int) !int {
	id := b.js(b.es.node(e, .id) or { -1 })!
	if id < 0 {
		return b.empty()
	}
	name := b.c.t.name(id)
	decl := b.c.t.new_node('VariableDeclaration', no_pos, no_pos)
	b.c.t.set_str(decl, .kind, 'var')
	d := b.c.t.new_node('VariableDeclarator', no_pos, no_pos)
	b.c.t.set_node(d, .id, id)
	b.c.t.set_null(d, .init)
	b.c.t.set_list(decl, .declarations, [d])
	assign := b.c.t.new_node('AssignmentExpression', no_pos, no_pos)
	b.c.t.set_str(assign, .operator, '=')
	b.c.t.set_node(assign, .left, b.c.t.id(name))
	obj := b.c.t.new_node('ObjectExpression', no_pos, no_pos)
	b.c.t.set_list(obj, .properties, [])
	b.c.t.set_node(assign, .right, obj)
	or_ := b.c.t.new_node('LogicalExpression', no_pos, no_pos)
	b.c.t.set_str(or_, .operator, '||')
	b.c.t.set_node(or_, .left, b.c.t.id(name))
	b.c.t.set_node(or_, .right, assign)
	st := b.c.t.new_node('ExpressionStatement', no_pos, no_pos)
	b.c.t.set_node(st, .expression, or_)
	block := b.c.t.new_node('BlockStatement', no_pos, no_pos)
	b.c.t.set_list(block, .body, [decl, st])
	return block
}
