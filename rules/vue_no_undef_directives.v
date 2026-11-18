module rules

import estree
import json2
import time

// Port of the `vue/no-undef-directives` rule of eslint-plugin-vue 10.12.1 (option ignore:
// names or /regexps/ of directives): a custom directive of the template that the `directives` of
// the Vue objects do not register (by its raw name, or case-insensitively when a registered name
// has capitals) and, with `<script setup>`, that no variable `v<Name>` of the global or module
// scope defines.

const vue_no_undef_directives_messages = {
	'undef': "The 'v-{{name}}' directive has been used, but not defined."
}

fn vnud_options(options []json2.Any) !VueRegexpGroup {
	o := option_object(vue_no_undef_directives, options, ['ignore'])!
	return vue_regexp_group(o.string_list('ignore')!)!
}

fn (mut c Checker) lint_vue_no_undef_directives(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	ignored := vnud_options(c.rule_options(vue_no_undef_directives))!
	mut findings := []Finding{}
	mut in_options := map[string]bool{}
	mut in_setup := map[string]bool{}
	mut setup := false
	if s := c.vue_script(root, abs_path) {
		t := c.es_tree(root, abs_path) or { return findings }
		setup = s.has_setup
		if setup {
			tree := c.scope_tree(root)
			for v in tree.scopes[0].variables {
				in_setup[tree.variables[v].name] = true
			}
			module := vue_module_scope(tree)
			if module >= 0 {
				for v in tree.scopes[module].variables {
					in_setup[tree.variables[v].name] = true
				}
			}
		}
		// onVueObjectEnter with `<script setup>`, executeOnVue without: the same objects.
		for object in s.objects_of(vue_all_object_types) {
			for name in vnud_registered_directives(t, object) {
				in_options[name] = true
			}
		}
	}
	doc := c.vue.doc
	for v in c.vue_template_vnodes() {
		node := &doc.nodes[v]
		if node.typ != .v_attribute || !node.directive {
			continue
		}
		key := &doc.nodes[node.key]
		name := c.vue_directive_name(v)
		if name in vue_builtin_directive_names {
			continue
		}
		stats.checked++
		raw := if key.dir_name >= 0 && doc.nodes[key.dir_name].raw_name != '' {
			doc.nodes[key.dir_name].raw_name
		} else {
			name
		}
		if raw in vue_builtin_directive_names || ignored.matches(raw, vue_kebab_case(raw)) {
			continue
		}
		if setup && 'v${vue_capitalize(vue_camel_case(raw))}' in in_setup {
			continue
		}
		if vnud_is_defined_in_options(raw, in_options) {
			continue
		}
		findings << c.vue_report_vnode(node.key, 'undef', {
			'name': raw
		})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnud_is_defined_in_options is isDefinedInOptions.
fn vnud_is_defined_in_options(raw string, defined map[string]bool) bool {
	if raw in defined {
		return true
	}
	camel := vue_js_to_lower(vue_camel_case(raw))
	for name, _ in defined {
		lower := vue_js_to_lower(name)
		if name != lower && lower == camel {
			return true
		}
	}
	return false
}

// vnud_registered_directives is getRegisteredDirectives: the non-empty static names of the
// properties of the first `directives` property whose value is an object.
fn vnud_registered_directives(t &estree.EsTree, object int) []string {
	directives := vue_find_property(t, object, 'directives', fn [t] (p int) bool {
		return t.typ(vue_property_value(t, p)) == .object_expression
	})
	if directives < 0 {
		return []
	}
	mut out := []string{}
	for p in t.list(vue_property_value(t, directives), .properties) or { []int{} } {
		if t.typ(p) != .property {
			continue
		}
		name := vue_static_property_name(t, p) or { continue }
		if name != '' {
			out << name
		}
	}
	return out
}
