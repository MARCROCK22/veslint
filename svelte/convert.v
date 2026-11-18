module svelte

import strings

// The conversion of the compiler AST to svelte-eslint-parser's AST (src/parser/converts/*.ts),
// and the queue of "script lets" (src/context/script-let.ts): every template expression,
// pattern and block is appended to the code handed to the script parser, in the order of the
// conversion; script_let.v parses that code and puts the nodes back (restore).

// LetKind is the method of ScriptLetContext that appended a let.
enum LetKind as u8 {
	expression          // addExpression / addExpressionFromRange
	shorthand_property  // addObjectShorthandProperty
	variable_declarator // addVariableDeclarator (@const)
	declaration         // addDeclaration ({let …})
	generic_alias       // addGenericTypeAliasDeclaration
	generic_default     // its default
	if_block            // nestIfBlock
	each_block          // nestEachBlock
	snippet_block       // nestSnippetBlock
	block               // nestBlock without params
	block_params        // nestBlock with params
	prep                // a preparation script of a typed {:then v} (all removed)
}

// Setter tells where the node a let gives goes, and what to check.
enum Setter as u8 {
	none
	expression       // node.expression = es
	debug_identifier // node.identifiers << es
	key_name         // node.key → its name = es (directive name, style shorthand)
	element_name     // element.name = es (component)
	member_object    // member.object = es
	each_key         // eachBlock.key = es
}

// Segment maps a piece of a let's text, copied from the file, back to it (remapNodes).
struct Segment {
mut:
	pre_start  int // byte offset in the pre-virtual code
	len        int
	file_start int
}

// ScriptLet is a queued let (a RestoreCallback).
struct ScriptLet {
mut:
	kind      LetKind
	node_type string // the statement type the restore matches
	start     int    // in the pre-virtual code (bytes)
	end       int
	segments  []Segment
	// target: the Svelte node the let belongs to (the one whose property it sets, or the block
	// it gives a scope), the setter and the checks.
	target  int = -1
	setter  Setter
	typed   bool   // TypeScript: `(part)as (typing);`
	check   string // 'directive:<compiler type>', 'identifier', 'identifier_or_member', 'style_identifier'
	binding bool   // a bind: directive's expression
	// Blocks with params: the parent Svelte node of each param (let: directives), with the
	// setter of each param, in source order.
	param_parents []int
	param_setters []ParamSetter
	// Snippet: insertions of type annotations (pre offsets), and whether a `return` was added.
	insertions []Segment
	ts_return  bool
	// Each: whether there is a context and an index.
	has_context bool
	has_index   bool
	// Generics: the TSTypeParameter (an ESTree index) and whether it has a constraint.
	param          int = -1
	has_constraint bool
	// Declaration ({let}): the part's range (file bytes).
	part_start int
	part_end   int
}

// ParamSetter is where a param of nestBlock goes.
struct ParamSetter {
	node  int // the Svelte node
	field u8  // 0: then value, 1: catch error, 2: let directive expression, 3: let name (key.name)
}

// Area is where a let's text goes in the pre-virtual code.
enum Area as u8 {
	render
	snippet
	generics
}

// Conv is the converter and the ScriptLetContext.
struct Conv {
	code    string
	parsers &Parsers = unsafe { nil }
mut:
	doc  &Document = unsafe { nil }
	ca   CAst
	sc   SourceCode
	lets []ScriptLet
	// The pre-virtual code: script code trimmed, `\n;`, the spaces after, then the areas.
	trimmed_len   int
	before_spaces string
	render        strings.Builder
	snippet       strings.Builder
	generics      strings.Builder
	started       bool
	current_kind  Area = .render
	close_stack   []CloseScope
	unique        UniqueIds
	letdir_stack  [][]LetParam
	slots         []int
	elements      map[int]int // Svelte element → compiler node
	snippets      []int
	err           ?ParseError
}

struct CloseScope {
	let_index int
	token     string
	kind      Area
	upper     Area
}

// LetParam is a ScriptLetBlockParam of a let: directive (or a then/catch value).
struct LetParam {
	start  int // getNodeRange of the pattern
	end    int
	typing string
	setter ParamSetter
	parent int
}

struct UniqueIds {
mut:
	seq  int = 1
	used map[string]bool
}

// generate is UniqueIdGenerator.generate: `$_<base>N`, retried while used or in the texts.
fn (mut u UniqueIds) generate(base string, texts []string) string {
	mut b := []u8{cap: base.len}
	for c in base.bytes() {
		b << if is_word_char(c) { c } else { `_` }
	}
	cleaned := b.bytestr()
	for {
		candidate := '$_${cleaned}${u.seq}'
		u.seq++
		if candidate in u.used || texts.any(it.contains(candidate)) {
			continue
		}
		u.used[candidate] = true
		return candidate
	}
	return ''
}

fn (mut c Conv) fail(message string, at int) {
	if c.err == none {
		c.err = ParseError{
			message: message
			index:   at
		}
	}
}

// ---------------------------------------------------------------------------------------------
// The pre-virtual code (ScriptsSourceCode).

fn (c &Conv) current_length() int {
	if !c.started {
		return c.sc.script_raw.len
	}
	return c.trimmed_len + 2 + c.before_spaces.len + c.render.len + c.snippet.len + c.generics.len
}

// add_let is ScriptsSourceCode.addLet: appends to an area, gives the range.
fn (mut c Conv) add_let(text string, kind Area) (int, int) {
	if !c.started {
		c.started = true
		c.trimmed_len = c.sc.trimmed_len
		c.before_spaces = if c.trimmed_len + 2 <= c.sc.script_raw.len {
			c.sc.script_raw[c.trimmed_len + 2..]
		} else {
			''
		}
	}
	start := c.current_length()
	match kind {
		.render { c.render.write_string(text) }
		.snippet { c.snippet.write_string(text) }
		.generics { c.generics.write_string(text) }
	}
	return start, c.current_length()
}

