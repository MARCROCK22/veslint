module rules

import json2

// Port of the `svelte/max-attributes-per-line` rule of eslint-plugin-svelte 3.24.1: at most
// `singleline` (1 by default) attributes in a start tag on one line, and at most `multiline` (1)
// per line of a start tag on several lines; the first attribute past the limit is reported, and
// the fix puts it on a new line.

const smapl_messages = {
	'requireNewline': "'{{name}}' should be on a new line."
}

struct SmaplOptions {
	multiline  int = 1
	singleline int = 1
}

fn smapl_options(options []json2.Any) !SmaplOptions {
	o := option_object(svelte_max_attributes_per_line, options, ['multiline', 'singleline'])!
	multiline := o.values['multiline'] or { json2.Any(f64(1)) }
	singleline := o.values['singleline'] or { json2.Any(f64(1)) }
	return SmaplOptions{
		multiline:  if multiline is f64 { int(multiline) } else { 1 }
		singleline: if singleline is f64 { int(singleline) } else { 1 }
	}
}

// smapl_report reports an attribute (none past the end of the list).
fn (c &Checker) smapl_report(attributes []int, index int, mut findings []Finding) {
	if index >= attributes.len {
		return
	}
	attr := attributes[index]
	doc := c.svelte.doc
	n := doc.nodes[attr]
	name := if n.typ in [.attribute, .shorthand_attribute, .directive, .style_directive,
		.special_directive] {
		s, e := c.sv_ref_range(n.key)
		c.sv_text(s, e)
	} else {
		c.sv_text(n.start, n.end)
	}
	prev := c.sv_token_before(n.start, true) or { return }
	findings << Finding{
		...c.sv_report_snode(attr, 'requireNewline', {
			'name': name
		})
		has_fix: true
		fix:     Fix{
			start: prev.end
			end:   n.start
			text:  '\n'
		}
	}
}

fn (mut c Checker) lint_svelte_max_attributes_per_line(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	options := smapl_options(c.rule_options(svelte_max_attributes_per_line))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for tag in c.sv_snodes_of(.start_tag) {
		attributes := doc.nodes[tag].attributes
		if attributes.len == 0 {
			continue
		}
		if c.sv_line(doc.nodes[tag].start) == c.sv_line(c.sv_snode_loc_end(tag)) {
			if attributes.len > options.singleline {
				c.smapl_report(attributes, options.singleline, mut findings)
			}
			continue
		}
		// groupAttributesByLine: a new group unless the attribute starts on the line where the
		// current group's first attribute ends.
		mut groups := [][]int{}
		for a in attributes {
			if groups.len > 0 && c.sv_line(c.sv_snode_loc_end(groups.last()[0])) == c.sv_line(doc.nodes[a].start) {
				groups[groups.len - 1] << a
			} else {
				groups << [a]
			}
		}
		for g in groups {
			c.smapl_report(g, options.multiline, mut findings)
		}
	}
	return findings
}
