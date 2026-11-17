module vue

// A port of vue-eslint-parser's intermediate tokenizer (src/html/intermediate-tokenizer.ts) and
// tree builder (src/html/parser.ts) for a .vue file (isSFC: names are compared by `rawName`).

enum ITokType {
	start_tag
	end_tag
	text
	mustache
}

// IToken is an intermediate token. A start tag's attributes are VAttribute nodes already.
struct IToken {
mut:
	typ          ITokType
	start        int
	end          int
	name         string
	raw_name     string
	self_closing bool
	attributes   []int
	value        string
	// Mustache: the end of its `{{` and the start of its `}}`.
	open_end    int
	close_start int
}

// PostKind is a postprocess the tree builder schedules for after the parse, in order.
enum PostKind {
	directive // convert the attribute `node` to a directive
	resolve   // resolve the references of the directives of the element `node`
	mustache  // parse the mustache of the container `node`
}

struct PostProcess {
	kind PostKind
	node int
	tok  IToken
}

struct SfcParser {
mut:
	tz  Tokenizer
	doc &Document = unsafe { nil }
	// Intermediate tokenizer.
	has_current     bool
	current         IToken
	attribute       int = -1
	attribute_names map[string]bool
	has_expr_start  bool
	text_buf        []u8
	expr_start      HTok
	expr_tokens     []HTok
	// Tree builder.
	element_stack []int
	v_pre_element int = -1
	post          []PostProcess
}

// html_token converts a token of the tokenizer to a token of the document.
fn html_token(t HTok) Token {
	return Token{
		typ:   t.typ.name()
		start: t.start
		end:   t.end
		value: t.value
	}
}

// ---- Intermediate tokenizer ----

fn (mut p SfcParser) next_itoken() ?IToken {
	for {
		token := p.tz.next_token() or { break }
		if result := p.process_token(token) {
			return result
		}
	}
	if p.has_current {
		return p.commit()
	}
	return none
}

fn (mut p SfcParser) process_token(token HTok) ?IToken {
	return match token.typ {
		.html_association { p.i_association(token) }
		.html_bogus_comment, .html_comment { p.i_comment(token) }
		.html_cdata_text, .html_rcdata_text, .html_raw_text, .html_text, .html_whitespace {
			p.process_text(token)
		}
		.html_end_tag_open { p.i_end_tag_open(token) }
		.html_identifier { p.i_identifier(token) }
		.html_literal { p.i_literal(token) }
		.html_self_closing_tag_close { p.i_self_closing_tag_close(token) }
		.html_tag_close { p.i_tag_close(token) }
		.html_tag_open { p.i_tag_open(token) }
		.v_expression_start { p.i_expression_start(token) }
		.v_expression_end { p.i_expression_end(token) }
	}
}

fn (mut p SfcParser) commit() IToken {
	mut has_token := p.has_current
	mut token := p.current
	p.has_current = false
	p.attribute = -1
	if has_token && token.typ == .text {
		token.value = p.text_buf.bytestr()
	}
	if p.has_expr_start {
		// VExpressionEnd was not found: the deferred tokens become text.
		start := p.expr_start
		end := if p.expr_tokens.len > 0 { p.expr_tokens.last() } else { start }
		mut value := []u8{}
		append_str(mut value, start.value)
		for t in p.expr_tokens {
			append_str(mut value, t.value)
		}
		p.has_expr_start = false
		p.expr_tokens = []HTok{}
		if !has_token {
			token = IToken{
				typ:   .text
				start: start.start
				end:   end.end
				value: value.bytestr()
			}
			has_token = true
		} else if token.typ == .text {
			token.end = end.end
			token.value += value.bytestr()
		} else {
			panic('vue parser: unreachable')
		}
	}
	return token
}

// append_str appends the bytes of a string (the values of text tokens are joined this way:
// a text can be made of many tokens).
@[inline]
fn append_str(mut b []u8, s string) {
	unsafe { b.push_many(s.str, s.len) }
}

fn (mut p SfcParser) report_token_error(start int, code string) {
	// The tokenizer's array: its errors and these are in the order they happen.
	p.tz.errors << ParseError{
		message: code
		code:    code
		index:   start
	}
}

fn (mut p SfcParser) i_comment(token HTok) ?IToken {
	p.doc.comments << html_token(token)
	if p.has_current && p.current.typ == .text {
		return p.commit()
	}
	return none
}