// pre_code is getCurrentVirtualCode (in bytes: blanks per byte, see blank_bytes).
fn (c &Conv) pre_code() string {
	if !c.started {
		return c.sc.script_raw
	}
	return c.sc.script_raw[..c.trimmed_len] + '\n;' + c.before_spaces + c.render.bytestr() +
		c.snippet.bytestr() + c.generics.bytestr()
}

fn (mut c Conv) append_let(l ScriptLet, text string, kind Area) int {
	mut sl := l
	s, e := c.add_let(text, kind)
	sl.start = s
	sl.end = e
	for mut seg in sl.segments {
		seg.pre_start += s
	}
	for mut ins in sl.insertions {
		ins.pre_start += s
	}
	c.lets << sl
	return c.lets.len - 1
}

fn (mut c Conv) push_scope(let_index int, token string, kind Area) {
	c.close_stack << CloseScope{
		let_index: let_index
		token:     token
		kind:      kind
		upper:     c.current_kind
	}
	c.current_kind = kind
}

fn (mut c Conv) close_scope() {
	cs := c.close_stack.pop()
	c.add_let(cs.token, cs.kind)
	c.current_kind = cs.upper
	c.lets[cs.let_index].end = c.current_length()
}

// ---------------------------------------------------------------------------------------------
// Ranges (getNodeRange).

// node_range is getNodeRange of a compiler expression: widened over its leading and trailing
// comments, then "balanced" (a buggy loop kept as it is).
fn (c &Conv) node_range(e int) (int, int) {
	ex := c.ca.exprs[e]
	mut start := ex.start
	mut end := ex.end
	mut open := 0
	mut close := 0
	code := c.code
	if ex.leading.len > 0 {
		cs := c.ca.comments[ex.leading[0]].start
		if cs < start {
			start = cs
			mut leading_end := ex.start
			for k := ex.leading.len - 1; k >= 0; k-- {
				cm := c.ca.comments[ex.leading[k]]
				gap := js_trim(code[cm.end..leading_end])
				open += gap.count('(')
				leading_end = cm.start
			}
		}
	}
	if ex.trailing.len > 0 {
		ce := c.ca.comments[ex.trailing.last()].end
		if end < ce {
			end = ce
			mut trailing_start := ex.end
			for t in ex.trailing {
				cm := c.ca.comments[t]
				if cm.start >= trailing_start {
					gap := js_trim(code[trailing_start..cm.start])
					close += gap.count(')')
				}
				trailing_start = cm.end
			}
		}
	}
	if open < close {
		for open < close && start >= 0 {
			if start < code.len && !is_space_at(code, start) {
				start--
				continue
			}
			break
		}
	} else if open > close {
		for open > close && end < code.len {
			if !is_space_at(code, end) {
				end++
				continue
			}
			break
		}
	}
	return start, end
}

// ---------------------------------------------------------------------------------------------
// Svelte nodes and tokens.

fn (mut c Conv) add(n SNode) int {
	c.doc.nodes << n
	return c.doc.nodes.len - 1
}

fn (mut c Conv) add_token(typ string, start int, end int) {
	c.doc.tokens << Token{
		typ:   typ
		start: start
		end:   end
		value: c.code[start..end]
	}
}

// index_of_from is code.indexOf(s, from) (-1 when absent).
fn (c &Conv) index_of_from(s string, from int) int {
	if from < 0 {
		return c.code.index(s) or { -1 }
	}
	return c.code.index_after(s, from) or { -1 }
}

// first_non_space is indexOf(code, (c) => c.trim(), from).
fn (c &Conv) first_non_space(from int) int {
	mut i := from
	for i < c.code.len {
		if !is_space_at(c.code, i) {
			return i
		}
		_, n := code_point_at(c.code, i)
		i += n
	}
	return -1
}

// ---------------------------------------------------------------------------------------------
// Root (root.ts convertSvelteRoot).

fn (mut c Conv) convert_root() {
	program := c.add(SNode{
		typ:   .program
		start: 0
		end:   c.code.len
	})
	_ = program
	mut children := c.ca.fragments[c.ca.fragment].clone()
	if c.ca.options >= 0 {
		opt := c.ca.nodes[c.ca.options]
		mut inserted := false
		for k, ch in children {
			if opt.end <= c.ca.nodes[ch].start {
				children.insert(k, c.ca.options)
				inserted = true
				break
			}
		}
		if !inserted {
			children << c.ca.options
		}
	}
	mut snippet_children := []int{}
	mut others := []int{}
	for ch in children {
		if c.ca.nodes[ch].typ == .snippet_block {
			snippet_children << ch
		} else {
			others << ch
		}
	}
	mut body := c.convert_children(others, 0)
	mut script := -1
	if c.ca.instance >= 0 {
		script = c.convert_script(c.ca.instance)
		body << script
	}
	if c.ca.module >= 0 {
		body << c.convert_script(c.ca.module)
	}
	if c.ca.css >= 0 {
		body << c.convert_style(c.ca.css)
	}
	body << c.convert_children(snippet_children, 0)
	if script >= 0 {
		c.convert_generics(script)
	}
	c.doc.nodes[0].children = body
	c.tag_comments(body)
	sort_snodes(mut c.doc.nodes[0].children, c.doc.nodes)
}

// sort_snodes is sortNodes: by start, then end (stable).
fn sort_snodes(mut list []int, nodes []SNode) {
	list.sort_with_compare(fn [nodes] (a &int, b &int) int {
		na := nodes[*a]
		nb := nodes[*b]
		if na.start != nb.start {
			return na.start - nb.start
		}
		return na.end - nb.end
	})
}

