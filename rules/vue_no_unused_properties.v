module rules

import estree
import json2
import time

// Port of the `vue/no-unused-properties` rule of eslint-plugin-vue 10.12.1 (options groups,
// default ['props'], deepData, ignorePublicMembers, unreferencedOptions): a property of a
// component (a prop, data, async data, computed property, method, property returned from setup()
// or inject of the groups chosen, the props of defineProps and defineModel, and what Vuex or Pinia
// map* helpers define) that neither the component nor the template nor the `v-bind()` of a style
// reads (vue_property_references.v tells what they read). Only a .vue file is linted: the rule
// is a defineTemplateBodyVisitor, which gives nothing without vue-eslint-parser.

const vue_no_unused_properties_messages = {
	'unused': "'{{name}}' of {{group}} found, but never used."
}

const vnup_all_groups = ['props', 'data', 'asyncData', 'computed', 'methods', 'setup', 'inject']

// vnup_label is PROPERTY_LABEL.
fn vnup_label(group string) string {
	return match group {
		'props' { 'property' }
		'data' { 'data' }
		'asyncData' { 'async data' }
		'computed' { 'computed property' }
		'methods' { 'method' }
		'setup' { 'property returned from `setup()`' }
		'inject' { 'inject' }
		else { group }
	}
}

struct VnupOptions {
	groups                         []string
	deep_data                      bool
	ignore_public_members          bool
	unknown_member_as_unreferenced bool
	return_as_unreferenced         bool
}

fn vnup_options(options []json2.Any) !VnupOptions {
	o := option_object(vue_no_unused_properties, options, ['groups', 'deepData', 'ignorePublicMembers',
		'unreferencedOptions'])!
	groups := if 'groups' in o.values { o.string_list('groups')! } else { ['props'] }
	for g in groups {
		if g !in vnup_all_groups {
			return error('option `groups` of `${vue_no_unused_properties}` must be one of ${vnup_all_groups}')
		}
	}
	unreferenced := o.string_list('unreferencedOptions')!
	for u in unreferenced {
		if u !in ['unknownMemberAsUnreferenced', 'returnAsUnreferenced'] {
			return error('option `unreferencedOptions` of `${vue_no_unused_properties}` must be unknownMemberAsUnreferenced or returnAsUnreferenced')
		}
	}
	return VnupOptions{
		groups:                         groups
		deep_data:                      o.bool_value('deepData')!
		ignore_public_members:          o.bool_value('ignorePublicMembers')!
		unknown_member_as_unreferenced: 'unknownMemberAsUnreferenced' in unreferenced
		return_as_unreferenced:         'returnAsUnreferenced' in unreferenced
	}
}

// VnupProperty is a ComponentPropertyData: `kind` is 'object', 'array', 'type', 'infer-type' or
// 'model', `node` the node reported (of the script), `property` the Property of an object one.
struct VnupProperty {
	name     string
	group    string
	kind     string
	node     int
	property int = -1
}

// VnupContainer is a VueComponentPropertiesContainer.
struct VnupContainer {
mut:
	properties []VnupProperty
	refs       []int
	refs_props []int
}

struct VnupCtx {
	o VnupOptions
mut:
	x          VprExtractor
	containers map[int]VnupContainer // by the Vue object, or -1 for the Program
	order      []int
	template   []int
	ref_names  map[string]bool
	findings   []Finding
}

fn (mut ctx VnupCtx) container(node int) &VnupContainer {
	if node !in ctx.containers {
		ctx.containers[node] = VnupContainer{}
		ctx.order << node
	}
	return unsafe { &ctx.containers[node] }
}

