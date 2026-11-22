module rules

import json2
import time

// Port of the `vue/no-duplicate-attributes` rule of eslint-plugin-vue 10.12.1 (options
// `allowCoexistClass` and `allowCoexistStyle`, both true by default: a `class` and a `:class`, or a
// `style` and a `:style`, may be on the same element).

const vnda_messages = {
	'duplicateAttribute': "Duplicate attribute '{{name}}'."
}

struct VndaOptions {
	allow_coexist_class bool = true
	allow_coexist_style bool = true
}

fn vnda_options(options []json2.Any) !VndaOptions {
	o := option_object(vue_no_duplicate_attributes, options, ['allowCoexistClass', 'allowCoexistStyle'])!
	// `options.allowCoexistStyle !== false`
	return VndaOptions{
		allow_coexist_class: if 'allowCoexistClass' in o.values {
			o.bool_value('allowCoexistClass')!
		} else {
			true
		}
		allow_coexist_style: if 'allowCoexistStyle' in o.values {
			o.bool_value('allowCoexistStyle')!
		} else {
			true
		}
	}
}

// vnda_name is getName: the name of a plain attribute, or the argument of a `v-bind` with a static
// one ('' for any other directive).
fn (c &Checker) vnda_name(attr int) string {
	a := &c.vue.doc.nodes[attr]
	if !a.directive {
		return c.vue.doc.nodes[a.key].name
	}
	if c.vue_directive_name(attr) != 'bind' {
		return ''
	}
	return c.vue_static_argument(attr) or { '' }
}

fn (mut c Checker) lint_vue_no_duplicate_attributes(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vnda_options(c.rule_options(vue_no_duplicate_attributes))!
	mut findings := []Finding{}
	mut directive_names := map[string]bool{}
	mut attribute_names := map[string]bool{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ == .v_start_tag {
			directive_names.clear()
			attribute_names.clear()
			continue
		}
		if node.typ != .v_attribute {
			continue
		}
		stats.checked++
		name := c.vnda_name(i)
		// `(… && attribute.key.argument.name) || null`: an empty name is no name.
		if name == '' {
			continue
		}
		duplicate := if (opts.allow_coexist_style && name == 'style')
			|| (opts.allow_coexist_class && name == 'class') {
			if node.directive { name in directive_names } else { name in attribute_names }
		} else {
			name in directive_names || name in attribute_names
		}
		if duplicate {
			findings << c.vue_report_vnode(i, 'duplicateAttribute', {
				'name': name
			})
		}
		if node.directive {
			directive_names[name] = true
		} else {
			attribute_names[name] = true
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