fn (mut c Conv) new_start_tag(element int, start int) int {
	return c.add(SNode{
		typ:    .start_tag
		start:  start
		end:    -1
		parent: element
	})
}

fn (mut c Conv) convert_script(script int) int {
	cn := c.ca.nodes[script]
	el := c.add(SNode{
		typ:    .script_element
		start:  cn.start
		end:    cn.end
		parent: 0
	})
	st := c.new_start_tag(el, cn.start)
	c.doc.nodes[el].start_tag = st
	if b := c.sc.find_block('script', cn.start, cn.end) {
		c.doc.nodes[st].attributes = c.convert_block_attributes(b.attrs, st)
	}
	c.extract_element_tags(el, 'script', fn (mut c Conv, el int, s int, e int) Ref {
		c.add_token('HTMLIdentifier', s, e)
		return sref(c.add(SNode{
			typ:    .name
			name:   'script'
			start:  s
			end:    e
			parent: el
		}))
	})
	return el
}

fn (mut c Conv) convert_style(css int) int {
	cn := c.ca.nodes[css]
	el := c.add(SNode{
		typ:    .style_element
		start:  cn.start
		end:    cn.end
		parent: 0
	})
	st := c.new_start_tag(el, cn.start)
	c.doc.nodes[el].start_tag = st
	if b := c.sc.find_block('style', cn.start, cn.end) {
		c.doc.nodes[st].attributes = c.convert_block_attributes(b.attrs, st)
	}
	c.extract_element_tags(el, 'style', fn (mut c Conv, el int, s int, e int) Ref {
		c.add_token('HTMLIdentifier', s, e)
		return sref(c.add(SNode{
			typ:    .name
			name:   'style'
			start:  s
			end:    e
			parent: el
		}))
	})
	n := c.doc.nodes[el]
	if n.end_tag >= 0 {
		cs := c.doc.nodes[n.start_tag].end
		ce := c.doc.nodes[n.end_tag].start
		if cs < ce {
			c.add_token('HTMLText', cs, ce)
			t := c.add(SNode{
				typ:    .text
				value:  c.code[cs..ce]
				start:  cs
				end:    ce
				parent: el
			})
			c.doc.nodes[el].children = [t]
		}
	}
	return el
}

// convert_block_attributes converts the attributes parseAttributes read for a block.
fn (mut c Conv) convert_block_attributes(attrs []int, parent int) []int {
	// The block attributes live in their own arena: copy them into the compiler AST.
	mut out := []int{}
	for a in attrs {
		out << c.import_block_attr(a)
	}
	return c.convert_attributes(out, parent)
}

fn (mut c Conv) import_block_attr(a int) int {
	src := c.sc.block_attrs.ast.nodes[a]
	mut n := src
	n.value = []
	for v in src.value {
		vn := c.sc.block_attrs.ast.nodes[v]
		mut dup := vn
		if vn.expression >= 0 {
			dup.expression = c.ca.add_expr(c.sc.block_attrs.ast.exprs[vn.expression])
		}
		n.value << c.ca.add(dup)
	}
	return c.ca.add(n)
}

// tag_comments adds the compiler's comments that lie in a start tag (of the elements reachable
// through element children from the root) and not in an attribute.
fn (mut c Conv) tag_comments(body []int) {
	if c.ca.comments.len == 0 {
		return
	}
	mut tags := []int{}
	mut buffer := []int{}
	for b in body {
		if c.doc.nodes[b].typ in [.script_element, .style_element, .element] {
			buffer << b
		}
	}
	for buffer.len > 0 {
		el := buffer[0]
		buffer.delete(0)
		tags << c.doc.nodes[el].start_tag
		if c.doc.nodes[el].typ == .element {
			mut kids := []int{}
			for ch in c.doc.nodes[el].children {
				if c.doc.nodes[ch].typ == .element {
					kids << ch
				}
			}
			buffer.prepend(kids)
		}
	}
	for cm in c.ca.comments {
		mut tag := -1
		for t in tags {
			tn := c.doc.nodes[t]
			if tn.start <= cm.start && cm.end <= tn.end {
				tag = t
				break
			}
		}
		if tag < 0 {
			continue
		}
		mut in_attr := false
		for a in c.doc.nodes[tag].attributes {
			an := c.doc.nodes[a]
			if an.start <= cm.start && cm.end <= an.end {
				in_attr = true
				break
			}
		}
		if in_attr {
			continue
		}
		c.doc.comments << Token{
			typ:   if cm.block { 'Block' } else { 'Line' }
			start: cm.start
			end:   cm.end
			value: cm.value
		}
	}
}

// ---------------------------------------------------------------------------------------------
// Children (element.ts convertChildren).

fn (mut c Conv) convert_children(nodes []int, parent int) []int {
	mut out := []int{}
	for ch in nodes {
		r := c.convert_child(ch, parent)
		if r >= 0 {
			out << r
		}
	}
	return out
}

// convert_trimmed converts trimChildren of a list (if/each/key/snippet bodies).
fn (mut c Conv) convert_trimmed(nodes []int, parent int) []int {
	return c.convert_children(c.trim_children(nodes), parent)
}

// trim_children is compat.ts trimChildren: whitespace-only texts at both ends dropped, the
// first and last texts trimmed (in a copy: their range stays).
fn (mut c Conv) trim_children(children []int) []int {
	if !c.text_starts_ws(if children.len > 0 { children[0] } else { -1 })
		&& !c.text_ends_ws(if children.len > 0 { children.last() } else { -1 }) {
		return children
	}
	mut nodes := children.clone()
	for nodes.len > 0 && c.ca.nodes[nodes[0]].typ == .text && is_blank(c.ca.nodes[nodes[0]].data) {
		nodes.delete(0)
	}
	if nodes.len > 0 && c.text_starts_ws(nodes[0]) {
		mut dup := c.ca.nodes[nodes[0]]
		dup.data = dup.data[js_trim_start_len(dup.data)..]
		nodes[0] = c.ca.add(dup)
	}
	for nodes.len > 0 && c.ca.nodes[nodes.last()].typ == .text
		&& is_blank(c.ca.nodes[nodes.last()].data) {
		nodes.delete_last()
	}
	if nodes.len > 0 && c.text_ends_ws(nodes.last()) {
		mut dup := c.ca.nodes[nodes.last()]
		dup.data = dup.data[..js_trim_end_len(dup.data)]
		nodes[nodes.len - 1] = c.ca.add(dup)
	}
	return nodes
}

