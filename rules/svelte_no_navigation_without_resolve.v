module rules

import estree
import json2
import svelte
import tsgo { SymbolResponse }
import treesitter { node_kind }

// Port of the `svelte/no-navigation-without-resolve` rule of eslint-plugin-svelte 3.24.1: the URL
// of `goto`, `pushState` and `replaceState` of `$app/navigation` and the `href` of an `<a>` (but
// one with `rel="external"`) must come from `resolve()` (or `asset()`) of `$app/paths`, or have
// the type ResolvedPathname of `$app/types`; the value is followed through `const` initializers,
// conditional expressions, static members of literal arrays and objects (with spreads) and the
// items of an `{#each}` over a literal array. Links may also be absolute, fragments or nullish,
// shallow routing may use an empty URL; options ignore each kind. Its condition is a SvelteKit 1
// to 3 project.

const svnnwr_messages = {
	'gotoWithoutResolve':         'Unexpected goto() call without resolve().'
	'linkWithoutResolve':         'Unexpected href link without resolve().'
	'pushStateWithoutResolve':    'Unexpected pushState() call without resolve().'
	'replaceStateWithoutResolve': 'Unexpected replaceState() call without resolve().'
}

struct SvnnwrConfig {
	absolute bool
	empty    bool
	fragment bool
	nullish  bool
}

// SvnnwrLookup is PropertyLookup: found (`value`), absent or unknown.
enum SvnnwrLookupKind {
	found
	absent
	unknown
}

struct SvnnwrLookup {
	kind  SvnnwrLookupKind
	value int = -1
}

struct SvnnwrContext {
	e        SvscEs
	b        SvscBridge
	root     C.TSNode
	abs_path string
	typed    bool
	resolve  map[int]bool // view identifiers of the references to resolve and asset
mut:
	visited           map[int]bool // the FindVariableContext of one check
	resolved_pathname int = -2 // the declared type of $app/types' ResolvedPathname (-1: none)
}

fn svnnwr_options(options []json2.Any) !SvnnwbOptions {
	o := option_object(svelte_no_navigation_without_resolve, options, ['ignoreGoto', 'ignoreLinks',
		'ignorePushState', 'ignoreReplaceState'])!
	return SvnnwbOptions{
		ignore_goto:          o.bool_value('ignoreGoto')!
		ignore_links:         o.bool_value('ignoreLinks')!
		ignore_push_state:    o.bool_value('ignorePushState')!
		ignore_replace_state: o.bool_value('ignoreReplaceState')!
	}
}

// svnnwr_binding is resolveBindingIdentifier: the first identifier of the variable (none for no
// variable or one met before in this check).
fn (mut c Checker) svnnwr_binding(mut ctx SvnnwrContext, id int) ?int {
	if ctx.visited[id] {
		return none
	}
	ctx.visited[id] = true
	t := ctx.e.t
	if ctx.e.svelte {
		v := c.sv_find_variable(id)
		if v < 0 {
			return none
		}
		defs := c.svelte.doc.scope.variables[v].defs
		return if defs.len == 0 { none } else { defs[0].name }
	}
	ts := t.ts_node(id)?
	tree := c.scope_tree(ctx.root)
	name := t.string_of(id, .name)?
	scope := tree.get_scope(ts)
	mut v := tree.find_variable(scope, name, t.nodes[id].start)
	if v < 0 && name.starts_with('\$') {
		v = tree.find_variable(scope, name[1..], t.nodes[id].start)
	}
	if v < 0 || tree.variables[v].identifiers.len == 0 {
		return none
	}
	return c.es_index_of(t, tree.variables[v].identifiers[0])
}

// svnnwr_string is getStringIfConstant with the node's scope (through the lint code).
fn (mut c Checker) svnnwr_string(ctx &SvnnwrContext, node int) ?string {
	lint := ctx.b.lint_of(node)?
	ts := ctx.b.lint.ts_node(lint)?
	value := c.get_static_value(ts)
	if !value.found {
		return none
	}
	return js_any_string_value(value.value)
}

