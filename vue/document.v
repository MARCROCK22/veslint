module vue

import treesitter

// Document is a parsed .vue file. nodes[0] is the VDocumentFragment; `tokens`, `comments` and
// `errors` are its arrays (also templateBody's). It holds tree-sitter trees: call free() when done.
@[heap]
pub struct Document {
pub mut:
	src        string
	nodes      []VNode
	tokens     []Token
	comments   []Token
	errors     []ParseError
	references []Reference
	variables  []Variable
	snippets   []Snippet
	// template_body is the element vue-eslint-parser makes `templateBody`, or -1.
	template_body int = -1
	script        ScriptInfo
	// line_terminators are the UTF-16 offsets right after each LF (vue-eslint-parser breaks
	// lines at LF only); gaps the UTF-16 offsets of the source the decoded text skips.
	line_terminators []int
	gaps             []int
	index            TextIndex
	// line_starts are the byte offsets of the starts of the lines (0, then after each LF).
	line_starts []int
}

pub struct Loc {
pub:
	line   int // from 1
	column int // UTF-16 units from 0
}

// add_node appends a node and gives its index.
fn (mut d Document) add_node(n VNode) int {
	d.nodes << n
	return d.nodes.len - 1
}

// loc is vue-eslint-parser's location of a byte offset.
pub fn (d &Document) loc(offset int) Loc {
	return d.loc_u16(d.index.to_u16(offset))
}

// loc_u16 is getLocFromIndex of a UTF-16 offset.
fn (d &Document) loc_u16(u int) Loc {
	line := sorted_last_index(d.line_terminators, u) + 1
	column := u - if line == 1 { 0 } else { d.line_terminators[line - 2] }
	return Loc{line, column}
}

// utf16 converts a byte offset of the file to a UTF-16 offset (ESLint's `range`).
pub fn (d &Document) utf16(offset int) int {
	return d.index.to_u16(offset)
}

// lang_of is getLang: the value of the first plain `lang` attribute of the element, if not empty.
pub fn (d &Document) lang_of(element int) ?string {
	start_tag := d.nodes[d.nodes[element].start_tag]
	for a in start_tag.attributes {
		attr := d.nodes[a]
		if attr.directive || d.nodes[attr.key].name != 'lang' {
			continue
		}
		if attr.value < 0 {
			return none
		}
		v := d.nodes[attr.value].text
		if v == '' {
			return none
		}
		return v
	}
	return none
}

// has_plain_attribute tells whether the element has a plain attribute of that (lower-cased) name.
pub fn (d &Document) has_plain_attribute(element int, name string) bool {
	start_tag := d.nodes[d.nodes[element].start_tag]
	for a in start_tag.attributes {
		attr := d.nodes[a]
		if !attr.directive && d.nodes[attr.key].name == name {
			return true
		}
	}
	return false
}

// is_script_setup is isScriptSetupElement.
pub fn (d &Document) is_script_setup(element int) bool {
	return d.nodes[element].name == 'script' && d.has_plain_attribute(element, 'setup')
}

// top_elements are the top-level elements named `name` (lower-cased), in order.
pub fn (d &Document) top_elements(name string) []int {
	mut out := []int{}
	for c in d.nodes[0].children {
		if d.nodes[c].typ == .v_element && d.nodes[c].name == name {
			out << c
		}
	}
	return out
}

// free deletes the tree-sitter trees of the snippets (and of the script, see ScriptInfo).
pub fn (mut d Document) free() {
	for mut s in d.snippets {
		if s.tree != unsafe { nil } {
			treesitter.tree_delete(s.tree)
			s.tree = unsafe { nil }
		}
	}
	if d.script.tree != unsafe { nil } {
		treesitter.tree_delete(d.script.tree)
		d.script.tree = unsafe { nil }
	}
}

// parse_sfc parses a .vue file (UTF-8, without BOM) as vue-eslint-parser 10.4.2 does with
// typescript-eslint's parser for its scripts and template expressions. To parse many files,
// make the Parsers once and use parse_sfc_with.
pub fn parse_sfc(src string) !&Document {
	parsers := new_parsers()!
	defer {
		parsers.close()
	}
	return parse_sfc_with(src, Options{}, parsers)
}

// parse_sfc_with is parse_sfc with vueFeatures options and parsers kept from file to file.
pub fn parse_sfc_with(src string, opts Options, parsers &Parsers) !&Document {
	mut doc := &Document{
		src:   src
		index: new_text_index(src)
	}
	doc.nodes << VNode{
		typ: .v_document_fragment
	}
	mut p := SfcParser{
		tz:  new_tokenizer(src, opts)
		doc: doc
	}
	p.parse()
	doc.line_terminators = p.tz.line_terminators
	doc.gaps = p.tz.gaps
	doc.errors = p.tz.errors
	doc.line_starts = [0]
	for lt in doc.line_terminators {
		doc.line_starts << doc.index.to_byte(lt)
	}
	mut ctx := new_expr_context(doc, opts, parsers)
	ctx.run_postprocesses(p.post)
	ctx.flush_tokens()
	doc.select_template_body()
	ctx.parse_script()
	if opts.style_css_variable_injection {
		ctx.parse_styles()
		ctx.flush_tokens()
	}
	return doc
}

// select_template_body sets template_body: the first top-level <template>, if its lang is html.
fn (mut d Document) select_template_body() {
	for c in d.nodes[0].children {
		if d.nodes[c].typ == .v_element && d.nodes[c].name == 'template' {
			lang := d.lang_of(c) or { 'html' }
			if lang == 'html' {
				d.template_body = c
			}
			return
		}
	}
}
