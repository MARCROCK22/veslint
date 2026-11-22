module rules

import json2

// Port of the `svelte/first-attribute-linebreak` rule of eslint-plugin-svelte 3.24.1: the first
// attribute of a start tag goes on the line of the tag's name ("beside", the default for a tag
// whose attributes are on one line) or below it ("below", the default for attributes on several
// lines). The fix replaces what is between the token before the attribute and it with a space or a
// line break.

const sfal_messages = {
	'expected':   'Expected a linebreak before this attribute.'
	'unexpected': 'Expected no linebreak before this attribute.'
}

struct SfalOptions {
	multiline_below  bool = true
	singleline_below bool
}

fn sfal_options(options []json2.Any) !SfalOptions {
	o := option_object(svelte_first_attribute_linebreak, options, ['multiline', 'singleline'])!
	multiline := o.string_value('multiline', ['below', 'beside'])!
	singleline := o.string_value('singleline', ['below', 'beside'])!
	return SfalOptions{
		multiline_below:  multiline != 'beside'
		singleline_below: singleline == 'below'
	}
}

fn (mut c Checker) lint_svelte_first_attribute_linebreak(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	options := sfal_options(c.rule_options(svelte_first_attribute_linebreak))!
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
		first := attributes[0]
		last := attributes.last()
		first_line := c.sv_line(doc.nodes[first].start)
		below := if first_line == c.sv_line(c.sv_snode_loc_end(last)) {
			options.singleline_below
		} else {
			options.multiline_below
		}
		name := doc.nodes[doc.nodes[tag].parent].name_ref
		if name.idx < 0 {
			continue
		}
		_, name_end := c.sv_ref_range(name)
		name_line := if name.es {
			c.sv_line(name_end)
		} else {
			c.sv_line(c.sv_snode_loc_end(name.idx))
		}
		if !below {
			if name_line == first_line {
				continue
			}
		} else if name_line < first_line {
			continue
		}
		prev := c.sv_token_before(doc.nodes[first].start, true) or { continue }
		findings << Finding{
			...c.sv_report_snode(first, if below { 'expected' } else { 'unexpected' }, {})
			has_fix: true
			fix:     Fix{
				start: prev.end
				end:   doc.nodes[first].start
				text:  if below { '\n' } else { ' ' }
			}
		}
	}
	return findings
}