fn (mut c Checker) lint_vue_no_unused_properties(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []Finding{}
	}
	sw := time.new_stopwatch()
	o := vnup_options(c.rule_options(vue_no_unused_properties))!
	s := c.vue_script(root, abs_path) or { return []Finding{} }
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut ctx := VnupCtx{
		o: o
		x: c.vpr_new_extractor(root, t, o.unknown_member_as_unreferenced, o.return_as_unreferenced)
	}
	// Program: the names the `v-bind()` of the styles read.
	if style := c.vpr_from_style_variables(mut ctx.x) {
		ctx.template << style
	}
	mut define_props := map[int]bool{}
	for call in c.vue_macros_named(t, 'defineProps') {
		define_props[call] = true
	}
	mut define_models := map[int]bool{}
	for call in c.vue_macros_named(t, 'defineModel') {
		define_models[call] = true
	}
	mut props_pattern := -1
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		if node in define_props && 'props' in o.groups {
			props_pattern = c.vnup_define_props(root, t, node, abs_path, mut ctx, mut stats)
		}
		if node in define_models && 'props' in o.groups {
			c.vnup_define_model(t, node, mut ctx)
		}
		owner := s.owner_of(node)
		if owner < 0 {
			continue
		}
		typ := t.typ(node)
		if owner == node {
			c.vnup_object_enter(t, node, mut ctx)
		}
		if typ == .call_expression {
			vnup_store_helper(t, node, owner, mut ctx)
		}
		if typ in [.function_expression, .arrow_function_expression] {
			if vnup_is_option_function(t, node, owner) {
				refs := c.vpr_from_function_param(mut ctx.x, node, 0)
				ctx.container(owner).refs << refs
			}
			kind := s.vue_function_kind(t, node)
			if kind == 'setup' {
				refs := c.vpr_from_function_param(mut ctx.x, node, 0)
				ctx.container(owner).refs_props << refs
			} else if kind == 'render' {
				refs := c.vpr_from_function_param(mut ctx.x, node, 0)
				ctx.container(owner).refs_props << refs
				if vnup_is_functional(t, owner) {
					v2 := c.vpr_from_function_param(mut ctx.x, node, 1)
					nest := c.vpr_get_nest(mut ctx.x, v2, 'props')
					ctx.container(owner).refs_props << nest
				}
			}
		}
		if typ in [.this_expression, .identifier] && c.vue_is_this(root, t, node) {
			stats.checked++
			refs := c.vpr_from_expression(mut ctx.x, VprNode{0, node}, false)
			ctx.container(owner).refs << refs
		}
	}
	if c.vue_has_template() {
		c.vnup_template(t, props_pattern, mut ctx)
	}
	c.vnup_report(root, t, mut ctx, mut stats)
	stats.eval_ms += ms(sw.elapsed())
	return ctx.findings
}

// vnup_define_props is onDefinePropsEnter: the props as properties of the Program, and what the
// pattern the props are assigned to reads (its pattern is returned, -1 for none).
fn (mut c Checker) vnup_define_props(root C.TSNode, t &estree.EsTree, call int, abs_path string, mut ctx VnupCtx, mut stats Stats) int {
	mut container := ctx.container(-1)
	for prop in c.vue_define_props(root, t, call, abs_path, true, mut stats) {
		if !prop.has_name || prop.name == '' || vnup_is_never_type_prop(t, prop) {
			continue
		}
		container.properties << match prop.kind {
			.object {
				VnupProperty{
					name:     prop.name
					group:    'props'
					kind:     'object'
					node:     prop.key
					property: prop.node
				}
			}
			.infer_type {
				VnupProperty{
					name:  prop.name
					group: 'props'
					kind:  'infer-type'
					node:  prop.node
				}
			}
			else {
				VnupProperty{
					name:  prop.name
					group: 'props'
					kind:  if prop.kind == .array { 'array' } else { 'type' }
					node:  prop.key
				}
			}
		}
	}
	pattern := vue_left_of_define_props(t, call)
	if pattern < 0 {
		return -1
	}
	refs := c.vpr_from_pattern(mut ctx.x, pattern)
	ctx.container(-1).refs_props << refs
	return pattern
}

// vnup_is_never_type_prop is isNeverTypeProp: a prop typed `never`.
fn vnup_is_never_type_prop(t &estree.EsTree, prop VueProp) bool {
	if prop.kind != .type_ || prop.node < 0 || t.typ(prop.node) != .ts_property_signature {
		return false
	}
	annotation := t.node(prop.node, .type_annotation) or { return false }
	typ := t.node(annotation, .type_annotation) or { return false }
	return t.typ(typ) == .ts_never_keyword
}

