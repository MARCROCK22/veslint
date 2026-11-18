module rules

import estree
import time

// Port of the `vue/no-props-shadow` rule of eslint-plugin-vue 10.12.1 (no options): a top-level
// declaration of `<script setup>` (of the module scope) named like a prop of its `defineProps`,
// other than a type-only one and than the variables the props are destructured into.

const vue_no_props_shadow_messages = {
	'shadow': "Declaration of '{{name}}' shadows the prop with the same name."
}

fn (mut c Checker) lint_vue_no_props_shadow(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	if !s.has_setup {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	mut prop_names := map[string]bool{}
	mut declarators := map[int]bool{}
	for call in c.vue_macros_named(t, 'defineProps') {
		for prop in c.vue_define_props(root, t, call, abs_path, true, mut stats) {
			if prop.has_name {
				prop_names[prop.name] = true
			}
		}
		target := if vue_has_with_defaults(t, call) { t.nodes[call].parent } else { call }
		parent := t.nodes[target].parent
		if parent >= 0 && t.typ(parent) == .variable_declarator {
			declarators[parent] = true
		}
	}
	if prop_names.len == 0 {
		return findings
	}
	tree := c.scope_tree(root)
	mut module_scope := 0
	for child in tree.scopes[0].children {
		if tree.scopes[child].kind == .esmodule {
			module_scope = child
			break
		}
	}
	for v in tree.scopes[module_scope].variables {
		variable := tree.variables[v]
		if variable.name !in prop_names {
			continue
		}
		stats.checked++
		if c.vue_is_type_only_variable(t, variable) {
			continue
		}
		if variable.defs.any(it.kind == .variable
			&& (c.es_index_of(t, it.node) or { -1 }) in declarators) {
			continue
		}
		name := c.es_index_of(t, variable.defs[0].name) or { continue }
		findings << Finding{
			stmt:       c.es_tree_position(t, name)
			message_id: 'shadow'
			data:       {
				'name': variable.name
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_is_type_only_variable is the rule's isTypeOnlyVariable: no definition, a type that is not
// a value, or only type imports (`import type …`, `import { type … }`).
fn (mut c Checker) vue_is_type_only_variable(t &estree.EsTree, variable ScopeVariable) bool {
	if variable.defs.len == 0 || (variable.is_type_variable() && !variable.is_value_variable()) {
		return true
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
