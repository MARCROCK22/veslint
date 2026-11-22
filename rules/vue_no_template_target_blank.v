module rules

import json2
import time

// Port of the `vue/no-template-target-blank` rule of eslint-plugin-vue 10.12.1 (options
// `allowReferrer` and `enforceDynamicLinks`, "always" by default or "never"): a `target="_blank"`
// on a tag with an external `href` (or a `:href`, unless "never") and without a `rel` with
// `noopener` and (unless `allowReferrer`) `noreferrer`, with a suggestion that changes or adds the
// `rel`.

const vnttb_messages = {
	'missingRel': 'Using target="_blank" without rel="noopener noreferrer" is a security risk.'
}

struct VnttbOptions {
	allow_referrer  bool
	enforce_dynamic bool = true
}

fn vnttb_options(options []json2.Any) !VnttbOptions {
	o := option_object(vue_no_template_target_blank, options, ['allowReferrer', 'enforceDynamicLinks'])!
	enforce := o.string_value('enforceDynamicLinks', ['always', 'never'])!
	return VnttbOptions{
		allow_referrer:  o.bool_value('allowReferrer')!
		enforce_dynamic: enforce != 'never'
	}
}

// vnttb_is_external is /^(?:\w+:|\/\/)/.
fn vnttb_is_external(href string) bool {
	if href.starts_with('//') {
		return true
	}
	mut i := 0
	for i < href.len && (href[i].is_letter() || href[i].is_digit() || href[i] == `_`) {
		i++
	}
	return i > 0 && i < href.len && href[i] == `:`
}

fn (mut c Checker) lint_vue_no_template_target_blank(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vnttb_options(c.rule_options(vue_no_template_target_blank))!
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute || node.directive || c.vue.doc.nodes[node.key].name != 'target'
			|| node.value < 0 || c.vue.doc.nodes[node.value].text != '_blank' {
			continue
		}
		stats.checked++
		start_tag := node.parent
		attributes := c.vue.doc.nodes[start_tag].attributes
		mut secure := false
		mut external := false
		mut dynamic := false
		mut rel := -1
		for a in attributes {
			attr := &c.vue.doc.nodes[a]
			if attr.directive {
				if c.vue_directive_name(a) == 'bind' {
					if argument := c.vue_static_argument(a) {
						if argument == 'href' {
							dynamic = true
						}
					}
				}
				continue
			}
			key := c.vue.doc.nodes[attr.key].name
			if key == 'rel' {
				if rel < 0 {
					rel = a
				}
				if attr.value >= 0 {
					tags := c.vue.doc.nodes[attr.value].text.to_lower().split(' ')
					if 'noopener' in tags && (opts.allow_referrer || 'noreferrer' in tags) {
						secure = true
					}
				}
			} else if key == 'href' && attr.value >= 0
				&& vnttb_is_external(c.vue.doc.nodes[attr.value].text) {
				external = true
			}
		}
		if secure || !(external || (opts.enforce_dynamic && dynamic)) {
			continue
		}
		mut fix := Fix{}
		mut desc := ''
		if rel >= 0 {
			desc = 'Change `rel` attribute value to `noopener noreferrer`.'
			r := &c.vue.doc.nodes[rel]
			fix = fix_replace_range(r.start, r.end, 'rel="noopener noreferrer"')
		} else {
			desc = 'Add `rel="noopener noreferrer"`.'
			fix = fix_insert_at(node.end, ' rel="noopener noreferrer"')
		}
		findings << Finding{
			...c.vue_report_vnode(i, 'missingRel', {})
			suggestions: [Suggestion{
				desc: desc
				fix:  fix
			}]
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