// vnup_define_model is onDefineModelEnter: a model kept in a variable is used through it.
fn (mut c Checker) vnup_define_model(t &estree.EsTree, call int, mut ctx VnupCtx) {
	model := vue_define_model(t, call)
	node := if model.name_node >= 0 { model.name_node } else { call }
	parent := t.nodes[call].parent
	if parent >= 0 && t.typ(parent) == .variable_declarator
		&& (t.node(parent, .init) or { -1 }) == call {
		refs := vpr_from_name(mut ctx.x, model.name, VprNode{0, node})
		ctx.container(-1).refs << refs
		return
	}
	ctx.container(-1).properties << VnupProperty{
		name:  model.name
		group: 'props'
		kind:  'model'
		node:  node
	}
}

// vnup_object_enter is onVueObjectEnter: the watchers and exposes read properties; the
// properties of the groups chosen.
fn (mut c Checker) vnup_object_enter(t &estree.EsTree, object int, mut ctx VnupCtx) {
	for item in vue_iterate_properties(t, object, ['watch', 'expose']) {
		if item.group == 'watch' {
			refs := c.vpr_from_path(mut ctx.x, item.name, item.node)
			ctx.container(object).refs << refs
			if item.kind == .object && (t.string_of(item.property, .kind) or { '' }) == 'init' {
				mut handlers := []int{}
				vue_watch_handler_values(t, item.property, mut handlers)
				for handler in handlers {
					name_refs := c.vpr_from_name_literal(mut ctx.x, handler)
					ctx.container(object).refs << name_refs
				}
			}
		} else {
			refs := vpr_from_name(mut ctx.x, item.name, VprNode{0, item.node})
			ctx.container(object).refs << refs
		}
	}
	for item in vue_iterate_properties(t, object, ctx.o.groups) {
		ctx.container(object).properties << VnupProperty{
			name:     item.name
			group:    item.group
			kind:     if item.kind == .object { 'object' } else { 'array' }
			node:     item.node
			property: item.property
		}
	}
}

// vnup_helper_group is the group of a Vuex or Pinia map* helper (by the regular expressions of
// the rule, whose alternatives are not anchored together), '' for another callee.
fn vnup_helper_group(name string) string {
	if name.starts_with('mapMutations') || name.ends_with('mapActions') {
		return 'methods'
	}
	if name.starts_with('mapState') || name.contains('mapGetters')
		|| name.ends_with('mapWritableState') {
		return 'computed'
	}
	return ''
}

// vnup_store_helper is the CallExpression listener: the properties a map* helper defines.
fn vnup_store_helper(t &estree.EsTree, call int, owner int, mut ctx VnupCtx) {
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
				ctx.container(owner).properties << VnupProperty{
					name:  name
					group: group
					kind:  'array'
					node:  p
				}
			}
		}
	} else if t.typ(arg) == .array_expression {
		for e in t.list(arg, .elements) or { []int{} } {
			if e < 0 || t.typ(e) !in [.literal, .template_literal] {
				continue
			}
			name := vue_string_literal_value(t, e, false) or { '' }
			if name != '' {
				ctx.container(owner).properties << VnupProperty{
					name:  name
					group: group
					kind:  'array'
					node:  e
				}
			}
		}
	}
}

// vnup_parent_property is getParentProperty: the Property (of an object expression) whose value
// the node is, -1 for none.
fn vnup_parent_property(t &estree.EsTree, node int) int {
	if node < 0 {
		return -1
	}
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .property || (t.node(parent, .value) or { -1 }) != node {
		return -1
	}
	return if vue_is_property(t, parent) { parent } else { -1 }
}

// vnup_is_option_function is the condition of the `ObjectExpression > Property >
// :function[params.length>0]` listener: a function with parameters that is the `data` of the
// Vue object, a computed property or the getter of one.
fn vnup_is_option_function(t &estree.EsTree, node int, owner int) bool {
	if (t.list(node, .params) or { []int{} }).len == 0 {
		return false
	}
	property := vnup_parent_property(t, node)
	if property < 0 {
		return false
	}
	object := t.nodes[property].parent
	if object == owner {
		return (vue_static_property_name(t, property) or { '' }) == 'data'
	}
	parent_property := vnup_parent_property(t, object)
	if parent_property < 0 {
		return false
	}
	if t.nodes[parent_property].parent == owner {
		return (vue_static_property_name(t, parent_property) or { '' }) == 'computed'
	}
	grand_property := vnup_parent_property(t, t.nodes[parent_property].parent)
	if grand_property < 0 || t.nodes[grand_property].parent != owner {
		return false
	}
	return (vue_static_property_name(t, grand_property) or { '' }) == 'computed'
		&& (vue_static_property_name(t, property) or { '' }) == 'get'
}

