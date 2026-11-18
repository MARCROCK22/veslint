module svelte

// Splitting the document (src/context/index.ts extractBlocks, the Context constructor; and
// src/parser/html.ts parseAttributes): the <script>, <style> and <template lang> blocks found
// by svelte-eslint-parser's own scan, the template code handed to the compiler (their contents
// blanked) and the script code (everything but the script contents blanked).

// Block is a <script>, <style> or <template> block of extractBlocks.
struct Block {
	tag          string // lower case
	original_tag string
	attrs        []int // Attribute nodes of the CAst of the blocks
	self_closing bool
	start_start  int
	start_end    int
	content_s    int
	content_e    int
	end_start    int
	end_end      int
}

// BlockAttrs is the arena of the attributes parseAttributes reads (CNodes with Text or
// ExpressionTag values, the ExpressionTag's expression a CExpr).
struct BlockAttrs {
mut:
	ast CAst
}

// is_valid_start_tag_open: `/>\s*$|^\s*$/m` on the text before the tag: true when some line of
// it is blank or ends with `>` and whitespace (or it is empty).
fn is_valid_start_tag_open(code string, idx int) bool {
	if idx == 0 {
		return true
	}
	// Scan the lines of code[..idx]: a line (between line terminators, `m` mode: \n, \r, U+2028,
	// U+2029) that is all whitespace, or whose last non-whitespace character is `>`.
	mut line_start := 0
	mut i := 0
	for {
		at_end := i >= idx
		mut is_term := false
		mut tlen := 1
		if !at_end {
			c := code[i]
			if c == `\n` || c == `\r` {
				is_term = true
			} else if is_line_sep(code, i) {
				is_term = true
				tlen = 3
			}
		}
		if at_end || is_term {
			line := code[line_start..if at_end { idx } else { i }]
			trimmed_len := js_trim_end_len(line)
			if trimmed_len == 0 || line[trimmed_len - 1] == `>` {
				// `^\s*$` on a blank line, or `>\s*$`. `\s*` also spans line terminators, so a `>`
				// followed by blank lines then the end counts too: covered by the blank line.
				return true
			}
			if at_end {
				return false
			}
			line_start = i + tlen
			i += tlen
			continue
		}
		i++
	}
	return false
}

// extract_blocks is extractBlocks: a scan for `<!--…-->` (skipped) and `<script`, `<style`,
// `<template` (any case) followed by whitespace or `>`.
fn extract_blocks(code string, mut attrs BlockAttrs) []Block {
	mut blocks := []Block{}
	lower := ascii_lower(code)
	mut i := 0
	for i < code.len {
		lt := code.index_after('<', i) or { break }
		if code[lt..].starts_with('<!--') {
			e := code.index_after('-->', lt + 4) or {
				// `<!--[\s\S]*?-->` does not match: the scan goes on from the next character.
				i = lt + 1
				continue
			}
			i = e + 3
			continue
		}
		mut tag := ''
		for t in ['script', 'style', 'template'] {
			if lower[lt + 1..].starts_with(t) {
				tag = t
				break
			}
		}
		if tag == '' {
			i = lt + 1
			continue
		}
		after := lt + 1 + tag.len
		if after >= code.len {
			i = lt + 1
			continue
		}
		next_ok, next_len := is_js_ws(code, after)
		if !next_ok && code[after] != `>` {
			i = lt + 1
			continue
		}
		last_index := after + if next_ok { next_len } else { 1 }
		if !is_valid_start_tag_open(code, lt) {
			i = last_index
			continue
		}
		original := code[lt + 1..after]
		mut start_end := last_index
		mut block_attrs := []int{}
		if next_ok {
			ba, index := parse_attributes(code, last_index, mut attrs)
			block_attrs = ba.clone()
			start_end = index
			if start_end + 1 < code.len && code[start_end] == `/` && code[start_end + 1] == `>` {
				blocks << Block{
					tag:          tag
					original_tag: original
					attrs:        block_attrs
					self_closing: true
					start_start:  lt
					start_end:    start_end + 2
				}
				i = last_index
				continue
			}
			if start_end < code.len && code[start_end] == `>` {
				start_end++
			} else {
				i = last_index
				continue
			}
		}
		close := '</${tag}>'
		end_start := lower.index_after(close, start_end) or {
			i = last_index
			continue
		}
		end_end := end_start + close.len
		blocks << Block{
			tag:          tag
			original_tag: original
			attrs:        block_attrs
			start_start:  lt
			start_end:    start_end
			content_s:    start_end
			content_e:    end_start
			end_start:    end_start
			end_end:      end_end
		}
		i = end_end
	}
	return blocks
}

