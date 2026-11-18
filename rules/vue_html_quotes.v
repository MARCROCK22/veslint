module rules

import json2
import time

// Port of the `vue/html-quotes` rule of eslint-plugin-vue 10.12.1 (option "double", the default, or
// "single", and `avoidEscape`): an attribute value not enclosed by the expected quotes (with
// `avoidEscape`, a quoted value that holds the expected quote is left), fixed by enclosing its
// content in them, the quotes of that kind inside written as `&quot;` or `&apos;`; nothing when
// the document has an `eof-*` parse error (hasInvalidEOF).

const vhq_messages = {
	'expected': 'Expected to be enclosed by {{kind}}.'
}

struct VhqOptions {
	double       bool = true
	avoid_escape bool
}

fn vhq_options(options []json2.Any) !VhqOptions {
	mut double := true
	if options.len > 0 {
		value := options[0]
		if value !is string || value as string !in ['double', 'single'] {
			return error('the first option of `${vue_html_quotes}` must be "double" or "single"')
		}
		double = value as string != 'single'
	}
	mut avoid_escape := false
	if options.len > 1 {
		o := option_object(vue_html_quotes, options[1..], ['avoidEscape'])!
		avoid_escape = o.bool_value('avoidEscape')!
	}
	return VhqOptions{
		double:       double
		avoid_escape: avoid_escape
	}
}

fn (mut c Checker) lint_vue_html_quotes(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	if c.vue.doc.errors.any(it.code.starts_with('eof-')) {
		return []
	}
	sw := time.new_stopwatch()
	opts := vhq_options(c.rule_options(vue_html_quotes))!
	quote_char := if opts.double { '"' } else { "'" }
	quote_name := if opts.double { 'double quotes' } else { 'single quotes' }
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute || node.value < 0 || c.vue_is_vbind_same_name_shorthand(i) {
			continue
		}
		stats.checked++
		value := &c.vue.doc.nodes[node.value]
		text := c.vue_text(value.start, value.end)
		first_char := if text.len > 0 { text[..1] } else { '' }
		if first_char == quote_char {
			continue
		}
		is_quoted := first_char == "'" || first_char == '"'
		// text.slice(1, -1) of a quoted text: its quotes are one byte each.
		quoted_content := if text.len >= 2 { text[1..text.len - 1] } else { '' }
		if opts.avoid_escape && is_quoted && quoted_content.contains(quote_char) {
			continue
		}
		content := if is_quoted { quoted_content } else { text }
		mut to_double := opts.double
		if opts.avoid_escape && !is_quoted && content.contains(quote_char) {
			to_double = if opts.double { content.contains("'") } else { !content.contains('"') }
		}
		replacement := if to_double {
			'"' + content.replace('"', '&quot;') + '"'
		} else {
			"'" + content.replace("'", '&apos;') + "'"
		}
		findings << c.with_fixes(c.vue_report_vnode(node.value, 'expected', {
			'kind': quote_name
		}), [fix_replace_range(value.start, value.end, replacement)])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