// vnup_is_functional is vueData.functional: the object has a `functional` property whose value
// is not the literal false.
fn vnup_is_functional(t &estree.EsTree, object int) bool {
	functional := vue_find_property(t, object, 'functional', none)
	if functional < 0 {
		return false
	}
	value := vue_property_value(t, functional)
	if t.typ(value) != .literal {
		return true
	}
	v := t.get(value, .value)
	return !(v is bool && v == false)
}

// vnup_template is the template's listeners: what each expression container reads (and, through
// the props variable, what it reads of the props), and the names of the `ref` attributes.
fn (mut c Checker) vnup_template(t &estree.EsTree, props_pattern int, mut ctx VnupCtx) {
	doc := c.vue.doc
	for v in c.vue_template_vnodes() {
		node := &doc.nodes[v]
		if node.typ == .v_expression_container {
			property := c.vpr_from_container(mut ctx.x, v, false)
			ctx.template << property
			if props_pattern < 0 || t.typ(props_pattern) != .identifier {
				continue
			}
			props_name := vue_identifier_name(t, props_pattern)
			for p in c.vpr_all_properties(mut ctx.x, property) {
				if p.name == props_name {
					nest := c.vpr_get_nest(mut ctx.x, property, p.name)
					ctx.template << nest
				}
			}
		} else if node.typ == .v_attribute && !node.directive {
			if doc.nodes[node.key].name == 'ref' && node.value >= 0 {
				ctx.ref_names[doc.nodes[node.value].text] = true
			}
		}
	}
}

// vnup_report is reportUnusedProperties.
fn (mut c Checker) vnup_report(root C.TSNode, t &estree.EsTree, mut ctx VnupCtx, mut stats Stats) {
	for key in ctx.order {
		container := ctx.containers[key]
		mut all := container.refs.clone()
		all << ctx.template
		refs := vpr_merge(mut ctx.x, all)
		refs_props := vpr_merge(mut ctx.x, container.refs_props)
		for property in container.properties {
			stats.checked++
			c.vnup_verify(root, t, property, refs, refs_props, mut ctx)
		}
	}
}

// vnup_verify is verifyPropertyUsage.
fn (mut c Checker) vnup_verify(root C.TSNode, t &estree.EsTree, property VnupProperty, refs int, refs_props int, mut ctx VnupCtx) {
	if property.group == 'props' && (c.vpr_has_property(mut ctx.x, refs_props, property.name,
		VprHasOptions{ external_call_as_any: true })
		|| c.vpr_has_property(mut ctx.x, refs, r'$props', VprHasOptions{})) {
		return
	}
	if property.group == 'setup' && property.name in ctx.ref_names {
		return
	}
	if ctx.o.ignore_public_members && property.kind == 'object' && property.group != 'props'
		&& c.vnup_is_public_property(root, t, property.property) {
		return
	}
	if c.vpr_has_property(mut ctx.x, refs, property.name, VprHasOptions{}) {
		if ctx.o.deep_data && property.group in ['data', 'asyncData'] && property.kind == 'object' {
			nest := c.vpr_get_nest(mut ctx.x, refs, property.name)
			c.vnup_verify_deep(root, t, [property.name], vue_property_value(t, property.property),
				nest, mut ctx)
		}
		return
	}
	ctx.findings << c.vue_report(t.nodes[property.node].start, t.nodes[property.node].end,
		'unused', {
			'group': vnup_label(property.group)
			'name':  property.name
		})
}