// parse_attributes is html.ts parseAttributes: the attributes of a block's start tag, up to
// `>`, `/>` or the end.
fn parse_attributes(code string, start int, mut attrs BlockAttrs) ([]int, int) {
	mut out := []int{}
	mut i := start
	for i < code.len {
		i = skip_html_spaces(code, i)
		if i >= code.len || code[i] == `>` || (code[i] == `/` && i + 1 < code.len
			&& code[i + 1] == `>`) {
			break
		}
		a, ni := parse_attribute(code, i, mut attrs)
		out << a
		i = ni
	}
	return out, i
}

// skip_html_spaces is State.skipSpaces (`/^\s$/u` per character).
fn skip_html_spaces(code string, i0 int) int {
	mut i := i0
	for i < code.len {
		ok, n := is_js_ws(code, i)
		if !ok {
			break
		}
		i += n
	}
	return i
}

fn parse_attribute(code string, start int, mut attrs BlockAttrs) (int, int) {
	// The key: the first character always, then up to `=`, `>`, `/>` or whitespace.
	_, n0 := code_point_at(code, start)
	mut i := start + n0
	for i < code.len {
		c := code[i]
		if c == `=` || c == `>` || (c == `/` && i + 1 < code.len && code[i + 1] == `>`) {
			break
		}
		ok, n := is_js_ws(code, i)
		if ok {
			break
		}
		i += n
	}
	key := code[start..i]
	key_end := i
	i = skip_html_spaces(code, i)
	if i >= code.len || code[i] != `=` {
		return attrs.ast.add(CNode{
			typ:        .attribute
			start:      start
			end:        key_end
			name:       key
			value_kind: .true_
		}), i
	}
	i++
	i = skip_html_spaces(code, i)
	if i >= code.len {
		return attrs.ast.add(CNode{
			typ:        .attribute
			start:      start
			end:        key_end
			name:       key
			value_kind: .true_
		}), i
	}
	v, ni := parse_attribute_value(code, i, mut attrs)
	return attrs.ast.add(CNode{
		typ:        .attribute
		start:      start
		end:        ni
		name:       key
		value_kind: .array
		value:      [v]
	}), ni
}

fn parse_attribute_value(code string, start int, mut attrs BlockAttrs) (int, int) {
	mut i := start
	mut quote := u8(0)
	if code[i] == `"` || code[i] == `'` {
		quote = code[i]
		i++
	}
	if m := parse_attribute_mustache(code, i) {
		mut e := m.end_index
		if quote == 0 || (e < code.len && code[e] == quote) {
			if quote != 0 {
				e++
			}
			ex := attrs.ast.add_expr(CExpr{
				kind:  .other
				start: m.start
				end:   m.end
			})
			return attrs.ast.add(CNode{
				typ:        .expression_tag
				start:      start
				end:        e
				expression: ex
			}), e
		}
	}
	if quote != 0 {
		if i >= code.len {
			return attrs.ast.add(CNode{
				typ:   .text
				start: start
				end:   i
				data:  quote.ascii_str()
				raw:   quote.ascii_str()
			}), i
		}
		for i < code.len {
			c := code[i]
			i++
			if c == quote {
				data := code[start + 1..i - 1]
				return attrs.ast.add(CNode{
					typ:   .text
					start: start + 1
					end:   i - 1
					data:  data
					raw:   data
				}), i
			}
		}
	} else {
		_, n0 := code_point_at(code, i)
		i += n0
		for i < code.len {
			c := code[i]
			if c == `>` || (c == `/` && i + 1 < code.len && code[i + 1] == `>`) {
				break
			}
			ok, n := is_js_ws(code, i)
			if ok {
				break
			}
			i += n
		}
	}
	data := code[start..i]
	return attrs.ast.add(CNode{
		typ:   .text
		start: start
		end:   i
		data:  data
		raw:   data
	}), i
}

struct Mustache {
	start     int
	end       int
	end_index int // after the `}`
}