fn (mut p SfcParser) process_text(token HTok) ?IToken {
	p.doc.tokens << html_token(token)
	mut result := ?IToken(none)
	if p.has_expr_start {
		last_end := if p.expr_tokens.len > 0 { p.expr_tokens.last().end } else { p.expr_start.end }
		if last_end == token.start {
			p.expr_tokens << token
			return none
		}
		result = p.commit()
	} else if p.has_current {
		if p.current.typ == .text && p.current.end == token.start {
			append_str(mut p.text_buf, token.value)
			p.current.end = token.end
			return none
		}
		result = p.commit()
	}
	// The value of the current text is in text_buf until it is committed.
	p.current = IToken{
		typ:   .text
		start: token.start
		end:   token.end
	}
	p.text_buf.clear()
	append_str(mut p.text_buf, token.value)
	p.has_current = true
	return result
}

fn (mut p SfcParser) i_association(token HTok) ?IToken {
	p.doc.tokens << html_token(token)
	if p.attribute >= 0 {
		p.doc.nodes[p.attribute].end = token.end
		if !p.has_current || p.current.typ != .start_tag {
			panic('vue parser: unreachable')
		}
		p.current.end = token.end
	}
	return none
}

fn (mut p SfcParser) i_end_tag_open(token HTok) ?IToken {
	p.doc.tokens << html_token(token)
	mut result := ?IToken(none)
	if p.has_current || p.has_expr_start {
		result = p.commit()
	}
	p.current = IToken{
		typ:   .end_tag
		start: token.start
		end:   token.end
		name:  token.value
	}
	p.has_current = true
	return result
}

fn (mut p SfcParser) i_identifier(token HTok) ?IToken {
	p.doc.tokens << html_token(token)
	if !p.has_current || p.current.typ in [.text, .mustache] {
		panic('vue parser: unreachable')
	}
	if p.current.typ == .end_tag {
		p.report_token_error(token.start, 'end-tag-with-attributes')
		return none
	}
	if token.value in p.attribute_names {
		p.report_token_error(token.start, 'duplicate-attribute')
	}
	p.attribute_names[token.value] = true
	attr := p.doc.add_node(VNode{
		typ:   .v_attribute
		start: token.start
		end:   token.end
	})
	key := p.doc.add_node(VNode{
		typ:      .v_identifier
		start:    token.start
		end:      token.end
		parent:   attr
		name:     token.value
		raw_name: p.tz.text[token.start..token.end]
	})
	p.doc.nodes[attr].key = key
	p.attribute = attr
	p.current.end = token.end
	p.current.attributes << attr
	return none
}

fn (mut p SfcParser) i_literal(token HTok) ?IToken {
	p.doc.tokens << html_token(token)
	if p.attribute >= 0 {
		p.doc.nodes[p.attribute].end = token.end
		lit := p.doc.add_node(VNode{
			typ:    .v_literal
			start:  token.start
			end:    token.end
			parent: p.attribute
			text:   token.value
		})
		p.doc.nodes[p.attribute].value = lit
		if !p.has_current || p.current.typ != .start_tag {
			panic('vue parser: unreachable')
		}
		p.current.end = token.end
	}
	return none
}

fn (mut p SfcParser) i_self_closing_tag_close(token HTok) ?IToken {
	p.doc.tokens << html_token(token)
	if !p.has_current || p.current.typ == .text {
		panic('vue parser: unreachable')
	}
	if p.current.typ == .start_tag {
		p.current.self_closing = true
	} else {
		p.report_token_error(token.start, 'end-tag-with-trailing-solidus')
	}
	p.current.end = token.end
	return p.commit()
}

fn (mut p SfcParser) i_tag_close(token HTok) ?IToken {
	p.doc.tokens << html_token(token)
	if !p.has_current || p.current.typ == .text {
		panic('vue parser: unreachable')
	}
	p.current.end = token.end
	return p.commit()
}

fn (mut p SfcParser) i_tag_open(token HTok) ?IToken {
	p.doc.tokens << html_token(token)
	mut result := ?IToken(none)
	if p.has_current || p.has_expr_start {
		result = p.commit()
	}
	p.current = IToken{
		typ:      .start_tag
		start:    token.start
		end:      token.end
		name:     token.value
		raw_name: p.tz.text[token.start + 1..token.end]
	}
	p.has_current = true
	p.attribute = -1
	p.attribute_names.clear()
	return result
}

fn (mut p SfcParser) i_expression_start(token HTok) ?IToken {
	if p.has_expr_start {
		return p.process_text(token)
	}
	if p.has_current && p.current.end != token.start {
		result := p.commit()
		p.doc.tokens << html_token(token)
		p.has_expr_start = true
		p.expr_start = token
		return result
	}
	p.doc.tokens << html_token(token)
	p.has_expr_start = true
	p.expr_start = token
	return none
}

