module rules

import json2

// Port of the `svelte/no-restricted-html-elements` rule of eslint-plugin-svelte 3.24.1: the HTML
// elements the options name (each option an element name, or {elements, message}) are reported
// on their start tag, with the option's message or the default one.

const snrhe_messages = map[string]string{}

struct SnrheOption {
	elements []string
	message  string
}

fn snrhe_options(options []json2.Any) ![]SnrheOption {
	mut out := []SnrheOption{}
	for option in options {
		if option is string {
			out << SnrheOption{
				elements: [option]
			}
			continue
		}
		o := option_object(svelte_no_restricted_html_elements, [option], ['elements', 'message'])!
		message := o.values['message'] or { json2.Any('') }
		out << SnrheOption{
			elements: o.string_list('elements')!
			message:  if message is string { message } else { '' }
		}
	}
	return out
}

fn (mut c Checker) lint_svelte_no_restricted_html_elements(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	options := snrhe_options(c.rule_options(svelte_no_restricted_html_elements))!
	if !c.is_svelte() || options.len == 0 {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.element) {
		n := doc.nodes[i]
		if n.kind != 'html' || n.name_ref.es || n.name_ref.idx < 0
			|| doc.nodes[n.name_ref.idx].typ != .name || n.start_tag < 0 {
			continue
		}
		name := doc.nodes[n.name_ref.idx].name
		tag := doc.nodes[n.start_tag]
		for option in options {
			message := if option.message != '' {
				option.message
			} else {
				'Unexpected use of forbidden HTML element ${name}.'
			}
			for element in option.elements {
				if element == name {
					findings << c.sv_report_message(tag.start, c.sv_snode_loc_end(n.start_tag),
						message)
				}
			}
		}
	}
	return findings
}
