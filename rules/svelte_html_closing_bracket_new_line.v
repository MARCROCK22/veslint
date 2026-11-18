module rules

import json2

// Port of the `svelte/html-closing-bracket-new-line` rule of eslint-plugin-svelte 3.24.1: the line
// breaks before the `>` (or the `/` of `/>`) of a tag: none for a tag whose last token before the
// bracket is on its first line (singleline, "never" by default), one otherwise (multiline,
// "always"), with selfClosingTag's own singleline/multiline for `/>`. An end tag is only checked
// for no line break. The fix writes the expected line breaks.

const shcbnl_messages = {
	'expectedBeforeClosingBracket': 'Expected {{expected}} before closing bracket, but {{actual}} found.'
}

struct ShcbnlOptions {
	singleline      string = 'never'
	multiline       string = 'always'
	self_singleline string
	self_multiline  string
}

fn shcbnl_options(options []json2.Any) !ShcbnlOptions {
	o := option_object(svelte_html_closing_bracket_new_line, options, ['singleline', 'multiline',
		'selfClosingTag'])!
	allowed := ['always', 'never']
	singleline := o.string_value('singleline', allowed)!
	multiline := o.string_value('multiline', allowed)!
	mut self_singleline := ''
	mut self_multiline := ''
	if self_closing := o.values['selfClosingTag'] {
		so := option_object(svelte_html_closing_bracket_new_line, [self_closing], [
			'singleline',
			'multiline',
		])!
		self_singleline = so.string_value('singleline', allowed)!
		self_multiline = so.string_value('multiline', allowed)!
	}
	return ShcbnlOptions{
		singleline:      if singleline == '' { 'never' } else { singleline }
		multiline:       if multiline == '' { 'always' } else { multiline }
		self_singleline: self_singleline
		self_multiline:  self_multiline
	}
}

// shcbnl_phrase is getPhrase.
fn shcbnl_phrase(line_breaks int) string {
	return match line_breaks {
		0 { 'no line breaks' }
		1 { '1 line break' }
		else { '${line_breaks} line breaks' }
	}
}

fn (mut c Checker) lint_svelte_html_closing_bracket_new_line(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	options := shcbnl_options(c.rule_options(svelte_html_closing_bracket_new_line))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes() {
		n := doc.nodes[i]
		if n.typ !in [.start_tag, .end_tag] {
			continue
		}
		self_closing := n.typ == .start_tag && n.self_closing
		closing := if self_closing {
			// The token before the last one (`/` of `/>`).
			tokens := c.sv_tokens_in(n.start, n.end, false)
			if tokens.len < 2 || tokens[tokens.len - 2].value != '/' {
				continue
			}
			tokens[tokens.len - 2]
		} else {
			last := c.sv_last_token(n.start, n.end) or { continue }
			if last.value != '>' {
				continue
			}
			last
		}
		prev := c.sv_token_before(closing.start, false) or { continue }
		multiline := c.sv_line(n.start) != c.sv_line(sv_token_loc_end(prev))
		self_option := if multiline { options.self_multiline } else { options.self_singleline }
		option := if self_closing && self_option != '' {
			self_option
		} else if multiline {
			options.multiline
		} else {
			options.singleline
		}
		expected := if option == 'always' { 1 } else { 0 }
		actual := c.sv_line(sv_token_loc_start(closing)) - c.sv_line(sv_token_loc_end(prev))
		if actual == expected || (n.typ == .end_tag && expected != 0) {
			continue
		}
		findings << Finding{
			...c.sv_report(sv_token_loc_end(prev), sv_token_loc_start(closing), 'expectedBeforeClosingBracket',
				{
					'expected': shcbnl_phrase(expected)
					'actual':   shcbnl_phrase(actual)
				})
			has_fix: true
			fix:     Fix{
				start: prev.end
				end:   closing.start
				text:  '\n'.repeat(expected)
			}
		}
	}
	return findings
}
