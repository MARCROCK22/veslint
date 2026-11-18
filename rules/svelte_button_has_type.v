module rules

import json2

// Port of the `svelte/button-has-type` rule of eslint-plugin-svelte 3.24.1: a `<button>` needs a
// `type` attribute (or a `bind:type`, a `{type}` shorthand or a spread attribute) whose static
// value is an allowed type (options button, submit, reset: true by default).

const sbht_messages = {
	'missingTypeAttribute':   'Missing an explicit type attribute for button.'
	'invalidTypeAttribute':   '{{value}} is an invalid value for button type attribute.'
	'forbiddenTypeAttribute': '{{value}} is a forbidden value for button type attribute.'
	'emptyTypeAttribute':     'A value must be set for button type attribute.'
}

struct SbhtOptions {
	button bool = true
	submit bool = true
	reset  bool = true
}

fn sbht_options(options []json2.Any) !SbhtOptions {
	o := option_object(svelte_button_has_type, options, ['button', 'submit', 'reset'])!
	return SbhtOptions{
		button: if 'button' in o.values { o.bool_value('button')! } else { true }
		submit: if 'submit' in o.values { o.bool_value('submit')! } else { true }
		reset:  if 'reset' in o.values { o.bool_value('reset')! } else { true }
	}
}

fn (mut c Checker) lint_svelte_button_has_type(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	options := sbht_options(c.rule_options(svelte_button_has_type))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	// "SvelteElement[name.name='button'] > SvelteStartTag"
	for tag in c.sv_snodes_of(.start_tag) {
		element := doc.nodes[tag].parent
		if element < 0 || doc.nodes[element].typ != .element
			|| c.sv_ref_name(doc.nodes[element].name_ref) != 'button' {
			continue
		}
		type_attr := c.sv_find_attribute(tag, 'type')
		if type_attr >= 0 {
			if doc.nodes[type_attr].values.len == 0 {
				findings << c.sv_report_snode(type_attr, 'emptyTypeAttribute', {})
				continue
			}
			value := c.sv_static_attribute_value(type_attr) or { continue }
			allowed := match value {
				'button' { options.button }
				'submit' { options.submit }
				'reset' { options.reset }
				else { true }
			}
			if value !in ['button', 'submit', 'reset'] {
				findings << c.sv_report_snode(type_attr, 'invalidTypeAttribute', {
					'value': value
				})
			} else if !allowed {
				findings << c.sv_report_snode(type_attr, 'forbiddenTypeAttribute', {
					'value': value
				})
			}
			continue
		}
		type_dir := c.sv_find_bind_directive(tag, 'type')
		if type_dir >= 0 {
			if doc.nodes[type_dir].expression.idx < 0 {
				findings << c.sv_report_snode(type_dir, 'emptyTypeAttribute', {})
			}
			continue
		}
		if c.sv_find_shorthand_attribute(tag, 'type') >= 0 {
			continue
		}
		if doc.nodes[tag].attributes.any(doc.nodes[it].typ == .spread_attribute) {
			continue
		}
		findings << c.sv_report_snode(tag, 'missingTypeAttribute', {})
	}
	return findings
}
