module vue

import estree
import strings

// to_json writes the document as tools/vue_parse_diff.mjs compares it with vue-eslint-parser's:
// the document fragment (no `parent`), which child is templateBody, the tokens, comments and
// errors, the Program's range, tokens and comments, and every code handed to the script parser.
// Ranges are UTF-16 offsets, as in ESLint; numbers of ESTree properties are the bits of the
// double (`{"$num": hex}`).
pub fn (d &Document) to_json() string {
	mut b := strings.new_builder(d.src.len * 8 + 256)
	b.write_string('{"document":')
	d.json_vnode(mut b, 0)
	b.write_string(',"templateBody":')
	if d.template_body >= 0 {
		b.write_string(d.nodes[0].children.index(d.template_body).str())
	} else {
		b.write_string('null')
	}
	b.write_string(',"tokens":')
	d.json_tokens(mut b, d.tokens)
	b.write_string(',"comments":')
	d.json_tokens(mut b, d.comments)
	b.write_string(',"errors":[')
	for i, e in d.errors {
		if i > 0 {
			b.write_u8(`,`)
		}
		u := d.utf16_error(e.index)
		l := if e.line != 0 { Loc{e.line, e.column} } else { d.loc_u16(u) }
		b.write_string('{"message":${estree.quote(e.message)},"index":${u},"lineNumber":${l.line},"column":${l.column}')
		if e.code != '' {
			b.write_string(',"code":${estree.quote(e.code)}')
		}
		b.write_u8(`}`)
	}
	b.write_string('],"program":{')
	s := d.script
	b.write_string('"range":[${d.utf16(s.program_start)},${d.utf16(s.program_end)}],"loc":')
	d.json_loc(mut b, s.program_start, s.program_end)
	b.write_string(',"tokens":')
	d.json_tokens(mut b, s.tokens)
	b.write_string(',"comments":')
	d.json_tokens(mut b, s.comments)
	b.write_string('},"codes":[')
	mut first := true
	for code in d.parser_codes() {
		if !first {
			b.write_u8(`,`)
		}
		first = false
		b.write_string(estree.quote(code))
	}
	b.write_string(']}')
	return b.str()
}

// utf16_error converts the index of an error, which may be past the end of the file.
fn (d &Document) utf16_error(index int) int {
	if index > d.src.len {
		return d.index.u16_len + (index - d.src.len)
	}
	return d.utf16(index)
}

// parser_codes are the codes handed to the script parser, in no particular order.
pub fn (d &Document) parser_codes() []string {
	mut out := []string{}
	for s in d.snippets {
		out << s.code
	}
	out << d.script.codes
	return out
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
		d.json_range_loc(mut b, t.start, t.end)
		b.write_u8(`}`)
	}
	b.write_u8(`]`)
}

fn (d &Document) json_id(mut b strings.Builder, e Expr, name string) {
	if e.kind != .estree {
		b.write_string('null')
		return
	}
	n := d.snippets[e.snippet].es.nodes[e.node]
	b.write_string('{"name":${estree.quote(name)},"range":[${d.utf16(n.start)},${d.utf16(n.end)}]}')
}