fn (c &Conv) text_starts_ws(i int) bool {
	if i < 0 {
		return false
	}
	n := c.ca.nodes[i]
	return n.typ == .text && js_trim_start_len(n.data) > 0
}

fn (c &Conv) text_ends_ws(i int) bool {
	if i < 0 {
		return false
	}
	n := c.ca.nodes[i]
	return n.typ == .text && js_trim_end_len(n.data) < n.data.len
}

fn (mut c Conv) convert_child(ch int, parent int) int {
	cn := c.ca.nodes[ch]
	match cn.typ {
		.comment {
			c.add_token('HTMLComment', cn.start, cn.end)
			return c.add(SNode{
				typ:    .html_comment
				value:  cn.data
				start:  cn.start
				end:    cn.end
				parent: parent
			})
		}
		.text {
			if cn.data == '' && cn.start == cn.end {
				return -1
			}
			t := c.add(SNode{
				typ:    .text
				value:  cn.data
				start:  cn.start
				end:    cn.end
				parent: parent
			})
			c.text_tokens(cn.start, cn.end)
			return t
		}
		.regular_element, .title_element {
			return c.convert_element(ch, parent, 'html')
		}
		.slot_element {
			el := c.convert_element(ch, parent, 'html')
			c.slots << el
			return el
		}
		.component {
			return c.convert_element(ch, parent, 'component')
		}
		.svelte_component, .svelte_element, .svelte_self, .svelte_window, .svelte_body,
		.svelte_head, .svelte_options, .svelte_fragment, .svelte_document, .svelte_boundary {
			return c.convert_element(ch, parent, 'special')
		}
		.expression_tag {
			return c.convert_mustache(ch, parent, '', 'text')
		}
		.html_tag {
			m := c.convert_mustache(ch, parent, '', 'raw')
			at := c.index_of_from('@html', c.doc.nodes[m].start)
			c.add_token('MustacheKeyword', at, at + 5)
			return m
		}
		.if_block {
			return c.convert_if(ch, parent, -1)
		}
		.each_block {
			return c.convert_each(ch, parent)
		}
		.await_block {
			return c.convert_await(ch, parent)
		}
		.key_block {
			return c.convert_key(ch, parent)
		}
		.snippet_block {
			return c.convert_snippet(ch, parent)
		}
		.debug_tag {
			d := c.add(SNode{
				typ:    .debug_tag
				start:  cn.start
				end:    cn.end
				parent: parent
			})
			for id in cn.identifiers {
				c.add_expression(id, d, '', .debug_identifier, '')
			}
			at := c.index_of_from('@debug', cn.start)
			c.add_token('MustacheKeyword', at, at + 6)
			return d
		}
		.const_tag {
			d := c.add(SNode{
				typ:    .const_tag
				start:  cn.start
				end:    cn.end
				parent: parent
			})
			c.add_variable_declarator(cn.decl_id, cn.decl_init, d)
			at := c.index_of_from('@const', cn.start)
			c.add_token('MustacheKeyword', at, at + 6)
			return d
		}
		.declaration_tag {
			d := c.add(SNode{
				typ:    .declaration_tag
				start:  cn.start
				end:    cn.end
				parent: parent
			})
			c.add_declaration(cn.decl_start, cn.decl_end, d)
			return d
		}
		.render_tag {
			d := c.add(SNode{
				typ:    .render_tag
				start:  cn.start
				end:    cn.end
				parent: parent
			})
			ex := c.ca.exprs[cn.expression]
			c.add_expression_from_range(ex.start, ex.end, d, '', .expression, '')
			at := c.index_of_from('@render', cn.start)
			c.add_token('MustacheKeyword', at, at + 7)
			return d
		}
		else {
			c.fail('Unknown type:${cn.typ.name()}', cn.start)
			return -1
		}
	}
}

// text_tokens is extractTextTokens: HTMLText tokens of the runs of whitespace and of
// non-whitespace (raw source).
fn (mut c Conv) text_tokens(start int, end int) {
	mut s := start
	mut word := false
	mut i := start
	for i < end {
		is_word := !is_space_at(c.code, i)
		if word != is_word {
			if s < i {
				c.add_token('HTMLText', s, i)
			}
			word = !word
			s = i
		}
		_, n := code_point_at(c.code, i)
		i += n
	}
	if s < end {
		c.add_token('HTMLText', s, end)
	}
}

fn (mut c Conv) convert_mustache(ch int, parent int, typing string, kind string) int {
	cn := c.ca.nodes[ch]
	m := c.add(SNode{
		typ:    .mustache_tag
		kind:   kind
		start:  cn.start
		end:    cn.end
		parent: parent
	})
	t := if typing != '' && c.has_type_info(cn.expression) { '' } else { typing }
	c.add_expression(cn.expression, m, t, .expression, '')
	return m
}

// ---------------------------------------------------------------------------------------------
// Elements (convertHTMLElement, convertSpecialElement, convertComponentElement).

fn (c &Conv) need_scope_by_children(fragment int) bool {
	for ch in c.ca.fragments[fragment] {
		if c.ca.nodes[ch].typ in [.const_tag, .declaration_tag, .snippet_block] {
			return true
		}
	}
	return false
}