fn (mut p SfcParser) i_expression_end(token HTok) ?IToken {
	if !p.has_expr_start {
		return p.process_text(token)
	}
	start := p.expr_start
	end := if p.expr_tokens.len > 0 { p.expr_tokens.last() } else { start }
	// `{{}}` is text.
	if token.start == start.end {
		p.doc.tokens.pop()
		p.has_expr_start = false
		result := p.process_text(start)
		p.process_text(token)
		return result
	}
	if end.end != token.start {
		result := p.commit()
		p.process_text(token)
		return result
	}
	mut buf := []u8{}
	for t in p.expr_tokens {
		append_str(mut buf, t.value)
	}
	value := buf.bytestr()
	p.doc.tokens << html_token(token)
	p.has_expr_start = false
	p.expr_tokens = []HTok{}
	mustache := IToken{
		typ:         .mustache
		start:       start.start
		end:         token.end
		value:       value
		open_end:    start.end
		close_start: token.start
	}
	if p.has_current {
		result := p.commit()
		p.current = mustache
		p.has_current = true
		return result
	}
	p.current = mustache
	p.has_current = true
	return p.commit()
}

// ---- Tree builder ----

fn (p &SfcParser) current_node() int {
	return if p.element_stack.len > 0 { p.element_stack.last() } else { 0 }
}

fn (mut p SfcParser) parse() {
	for {
		token := p.next_itoken() or { break }
		match token.typ {
			.start_tag { p.start_tag(token) }
			.end_tag { p.end_tag(token) }
			.text { p.text_token(token) }
			.mustache { p.mustache_token(token) }
		}
	}
	p.pop_element_stack_until(0)
	p.doc.propagate_end_location(0)
}

fn (mut p SfcParser) pop_element_stack() {
	element := p.element_stack.pop()
	p.doc.propagate_end_location(element)
	cur := p.current_node()
	p.tz.namespace = if cur == 0 { Namespace.html } else { p.doc.nodes[cur].namespace }
	if p.v_pre_element == element {
		p.v_pre_element = -1
		p.tz.expression_enabled = true
	}
	if p.element_stack.len == 0 {
		p.tz.expression_enabled = false
	}
}

fn (mut p SfcParser) pop_element_stack_until(index int) {
	for p.element_stack.len > index {
		p.pop_element_stack()
	}
}

fn (mut d Document) propagate_end_location(i int) {
	n := d.nodes[i]
	last := if n.typ == .v_element && n.end_tag >= 0 {
		n.end_tag
	} else if n.children.len > 0 {
		n.children.last()
	} else {
		-1
	}
	if last >= 0 {
		d.nodes[i].end = d.nodes[last].end
	}
}

// attr_value is the value of the first plain attribute of the element named `name`, if any.
fn (d &Document) attr_value(attributes []int, name string, plain_only bool) ?string {
	for a in attributes {
		attr := d.nodes[a]
		if plain_only && attr.directive {
			continue
		}
		if attr.directive || d.nodes[attr.key].name != name {
			continue
		}
		if attr.value < 0 {
			return none
		}
		return d.nodes[attr.value].text
	}
	return none
}

// first_attr_value is like attr_value but stops at the first attribute with that key name, plain
// or not (what `attributes.find(a => a.key.name === name)` finds before any conversion).
fn (d &Document) first_attr_value(attributes []int, name string) ?string {
	for a in attributes {
		attr := d.nodes[a]
		if attr.directive || d.nodes[attr.key].name != name {
			continue
		}
		if attr.value < 0 {
			return none
		}
		return d.nodes[attr.value].text
	}
	return none
}

fn (p &SfcParser) is_html_integration_point(e int) bool {
	el := p.doc.nodes[e]
	if el.namespace == .mathml {
		if el.raw_name != 'annotation-xml' {
			return false
		}
		start_tag := p.doc.nodes[el.start_tag]
		for a in start_tag.attributes {
			attr := p.doc.nodes[a]
			if !attr.directive && p.doc.nodes[attr.key].name == 'encoding' && attr.value >= 0 {
				v := p.doc.nodes[attr.value].text
				if v == 'text/html' || v == 'application/xhtml+xml' {
					return true
				}
			}
		}
		return false
	}
	if el.namespace == .svg {
		return el.raw_name in ['foreignObject', 'desc', 'title']
	}
	return false
}

fn (p &SfcParser) is_mathml_integration_point(e int) bool {
	el := p.doc.nodes[e]
	return el.namespace == .mathml && el.raw_name in ['mi', 'mo', 'mn', 'ms', 'mtext']
}