// svnnwr_property_name is getPropertyName with a scope, of a MemberExpression or a Property.
fn (mut c Checker) svnnwr_property_name(ctx &SvnnwrContext, node int) ?string {
	t := ctx.e.t
	computed := t.flag(node, .computed) or { false }
	if t.typ(node) == .member_expression {
		property := t.node(node, .property)?
		if computed {
			return c.svnnwr_string(ctx, property)
		}
		if t.typ(property) == .private_identifier {
			return none
		}
		return t.string_of(property, .name)
	}
	key := t.node(node, .key)?
	if computed {
		return c.svnnwr_string(ctx, key)
	}
	if t.typ(key) == .literal {
		return c.svnnwr_string(ctx, key)
	}
	if t.typ(key) == .identifier {
		return t.string_of(key, .name)
	}
	return none
}

// svnnwr_variable_init is resolveVariableInit.
fn (mut c Checker) svnnwr_variable_init(mut ctx SvnnwrContext, id int) ?int {
	binding := c.svnnwr_binding(mut ctx, id)?
	parent := c.svsc_parent(&ctx.e, binding)
	if parent < 0 || ctx.e.t.typ(parent) != .variable_declarator {
		return none
	}
	return ctx.e.t.node(parent, .init)
}

// svnnwr_literal_source is resolveToLiteralSource.
fn (mut c Checker) svnnwr_literal_source(mut ctx SvnnwrContext, node int) ?int {
	t := ctx.e.t
	if t.typ(node) == .identifier {
		return c.svnnwr_variable_init(mut ctx, node)
	}
	if t.typ(node) == .member_expression {
		key := c.svnnwr_property_name(ctx, node)?
		return c.svnnwr_access_key(mut ctx, t.node(node, .object)?, key)
	}
	return none
}

fn (mut c Checker) svnnwr_to_array(mut ctx SvnnwrContext, node int) ?int {
	if ctx.e.t.typ(node) == .array_expression {
		return node
	}
	resolved := c.svnnwr_literal_source(mut ctx, node)?
	return c.svnnwr_to_array(mut ctx, resolved)
}

fn (mut c Checker) svnnwr_to_object(mut ctx SvnnwrContext, node int) ?int {
	if ctx.e.t.typ(node) == .object_expression {
		return node
	}
	resolved := c.svnnwr_literal_source(mut ctx, node)?
	return c.svnnwr_to_object(mut ctx, resolved)
}

// svnnwr_array_index is arrayIndex: a canonical non-negative integer index.
fn svnnwr_array_index(key string) ?int {
	if key == '' || (key.len > 1 && key[0] == `0`) || key.len > 15 {
		return none
	}
	for ch in key {
		if !ch.is_digit() {
			return none
		}
	}
	return key.int()
}

fn (mut c Checker) svnnwr_access_key(mut ctx SvnnwrContext, expr int, key string) ?int {
	if index := svnnwr_array_index(key) {
		return c.svnnwr_element(mut ctx, expr, index)
	}
	return c.svnnwr_property(mut ctx, expr, key)
}

// svnnwr_flatten is flattenElements (-1 for a hole); none at an unknown spread.
fn (mut c Checker) svnnwr_flatten(mut ctx SvnnwrContext, array int, index int) ?[]int {
	t := ctx.e.t
	mut out := []int{}
	for element in t.list(array, .elements) or { []int{} } {
		if out.len > index {
			break
		}
		if element < 0 {
			out << -1
		} else if t.typ(element) == .spread_element {
			spread := c.svnnwr_to_array(mut ctx, t.node(element, .argument)?)?
			out << c.svnnwr_flatten(mut ctx, spread, index - out.len)?
		} else {
			out << element
		}
	}
	return out
}

fn (mut c Checker) svnnwr_element(mut ctx SvnnwrContext, expr int, index int) ?int {
	array := c.svnnwr_to_array(mut ctx, expr)?
	flattened := c.svnnwr_flatten(mut ctx, array, index)?
	if index >= flattened.len || flattened[index] < 0 {
		return none
	}
	return flattened[index]
}

