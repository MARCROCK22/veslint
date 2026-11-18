module rules

import svelte

// eslint-plugin-svelte's src/utils/ast-utils.ts (and element-types.ts) for the svelte/* rules, on
// the document being linted (c.svelte.doc). Nodes are indexes of doc.nodes (Svelte nodes) or of
// doc.es (ESTree nodes), or svelte.Ref values where both may be.

// sv_start_tag is the start tag of an element-like node (SvelteElement, SvelteScriptElement,
// SvelteStyleElement), or the node itself when it is a SvelteStartTag.
fn (c &Checker) sv_start_tag(i int) int {
	n := &c.svelte.doc.nodes[i]
	return if n.typ == .start_tag { i } else { n.start_tag }
}

// sv_ref_name is the name of an Identifier (ESTree) or a SvelteName, '' for another node.
fn (c &Checker) sv_ref_name(r svelte.Ref) string {
	if r.idx < 0 {
		return ''
	}
	doc := c.svelte.doc
	if r.es {
		if doc.es.nodes[r.idx].typ != .identifier {
			return ''
		}
		return doc.es.string_of(r.idx, .name) or { '' }
	}
	return if doc.nodes[r.idx].typ == .name { doc.nodes[r.idx].name } else { '' }
}

// sv_simple_name is getSimpleNameFromNode: an Identifier's or a SvelteName's name, `a.b` for a
// SvelteMemberExpressionName or a MemberExpression that is not computed, else the node's text.
fn (c &Checker) sv_simple_name(r svelte.Ref) string {
	doc := c.svelte.doc
	if r.es {
		match doc.es.nodes[r.idx].typ {
			.identifier {
				return doc.es.string_of(r.idx, .name) or { '' }
			}
			.member_expression {
				computed := doc.es.flag(r.idx, .computed) or { false }
				if !computed {
					object := doc.es.node(r.idx, .object) or { -1 }
					property := doc.es.node(r.idx, .property) or { -1 }
					if object >= 0 && property >= 0 {
						return '${c.sv_simple_name(sv_es_ref(object))}.${c.sv_simple_name(sv_es_ref(property))}'
					}
				}
			}
			else {}
		}
		return c.sv_es_text(r.idx)
	}
	n := &doc.nodes[r.idx]
	match n.typ {
		.name {
			return n.name
		}
		.member_expression_name {
			return '${c.sv_simple_name(n.object)}.${c.sv_simple_name(sv_snode_ref(n.property))}'
		}
		else {
			return c.sv_snode_text(r.idx)
		}
	}
}

// sv_element_name is getNodeName of a SvelteElement.
fn (c &Checker) sv_element_name(i int) string {
	return c.sv_simple_name(c.svelte.doc.nodes[i].name_ref)
}

// sv_attribute_name is `key.name` of a SvelteAttribute or a SvelteShorthandAttribute.
fn (c &Checker) sv_attribute_name(attr int) string {
	return c.sv_ref_name(c.svelte.doc.nodes[attr].key)
}

// sv_directive_key_name is `key.name.name` of a directive (SvelteDirective, SvelteStyleDirective):
// the name of its SvelteDirectiveKey's name ('' when that is not a name).
fn (c &Checker) sv_directive_key_name(dir int) string {
	doc := c.svelte.doc
	key := doc.nodes[dir].key
	if key.es || key.idx < 0 || doc.nodes[key.idx].typ != .directive_key {
		return ''
	}
	return c.sv_ref_name(doc.nodes[key.idx].key)
}

// sv_find_attribute is findAttribute: the first SvelteAttribute of the start tag with that name,
// -1 for none.
fn (c &Checker) sv_find_attribute(element int, name string) int {
	tag := c.sv_start_tag(element)
	if tag < 0 {
		return -1
	}
	doc := c.svelte.doc
	for a in doc.nodes[tag].attributes {
		if doc.nodes[a].typ == .attribute && c.sv_attribute_name(a) == name {
			return a
		}
	}
	return -1
}

// sv_find_shorthand_attribute is findShorthandAttribute.
fn (c &Checker) sv_find_shorthand_attribute(element int, name string) int {
	tag := c.sv_start_tag(element)
	if tag < 0 {
		return -1
	}
	doc := c.svelte.doc
	for a in doc.nodes[tag].attributes {
		if doc.nodes[a].typ == .shorthand_attribute && c.sv_attribute_name(a) == name {
			return a
		}
	}
	return -1
}

// sv_find_bind_directive is findBindDirective: the first `bind:<name>` directive.
fn (c &Checker) sv_find_bind_directive(element int, name string) int {
	tag := c.sv_start_tag(element)
	if tag < 0 {
		return -1
	}
	doc := c.svelte.doc
	for a in doc.nodes[tag].attributes {
		if doc.nodes[a].typ == .directive && doc.nodes[a].kind == 'Binding'
			&& c.sv_directive_key_name(a) == name {
			return a
		}
	}
	return -1
}

