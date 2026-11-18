module rules

import estree
import time
import vue

// Port of the `vue/no-use-computed-property-like-method` rule of eslint-plugin-vue 10.12.1: a
// computed property called like a method (`this.foo()` in the Vue object, `foo()` in the template
// of the exported component) when the computed property cannot return a function: what its
// getter returns is decided through the variables it is assigned from, conditional and logical
// expressions, getStaticValue, the data, props (by their type constructors), computed properties
// and methods of the same component.

const vue_no_use_computed_property_like_method_messages = {
	'unexpected': 'Use {{ likeProperty }} instead of {{ likeMethod }}.'
}

// vucp_groups are GROUPS: the groups of the component whose properties may be functions.
const vucp_groups = ['data', 'props', 'computed', 'methods']

// vucp_native_not_function_types are NATIVE_NOT_FUNCTION_TYPES: prop types that are not
// functions.
const vucp_native_not_function_types = ['String', 'Number', 'BigInt', 'Boolean', 'Object', 'Array',
	'Symbol']

// vucp_non_function_expression_types are NON_FUNCTION_EXPRESSION_TYPES.
const vucp_non_function_expression_types = [estree.NodeType.object_expression, .array_expression,
	.literal, .template_literal, .binary_expression, .unary_expression, .update_expression]

// VucpFunction is a FunctionData: a computed property's getter or a method, and what it returns
// (-1 for a `return` without a value).
struct VucpFunction {
	name string
	kind string // 'methods' or 'computed'
	node int
mut:
	returns []int
	// cache is cacheMaybeReturnFunction: -1 for null, 0 false, 1 true.
	cache int = -1
}

// VucpCall is a CallMember, with the range of the call in file offsets.
struct VucpCall {
	name string
	// this_member: the callee is a MemberExpression (the message says `this.`).
	this_member bool
	start       int
	end         int
}

// VucpComponent is a ComponentStack.
struct VucpComponent {
	node  int
	upper int
mut:
	maybe_functions map[string]bool
	functions       []VucpFunction
	call_members    []VucpCall
	cache_exprs     map[int]bool
}

// VucpCtx is what the rule's functions share.
struct VucpCtx {
	root C.TSNode
	t    &estree.EsTree = unsafe { nil }
mut:
	components []VucpComponent
	findings   []Finding
}

