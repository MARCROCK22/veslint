module rules

import estree
import time

// Port of the `vue/require-typed-ref` rule of eslint-plugin-vue 10.12.1 (no options): a `ref()`
// or `shallowRef()` of the composition API without a type argument and without a value (or with
// null or undefined), outside a typed position, in a .ts or .mts file or a .vue file with a
// `lang="ts"` script.

const vue_require_typed_ref_messages = {
	'noType': 'Specify type parameter for `{{name}}` function, otherwise created variable will not be typechecked.'
}

fn (mut c Checker) lint_vue_require_typed_ref(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	filename := s.filename
	is_vue_file := filename.ends_with('.vue') || filename.ends_with('.jsx')
		|| filename.ends_with('.tsx')
	is_ts_file := filename.ends_with('.ts') || filename.ends_with('.tsx')
		|| filename.ends_with('.mts')
	if !is_vue_file && !is_ts_file {
		return findings
	}
	if is_vue_file {
		// A .jsx or .tsx file has no document fragment.
		if !c.is_vue() {
			return findings
		}
		scripts := c.vue.doc.top_elements('script')
		if scripts.all(!c.vue_has_attribute(it, 'lang', 'ts')) {
			return findings
		}
	}
	t := c.es_tree(root, abs_path) or { return findings }
	for d in c.vue_composition_api_calls(root, t, vx6r_define_names) {
		if d.name !in ['ref', 'shallowRef'] {
			continue
		}
		stats.checked++
		args := t.list(d.call, .arguments) or { []int{} }
		if args.len > 0 && !vrtr_is_null_or_undefined(t, args[0]) {
			continue
		}
		if (t.node(d.call, .type_arguments) or { -1 }) >= 0 {
			continue
		}
		if !c.vrtr_is_in_typed_position(root, t, d.call) {
			findings << Finding{
				stmt:       c.es_tree_position(t, d.call)
				message_id: 'noType'
				data:       {
					'name': d.name
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn vrtr_is_null_or_undefined(t &estree.EsTree, node int) bool {
	if t.typ(node) == .literal {
		return t.get(node, .value) is estree.Null
	}
	return t.typ(node) == .identifier && (t.string_of(node, .name) or { '' }) == 'undefined'
}

// vrtr_has_type_annotation is hasTypeAnnotation.
fn vrtr_has_type_annotation(t &estree.EsTree, node int) bool {
	if node < 0 {
		return false
	}
	if t.typ(node) == .assignment_pattern {
		return vrtr_has_type_annotation(t, t.node(node, .left) or { -1 })
	}
	return (t.node(node, .type_annotation) or { -1 }) >= 0
}

// vrtr_definition is findDefinition: the only definition of the identifier's variable.
fn (mut c Checker) vrtr_definition(root C.TSNode, t &estree.EsTree, id int) ?ScopeDefinition {
	v := c.unb_find_variable(root, t, id)
	if v < 0 {
		return none
	}
	tree := c.scope_tree(root)
	defs := tree.variables[v].defs
	return if defs.len == 1 { defs[0] } else { none }
}

// vrtr_find_function is the rule's findFunction.
fn (mut c Checker) vrtr_find_function(root C.TSNode, t &estree.EsTree, id int) int {
	def := c.vrtr_definition(root, t, id) or { return -1 }
	if def.kind == .function_name {
		return c.es_index_of(t, def.node) or { -1 }
	}
	if def.kind != .variable {
		return -1
	}
	init := def.init or { return -1 }
	es := c.es_index_of(t, unwrap_parens(init)) or { return -1 }
	return if t.typ(es) in [.arrow_function_expression, .function_expression] { es } else { -1 }
}

// vrtr_is_in_typed_position is isInTypedPosition.
fn (mut c Checker) vrtr_is_in_typed_position(root C.TSNode, t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	match t.typ(parent) {
		.ts_as_expression, .ts_satisfies_expression, .ts_type_assertion {
			return true
		}
		.variable_declarator {
			return (t.node(parent, .init) or { -1 }) == node
				&& vrtr_has_type_annotation(t, t.node(parent, .id) or { -1 })
		}
		.assignment_pattern {
			return (t.node(parent, .right) or { -1 }) == node
				&& vrtr_has_type_annotation(t, t.node(parent, .left) or { -1 })
		}
		.assignment_expression {
			left := t.node(parent, .left) or { return false }
			if (t.string_of(parent, .operator) or { '' }) != '=' || t.typ(left) != .identifier {
				return false
			}
			def := c.vrtr_definition(root, t, left) or { return false }
			if def.kind !in [.variable, .parameter] {
				return false
			}
			name := c.es_index_of(t, def.name) or { return false }
			return vrtr_has_type_annotation(t, name)
		}
		.call_expression {
			args := t.list(parent, .arguments) or { []int{} }
			index := args.index(node)
			callee := t.node(parent, .callee) or { return false }
			if index < 0 || t.typ(callee) != .identifier {
				return false
			}
			function := c.vrtr_find_function(root, t, callee)
			if function < 0 {
				return false
			}
			params := t.list(function, .params) or { []int{} }
			if index < params.len {
				return vrtr_has_type_annotation(t, params[index])
			}
			return params.len > 0 && t.typ(params.last()) == .rest_element
				&& vrtr_has_type_annotation(t, params.last())
		}
		else {
			return false
		}
	}
}