// sv_static_attribute_value is getStaticAttributeValue: the text of an attribute whose values
// are all SvelteLiterals, none when one is not.
fn (c &Checker) sv_static_attribute_value(attr int) ?string {
	doc := c.svelte.doc
	mut s := ''
	for v in doc.nodes[attr].values {
		if doc.nodes[v].typ != .literal {
			return none
		}
		s += doc.nodes[v].value
	}
	return s
}

// sv_lang_value is getLangValue of a script or style element (none without a static lang).
fn (c &Checker) sv_lang_value(element int) ?string {
	attr := c.sv_find_attribute(element, 'lang')
	if attr < 0 {
		return none
	}
	return c.sv_static_attribute_value(attr)
}

// sv_is_module_script is isModuleScript: `<script module>` or `<script context="module">`.
fn (c &Checker) sv_is_module_script(script int) bool {
	if c.sv_find_attribute(script, 'module') >= 0 {
		return true
	}
	attr := c.sv_find_attribute(script, 'context')
	if attr < 0 {
		return false
	}
	doc := c.svelte.doc
	values := doc.nodes[attr].values
	return values.len == 1 && doc.nodes[values[0]].typ == .literal
		&& doc.nodes[values[0]].value == 'module'
}

// sv_is_html_element_like is isHTMLElementLike: an html SvelteElement, or `<svelte:element>`.
fn (c &Checker) sv_is_html_element_like(i int) bool {
	n := &c.svelte.doc.nodes[i]
	if n.typ != .element {
		return false
	}
	return match n.kind {
		'html' { true }
		'special' { c.sv_ref_name(n.name_ref) == 'svelte:element' }
		else { false }
	}
}

// sv_is_void_html_element is isVoidHtmlElement.
fn (c &Checker) sv_is_void_html_element(i int) bool {
	return c.sv_element_name(i) in sv_void_elements
}

// sv_is_svg_element is isSvgElement.
fn (c &Checker) sv_is_svg_element(i int) bool {
	return c.sv_element_name(i) in sv_svg_elements
}

// sv_is_mathml_element is isMathMLElement.
fn (c &Checker) sv_is_mathml_element(i int) bool {
	return c.sv_element_name(i) in sv_mathml_elements
}

// sv_is_foreign_element is isForeignElement (SVG or MathML).
fn (c &Checker) sv_is_foreign_element(i int) bool {
	name := c.sv_element_name(i)
	return name in sv_svg_elements || name in sv_mathml_elements
}

// sv_directive_name is getDirectiveName of a SvelteDirective.
fn (c &Checker) sv_directive_name(dir int) string {
	n := &c.svelte.doc.nodes[dir]
	return match n.kind {
		'Action' { 'use' }
		'Animation' { 'animate' }
		'Binding' { 'bind' }
		'Class' { 'class' }
		'EventHandler' { 'on' }
		'Let' { 'let' }
		'Transition' { if n.intro && n.outro { 'transition' } else if n.intro { 'in' } else { 'out' } }
		'Ref' { 'ref' }
		else { '' }
	}
}

// sv_attribute_key_text is getAttributeKeyText.
fn (c &Checker) sv_attribute_key_text(attr int) string {
	doc := c.svelte.doc
	n := &doc.nodes[attr]
	match n.typ {
		.attribute, .shorthand_attribute, .generics_directive {
			return c.sv_ref_name(n.key)
		}
		.style_directive {
			return 'style:${c.sv_directive_key_name(attr)}'
		}
		.special_directive {
			return n.kind
		}
		.directive {
			key := doc.nodes[n.key.idx]
			modifiers := if key.modifiers.len > 0 { '|' + key.modifiers.join('|') } else { '' }
			return '${c.sv_directive_name(attr)}:${c.sv_simple_name(key.key)}${modifiers}'
		}
		.attach_tag {
			return '@attach'
		}
		else {
			return ''
		}
	}
}

// SvQuoteAndRange is getAttributeValueQuoteAndRange's result: the quote (`unquoted`, `double`,
// `single`), the range of the value with its quotes, and its first and last tokens.
struct SvQuoteAndRange {
	quote string
	start int
	end   int
	first svelte.Token
	last  svelte.Token
}

