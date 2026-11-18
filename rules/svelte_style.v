module rules

import os
import postcss
import svelte

// The CSS of a .svelte file for the svelte/* rules (prefix `svst_`): eslint-plugin-svelte 3.24.1's
// utils/css-utils (the `style` attributes, parsed by its TemplateSafeParser: postcss-safe-parser
// with a tokenizer that keeps a `{…}` of the template as one word) and svelte-eslint-parser
// 1.10.1's style context (the first <style> element, parsed by postcss or postcss-scss, and the
// selectors of its rules by postcss-selector-parser), on the port of those packages in postcss/.
// Offsets are bytes of the file; postcss counts UTF-16 units, which go through the document's
// tables.

// SvstInterp is an interpolation of a style: a SvelteMustacheTag of the attribute's value, or an
// expression of a template literal (`r`), with the range of that node (bytes).
struct SvstInterp {
	r     svelte.Ref
	start int
	end   int
}

enum SvstKind {
	decl
	comment
	inline
}

// SvstChild is a node of a style (SvelteStyleDeclaration, SvelteStyleComment or
// SvelteStyleInline), with its range (bytes; for an inline one, getRange of its interpolation).
struct SvstChild {
	kind  SvstKind
	start int
	end   int
mut:
	prop            string
	prop_start      int
	prop_end        int
	value           string
	value_start     int
	value_end       int
	important       bool
	prop_interps    []SvstInterp
	value_interps   []SvstInterp
	unknown_interps []SvstInterp
	interp          SvstInterp
}

// SvstRoot is a SvelteStyleRoot: the declarations, comments and interpolations of a style.
struct SvstRoot {
	nodes []SvstChild
}

// svst_safe_parse is safeParseCss of the text [start, end) of the file: none when the parser
// throws.
fn (c &Checker) svst_safe_parse(start int, end int) ?postcss.Root {
	css := postcss.units(c.sv_text(start, end))
	return postcss.parse(css, postcss.ParseOptions{
		safe:     true
		template: true
	}) or { return none }
}

// svst_parse_attribute is parseStyleAttributeValue of a `style` SvelteAttribute.
fn (c &Checker) svst_parse_attribute(attr int) ?SvstRoot {
	doc := c.svelte.doc
	values := doc.nodes[attr].values
	if values.len == 0 {
		return none
	}
	start := doc.nodes[values[0]].start
	root := c.svst_safe_parse(start, doc.nodes[values.last()].end)?
	mut interps := []SvstInterp{}
	for v in values {
		if doc.nodes[v].typ == .mustache_tag {
			interps << SvstInterp{
				r:     sv_snode_ref(v)
				start: doc.nodes[v].start
				end:   doc.nodes[v].end
			}
		}
	}
	return c.svst_convert_root(&root, interps, interps.map([it.start, it.end]), doc.utf16(start))
}

// svst_byte is the byte offset of the file of a UTF-16 offset of the style that starts at the
// UTF-16 offset `base`.
fn (c &Checker) svst_byte(base int, offset int) int {
	return c.svelte.doc.byte_offset(base + offset)
}

// svst_convert_root is convertRoot: the top-level nodes of the postcss tree with the
// interpolations put in the declarations they are in, or between them as inline nodes (`ranges`
// are their getRange); none when a node is a rule or an at-rule, or an interpolation is in a
// comment.
fn (c &Checker) svst_convert_root(root &postcss.Root, interps_in []SvstInterp, ranges_in [][]int, base int) ?SvstRoot {
	mut interps := interps_in.clone()
	mut ranges := ranges_in.clone()
	mut nodes := []SvstChild{}
	for child in root.nodes[0].nodes {
		mut converted := c.svst_convert_child(root, child, base)?
		for interps.len > 0 {
			t := interps[0]
			if t.end <= converted.start {
				nodes << svst_inline(t, ranges[0])
				interps.delete(0)
				ranges.delete(0)
				continue
			}
			if t.start < converted.end {
				if converted.kind == .comment {
					return none
				}
				index := t.start
				if converted.prop_start <= index && index < converted.prop_end {
					converted.prop_interps << t
				} else if converted.value_start <= index && index < converted.value_end {
					converted.value_interps << t
				} else {
					converted.unknown_interps << t
				}
				interps.delete(0)
				ranges.delete(0)
				continue
			}
			break
		}
		nodes << converted
	}
	for k, t in interps {
		nodes << svst_inline(t, ranges[k])
	}
	return SvstRoot{
		nodes: nodes
	}
}