fn (mut c Conv) convert_element(ch int, parent int, kind string) int {
	cn := c.ca.nodes[ch]
	el := c.add(SNode{
		typ:    .element
		kind:   kind
		start:  cn.start
		end:    cn.end
		parent: parent
	})
	st := c.new_start_tag(el, cn.start)
	c.doc.nodes[el].start_tag = st
	c.elements[el] = ch
	mut let_dirs := []int{}
	mut attrs := []int{}
	for a in cn.attributes {
		if c.ca.nodes[a].typ == .let_directive {
			let_dirs << a
		} else {
			attrs << a
		}
	}
	mut let_params := []LetParam{}
	if let_dirs.len > 0 {
		c.letdir_stack << []LetParam{}
		converted := c.convert_attributes(let_dirs, st)
		c.doc.nodes[st].attributes << converted
		let_params = c.letdir_stack.pop()
	}
	if let_params.len == 0 && !c.need_scope_by_children(cn.fragment) {
		converted := c.convert_attributes(attrs, st)
		c.doc.nodes[st].attributes << converted
		kids := c.convert_children(c.ca.fragments[cn.fragment], el)
		c.doc.nodes[el].children << kids
	} else {
		c.nest_block(el, let_params)
		converted := c.convert_attributes(attrs, st)
		c.doc.nodes[st].attributes << converted
		sort_snodes(mut c.doc.nodes[st].attributes, c.doc.nodes)
		kids := c.convert_children(c.ca.fragments[cn.fragment], el)
		c.doc.nodes[el].children << kids
		c.close_scope()
	}
	if kind == 'special' && cn.expression >= 0
		&& (cn.typ == .svelte_component || cn.typ == .svelte_element) {
		c.process_this_attribute(ch, cn.expression, el)
	}
	if kind == 'component' {
		c.extract_element_tags(el, cn.name, fn (mut c Conv, el int, s int, e int) Ref {
			return c.component_name(el, s)
		})
	} else {
		c.extract_element_tags(el, cn.name, fn (mut c Conv, el int, s int, e int) Ref {
			c.add_token('HTMLIdentifier', s, e)
			cnode := c.ca.nodes[c.elements[el]]
			return sref(c.add(SNode{
				typ:    .name
				name:   cnode.name
				start:  s
				end:    e
				parent: el
			}))
		})
	}
	if kind == 'html' {
		name := c.doc.nodes[c.doc.nodes[el].name_ref.idx].name
		if name == 'script' || name == 'style'
			|| (name == 'template' && c.sc.find_block('template', cn.start, cn.end) != none) {
			for k in c.doc.nodes[el].children {
				if c.doc.nodes[k].typ == .text {
					c.doc.nodes[k].value = c.code[c.doc.nodes[k].start..c.doc.nodes[k].end]
				}
			}
			if name == 'script' {
				n := c.doc.nodes[el]
				s := c.doc.nodes[n.start_tag].end
				e := if n.end_tag >= 0 { c.doc.nodes[n.end_tag].start } else { n.end }
				c.strip_script_code(s, e)
			}
		}
		stn := c.doc.nodes[st]
		if stn.self_closing && name.ends_with('-') && name.len >= 2 && name[0].is_letter()
			&& name[1..].bytes().all(it == `-`) {
			if b := c.sc.find_self_closing_block(stn.start, stn.end) {
				c.doc.nodes[c.doc.nodes[el].name_ref.idx].name = b.original_tag
			}
		}
	}
	return el
}

// strip_script_code is ScriptsSourceCode.stripCode: blanks a range of the script code (and of
// the trimmed code, whose length stays the one computed first).
fn (mut c Conv) strip_script_code(start int, end int) {
	if start >= end {
		return
	}
	raw := c.sc.script_raw
	c.sc.script_raw = raw[..start] + blank_bytes(raw[start..end]) + raw[end..]
	// The JavaScript-blanked copy: the same characters, at UTF-16-blanked positions.
	text16 := c.sc.script_u16
	us := c.doc.index.to_u16(start)
	ue := c.doc.index.to_u16(end)
	bs := u16_byte_offset(text16, us)
	be := u16_byte_offset(text16, ue)
	c.sc.script_u16 = text16[..bs] + blank_u16(text16[bs..be]) + text16[be..]
}

// u16_byte_offset is the byte offset of a UTF-16 offset of a string.
fn u16_byte_offset(s string, u int) int {
	mut units := 0
	mut i := 0
	for i < s.len && units < u {
		n := utf8_len(s[i])
		units += if n == 4 { 2 } else { 1 }
		i += n
	}
	return i
}

// component_name builds the name of a component element: an Identifier for the first segment
// (re-parsed by the script parser) and a SvelteMemberExpressionName per other segment.
fn (mut c Conv) component_name(el int, s int) Ref {
	cnode := c.ca.nodes[c.elements[el]]
	chains := cnode.name.split('.')
	id := chains[0]
	id_end := s + id.len
	mut object := Ref{}
	mut first_member := -1
	mut start := id_end + 1
	for name in chains[1..] {
		e := start + name.len
		c.add_token('HTMLIdentifier', start, e)
		mem := c.add(SNode{
			typ:    .member_expression_name
			start:  s
			end:    e
			parent: el
		})
		prop := c.add(SNode{
			typ:    .name
			name:   name
			start:  start
			end:    e
			parent: mem
		})
		c.doc.nodes[mem].property = prop
		if object.idx >= 0 && !object.es {
			c.doc.nodes[mem].object = object
			c.doc.nodes[object.idx].parent = mem
		}
		if first_member < 0 {
			first_member = mem
		}
		object = sref(mem)
		start = e + 1
	}
	// The Identifier: addExpression of its range; the result goes to the first member's object,
	// or to the element's name.
	if first_member >= 0 {
		c.add_expression_from_range(s, id_end, first_member, '', .member_object, '')
		// The identifier's parent is the first member (the made-up Identifier's parent was set
		// to it); the script parser's identifier gets that parent in the callback.
		return object
	}
	c.add_expression_from_range(s, id_end, el, '', .element_name, '')
	return Ref{}
}