fn (mut c Checker) svnnwr_lookup(mut ctx SvnnwrContext, expr int, key string) SvnnwrLookup {
	t := ctx.e.t
	object := c.svnnwr_to_object(mut ctx, expr) or {
		return SvnnwrLookup{
			kind: .unknown
		}
	}
	mut result := SvnnwrLookup{
		kind: .absent
	}
	for property in t.list(object, .properties) or { []int{} } {
		if t.typ(property) == .spread_element {
			spread := c.svnnwr_lookup(mut ctx, t.node(property, .argument) or { continue }, key)
			if spread.kind != .absent {
				result = spread
			}
		} else {
			name := c.svnnwr_property_name(ctx, property) or {
				result = SvnnwrLookup{
					kind: .unknown
				}
				continue
			}
			if name == key {
				result = SvnnwrLookup{
					kind:  .found
					value: t.node(property, .value) or { -1 }
				}
			}
		}
	}
	return result
}

fn (mut c Checker) svnnwr_property(mut ctx SvnnwrContext, expr int, key string) ?int {
	lookup := c.svnnwr_lookup(mut ctx, expr, key)
	return if lookup.kind == .found && lookup.value >= 0 { lookup.value } else { none }
}

// svnnwr_each_block_of is eachBlockOf: the iterated array and the `as` pattern of an `{#each}` a
// binding comes from.
fn (c &Checker) svnnwr_each_block_of(e &SvscEs, node int) ?(int, int) {
	parent := c.svsc_parent_ref(e, node)?
	t := e.t
	if !parent.es {
		p := c.svelte.doc.nodes[parent.idx]
		if p.typ != .each_block || !p.context.es || p.context.idx != node || !p.expression.es {
			return none
		}
		return p.expression.idx, node
	}
	if t.typ(parent.idx) == .property {
		outer := t.nodes[parent.idx].parent
		if outer >= 0 && t.typ(outer) == .object_pattern {
			return c.svnnwr_each_block_of(e, outer)
		}
		return none
	}
	if t.typ(parent.idx) == .array_pattern {
		return c.svnnwr_each_block_of(e, parent.idx)
	}
	return none
}

// svnnwr_destructured is destructuredValue.
fn (mut c Checker) svnnwr_destructured(mut ctx SvnnwrContext, pattern int, element int, binding int) ?int {
	if pattern == binding {
		return element
	}
	t := ctx.e.t
	if t.typ(pattern) == .object_pattern {
		for property in t.list(pattern, .properties) or { []int{} } {
			if t.typ(property) != .property {
				continue
			}
			key := c.svnnwr_property_name(ctx, property) or { continue }
			value := c.svnnwr_property(mut ctx, element, key) or { continue }
			if result := c.svnnwr_destructured(mut ctx, t.node(property, .value) or { continue },
				value, binding)
			{
				return result
			}
		}
		return none
	}
	if t.typ(pattern) == .array_pattern {
		for index, sub in t.list(pattern, .elements) or { []int{} } {
			if sub < 0 {
				continue
			}
			value := c.svnnwr_element(mut ctx, element, index) or { continue }
			if result := c.svnnwr_destructured(mut ctx, sub, value, binding) {
				return result
			}
		}
	}
	return none
}

// svnnwr_each_item_allowed is eachItemValueIsAllowed (`key` '' for none).
fn (mut c Checker) svnnwr_each_item_allowed(mut ctx SvnnwrContext, binding int, key string, config SvnnwrConfig, mut stats Stats) bool {
	if !ctx.e.svelte {
		return false
	}
	array_expr, context := c.svnnwr_each_block_of(&ctx.e, binding) or { return false }
	array := c.svnnwr_to_array(mut ctx, array_expr) or { return false }
	t := ctx.e.t
	for element in t.list(array, .elements) or { []int{} } {
		if element < 0 || t.typ(element) == .spread_element {
			return false
		}
		mut bound := c.svnnwr_destructured(mut ctx, context, element, binding) or { return false }
		if key != '' {
			bound = c.svnnwr_access_key(mut ctx, bound, key) or { return false }
		}
		if !c.svnnwr_allowed(mut ctx, sv_es_ref(bound), config, mut stats) {
			return false
		}
	}
	return true
}

