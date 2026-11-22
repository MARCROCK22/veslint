module rules

import json2

// Port of the `svelte/html-self-closing` rule of eslint-plugin-svelte 3.24.1: an element without
// content (or with white space only) is self-closing or not by its kind (void, normal, svg, math,
// component, svelte), from the options (an object, or the presets "all", "html", "none"); the fix
// closes it (removing its content and end tag) or writes its end tag. The report starts at the
// start tag's `>` (or `/>`), located by the text, and ends with the element.

const shsc_messages = {
	'requireClosing':  'Require self-closing on {{type}}.'
	'disallowClosing': 'Disallow self-closing on {{type}}.'
}

const shsc_type_messages = {
	'normal':    'HTML elements'
	'void':      'HTML void elements'
	'svg':       'SVG elements'
	'math':      'MathML elements'
	'component': 'Svelte custom components'
	'svelte':    'Svelte special elements'
}

fn shsc_options(options []json2.Any) !map[string]string {
	mut o := {
		'void':      'always'
		'normal':    'never'
		'svg':       'always'
		'math':      'never'
		'component': 'always'
		'svelte':    'always'
	}
	if options.len == 0 {
		return o
	}
	option := options[0]
	if option is string {
		match option {
			'all' {
				for k, _ in o {
					o[k] = 'always'
				}
			}
			'html' {
				o['component'] = 'never'
			}
			'none' {
				for k, _ in o {
					o[k] = 'never'
				}
			}
			else {}
		}
		return o
	}
	// Another value than an object or a preset (the schema's object branch has no `type`) leaves
	// the defaults.
	if option !is map[string]json2.Any {
		return o
	}
	object := option_object(svelte_html_self_closing, options, ['void', 'normal', 'svg', 'math',
		'component', 'svelte'])!
	for k, _ in o {
		value := object.string_value(k, ['never', 'always', 'ignore'])!
		if value != '' {
			o[k] = value
		}
	}
	return o
}

// shsc_element_type is getElementType.
fn (c &Checker) shsc_element_type(i int) string {
	n := &c.svelte.doc.nodes[i]
	return if n.kind == 'component' {
		'component'
	} else if n.kind == 'special' {
		'svelte'
	} else if c.sv_is_void_html_element(i) {
		'void'
	} else if c.sv_is_svg_element(i) {
		'svg'
	} else if c.sv_is_mathml_element(i) {
		'math'
	} else {
		'normal'
	}
}

fn (mut c Checker) lint_svelte_html_self_closing(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	options := shsc_options(c.rule_options(svelte_html_self_closing))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.element) {
		n := doc.nodes[i]
		if n.start_tag < 0 {
			continue
		}
		// isElementEmpty: no children but white space texts (/^\s*$/).
		if !n.children.all(doc.nodes[it].typ == .text && doc.nodes[it].value.runes().all(is_js_space(it))) {
			continue
		}
		typ := c.shsc_element_type(i)
		option := options[typ] or { 'never' }
		if option == 'ignore' {
			continue
		}
		should_close := option == 'always'
		tag := doc.nodes[n.start_tag]
		if should_close == tag.self_closing {
			continue
		}
		mut fixes := []Fix{}
		if should_close {
			for child in n.children {
				fixes << Fix{
					start: doc.nodes[child].start
					end:   doc.nodes[child].end
				}
			}
			fixes << Fix{
				start: tag.end - 1
				end:   tag.end - 1
				text:  '/'
			}
			if n.end_tag >= 0 {
				fixes << Fix{
					start: doc.nodes[n.end_tag].start
					end:   doc.nodes[n.end_tag].end
				}
			}
		} else {
			fixes << Fix{
				start: tag.end - 2
				end:   tag.end - 1
			}
			if !c.sv_is_void_html_element(i) {
				fixes << Fix{
					start: n.end
					end:   n.end
					text:  '</${c.sv_element_name(i)}>'
				}
			}
		}
		has_fix, fix := c.merge_fixes(fixes)!
		findings << Finding{
			...c.sv_report(tag.end - if tag.self_closing { 2 } else { 1 }, c.sv_snode_loc_end(i),
				if should_close { 'requireClosing' } else { 'disallowClosing' }, {
					'type': shsc_type_messages[typ]
				})
			text_loc_start: true
			has_fix:        has_fix
			fix:            fix
		}
	}
	return findings
}