fn (p &SfcParser) detect_namespace(token IToken) Namespace {
	name := token.raw_name
	mut ns := p.tz.namespace
	if ns == .mathml || ns == .svg {
		element := p.current_node()
		if element != 0 {
			el := p.doc.nodes[element]
			if el.namespace == .mathml && el.raw_name == 'annotation-xml' && name == 'svg' {
				return .svg
			}
			if p.is_html_integration_point(element) || (p.is_mathml_integration_point(element)
				&& name != 'mglyph' && name != 'malignmark') {
				ns = .html
			}
		}
	}
	if ns == .html {
		if name == 'svg' {
			return .svg
		}
		if name == 'math' {
			return .mathml
		}
	}
	if name == 'template' {
		for a in token.attributes {
			attr := p.doc.nodes[a]
			if p.doc.nodes[attr.key].name == 'xmlns' {
				if attr.value >= 0 {
					v := p.doc.nodes[attr.value].text
					if v == ns_html {
						return .html
					}
					if v == ns_mathml {
						return .mathml
					}
					if v == ns_svg {
						return .svg
					}
				}
				break
			}
		}
	}
	return ns
}

fn is_dt_dd(name string) bool {
	return name == 'dd' || name == 'dt'
}

fn (mut p SfcParser) close_current_element_if_necessary(token IToken) {
	element := p.current_node()
	if element == 0 {
		return
	}
	name := token.raw_name
	element_name := p.doc.nodes[element].raw_name
	if element_name == 'p' && name in html_non_phrasing_tags {
		p.pop_element_stack()
	}
	if element_name == name && name in html_can_be_left_open_tags {
		p.pop_element_stack()
	}
	if is_dt_dd(element_name) && is_dt_dd(name) {
		p.pop_element_stack()
	}
}

fn adjust_attribute_name(name string, ns Namespace) string {
	if ns == .svg {
		return svg_attribute_name_map[name] or { name }
	}
	if ns == .mathml {
		return mathml_attribute_name_map[name] or { name }
	}
	return name
}

fn (mut p SfcParser) process_attribute(attr int, ns Namespace) {
	if p.need_convert_to_directive(attr) {
		p.post << PostProcess{
			kind: .directive
			node: attr
		}
		return
	}
	key := p.doc.nodes[attr].key
	p.doc.nodes[key].name = adjust_attribute_name(p.doc.nodes[key].name, ns)
	raw := p.doc.nodes[key].raw_name
	value_node := p.doc.nodes[attr].value
	has_value := value_node >= 0
	value := if has_value { p.doc.nodes[value_node].text } else { '' }
	if raw == 'xmlns' && (!has_value || value != ns.uri()) {
		p.report_token_error(p.doc.nodes[attr].start, 'x-invalid-namespace')
	} else if raw == 'xmlns:xlink' && (!has_value || value != ns_xlink) {
		p.report_token_error(p.doc.nodes[attr].start, 'x-invalid-namespace')
	}
}

// is_directive_name is /^(?:v-|[.:@#]).*[^.:@#]$/u.
fn is_directive_name(name string) bool {
	mut rest := 0
	if name.starts_with('v-') {
		rest = 2
	} else if name.len > 0 && name[0] in [`.`, `:`, `@`, `#`] {
		rest = 1
	} else {
		return false
	}
	if name.len <= rest {
		// `v-` alone: try the one-character prefix, which `v` is not.
		return false
	}
	// `.` does not match line terminators.
	mut i := rest
	for i < name.len {
		cp, n := decode_cp(name, i)
		if cp == 0x0a || cp == 0x0d || cp == 0x2028 || cp == 0x2029 {
			return false
		}
		i += n
	}
	last := name[name.len - 1]
	if last in [`.`, `:`, `@`, `#`] {
		// With the `v-` prefix the one-character alternative cannot match either.
		return false
	}
	return true
}

fn (p &SfcParser) is_script_setup_ts(element int) bool {
	el := p.doc.nodes[element]
	if el.name != 'script' {
		return false
	}
	start_tag := p.doc.nodes[el.start_tag]
	mut setup := false
	for a in start_tag.attributes {
		attr := p.doc.nodes[a]
		if !attr.directive && p.doc.nodes[attr.key].name == 'setup' {
			setup = true
			break
		}
	}
	if !setup {
		return false
	}
	lang := p.doc.lang_of(element) or { return false }
	return lang == 'ts' || lang == 'tsx'
}

