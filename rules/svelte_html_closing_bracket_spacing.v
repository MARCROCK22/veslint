module rules

import json2

// Port of the `svelte/html-closing-bracket-spacing` rule of eslint-plugin-svelte 3.24.1: the white
// space before the `>` (or `/>`) of a tag, by kind of tag (startTag, endTag: "never" by default;
// selfClosingTag: "always"; or "ignore"); white space with a line break is left alone. The report
// is located by the text; the fix adds a space or removes the white space.

const shcbs_messages = {
	'expectedSpace':   "Expected space before '>', but not found."
	'unexpectedSpace': "Expected no space before '>', but found."
}

struct ShcbsOptions {
	start_tag        string = 'never'
	end_tag          string = 'never'
	self_closing_tag string = 'always'
}

fn shcbs_options(options []json2.Any) !ShcbsOptions {
	o := option_object(svelte_html_closing_bracket_spacing, options, ['startTag', 'endTag',
		'selfClosingTag'])!
	allowed := ['always', 'never', 'ignore']
	start := o.string_value('startTag', allowed)!
	end := o.string_value('endTag', allowed)!
	self_closing := o.string_value('selfClosingTag', allowed)!
	return ShcbsOptions{
		start_tag:        if start == '' { 'never' } else { start }
		end_tag:          if end == '' { 'never' } else { end }
		self_closing_tag: if self_closing == '' { 'always' } else { self_closing }
	}
}

fn (mut c Checker) lint_svelte_html_closing_bracket_spacing(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	options := shcbs_options(c.rule_options(svelte_html_closing_bracket_spacing))!
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
		option := if n.typ == .end_tag {
			options.end_tag
		} else if n.self_closing {
			options.self_closing_tag
		} else {
			options.start_tag
		}
		if option == 'ignore' {
			continue
		}
		// /(\s*)\/?>$/ on the tag's text.
		text := c.sv_text(n.start, n.end)
		if !text.ends_with('>') {
			continue
		}
		mut at := text.len - 1
		if at > 0 && text[at - 1] == `/` {
			at--
		}
		mut space_start := at
		for space_start > 0 {
			prev := text[..space_start].runes().last()
			if !is_js_space(prev) {
				break
			}
			space_start -= prev.str().len
		}
		spaces := text[space_start..at]
		if spaces.contains('\n') {
			continue
		}
		start := n.start + space_start
		if option == 'always' && spaces == '' {
			findings << Finding{
				...c.sv_report_text(start, n.end, 'expectedSpace', {})
				has_fix: true
				fix:     Fix{
					start: start
					end:   start
					text:  ' '
				}
			}
		} else if option == 'never' && spaces != '' {
			findings << Finding{
				...c.sv_report_text(start, n.end, 'unexpectedSpace', {})
				has_fix: true
				fix:     Fix{
					start: start
					end:   start + spaces.len
				}
			}
		}
	}
	return findings
}
