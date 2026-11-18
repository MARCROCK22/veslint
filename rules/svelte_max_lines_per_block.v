module rules

import json2
import postcss

// Port of the `svelte/max-lines-per-block` rule of eslint-plugin-svelte 3.24.1: the lines inside a
// <script> or <style> element (without its tag lines), and the lines of the template (the file
// without its top-level <script>, <style> and <svelte:options> elements), over their maximum;
// skipBlankLines and skipComments leave out blank lines and lines a comment fills (the script's
// comments, the HTML comments and, in a <style>, the comments of postcss's tokenizer).

const smlpb_messages = {
	'tooManyLines': '{{block}} block has too many lines ({{lineCount}}). Maximum allowed is {{max}}.'
}

struct SmlpbOptions {
	script           int // 0: none
	template         int
	style            int
	skip_blank_lines bool
	skip_comments    bool
}

fn smlpb_options(options []json2.Any) !SmlpbOptions {
	o := option_object(svelte_max_lines_per_block, options, ['script', 'template', 'style',
		'skipBlankLines', 'skipComments'])!
	number := fn [o] (key string) int {
		v := o.values[key] or { return 0 }
		return if v is f64 {
			int(v)
		} else if v is i64 {
			int(v)
		} else {
			0
		}
	}
	return SmlpbOptions{
		script:           number('script')
		template:         number('template')
		style:            number('style')
		skip_blank_lines: if 'skipBlankLines' in o.values {
			o.bool_value('skipBlankLines')!
		} else {
			false
		}
		skip_comments:    if 'skipComments' in o.values {
			o.bool_value('skipComments')!
		} else {
			false
		}
	}
}

// smlpb_lines is sourceCode.lines: the lines of the text (they end at CRLF, CR, LF, U+2028 and
// U+2029), as UTF-16 units.
fn smlpb_lines(src string) [][]u16 {
	u := postcss.units(src)
	mut out := [][]u16{}
	mut start := 0
	mut i := 0
	for i < u.len {
		c := u[i]
		if c == `\r` || c == `\n` || c == 0x2028 || c == 0x2029 {
			out << u[start..i].clone()
			if c == `\r` && i + 1 < u.len && u[i + 1] == `\n` {
				i++
			}
			start = i + 1
		}
		i++
	}
	out << u[start..].clone()
	return out
}

// smlpb_blank is `!s.trim()`.
fn smlpb_blank(s []u16) bool {
	return s.all(postcss.is_js_space(it))
}

// SmlpbLoc is a node's loc: lines from 1, columns of UTF-16 units from 0.
struct SmlpbLoc {
	start_line   int
	start_column int
	end_line     int
	end_column   int
}

fn (c &Checker) smlpb_loc(start int, end int) SmlpbLoc {
	s := c.svelte.doc.loc(start)
	e := c.svelte.doc.loc(end)
	return SmlpbLoc{s.line, s.column, e.line, e.column}
}

// smlpb_full_line is isFullLineComment.
fn smlpb_full_line(line []u16, number int, loc SmlpbLoc) bool {
	before := line[..if loc.start_column < line.len { loc.start_column } else { line.len }]
	after := if loc.end_column < line.len { line[loc.end_column..] } else { []u16{} }
	return (loc.start_line < number || smlpb_blank(before))
		&& (loc.end_line > number || smlpb_blank(after))
}

// smlpb_count is countLines: the lines between start_line and end_line.
fn smlpb_count(lines [][]u16, start_line int, end_line int, skip_blank bool, comment_lines map[int]bool) int {
	if end_line - start_line <= 1 {
		return 0
	}
	mut count := 0
	for i in start_line + 1 .. end_line {
		if skip_blank && (i - 1 >= lines.len || smlpb_blank(lines[i - 1])) {
			continue
		}
		if i in comment_lines {
			continue
		}
		count++
	}
	return count
}

// smlpb_comment_locs are the locs of sourceCode.getAllComments().
fn (c &Checker) smlpb_comment_locs() []SmlpbLoc {
	return c.svelte.doc.comments.map(c.smlpb_loc(it.start, it.end))
}

// smlpb_ast_comment_lines is collectAstCommentLines.
fn smlpb_ast_comment_lines(comments []SmlpbLoc, lines [][]u16, start_line int, end_line int) map[int]bool {
	mut out := map[int]bool{}
	for loc in comments {
		if loc.end_line < start_line || loc.start_line > end_line {
			continue
		}
		from := if loc.start_line > start_line { loc.start_line } else { start_line }
		to := if loc.end_line < end_line { loc.end_line } else { end_line }
		for i in from .. to + 1 {
			if i - 1 < lines.len && smlpb_full_line(lines[i - 1], i, loc) {
				out[i] = true
			}
		}
	}
	return out
}

