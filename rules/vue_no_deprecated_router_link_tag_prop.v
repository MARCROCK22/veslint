module rules

import json2
import time

// Port of the `vue/no-deprecated-router-link-tag-prop` rule of eslint-plugin-vue 10.12.1 (option
// `components`, ["RouterLink"] by default, each matched in kebab-case and in PascalCase): the
// `tag` attribute (its key) or the argument of a `:tag` of such a component.

const vndrltp_messages = {
	'deprecated': "'tag' property on '{{element}}' component is deprecated. Use scoped slots instead."
}

fn vndrltp_options(options []json2.Any) ![]string {
	o := option_object(vue_no_deprecated_router_link_tag_prop, options, ['components'])!
	components := if 'components' in o.values {
		o.string_list('components')!
	} else {
		['RouterLink']
	}
	mut names := []string{}
	for component in components {
		names << vue_kebab_case(component)
		names << vue_pascal_case(component)
	}
	return names
}

fn (mut c Checker) lint_vue_no_deprecated_router_link_tag_prop(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	names := vndrltp_options(c.rule_options(vue_no_deprecated_router_link_tag_prop))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_element || node.raw_name !in names {
			continue
		}
		stats.checked++
		mut tag_key := -1
		attr := c.vue_get_attribute(i, 'tag', none)
		if attr >= 0 {
			tag_key = c.vue.doc.nodes[attr].key
		} else {
			directive := c.vue_get_directive(i, 'bind', 'tag')
			if directive >= 0 {
				argument := c.vue_directive_argument(directive)
				if argument >= 0 && c.vue.doc.nodes[argument].typ == .v_identifier {
					tag_key = argument
				}
			}
		}
		if tag_key >= 0 {
			findings << c.vue_report_vnode(tag_key, 'deprecated', {
				'element': node.raw_name
			})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