// parse_attribute_mustache is parseAttributeMustache: `{` then leading comments, then the text
// up to a `}` (strings skipped) that espree parses as an expression. svelte-eslint-parser
// tries each `}` in turn; any non-empty text is taken as an expression here (a block attribute
// written as `{…}` that espree rejects is not in the corpus).
fn parse_attribute_mustache(code string, i0 int) ?Mustache {
	if i0 >= code.len || code[i0] != `{` {
		return none
	}
	mut i := skip_html_spaces(code, i0 + 1)
	mut start := i
	for i < code.len {
		if code[i..].starts_with('//') {
			nl := code.index_after('\n', i + 2) or { code.len - 1 }
			i = skip_html_spaces(code, nl + 1)
			start = i
			continue
		}
		if code[i..].starts_with('/*') {
			e := code.index_after('*/', i + 2) or { code.len - 2 }
			i = skip_html_spaces(code, e + 2)
			start = i
			continue
		}
		if code[i] == `"` || code[i] == `'` {
			q := code[i]
			i++
			for i < code.len {
				if code[i] == q {
					i++
					break
				}
				if code[i] == `\\` {
					i++
				}
				i++
			}
			i = skip_html_spaces(code, i)
			continue
		}
		end_candidate := i
		i = skip_html_spaces(code, i)
		if i < code.len && code[i] == `}` {
			if end_candidate > start {
				return Mustache{start, end_candidate, i + 1}
			}
			return none
		}
		if i < code.len {
			_, n := code_point_at(code, i)
			i += n
		}
	}
	return none
}

// SourceCode is the Context's split of the document.
struct SourceCode {
mut:
	template     string // bytes: the file with block contents blanked (same length)
	script_raw   string // bytes: the file with everything but script contents blanked
	script_attrs map[string]string
	// attrs merged over the script blocks with a text value (lang, generics, context…); a
	// name with a non-text value maps to '\x00undefined'.
	blocks      []Block
	block_attrs BlockAttrs
}

const undefined_attr = '\x00undefined'

// split_document is the Context constructor's loop.
fn split_document(code string) SourceCode {
	mut sc := SourceCode{}
	sc.blocks = []
	blocks := extract_blocks(code, mut sc.block_attrs)
	mut template := []u8{cap: code.len}
	mut script := []u8{cap: code.len}
	mut start := 0
	blank := fn [code] (from int, to int, mut out []u8) {
		for k in from .. to {
			c := code[k]
			out << if c == `\n` || c == `\r` { c } else { ` ` }
		}
	}
	for b in blocks {
		if b.tag == 'template' {
			if b.self_closing {
				continue
			}
			mut lang_ok := false
			for a in b.attrs {
				an := sc.block_attrs.ast.nodes[a]
				if an.name != 'lang' {
					continue
				}
				// The first `lang` decides.
				if an.value_kind == .array && an.value.len > 0 {
					v := sc.block_attrs.ast.nodes[an.value[0]]
					lang_ok = v.typ == .text && v.data != 'html'
				}
				break
			}
			if !lang_ok {
				continue
			}
		}
		sc.blocks << b
		if b.self_closing {
			template << code[start..b.start_start + 2].bytes()
			for _ in 0 .. b.tag.len - 1 {
				template << `-`
			}
			template << code[b.start_start + 1 + b.tag.len..b.start_end].bytes()
			blank(start, b.start_end, mut script)
			start = b.start_end
		} else {
			template << code[start..b.content_s].bytes()
			blank(b.content_s, b.content_e, mut template)
			if b.tag == 'script' {
				blank(start, b.content_s, mut script)
				script << code[b.content_s..b.content_e].bytes()
				for a in b.attrs {
					an := sc.block_attrs.ast.nodes[a]
					if an.value_kind == .array {
						v := sc.block_attrs.ast.nodes[an.value[0]]
						sc.script_attrs[an.name] = if v.typ == .text {
							v.data
						} else {
							undefined_attr
						}
					}
				}
			} else {
				blank(start, b.content_e, mut script)
			}
			start = b.content_e
		}
	}
	template << code[start..].bytes()
	blank(start, code.len, mut script)
	sc.template = template.bytestr()
	sc.script_raw = script.bytestr()
	return sc
}

// find_block is Context.findBlock: the non-self-closing block of that tag whose content is
// inside [start, end).
fn (sc &SourceCode) find_block(tag string, start int, end int) ?Block {
	for b in sc.blocks {
		if b.tag == tag && !b.self_closing && start <= b.content_s && b.content_e <= end {
			return b
		}
	}
	return none
}

// find_self_closing_block is Context.findSelfClosingBlock.
fn (sc &SourceCode) find_self_closing_block(start int, end int) ?Block {
	for b in sc.blocks {
		if b.self_closing && start <= b.start_start && b.start_end <= end {
			return b
		}
	}
	return none
}
