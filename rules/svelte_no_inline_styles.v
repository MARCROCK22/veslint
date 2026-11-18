module rules

import json2

// Port of the `svelte/no-inline-styles` rule of eslint-plugin-svelte 3.24.1: the `style` attributes
// and `style:` directives of HTML elements, and with allowTransitions false their transitions.

const snis_messages = {
	'hasStyleAttribute': 'Found disallowed style attribute.'
	'hasStyleDirective': 'Found disallowed style directive.'
	'hasTransition':     'Found disallowed transition.'
}

fn snis_options(options []json2.Any) !bool {
	o := option_object(svelte_no_inline_styles, options, ['allowTransitions'])!
	return if 'allowTransitions' in o.values { o.bool_value('allowTransitions')! } else { true }
}

fn (mut c Checker) lint_svelte_no_inline_styles(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	allow_transitions := snis_options(c.rule_options(svelte_no_inline_styles))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.element) {
		if doc.nodes[i].kind != 'html' || doc.nodes[i].start_tag < 0 {
			continue
		}
		for a in doc.nodes[doc.nodes[i].start_tag].attributes {
			n := doc.nodes[a]
			if n.typ == .style_directive {
				findings << c.sv_report_snode(a, 'hasStyleDirective', {})
			}
			if n.typ == .attribute && c.sv_attribute_name(a) == 'style' {
				findings << c.sv_report_snode(a, 'hasStyleAttribute', {})
			}
			if !allow_transitions && n.typ == .directive && n.kind == 'Transition' {
				findings << c.sv_report_snode(a, 'hasTransition', {})
			}
		}
	}
	return findings
}
