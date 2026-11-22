module rules

import json2
import jsregexp
import time

// Port of the `vue/no-v-html` rule of eslint-plugin-vue 10.12.1 (option `ignorePattern`: a
// `v-html` whose value is an identifier matching it, or an expression whose text matches it, is
// not reported).

const vnvh_messages = {
	'unexpected': "'v-html' directive can lead to XSS attack."
}

struct VnvhOptions {
	has_ignore bool
	ignore     jsregexp.JsRegex
}

fn vnvh_options(options []json2.Any) !VnvhOptions {
	o := option_object(vue_no_v_html, options, ['ignorePattern'])!
	value := o.values['ignorePattern'] or { return VnvhOptions{} }
	if value !is string {
		return error('option `ignorePattern` of `${vue_no_v_html}` must be a string')
	}
	pattern := value as string
	// `options?.ignorePattern ? new RegExp(…) : undefined`
	if pattern == '' {
		return VnvhOptions{}
	}
	return VnvhOptions{
		has_ignore: true
		ignore:     jsregexp.js_regex_new(pattern, 'u')!
	}
}

fn (mut c Checker) lint_vue_no_v_html(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vnvh_options(c.rule_options(vue_no_v_html))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, 'html') {
			continue
		}
		stats.checked++
		if opts.has_ignore {
			value := c.vue.doc.nodes[i].value
			e := c.vue_container_expression(value)
			if !e.is_null() {
				text := if c.vue_expr_type(e) == 'Identifier' {
					c.vue.doc.snippets[e.snippet].es.string_of(e.node, .name) or { '' }
				} else {
					start, end := c.vue_expr_range(e)
					c.vue_text(start, end)
				}
				if opts.ignore.test(utf16_units(text))! {
					continue
				}
			}
		}
		findings << c.vue_report_vnode(i, 'unexpected', {})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
