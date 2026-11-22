module rules

import json2

// Port of the `svelte/no-trailing-spaces` rule of eslint-plugin-svelte 3.24.1 (its own code, not a
// wrapper): the white space (String#trimEnd's) at the end of each line of sourceCode.lines is
// reported and removed, but on the lines a TemplateElement spans (but its last), with
// `skipBlankLines` the lines of white space only, and with `ignoreComments` the lines of the
// comments (a block comment's but its last) and of the HTML comments (but their last). It has no
// conditions: it lints every file.

const svnts_messages = {
	'trailingSpace': 'Trailing spaces not allowed.'
}

struct SvntsOptions {
	skip_blank_lines bool
	ignore_comments  bool
}

fn svnts_options(options []json2.Any) !SvntsOptions {
	o := option_object(svelte_no_trailing_spaces, options, ['skipBlankLines', 'ignoreComments'])!
	return SvntsOptions{
		skip_blank_lines: o.bool_value('skipBlankLines')!
		ignore_comments:  o.bool_value('ignoreComments')!
	}
}

// svnts_is_js_space: the code point is white space or a line terminator for String#trim.
fn svnts_is_js_space(r rune) bool {
	return r in [`\t`, `\n`, `\v`, `\f`, `\r`, ` `, ` `, ` `, ` `, ` `, ` `, ` `, `　`,
		`﻿`] || (r >= ` ` && r <= ` `)
}

// svnts_trimmed_end is where line.trimEnd() ends (a byte offset of the line).
fn svnts_trimmed_end(line string) int {
	mut end := line.len
	for end > 0 {
		mut first := end - 1
		for first > 0 && line[first] & 0xc0 == 0x80 {
			first--
		}
		r := line[first..end].runes()
		if r.len != 1 || !svnts_is_js_space(r[0]) {
			break
		}
		end = first
	}
	return end
}

// svnts_line_starts are the starts of the lines of ESLint's sourceCode.lines.
fn svnts_line_starts(text string) []int {
	mut out := [0]
	mut start := 0
	for {
		_, next := sntr_line_end(text, start)
		if next < 0 {
			break
		}
		out << next
		start = next
	}
	return out
}

// svnts_line is the 1-based line of a byte offset among `starts`.
fn svnts_line(starts []int, offset int) int {
	mut lo := 0
	mut hi := starts.len
	for lo < hi {
		mid := (lo + hi) / 2
		if starts[mid] <= offset {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo
}

fn (mut c Checker) lint_svelte_no_trailing_spaces(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	o := svnts_options(c.rule_options(svelte_no_trailing_spaces))!
	text := c.file_text()
	starts := svnts_line_starts(text)
	// A node's loc is its parser's: svelte-eslint-parser's lines for a .svelte file.
	mut ignored := map[int]bool{}
	add := fn [mut ignored] (first int, last int) {
		for line in first .. last + 1 {
			ignored[line] = true
		}
	}
	line_of := fn [c, starts] (offset int) int {
		if c.is_svelte() {
			return c.svelte.doc.loc(offset).line
		}
		return svnts_line(starts, offset)
	}
	if o.ignore_comments {
		if c.is_svelte() {
			for comment in c.svelte.doc.comments {
				last := line_of(comment.end)
				add(line_of(comment.start), if comment.typ == 'Block' { last - 1 } else { last })
			}
		} else {
			for comment in c.source_tokens(root).comments {
				last := line_of(comment.end)
				add(line_of(comment.start), if comment.kind == .block_comment {
					last - 1
				} else {
					last
				})
			}
		}
	}
	if e := c.svsc_es(root, abs_path) {
		for i in e.entered() {
			if e.t.typ(i) == .template_element {
				add(line_of(e.t.nodes[i].start), line_of(e.t.nodes[i].end) - 1)
			}
		}
	}
	if o.ignore_comments && c.is_svelte() {
		for i in c.sv_snodes_of(.html_comment) {
			n := c.svelte.doc.nodes[i]
			add(line_of(n.start), line_of(n.end) - 1)
		}
	}
	mut findings := []Finding{}
	for k, start in starts {
		end, _ := sntr_line_end(text, start)
		line := text[start..end]
		trimmed := svnts_trimmed_end(line)
		if o.skip_blank_lines && svnts_trimmed_end(line) == 0 {
			continue
		}
		if (k + 1) in ignored || trimmed == line.len {
			continue
		}
		findings << Finding{
			stmt:       c.position_range(start + trimmed, end)
			message_id: 'trailingSpace'
			text_loc:   true
			has_fix:    true
			fix:        fix_replace_range(start + trimmed, end, '')
		}
	}
	return findings
}
