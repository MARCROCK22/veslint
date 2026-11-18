module svelte

import estree
import strings

// to_json writes the document as tools/svelte_parse_diff.mjs compares it with
// svelte-eslint-parser's result: the Program (Svelte nodes and ESTree, without `parent`), its
// tokens and comments, and the codes handed to the script parser (`~codes`), or the error
// (`fatal`). Ranges are UTF-16 offsets; numbers of ESTree properties are the bits of the double
// (`{"$num": hex}`).
pub fn (d &Document) to_json() string {
	mut b := strings.new_builder(d.src.len * 8 + 256)
	if e := d.error {
		d.json_error(mut b, e)
		return b.str()
	}
	b.write_string('{"program":')
	d.json_snode(mut b, 0)
	b.write_string(',"tokens":')
	d.json_tokens(mut b, d.tokens)
	b.write_string(',"comments":')
	d.json_tokens(mut b, d.comments)
	b.write_string(',"~codes":[')
	for k, code in d.parser_codes() {
		if k > 0 {
			b.write_u8(`,`)
		}
		b.write_string(estree.quote(code))
	}
	b.write_string(']}')
	return b.str()
}

// parser_codes are the codes handed to the script parser, sorted.
pub fn (d &Document) parser_codes() []string {
	mut out := [d.pre_u16]
	if d.virtual_code != '' {
		out << d.virtual_code
	}
	if d.generics_code != '' {
		out << d.generics_code
	}
	out.sort()
	return out
}

fn (d &Document) json_error(mut b strings.Builder, e ParseError) {
	if e.ts_message {
		// typescript-eslint's error: positions in the pre-virtual code.
		u := pre_u16_offset(d, e.pre_index)
		line, col := ts_line_column(d.pre_u16, u)
		b.write_string('{"fatal":{"ts":true,"code":${estree.quote(d.pre_u16)},"message":${estree.quote(e.message)},"index":${u},"lineNumber":${line},"column":${col}}}')
		return
	}
	u := if e.index < 0 { e.index } else { d.utf16(e.index) }
	l := d.lc.loc_u16(u)
	b.write_string('{"fatal":{"message":${estree.quote(e.message)},"index":${u},"lineNumber":${l.line},"column":${l.column}}}')
}

// pre_u16_offset converts a byte offset of the pre-virtual code to an offset of
// svelte-eslint-parser's (UTF-16, JavaScript blanks).
fn pre_u16_offset(d &Document, p int) int {
	if d.separator < 0 || p < d.src.len {
		if d.separator >= 0 && p >= d.separator && p < d.separator + 2 {
			return d.utf16(d.separator) + (p - d.separator)
		}
		return d.utf16(p)
	}
	prefix := if d.separator + 2 > d.src.len { d.separator + 2 } else { d.src.len }
	prefix16 := if d.separator + 2 > d.src.len {
		d.utf16(d.separator) + 2
	} else {
		d.index.u16_len
	}
	if p < prefix {
		return d.utf16(d.separator) + (p - d.separator)
	}
	return prefix16 + u16_len_of(d.pre[prefix..p])
}

// ts_line_column is TypeScript's line (from 1) and character of a UTF-16 offset.
fn ts_line_column(text string, u int) (int, int) {
	mut line := 1
	mut line_start := 0
	mut units := 0
	mut i := 0
	for i < text.len && units < u {
		c := text[i]
		n := utf8_len(c)
		if c == `\n` {
			line++
			line_start = units + 1
		} else if c == `\r` {
			if !(i + 1 < text.len && text[i + 1] == `\n`) {
				line++
				line_start = units + 1
			}
		} else if is_line_sep(text, i) {
			line++
			line_start = units + 1
		}
		units += if n == 4 { 2 } else { 1 }
		i += n
	}
	return line, u - line_start
}

fn (d &Document) json_loc(mut b strings.Builder, start int, end int) {
	ls := d.loc(start)
	le := d.loc(end)
	b.write_string('{"start":{"line":${ls.line},"column":${ls.column}},"end":{"line":${le.line},"column":${le.column}}}')
}

fn (d &Document) json_range_loc(mut b strings.Builder, start int, end int) {
	b.write_string('"range":[${d.utf16(start)},${d.utf16(end)}],"loc":')
	d.json_loc(mut b, start, end)
}

fn (d &Document) json_tokens(mut b strings.Builder, tokens []Token) {
	b.write_u8(`[`)
	for i, t in tokens {
		if i > 0 {
			b.write_u8(`,`)
		}
		b.write_string('{"type":${estree.quote(t.typ)},"value":${estree.quote(t.value)},')
		b.write_string('"range":[${d.utf16(t.start)},${d.utf16(t.end)}],"loc":')
		ls := if t.loc_start >= 0 { t.loc_start } else { t.start }
		le := if t.loc_end >= 0 { t.loc_end } else { t.end }
		d.json_loc(mut b, ls, le)
		b.write_u8(`}`)
	}
	b.write_u8(`]`)
}

