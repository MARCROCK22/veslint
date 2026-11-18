module rules

import estree
import time

// Port of the `vue/no-unused-refs` rule of eslint-plugin-vue 10.12.1 (no options): a `ref="name"`
// of the template whose name no `$refs.name` (or destructuring of `$refs`) of the template or the
// script uses, nor `useTemplateRef('name')`, a `setup` name of a Vue object or (with
// `<script setup>`) a variable of the global or module scope; nothing at all once `$refs` is used
// in a way that does not tell which refs (passed, returned, assigned whole, iterated, a dynamic
// property).

const vue_no_unused_refs_messages = {
	'unused': "'{{name}}' is defined as ref, but never used."
}

// VnurUses are the refs used, and whether some use cannot tell which (hasUnknown).
struct VnurUses {
mut:
	used    map[string]bool
	unknown bool
}

fn (mut c Checker) lint_vue_no_unused_refs(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut uses := VnurUses{}
	if s := c.vue_script(root, abs_path) {
		t := c.es_tree(root, abs_path) or { return findings }
		if s.has_setup {
			tree := c.scope_tree(root)
			for v in tree.scopes[0].variables {
				if tree.variables[v].defs.len > 0 {
					uses.used[tree.variables[v].name] = true
				}
			}
			module := vue_module_scope(tree)
			if module >= 0 {
				for v in tree.scopes[module].variables {
					if tree.variables[v].defs.len > 0 {
						uses.used[tree.variables[v].name] = true
					}
				}
			}
		}
		for object in s.objects_of(vue_all_object_types) {
			for p in vue_iterate_properties(t, object, ['setup']) {
				uses.used[p.name] = true
			}
		}
		for node in 0 .. t.nodes.len {
			if t.typ(node) == .identifier && (t.string_of(node, .name) or { '' }) == r'$refs' {
				parent := t.nodes[node].parent
				refs := if parent >= 0 && t.typ(parent) == .member_expression
					&& (t.node(parent, .property) or { -1 }) == node {
					parent
				} else {
					node
				}
				vnur_extract(t, refs, vnur_es_parent, mut uses)
			} else if t.typ(node) == .call_expression {
				args := t.list(node, .arguments) or { continue }
				if args.len == 0 || !vue_is_string_literal(t, args[0])
					|| vue_callee_name(t, node) != 'useTemplateRef' {
					continue
				}
				if name := vue_string_literal_value(t, args[0], false) {
					uses.used[name] = true
				}
			}
		}
	}
	if uses.unknown {
		return findings
	}
	doc := c.vue.doc
	roots := c.vue_template_roots()
	mut defined := []int{}
	for v in c.vue_template_vnodes() {
		node := &doc.nodes[v]
		if node.typ == .v_expression_container {
			for r in node.references {
				reference := &doc.references[r]
				if reference.variable >= 0 || reference.name != r'$refs'
					|| reference.id.kind != .estree {
					continue
				}
				vnur_extract(&doc.snippets[reference.id.snippet].es, reference.id.node, fn [roots, reference] (es &estree.EsTree, node int) int {
					return roots.parent(es, reference.id.snippet, node)
				}, mut uses)
			}
		} else if node.typ == .v_attribute && !node.directive && doc.nodes[node.key].name == 'ref'
			&& node.value >= 0 {
			defined << node.value
		}
	}
	if uses.unknown {
		return findings
	}
	for literal in defined {
		stats.checked++
		name := doc.nodes[literal].text
		if name in uses.used {
			continue
		}
		findings << c.vue_report_vnode(literal, 'unused', {
			'name': name
		})
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnur_extract is extractUsedForPattern: what the parent of `$refs` (or of `this.$refs`, through
// chain expressions) does with it.
fn vnur_extract(t &estree.EsTree, refs int, parent_of fn (&estree.EsTree, int) int, mut uses VnurUses) {
	mut node := refs
	for parent_of(t, node) >= 0 && t.typ(parent_of(t, node)) == .chain_expression {
		node = parent_of(t, node)
	}
	parent := parent_of(t, node)
	if parent < 0 {
		return
	}
	match t.typ(parent) {
		.assignment_expression {
			if (t.node(parent, .right) or { -1 }) == node {
				left := t.node(parent, .left) or { return }
				if t.typ(left) == .object_pattern {
					vnur_extract_object_pattern(t, left, mut uses)
				} else if t.typ(left) == .identifier {
					uses.unknown = true
				}
			}
		}
		.variable_declarator {
			if (t.node(parent, .init) or { -1 }) == node {
				id := t.node(parent, .id) or { return }
				if t.typ(id) == .object_pattern {
					vnur_extract_object_pattern(t, id, mut uses)
				} else if t.typ(id) == .identifier {
					uses.unknown = true
				}
			}
		}
		.member_expression {
			if (t.node(parent, .object) or { -1 }) == node {
				if name := vue_static_property_name(t, parent) {
					if name != '' {
						uses.used[name] = true
						return
					}
				}
				uses.unknown = true
			}
		}
		.call_expression {
			if node in (t.list(parent, .arguments) or { []int{} }) {
				uses.unknown = true
			}
		}
		.for_in_statement, .return_statement {
			uses.unknown = true
		}
		else {}
	}
}

// vnur_extract_object_pattern is extractUsedForObjectPattern.
fn vnur_extract_object_pattern(t &estree.EsTree, pattern int, mut uses VnurUses) {
	for p in t.list(pattern, .properties) or { []int{} } {
		if t.typ(p) != .property {
			uses.unknown = true
			return
		}
		name := vue_static_property_name(t, p) or { '' }
		if name == '' {
			uses.unknown = true
			return
		}
		uses.used[name] = true
	}
}

// vnur_es_parent is the parent of a node of the script.
fn vnur_es_parent(t &estree.EsTree, node int) int {
	return t.nodes[node].parent
}
