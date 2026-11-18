module rules

import json2
import time

// Ports of the `vue/singleline-html-element-content-newline` and
// `vue/multiline-html-element-content-newline` rules of eslint-plugin-vue 10.12.1: the line breaks
// after the start tag and before the end tag of an element with content, on one line (none found,
// one expected; options `ignores`, `externalIgnores`, `ignoreWhenNoAttributes`, `ignoreWhenEmpty`)
// or on several (exactly one expected, or at least one with `allowEmptyLines`; options `ignores`,
// `ignoreWhenEmpty`), fixed to one line break. The elements of `ignores` (by default pre, textarea,
// router-link, nuxt-link and the inline elements) are skipped with everything inside them.

const vhecn_single_messages = {
	'unexpectedAfterClosingBracket':  'Expected 1 line break after opening tag (`<{{name}}>`), but no line breaks found.'
	'unexpectedBeforeOpeningBracket': 'Expected 1 line break before closing tag (`</{{name}}>`), but no line breaks found.'
}

const vhecn_multi_messages = {
	'unexpectedAfterClosingBracket':  'Expected 1 line break after opening tag (`<{{name}}>`), but {{actual}} line breaks found.'
	'unexpectedBeforeOpeningBracket': 'Expected 1 line break before closing tag (`</{{name}}>`), but {{actual}} line breaks found.'
}

struct VhecnOptions {
	ignores                   []string
	ignore_when_no_attributes bool
	ignore_when_empty         bool
	allow_empty_lines         bool
}

fn vhecn_default_ignores() []string {
	mut out := ['pre', 'textarea', 'router-link', 'nuxt-link']
	out << vue_inline_non_void_element_names.keys()
	return out
}

fn vhecn_bool(o OptionObject, key string, default_value bool) !bool {
	if key in o.values {
		return o.bool_value(key)!
	}
	return default_value
}

fn vhecn_parse(rule string, options []json2.Any, keys []string) !VhecnOptions {
	o := option_object(rule, options, keys)!
	mut ignores := if 'ignores' in o.values {
		o.string_list('ignores')!
	} else {
		vhecn_default_ignores()
	}
	if 'externalIgnores' in keys {
		ignores << o.string_list('externalIgnores')!
	}
	return VhecnOptions{
		ignores:                   ignores
		ignore_when_no_attributes: vhecn_bool(o, 'ignoreWhenNoAttributes', true)!
		ignore_when_empty:         vhecn_bool(o, 'ignoreWhenEmpty', true)!
		allow_empty_lines:         vhecn_bool(o, 'allowEmptyLines', false)!
	}
}

fn vhecn_single_options(options []json2.Any) !VhecnOptions {
	return vhecn_parse(vue_singleline_html_element_content_newline, options, ['ignores',
		'externalIgnores', 'ignoreWhenNoAttributes', 'ignoreWhenEmpty'])
}

fn vhecn_multi_options(options []json2.Any) !VhecnOptions {
	return vhecn_parse(vue_multiline_html_element_content_newline, options, ['ignores',
		'ignoreWhenEmpty', 'allowEmptyLines'])
}

fn vhecn_phrase(line_breaks int) string {
	return if line_breaks == 0 { 'no' } else { line_breaks.str() }
}

fn (mut c Checker) lint_vue_singleline_html_element_content_newline(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	opts := vhecn_single_options(c.rule_options(vue_singleline_html_element_content_newline))!
	return c.vhecn_lint(opts, false, mut stats)
}

fn (mut c Checker) lint_vue_multiline_html_element_content_newline(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	opts := vhecn_multi_options(c.rule_options(vue_multiline_html_element_content_newline))!
	return c.vhecn_lint(opts, true, mut stats)
}

fn (mut c Checker) vhecn_lint(opts VhecnOptions, multiline bool, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut in_ignored := -1
	for step in c.vue_template_steps() {
		if step.node.kind != .vnode {
			continue
		}
		i := step.node.v
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_element {
			continue
		}
		if step.leave {
			if in_ignored == i {
				in_ignored = -1
			}
			continue
		}
		if in_ignored >= 0 {
			continue
		}
		stats.checked++
		if node.name in opts.ignores || vue_pascal_case(node.raw_name) in opts.ignores
			|| vue_kebab_case(node.raw_name) in opts.ignores {
			in_ignored = i
			continue
		}
		start_tag := &c.vue.doc.nodes[node.start_tag]
		if start_tag.self_closing || node.end_tag < 0 {
			continue
		}
		end_tag := &c.vue.doc.nodes[node.end_tag]
		element_line := c.vu4_line(node.start)
		end_tag_line := c.vu4_line(end_tag.start)
		if multiline {
			if element_line >= end_tag_line {
				continue
			}
		} else if element_line != end_tag_line
			|| (opts.ignore_when_no_attributes && start_tag.attributes.len == 0) {
			continue
		}
		content_first := c.vu4_token_after(start_tag.end, true, true) or { continue }
		content_last := c.vu4_token_before(end_tag.start, true, true) or { continue }
		if opts.ignore_when_empty && node.children.len == 0 && content_first.start >= end_tag.start {
			continue
		}
		before := c.vu4_line(content_first.start) - c.vu4_line(start_tag.end)
		after := end_tag_line - c.vu4_line(content_last.end)
		invalid_before := if !multiline {
			true
		} else if opts.allow_empty_lines {
			before == 0
		} else {
			before != 1
		}
		if invalid_before {
			mut data := {
				'name': node.raw_name
			}
			if multiline {
				data['actual'] = vhecn_phrase(before)
			}
			findings << c.with_fixes(c.vue_report(start_tag.end, content_first.start, 'unexpectedAfterClosingBracket',
				data), [fix_replace_range(start_tag.end, content_first.start, '\n')])!
		}
		if js_trim(c.vue_text(start_tag.end, end_tag.start)) == '' {
			continue
		}
		invalid_after := if !multiline {
			true
		} else if opts.allow_empty_lines {
			after == 0
		} else {
			after != 1
		}
		if invalid_after {
			mut data := {
				'name': if multiline { node.name } else { node.raw_name }
			}
			if multiline {
				data['actual'] = vhecn_phrase(after)
			}
			findings << c.with_fixes(c.vue_report(content_last.end, end_tag.start, 'unexpectedBeforeOpeningBracket',
				data), [fix_replace_range(content_last.end, end_tag.start, '\n')])!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
