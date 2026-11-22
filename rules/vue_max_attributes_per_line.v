module rules

import json2
import time

// Port of the `vue/max-attributes-per-line` rule of eslint-plugin-vue 10.12.1 (options `singleline`
// and `multiline`, a number or `{max}`): the attributes of a start tag past the maximum of its
// kind, a single-line tag counted as a whole and a multiline one line by line (attributes on the
// line another ends on). The first attribute reported in a group is fixed by a line break before
// it, in place of the whitespace after the previous token that is not whitespace.

const vmapl_messages = {
	'shouldBeOnNewLine': "'{{name}}' should be on a new line."
}

struct VmaplOptions {
	singleline int = 1
	multiline  int = 1
}

// vmapl_max reads a `singleline`/`multiline` option as parseOptions does: a number, or an object
// with a numeric `max`; anything else keeps the default.
fn vmapl_max(value json2.Any, default_max int) int {
	if value is f64 || value is int || value is i64 {
		return int(value.f64())
	}
	if value is map[string]json2.Any {
		max := value['max'] or { return default_max }
		if max is f64 || max is int || max is i64 {
			return int(max.f64())
		}
	}
	return default_max
}

fn vmapl_options(options []json2.Any) !VmaplOptions {
	o := option_object(vue_max_attributes_per_line, options, ['singleline', 'multiline'])!
	mut singleline := 1
	mut multiline := 1
	if value := o.values['singleline'] {
		singleline = vmapl_max(value, 1)
	}
	if value := o.values['multiline'] {
		// `if (options.multiline)`: 0 is falsy and keeps the default (the schema's minimum is 1).
		if !((value is f64 || value is int || value is i64) && value.f64() == 0) {
			multiline = vmapl_max(value, 1)
		}
	}
	return VmaplOptions{
		singleline: singleline
		multiline:  multiline
	}
}

fn (mut c Checker) lint_vue_max_attributes_per_line(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vmapl_options(c.rule_options(vue_max_attributes_per_line))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_start_tag || node.attributes.len == 0 {
			continue
		}
		stats.checked++
		single := c.vue.doc.loc(node.start).line == c.vue.doc.loc(node.end).line
		if single {
			if node.attributes.len > opts.singleline {
				c.vmapl_report(node.attributes[opts.singleline..], mut findings)!
			}
			continue
		}
		// groupAttrsByLine: an attribute that starts on the line the previous one ends on joins
		// its group.
		mut group := [node.attributes[0]]
		for k := 1; k <= node.attributes.len; k++ {
			if k < node.attributes.len {
				prev := c.vue.doc.nodes[node.attributes[k - 1]]
				cur := c.vue.doc.nodes[node.attributes[k]]
				if c.vue.doc.loc(prev.end).line == c.vue.doc.loc(cur.start).line {
					group << node.attributes[k]
					continue
				}
			}
			if group.len > opts.multiline {
				c.vmapl_report(group[opts.multiline..], mut findings)!
			}
			if k < node.attributes.len {
				group = [node.attributes[k]]
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) vmapl_report(attributes []int, mut findings []Finding) ! {
	for k, attr in attributes {
		a := &c.vue.doc.nodes[attr]
		name := c.vue_vnode_text(a.key)
		finding := c.vue_report_vnode(attr, 'shouldBeOnNewLine', {
			'name': name
		})
		if k != 0 {
			findings << finding
			continue
		}
		mut prev_end := -1
		for t := vue_lower_bound(c.vue.doc.tokens, a.start) - 1; t >= 0; t-- {
			token := c.vue.doc.tokens[t]
			if token.end <= a.start && token.typ != 'HTMLWhitespace' {
				prev_end = token.end
				break
			}
		}
		if prev_end < 0 {
			findings << finding
			continue
		}
		findings << c.with_fixes(finding, [fix_replace_range(prev_end, a.start, '\n')])!
	}
}
