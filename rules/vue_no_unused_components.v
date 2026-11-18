module rules

import json2
import time

// Port of the `vue/no-unused-components` rule of eslint-plugin-vue 10.12.1 (option
// ignoreWhenBindingPresent, default true): the components the last Vue object of the script
// registers that no element, `is` attribute or `:is`/`v-is` literal of the template uses (a
// PascalCase or camelCase name is used by any name without `_` that converts to it); nothing when
// the root <template> has a `src`, or, with ignoreWhenBindingPresent, when an `:is` or `v-is` is
// not a literal.

const vue_no_unused_components_messages = {
	'unused': 'The "{{name}}" component has been registered but not used.'
}

fn vnuc_options(options []json2.Any) !bool {
	o := option_object(vue_no_unused_components, options, ['ignoreWhenBindingPresent'])!
	if 'ignoreWhenBindingPresent' !in o.values {
		return true
	}
	return o.bool_value('ignoreWhenBindingPresent')!
}

fn (mut c Checker) lint_vue_no_unused_components(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	ignore_when_binding_present := vnuc_options(c.rule_options(vue_no_unused_components))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	mut registered := []VueRegisteredComponent{}
	if s := c.vue_script(root, abs_path) {
		objects := s.objects_of(vue_all_object_types)
		if objects.len > 0 {
			registered = vue_registered_components(t, objects.last())
		}
	}
	if registered.len == 0 {
		return findings
	}
	doc := c.vue.doc
	mut used := []string{}
	for v in c.vue_template_vnodes() {
		node := &doc.nodes[v]
		if node.typ == .v_element {
			if !vue_is_html_well_known_element_name(node.raw_name)
				&& !vue_is_svg_well_known_element_name(node.raw_name)
				&& !vue_is_math_well_known_element_name(node.raw_name) && node.raw_name !in used {
				used << node.raw_name
			}
			continue
		}
		if node.typ != .v_attribute {
			continue
		}
		if !node.directive {
			if doc.nodes[node.key].name == 'is' && node.value >= 0 {
				value := doc.nodes[node.value].text
				// Usage on native elements 3.1+.
				name := if value.starts_with('vue:') { value[4..] } else { value }
				if name !in used {
					used << name
				}
			}
			continue
		}
		dir_name := c.vue_directive_name(v)
		key := &doc.nodes[node.key]
		is_bind_is := dir_name == 'bind' && key.argument >= 0
			&& doc.nodes[key.argument].typ == .v_identifier && doc.nodes[key.argument].name == 'is'
		if !is_bind_is && dir_name != 'is' {
			continue
		}
		if node.value < 0 || doc.nodes[node.value].typ != .v_expression_container {
			continue
		}
		expression := doc.nodes[node.value].expression
		if expression.is_null() {
			continue
		}
		if expression.kind == .estree && c.vue_expr_type(expression) == 'Literal' {
			es := &doc.snippets[expression.snippet].es
			value := es.get(expression.node, .value)
			if value is string && value !in used {
				used << value
			}
		} else if ignore_when_binding_present {
			return findings
		}
	}
	if c.vue_has_attribute(doc.template_body, 'src', none) {
		return findings
	}
	for component in registered {
		stats.checked++
		name := component.name
		if vue_is_pascal_case(name) || vue_is_camel_case(name) {
			if used.any(!it.contains('_')
				&& (name == vue_pascal_case(it) || name == vue_camel_case(it))) {
				continue
			}
		} else if name in used {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, component.node)
			message_id: 'unused'
			data:       {
				'name': name
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
