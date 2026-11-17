module rules

import json2
import time

// Port of the `vue/no-v-text-v-html-on-component` rule of eslint-plugin-vue 10.12.1 (options
// `allow`, component names, and `ignoreElementNamespaces`): a `v-text` or a `v-html` on a custom
// component that `allow` does not name (as written, in PascalCase or in kebab-case).

const vnvtvhoc_messages = {
	'disallow': "Using {{directiveName}} on component may break component's content."
}

struct VnvtvhocOptions {
	allow                     []string
	ignore_element_namespaces bool
}

fn vnvtvhoc_options(options []json2.Any) !VnvtvhocOptions {
	o := option_object(vue_no_v_text_v_html_on_component, options, ['allow', 'ignoreElementNamespaces'])!
	return VnvtvhocOptions{
		allow:                     if 'allow' in o.values { o.string_list('allow')! } else { [] }
		ignore_element_namespaces: o.bool_value('ignoreElementNamespaces')!
	}
}

fn (mut c Checker) lint_vue_no_v_text_v_html_on_component(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vnvtvhoc_options(c.rule_options(vue_no_v_text_v_html_on_component))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		name := c.vue_directive_name(i)
		if !c.vue.doc.nodes[i].directive || name !in ['text', 'html'] {
			continue
		}
		stats.checked++
		element := c.vue_attribute_element(i)
		if !c.vue_is_custom_component(element, opts.ignore_element_namespaces) {
			continue
		}
		raw := c.vue.doc.nodes[element].raw_name
		if raw in opts.allow || vue_pascal_case(raw) in opts.allow || vue_kebab_case(raw) in opts.allow {
			continue
		}
		findings << c.vue_report_vnode(i, 'disallow', {
			'directiveName': 'v-${name}'
		})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
