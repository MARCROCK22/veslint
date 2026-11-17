module rules

import vue

// What vue-eslint-parser adds to the scopes of a .vue file with a <script setup>
// (analyzeScriptSetupScope of src/script-setup/scope-analyzer.ts), before ESLint adds the globals
// of the configuration: the variables of the script the template uses get a reference (and count
// as used), and the compiler macros (`defineProps`…) and the names of the `generic` resolve to
// variables of the global scope.

const vue_compiler_macros = ['defineProps', 'defineEmits', 'defineExpose', 'withDefaults',
	'defineOptions', 'defineSlots', 'defineModel']

// VueScopeSetup is what the scope tree needs of the document.
pub struct VueScopeSetup {
pub:
	script_setup bool
	uses         []vue.TemplateUse
	generic      []string
}

fn vue_scope_setup(doc &vue.Document) VueScopeSetup {
	return VueScopeSetup{
		script_setup: true
		uses:         doc.template_uses()
		generic:      doc.script_setup_generic_names()
	}
}

// vue_script_setup_scope ports analyzeUsedInTemplateVariables and analyzeScriptSetupVariables.
fn (mut b ScopeBuilder) vue_script_setup_scope(setup VueScopeSetup) {
	// The variables of the global scope and of the module scope (which wins for a name).
	mut variables := map[string]int{}
	for v in b.tree.scopes[0].variables {
		variables[b.tree.variables[v].name] = v
	}
	for child in b.tree.scopes[0].children {
		if b.tree.scopes[child].kind == .esmodule {
			for v in b.tree.scopes[child].variables {
				variables[b.tree.variables[v].name] = v
			}
			break
		}
	}
	mut marked := map[string]bool{}
	for use in setup.uses {
		match use.kind {
			.exact {
				b.vue_mark_used(variables, mut marked, use.name, use)
			}
			.component, .element {
				if !b.vue_mark_component(variables, mut marked, use.name) && use.kind == .element {
					dot := use.name.index('.') or { -1 }
					if dot > 0 {
						b.vue_mark_component(variables, mut marked, use.name[..dot])
					}
				}
			}
		}
	}
	mut through := []int{cap: b.tree.through.len}
	for r in b.tree.through {
		ref := b.tree.references[r]
		from_kind := b.tree.scopes[ref.from].kind
		if (ref.name in vue_compiler_macros && from_kind in [.global, .esmodule])
			|| ref.name in setup.generic {
			v := b.define_variable(0, ref.name)
			b.tree.references[r].resolved = v
			b.tree.variables[v].references << r
			continue
		}
		through << r
	}
	if through.len != b.tree.through.len {
		removed := b.tree.through.filter(it !in through)
		b.tree.through = through
		b.tree.scopes[0].through = b.tree.scopes[0].through.filter(it !in removed)
	}
}

// vue_mark_component is markSetupReferenceVariableAsUsed: the name, its camelCase or its
// PascalCase, the first that is a variable of the script.
fn (mut b ScopeBuilder) vue_mark_component(variables map[string]int, mut marked map[string]bool, name string) bool {
	camel := vue.camelized(name)
	first := camel.runes()
	pascal := if first.len > 0 {
		first[0].str().to_upper() + camel[first[0].length_in_bytes()..]
	} else {
		camel
	}
	for candidate in [name, camel, pascal] {
		if candidate in variables {
			b.vue_mark_used(variables, mut marked, candidate, vue.TemplateUse{})
			return true
		}
	}
	return false
}

// vue_mark_used is markVariableAsUsed: once per name, a variable with a definition gets a
// read-only reference from its own scope at its first name, and counts as used.
fn (mut b ScopeBuilder) vue_mark_used(variables map[string]int, mut marked map[string]bool, name string, use vue.TemplateUse) {
	v := variables[name] or { return }
	if b.tree.variables[v].identifiers.len == 0 || name in marked {
		return
	}
	marked[name] = true
	r := b.tree.references.len
	b.tree.references << ScopeReference{
		identifier: b.tree.variables[v].identifiers[0]
		name:       name
		from:       b.tree.variables[v].scope
		read:       true
		type_ref:   use.has_kind && use.is_type_reference
		value_ref:  use.has_kind && use.is_value_reference
		resolved:   v
	}
	b.tree.variables[v].references << r
	b.tree.variables[v].eslint_used = true
}
