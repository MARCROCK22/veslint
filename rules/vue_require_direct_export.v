module rules

import estree
import json2
import time

// Port of the `vue/require-direct-export` rule of eslint-plugin-vue 10.12.1 (option
// `disallowFunctionalComponentFunction`): in a Vue file (.vue, .jsx, .tsx), an `export default`
// of something else than an object literal, `defineComponent({…})` or `Vue.extend({…})`; a
// function that returns something (a Vue 3 functional component) is allowed, unless the option
// says so.

const vue_require_direct_export_messages = {
	'expectedDirectExport': 'Expected the component literal to be directly exported.'
}

fn vue_require_direct_export_options(options []json2.Any) !bool {
	o := option_object(vue_require_direct_export, options, ['disallowFunctionalComponentFunction'])!
	value := o.values['disallowFunctionalComponentFunction'] or { return false }
	return value is bool && value
}

fn (mut c Checker) lint_vue_require_direct_export(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	disallow_functional := vue_require_direct_export_options(c.rule_options(vue_require_direct_export))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	if !s.is_vue_file {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	for statement in t.list(t.root, .body) or { []int{} } {
		if t.typ(statement) != .export_default_declaration {
			continue
		}
		stats.checked++
		node := t.node(statement, .declaration) or { continue }
		if t.typ(node) == .object_expression || vrde_is_component_call(t, node) {
			continue
		}
		is_function := t.typ(node) in [.function_expression, .function_declaration,
			.arrow_function_expression]
		if !disallow_functional && is_function {
			body := t.node(node, .body) or { -1 }
			// An arrow function with an expression body is allowed; another function must return
			// something ('ExportDefaultDeclaration:exit').
			if body < 0 || t.typ(body) != .block_statement || vrde_has_return_argument(t, node) {
				continue
			}
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, statement)
			message_id: 'expectedDirectExport'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vrde_is_component_call: `defineComponent({…})` or `Vue.extend({…})`.
fn vrde_is_component_call(t &estree.EsTree, node int) bool {
	if t.typ(node) != .call_expression {
		return false
	}
	args := t.list(node, .arguments) or { []int{} }
	if args.len == 0 || t.typ(args[0]) != .object_expression {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	if t.typ(callee) == .identifier {
		return (t.string_of(callee, .name) or { '' }) == 'defineComponent'
	}
	if t.typ(callee) == .member_expression {
		object := t.node(callee, .object) or { return false }
		property := t.node(callee, .property) or { return false }
		return t.typ(object) == .identifier && (t.string_of(object, .name) or { '' }) == 'Vue'
			&& t.typ(property) == .identifier && (t.string_of(property, .name) or { '' }) == 'extend'
	}
	return false
}

// vrde_has_return_argument: a `return` with an argument whose function is `function` (the
// ReturnStatement listener while the innermost `:function > BlockStatement` is its body).
fn vrde_has_return_argument(t &estree.EsTree, function int) bool {
	start := t.nodes[function].start
	end := t.nodes[function].end
	for i in 0 .. t.nodes.len {
		if t.typ(i) != .return_statement || t.nodes[i].start < start || t.nodes[i].end > end {
			continue
		}
		_ := t.node(i, .argument) or { continue }
		mut p := t.nodes[i].parent
		for p >= 0 && t.typ(p) !in [.function_expression, .function_declaration,
			.arrow_function_expression] {
			p = t.nodes[p].parent
		}
		if p == function {
			return true
		}
	}
	return false
}
