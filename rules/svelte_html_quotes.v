module rules

import json2

// Port of the `svelte/html-quotes` rule of eslint-plugin-svelte 3.24.1: the quotes of attribute
// values (prefer: "double" by default, or "single"); a value that is a single mustache tag, and a
// directive's expression, are unquoted unless dynamic.quoted, or unless
// dynamic.avoidInvalidUnquotedInHTML and its text could not be unquoted in HTML. A value that
// would need its quote escaped is left alone. The report is located by the text.

const shq_messages = {
	'expectedEnclosed':   'Expected to be enclosed by quotes.'
	'expectedEnclosedBy': 'Expected to be enclosed by {{kind}}.'
	'unexpectedEnclosed': 'Unexpected to be enclosed by any quotes.'
}

struct ShqOptions {
	prefer        string = 'double'
	dynamic       string = 'unquoted'
	avoid_invalid bool
}

fn shq_options(options []json2.Any) !ShqOptions {
	o := option_object(svelte_html_quotes, options, ['prefer', 'dynamic'])!
	prefer := o.string_value('prefer', ['double', 'single'])!
	mut quoted := false
	mut avoid := false
	if dynamic := o.values['dynamic'] {
		d := option_object(svelte_html_quotes, [dynamic], ['quoted', 'avoidInvalidUnquotedInHTML'])!
		quoted = d.bool_value('quoted')!
		avoid = d.bool_value('avoidInvalidUnquotedInHTML')!
	}
	p := if prefer == '' { 'double' } else { prefer }
	return ShqOptions{
		prefer:        p
		dynamic:       if quoted { p } else { 'unquoted' }
		avoid_invalid: avoid
	}
}

fn shq_quote_char(kind string) string {
	return if kind == 'double' { '"' } else { "'" }
}

fn shq_quote_name(kind string) string {
	return match kind {
		'double' { 'double quotes' }
		'single' { 'single quotes' }
		else { 'unquoted' }
	}
}

// shq_can_be_unquoted is canBeUnquotedInHTML: no /[\s"'<=>`]/.
fn shq_can_be_unquoted(text string) bool {
	for r in text.runes() {
		if is_js_space(r) || r in [`"`, `'`, `<`, `=`, `>`, `\``] {
			return false
		}
	}
	return true
}

// shq_verify is verifyQuote.
fn (c &Checker) shq_verify(prefer string, attr int, mut findings []Finding) ! {
	q := c.sv_attribute_value_quote_and_range(attr) or { return }
	if q.quote == prefer {
		return
	}
	mut message_id := ''
	mut expected := prefer
	src := c.svelte.doc.src
	if q.quote != 'unquoted' {
		if expected == 'unquoted' {
			message_id = 'unexpectedEnclosed'
		} else {
			if src[q.start + 1..q.end - 1].contains(shq_quote_char(expected)) {
				return
			}
			message_id = 'expectedEnclosedBy'
		}
	} else {
		content := src[q.start..q.end]
		double := content.contains('"')
		single := content.contains("'")
		if double && single {
			return
		}
		if double && expected == 'double' {
			expected = 'single'
			message_id = 'expectedEnclosed'
		} else if single && expected == 'single' {
			expected = 'double'
			message_id = 'expectedEnclosed'
		} else {
			message_id = 'expectedEnclosedBy'
		}
	}
	mut fixes := []Fix{}
	if expected != 'unquoted' {
		fixes << Fix{
			start: q.start
			end:   q.start
			text:  shq_quote_char(expected)
		}
	}
	if q.quote != 'unquoted' {
		fixes << Fix{
			start: q.start
			end:   q.start + 1
		}
		fixes << Fix{
			start: q.end - 1
			end:   q.end
		}
	}
	if expected != 'unquoted' {
		fixes << Fix{
			start: q.end
			end:   q.end
			text:  shq_quote_char(expected)
		}
	}
	has_fix, fix := c.merge_fixes(fixes)!
	findings << Finding{
		...c.sv_report_text(q.start, q.end, message_id, {
			'kind': shq_quote_name(expected)
		})
		has_fix: has_fix
		fix:     fix
	}
}

fn (mut c Checker) lint_svelte_html_quotes(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	options := shq_options(c.rule_options(svelte_html_quotes))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes() {
		n := doc.nodes[i]
		match n.typ {
			.attribute, .style_directive {
				if n.values.len == 1 && doc.nodes[n.values[0]].typ == .mustache_tag {
					value := doc.nodes[n.values[0]]
					text := c.sv_text(value.start, value.end)
					c.shq_verify(if options.avoid_invalid && !shq_can_be_unquoted(text) {
						options.prefer
					} else {
						options.dynamic
					}, i, mut findings)!
				} else if n.values.len >= 1 {
					c.shq_verify(options.prefer, i, mut findings)!
				}
			}
			.directive, .special_directive {
				if n.expression.idx < 0 {
					continue
				}
				ex_start, ex_end := c.sv_ref_range(n.expression)
				key_start, key_end := c.sv_ref_range(n.key)
				if key_start <= ex_start && ex_end <= key_end {
					continue
				}
				open, close := c.sv_mustache_tokens(i) or { continue }
				text := c.sv_text(open.start, close.end)
				c.shq_verify(if options.avoid_invalid && !shq_can_be_unquoted(text) {
					options.prefer
				} else {
					options.dynamic
				}, i, mut findings)!
			}
			else {}
		}
	}
	return findings
}
