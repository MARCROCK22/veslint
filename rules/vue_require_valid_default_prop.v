module rules

import estree
import time

// Port of the `vue/require-valid-default-prop` rule of eslint-plugin-vue 10.12.1 (no options): a
// default of a prop (its `default`, the `withDefaults` one, the props destructure's, or a
// defineModel's) whose value, or the value a default function returns, is not of the prop's
// native types (an object, array or function default must be a function, except in a props
// destructure).

const vue_require_valid_default_prop_messages = {
	'invalidType': "Type of the default value for '{{name}}' prop must be a {{types}}."
}

const vrvdp_native_types = ['String', 'Number', 'Boolean', 'Function', 'Object', 'Array', 'Symbol',
	'BigInt']
const vrvdp_function_value_types = ['Function', 'Object', 'Array']

// VrvdpValueType is getValueType's answer (`ok` false for null).
struct VrvdpValueType {
	ok          bool
	typ         string
	function    bool
	expression  bool
	body        int = -1
	return_type string // of an expression body ('' for null)
}

// VrvdpProp is a prop as processPropDefs reads it.
struct VrvdpProp {
	kind     VuePropKind
	has_name bool
	name     string
	node     int = -1
	value    int = -1
	types    []string // of a type or infer-type prop
}

struct VrvdpDefault {
	expression int
	src        string // 'assignment', 'withDefaults' or 'defaultProperty'
}

// VrvdpContext is a PropDefaultFunctionContext: a default function with a block body whose
// return values are checked, inside `scope` (a Vue object, or the range of a macro call).
struct VrvdpContext {
	prop        VrvdpProp
	types       []string
	body        int
	function    int
	scope_start int
	scope_end   int
}