fn svst_inline(t SvstInterp, range []int) SvstChild {
	return SvstChild{
		kind:   .inline
		start:  range[0]
		end:    range[1]
		interp: t
	}
}

// svst_convert_child is convertChild: a declaration or a comment, none for anything else.
fn (c &Checker) svst_convert_child(root &postcss.Root, i int, base int) ?SvstChild {
	n := root.nodes[i]
	start := c.svst_byte(base, n.start.offset)
	end := c.svst_byte(base, n.end.offset)
	match n.typ {
		.decl {
			prop_end := n.start.offset + postcss.u16_len(n.prop)
			value_start := prop_end + postcss.u16_len(n.between)
			return SvstChild{
				kind:        .decl
				start:       start
				end:         end
				prop:        n.prop
				prop_start:  start
				prop_end:    c.svst_byte(base, prop_end)
				value:       n.value
				value_start: c.svst_byte(base, value_start)
				value_end:   c.svst_byte(base, value_start + postcss.u16_len(n.value))
				important:   n.important
			}
		}
		.comment {
			return SvstChild{
				kind:  .comment
				start: start
				end:   end
			}
		}
		else {
			return none
		}
	}
}

// svst_is_string_literal is isStringLiteral: a Literal whose value is a string.
fn (c &Checker) svst_is_string_literal(node int) bool {
	es := &c.svelte.doc.es
	return es.nodes[node].typ == .literal && es.get(node, .value) is string
}

// svst_inline_style is getInlineStyle of an interpolation (a mustache tag's expression): the
// style of a string literal or a template literal.
fn (c &Checker) svst_inline_style(r svelte.Ref) ?SvstRoot {
	doc := c.svelte.doc
	if r.idx < 0 {
		return none
	}
	if !r.es {
		if doc.nodes[r.idx].typ == .mustache_tag {
			return c.svst_inline_style(doc.nodes[r.idx].expression)
		}
		return none
	}
	es := &doc.es
	node := r.idx
	n := es.nodes[node]
	if c.svst_is_string_literal(node) {
		root := c.svst_safe_parse(n.start + 1, n.end - 1)?
		return c.svst_convert_root(&root, [], [], doc.utf16(n.start) + 1)
	}
	if n.typ == .template_literal {
		root := c.svst_safe_parse(n.start + 1, n.end - 1)?
		quasis := es.list(node, .quasis) or { []int{} }
		expressions := es.list(node, .expressions) or { []int{} }
		mut interps := []SvstInterp{}
		mut ranges := [][]int{}
		for k, e in expressions {
			interps << SvstInterp{
				r:     sv_es_ref(e)
				start: es.nodes[e].start
				end:   es.nodes[e].end
			}
			ranges << [es.nodes[quasis[k]].end - 2, es.nodes[quasis[k + 1]].start + 1]
		}
		return c.svst_convert_root(&root, interps, ranges, doc.utf16(n.start) + 1)
	}
	return none
}

// svst_all_inline_styles is getAllInlineStyles: the styles of the string and template literals
// an interpolation may give (through conditional and logical expressions), in that order.
fn (c &Checker) svst_all_inline_styles(t SvstInterp) []SvstRoot {
	mut out := []SvstRoot{}
	for e in c.svst_extract_expressions(t.r) {
		if style := c.svst_inline_style(sv_es_ref(e)) {
			out << style
		}
	}
	return out
}