// svnnwr_is_allowed_type is expressionIsAllowedType.
fn (mut c Checker) svnnwr_is_allowed_type(mut ctx SvnnwrContext, value svelte.Ref, nullish bool, mut stats Stats) bool {
	if !ctx.typed || !value.es {
		return false
	}
	ts := c.svsc_lint_ts(&ctx.b, value.idx, ctx.abs_path, mut stats) or { return false }
	mut t := c.node_type(ts) or { return false }
	if nullish {
		if t.flags & (type_flag_null | type_flag_undefined) != 0 {
			return true
		}
		t = c.client.non_nullable_type(c.snapshot, c.project, t.id) or { return false }
	}
	if ctx.resolved_pathname == -2 {
		ctx.resolved_pathname = -1
		module := c.client.resolve_name(c.snapshot, c.project, '"\$app/types"', 1536) or {
			return false
		}
		if !module.is_null() {
			for export in c.client.exports_of_symbol(c.snapshot, c.project, module.id) or {
				[]SymbolResponse{}
			} {
				if export.name == 'ResolvedPathname' {
					declared := c.client.declared_type_of_symbol(c.snapshot, c.project, export.id) or {
						break
					}
					ctx.resolved_pathname = declared.id
					break
				}
			}
		}
	}
	if ctx.resolved_pathname < 0 {
		return false
	}
	return (c.assignable(t.id, ctx.resolved_pathname) or { false })
		&& (c.assignable(ctx.resolved_pathname, t.id) or { false })
}

// svnnwr_is_resolve_call is expressionIsResolveCall.
fn (mut c Checker) svnnwr_is_resolve_call(mut ctx SvnnwrContext, node int) bool {
	t := ctx.e.t
	if t.typ(node) == .call_expression {
		callee := t.node(node, .callee) or { -1 }
		if callee >= 0 && t.typ(callee) == .identifier && ctx.resolve[callee] {
			return true
		}
		if callee >= 0 && t.typ(callee) == .member_expression {
			property := t.node(callee, .property) or { -1 }
			if property >= 0 && t.typ(property) == .identifier && ctx.resolve[property] {
				return true
			}
		}
	}
	if t.typ(node) != .identifier {
		return false
	}
	init := c.svnnwr_variable_init(mut ctx, node) or { return false }
	return c.svnnwr_is_resolve_call(mut ctx, init)
}

// svnnwr_is_absolute is expressionIsAbsoluteUrl.
fn (c &Checker) svnnwr_is_absolute(t &estree.EsTree, value svelte.Ref) bool {
	if !value.es {
		n := c.svelte.doc.nodes[value.idx]
		return n.typ == .literal && svsc_url_is_absolute(n.value)
	}
	node := value.idx
	match t.typ(node) {
		.binary_expression {
			return (t.string_of(node, .operator) or { '' }) == '+'
				&& (c.svnnwr_is_absolute(t, sv_es_ref(t.node(node, .left) or { return false }))
					|| c.svnnwr_is_absolute(t, sv_es_ref(t.node(node, .right) or { return false })))
		}
		.literal {
			v := t.get(node, .value)
			return v is string && svsc_url_is_absolute(v)
		}
		.template_literal {
			return (t.list(node, .expressions) or { []int{} }).any(c.svnnwr_is_absolute(t,
				sv_es_ref(it))) || (t.list(node, .quasis) or { []int{} }).any(svsc_url_is_absolute(svsc_raw(t,
				it)))
		}
		else {
			return false
		}
	}
}

