module rules

import estree
import json2
import time

// Port of the `vue/component-name-in-template-casing` rule of eslint-plugin-vue 10.12.1 (options:
// "PascalCase", the default, or "kebab-case"; globals, ignores, registeredComponentsOnly, default
// true): an element of the template that is a component (not a well-known HTML, SVG or MathML
// element, nor template/slot/component) whose name (the part before a `.`) is not in the case,
// fixed in its start and end tags; with registeredComponentsOnly, only the components the Vue
// objects register, the non-type-only variables of `<script setup>`'s module scope, the globals
// (names, or /regexps/ matched with the raw name). Nothing after an `eof-*` parse error.

const vue_component_name_in_template_casing_messages = {
	'incorrectCase': 'Component name "{{name}}" is not {{caseType}}.'
}

struct VcnitcOptions {
	case_type       string = 'PascalCase'
	ignores         VueRegexpGroup
	global_strings  []string
	global_patterns VueRegexpGroup
	registered_only bool = true
}

fn vcnitc_options(options []json2.Any) !VcnitcOptions {
	mut case_type := 'PascalCase'
	if options.len > 0 {
		value := options[0]
		if value is string && value in ['PascalCase', 'kebab-case'] {
			case_type = value
		}
	}
	o := option_object(vue_component_name_in_template_casing, if options.len > 1 {
		options[1..].clone()
	} else {
		[]json2.Any{}
	}, [
		'globals',
		'ignores',
		'registeredComponentsOnly',
	])!
	mut strings := []string{}
	mut patterns := []string{}
	for global in o.string_list('globals')! {
		if vue_is_regexp(global) {
			patterns << global
		} else {
			strings << global
		}
	}
	return VcnitcOptions{
		case_type:       case_type
		ignores:         vue_regexp_group(o.string_list('ignores')!)!
		global_strings:  strings
		global_patterns: vue_regexp_group(patterns)!
		registered_only: if value := o.values['registeredComponentsOnly'] {
			value !is bool || value as bool
		} else {
			true
		}
	}
}

fn (mut c Checker) lint_vue_component_name_in_template_casing(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	o := vcnitc_options(c.rule_options(vue_component_name_in_template_casing))!
	mut findings := []Finding{}
	if c.vue_has_invalid_eof() {
		return findings
	}
	mut registered := map[string]bool{}
	for name in o.global_strings {
		registered[vue_pascal_case(name)] = true
	}
	if s := c.vue_script(root, abs_path) {
		t := c.es_tree(root, abs_path) or { return findings }
		if s.has_setup {
			tree := c.scope_tree(root)
			module := vue_module_scope(tree)
			if module >= 0 {
				for v in tree.scopes[module].variables {
					if !c.vcnitc_is_type_only_import(t, tree.variables[v]) {
						registered[tree.variables[v].name] = true
					}
				}
			}
		}
		if o.registered_only {
			for object in s.objects_of(vue_all_object_types) {
				for component in vue_registered_components(t, object) {
					registered[component.name] = true
				}
			}
		}
	}
	doc := c.vue.doc
	for v in c.vue_template_vnodes() {
		node := &doc.nodes[v]
		if node.typ != .v_element {
			continue
		}
		raw := node.raw_name
		if o.ignores.matches(raw) || vue_is_html_well_known_element_name(raw)
			|| vue_is_svg_well_known_element_name(raw) || vue_is_math_well_known_element_name(raw)
			|| vue_is_builtin_element_name(raw) {
			continue
		}
		component_name := raw.all_before('.')
		if o.registered_only && vue_pascal_case(component_name) !in registered
			&& !o.global_patterns.matches(raw) {
			continue
		}
		stats.checked++
		if vue_case_check(o.case_type, component_name) {
			continue
		}
		start_tag := &doc.nodes[node.start_tag]
		open := c.vue_first_token_in(start_tag.start, start_tag.end) or { continue }
		casing := vue_case_exact_convert(o.case_type, component_name) + raw[component_name.len..]
		mut fixes := [fix_replace_range(open.start, open.end, '<${casing}')]
		if node.end_tag >= 0 {
			end_tag := &doc.nodes[node.end_tag]
			if end_open := c.vue_first_token_in(end_tag.start, end_tag.end) {
				fixes << fix_replace_range(end_open.start, end_open.end, '</${casing}')
			}
		}
		findings << c.with_fixes(c.vue_report(open.start, open.end, 'incorrectCase', {
			'name':     raw
			'caseType': o.case_type
		}), fixes)!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vcnitc_is_type_only_import is isTypeOnlyImport: definitions that are all type imports
// (`import type …`, `import { type … }`).
fn (mut c Checker) vcnitc_is_type_only_import(t &estree.EsTree, variable ScopeVariable) bool {
	if variable.defs.len == 0 {
		return false
	}
	for def in variable.defs {
		if def.kind != .import_binding {
			return false
		}
		mut specifier := c.es_index_of(t, def.node) or { return false }
		if t.typ(specifier) == .identifier {
			specifier = t.nodes[specifier].parent
		}
		declaration := t.nodes[specifier].parent
		if declaration < 0 || t.typ(declaration) != .import_declaration {
			return false
		}
		if (t.string_of(declaration, .import_kind) or { '' }) == 'type' {
			continue
		}
		if t.typ(specifier) == .import_specifier
			&& (t.string_of(specifier, .import_kind) or { '' }) == 'type' {
			continue
		}
		return false
	}
	return true
}
