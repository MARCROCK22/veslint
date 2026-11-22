module rules

import json2
import time

// Port of the `vue/first-attribute-linebreak` rule of eslint-plugin-vue 10.12.1 (options
// `multiline`, "below" by default, and `singleline`, "ignore" by default: "below", "beside" or
// "ignore", for start tags whose attributes span several lines or one): the first attribute of a
// start tag on the tag's line when it should be below, or below it when it should be beside, fixed
// by a line break or a space after the token before it.

const vfal_messages = {
	'expected':   'Expected a linebreak before this attribute.'
	'unexpected': 'Expected no linebreak before this attribute.'
}

struct VfalOptions {
	singleline string = 'ignore'
	multiline  string = 'below'
}

fn vfal_options(options []json2.Any) !VfalOptions {
	o := option_object(vue_first_attribute_linebreak, options, ['multiline', 'singleline'])!
	singleline := o.string_value('singleline', ['below', 'beside', 'ignore'])!
	multiline := o.string_value('multiline', ['below', 'beside', 'ignore'])!
	return VfalOptions{
		singleline: if singleline == '' { 'ignore' } else { singleline }
		multiline:  if multiline == '' { 'below' } else { multiline }
	}
}

fn (mut c Checker) lint_vue_first_attribute_linebreak(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vfal_options(c.rule_options(vue_first_attribute_linebreak))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_start_tag || node.attributes.len == 0 {
			continue
		}
		stats.checked++
		first := node.attributes[0]
		first_start, _ := c.vue_vnode_range(first)
		_, last_end := c.vue_vnode_range(node.attributes.last())
		first_line := c.vue.doc.loc(first_start).line
		location := if first_line == c.vue.doc.loc(last_end).line {
			opts.singleline
		} else {
			opts.multiline
		}
		if location == 'ignore' {
			continue
		}
		tag_start, _ := c.vue_vnode_range(i)
		tag_line := c.vue.doc.loc(tag_start).line
		if location == 'beside' {
			if tag_line == first_line {
				continue
			}
		} else if tag_line < first_line {
			continue
		}
		report := c.vue_report_vnode(first, if location == 'beside' {
			'unexpected'
		} else {
			'expected'
		}, {})
		prev := c.vue_token_before(c.vue.doc.nodes[first].start, true, false) or {
			findings << report
			continue
		}
		findings << c.with_fixes(report, [
			fix_replace_range(prev.end, c.vue.doc.nodes[first].start, if location == 'beside' {
				' '
			} else {
				'\n'
			}),
		])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
