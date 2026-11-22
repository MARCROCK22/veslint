module rules

import estree
import jsregexp
import json2
import os
import time

// Port of the `vue/no-undef-components` rule of eslint-plugin-vue 10.12.1 (option
// ignorePatterns): a component of the template (an element that is not a well-known HTML, SVG or
// MathML element nor a built-in component, or the value of an `is` attribute) that is not defined:
// with `<script setup>`, by a variable of the global or module scope that is not only a type (by
// its name, camelized or PascalCase, or the part before a `.`), the file's name, or the `name` of
// the exported object or defineOptions; otherwise by the components the Vue objects register or
// their `name` (also checking `:is`/`v-is` literals).

const vue_no_undef_components_messages = {
	'undef':    "The '<{{name}}>' component has been used, but not defined."
	'typeOnly': "The '<{{name}}>' component has been used, but '{{name}}' only refers to a type."
}

fn vnuco_options(options []json2.Any) ![]jsregexp.JsRegex {
	o := option_object(vue_no_undef_components, options, ['ignorePatterns'])!
	mut out := []jsregexp.JsRegex{}
	for pattern in o.string_list('ignorePatterns')! {
		out << jsregexp.js_regex_new(pattern, '')!
	}
	return out
}

// VnucoNames are DefinedInSetupComponents (`kebab` empty) or DefinedInOptionComponents.
struct VnucoNames {
mut:
	names map[string]bool
	kebab map[string]bool
}

// vnuco_camelize is camelize: `-x` becomes `X` (x a word character).
fn vnuco_camelize(s string) string {
	mut out := []u8{cap: s.len}
	mut i := 0
	for i < s.len {
		if s[i] == `-` && i + 1 < s.len
			&& (s[i + 1].is_letter() || s[i + 1].is_digit() || s[i + 1] == `_`) {
			out << s[i + 1].ascii_str().to_upper()[0]
			i += 2
			continue
		}
		out << s[i]
		i++
	}
	return out.bytestr()
}

// is_defined_in_setup is DefinedInSetupComponents.isDefinedComponent.
fn (n &VnucoNames) is_defined_in_setup(raw string) bool {
	if raw in n.names {
		return true
	}
	camel := vnuco_camelize(raw)
	if camel in n.names || vue_capitalize(camel) in n.names {
		return true
	}
	dot := raw.index('.') or { -1 }
	return dot > 0 && n.is_defined_in_setup(raw[..dot])
}

fn (mut n VnucoNames) add_option_name(name string) {
	n.names[name] = true
	n.kebab[vue_kebab_case(name)] = true
}

// is_defined_in_options is DefinedInOptionComponents.isDefinedComponent: a component registered
// as `foo-bar` cannot be used as `FooBar`.
fn (n &VnucoNames) is_defined_in_options(raw string) bool {
	return raw in n.names || (vue_kebab_case(raw) in n.kebab && !vue_is_pascal_case(raw))
}

fn (mut c Checker) lint_vue_no_undef_components(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	ignore_patterns := vnuco_options(c.rule_options(vue_no_undef_components))!
	mut findings := []Finding{}
	mut in_setup := VnucoNames{}
	mut in_options := VnucoNames{}
	mut type_only := map[string]bool{}
	mut setup := false
	if s := c.vue_script(root, abs_path) {
		t := c.es_tree(root, abs_path) or { return findings }
		setup = s.has_setup
		if setup {
			tree := c.scope_tree(root)
			for v in tree.scopes[0].variables {
				in_setup.names[tree.variables[v].name] = true
			}
			module := vue_module_scope(tree)
			if module >= 0 {
				for v in tree.scopes[module].variables {
					variable := tree.variables[v]
					if (variable.is_type_variable() && !variable.is_value_variable())
						|| c.vcnitc_is_type_only_import(t, variable) {
						type_only[variable.name] = true
					} else {
						in_setup.names[variable.name] = true
					}
				}
			}
			// For circular references.
			filename := os.base(s.filename)
			ext := os.file_ext(filename)
			in_setup.names[filename[..filename.len - ext.len]] = true
			for object in s.objects_of([VueObjectType.export]) {
				vnuco_add_self_name(t, object, mut in_options)
			}
			for call in c.vue_macros_named(t, 'defineOptions') {
				args := t.list(call, .arguments) or { []int{} }
				if args.len > 0 && t.typ(args[0]) == .object_expression {
					vnuco_add_self_name(t, args[0], mut in_options)
				}
			}
		} else {
			for object in s.objects_of(vue_all_object_types) {
				for component in vue_registered_components(t, object) {
					in_options.add_option_name(component.name)
				}
				vnuco_add_self_name(t, object, mut in_options)
			}
		}
	}
	doc := c.vue.doc
	for v in c.vue_template_vnodes() {
		node := &doc.nodes[v]
		mut name := ''
		mut report := -1
		if node.typ == .v_element {
			name = node.raw_name
			report = node.start_tag
		} else if node.typ == .v_attribute && !node.directive {
			if doc.nodes[node.key].name != 'is' || node.value < 0 {
				continue
			}
			value := doc.nodes[node.value].text
			name = if value.starts_with('vue:') { value[4..] } else { value }
			report = v
		} else if node.typ == .v_attribute && !setup {
			dir_name := c.vue_directive_name(v)
			key := &doc.nodes[node.key]
			is_bind_is := dir_name == 'bind' && key.argument >= 0
				&& doc.nodes[key.argument].typ == .v_identifier
				&& doc.nodes[key.argument].name == 'is'
			if (!is_bind_is && dir_name != 'is') || node.value < 0
				|| doc.nodes[node.value].typ != .v_expression_container {
				continue
			}
			expression := doc.nodes[node.value].expression
			if expression.kind != .estree || c.vue_expr_type(expression) != 'Literal' {
				continue
			}
			name = vue_literal_string(&doc.snippets[expression.snippet].es, expression.node)
			report = v
		} else {
			continue
		}
		stats.checked++
		if !vnuco_is_verify_target(name, ignore_patterns) {
			continue
		}
		if setup {
			if in_setup.is_defined_in_setup(name) || in_options.is_defined_in_options(name) {
				continue
			}
		} else if in_options.is_defined_in_options(name) {
			continue
		}
		findings << c.vue_report_vnode(report, if setup && name in type_only {
			'typeOnly'
		} else {
			'undef'
		}, {
			'name': name
		})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnuco_add_self_name adds the string `name` of an object.
fn vnuco_add_self_name(t &estree.EsTree, object int, mut names VnucoNames) {
	property := vue_find_property(t, object, 'name', none)
	if property < 0 || !vue_is_string_literal(t, vue_property_value(t, property)) {
		return
	}
	name := vue_string_literal_value(t, vue_property_value(t, property), false) or { return }
	if name != '' {
		names.add_option_name(name)
	}
}

// vnuco_is_verify_target is isVerifyTargetComponent.
fn vnuco_is_verify_target(raw string, ignore_patterns []jsregexp.JsRegex) bool {
	kebab := vue_kebab_case(raw)
	if vue_is_html_well_known_element_name(raw) || vue_is_svg_well_known_element_name(raw)
		|| vue_is_math_well_known_element_name(raw) || kebab in vue_builtin_component_names {
		return false
	}
	pascal := vue_pascal_case(raw)
	for r in ignore_patterns {
		if vue_regexp_test(&r, raw) || vue_regexp_test(&r, kebab) || vue_regexp_test(&r, pascal) {
			return false
		}
	}
	return true
}