fn (d &Document) json_vnode(mut b strings.Builder, i int) {
	if i < 0 {
		b.write_string('null')
		return
	}
	n := d.nodes[i]
	b.write_string('{"type":"${n.typ.type_name()}",')
	ls := if n.loc_start >= 0 { n.loc_start } else { n.start }
	le := if n.loc_end >= 0 { n.loc_end } else { n.end }
	b.write_string('"range":[${d.utf16(n.start)},${d.utf16(n.end)}],"loc":')
	d.json_loc(mut b, ls, le)
	match n.typ {
		.v_document_fragment {
			b.write_string(',"children":')
			d.json_vnodes(mut b, n.children)
		}
		.v_element {
			b.write_string(',"name":${estree.quote(n.name)},"rawName":${estree.quote(n.raw_name)},"namespace":"${n.namespace.uri()}","startTag":')
			d.json_vnode(mut b, n.start_tag)
			b.write_string(',"children":')
			d.json_vnodes(mut b, n.children)
			b.write_string(',"endTag":')
			d.json_vnode(mut b, n.end_tag)
			b.write_string(',"variables":[')
			for k, v in n.variables {
				if k > 0 {
					b.write_u8(`,`)
				}
				variable := d.variables[v]
				b.write_string('{"id":')
				d.json_id(mut b, variable.id, variable.name)
				b.write_string(',"kind":"${variable.kind}","references":[')
				for m, r in variable.references {
					if m > 0 {
						b.write_u8(`,`)
					}
					id := d.references[r].id
					rn := d.snippets[id.snippet].es.nodes[id.node]
					b.write_string('[${d.utf16(rn.start)},${d.utf16(rn.end)}]')
				}
				b.write_string(']}')
			}
			b.write_u8(`]`)
			if n.style {
				b.write_string(',"style":true')
			}
		}
		.v_start_tag {
			b.write_string(',"selfClosing":${n.self_closing},"attributes":')
			d.json_vnodes(mut b, n.attributes)
		}
		.v_end_tag {}
		.v_attribute {
			b.write_string(',"directive":${n.directive},"key":')
			d.json_vnode(mut b, n.key)
			b.write_string(',"value":')
			d.json_vnode(mut b, n.value)
		}
		.v_identifier {
			b.write_string(',"name":${estree.quote(n.name)},"rawName":${estree.quote(n.raw_name)}')
		}
		.v_directive_key {
			b.write_string(',"name":')
			d.json_vnode(mut b, n.dir_name)
			b.write_string(',"argument":')
			d.json_vnode(mut b, n.argument)
			b.write_string(',"modifiers":')
			d.json_vnodes(mut b, n.modifiers)
		}
		.v_literal, .v_text {
			b.write_string(',"value":${estree.quote(n.text)}')
		}
		.v_expression_container {
			b.write_string(',"expression":')
			d.json_expr(mut b, n.expression)
			b.write_string(',"references":[')
			for k, r in n.references {
				if k > 0 {
					b.write_u8(`,`)
				}
				ref := d.references[r]
				b.write_string('{"id":')
				d.json_id(mut b, ref.id, ref.name)
				b.write_string(',"mode":"${ref.mode}","variable":')
				if ref.variable >= 0 {
					v := d.variables[ref.variable]
					d.json_id(mut b, v.id, v.name)
				} else {
					b.write_string('null')
				}
				if ref.has_kind {
					b.write_string(',"isValueReference":${ref.is_value_reference},"isTypeReference":${ref.is_type_reference}')
				}
				b.write_u8(`}`)
			}
			b.write_u8(`]`)
		}
		.v_for_expression {
			b.write_string(',"left":')
			d.json_exprs(mut b, n.exprs)
			b.write_string(',"right":')
			d.json_expr(mut b, n.right)
		}
		.v_on_expression {
			b.write_string(',"body":')
			d.json_exprs(mut b, n.exprs)
		}
		.v_slot_scope_expression {
			b.write_string(',"params":')
			d.json_exprs(mut b, n.exprs)
		}
		.v_generic_expression {
			b.write_string(',"params":')
			d.json_exprs(mut b, n.exprs)
			b.write_string(',"rawParams":[')
			for k, p in n.raw_params {
				if k > 0 {
					b.write_u8(`,`)
				}
				b.write_string(estree.quote(p))
			}
			b.write_u8(`]`)
		}
		.v_filter_sequence_expression {
			b.write_string(',"expression":')
			d.json_expr(mut b, n.expression)
			b.write_string(',"filters":')
			d.json_vnodes(mut b, n.filters)
		}
		.v_filter {
			b.write_string(',"callee":{"type":"Identifier",')
			d.json_range_loc(mut b, n.callee_start, n.callee_end)
			b.write_string(',"name":${estree.quote(n.callee_name)}},"arguments":')
			d.json_exprs(mut b, n.exprs)
		}
	}
	b.write_u8(`}`)
}

fn (d &Document) json_vnodes(mut b strings.Builder, list []int) {
	b.write_u8(`[`)
	for k, c in list {
		if k > 0 {
			b.write_u8(`,`)
		}
		d.json_vnode(mut b, c)
	}
	b.write_u8(`]`)
}

fn (d &Document) json_exprs(mut b strings.Builder, list []Expr) {
	b.write_u8(`[`)
	for k, e in list {
		if k > 0 {
			b.write_u8(`,`)
		}
		d.json_expr(mut b, e)
	}
	b.write_u8(`]`)
}

fn (d &Document) json_expr(mut b strings.Builder, e Expr) {
	match e.kind {
		.null { b.write_string('null') }
		.vnode { d.json_vnode(mut b, e.node) }
		.estree { d.json_es(mut b, &d.snippets[e.snippet].es, e.node) }
	}
}

fn (d &Document) json_es(mut b strings.Builder, es &estree.EsTree, i int) {
	n := es.nodes[i]
	b.write_string('{"type":"${n.typ.type_name()}",')
	d.json_range_loc(mut b, n.start, n.end)
	for p in n.props {
		b.write_string(',${estree.quote(p.key.key_name())}:')
		match p.kind {
			.null {
				b.write_string('null')
			}
			.bool {
				b.write_string(if p.b { 'true' } else { 'false' })
			}
			.number {
				b.write_string('{"\$num":"${f64_hex(p.num)}"}')
			}
			.string {
				b.write_string(estree.quote(p.str))
			}
			.node {
				d.json_es(mut b, es, p.idx)
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
						d.json_es(mut b, es, item)
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
