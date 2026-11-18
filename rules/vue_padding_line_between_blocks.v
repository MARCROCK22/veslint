module rules

import json2
import time
import vue

// Port of the `vue/padding-line-between-blocks` rule of eslint-plugin-vue 10.12.1 (option "always",
// the default, or "never"): between two top-level elements of the document, a blank line expected
// (fixed by a line break after the first line break, or two after the first block) or not
// (fixed by keeping one line break and the indentation of each blank run). The tokens and comments
// between the blocks count; nothing when the template has an `eof-*` parse error.

const vplbb_messages = {
	'never':  'Unexpected blank line before this block.'
	'always': 'Expected blank line before this block.'
}

fn vplbb_options(options []json2.Any) !bool {
	if options.len == 0 {
		return true
	}
	value := options[0]
	if value !is string || value as string !in ['always', 'never'] {
		return error('the option of `${vue_padding_line_between_blocks}` must be "always" or "never"')
	}
	return value as string == 'always'
}

// vu4_has_invalid_eof is hasInvalidEOF of the Program: the template has an `eof-*` parse error.
fn (c &Checker) vu4_has_invalid_eof() bool {
	return c.vue_has_template() && c.vue.doc.errors.any(it.code.starts_with('eof-'))
}

// vu4_split_lines_last is the last piece of `text.split(/\r\n|[\r\n  ]/)`.
fn vu4_split_lines_last(text string) string {
	mut last := 0
	mut k := 0
	for k < text.len {
		if text[k] == `\r` || text[k] == `\n` {
			k++
			last = k
			continue
		}
		if k + 2 < text.len && text[k] == 0xe2 && text[k + 1] == 0x80
			&& (text[k + 2] == 0xa8 || text[k + 2] == 0xa9) {
			k += 3
			last = k
			continue
		}
		k++
	}
	return text[last..]
}

fn (mut c Checker) lint_vue_padding_line_between_blocks(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() || c.vu4_has_invalid_eof() {
		return []
	}
	sw := time.new_stopwatch()
	always := vplbb_options(c.rule_options(vue_padding_line_between_blocks))!
	mut findings := []Finding{}
	doc := c.vue.doc
	elements := doc.nodes[0].children.filter(doc.nodes[it].typ == .v_element)
	// The tokens but white space, and the comments, by start.
	mut tokens := doc.tokens.filter(it.typ != 'HTMLWhitespace')
	tokens << doc.comments
	tokens.sort(a.start < b.start)
	for k := 1; k < elements.len; k++ {
		stats.checked++
		prev := doc.nodes[elements[k - 1]]
		next := doc.nodes[elements[k]]
		between := tokens.filter(prev.end <= it.start && it.start < next.start)
		if always {
			c.vplbb_always(elements[k], prev, next, between, mut findings)!
		} else {
			c.vplbb_never(elements[k], prev, next, between, mut findings)!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) vplbb_never(next_i int, prev vue.VNode, next vue.VNode, between []vue.Token, mut findings []Finding) ! {
	if c.vu4_line(prev.end) == c.vu4_line(next.start) {
		return
	}
	mut pads := [][]int{}
	mut prev_end := prev.end
	mut starts := between.map(it.start)
	mut ends := between.map(it.end)
	starts << next.start
	ends << next.end
	for k, start in starts {
		if c.vu4_line(start) - c.vu4_line(prev_end) > 1 {
			pads << [prev_end, start]
		}
		prev_end = ends[k]
	}
	if pads.len == 0 {
		return
	}
	mut fixes := []Fix{}
	for pad in pads {
		fixes << fix_replace_range(pad[0], pad[1], '\n' +
			vu4_split_lines_last(c.vue_text(pad[0], pad[1])))
	}
	findings << c.with_fixes(c.vue_report_vnode(next_i, 'never', map[string]string{}),
		fixes)!
}

fn (c &Checker) vplbb_always(next_i int, prev vue.VNode, next vue.VNode, between []vue.Token, mut findings []Finding) ! {
	mut prev_end := prev.end
	mut linebreak := -1
	mut starts := between.map(it.start)
	mut ends := between.map(it.end)
	starts << next.start
	ends << next.end
	for k, start in starts {
		breaks := c.vu4_line(start) - c.vu4_line(prev_end)
		if breaks > 1 {
			return
		}
		if linebreak < 0 && breaks > 0 {
			linebreak = prev_end
		}
		prev_end = ends[k]
	}
	fix := if linebreak >= 0 {
		fix_insert_at(linebreak, '\n')
	} else {
		fix_insert_at(prev.end, '\n\n')
	}
	findings << c.with_fixes(c.vue_report_vnode(next_i, 'always', map[string]string{}),
		[fix])!
}