// svnnwr_starts_with is expressionStartsWith.
fn (mut c Checker) svnnwr_starts_with(mut ctx SvnnwrContext, value svelte.Ref, prefix string) bool {
	if !value.es {
		n := c.svelte.doc.nodes[value.idx]
		return n.typ == .literal && n.value.starts_with(prefix)
	}
	t := ctx.e.t
	node := value.idx
	match t.typ(node) {
		.binary_expression {
			return (t.string_of(node, .operator) or { '' }) == '+'
				&& c.svnnwr_starts_with(mut ctx, sv_es_ref(t.node(node, .left) or { return false }), prefix)
		}
		.identifier {
			init := c.svnnwr_variable_init(mut ctx, node) or { return false }
			return c.svnnwr_starts_with(mut ctx, sv_es_ref(init), prefix)
		}
		.literal {
			v := t.get(node, .value)
			return v is string && v.starts_with(prefix)
		}
		.template_element {
			return svsc_raw(t, node).starts_with(prefix)
		}
		.template_literal {
			expressions := t.list(node, .expressions) or { []int{} }
			quasis := t.list(node, .quasis) or { []int{} }
			return (expressions.len >= 1 && c.svnnwr_starts_with(mut ctx, sv_es_ref(expressions[0]),
				prefix)) || (quasis.len >= 1 && c.svnnwr_starts_with(mut ctx, sv_es_ref(quasis[0]),
				prefix))
		}
		else {
			return false
		}
	}
}

// svnnwr_is_empty is expressionIsEmpty.
fn svnnwr_is_empty(t &estree.EsTree, value svelte.Ref) bool {
	return value.es && svnnwb_is_empty(t, value.idx)
}

// svnnwr_is_nullish is expressionIsNullish.
fn svnnwr_is_nullish(t &estree.EsTree, value svelte.Ref) bool {
	if !value.es {
		return false
	}
	node := value.idx
	if t.typ(node) == .identifier {
		return (t.string_of(node, .name) or { '' }) == 'undefined'
	}
	if t.typ(node) == .literal {
		return t.get(node, .value) is estree.Null
	}
	return false
}

// svnnwr_allowed is isValueAllowed.
fn (mut c Checker) svnnwr_allowed(mut ctx SvnnwrContext, value svelte.Ref, config SvnnwrConfig, mut stats Stats) bool {
	t := ctx.e.t
	if value.es && t.typ(value.idx) == .identifier {
		if binding := c.svnnwr_binding(mut ctx, value.idx) {
			parent := c.svsc_parent(&ctx.e, binding)
			if parent >= 0 && t.typ(parent) == .variable_declarator {
				// variableValueIsAllowed
				if c.svnnwr_is_allowed_type(mut ctx, sv_es_ref(binding), config.nullish, mut
					stats)
				{
					return true
				}
				init := t.node(parent, .init) or { return false }
				return c.svnnwr_allowed(mut ctx, sv_es_ref(init), config, mut stats)
			}
			if c.svnnwr_each_item_allowed(mut ctx, binding, '', config, mut stats) {
				return true
			}
		}
	}
	if value.es && t.typ(value.idx) == .member_expression
		&& c.svnnwr_member_allowed(mut ctx, value.idx, config, mut stats) {
		return true
	}
	if value.es && t.typ(value.idx) == .conditional_expression {
		consequent := t.node(value.idx, .consequent) or { return false }
		alternate := t.node(value.idx, .alternate) or { return false }
		return c.svnnwr_allowed(mut ctx, sv_es_ref(consequent), config, mut stats)
			&& c.svnnwr_allowed(mut ctx, sv_es_ref(alternate), config, mut stats)
	}
	if config.absolute && c.svnnwr_is_absolute(t, value) {
		return true
	}
	if config.empty && svnnwr_is_empty(t, value) {
		return true
	}
	if config.fragment && c.svnnwr_starts_with(mut ctx, value, '#') {
		return true
	}
	if config.nullish && svnnwr_is_nullish(t, value) {
		return true
	}
	if c.svnnwr_is_allowed_type(mut ctx, value, config.nullish, mut stats) {
		return true
	}
	return value.es && c.svnnwr_is_resolve_call(mut ctx, value.idx)
}