fn (c &Checker) svst_extract_expressions(r svelte.Ref) []int {
	doc := c.svelte.doc
	if r.idx < 0 {
		return []
	}
	if !r.es {
		if doc.nodes[r.idx].typ == .mustache_tag && doc.nodes[r.idx].expression.es {
			return c.svst_extract_expressions(doc.nodes[r.idx].expression)
		}
		return []
	}
	es := &doc.es
	node := r.idx
	match es.nodes[node].typ {
		.template_literal {
			return [node]
		}
		.conditional_expression {
			mut out := []int{}
			if a := es.node(node, .consequent) {
				out << c.svst_extract_expressions(sv_es_ref(a))
			}
			if b := es.node(node, .alternate) {
				out << c.svst_extract_expressions(sv_es_ref(b))
			}
			return out
		}
		.logical_expression {
			mut out := []int{}
			if a := es.node(node, .left) {
				out << c.svst_extract_expressions(sv_es_ref(a))
			}
			if b := es.node(node, .right) {
				out << c.svst_extract_expressions(sv_es_ref(b))
			}
			return out
		}
		else {
			return if c.svst_is_string_literal(node) { [node] } else { []int{} }
		}
	}
}

// SvstDecl is a property of iterateStyleDeclSetFromAttrs (no-dupe-style-properties and
// no-shorthand-style-property-overrides) with its loc: a declaration's property (from
// getLocFromIndex, text_loc) or a style directive's name (a node's loc).
struct SvstDecl {
	prop     string
	start    int
	end      int
	text_loc bool
}

// svst_decl_sets_of_root is iterateStyleDeclSetFromStyleRoot: a set for each declaration, and
// one for the declarations of the inline styles of each interpolation.
fn (c &Checker) svst_decl_sets_of_root(root SvstRoot) [][]SvstDecl {
	mut out := [][]SvstDecl{}
	for child in root.nodes {
		if child.kind == .decl {
			out << [
				SvstDecl{
					prop:     child.prop
					start:    child.prop_start
					end:      child.prop_end
					text_loc: true
				},
			]
		} else if child.kind == .inline {
			mut decls := []SvstDecl{}
			for style in c.svst_all_inline_styles(child.interp) {
				for set in c.svst_decl_sets_of_root(style) {
					decls << set
				}
			}
			out << decls
		}
	}
	return out
}

// svst_decl_sets_of_tag is iterateStyleDeclSetFromAttrs of a start tag: a style directive's
// property (at its name), and the declarations of each `style` attribute.
fn (c &Checker) svst_decl_sets_of_tag(tag int) [][]SvstDecl {
	doc := c.svelte.doc
	mut out := [][]SvstDecl{}
	for a in doc.nodes[tag].attributes {
		n := doc.nodes[a]
		if n.typ == .style_directive {
			key := doc.nodes[n.key.idx]
			start, end := c.sv_ref_range(key.key)
			name_end := if !key.key.es && doc.nodes[key.key.idx].loc_end >= 0 {
				doc.nodes[key.key.idx].loc_end
			} else {
				end
			}
			out << [
				SvstDecl{
					prop:  c.sv_directive_key_name(a)
					start: start
					end:   name_end
				},
			]
		} else if n.typ == .attribute {
			if c.sv_attribute_name(a) != 'style' {
				continue
			}
			root := c.svst_parse_attribute(a) or { continue }
			out << c.svst_decl_sets_of_root(root)
		}
	}
	return out
}

fn (c &Checker) svst_report_decl(d SvstDecl, message_id string, data map[string]string) Finding {
	return if d.text_loc {
		c.sv_report_text(d.start, d.end, message_id, data)
	} else {
		c.sv_report(d.start, d.end, message_id, data)
	}
}