// smlpb_css_comment_lines is collectCssCommentLines: the lines of the comments of postcss's
// tokenizer with no other token starting on them (none when it throws).
fn smlpb_css_comment_lines(lines [][]u16, start_line int, end_line int) map[int]bool {
	mut out := map[int]bool{}
	mut css := []u16{}
	for i in start_line - 1 .. end_line {
		if i < 0 || i >= lines.len {
			continue
		}
		if i > start_line - 1 {
			css << `\n`
		}
		css << lines[i]
	}
	if smlpb_blank(css) {
		return out
	}
	input := postcss.new_input(css, '')
	mut t := postcss.new_tokenizer(&input, .css, false, false)
	mut comment_lines := map[int]bool{}
	mut code_lines := map[int]bool{}
	for {
		token := t.next_token(false) or { return out }
		if token.is_none() {
			break
		}
		if token.start < 0 {
			continue
		}
		line, _ := input.from_offset(token.start)
		token_line := line + start_line - 1
		if token.typ == 'comment' {
			end_line_of := if token.end >= 0 {
				l, _ := input.from_offset(token.end)
				l + start_line - 1
			} else {
				token_line
			}
			for i in token_line .. end_line_of + 1 {
				comment_lines[i] = true
			}
		} else {
			code_lines[token_line] = true
		}
	}
	for line, _ in comment_lines {
		if line !in code_lines {
			out[line] = true
		}
	}
	return out
}

fn (mut c Checker) lint_svelte_max_lines_per_block(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	options := smlpb_options(c.rule_options(svelte_max_lines_per_block))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	lines := smlpb_lines(doc.src)
	mut findings := []Finding{}
	mut html_comments := []SmlpbLoc{}
	for i in c.sv_snodes() {
		n := doc.nodes[i]
		match n.typ {
			.html_comment {
				html_comments << c.smlpb_loc(n.start, c.sv_snode_loc_end(i))
			}
			.script_element, .style_element {
				max := if n.typ == .script_element { options.script } else { options.style }
				if max == 0 {
					continue
				}
				loc := c.smlpb_loc(n.start, c.sv_snode_loc_end(i))
				comment_lines := if !options.skip_comments {
					map[int]bool{}
				} else if n.typ == .script_element {
					smlpb_ast_comment_lines(c.smlpb_comment_locs(), lines, loc.start_line + 1,
						loc.end_line - 1)
				} else {
					smlpb_css_comment_lines(lines, loc.start_line + 1, loc.end_line - 1)
				}
				count := smlpb_count(lines, loc.start_line, loc.end_line, options.skip_blank_lines,
					comment_lines)
				if count > max {
					findings << c.sv_report_snode(i, 'tooManyLines', {
						'block':     if n.typ == .script_element { '<script>' } else { '<style>' }
						'lineCount': count.str()
						'max':       max.str()
					})
				}
			}
			else {}
		}
	}
	if options.template == 0 {
		return findings
	}
	mut excluded := map[int]bool{}
	mut first_template := -1
	for ch in doc.nodes[0].children {
		n := doc.nodes[ch]
		if n.typ in [.script_element, .style_element] || c.smlpb_is_svelte_options(ch) {
			loc := c.smlpb_loc(n.start, c.sv_snode_loc_end(ch))
			for l in loc.start_line .. loc.end_line + 1 {
				excluded[l] = true
			}
		} else if first_template < 0 {
			first_template = ch
		}
	}
	mut comment_lines := map[int]bool{}
	if options.skip_comments {
		mut all := html_comments.clone()
		all << c.smlpb_comment_locs()
		for loc in all {
			for l in loc.start_line .. loc.end_line + 1 {
				if l in excluded || l - 1 >= lines.len {
					continue
				}
				if smlpb_full_line(lines[l - 1], l, loc) {
					comment_lines[l] = true
				}
			}
		}
	}
	mut count := 0
	for l in 1 .. lines.len + 1 {
		if l in excluded {
			continue
		}
		if options.skip_blank_lines && smlpb_blank(lines[l - 1]) {
			continue
		}
		if l in comment_lines {
			continue
		}
		count++
	}
	if count > options.template && first_template >= 0 {
		findings << c.sv_report_snode(first_template, 'tooManyLines', {
			'block':     'template'
			'lineCount': count.str()
			'max':       options.template.str()
		})
	}
	return findings
}

fn (c &Checker) smlpb_is_svelte_options(i int) bool {
	doc := c.svelte.doc
	n := doc.nodes[i]
	return n.typ == .element && !n.name_ref.es && n.name_ref.idx >= 0
		&& doc.nodes[n.name_ref.idx].typ == .name && doc.nodes[n.name_ref.idx].name == 'svelte:options'
}