fn (p &SfcParser) need_convert_to_directive(attr int) bool {
	element := p.doc.nodes[p.doc.nodes[attr].parent].parent
	tag_name := p.doc.nodes[element].raw_name
	attr_name := p.doc.nodes[p.doc.nodes[attr].key].raw_name
	if attr_name == 'generic' && p.doc.nodes[element].parent == 0
		&& p.is_script_setup_ts(element) {
		return true
	}
	enabled := p.tz.expression_enabled || (attr_name == 'v-pre' && p.v_pre_element < 0)
	if !enabled {
		return false
	}
	return is_directive_name(attr_name) || attr_name == 'slot-scope'
		|| (tag_name == 'template' && attr_name == 'scope')
}

fn (mut p SfcParser) start_tag(token IToken) {
	p.close_current_element_if_necessary(token)
	parent := p.current_node()
	namespace := p.detect_namespace(token)
	name := if namespace == .svg {
		svg_element_name_map[token.name] or { token.name }
	} else {
		token.name
	}
	element := p.doc.add_node(VNode{
		typ:       .v_element
		start:     token.start
		end:       token.end
		parent:    parent
		name:      name
		raw_name:  token.raw_name
		namespace: namespace
	})
	start_tag := p.doc.add_node(VNode{
		typ:          .v_start_tag
		start:        token.start
		end:          token.end
		parent:       element
		self_closing: token.self_closing
		attributes:   token.attributes
	})
	p.doc.nodes[element].start_tag = start_tag
	mut has_v_pre := false
	if p.v_pre_element < 0 {
		for a in token.attributes {
			if p.doc.nodes[p.doc.nodes[a].key].raw_name == 'v-pre' {
				has_v_pre = true
				break
			}
		}
	}
	if has_v_pre {
		p.tz.expression_enabled = false
	}
	p.doc.nodes[parent].children << element
	for a in token.attributes {
		p.doc.nodes[a].parent = start_tag
		p.process_attribute(a, namespace)
	}
	p.post << PostProcess{
		kind: .resolve
		node: element
	}
	is_void := namespace == .html && token.raw_name in html_void_element_tags
	if token.self_closing && !is_void && namespace == .html {
		p.report_token_error(token.start, 'non-void-html-element-start-tag-with-trailing-solidus')
	}
	if token.self_closing || is_void {
		p.tz.expression_enabled = p.v_pre_element < 0
		return
	}
	p.element_stack << element
	if has_v_pre {
		p.v_pre_element = element
	}
	p.tz.namespace = namespace
	if namespace == .html {
		element_name := token.raw_name
		if parent == 0 {
			lang := p.doc.attr_value(token.attributes, 'lang', true) or { '' }
			if element_name == 'template' {
				p.tz.expression_enabled = true
				if lang != '' && lang != 'html' {
					p.tz.state = .rawtext
					p.tz.expression_enabled = false
				}
			} else {
				// A custom block (or <script>, <style>) is not HTML.
				if lang == '' || lang != 'html' {
					p.tz.state = .rawtext
				}
			}
		} else {
			if element_name in html_rcdata_tags {
				p.tz.state = .rcdata
			}
			if element_name in html_rawtext_tags {
				p.tz.state = .rawtext
			}
		}
	}
}

fn (mut p SfcParser) end_tag(token IToken) {
	mut i := p.element_stack.len - 1
	for i >= 0 {
		if js_to_lower(p.doc.nodes[p.element_stack[i]].name) == token.name {
			break
		}
		i--
	}
	if i < 0 {
		p.report_token_error(token.start, 'x-invalid-end-tag')
		return
	}
	element := p.element_stack[i]
	end_tag := p.doc.add_node(VNode{
		typ:    .v_end_tag
		start:  token.start
		end:    token.end
		parent: element
	})
	p.doc.nodes[element].end_tag = end_tag
	p.pop_element_stack_until(i)
}

fn (mut p SfcParser) text_token(token IToken) {
	parent := p.current_node()
	text := p.doc.add_node(VNode{
		typ:    .v_text
		start:  token.start
		end:    token.end
		parent: parent
		text:   token.value
	})
	p.doc.nodes[parent].children << text
}

fn (mut p SfcParser) mustache_token(token IToken) {
	parent := p.current_node()
	container := p.doc.add_node(VNode{
		typ:    .v_expression_container
		start:  token.start
		end:    token.end
		parent: parent
	})
	p.doc.nodes[parent].children << container
	p.post << PostProcess{
		kind: .mustache
		node: container
		tok:  token
	}
}

// js_to_lower is String.prototype.toLowerCase for the names of elements.
fn js_to_lower(s string) string {
	return s.to_lower()
}