fn (mut c Checker) lint_vue_require_valid_default_prop(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut contexts := []VrvdpContext{}
	// onVueObjectEnter: the object props whose value is an object.
	for step in t.steps() {
		if step.leave || t.typ(step.node) != .object_expression
			|| s.object_type(step.node) == .none_ {
			continue
		}
		obj := step.node
		mut props := []VrvdpProp{}
		for p in vue_props_from_options(t, obj) {
			if p.kind == .object && t.typ(p.value) == .object_expression {
				props << vrvdp_prop(p)
			}
		}
		for ctx in c.vrvdp_process(t, props, map[string][]VrvdpDefault{}, mut findings) {
			contexts << VrvdpContext{
				...ctx
				scope_start: -1
				scope_end:   obj
			}
		}
	}
	for call in c.vue_macros_named(t, 'defineProps') {
		with_defaults := c.vx6_with_defaults_expressions(root, t, call)
		destructure := vx6_destructure_defaults(t, call)
		mut others := map[string][]VrvdpDefault{}
		for name, expression in with_defaults.props {
			if expression >= 0 {
				others[name] << VrvdpDefault{expression, 'withDefaults'}
			}
		}
		for name, d in destructure {
			others[name] << VrvdpDefault{d.expression, 'assignment'}
		}
		mut props := []VrvdpProp{}
		mut inferred := map[int]map[string][]string{}
		for p in c.vue_define_props(root, t, call, abs_path, true, mut stats) {
			match p.kind {
				.object {
					props << vrvdp_prop(p)
				}
				.type_ {
					info := c.vx6_type_prop(root, t, p.node, abs_path, mut stats)
					props << VrvdpProp{
						...vrvdp_prop(p)
						types: info.types
					}
				}
				.infer_type {
					if p.node !in inferred {
						inferred[p.node] = c.vx6_infer_type_props(t, p.node, abs_path, mut
							stats)
					}
					props << VrvdpProp{
						...vrvdp_prop(p)
						types: inferred[p.node][p.name] or { ['null'] }
					}
				}
				else {}
			}
		}
		for ctx in c.vrvdp_process(t, props, others, mut findings) {
			contexts << VrvdpContext{
				...ctx
				scope_start: t.nodes[call].start
				scope_end:   t.nodes[call].end
			}
		}
	}
	for call in c.vue_macros_named(t, 'defineModel') {
		model := vue_define_model(t, call)
		options := if model.options >= 0 { vue_skip_ts_as(t, model.options) } else { -1 }
		mut prop := VrvdpProp{}
		mut others := map[string][]VrvdpDefault{}
		if model.type_node >= 0 {
			mut checked := map[int]bool{}
			prop = VrvdpProp{
				kind:     .infer_type
				has_name: true
				name:     model.name
				node:     model.type_node
				types:    c.vx6_infer_runtime_type(root, t, model.type_node, abs_path, mut
					checked, mut stats)
			}
			if options >= 0 && t.typ(options) == .object_expression {
				d := vrvdp_property_node(t, options, 'default')
				if d >= 0 {
					others[model.name] << VrvdpDefault{vue_property_value(t, d), 'defaultProperty'}
				}
			}
		} else if options >= 0 && t.typ(options) == .object_expression {
			prop = VrvdpProp{
				kind:     .object
				has_name: true
				name:     model.name
				node:     call
				value:    options
			}
		} else {
			continue
		}
		for ctx in c.vrvdp_process(t, [prop], others, mut findings) {
			contexts << VrvdpContext{
				...ctx
				scope_start: t.nodes[call].start
				scope_end:   t.nodes[call].end
			}
		}
	}
	// The ReturnStatements of each default function (verifyReturnTypes).
	for ctx in contexts {
		stats.checked++
		in_scope := if ctx.scope_start < 0 {
			s.owner_of(ctx.function) == ctx.scope_end
		} else {
			ctx.scope_start <= t.nodes[ctx.function].start
				&& t.nodes[ctx.function].end <= ctx.scope_end
		}
		if !in_scope {
			continue
		}
		for step in t.steps() {
			if step.leave || t.typ(step.node) != .return_statement
				|| vaa_innermost_function(t, step.node) != ctx.function {
				continue
			}
			argument := t.node(step.node, .argument) or { continue }
			value := vrvdp_value_type(t, argument)
			if !value.ok || value.typ in ctx.types {
				continue
			}
			c.vrvdp_report(t, argument, ctx.prop, ctx.types, mut findings)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn vrvdp_prop(p VueProp) VrvdpProp {
	return VrvdpProp{
		kind:     p.kind
		has_name: p.has_name
		name:     p.name
		node:     p.node
		value:    p.value
	}
}

// vrvdp_process is processPropDefs: it reports the defaults it can tell, and gives the default
// functions with a block body.
fn (mut c Checker) vrvdp_process(t &estree.EsTree, props []VrvdpProp, others map[string][]VrvdpDefault, mut findings []Finding) []VrvdpContext {
	mut contexts := []VrvdpContext{}
	for prop in props {
		mut type_list := []string{}
		mut defaults := []VrvdpDefault{}
		if prop.kind == .object {
			if t.typ(prop.value) == .object_expression {
				typ := vrvdp_property_node(t, prop.value, 'type')
				if typ < 0 {
					continue
				}
				type_list = vrvdp_types(t, vue_property_value(t, typ))
				d := vrvdp_property_node(t, prop.value, 'default')
				if d >= 0 {
					defaults << VrvdpDefault{vue_property_value(t, d), 'defaultProperty'}
				}
			} else {
				type_list = vrvdp_types(t, prop.value)
			}
		} else {
			type_list = prop.types.clone()
		}
		if prop.has_name {
			defaults << others[prop.name] or { []VrvdpDefault{} }
		}
		if defaults.len == 0 {
			continue
		}
		mut name_list := []string{}
		for name in type_list {
			if name in vrvdp_native_types && name !in name_list {
				name_list << name
			}
		}
		if name_list.len == 0 {
			continue
		}
		for d in defaults {
			value := vrvdp_value_type(t, d.expression)
			if !value.ok {
				continue
			}
			if value.function {
				if 'Function' in name_list {
					continue
				}
				if d.src == 'assignment' {
					c.vrvdp_report(t, d.expression, prop, name_list, mut findings)
					continue
				}
				if value.expression {
					if value.return_type == '' || value.return_type in name_list {
						continue
					}
					c.vrvdp_report(t, value.body, prop, name_list, mut findings)
				} else {
					contexts << VrvdpContext{
						prop:     prop
						types:    name_list
						body:     value.body
						function: vue_skip_chain(t, d.expression)
					}
				}
				continue
			}
			if value.typ in name_list
				&& (d.src == 'assignment' || value.typ !in vrvdp_function_value_types) {
				continue
			}
			expected := if d.src == 'assignment' {
				name_list
			} else {
				name_list.map(if it in vrvdp_function_value_types { 'Function' } else { it })
			}
			c.vrvdp_report(t, d.expression, prop, expected, mut findings)
		}
	}
	return contexts
}

fn (mut c Checker) vrvdp_report(t &estree.EsTree, node int, prop VrvdpProp, types []string, mut findings []Finding) {
	name := if prop.has_name {
		prop.name
	} else {
		key := t.node(prop.node, .key) or { -1 }
		'[${if key >= 0 { c.vx6_raw(t, key) } else { '' }}]'
	}
	findings << Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: 'invalidType'
		data:       {
			'name':  name
			'types': types.join(' or ').to_lower()
		}
	}
}

// vrvdp_property_node is getPropertyNode: a non-computed Property whose key is the identifier.
fn vrvdp_property_node(t &estree.EsTree, object int, name string) int {
	for p in t.list(object, .properties) or { []int{} } {
		if t.typ(p) != .property || (t.flag(p, .computed) or { false }) {
			continue
		}
		key := t.node(p, .key) or { continue }
		if t.typ(key) == .identifier && (t.string_of(key, .name) or { '' }) == name {
			return p
		}
	}
	return -1
}

// vrvdp_types is getTypes: the identifier, or the identifiers of an array.
fn vrvdp_types(t &estree.EsTree, target int) []string {
	node := vue_skip_ts_as(t, target)
	if node < 0 {
		return []
	}
	if t.typ(node) == .identifier {
		return [t.string_of(node, .name) or { '' }]
	}
	if t.typ(node) == .array_expression {
		mut out := []string{}
		for e in t.list(node, .elements) or { []int{} } {
			if e >= 0 && t.typ(e) == .identifier {
				out << t.string_of(e, .name) or { '' }
			}
		}
		return out
	}
	return []
}

// vrvdp_value_type is getValueType.
fn vrvdp_value_type(t &estree.EsTree, target int) VrvdpValueType {
	node := vue_skip_chain(t, target)
	if node < 0 {
		return VrvdpValueType{}
	}
	match t.typ(node) {
		.call_expression {
			callee := t.node(node, .callee) or { return VrvdpValueType{} }
			name := t.string_of(callee, .name) or { '' }
			if t.typ(callee) == .identifier && name in vrvdp_native_types {
				return VrvdpValueType{
					ok:  true
					typ: name
				}
			}
		}
		.template_literal {
			return VrvdpValueType{
				ok:  true
				typ: 'String'
			}
		}
		.literal {
			value := t.get(node, .value)
			typ := match value {
				estree.BigIntValue { 'BigInt' }
				estree.Null { return VrvdpValueType{} }
				bool { 'Boolean' }
				string { 'String' }
				f64 { 'Number' }
				else { 'Object' }
			}
			if typ in vrvdp_native_types {
				return VrvdpValueType{
					ok:  true
					typ: typ
				}
			}
		}
		.array_expression {
			return VrvdpValueType{
				ok:  true
				typ: 'Array'
			}
		}
		.object_expression {
			return VrvdpValueType{
				ok:  true
				typ: 'Object'
			}
		}
		.function_expression {
			return VrvdpValueType{
				ok:       true
				typ:      'Function'
				function: true
				body:     t.node(node, .body) or { -1 }
			}
		}
		.arrow_function_expression {
			body := t.node(node, .body) or { -1 }
			if t.flag(node, .expression) or { false } {
				inner := vrvdp_value_type(t, body)
				return VrvdpValueType{
					ok:          true
					typ:         'Function'
					function:    true
					expression:  true
					body:        body
					return_type: if inner.ok { inner.typ } else { '' }
				}
			}
			return VrvdpValueType{
				ok:       true
				typ:      'Function'
				function: true
				body:     body
			}
		}
		else {}
	}
	return VrvdpValueType{}
}
