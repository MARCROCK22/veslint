module rules

import json2
import time

// Port of the `vue/html-self-closing` rule of eslint-plugin-vue 10.12.1 (options `html.normal`,
// `html.void`, `html.component`, `svg`, `math`: "always", "never" or "any"): an empty element of a
// kind whose mode is "always" that is not self-closing (fixed to `/>`), or a self-closing one of
// a kind whose mode is "never" (fixed to `>` for a void element, to an end tag otherwise). Not the
// top-level elements, and nothing when the document has an `eof-*` parse error.

const vhsc_messages = {
	'requireSelfClosing':  'Require self-closing on {{elementType}} (<{{name}}>).'
	'disallowSelfClosing': 'Disallow self-closing on {{elementType}} (<{{name}}/>).'
}

struct VhscOptions {
	normal    string = 'always'
	void      string = 'never'
	component string = 'always'
	svg       string = 'always'
	math      string = 'always'
}

// vhsc_mode is `(options && options.x) || default`: a value that is not a non-empty string
// (the schema allows only the three modes) keeps the default.
fn vhsc_mode(m map[string]json2.Any, key string, default_value string) string {
	value := m[key] or { return default_value }
	if value is string && value != '' {
		return value
	}
	return default_value
}

fn vhsc_options(options []json2.Any) !VhscOptions {
	o := option_object(vue_html_self_closing, options, ['html', 'svg', 'math'])!
	mut html := map[string]json2.Any{}
	if value := o.values['html'] {
		if value is map[string]json2.Any {
			html = value.clone()
		}
	}
	return VhscOptions{
		normal:    vhsc_mode(html, 'normal', 'always')
		void:      vhsc_mode(html, 'void', 'never')
		component: vhsc_mode(html, 'component', 'always')
		svg:       vhsc_mode(o.values, 'svg', 'always')
		math:      vhsc_mode(o.values, 'math', 'always')
	}
}

// vhsc_element_type is getElementType with the mode and the message of the kind ('' mode for an
// unknown element).
fn (c &Checker) vhsc_element_type(element int, opts VhscOptions) (string, string, bool) {
	el := &c.vue.doc.nodes[element]
	if c.vue_is_custom_component(element, false) || el.raw_name.to_lower() in [
		'template',
		'slot',
		'component',
	] {
		return opts.component, 'Vue.js custom components', false
	}
	if el.namespace == .html {
		if vue_is_html_void_element_name(el.name) {
			return opts.void, 'HTML void elements', true
		}
		return opts.normal, 'HTML elements', false
	}
	if el.namespace == .svg {
		return opts.svg, 'SVG elements', false
	}
	if el.namespace == .mathml {
		return opts.math, 'MathML elements', false
	}
	return '', 'unknown elements', false
}

fn (mut c Checker) lint_vue_html_self_closing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	if c.vue.doc.errors.any(it.code.starts_with('eof-')) {
		return []
	}
	sw := time.new_stopwatch()
	opts := vhsc_options(c.rule_options(vue_html_self_closing))!
	mut findings := []Finding{}
	src := c.vue.doc.src
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_element || node.parent < 0
			|| c.vue.doc.nodes[node.parent].typ == .v_document_fragment {
			continue
		}
		stats.checked++
		mode, kind, is_void := c.vhsc_element_type(i, opts)
		start_tag := &c.vue.doc.nodes[node.start_tag]
		data := {
			'elementType': kind
			'name':        node.raw_name
		}
		close := c.vue_last_token_in(start_tag.start, start_tag.end) or { continue }
		if mode == 'always' && !start_tag.self_closing {
			content_end := if node.end_tag < 0 {
				node.end
			} else {
				c.vue.doc.nodes[node.end_tag].start
			}
			if js_trim(c.vue_text(start_tag.end, content_end)) == '' {
				finding := if node.end_tag >= 0 {
					c.vue_report_vnode(node.end_tag, 'requireSelfClosing', data)
				} else {
					c.vue_report_vnode(i, 'requireSelfClosing', data)
				}
				if close.typ == 'HTMLTagClose' {
					before := vu4_rune_before(src, close.start)
					text := if before != 0 && is_js_space(before) { '/>' } else { ' />' }
					findings << c.with_fixes(finding, [fix_replace_range(close.start, node.end,
						text)])!
				} else {
					findings << finding
				}
			}
		}
		if mode == 'never' && start_tag.self_closing {
			finding := c.vue_report(node.end - 2, node.end, 'disallowSelfClosing', data)
			if close.typ != 'HTMLSelfClosingTagClose' {
				findings << finding
			} else if is_void {
				findings << c.with_fixes(finding, [fix_replace_range(close.start, close.end, '>')])!
			} else {
				findings << c.with_fixes(finding, [
					fix_replace_range(node.start, node.end, src[node.start..close.start] +
						'></${node.raw_name}>'),
				])!
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