// process_this_attribute is processThisAttribute (svelte:element, svelte:component).
fn (mut c Conv) process_this_attribute(ch int, expr int, el int) {
	start_index := c.find_start_index_of_this(ch) or {
		c.fail('Cannot resolved `this` attribute.', -1)
		return
	}
	eq := c.index_of_from('=', start_index + 4)
	ex := c.ca.exprs[expr]
	value_start := c.first_non_space(eq + 1)
	mut this_node := -1
	if ex.kind == .literal && ex.synthetic && value_start >= 0 && c.code[value_start] != `{` {
		// The compiler's Literal: its value is the (decoded) text of the attribute.
		this_node = c.create_this_attribute(el, start_index, eq, ex.name)
	} else {
		close_index := c.index_of_from('}', ex.end)
		mut end_index := close_index
		for end_index >= 0 && end_index < c.code.len {
			if c.code[end_index] == `>` || is_space_at(c.code, end_index) {
				break
			}
			end_index++
		}
		this_node = c.add(SNode{
			typ:    .special_directive
			kind:   'this'
			start:  start_index
			end:    end_index
			parent: c.doc.nodes[el].start_tag
		})
		key := c.add(SNode{
			typ:    .special_directive_key
			start:  start_index
			end:    eq
			parent: this_node
		})
		c.doc.nodes[this_node].key = sref(key)
		c.add_token('HTMLIdentifier', start_index, start_index + 4)
		c.add_token('Punctuator', eq, eq + 1)
		c.add_expression(expr, this_node, '', .expression, '')
	}
	st := c.doc.nodes[el].start_tag
	mut attrs := c.doc.nodes[st].attributes.clone()
	end := c.doc.nodes[this_node].end
	mut target := -1
	for k, a in attrs {
		if end <= c.doc.nodes[a].start {
			target = k
			break
		}
	}
	if target < 0 {
		attrs << this_node
	} else {
		attrs.insert(target, this_node)
	}
	c.doc.nodes[st].attributes = attrs
}

fn (mut c Conv) create_this_attribute(el int, start_index int, eq int, value string) int {
	value_start := c.first_non_space(eq + 1)
	quote := if c.code[value_start..].starts_with(value) {
		''
	} else {
		c.code[value_start..value_start + 1]
	}
	lit_start := value_start + quote.len
	lit_end := lit_start + value.len
	end := lit_end + quote.len
	attr := c.add(SNode{
		typ:    .attribute
		start:  start_index
		end:    end
		parent: c.doc.nodes[el].start_tag
	})
	key := c.add(SNode{
		typ:    .name
		name:   'this'
		start:  start_index
		end:    eq
		parent: attr
	})
	lit := c.add(SNode{
		typ:    .literal
		value:  value
		start:  lit_start
		end:    lit_end
		parent: attr
	})
	c.doc.nodes[attr].key = sref(key)
	c.doc.nodes[attr].values = [lit]
	c.add_token('HTMLIdentifier', start_index, start_index + 4)
	c.add_token('Punctuator', eq, eq + 1)
	if quote != '' {
		c.add_token('Punctuator', value_start, lit_start)
	}
	c.add_token('HTMLText', lit_start, lit_end)
	if quote != '' {
		c.add_token('Punctuator', lit_end, end)
	}
	return attr
}

// find_start_index_of_this is findStartIndexOfThis.
fn (c &Conv) find_start_index_of_this(ch int) ?int {
	cn := c.ca.nodes[ch]
	from := c.index_of_from(cn.name, cn.start) + cn.name.len
	mut sorted := cn.attributes.clone()
	nodes := c.ca.nodes
	sorted.sort_with_compare(fn [nodes] (a &int, b &int) int {
		return nodes[*a].start - nodes[*b].start
	})
	mut limit := if sorted.len > 0 { c.ca.nodes[sorted[0]].start } else { cn.end }
	mut idx := c.find_this(from, limit)
	for idx < 0 {
		if sorted.len == 0 {
			return none
		}
		next := c.ca.nodes[sorted[0]].end
		sorted.delete(0)
		limit = if sorted.len > 0 { c.ca.nodes[sorted[0]].start } else { cn.end }
		idx = c.find_this(next, limit)
	}
	return idx
}

fn (c &Conv) find_this(from int, to int) int {
	mut i := from
	for i < to && i < c.code.len {
		if c.code[i..].starts_with('this') {
			return i
		}
		i++
	}
	return -1
}

// NameBuilder builds the name node of an element from the range of its name.
type NameBuilder = fn (mut c Conv, el int, s int, e int) Ref

// extract_element_tags is extractElementTags.
fn (mut c Conv) extract_element_tags(el int, _name string, build NameBuilder) {
	n := c.doc.nodes[el]
	mut name_end := n.start + 1
	for name_end < c.code.len {
		ch := c.code[name_end]
		if ch == `/` || ch == `>` || is_space_at(c.code, name_end) {
			break
		}
		name_end++
	}
	if name_end >= c.code.len {
		name_end = -1
	}
	ne := if name_end < 0 { c.code.len } else { name_end }
	name_ref := build(mut c, el, n.start + 1, ne)
	c.doc.nodes[el].name_ref = name_ref
	st := c.doc.nodes[el].start_tag
	attrs := c.doc.nodes[st].attributes
	from := if attrs.len > 0 { c.doc.nodes[attrs.last()].end } else { ne }
	start_tag_end := c.index_of_from('>', from) + 1
	c.doc.nodes[st].end = start_tag_end
	if n.end - 1 < 0 || n.end - 1 >= c.code.len || c.code[n.end - 1] != `>` {
		return
	}
	if n.end >= 2 && c.code[n.end - 2] == `/` {
		c.doc.nodes[st].self_closing = true
		return
	}
	end_open := c.code[..n.end - 1].last_index('<') or { -1 }
	if end_open <= start_tag_end - 1 {
		return
	}
	name_start := end_open + 2
	mut end_name_end := name_start
	for end_name_end < c.code.len {
		if c.code[end_name_end] == `>` || is_space_at(c.code, end_name_end) {
			break
		}
		end_name_end++
	}
	close := c.index_of_from('>', end_name_end)
	et := c.add(SNode{
		typ:    .end_tag
		start:  end_open
		end:    close + 1
		parent: el
	})
	c.doc.nodes[el].end_tag = et
	c.add_token('HTMLIdentifier', name_start, end_name_end)
}