fn (d &Document) json_ref(mut b strings.Builder, r Ref) {
	if r.idx < 0 {
		b.write_string('null')
	} else if r.es {
		d.json_es(mut b, r.idx, '')
	} else {
		d.json_snode(mut b, r.idx)
	}
}

fn (d &Document) json_snodes(mut b strings.Builder, list []int) {
	b.write_u8(`[`)
	for k, i in list {
		if k > 0 {
			b.write_u8(`,`)
		}
		d.json_snode(mut b, i)
	}
	b.write_u8(`]`)
}

fn (d &Document) json_es_list(mut b strings.Builder, list []int) {
	b.write_u8(`[`)
	for k, i in list {
		if k > 0 {
			b.write_u8(`,`)
		}
		d.json_es(mut b, i, '')
	}
	b.write_u8(`]`)
}

fn json_bool(v bool) string {
	return if v { 'true' } else { 'false' }
}

fn (d &Document) json_snode(mut b strings.Builder, i int) {
	n := d.nodes[i]
	b.write_string('{"type":"${n.typ.type_name()}"')
	match n.typ {
		.program {
			b.write_string(',"body":')
			d.json_snodes(mut b, n.children)
			b.write_string(',"sourceType":"module"')
		}
		.script_element, .style_element, .element {
			if n.typ == .element {
				b.write_string(',"kind":"${n.kind}"')
			}
			b.write_string(',"name":')
			d.json_ref(mut b, n.name_ref)
			b.write_string(',"startTag":')
			d.json_snode(mut b, n.start_tag)
			if n.typ == .script_element {
				b.write_string(',"body":')
				d.json_es_list(mut b, n.body)
			} else {
				b.write_string(',"children":')
				d.json_snodes(mut b, n.children)
			}
			b.write_string(',"endTag":')
			if n.end_tag >= 0 {
				d.json_snode(mut b, n.end_tag)
			} else {
				b.write_string('null')
			}
		}
		.start_tag {
			b.write_string(',"attributes":')
			d.json_snodes(mut b, n.attributes)
			b.write_string(',"selfClosing":${json_bool(n.self_closing)}')
		}
		.end_tag, .special_directive_key {}
		.name {
			b.write_string(',"name":${estree.quote(n.name)}')
		}
		.member_expression_name {
			b.write_string(',"object":')
			d.json_ref(mut b, n.object)
			b.write_string(',"property":')
			d.json_snode(mut b, n.property)
		}
		.text, .literal, .html_comment {
			b.write_string(',"value":${estree.quote(n.value)}')
		}
		.mustache_tag {
			b.write_string(',"kind":"${n.kind}","expression":')
			d.json_ref(mut b, n.expression)
		}
		.debug_tag {
			b.write_string(',"identifiers":')
			d.json_es_list(mut b, n.identifiers)
		}
		.const_tag {
			b.write_string(',"declarations":')
			d.json_es_list(mut b, n.declarations)
		}
		.declaration_tag {
			b.write_string(',"declaration":')
			d.json_ref(mut b, n.declaration)
		}
		.render_tag, .attach_tag, .key_block {
			b.write_string(',"expression":')
			d.json_ref(mut b, n.expression)
			if n.typ == .key_block {
				b.write_string(',"children":')
				d.json_snodes(mut b, n.children)
			}
		}
		.if_block {
			b.write_string(',"elseif":${json_bool(n.elseif)},"expression":')
			d.json_ref(mut b, n.expression)
			b.write_string(',"children":')
			d.json_snodes(mut b, n.children)
			b.write_string(',"else":')
			if n.else_ >= 0 {
				d.json_snode(mut b, n.else_)
			} else {
				b.write_string('null')
			}
		}
		.else_block {
			b.write_string(',"elseif":${json_bool(n.elseif)},"children":')
			d.json_snodes(mut b, n.children)
		}
		.each_block {
			b.write_string(',"expression":')
			d.json_ref(mut b, n.expression)
			b.write_string(',"context":')
			d.json_ref(mut b, n.context)
			b.write_string(',"index":')
			d.json_ref(mut b, n.index_ref)
			b.write_string(',"key":')
			d.json_ref(mut b, n.key_expr)
			b.write_string(',"children":')
			d.json_snodes(mut b, n.children)
			b.write_string(',"else":')
			if n.else_ >= 0 {
				d.json_snode(mut b, n.else_)
			} else {
				b.write_string('null')
			}
		}
		.await_block {
			b.write_string(',"expression":')
			d.json_ref(mut b, n.expression)
			b.write_string(',"kind":"${n.kind}","pending":')
			d.json_opt_snode(mut b, n.pending)
			b.write_string(',"then":')
			d.json_opt_snode(mut b, n.then)
			b.write_string(',"catch":')
			d.json_opt_snode(mut b, n.catch_)
		}
		.await_pending_block {
			b.write_string(',"children":')
			d.json_snodes(mut b, n.children)
		}
		.await_then_block {
			b.write_string(',"awaitThen":${json_bool(n.await_then)},"value":')
			d.json_ref(mut b, n.value_es)
			b.write_string(',"children":')
			d.json_snodes(mut b, n.children)
		}
		.await_catch_block {
			b.write_string(',"awaitCatch":${json_bool(n.await_catch)},"error":')
			d.json_ref(mut b, n.error_es)
			b.write_string(',"children":')
			d.json_snodes(mut b, n.children)
		}
		.snippet_block {
			b.write_string(',"id":')
			d.json_ref(mut b, n.id)
			b.write_string(',"params":')
			d.json_es_list(mut b, n.params)
			b.write_string(',"children":')
			d.json_snodes(mut b, n.children)
		}
		.attribute {
			b.write_string(',"boolean":${json_bool(n.boolean)},"key":')
			d.json_ref(mut b, n.key)
			b.write_string(',"value":')
			d.json_snodes(mut b, n.values)
		}
		.shorthand_attribute {
			b.write_string(',"key":')
			d.json_ref(mut b, n.key)
			b.write_string(',"value":')
			d.json_ref(mut b, n.value_ref)
		}
		.spread_attribute {
			b.write_string(',"argument":')
			d.json_ref(mut b, n.expression)
		}
		.directive {
			b.write_string(',"kind":"${n.kind}","key":')
			d.json_ref(mut b, n.key)
			if n.kind in ['Binding', 'Class'] {
				b.write_string(',"shorthand":${json_bool(n.shorthand)}')
			}
			if n.kind == 'Transition' {
				b.write_string(',"intro":${json_bool(n.intro)},"outro":${json_bool(n.outro)}')
			}
			b.write_string(',"expression":')
			if n.function_bindings && n.expression.es {
				d.json_es(mut b, n.expression.idx, 'SvelteFunctionBindingsExpression')
			} else {
				d.json_ref(mut b, n.expression)
			}
		}
		.style_directive {
			b.write_string(',"key":')
			d.json_ref(mut b, n.key)
			b.write_string(',"shorthand":${json_bool(n.shorthand)},"value":')
			d.json_snodes(mut b, n.values)
		}
		.special_directive {
			b.write_string(',"kind":"${n.kind}","key":')
			d.json_ref(mut b, n.key)
			b.write_string(',"expression":')
			d.json_ref(mut b, n.expression)
		}
		.generics_directive {
			b.write_string(',"key":')
			d.json_ref(mut b, n.key)
			b.write_string(',"params":')
			d.json_es_list(mut b, n.generic_params)
		}
		.directive_key {
			b.write_string(',"name":')
			d.json_ref(mut b, n.key)
			b.write_string(',"modifiers":[')
			for k, m in n.modifiers {
				if k > 0 {
					b.write_u8(`,`)
				}
				b.write_string(estree.quote(m))
			}
			b.write_u8(`]`)
		}
	}
	b.write_u8(`,`)
	end := if n.loc_end >= 0 { n.loc_end } else { n.end }
	b.write_string('"range":[${d.utf16(n.start)},${d.utf16(n.end)}],"loc":')
	d.json_loc(mut b, n.start, end)
	b.write_u8(`}`)
}

