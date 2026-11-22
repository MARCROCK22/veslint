module rules

import json2
import time

// Port of the `vue/no-child-content` rule of eslint-plugin-vue 10.12.1 (option
// `additionalDirectives`: directive names besides `html` and `text`): the child content (children
// and HTML comments, unless all blank text) of an element with an end tag and one of those
// directives, with a suggestion that removes it.

const vncc_messages = {
	'disallowedChildContent': 'Child content is disallowed because it will be overwritten by the v-{{ directiveName }} directive.'
	'removeChildContent':     'Remove child content.'
}

fn vncc_options(options []json2.Any) ![]string {
	mut directives := ['html', 'text']
	if options.len > 0 {
		o := option_object(vue_no_child_content, options, ['additionalDirectives'])!
		if 'additionalDirectives' !in o.values {
			return error('`${vue_no_child_content}` needs `additionalDirectives`')
		}
		directives << o.string_list('additionalDirectives')!
	}
	return directives
}

fn (mut c Checker) lint_vue_no_child_content(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	directives := vncc_options(c.rule_options(vue_no_child_content))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute || !node.directive {
			continue
		}
		name := c.vue_directive_name(i)
		element := c.vue_attribute_element(i)
		el := &c.vue.doc.nodes[element]
		if el.end_tag < 0 || name !in directives {
			continue
		}
		stats.checked++
		// The children, then the HTML comments between the tags (getTokensBetween).
		mut ranges := [][]int{}
		mut not_empty := false
		for child in el.children {
			ch := &c.vue.doc.nodes[child]
			start, end := c.vue_vnode_range(child)
			ranges << [start, end]
			if ch.typ != .v_text || js_trim(ch.text) != '' {
				not_empty = true
			}
		}
		after := c.vue.doc.nodes[el.start_tag].end
		before := c.vue.doc.nodes[el.end_tag].start
		for comment in c.vue.doc.comments {
			if comment.typ == 'HTMLComment' && comment.start >= after && comment.end <= before {
				ranges << [comment.start, comment.end]
				not_empty = true
			}
		}
		if !not_empty {
			continue
		}
		mut start := ranges[0][0]
		mut end := ranges[0][1]
		for r in ranges {
			if r[0] < start {
				start = r[0]
			}
			if r[1] > end {
				end = r[1]
			}
		}
		mut report := c.vue_report(start, end, 'disallowedChildContent', {
			'directiveName': name
		})
		// Overlapping removals (a comment inside a child) make ESLint throw: no suggestion then.
		ok, suggestion := c.suggestion('removeChildContent', {}, ranges.map(fix_remove_range(it[0],
			it[1]))) or { false, Suggestion{} }
		if ok {
			report = Finding{
				...report
				suggestions: [suggestion]
			}
		}
		findings << report
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