// svst_vendor_prefix is getVendorPrefix (utils/css-utils/utils.ts): /^-\w+-/u's match, or ''.
fn svst_vendor_prefix(prop string) string {
	if prop.len < 3 || prop[0] != `-` {
		return ''
	}
	mut i := 1
	for i < prop.len && (prop[i].is_letter() || prop[i].is_digit() || prop[i] == `_`) {
		i++
	}
	if i == 1 || i >= prop.len || prop[i] != `-` {
		return ''
	}
	return prop[..i + 1]
}

// --- svelte-eslint-parser's style context ---

enum SvstStatus {
	no_style_element
	success
	parse_error
	unknown_lang
}

// SvstContext is getStyleContext(): the first <style> element of the Program (with an end tag)
// parsed by postcss (lang `css`, `postcss` or none) or postcss-scss (`scss`).
struct SvstContext {
	status SvstStatus
	lang   string
	error  string
	style  int = -1
	root   postcss.Root
}

fn (c &Checker) svst_style_context(abs_path string) SvstContext {
	doc := c.svelte.doc
	mut style := -1
	for ch in doc.nodes[0].children {
		if doc.nodes[ch].typ == .style_element {
			style = ch
			break
		}
	}
	if style < 0 || doc.nodes[style].end_tag < 0 || doc.nodes[style].start_tag < 0 {
		return SvstContext{
			status: .no_style_element
		}
	}
	start_tag := doc.nodes[style].start_tag
	mut lang := 'css'
	for a in doc.nodes[start_tag].attributes {
		n := doc.nodes[a]
		if n.typ == .attribute && c.sv_attribute_name(a) == 'lang' && n.values.len > 0
			&& doc.nodes[n.values[0]].typ == .literal {
			lang = doc.nodes[n.values[0]].value
		}
	}
	syntax := match lang {
		'css', 'postcss' {
			postcss.Syntax.css
		}
		'scss' {
			postcss.Syntax.scss
		}
		else {
			return SvstContext{
				status: .unknown_lang
				lang:   lang
				style:  style
			}
		}
	}
	css := postcss.units(c.sv_text(doc.nodes[start_tag].end, doc.nodes[doc.nodes[style].end_tag].start))
	root := postcss.parse(css, postcss.ParseOptions{
		syntax: syntax
		from:   c.sv_file_path(abs_path)
	}) or {
		return SvstContext{
			status: .parse_error
			lang:   lang
			error:  err.msg()
			style:  style
		}
	}
	return SvstContext{
		status: .success
		lang:   lang
		style:  style
		root:   root
	}
}

// svst_parse_error_message is valid-style-parse's message of a parse error: the current
// directory taken out of the error's path.
fn svst_parse_error_message(message string) string {
	return message.replace_once(os.getwd() + os.path_separator, '')
}

// svst_selector_report is a report at a node of the selector of a rule of the style context:
// styleSelectorNodeLoc after svelte-eslint-parser's fixPostCSSNodeLocation of the rule and
// fixSelectorNodeLocation of the node (lines and columns, not offsets).
fn (c &Checker) svst_selector_report(ctx &SvstContext, rule int, sel &postcss.SelNode, message_id string) Finding {
	doc := c.svelte.doc
	style := doc.nodes[ctx.style]
	style_line := doc.loc(style.start).line
	tag_end_column := doc.loc(doc.nodes[style.start_tag].end).column
	rs := ctx.root.nodes[rule].start
	rule_line := rs.line + style_line - 1
	rule_column := rs.column + (if rule_line == style_line { tag_end_column } else { 0 }) - 1
	mut line := sel.start_line
	mut column := sel.start_column
	if line == 1 {
		column += rule_column
	}
	line += rule_line - 1
	mut end_line := sel.end_line
	mut end_column := sel.end_column
	if end_line == 1 {
		end_column += rule_column
	}
	end_line += rule_line - 1
	return Finding{
		stmt:             c.position_range(doc.offset_of_loc(line, column - 1), doc.offset_of_loc(end_line,
			end_column))
		message_id:       message_id
		line_loc:         true
		fixed_line:       line
		fixed_column:     column
		fixed_end_line:   end_line
		fixed_end_column: end_column + 1
	}
}
