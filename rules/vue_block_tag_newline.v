module rules

import json2
import time

// Port of the `vue/block-tag-newline` rule of eslint-plugin-vue 10.12.1 (options `singleline`
// ("consistent" by default), `multiline` ("always"), `maxEmptyLines` (0) and `blocks` with the
// same options by block name): the line breaks after the start tag and before the end tag of each
// top-level element with content, fixed by adding, removing or limiting them. Nothing when the
// template has an `eof-*` parse error.

const vbtn_messages = {
	'unexpectedOpeningLinebreak': "There should be no line break after '<{{tag}}>'."
	'expectedOpeningLinebreak':   "Expected {{expected}} after '<{{tag}}>', but {{actual}} found."
	'expectedClosingLinebreak':   "Expected {{expected}}  before '</{{tag}}>', but {{actual}} found."
	'missingOpeningLinebreak':    "A line break is required after '<{{tag}}>'."
	'missingClosingLinebreak':    "A line break is required before '</{{tag}}>'."
}

struct VbtnContents {
	singleline    string
	multiline     string
	max_empty     int
	has_max_empty bool
}

struct VbtnOptions {
	base   VbtnContents
	blocks map[string]VbtnContents
}

fn vbtn_contents(rule string, value json2.Any, keys []string) !VbtnContents {
	o := option_object(rule, [value], keys)!
	modes := ['always', 'never', 'consistent', 'ignore']
	mut max_empty := 0
	mut has_max_empty := false
	if v := o.values['maxEmptyLines'] {
		if v !is f64 && v !is int && v !is i64 {
			return error('option `maxEmptyLines` of `${rule}` must be a number')
		}
		max_empty = int(v.f64())
		has_max_empty = true
	}
	return VbtnContents{
		singleline:    if 'singleline' in o.values {
			o.string_value('singleline', modes)!
		} else {
			''
		}
		multiline:     if 'multiline' in o.values {
			o.string_value('multiline', modes)!
		} else {
			''
		}
		max_empty:     max_empty
		has_max_empty: has_max_empty
	}
}

fn vbtn_options(options []json2.Any) !VbtnOptions {
	if options.len == 0 {
		return VbtnOptions{
			base: VbtnContents{'consistent', 'always', 0, true}
		}
	}
	o := option_object(vue_block_tag_newline, options, ['singleline', 'multiline', 'maxEmptyLines',
		'blocks'])!
	mut first := o.values.clone()
	first.delete('blocks')
	given := vbtn_contents(vue_block_tag_newline, json2.Any(first), ['singleline', 'multiline',
		'maxEmptyLines'])!
	base := VbtnContents{
		singleline:    if given.singleline != '' { given.singleline } else { 'consistent' }
		multiline:     if given.multiline != '' { given.multiline } else { 'always' }
		max_empty:     given.max_empty
		has_max_empty: true
	}
	mut blocks := map[string]VbtnContents{}
	if value := o.values['blocks'] {
		if value !is map[string]json2.Any {
			return error('option `blocks` of `${vue_block_tag_newline}` must be an object')
		}
		for name, block in value.as_map() {
			b := vbtn_contents(vue_block_tag_newline, block, ['singleline', 'multiline', 'maxEmptyLines'])!
			blocks[name] = VbtnContents{
				singleline:    if b.singleline != '' { b.singleline } else { base.singleline }
				multiline:     if b.multiline != '' { b.multiline } else { base.multiline }
				max_empty:     if b.has_max_empty { b.max_empty } else { base.max_empty }
				has_max_empty: true
			}
		}
	}
	return VbtnOptions{
		base:   base
		blocks: blocks
	}
}

// vbtn_linebreaks is getLinebreakCount: the line breaks of a text (CRLF counts once).
fn vbtn_linebreaks(text string) int {
	return un_source_lines(text).len - 1
}

fn vbtn_phrase(n int) string {
	return if n == 1 { '1 line break' } else { '${n} line breaks' }
}