// svnnwr_member_allowed is memberValueIsAllowed.
fn (mut c Checker) svnnwr_member_allowed(mut ctx SvnnwrContext, value int, config SvnnwrConfig, mut stats Stats) bool {
	t := ctx.e.t
	key := c.svnnwr_property_name(ctx, value) or { return false }
	object := t.node(value, .object) or { return false }
	if t.typ(object) != .identifier {
		target := c.svnnwr_access_key(mut ctx, object, key) or { return false }
		return c.svnnwr_allowed(mut ctx, sv_es_ref(target), config, mut stats)
	}
	binding := c.svnnwr_binding(mut ctx, object) or { return false }
	if c.svnnwr_each_item_allowed(mut ctx, binding, key, config, mut stats) {
		return true
	}
	parent := c.svsc_parent(&ctx.e, binding)
	if parent >= 0 && t.typ(parent) == .variable_declarator {
		init := t.node(parent, .init) or { return false }
		target := c.svnnwr_access_key(mut ctx, init, key) or { return false }
		return c.svnnwr_allowed(mut ctx, sv_es_ref(target), config, mut stats)
	}
	return false
}

// svnnwr_expression_value is hasRelExternal's expressionValue.
fn (mut c Checker) svnnwr_expression_value(ctx &SvnnwrContext, expression int) string {
	if s := c.svnnwr_static_string(ctx, expression) {
		return s
	}
	t := ctx.e.t
	if t.typ(expression) == .template_literal {
		quasis := t.list(expression, .quasis) or { []int{} }
		expressions := t.list(expression, .expressions) or { []int{} }
		mut out := ''
		for k, quasi in quasis {
			value := t.get(quasi, .value)
			if value is estree.TemplateValue {
				out += if value.has_cooked { value.cooked } else { value.raw }
			}
			if k < expressions.len {
				out += c.svnnwr_expression_value(ctx, expressions[k])
			}
		}
		return out
	}
	return '\x00'
}

// svnnwr_static_string: the static value of an expression when it is a string.
fn (mut c Checker) svnnwr_static_string(ctx &SvnnwrContext, node int) ?string {
	lint := ctx.b.lint_of(node)?
	ts := ctx.b.lint.ts_node(lint)?
	value := c.get_static_value(ts)
	if !value.found || value.value.kind != .string_ {
		return none
	}
	return stv_units_string(value.value.units)
}

// svnnwr_has_rel_external is hasRelExternal of a start tag.
fn (mut c Checker) svnnwr_has_rel_external(ctx &SvnnwrContext, start_tag int) bool {
	doc := c.svelte.doc
	for attr in doc.nodes[start_tag].attributes {
		n := doc.nodes[attr]
		if n.typ !in [.attribute, .shorthand_attribute] || c.sv_attribute_name(attr) != 'rel' {
			continue
		}
		mut value := ''
		if n.typ == .shorthand_attribute {
			value = if n.value_ref.es {
				c.svnnwr_expression_value(ctx, n.value_ref.idx)
			} else {
				''
			}
		} else {
			for part in n.values {
				p := doc.nodes[part]
				value += if p.typ == .literal {
					p.value
				} else if p.expression.es {
					c.svnnwr_expression_value(ctx, p.expression.idx)
				} else {
					''
				}
			}
		}
		return value.split_any(' \t\n\r\f\v ﻿').contains('external')
	}
	return false
}

