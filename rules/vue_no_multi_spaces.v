module rules

import json2
import time
import vue

// Port of the `vue/no-multi-spaces` rule of eslint-plugin-vue 10.12.1 (options `ignoreProperties`
// and `ignoreEOLComments`): more than one space between two tokens on a line of the template, or
// of the start and end tags of the other top-level elements, with the fix that leaves one.

const vue_no_multi_spaces_messages = {
	'multipleSpaces':  "Multiple spaces found before '{{displayValue}}'."
	'useLatestParser': 'Use the latest vue-eslint-parser. See also https://eslint.vuejs.org/user-guide/#what-is-the-use-the-latest-vue-eslint-parser-error.'
}

struct VnmsOptions {
	ignore_properties   bool
	ignore_eol_comments bool
}

fn vue_no_multi_spaces_options(options []json2.Any) !VnmsOptions {
	o := option_object(vue_no_multi_spaces, options, ['ignoreProperties', 'ignoreEOLComments'])!
	is_true := fn [o] (key string) bool {
		value := o.values[key] or { return false }
		return value is bool && value
	}
	return VnmsOptions{
		ignore_properties:   is_true('ignoreProperties')
		ignore_eol_comments: is_true('ignoreEOLComments')
	}
}

fn (mut c Checker) lint_vue_no_multi_spaces(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	o := vue_no_multi_spaces_options(c.rule_options(vue_no_multi_spaces))!
	mut findings := []Finding{}
	doc := c.vue.doc
	mut lists := [][]vue.Token{}
	for element in doc.nodes[0].children {
		node := &doc.nodes[element]
		if node.typ != .v_element {
			continue
		}
		if element == doc.template_body {
			lists << c.vue_tokens_with_comments_in(node.start, node.end)
		} else {
			start_tag := &doc.nodes[node.start_tag]
			lists << c.vue_tokens_in(start_tag.start, start_tag.end)
			if node.end_tag >= 0 {
				end_tag := &doc.nodes[node.end_tag]
				lists << c.vue_tokens_in(end_tag.start, end_tag.end)
			}
		}
	}
	for tokens in lists {
		stats.checked++
		for k in 1 .. tokens.len {
			prev := tokens[k - 1]
			token := tokens[k]
			mut ignore := o.ignore_properties
				&& (vnms_is_colon(c, token) || vnms_is_colon(c, prev))
			if !ignore && o.ignore_eol_comments && token.typ in ['Line', 'Block'] {
				if next := c.vue_token_after(token.end, true, false) {
					if doc.loc(next.start).line > doc.loc(token.end).line {
						ignore = true
					}
				} else {
					ignore = true
				}
			}
			if ignore || token.start - prev.end <= 1
				|| utf16_units(c.src[prev.end..token.start]).len <= 1
				|| doc.loc(token.start).line != doc.loc(prev.start).line {
				continue
			}
			findings << c.with_fixes(c.vue_report(prev.end, token.start, 'multipleSpaces',
				{
					'displayValue': c.src[token.start..token.end]
				}), [fix_replace_range(prev.end, token.start, ' ')])!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn vnms_is_colon(c &Checker, token vue.Token) bool {
	return token.typ == 'Punctuator' && c.src[token.start..token.end] == ':'
}