fn (d &Document) json_opt_snode(mut b strings.Builder, i int) {
	if i < 0 {
		b.write_string('null')
	} else {
		d.json_snode(mut b, i)
	}
}

// json_es writes an ESTree node (type_override: SvelteFunctionBindingsExpression).
fn (d &Document) json_es(mut b strings.Builder, i int, type_override string) {
	es := &d.es
	n := es.nodes[i]
	typ := if type_override != '' { type_override } else { d.es_type_name(i) }
	b.write_string('{"type":"${typ}",')
	d.json_range_loc(mut b, n.start, n.end)
	for p in n.props {
		b.write_string(',${estree.quote(p.key.key_name())}:')
		match p.kind {
			.null {
				b.write_string('null')
			}
			.bool {
				b.write_string(json_bool(p.b))
			}
			.number {
				b.write_string('{"\$num":"${f64_hex(p.num)}"}')
			}
			.string {
				b.write_string(estree.quote(p.str))
			}
			.node {
				d.json_es(mut b, p.idx, '')
			}
			.list {
				b.write_u8(`[`)
				for k, item in es.lists[p.idx] {
					if k > 0 {
						b.write_u8(`,`)
					}
					if item < 0 {
						b.write_string('null')
					} else {
						d.json_es(mut b, item, '')
					}
				}
				b.write_u8(`]`)
			}
			.regex {
				b.write_string('{"flags":${estree.quote(p.str2)},"pattern":${estree.quote(p.str)}}')
			}
			.template {
				cooked := if p.b { 'null' } else { estree.quote(p.str) }
				b.write_string('{"cooked":${cooked},"raw":${estree.quote(p.str2)}}')
			}
			.bigint {
				b.write_string('{"\$bigint":${estree.quote(p.str)}}')
			}
			.regexp {
				b.write_string('{"\$regexp":true}')
			}
		}
	}
	b.write_u8(`}`)
}

fn f64_hex(f f64) string {
	bits := unsafe { *(&u64(&f)) }
	s := bits.hex()
	return '0'.repeat(16 - s.len) + s
}

// json_string quotes a string for JSON (UTF-16 escapes outside printable ASCII).
pub fn json_string(s string) string {
	return estree.quote(s)
}