fn (mut c Checker) lint_svelte_no_navigation_without_resolve(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	o := svnnwr_options(c.rule_options(svelte_no_navigation_without_resolve))!
	if !c.is_svelte() && !c.src.contains('\$app/navigation') {
		return []
	}
	if !c.svsc_kit_version_in(abs_path, ['1.0.0-next', '1', '2', '3']) {
		return []
	}
	e := c.svsc_es(root, abs_path) or { return [] }
	b := c.svsc_bridge(root, &e, abs_path) or { return [] }
	t := e.t
	// extractResolveReferences: `resolve` and `asset` of $app/paths.
	mut resolve := map[int]bool{}
	tree := c.scope_tree(root)
	for traced in c.es_esm_references(root, {
		'\$app/paths': EsTrace{
			esm:      true
			children: {
				'asset':   EsTrace{
					read: true
				}
				'resolve': EsTrace{
					read: true
				}
			}
		}
	}) {
		if node_kind(traced.node) == 'import_specifier' {
			v := c.svsc_import_variable(root, traced.node)
			if v < 0 {
				continue
			}
			for r in tree.variables[v].references {
				lint_node := c.es_index_of(b.lint, tree.references[r].identifier) or { continue }
				if b.lint.typ(lint_node) == .identifier {
					resolve[b.view_of(lint_node) or { continue }] = true
				}
			}
			continue
		}
		lint_node := c.es_index_of(b.lint, traced.node) or { continue }
		if b.lint.typ(lint_node) != .member_expression {
			continue
		}
		property := b.lint.node(lint_node, .property) or { continue }
		if b.lint.typ(property) == .identifier
			&& (b.lint.string_of(property, .name) or { '' }) == 'resolve' {
			resolve[b.view_of(property) or { continue }] = true
		}
	}
	mut ctx := SvnnwrContext{
		e:        e
		b:        b
		root:     root
		abs_path: abs_path
		typed:    c.scope_setup.type_information
		resolve:  resolve
	}
	mut findings := []Finding{}
	for traced in c.es_esm_references(root, {
		'\$app/navigation': EsTrace{
			esm:      true
			children: {
				'goto':         EsTrace{
					call: true
				}
				'pushState':    EsTrace{
					call: true
				}
				'replaceState': EsTrace{
					call: true
				}
			}
		}
	}) {
		name := traced.path.last()
		if (name == 'goto' && o.ignore_goto) || (name == 'pushState' && o.ignore_push_state)
			|| (name == 'replaceState' && o.ignore_replace_state) {
			continue
		}
		lint_call := c.es_index_of(b.lint, traced.node) or { continue }
		call := b.view_of(lint_call) or { continue }
		args := t.list(call, .arguments) or { continue }
		if args.len == 0 || args[0] < 0 {
			continue
		}
		ctx.visited = map[int]bool{}
		if !c.svnnwr_allowed(mut ctx, sv_es_ref(args[0]), SvnnwrConfig{
			empty: name != 'goto'
		}, mut stats) {
			findings << c.svsc_report(&e, args[0], match name {
				'goto' { 'gotoWithoutResolve' }
				'pushState' { 'pushStateWithoutResolve' }
				else { 'replaceStateWithoutResolve' }
			}, {})
		}
	}
	if !o.ignore_links && e.svelte {
		doc := c.svelte.doc
		for i in c.sv_snodes() {
			n := doc.nodes[i]
			mut value := svelte.Ref{}
			if n.typ == .shorthand_attribute {
				value = n.value_ref
			} else if n.typ == .attribute && n.values.len > 0 {
				first := doc.nodes[n.values[0]]
				value = if first.typ == .mustache_tag {
					first.expression
				} else {
					sv_snode_ref(n.values[0])
				}
			} else {
				continue
			}
			start_tag := n.parent
			if start_tag < 0 || doc.nodes[start_tag].parent < 0 {
				continue
			}
			element := doc.nodes[doc.nodes[start_tag].parent]
			if element.typ != .element || element.kind != 'html' || element.name_ref.es
				|| element.name_ref.idx < 0 || doc.nodes[element.name_ref.idx].typ != .name
				|| doc.nodes[element.name_ref.idx].name != 'a' || c.sv_attribute_name(i) != 'href'
				|| value.idx < 0 {
				continue
			}
			if c.svnnwr_has_rel_external(&ctx, start_tag) {
				continue
			}
			ctx.visited = map[int]bool{}
			if !c.svnnwr_allowed(mut ctx, value, SvnnwrConfig{
				absolute: true
				fragment: true
				nullish:  true
			}, mut stats) {
				findings << c.sv_report_snode(i, 'linkWithoutResolve', {})
			}
		}
	}
	return findings
}
