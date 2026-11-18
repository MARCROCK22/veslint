module rules

import estree
import json2
import time
import treesitter { node_end, node_start }

// Port of the `vue/no-dupe-keys` rule of eslint-plugin-vue 10.12.1 (option `groups`): a name that
// two groups of a Vue object define, and in `<script setup>` a prop or model whose name a
// top-level declaration also uses (unless it is the destructured or aliased prop itself).

const vue_no_dupe_keys_messages = {
	'duplicateKey': "Duplicate key '{{name}}'. May cause name collision in script or template tag."
}

const vndk_group_names = ['props', 'computed', 'data', 'methods', 'setup']

fn vue_no_dupe_keys_options(options []json2.Any) ![]string {
	o := option_object(vue_no_dupe_keys, options, ['groups'])!
	mut groups := vndk_group_names.clone()
	value := o.values['groups'] or { return groups }
	if value !is []json2.Any {
		return error('`groups` of `${vue_no_dupe_keys}` must be a list')
	}
	for item in value as []json2.Any {
		if item !is string {
			return error('`groups` of `${vue_no_dupe_keys}` must be strings')
		}
		if (item as string) !in groups {
			groups << item as string
		}
	}
	return groups
}

fn (mut c Checker) lint_vue_no_dupe_keys(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	groups := vue_no_dupe_keys_options(c.rule_options(vue_no_dupe_keys))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for obj in s.objects {
		mut used := map[string]bool{}
		for o in vue_iterate_properties(t, obj, groups) {
			stats.checked++
			if o.name in used {
				findings << Finding{
					stmt:       c.es_tree_position(t, o.node)
					message_id: 'duplicateKey'
					data:       {
						'name': o.name
					}
				}
			}
			used[o.name] = true
		}
	}
	if !s.has_setup {
		stats.eval_ms += ms(sw.elapsed())
		return findings
	}
	tree := c.scope_tree(root)
	mut prop_refs := []int{}
	mut prop_names := []string{}
	mut reported := map[int]bool{} // ESTree nodes of the reported definitions
	for call in c.vue_macros_named(t, 'defineProps') {
		pattern := vndk_props_pattern(t, call)
		prop_refs = if pattern >= 0 { c.vndk_extract_references(root, t, pattern) } else { []int{} }
		prop_refs << call
		renamed := vndk_renamed_props(t, pattern)
		for prop in c.vue_define_props(root, t, call, abs_path, true, mut stats) {
			stats.checked++
			if !prop.has_name || prop.name == '' {
				continue
			}
			if prop.name !in prop_names {
				prop_names << prop.name
			}
			if prop.name in renamed {
				continue
			}
			v := c.vndk_find_variable_by_name(root, t, call, prop.name)
			if v < 0 || tree.variables[v].defs.len == 0 {
				continue
			}
			defs := tree.variables[v].defs
			mut skip := false
			for def in defs {
				if def.kind != .variable {
					continue
				}
				declarator := c.vx6r_es_node(t, def.node, 'variable_declarator')
				if declarator >= 0 && !vndk_aliases_other_prop(t, declarator, prop.name, prop_refs)
					&& vndk_is_inside_initializer(t, declarator, prop_refs) {
					skip = true
					break
				}
			}
			if skip {
				continue
			}
			reported[c.vndk_def_node(t, defs[0])] = true
			findings << c.vndk_report_def(t, defs[0], prop.name)
		}
	}
	// Program:exit: the models.
	mut used := map[string]bool{}
	for name in prop_names {
		used[name] = true
	}
	for call in c.vue_macros_named(t, 'defineModel') {
		model := vue_define_model(t, call)
		name := model.name
		if name in used {
			if t.nodes[call].parent in reported {
				continue
			}
			findings << Finding{
				stmt:       c.es_tree_position(t, if model.name_node >= 0 {
					model.name_node
				} else {
					call
				})
				message_id: 'duplicateKey'
				data:       {
					'name': name
				}
			}
			continue
		}
		used[name] = true
		v := c.vndk_find_variable_by_name(root, t, call, name)
		if v < 0 || tree.variables[v].defs.len == 0 {
			continue
		}
		pattern := vndk_props_pattern(t, call)
		mut refs := prop_refs.clone()
		if pattern >= 0 {
			refs << c.vndk_extract_references(root, t, pattern)
		}
		refs << call
		defs := tree.variables[v].defs
		mut skip := false
		for def in defs {
			if def.kind != .variable {
				continue
			}
			declarator := c.vx6r_es_node(t, def.node, 'variable_declarator')
			if declarator >= 0 && vndk_is_inside_initializer(t, declarator, refs) {
				skip = true
				break
			}
		}
		if !skip {
			findings << c.vndk_report_def(t, defs[0], name)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vndk_report_def reports a definition's node (`variable.defs[0].node`).
fn (mut c Checker) vndk_report_def(t &estree.EsTree, def ScopeDefinition, name string) Finding {
	node := c.vndk_def_node(t, def)
	stmt := if node >= 0 {
		c.es_tree_position(t, node)
	} else {
		c.position_range(node_start(def.node), node_end(def.node))
	}
	return Finding{
		stmt:       stmt
		message_id: 'duplicateKey'
		data:       {
			'name': name
		}
	}
}

// vndk_find_variable_by_name is findVariable(getScope(node), name).
fn (mut c Checker) vndk_find_variable_by_name(root C.TSNode, t &estree.EsTree, node int, name string) int {
	ts := t.ts_node(node) or { return -1 }
	tree := c.scope_tree(root)
	return tree.find_variable(tree.get_scope(ts), name, t.nodes[node].start)
}

// vndk_props_pattern is getPropsPattern.
fn vndk_props_pattern(t &estree.EsTree, call int) int {
	mut target := call
	if vue_has_with_defaults(t, target) {
		target = t.nodes[target].parent
	}
	parent := t.nodes[target].parent
	if parent >= 0 && t.typ(parent) == .variable_declarator
		&& (t.node(parent, .init) or { -1 }) == target {
		return t.node(parent, .id) or { -1 }
	}
	return -1
}

// vndk_extract_references is extractReferences.
fn (mut c Checker) vndk_extract_references(root C.TSNode, t &estree.EsTree, node int) []int {
	if node < 0 {
		return []
	}
	match t.typ(node) {
		.identifier {
			v := c.unb_find_variable(root, t, node)
			if v < 0 {
				return []
			}
			tree := c.scope_tree(root)
			mut out := []int{}
			for r in tree.variables[v].references {
				out << c.es_index_of(t, tree.references[r].identifier) or { continue }
			}
			return out
		}
		.object_pattern {
			mut out := []int{}
			for p in t.list(node, .properties) or { []int{} } {
				out << c.vndk_extract_references(root, t, if t.typ(p) == .property {
					t.node(p, .value) or { -1 }
				} else {
					p
				})
			}
			return out
		}
		.assignment_pattern {
			return c.vndk_extract_references(root, t, t.node(node, .left) or { -1 })
		}
		.rest_element {
			return c.vndk_extract_references(root, t, t.node(node, .argument) or { -1 })
		}
		else {
			return []
		}
	}
}

// vndk_renamed_props is collectRenamedProps.
fn vndk_renamed_props(t &estree.EsTree, pattern int) []string {
	mut out := []string{}
	if pattern < 0 || t.typ(pattern) != .object_pattern {
		return out
	}
	for p in t.list(pattern, .properties) or { []int{} } {
		if t.typ(p) != .property {
			continue
		}
		key := t.node(p, .key) or { continue }
		value := t.node(p, .value) or { continue }
		if t.typ(key) == .identifier && t.typ(value) == .identifier {
			k := t.string_of(key, .name) or { '' }
			if k != (t.string_of(value, .name) or { '' }) {
				out << k
			}
		}
	}
	return out
}

// vndk_is_inside_initializer is isInsideInitializer.
fn vndk_is_inside_initializer(t &estree.EsTree, declarator int, refs []int) bool {
	init := t.node(declarator, .init) or { return false }
	return refs.any(vx6_is_in_range(t, init, it))
}

// vndk_aliased_prop_name is getAliasedPropName ('' for null).
fn vndk_aliased_prop_name(t &estree.EsTree, node int, refs []int) ?string {
	expression := vue_skip_chain(t, vue_skip_ts_as(t, node))
	if t.typ(expression) == .member_expression {
		object := vue_skip_ts_as(t, t.node(expression, .object) or { return none })
		return if object in refs { vue_static_property_name(t, expression) } else { none }
	}
	if t.typ(expression) == .call_expression {
		callee := t.node(expression, .callee) or { return none }
		args := t.list(expression, .arguments) or { []int{} }
		if t.typ(callee) == .identifier && (t.string_of(callee, .name) or { '' }) == 'toRef'
			&& args.len > 0 && args[0] in refs {
			if args.len > 1 && t.typ(args[1]) == .literal {
				value := t.get(args[1], .value)
				if value is string {
					return value
				}
			}
			return none
		}
	}
	return none
}

// vndk_is_props_object is isPropsObject.
fn vndk_is_props_object(t &estree.EsTree, node int, refs []int) bool {
	if node in refs {
		return true
	}
	if t.typ(node) != .call_expression {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	args := t.list(node, .arguments) or { []int{} }
	return t.typ(callee) == .identifier && (t.string_of(callee, .name) or { '' }) == 'toRefs'
		&& args.len > 0 && args[0] in refs
}

// vndk_aliases_other_prop is aliasesOtherProp.
fn vndk_aliases_other_prop(t &estree.EsTree, declarator int, name string, refs []int) bool {
	init := t.node(declarator, .init) or { return false }
	id := t.node(declarator, .id) or { return false }
	if t.typ(id) == .identifier && (t.string_of(id, .name) or { '' }) == name {
		aliased := vndk_aliased_prop_name(t, init, refs) or { return false }
		return aliased != name
	}
	if t.typ(id) == .object_pattern && vndk_is_props_object(t, init, refs) {
		for p in t.list(id, .properties) or { []int{} } {
			if t.typ(p) != .property {
				continue
			}
			mut value := t.node(p, .value) or { continue }
			if t.typ(value) == .assignment_pattern {
				value = t.node(value, .left) or { continue }
			}
			if t.typ(value) != .identifier || (t.string_of(value, .name) or { '' }) != name {
				continue
			}
			key := vue_static_property_name(t, p) or { return false }
			return key != name
		}
	}
	return false
}

// vndk_def_node is the ESTree node of `def.node` (-1 for none): the VariableDeclarator of a
// variable, the specifier of an import.
fn (mut c Checker) vndk_def_node(t &estree.EsTree, def ScopeDefinition) int {
	if def.kind == .variable {
		return c.vx6r_es_node(t, def.node, 'variable_declarator')
	}
	if def.kind == .import_binding {
		id := c.es_index_of(t, def.name) or { return -1 }
		return t.nodes[id].parent
	}
	return c.es_index_of(t, def.node) or { -1 }
}
