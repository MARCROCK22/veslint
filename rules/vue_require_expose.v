module rules

import estree
import json2
import time

// Port of the `vue/require-expose` rule of eslint-plugin-vue 10.12.1 (no options): a Vue object
// (not a mixin) of a file without `<script setup>` that has no `expose` option, does not call
// `expose` in its setup function and whose setup does not return a render function, with
// suggestions to add `expose: []` or `expose` with every property.

const vue_require_expose_messages = {
	'requireExpose':           'The public properties of the component must be explicitly declared using `expose`. If the component does not have public properties, declare it empty.'
	'addExposeOptionForEmpty': 'Add the `expose` option to give an empty array.'
	'addExposeOptionForAll':   'Add the `expose` option to declare all properties.'
}

const vre_fix_expose_before_options = ['name', 'components', 'directives', 'extends', 'mixins',
	'provide', 'inject', 'inheritAttrs', 'props', 'emits']

fn (mut c Checker) lint_vue_require_expose(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	if s.has_setup || s.objects.len == 0 {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	mut order := []int{len: t.nodes.len, init: -1}
	mut next := 0
	for step in t.steps() {
		if !step.leave {
			order[step.node] = next
			next++
		}
	}
	// onSetupFunctionEnter: the expose references of each object, from the preorder index of its
	// setup function; and whether the setup returns a function.
	mut context_ids := map[int]map[u64]bool{}
	mut expose_ids := map[int]map[u64]bool{}
	mut from := map[int]int{}
	mut setup_render := map[int]bool{}
	for step in t.steps() {
		f := step.node
		if step.leave || s.vue_function_kind(t, f) != 'setup' {
			continue
		}
		owner := s.owner_of(f)
		if c.vre_returns_function(root, t, f) {
			setup_render[owner] = true
		}
		params := t.list(f, .params) or { []int{} }
		if params.len < 2 || t.typ(params[1]) in [.rest_element, .array_pattern] {
			continue
		}
		param := params[1]
		mut context_set := map[u64]bool{}
		mut expose_set := map[u64]bool{}
		if t.typ(param) == .object_pattern {
			property := vx6_find_assignment_property(t, param, 'expose')
			if property < 0 {
				continue
			}
			value := vue_property_value(t, property)
			if t.typ(value) != .identifier
				|| !c.vneaa_read_references(root, t, value, mut expose_set) {
				continue
			}
		} else if t.typ(param) == .identifier {
			if !c.vneaa_read_references(root, t, param, mut context_set) {
				continue
			}
		}
		context_ids[owner] = context_set.clone()
		expose_ids[owner] = expose_set.clone()
		from[owner] = order[f]
	}
	// CallExpression: a call of `expose` in the object after its setup function.
	mut called := map[int]bool{}
	if from.len > 0 {
		for step in t.steps() {
			call := step.node
			if step.leave || t.typ(call) != .call_expression {
				continue
			}
			owner := s.owner_of(call)
			if owner !in from || order[call] < from[owner] || owner in called {
				continue
			}
			callee := t.node(call, .callee) or { continue }
			if t.typ(callee) == .identifier && vneaa_key(t, callee) in expose_ids[owner] {
				called[owner] = true
				continue
			}
			member := vue_skip_chain(t, callee)
			if t.typ(member) == .member_expression
				&& (vue_static_property_name(t, member) or { '' }) == 'expose' {
				object := t.node(member, .object) or { continue }
				if t.typ(object) == .identifier && vneaa_key(t, object) in context_ids[owner] {
					called[owner] = true
				}
			}
		}
	}
	for obj in s.objects {
		stats.checked++
		if obj in called || obj in setup_render {
			continue
		}
		if s.object_type(obj) == .definition
			&& c.vue_component_definition_type(root, t, obj) == 'mixin' {
			continue
		}
		properties := t.list(obj, .properties) or { []int{} }
		if properties.any(t.typ(it) == .property && !(t.flag(it, .computed) or { false })
			&& (vue_static_property_name(t, it) or { '' }) == 'expose') {
			continue
		}
		findings << Finding{
			stmt:        c.es_tree_position(t, obj)
			message_id:  'requireExpose'
			suggestions: c.vre_suggestions(root, t, obj)!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vre_returns_function: the setup function's scope gets `returnFunction` (an arrow whose body is
// a function, or a `return` of a function directly in it).
fn (mut c Checker) vre_returns_function(root C.TSNode, t &estree.EsTree, f int) bool {
	if t.typ(f) == .arrow_function_expression && (t.flag(f, .expression) or { false }) {
		if c.vre_is_function(root, t, t.node(f, .body) or { -1 }, 0) {
			return true
		}
	}
	for step in t.steps() {
		if step.leave || t.typ(step.node) != .return_statement
			|| vaa_innermost_function(t, step.node) != f {
			continue
		}
		argument := t.node(step.node, .argument) or { continue }
		if c.vre_is_function(root, t, argument, 0) {
			return true
		}
	}
	return false
}

// vre_is_function is the rule's isFunction.
fn (mut c Checker) vre_is_function(root C.TSNode, t &estree.EsTree, node int, depth int) bool {
	if node < 0 || depth > 20 {
		return false
	}
	if t.typ(node) in [.arrow_function_expression, .function_expression] {
		return true
	}
	if t.typ(node) != .identifier {
		return false
	}
	v := c.unb_find_variable(root, t, node)
	if v < 0 {
		return false
	}
	tree := c.scope_tree(root)
	for def in tree.variables[v].defs {
		if def.kind == .function_name {
			return true
		}
		if def.kind == .variable {
			if init := def.init {
				es := c.es_index_of(t, unwrap_parens(init)) or { return false }
				return c.vre_is_function(root, t, es, depth + 1)
			}
		}
	}
	return false
}

// vre_suggestions is buildSuggest.
fn (mut c Checker) vre_suggestions(root C.TSNode, t &estree.EsTree, object int) ![]Suggestion {
	properties := t.list(object, .properties) or { []int{} }
	property_nodes := properties.filter(vue_is_property(t, it))
	mut before := -1
	for p in property_nodes {
		if (vue_static_property_name(t, p) or { '' }) in vre_fix_expose_before_options {
			before = p
			break
		}
	}
	all := vue_iterate_properties(t, object, ['props', 'data', 'computed', 'setup', 'methods',
		'watch'])
	build := fn [mut c, t, object, properties, property_nodes, before] (text string) ?Fix {
		if before >= 0 {
			return fix_insert_at(t.nodes[before].end, ',\n${text}')
		}
		if properties.len > 0 {
			after := if property_nodes.len > 0 { property_nodes[0] } else { properties[0] }
			ts := t.ts_node(after)?
			token := c.source_tokens(ts).before(t.nodes[after].start, false)?
			return fix_insert_at(token.end, '\n${text},')
		}
		left_end := t.nodes[object].start + 1
		right_start := t.nodes[object].end - 1
		between := c.src[left_end..right_start]
		multiline := between.contains('\n') || (!c.is_vue()
			&& (between.contains('\r') || between.contains(' ')
			|| between.contains(' ')))
		return fix_insert_at(left_end, '\n${text}${if multiline { '' } else { '\n' }}')
	}
	mut out := []Suggestion{}
	if fix := build('expose: []') {
		ok, suggestion := c.suggestion('addExposeOptionForEmpty', {}, [fix])!
		if ok {
			out << suggestion
		}
	}
	if all.len > 0 {
		names := all.map(js_json_stringify(json2.Any(it.name))).join(', ')
		if fix := build('expose: [${names}]') {
			ok, suggestion := c.suggestion('addExposeOptionForAll', {}, [fix])!
			if ok {
				out << suggestion
			}
		}
	}
	return out
}