// vnup_verify_deep is verifyDataOptionDeepProperties.
fn (mut c Checker) vnup_verify_deep(root C.TSNode, t &estree.EsTree, segments []string, value int, refs int, mut ctx VnupCtx) {
	mut target := value
	if target >= 0 && t.typ(target) == .identifier {
		target = c.vnup_find_expression(root, t, target, 0)
	}
	if target < 0 || t.typ(target) != .object_expression {
		return
	}
	for p in t.list(target, .properties) or { []int{} } {
		if t.typ(p) != .property {
			continue
		}
		name := vue_static_property_name(t, p) or { continue }
		mut path := segments.clone()
		path << name
		if !c.vpr_has_property(mut ctx.x, refs, name, VprHasOptions{ unknown_call_as_any: true }) {
			key := t.node(p, .key) or { continue }
			ctx.findings << c.vue_report(t.nodes[key].start, t.nodes[key].end, 'unused', {
				'group': vnup_label('data')
				'name':  path.join('.')
			})
			continue
		}
		nest := c.vpr_get_nest(mut ctx.x, refs, name)
		c.vnup_verify_deep(root, t, path, vue_property_value(t, p), nest, mut ctx)
	}
}

// vnup_find_expression is findExpression: the initializer of a `const` (through aliases), or
// the identifier itself.
fn (mut c Checker) vnup_find_expression(root C.TSNode, t &estree.EsTree, id int, depth int) int {
	v := c.vue_find_variable(root, t, id)
	if v < 0 || depth > 100 {
		return id
	}
	defs := c.scope_tree(root).variables[v].defs
	if defs.len == 1 && defs[0].kind == .variable && defs[0].parent_kind == 'const' {
		init_ts := defs[0].init or { return id }
		init := c.es_index_of(t, init_ts) or { return id }
		return if t.typ(init) == .identifier {
			c.vnup_find_expression(root, t, init, depth + 1)
		} else {
			init
		}
	}
	return id
}

// vnup_is_public_property is isPublicProperty: the property's JSDoc comment (or its function's)
// has a `@public` tag.
fn (mut c Checker) vnup_is_public_property(root C.TSNode, t &estree.EsTree, property int) bool {
	mut jsdoc := c.vnup_jsdoc(root, t.nodes[property].start)
	if jsdoc.len == 0 {
		value := vue_property_value(t, property)
		if value >= 0 && t.typ(value) in [.function_expression, .arrow_function_expression] {
			jsdoc = c.vnup_jsdoc(root, t.nodes[value].start)
		}
	}
	if jsdoc.len == 0 {
		return false
	}
	// /(?:^|\s|\*)@public\b/u on the comment's value.
	value := jsdoc[0]
	mut from := 0
	for {
		i := value.index_after('@public', from) or { return false }
		before_ok := i == 0 || value[i - 1] in [` `, `\t`, `\n`, `\r`, `\v`, `\f`, `*`]
			|| vnup_unicode_space_before(value, i)
		after := i + '@public'.len
		after_ok := after >= value.len || !(value[after].is_letter() || value[after].is_digit()
			|| value[after] == `_`)
		if before_ok && after_ok {
			return true
		}
		from = i + 1
	}
	return false
}

// vnup_unicode_space_before: the code point before `i` is a Unicode space of \s other than the
// ASCII ones.
fn vnup_unicode_space_before(s string, i int) bool {
	mut j := i - 1
	for j > 0 && s[j] & 0xc0 == 0x80 {
		j--
	}
	if j < 0 || s[j] < 0x80 {
		return false
	}
	r := s[j..i].runes()
	if r.len != 1 {
		return false
	}
	return r[0] in [` `, ` `, ` `, ` `, ` `, ` `, ` `, ` `, ` `, ` `, ` `,
		` `, ` `, ` `, ` `, ` `, ` `, `　`, `﻿`]
}

// vnup_jsdoc is findJSDocComment of a node starting at `start`: the value of the JSDoc block
// comment before it (through line comments), in a one-element list; empty for none.
fn (mut c Checker) vnup_jsdoc(root C.TSNode, start int) []string {
	tokens := c.source_tokens(root)
	mut at := start
	for {
		mut lo := 0
		mut hi := tokens.all.len
		for lo < hi {
			mid := (lo + hi) / 2
			if tokens.all[mid].end <= at {
				lo = mid + 1
			} else {
				hi = mid
			}
		}
		if lo == 0 {
			return []
		}
		before := tokens.all[lo - 1]
		if before.kind == .line_comment {
			at = before.start
			continue
		}
		if before.kind != .block_comment {
			return []
		}
		value := c.src[before.start + 2..before.end - 2]
		if value.len > 0 && value[0] == `*` && (value.len < 2 || value[1] != `*`) {
			return [value]
		}
		return []
	}
	return []
}