// ---------------------------------------------------------------------------------------------
// The script lets (ScriptLetContext's add* and nest* methods).

fn (c &Conv) is_ts() bool {
	return true
}

// add_expression is addExpression for a compiler expression.
fn (mut c Conv) add_expression(expr int, target int, typing string, setter Setter, check string) {
	s, e := c.node_range(expr)
	c.add_expression_from_range(s, e, target, typing, setter, check)
}

fn (mut c Conv) add_expression_from_range(s int, e int, target int, typing string, setter Setter, check string) {
	part := js_slice(c.code, s, e)
	typed := typing != '' && c.is_ts()
	text := if typed { '(${part})as (${typing});' } else { '(${part});' }
	c.append_let(ScriptLet{
		kind:      .expression
		node_type: 'ExpressionStatement'
		segments:  [Segment{1, part.len, s}]
		target:    target
		setter:    setter
		typed:     typed
		check:     check
	}, text, c.current_kind)
}

// add_name_expression is addExpression of a SvelteName (its range).
fn (mut c Conv) add_name_expression(name int, target int, setter Setter, check string) {
	n := c.doc.nodes[name]
	c.add_expression_from_range(n.start, n.end, target, '', setter, check)
}

fn (mut c Conv) add_object_shorthand_property(s int, e int, target int) {
	part := c.code[s..e]
	c.append_let(ScriptLet{
		kind:      .shorthand_property
		node_type: 'ExpressionStatement'
		segments:  [Segment{2, part.len, s}]
		target:    target
	}, '({${part}});', c.current_kind)
}

fn (mut c Conv) add_variable_declarator(id int, init int, target int) {
	s, _ := c.node_range(id)
	_, e := c.node_range(init)
	part := c.code[s..e]
	c.append_let(ScriptLet{
		kind:      .variable_declarator
		node_type: 'VariableDeclaration'
		segments:  [Segment{6, part.len, s}]
		target:    target
	}, 'const ${part};', c.current_kind)
}

fn (mut c Conv) add_declaration(s int, e int, target int) {
	part := c.code[s..e]
	c.append_let(ScriptLet{
		kind:       .declaration
		node_type:  'VariableDeclaration'
		segments:   [Segment{0, part.len, s}]
		target:     target
		part_start: s
		part_end:   e
	}, '${part};', c.current_kind)
}

fn (mut c Conv) nest_if_block(test int, if_block int) int {
	s, e := c.node_range(test)
	part := c.code[s..e]
	i := c.append_let(ScriptLet{
		kind:      .if_block
		node_type: 'IfStatement'
		segments:  [Segment{3, part.len, s}]
		target:    if_block
	}, 'if(${part}){', c.current_kind)
	c.push_scope(i, '}', c.current_kind)
	return i
}

fn (mut c Conv) begin_else(if_let int) {
	c.close_scope()
	c.add_let('else ', c.current_kind)
	c.push_scope(if_let, '', c.current_kind)
}

fn (mut c Conv) nest_each_block(expr int, context int, idx_start int, idx_end int, each int) {
	es, ee := c.node_range(expr)
	mut source := 'Array.from('
	mut segs := [Segment{source.len, ee - es, es}]
	source += c.code[es..ee] + ').forEach(('
	if context >= 0 {
		cs, ce := c.node_range(context)
		segs << Segment{source.len, ce - cs, cs}
		source += c.code[cs..ce]
	} else {
		source += '__\$ctx__'
	}
	if idx_start >= 0 {
		source += ','
		segs << Segment{source.len, idx_end - idx_start, idx_start}
		source += c.code[idx_start..idx_end]
	}
	source += ')=>{'
	i := c.append_let(ScriptLet{
		kind:        .each_block
		node_type:   'ExpressionStatement'
		segments:    segs
		target:      each
		has_context: context >= 0
		has_index:   idx_start >= 0
	}, source, c.current_kind)
	c.push_scope(i, '});', c.current_kind)
}

// nest_block is nestBlock: `{…}` without params, `(p1: (t1),…)=>{…};` with.
fn (mut c Conv) nest_block(block int, params []LetParam) {
	if params.len == 0 {
		i := c.append_let(ScriptLet{
			kind:      .block
			node_type: 'BlockStatement'
			target:    block
		}, '{', c.current_kind)
		c.push_scope(i, '}', c.current_kind)
		return
	}
	mut sorted := params.clone()
	sorted.sort_with_compare(fn (a &LetParam, b &LetParam) int {
		return a.start - b.start
	})
	mut source := ''
	mut segs := []Segment{}
	mut parents := []int{}
	mut setters := []ParamSetter{}
	for p in sorted {
		if source != '' {
			source += ','
		}
		segs << Segment{source.len + 1, p.end - p.start, p.start}
		source += c.code[p.start..p.end]
		if c.is_ts() {
			source += ': (${p.typing})'
		}
		parents << p.parent
		setters << p.setter
	}
	i := c.append_let(ScriptLet{
		kind:          .block_params
		node_type:     'ExpressionStatement'
		segments:      segs
		target:        block
		param_parents: parents
		param_setters: setters
	}, '(${source})=>{', c.current_kind)
	c.push_scope(i, '};', c.current_kind)
}

