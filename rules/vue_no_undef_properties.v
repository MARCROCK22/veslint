module rules

import estree
import json2
import time

// Port of the `vue/no-undef-properties` rule of eslint-plugin-vue 10.12.1 (option ignores,
// default ['/^\$/']): a property the component or its template reads (through `this`, the
// parameters of `data`, computed properties, setup and render, the props variable of
// defineProps, the watchers and exposes, the template's expressions and the `v-bind()` of the
// styles; vue_property_references.v) that the component does not define (its props, data, async
// data, computed properties, methods, setup's returned object and its `...toRefs(reactive({…}))`,
// inject; with `<script setup>` the variables of the global and module scopes, the props of
// defineProps and the models of defineModel). Each name and each node is reported once per
// component, in the order ESLint's listeners meet them. Only a .vue file is linted (a
// defineTemplateBodyVisitor rule).

const vue_no_undef_properties_messages = {
	'undef':      "'{{name}}' is not defined."
	'undefProps': "'{{name}}' is not defined in props."
}

// vnudp_reserved is vue-reserved.json.
const vnudp_reserved = [r'$data', r'$props', r'$el', r'$options', r'$parent', r'$root', r'$children',
	r'$slots', r'$scopedSlots', r'$refs', r'$isServer', r'$attrs', r'$listeners', r'$watch', r'$set',
	r'$delete', r'$on', r'$once', r'$off', r'$emit', r'$mount', r'$forceUpdate', r'$nextTick',
	r'$destroy']

const vnudp_define_groups = ['props', 'asyncData', 'data', 'computed', 'setup', 'methods', 'inject']

fn vnudp_options(options []json2.Any) !VueRegexpGroup {
	o := option_object(vue_no_undef_properties, options, ['ignores'])!
	ignores := if 'ignores' in o.values { o.string_list('ignores')! } else { [r'/^\$/'] }
	return vue_regexp_group(ignores)!
}

// VnudpData is a PropertyData: `object` is the ObjectExpression whose properties `get` looks
// up (-1 when it has none).
struct VnudpData {
	has_nest bool
	is_props bool
	object   int = -1
}

// VnudpContext is a VueComponentContext.
struct VnudpContext {
mut:
	defs           map[string]VnudpData
	reported_nodes map[u64]bool
	reported_names map[string]bool
	has_unknown    bool
}

struct VnudpState {
	ignores VueRegexpGroup
mut:
	x        VprExtractor
	contexts map[int]VnudpContext // by the Vue object, -1 for the Program
	order    []int
	helpers  map[string]bool // propertiesDefinedByStoreHelpers
	reactive map[int]bool
	to_refs  map[int]bool
	built    bool
	findings []Finding
}

fn (mut st VnudpState) context(node int) &VnudpContext {
	if node !in st.contexts {
		st.contexts[node] = VnudpContext{}
		st.order << node
	}
	return unsafe { &st.contexts[node] }
}