fn (mut c Checker) lint_vue_no_use_computed_property_like_method(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	s := c.vue_script(root, abs_path) or { return []Finding{} }
	if s.objects.len == 0 {
		return []Finding{}
	}
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut x := VucpCtx{
		root: root
		t:    t
	}
	mut current := -1
	mut template_component := -1
	mut scope_stack := []int{}
	for step in t.steps() {
		node := step.node
		typ := t.typ(node)
		if step.leave {
			// defineVueVisitor calls ':function:exit' only inside a Vue object.
			if typ in [.function_expression, .function_declaration, .arrow_function_expression]
				&& s.owner_of(node) >= 0 && scope_stack.len > 0 {
				scope_stack.pop()
			}
			if current >= 0 && x.components[current].node == node {
				c.vucp_verify_component(mut x, current)
				current = x.components[current].upper
			}
			continue
		}
		if typ == .object_expression && s.object_type(node) != .none_ {
			x.components << c.vucp_component(x, node, current)
			current = x.components.len - 1
			if template_component < 0 && vucp_is_in_export_default(t, node) {
				template_component = current
			}
		}
		if s.owner_of(node) < 0 || current < 0 {
			continue
		}
		match typ {
			.function_expression, .function_declaration, .arrow_function_expression {
				scope_stack << node
			}
			.return_statement {
				if scope_stack.len > 0 {
					argument := t.node(node, .argument) or { -1 }
					for mut data in x.components[current].functions {
						if data.node == scope_stack.last() {
							data.returns << argument
							break
						}
					}
				}
			}
			.this_expression, .identifier {
				parent := t.nodes[node].parent
				if parent < 0 || t.typ(parent) != .member_expression
					|| (t.node(parent, .object) or { -1 }) != node {
					continue
				}
				call := t.nodes[parent].parent
				if call < 0 || t.typ(call) != .call_expression
					|| (t.node(call, .callee) or { -1 }) != parent || !c.vue_is_this(root, t, node) {
					continue
				}
				stats.checked++
				name := vue_static_property_name(t, parent) or { '' }
				if name != '' {
					x.components[current].call_members << VucpCall{
						name:        name
						this_member: true
						start:       t.nodes[call].start
						end:         t.nodes[call].end
					}
				}
			}
			else {}
		}
	}
	if template_component >= 0 && c.vue_has_template() {
		for call in c.vucp_template_calls() {
			stats.checked++
			c.vucp_verify_call_member(mut x, template_component, call)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return x.findings
}

// vucp_template_calls are the calls the VExpressionContainer listener verifies: a call whose
// callee is a reference of the container to no variable of the template.
fn (mut c Checker) vucp_template_calls() []VucpCall {
	doc := c.vue.doc
	roots := c.vue_template_roots()
	mut out := []VucpCall{}
	for i in c.vue_template_vnodes() {
		if doc.nodes[i].typ != .v_expression_container {
			continue
		}
		for r in doc.nodes[i].references {
			reference := &doc.references[r]
			if reference.variable >= 0 || reference.id.kind != .estree {
				continue
			}
			snippet := reference.id.snippet
			es := &doc.snippets[snippet].es
			id := reference.id.node
			parent := roots.parent(es, snippet, id)
			if parent < 0 || es.typ(parent) != .call_expression
				|| (es.node(parent, .callee) or { -1 }) != id {
				continue
			}
			start, end := c.vue_expr_range(vue.Expr{
				kind:    .estree
				snippet: snippet
				node:    parent
			})
			out << VucpCall{
				name:  vue_identifier_name(es, id)
				start: start
				end:   end
			}
		}
	}
	return out
}

// vucp_is_in_export_default ports isInExportDefault: an ancestor is the ExportDefaultDeclaration.
fn vucp_is_in_export_default(t &estree.EsTree, node int) bool {
	mut parent := t.nodes[node].parent
	for parent >= 0 {
		if t.typ(parent) == .export_default_declaration {
			return true
		}
		parent = t.nodes[parent].parent
	}
	return false
}

// vucp_component is the constructor of ComponentStack: what the data, props, computed properties
// and methods of the object may be.
fn (mut c Checker) vucp_component(x &VucpCtx, node int, upper int) VucpComponent {
	t := x.t
	mut comp := VucpComponent{
		node:  node
		upper: upper
	}
	for property in vue_iterate_properties(t, node, vucp_groups) {
		if property.kind == .array {
			continue
		}
		value := vue_property_value(t, property.property)
		match property.group {
			'data' {
				comp.maybe_functions[property.name] = c.vucp_can_be_function(x, value)
			}
			'props' {
				types := c.vucp_props_types(x, value)
				comp.maybe_functions[property.name] = if found := types {
					found.any(it !in vucp_native_not_function_types)
				} else {
					true
				}
			}
			'computed' {
				mut getter := value
				if value >= 0 && t.typ(value) == .object_expression {
					get := vue_find_property(t, value, 'get', none)
					if get >= 0 {
						getter = vue_property_value(t, get)
					}
				}
				vucp_process_function(t, property.name, getter, 'computed', mut comp)
			}
			'methods' {
				vucp_process_function(t, property.name, value, 'methods', mut comp)
				comp.maybe_functions[property.name] = true
			}
			else {}
		}
	}
	return comp
}

// vucp_process_function is processFunction.
fn vucp_process_function(t &estree.EsTree, name string, value int, kind string, mut comp VucpComponent) {
	if value < 0 {
		return
	}
	if t.typ(value) == .function_expression {
		comp.functions << VucpFunction{
			name: name
			kind: kind
			node: value
		}
	} else if t.typ(value) == .arrow_function_expression {
		mut data := VucpFunction{
			name: name
			kind: kind
			node: value
		}
		if t.flag(value, .expression) or { false } {
			data.returns << (t.node(value, .body) or { -1 })
		}
		comp.functions << data
	}
}

// vucp_resolved is resolvedExpressions: the expressions the value of `node` may come from.
fn (mut c Checker) vucp_resolved(x &VucpCtx, node int) []int {
	mut resolved := map[int][]int{}
	return c.vucp_resolved_internal(x, node, mut resolved)
}

// vucp_resolved_internal is resolvedExpressionsInternal: a node being resolved again (a cycle)
// resolves to what is known of it so far, or to itself when nothing is.
fn (mut c Checker) vucp_resolved_internal(x &VucpCtx, node int, mut resolved map[int][]int) []int {
	if node !in resolved {
		resolved[node] = []int{}
		c.vucp_extract_resolved(x, node, node, mut resolved)
	}
	if resolved[node].len == 0 {
		resolved[node] << node
	}
	return resolved[node].clone()
}

// vucp_add_resolved adds the expressions to the set of `key`.
fn vucp_add_resolved(key int, exprs []int, mut resolved map[int][]int) {
	for e in exprs {
		if e !in resolved[key] {
			resolved[key] << e
		}
	}
}

// vucp_extract_resolved is extractResolvedExpressions, adding to the set of `key` as the
// generator yields (a cycle back to `key` sees what was added before it).
fn (mut c Checker) vucp_extract_resolved(x &VucpCtx, key int, node int, mut resolved map[int][]int) {
	t := x.t
	match t.typ(node) {
		.identifier {
			v := c.vue_find_variable(x.root, t, node)
			if v < 0 {
				return
			}
			refs := c.scope_tree(x.root).variables[v].references.clone()
			for r in refs {
				id := c.es_index_of(t, c.scope_tree(x.root).references[r].identifier) or {
					continue
				}
				parent := t.nodes[id].parent
				if parent < 0 {
					continue
				}
				if t.typ(parent) == .variable_declarator {
					init := t.node(parent, .init) or { -1 }
					if (t.node(parent, .id) or { -1 }) == id && init >= 0 {
						sub := c.vucp_resolved_internal(x, init, mut resolved)
						vucp_add_resolved(key, sub, mut resolved)
					}
				} else if t.typ(parent) == .assignment_expression
					&& (t.node(parent, .left) or { -1 }) == id {
					right := t.node(parent, .right) or { continue }
					sub := c.vucp_resolved_internal(x, right, mut resolved)
					vucp_add_resolved(key, sub, mut resolved)
				}
			}
		}
		.conditional_expression {
			for field in [estree.Key.consequent, .alternate] {
				branch := t.node(node, field) or { continue }
				sub := c.vucp_resolved_internal(x, branch, mut resolved)
				vucp_add_resolved(key, sub, mut resolved)
			}
		}
		.logical_expression {
			for field in [estree.Key.left, .right] {
				side := t.node(node, field) or { continue }
				sub := c.vucp_resolved_internal(x, side, mut resolved)
				vucp_add_resolved(key, sub, mut resolved)
			}
		}
		else {}
	}
}

// vucp_props_types is getComponentPropsTypes of a prop's value: the names of its type
// constructors, none when they cannot be known.
fn (mut c Checker) vucp_props_types(x &VucpCtx, value int) ?[]string {
	t := x.t
	if value < 0 {
		return none
	}
	mut result := []string{}
	for expr in c.vucp_resolved(x, value) {
		mut type_exprs := []int{}
		if t.typ(expr) == .object_expression {
			typ := vue_find_property(t, expr, 'type', none)
			if typ < 0 {
				return none
			}
			type_exprs = c.vucp_resolved(x, vue_property_value(t, typ))
		} else {
			type_exprs = [expr]
		}
		for type_expr in type_exprs {
			if t.typ(type_expr) == .identifier {
				result << vue_identifier_name(t, type_expr)
			} else if t.typ(type_expr) == .array_expression {
				for element in t.list(type_expr, .elements) or { []int{} } {
					if element < 0 {
						continue
					}
					if t.typ(element) == .spread_element {
						return none
					}
					for element_expr in c.vucp_resolved(x, element) {
						if t.typ(element_expr) != .identifier {
							return none
						}
						result << vue_identifier_name(t, element_expr)
					}
				}
			} else {
				return none
			}
		}
	}
	return result
}

// vucp_can_be_function is canBeFunction: an expression it resolves to may be a function (its
// static value is unknown, or a function).
fn (mut c Checker) vucp_can_be_function(x &VucpCtx, node int) bool {
	t := x.t
	if node < 0 {
		return true
	}
	for expr in c.vucp_resolved(x, node) {
		typ := t.typ(expr)
		if typ in vucp_non_function_expression_types {
			continue
		}
		if typ == .conditional_expression
			&& !c.vucp_can_be_function(x, t.node(expr, .consequent) or { -1 })
			&& !c.vucp_can_be_function(x, t.node(expr, .alternate) or { -1 }) {
			continue
		}
		evaluated := c.un_static_value(t, expr)
		if !evaluated.found || evaluated.value.kind == .function_ {
			return true
		}
	}
	return false
}

// vucp_verify_component is verifyComponent.
fn (mut c Checker) vucp_verify_component(mut x VucpCtx, comp int) {
	for call in x.components[comp].call_members.clone() {
		c.vucp_verify_call_member(mut x, comp, call)
	}
}

// vucp_verify_call_member is verifyCallMember.
fn (mut c Checker) vucp_verify_call_member(mut x VucpCtx, comp int, call VucpCall) {
	f := vucp_find_function(x.components[comp], call.name, 'computed')
	if f < 0 || c.vucp_maybe_return_function(mut x, comp, f) {
		return
	}
	prefix := if call.this_member { 'this.' } else { '' }
	x.findings << c.vue_report(call.start, call.end, 'unexpected', {
		'likeProperty': '${prefix}${call.name}'
		'likeMethod':   '${prefix}${call.name}()'
	})
}

// vucp_find_function is the index of the first function of that name (and kind, when not
// empty), -1 for none.
fn vucp_find_function(comp &VucpComponent, name string, kind string) int {
	for i, data in comp.functions {
		if data.name == name && (kind == '' || data.kind == kind) {
			return i
		}
	}
	return -1
}

// vucp_maybe_return_function is FunctionData.maybeReturnFunction.
fn (mut c Checker) vucp_maybe_return_function(mut x VucpCtx, comp int, f int) bool {
	if x.components[comp].functions[f].cache >= 0 {
		return x.components[comp].functions[f].cache == 1
	}
	// Avoid infinite recursion.
	x.components[comp].functions[f].cache = 1
	mut result := false
	for value in x.components[comp].functions[f].returns.clone() {
		if value >= 0 && c.vucp_maybe_function_expression(mut x, comp, value) {
			result = true
			break
		}
	}
	x.components[comp].functions[f].cache = if result { 1 } else { 0 }
	return result
}

// vucp_maybe_function_expression is ComponentStack.maybeFunctionExpression.
fn (mut c Checker) vucp_maybe_function_expression(mut x VucpCtx, comp int, node int) bool {
	if node < 0 {
		return false
	}
	if cached := x.components[comp].cache_exprs[node] {
		return cached
	}
	// Avoid infinite recursion.
	x.components[comp].cache_exprs[node] = true
	mut result := false
	for expr in c.vucp_resolved(x, node) {
		if !c.vucp_can_be_function(x, expr) {
			continue
		}
		if c.vucp_expression_could_be_function(mut x, comp, expr) {
			result = true
			break
		}
	}
	x.components[comp].cache_exprs[node] = result
	return result
}

// vucp_expression_could_be_function is ComponentStack.expressionCouldBeFunction.
fn (mut c Checker) vucp_expression_could_be_function(mut x VucpCtx, comp int, expr int) bool {
	t := x.t
	match t.typ(expr) {
		.member_expression {
			if c.vue_is_this(x.root, t, t.node(expr, .object) or { -1 }) {
				name := vue_static_property_name(t, expr) or { '' }
				if name != '' && !c.vucp_maybe_function_property(mut x, comp, name) {
					return false
				}
			}
			return true
		}
		.call_expression {
			callee := t.node(expr, .callee) or { -1 }
			if callee >= 0 && t.typ(callee) == .member_expression
				&& c.vue_is_this(x.root, t, t.node(callee, .object) or { -1 }) {
				if name := vue_static_property_name(t, callee) {
					f := vucp_find_function(x.components[comp], name, '')
					if f >= 0 && x.components[comp].functions[f].kind == 'methods'
						&& !c.vucp_maybe_return_function(mut x, comp, f) {
						return false
					}
				}
			}
			return true
		}
		.conditional_expression {
			consequent := t.node(expr, .consequent) or { -1 }
			alternate := t.node(expr, .alternate) or { -1 }
			return c.vucp_maybe_function_expression(mut x, comp, consequent)
				|| c.vucp_maybe_function_expression(mut x, comp, alternate)
		}
		else {
			return true
		}
	}
}

// vucp_maybe_function_property is ComponentStack.maybeFunctionProperty.
fn (mut c Checker) vucp_maybe_function_property(mut x VucpCtx, comp int, name string) bool {
	if cached := x.components[comp].maybe_functions[name] {
		return cached
	}
	// Avoid infinite recursion.
	x.components[comp].maybe_functions[name] = true
	f := vucp_find_function(x.components[comp], name, '')
	result := if f >= 0 && x.components[comp].functions[f].kind == 'computed' {
		c.vucp_maybe_return_function(mut x, comp, f)
	} else {
		true
	}
	x.components[comp].maybe_functions[name] = result
	return result
}
