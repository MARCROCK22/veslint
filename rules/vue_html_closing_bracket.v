module rules

import json2
import time
import vue

// Ports of the `vue/html-closing-bracket-spacing` and `vue/html-closing-bracket-newline` rules of
// eslint-plugin-vue 10.12.1, which check the closing bracket of every start and end tag of the
// document (defineDocumentVisitor) with the template's token store.
//
// html-closing-bracket-spacing (options `startTag` and `endTag`, "never" by default, and
// `selfClosingTag`, "always" by default): a space before the `>` or `/>` of a tag where there
// should be none, or none where there should be one, when the bracket is on the line of the token
// before it; fixed.
//
// html-closing-bracket-newline (options `singleline`, "never" by default, `multiline`, "always" by
// default, and `selfClosingTag` with its own `singleline` and `multiline`): a number of line
// breaks before the closing bracket of a tag other than the expected one (one for "always", none
// for "never", by whether the tag starts on the line where the token before the bracket ends);
// fixed.
//
// Both run on any .vue file, with or without a <template>: the token store vue-eslint-parser gives
// holds the tokens of the whole document.

const vhcbs_messages = {
	'missing':    "Expected a space before '{{bracket}}', but not found."
	'unexpected': "Expected no space before '{{bracket}}', but found."
}

const vhcbn_messages = {
	'expectedBeforeClosingBracket': 'Expected {{expected}} before closing bracket, but {{actual}} found.'
}

struct VhcbsOptions {
	start_tag        string = 'never'
	end_tag          string = 'never'
	self_closing_tag string = 'always'
}

fn vhcbs_options(options []json2.Any) !VhcbsOptions {
	o := option_object(vue_html_closing_bracket_spacing, options, ['startTag', 'endTag',
		'selfClosingTag'])!
	start_tag := o.string_value('startTag', ['always', 'never'])!
	end_tag := o.string_value('endTag', ['always', 'never'])!
	self_closing_tag := o.string_value('selfClosingTag', ['always', 'never'])!
	return VhcbsOptions{
		start_tag:        if start_tag == '' { 'never' } else { start_tag }
		end_tag:          if end_tag == '' { 'never' } else { end_tag }
		self_closing_tag: if self_closing_tag == '' { 'always' } else { self_closing_tag }
	}
}

// vue_document_tags are the VStartTag and VEndTag nodes of the document, in traversal order.
fn (c &Checker) vue_document_tags() []int {
	mut out := []int{}
	for step in c.vue_document_steps() {
		if !step.leave && step.node.kind == .vnode
			&& c.vue.doc.nodes[step.node.v].typ in [.v_start_tag, .v_end_tag] {
			out << step.node.v
		}
	}
	return out
}

fn (mut c Checker) lint_vue_html_closing_bracket_spacing(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vhcbs_options(c.rule_options(vue_html_closing_bracket_spacing))!
	mut findings := []Finding{}
	for i in c.vue_document_tags() {
		stats.checked++
		start, end := c.vue_vnode_range(i)
		tokens := c.vue_tokens_in(start, end)
		if tokens.len == 0 {
			continue
		}
		open_type := tokens[0].typ
		last := tokens.last()
		typ := if open_type == 'HTMLEndTagOpen' && last.typ == 'HTMLTagClose' {
			opts.end_tag
		} else if open_type == 'HTMLTagOpen' && last.typ == 'HTMLTagClose' {
			opts.start_tag
		} else if open_type == 'HTMLTagOpen' && last.typ == 'HTMLSelfClosingTagClose' {
			opts.self_closing_tag
		} else {
			''
		}
		if typ == '' || tokens.len < 2 {
			continue
		}
		prev := tokens[tokens.len - 2]
		if c.vue.doc.loc(prev.end).line != c.vue.doc.loc(last.start).line {
			continue
		}
		has_space := prev.end != last.start
		bracket := c.vue_text(last.start, last.end)
		if typ == 'always' && !has_space {
			findings << c.with_fixes(c.vue_report(last.start, last.end, 'missing', {
				'bracket': bracket
			}), [fix_insert_at(last.start, ' ')])!
		} else if typ == 'never' && has_space {
			findings << c.with_fixes(c.vue_report(prev.end, last.end, 'unexpected', {
				'bracket': bracket
			}), [fix_remove_range(prev.end, last.start)])!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

struct VhcbnOptions {
	singleline              string = 'never'
	multiline               string = 'always'
	self_closing_singleline string
	self_closing_multiline  string
}

fn vhcbn_options(options []json2.Any) !VhcbnOptions {
	o := option_object(vue_html_closing_bracket_newline, options, ['singleline', 'multiline',
		'selfClosingTag'])!
	singleline := o.string_value('singleline', ['always', 'never'])!
	multiline := o.string_value('multiline', ['always', 'never'])!
	mut self_singleline := ''
	mut self_multiline := ''
	if self_closing := o.values['selfClosingTag'] {
		s := option_object(vue_html_closing_bracket_newline, [self_closing], [
			'singleline',
			'multiline',
		])!
		self_singleline = s.string_value('singleline', ['always', 'never'])!
		self_multiline = s.string_value('multiline', ['always', 'never'])!
	}
	return VhcbnOptions{
		singleline:              if singleline == '' { 'never' } else { singleline }
		multiline:               if multiline == '' { 'always' } else { multiline }
		self_closing_singleline: self_singleline
		self_closing_multiline:  self_multiline
	}
}

// vhcbn_phrase is getPhrase.
fn vhcbn_phrase(line_breaks int) string {
	return match line_breaks {
		0 { 'no line breaks' }
		1 { '1 line break' }
		else { '${line_breaks} line breaks' }
	}
}

fn (mut c Checker) lint_vue_html_closing_bracket_newline(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vhcbn_options(c.rule_options(vue_html_closing_bracket_newline))!
	mut findings := []Finding{}
	for i in c.vue_document_tags() {
		stats.checked++
		node := &c.vue.doc.nodes[i]
		start, end := c.vue_vnode_range(i)
		closing := c.vue_last_token_in(start, end) or { continue }
		if closing.typ != 'HTMLSelfClosingTagClose' && closing.typ != 'HTMLTagClose' {
			continue
		}
		prev := c.vue_token_before(closing.start, false, false) or { continue }
		prev_end_line := c.vue.doc.loc(prev.end).line
		singleline := c.vue.doc.loc(start).line == prev_end_line
		expected := c.vhcbn_expected(node, opts, singleline)
		actual := c.vue.doc.loc(closing.start).line - prev_end_line
		if actual == expected {
			continue
		}
		findings << c.with_fixes(c.vue_report(prev.end, closing.start, 'expectedBeforeClosingBracket',
			{
				'expected': vhcbn_phrase(expected)
				'actual':   vhcbn_phrase(actual)
			}), [fix_replace_range(prev.end, closing.start, '\n'.repeat(expected))])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vhcbn_expected is getExpectedLineBreaks.
fn (c &Checker) vhcbn_expected(node &vue.VNode, opts VhcbnOptions, singleline bool) int {
	if node.typ == .v_start_tag && node.self_closing {
		self_option := if singleline {
			opts.self_closing_singleline
		} else {
			opts.self_closing_multiline
		}
		if self_option != '' {
			return if self_option == 'always' { 1 } else { 0 }
		}
	}
	option := if singleline { opts.singleline } else { opts.multiline }
	return if option == 'always' { 1 } else { 0 }
}