fn (mut c Checker) lint_vue_no_undef_properties(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []Finding{}
	}
	sw := time.new_stopwatch()
	ignores := vnudp_options(c.rule_options(vue_no_undef_properties))!
	s := c.vue_script(root, abs_path) or { return []Finding{} }
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut st := VnudpState{
		ignores: ignores
		x:       c.vpr_new_extractor(root, t, false, false)
	}
	// Program: with `<script setup>`, the variables of the global and module scopes are defined.
	if s.has_setup {
		tree := c.scope_tree(root)
		mut ctx := st.context(-1)
		for v in tree.scopes[0].variables {
			ctx.defs[tree.variables[v].name] = VnudpData{}
		}
		module := vue_module_scope(tree)
		if module >= 0 {
			for v in tree.scopes[module].variables {
				ctx.defs[tree.variables[v].name] = VnudpData{}
			}
		}
	}
	mut define_props := map[int]bool{}
	for call in c.vue_macros_named(t, 'defineProps') {
		define_props[call] = true
	}
	mut define_models := map[int]bool{}
	for call in c.vue_macros_named(t, 'defineModel') {
		define_models[call] = true
	}
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		if node in define_props {
			c.vnudp_define_props(root, t, node, abs_path, mut st, mut stats)
		}
		if node in define_models {
			model := vue_define_model(t, node)
			st.context(-1).defs[model.name] = VnudpData{
				is_props: true
			}
		}
		owner := s.owner_of(node)
		if owner < 0 {
			continue
		}
		typ := t.typ(node)
		if owner == node {
			c.vnudp_object_enter(root, t, node, mut st)
		}
		if typ == .call_expression {
			vnudp_add_store_helper(t, node, mut st)
		}
		if typ in [.function_expression, .arrow_function_expression] {
			if is_props := vnudp_option_function(t, node, owner) {
				refs := c.vpr_from_function_param(mut st.x, node, 0)
				c.vnudp_verify(t, owner, refs, is_props, mut st)
			}
			kind := s.vue_function_kind(t, node)
			if kind == 'setup' {
				refs := c.vpr_from_function_param(mut st.x, node, 0)
				c.vnudp_verify(t, owner, refs, true, mut st)
			} else if kind == 'render' {
				refs := c.vpr_from_function_param(mut st.x, node, 0)
				c.vnudp_verify(t, owner, refs, false, mut st)
				if vnup_is_functional(t, owner) {
					v2 := c.vpr_from_function_param(mut st.x, node, 1)
					nest := c.vpr_get_nest(mut st.x, v2, 'props')
					c.vnudp_verify(t, owner, nest, true, mut st)
				}
			}
		}
		if typ in [.this_expression, .identifier] && c.vue_is_this(root, t, node) {
			stats.checked++
			refs := c.vpr_from_expression(mut st.x, VprNode{0, node}, false)
			c.vnudp_verify(t, owner, refs, false, mut st)
		}
	}
	// Program:exit: the styles' `v-bind()`, and the template's expressions. vue-eslint-parser walks
	// the template in the Program:exit of the first rule that asks for it (vue_template_owner_of):
	// after this rule's own when it is this one, before it when another rule comes first.
	template_ctx := vnudp_template_context(t, st)
	if template_ctx != -2 {
		template_first := c.vue_template_owner != vue_no_undef_properties
		if template_first {
			c.vnudp_verify_template(t, template_ctx, mut st, mut stats)
		}
		if style := c.vpr_from_style_variables(mut st.x) {
			c.vnudp_verify(t, template_ctx, style, false, mut st)
		}
		if !template_first {
			c.vnudp_verify_template(t, template_ctx, mut st, mut stats)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return st.findings
}

// vnudp_verify_template is the template's listener: the expressions of the template.
fn (mut c Checker) vnudp_verify_template(t &estree.EsTree, template_ctx int, mut st VnudpState, mut stats Stats) {
	if !c.vue_has_template() {
		return
	}
	for v in c.vue_template_vnodes() {
		if c.vue.doc.nodes[v].typ == .v_expression_container {
			stats.checked++
			refs := c.vpr_from_container(mut st.x, v, true)
			c.vnudp_verify(t, template_ctx, refs, false, mut st)
		}
	}
}

// vnudp_template_context is getVueComponentContextForTemplate: the Program's context, or the
// first one of a Vue object in the default export; -2 for none.
fn vnudp_template_context(t &estree.EsTree, st &VnudpState) int {
	if -1 in st.contexts {
		return -1
	}
	for key in st.order {
		if key >= 0 && vucp_is_in_export_default(t, key) {
			return key
		}
	}
	return -2
}

// vnudp_define_props is onDefinePropsEnter.
fn (mut c Checker) vnudp_define_props(root C.vt_node, t &estree.EsTree, call int, abs_path string, mut st VnudpState, mut stats Stats) {
	for prop in c.vue_define_props(root, t, call, abs_path, true, mut stats) {
		if prop.kind == .unknown {
			st.context(-1).has_unknown = true
			return
		}
		if !prop.has_name || prop.name == '' {
			continue
		}
		st.context(-1).defs[prop.name] = VnudpData{
			is_props: true
		}
	}
	pattern := vue_left_of_define_props(t, call)
	if pattern < 0 {
		return
	}
	refs := c.vpr_from_pattern(mut st.x, pattern)
	c.vnudp_verify(t, -1, refs, false, mut st)
}

// vnudp_object_enter is onVueObjectEnter.
fn (mut c Checker) vnudp_object_enter(root C.vt_node, t &estree.EsTree, object int, mut st VnudpState) {
	st.context(object)
	// Collect store helpers before any reference is verified.
	for group_name in ['computed', 'methods'] {
		group := vue_find_property(t, object, group_name, none)
		if group < 0 {
			continue
		}
		value := vue_property_value(t, group)
		mut values := []int{}
		if t.typ(value) == .object_expression {
			for p in t.list(value, .properties) or { []int{} } {
				values << if t.typ(p) == .spread_element {
					t.node(p, .argument) or { -1 }
				} else {
					-1
				}
			}
		} else {
			values << value
		}
		for v in values {
			if v >= 0 && t.typ(v) == .call_expression {
				vnudp_add_store_helper(t, v, mut st)
			}
		}
	}
	for prop in vue_iterate_properties(t, object, vnudp_define_groups) {
		mut map_object := -1
		if prop.group in ['data', 'asyncData'] && prop.kind == .object {
			value := vue_property_value(t, prop.property)
			if t.typ(value) == .object_expression && vnudp_has_property_map(t, value) {
				map_object = value
			}
		}
		st.context(object).defs[prop.name] = VnudpData{
			has_nest: map_object >= 0
			is_props: prop.group == 'props'
			object:   map_object
		}
	}
	for name in c.vnudp_setup_to_refs_names(root, t, object, mut st) {
		if name !in st.context(object).defs {
			st.context(object).defs[name] = VnudpData{}
		}
	}
	for item in vue_iterate_properties(t, object, ['watch', 'expose']) {
		if item.group == 'watch' {
			refs := c.vpr_from_path(mut st.x, item.name, item.node)
			c.vnudp_verify(t, object, refs, false, mut st)
			if item.kind == .object && (t.string_of(item.property, .kind) or { '' }) == 'init' {
				mut handlers := []int{}
				vue_watch_handler_values(t, item.property, mut handlers)
				for handler in handlers {
					name_refs := c.vpr_from_name_literal(mut st.x, handler)
					c.vnudp_verify(t, object, name_refs, false, mut st)
				}
			}
		} else {
			refs := vpr_from_name(mut st.x, item.name, VprNode{0, item.node})
			c.vnudp_verify(t, object, refs, false, mut st)
		}
	}
}

// vnudp_add_store_helper is addPropertiesDefinedByStoreHelper.
fn vnudp_add_store_helper(t &estree.EsTree, call int, mut st VnudpState) {
	group := vnup_helper_group(vue_callee_name(t, call))
	args := t.list(call, .arguments) or { []int{} }
	if group == '' || args.len == 0 {
		return
	}
	arg := if args.len == 2 { args[1] } else { args[0] }
	if t.typ(arg) == .object_expression {
		for p in t.list(arg, .properties) or { []int{} } {
			if t.typ(p) == .spread_element {
				continue
			}
			name := vue_static_property_name(t, p) or { '' }
			if name != '' {
				st.helpers[name] = true
			}
		}
	} else if t.typ(arg) == .array_expression {
		for e in t.list(arg, .elements) or { []int{} } {
			if e < 0 || !vue_is_string_literal(t, e) {
				continue
			}
			name := vue_string_literal_value(t, e, false) or { '' }
			if name != '' {
				st.helpers[name] = true
			}
		}
	}
}

// vnudp_property_map is getObjectPropertyMap: the properties of an object by name (the last of
// a name), none when one is not a Property with a static name.
fn vnudp_property_map(t &estree.EsTree, object int) ?map[string]int {
	mut out := map[string]int{}
	for p in t.list(object, .properties) or { []int{} } {
		if t.typ(p) != .property {
			return none
		}
		name := vue_static_property_name(t, p) or { return none }
		out[name] = p
	}
	return out
}

fn vnudp_has_property_map(t &estree.EsTree, object int) bool {
	vnudp_property_map(t, object) or { return false }
	return true
}

// vnudp_get is PropertyData.get of a data property's object (getPropertyDataFromObjectProperty).
fn vnudp_get(t &estree.EsTree, data VnudpData, name string) ?VnudpData {
	if data.object < 0 {
		return none
	}
	properties := vnudp_property_map(t, data.object) or { return none }
	property := properties[name] or { return none }
	value := vue_property_value(t, property)
	if value >= 0 && t.typ(value) == .object_expression && vnudp_has_property_map(t, value) {
		return VnudpData{
			has_nest: true
			object:   value
		}
	}
	return VnudpData{}
}

// vnudp_option_function is the `ObjectExpression > Property > :function[params.length>0]`
// listener's condition, and its isProps (the function is the `data` of the object); none when
// the listener does nothing.
fn vnudp_option_function(t &estree.EsTree, node int, owner int) ?bool {
	if !vnup_is_option_function(t, node, owner) {
		return none
	}
	property := vnup_parent_property(t, node)
	return t.nodes[property].parent == owner
}

// vnudp_setup_to_refs_names is iterateSetupToRefsNames: the names `...toRefs(reactive({…}))`
// spreads in the objects setup() returns define.
fn (mut c Checker) vnudp_setup_to_refs_names(root C.vt_node, t &estree.EsTree, object int, mut st VnudpState) []string {
	setup := vue_find_property(t, object, 'setup', none)
	if setup < 0 {
		return []
	}
	value := vue_property_value(t, setup)
	if t.typ(value) !in [.function_expression, .arrow_function_expression] {
		return []
	}
	body := t.node(value, .body) or { return [] }
	mut returned := []int{}
	if t.typ(body) == .object_expression {
		returned << body
	} else if t.typ(body) == .block_statement {
		for statement in t.list(body, .body) or { []int{} } {
			if t.typ(statement) == .return_statement {
				argument := t.node(statement, .argument) or { continue }
				if t.typ(argument) == .object_expression {
					returned << argument
				}
			}
		}
	}
	mut out := []string{}
	for r in returned {
		for p in t.list(r, .properties) or { []int{} } {
			if t.typ(p) != .spread_element {
				continue
			}
			reactive_object := c.vnudp_reactive_object_from_to_refs(root, t,
				t.node(p, .argument) or { continue }, mut st)
			if reactive_object < 0 {
				continue
			}
			for q in t.list(reactive_object, .properties) or { []int{} } {
				if t.typ(q) != .property {
					continue
				}
				name := vue_static_property_name(t, q) or { '' }
				if name != '' {
					out << name
				}
			}
		}
	}
	return out
}

// vnudp_reactive_object_from_to_refs is getReactiveObjectFromToRefs: the object of
// `toRefs(reactive({…}))` (or of a `const` initialized with `reactive({…})`), -1 for none.
fn (mut c Checker) vnudp_reactive_object_from_to_refs(root C.vt_node, t &estree.EsTree, node int, mut st VnudpState) int {
	if !st.built {
		st.built = true
		for call in c.vue_composition_api_calls(root, t, ['reactive']).map(it.call) {
			st.reactive[call] = true
		}
		for call in c.vue_composition_api_calls(root, t, ['toRefs']).map(it.call) {
			st.to_refs[call] = true
		}
	}
	if t.typ(node) != .call_expression || node !in st.to_refs {
		return -1
	}
	args := t.list(node, .arguments) or { []int{} }
	mut arg := if args.len > 0 { args[0] } else { -1 }
	if arg >= 0 && t.typ(arg) == .identifier {
		v := c.vue_find_variable(root, t, arg)
		if v < 0 {
			return -1
		}
		defs := c.scope_tree(root).variables[v].defs
		if defs.len != 1 || defs[0].kind != .variable || defs[0].parent_kind != 'const' {
			return -1
		}
		init_ts := defs[0].init or { return -1 }
		arg = c.es_index_of(t, init_ts) or { return -1 }
	}
	if arg < 0 || t.typ(arg) != .call_expression || arg !in st.reactive {
		return -1
	}
	reactive_args := t.list(arg, .arguments) or { []int{} }
	if reactive_args.len > 0 && t.typ(reactive_args[0]) == .object_expression {
		return reactive_args[0]
	}
	return -1
}

// vnudp_verify is VueComponentContext.verifyReferences of the context of `key`.
fn (mut c Checker) vnudp_verify(t &estree.EsTree, key int, refs int, is_props bool, mut st VnudpState) {
	if st.context(key).has_unknown {
		return
	}
	c.vnudp_verify_level(t, key, none, refs, '', is_props, mut st)
}

// vnudp_verify_level is verifyUndefProperties: `data` is the PropertyData whose `get` looks the
// names up (none for the context's own definitions).
fn (mut c Checker) vnudp_verify_level(t &estree.EsTree, key int, data ?VnudpData, refs int, path string, is_props bool, mut st VnudpState) {
	for p in c.vpr_all_properties(mut st.x, refs) {
		reference_path := if path != '' { '${path}.${p.name}' } else { p.name }
		found := vnudp_lookup(t, st, key, data, p.name) or {
			c.vnudp_report(key, p.nodes[0], reference_path, 'undef', mut st)
			continue
		}
		if is_props && !found.is_props {
			c.vnudp_report(key, p.nodes[0], reference_path, 'undefProps', mut st)
			continue
		}
		if found.has_nest {
			nest := c.vpr_get_nest(mut st.x, refs, p.name)
			c.vnudp_verify_level(t, key, found, nest, reference_path, is_props, mut st)
		}
	}
}

// vnudp_lookup is `defineProperties.get(name)`: in the PropertyData `data`, or in the
// definitions of the context of `key`.
fn vnudp_lookup(t &estree.EsTree, st &VnudpState, key int, data ?VnudpData, name string) ?VnudpData {
	if d := data {
		return vnudp_get(t, d, name)
	}
	if key in st.contexts {
		if v := st.contexts[key].defs[name] {
			return v
		}
	}
	return none
}

// vnudp_report is VueComponentContext.report: once per node and once per name.
fn (mut c Checker) vnudp_report(key int, node VprNode, name string, message_id string, mut st VnudpState) {
	if name in vnudp_reserved || st.ignores.matches(name) || name in st.helpers {
		return
	}
	mut ctx := st.context(key)
	if node.key() in ctx.reported_nodes || name in ctx.reported_names {
		return
	}
	ctx.reported_nodes[node.key()] = true
	ctx.reported_names[name] = true
	start, end := c.vpr_range(st.x, node)
	st.findings << c.vue_report(start, end, message_id, {
		'name': name
	})
}