// sv_mustache_tokens is getMustacheTokens: the `{` and `}` around a node's expression (a mustache
// tag and the like are wrapped; a directive's expression may be in parentheses), none when there
// are none (a shorthand, no expression).
fn (c &Checker) sv_mustache_tokens(i int) ?(svelte.Token, svelte.Token) {
	doc := c.svelte.doc
	n := &doc.nodes[i]
	if n.typ in [.mustache_tag, .shorthand_attribute, .spread_attribute, .debug_tag, .declaration_tag,
		.render_tag] {
		open := c.sv_first_token(n.start, n.end)?
		close := c.sv_last_token(n.start, n.end)?
		return open, close
	}
	if n.expression.idx < 0 || !n.expression.es {
		return none
	}
	ex_start, ex_end := c.sv_ref_range(n.expression)
	if n.key.idx >= 0 {
		key_start, key_end := c.sv_ref_range(n.key)
		if key_start <= ex_start && ex_end <= key_end {
			return none
		}
	}
	mut open := c.sv_token_before(ex_start, false)?
	mut close := c.sv_token_after(ex_end, false)?
	for sv_is_punctuator(open, '(') && sv_is_punctuator(close, ')') {
		open = c.sv_token_before(open.start, false)?
		close = c.sv_token_after(close.end, false)?
	}
	if !sv_is_punctuator(open, '{') || !sv_is_punctuator(close, '}') {
		return none
	}
	return open, close
}

// sv_attribute_value_tokens is getAttributeValueRangeTokens.
fn (c &Checker) sv_attribute_value_tokens(attr int) ?(svelte.Token, svelte.Token) {
	doc := c.svelte.doc
	n := &doc.nodes[attr]
	if n.typ in [.attribute, .style_directive] {
		if n.values.len == 0 {
			return none
		}
		first := doc.nodes[n.values[0]]
		last := doc.nodes[n.values.last()]
		return c.sv_first_token(first.start, first.end)?, c.sv_last_token(last.start, last.end)?
	}
	return c.sv_mustache_tokens(attr)
}

// sv_attribute_value_quote_and_range is getAttributeValueQuoteAndRange.
fn (c &Checker) sv_attribute_value_quote_and_range(attr int) ?SvQuoteAndRange {
	first, last := c.sv_attribute_value_tokens(attr)?
	n := &c.svelte.doc.nodes[attr]
	_, key_end := c.sv_ref_range(n.key)
	eq := c.sv_token_after(key_end, false)?
	if eq.value != '=' || first.start < eq.end {
		return none
	}
	before := c.sv_tokens_between(eq.end, first.start, false)
	if before.len == 0 {
		return SvQuoteAndRange{
			quote: 'unquoted'
			start: first.start
			end:   last.end
			first: first
			last:  last
		}
	}
	if before.len > 1 || (before[0].value != '"' && before[0].value != "'") {
		return none
	}
	after := c.sv_token_after(last.end, false)?
	if after.value != before[0].value {
		return none
	}
	return SvQuoteAndRange{
		quote: if before[0].value == '"' { 'double' } else { 'single' }
		start: before[0].start
		end:   after.end
		first: before[0]
		last:  after
	}
}

// sv_equal_tokens is equalTokens: the two ranges have the same tokens (type and value).
fn (c &Checker) sv_equal_tokens(a_start int, a_end int, b_start int, b_end int) bool {
	left := c.sv_tokens_in(a_start, a_end, false)
	right := c.sv_tokens_in(b_start, b_end, false)
	if left.len != right.len {
		return false
	}
	for k in 0 .. left.len {
		if left[k].typ != right[k].typ || left[k].value != right[k].value {
			return false
		}
	}
	return true
}

// sv_parent is a node's parent for ESLint: a Svelte node's, an ESTree node's Svelte parent when
// it is in the template or a script's body (doc.es_parent), else its ESTree parent; none at the
// top.
fn (c &Checker) sv_parent(r svelte.Ref) ?svelte.Ref {
	doc := c.svelte.doc
	if r.es {
		if p := doc.es_parent[r.idx] {
			return sv_snode_ref(p)
		}
		p := doc.es.nodes[r.idx].parent
		if p < 0 {
			return none
		}
		return sv_es_ref(p)
	}
	p := doc.nodes[r.idx].parent
	if p < 0 {
		return none
	}
	return sv_snode_ref(p)
}

// sv_scope_of is getScope: the scope (an index of doc.scope.scopes) of the closest node from
// `r` up that has one (a function-expression-name scope gives its child), else the global one.
fn (c &Checker) sv_scope_of(r svelte.Ref) int {
	info := &c.svelte.doc.scope
	mut node := ?svelte.Ref(r)
	for node != none {
		n := node or { break }
		for k, s in info.scopes {
			if s.block.es == n.es && s.block.idx == n.idx {
				if s.typ == 'function-expression-name' && s.children.len > 0 {
					return s.children[0]
				}
				return k
			}
		}
		node = c.sv_parent(n)
	}
	return 0
}