fn (mut c Conv) append_prep(script string, node_type string) {
	c.append_let(ScriptLet{
		kind:      .prep
		node_type: node_type
	}, script, c.current_kind)
}

fn (mut c Conv) generate_unique_id(base string) string {
	return c.unique.generate(base, [c.code, c.pre_code()])
}

// ---------------------------------------------------------------------------------------------
// Typings (TypeScript).

fn conditional(check string, ext string, t string, f string) string {
	return '${check} extends ${ext}?(${t}):(${f})'
}

fn (c &Conv) element_name_of(el int) string {
	return c.ca.nodes[c.elements[el]].name
}

// build_event_handler_type is buildEventHandlerType.
fn (c &Conv) build_event_handler_type(element int, event string) string {
	native := '(e:${conditional("'${event}'", 'infer EVT', conditional('EVT', 'keyof HTMLElementEventMap', 'HTMLElementEventMap[EVT]', 'CustomEvent<any>'), 'never')})=>void'
	en := c.doc.nodes[element]
	if en.typ != .element {
		return native
	}
	name := c.element_name_of(element)
	if en.kind == 'component' {
		events := "import('svelte').ComponentEvents<${name}>"
		return '(e:${conditional('0', '(1 & ${events})', 'CustomEvent<any>', conditional("'${event}'", 'infer EVT', conditional('EVT', 'keyof ${events}', '${events}[EVT]', 'CustomEvent<any>'), 'never'))})=>void'
	}
	if en.kind == 'special' {
		if name == 'svelte:component' {
			return '(e:CustomEvent<any>)=>void'
		}
		return native
	}
	attr := 'on:${event}'
	s := "import('svelte/elements').SvelteHTMLElements"
	return conditional("'${name}'", 'infer EL', conditional('EL', 'keyof ${s}', conditional("'${attr}'",
		'infer ATTR', conditional('ATTR', 'keyof ${s}[EL]', '${s}[EL][ATTR]', native), 'never'),
		native), 'never')
}

// build_attribute_type is buildAttributeType.
fn (c &Conv) build_attribute_type(element int, attr_name string) string {
	en := c.doc.nodes[element]
	if attr_name.starts_with('on') && (en.typ != .element || en.kind == 'html') {
		return c.build_event_handler_type(element, attr_name[2..])
	}
	if en.typ != .element || en.kind != 'component' {
		return ''
	}
	props := "import('svelte').ComponentProps<typeof ${c.element_name_of(element)}>"
	return conditional("'${attr_name}'", 'infer PROP', conditional('PROP', 'keyof ${props}',
		'${props}[PROP]', 'never'), 'never')
}

// build_let_directive_type is buildLetDirectiveType.
fn (c &Conv) build_let_directive_type(element int, let_name string) string {
	en := c.doc.nodes[element]
	if en.typ != .element {
		return 'any'
	}
	mut slot_name := 'default'
	mut component := ''
	cn := c.ca.nodes[c.elements[element]]
	mut slot_attr := -1
	for a in cn.attributes {
		an := c.ca.nodes[a]
		if an.typ == .attribute && an.name == 'slot' {
			slot_attr = a
			break
		}
	}
	if slot_attr >= 0 {
		an := c.ca.nodes[slot_attr]
		if an.value_kind == .array && an.value.len == 1 && c.ca.nodes[an.value[0]].typ == .text {
			slot_name = c.ca.nodes[an.value[0]].data
		} else {
			return 'any'
		}
		p := c.find_parent_component(element)
		if p < 0 {
			return 'any'
		}
		component = c.element_name_of(p)
	} else {
		if en.kind == 'component' {
			component = cn.name
		} else {
			p := c.find_parent_component(element)
			if p < 0 {
				return 'any'
			}
			component = c.element_name_of(p)
		}
	}
	return "${component}['\$\$slot_def'][${json_quote(slot_name)}][${json_quote(let_name)}]"
}

fn (c &Conv) find_parent_component(node int) int {
	mut p := c.doc.nodes[node].parent
	for p >= 0 && c.doc.nodes[p].typ != .element {
		p = c.doc.nodes[p].parent
	}
	if p < 0 || c.doc.nodes[p].kind != 'component' {
		return -1
	}
	return p
}

// json_quote is JSON.stringify of a string.
fn json_quote(s string) string {
	mut b := strings.new_builder(s.len + 2)
	b.write_u8(`"`)
	for ch in s {
		match ch {
			`"` { b.write_string('\\"') }
			`\\` { b.write_string('\\\\') }
			`\n` { b.write_string('\\n') }
			`\r` { b.write_string('\\r') }
			`\t` { b.write_string('\\t') }
			8 { b.write_string('\\b') }
			12 { b.write_string('\\f') }
			else {
				if ch < 0x20 {
					b.write_string('\\u00${ch.hex()}')
				} else {
					b.write_u8(ch)
				}
			}
		}
	}
	b.write_u8(`"`)
	return b.str()
}

// convert_generics is convertGenericsAttribute (root.ts): not done yet.
fn (mut c Conv) convert_generics(script int) {
}

// js_slice is String#slice: a negative index counts from the end; an empty string when start
// is not before end (getNodeRange's balancing loop can leave start at -1).
fn js_slice(s string, start int, end int) string {
	mut a := if start < 0 { s.len + start } else { start }
	mut b := if end < 0 { s.len + end } else { end }
	if a < 0 {
		a = 0
	}
	if b > s.len {
		b = s.len
	}
	if a >= b {
		return ''
	}
	return s[a..b]
}