fn (mut c Checker) lint_vue_block_tag_newline(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() || c.vue_has_invalid_eof() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vbtn_options(c.rule_options(vue_block_tag_newline))!
	mut findings := []Finding{}
	doc := c.vue.doc
	for element in doc.nodes[0].children {
		el := doc.nodes[element]
		if el.typ != .v_element {
			continue
		}
		stats.checked++
		o := opts.blocks[el.name] or { opts.base }
		c.vbtn_verify(element, o, mut findings)!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) vbtn_verify(element int, o VbtnContents, mut findings []Finding) ! {
	el := c.vue.doc.nodes[element]
	if el.end_tag < 0 {
		return
	}
	start_tag := c.vue.doc.nodes[el.start_tag]
	end_tag := c.vue.doc.nodes[el.end_tag]
	if start_tag.self_closing {
		return
	}
	text := c.vue_text(start_tag.end, end_tag.start)
	trimmed := js_trim(text)
	if trimmed == '' {
		return
	}
	multiline := trimmed.contains('\n') || trimmed.contains('\r') || trimmed.contains(' ')
		|| trimmed.contains(' ')
	option := if o.multiline != o.singleline && multiline { o.multiline } else { o.singleline }
	if option == 'ignore' {
		return
	}
	before_len := vu4_trim_start_offset(text, 0)
	after_start := vu4_trim_end_offset(text, text.len)
	before_text := text[..before_len]
	after_text := text[after_start..]
	before_count := vbtn_linebreaks(before_text)
	after_count := vbtn_linebreaks(after_text)
	mut mode := option
	if option == 'consistent' {
		if (before_count > 0) == (after_count > 0) {
			return
		}
		mode = 'always'
	}
	tag := el.name
	max_empty := o.max_empty
	// After the start tag.
	before_end := start_tag.end + before_text.len
	if mode == 'always' {
		if before_count == 0 {
			findings << c.with_fixes(c.vue_report(start_tag.end, start_tag.end, 'missingOpeningLinebreak',
				{
					'tag': tag
				}), [fix_insert_at(start_tag.end, '\n')])!
		} else if max_empty < before_count - 1 {
			findings << c.with_fixes(c.vbtn_report(start_tag.end, before_end, false, 'expectedOpeningLinebreak',
				{
					'tag':      tag
					'expected': vbtn_phrase(max_empty + 1)
					'actual':   vbtn_phrase(before_count)
				}), [fix_replace_range(start_tag.end, before_end, '\n'.repeat(max_empty + 1))])!
		}
	} else if before_count > 0 {
		findings << c.with_fixes(c.vbtn_report(start_tag.end, before_end, false, 'unexpectedOpeningLinebreak',
			{
				'tag': tag
			}), [fix_remove_range(start_tag.end, before_end)])!
	}
	// Before the end tag.
	after_begin := end_tag.start - after_text.len
	if mode == 'always' {
		if after_count == 0 {
			findings << c.with_fixes(c.vue_report(end_tag.start, end_tag.start, 'missingClosingLinebreak',
				{
					'tag': tag
				}), [fix_insert_at(end_tag.start, '\n')])!
		} else if max_empty < after_count - 1 {
			findings << c.with_fixes(c.vbtn_report(after_begin, end_tag.start, true, 'expectedClosingLinebreak',
				{
					'tag':      tag
					'expected': vbtn_phrase(max_empty + 1)
					'actual':   vbtn_phrase(after_count)
				}), [fix_replace_range(after_begin, end_tag.start, '\n'.repeat(max_empty + 1))])!
		}
	} else if after_count > 0 {
		// The rule reports this one with the message of the start tag's.
		findings << c.with_fixes(c.vbtn_report(after_begin, end_tag.start, true, 'unexpectedOpeningLinebreak',
			{
				'tag': tag
			}), [fix_remove_range(after_begin, end_tag.start)])!
	}
}

// vbtn_report is a report whose start (`text_start`) or end is sourceCode.getLocFromIndex of an
// offset: ESLint's lines there, vue-eslint-parser's on the other side (a tag's loc).
fn (c &Checker) vbtn_report(start int, end int, text_start bool, message_id string, data map[string]string) Finding {
	return Finding{
		...c.vue_report(start, end, message_id, data)
		text_loc_start: text_start
		text_loc_end:   !text_start
	}
}
