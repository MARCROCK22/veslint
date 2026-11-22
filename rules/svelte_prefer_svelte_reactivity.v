module rules

import estree
import treesitter { named_children, node_field, node_kind, node_start }

// Port of the `svelte/prefer-svelte-reactivity` rule of eslint-plugin-svelte 3.24.1: an instance
// of the global Date, Map, Set, URL or URLSearchParams that is mutated (a setter method called, a
// URL part assigned) is reported, and in a `.svelte.[js|ts]` module also one constructed in an
// exported declaration or variable. Its condition is a component in runes mode or a module. It
// runs on the lint code (ReferenceTracker, scopes).

const svpsr_messages = {
	'mutableDateUsed':            'Found a mutable instance of the built-in Date class. Use SvelteDate instead.'
	'mutableMapUsed':             'Found a mutable instance of the built-in Map class. Use SvelteMap instead.'
	'mutableSetUsed':             'Found a mutable instance of the built-in Set class. Use SvelteSet instead.'
	'mutableURLUsed':             'Found a mutable instance of the built-in URL class. Use SvelteURL instead.'
	'mutableURLSearchParamsUsed': 'Found a mutable instance of the built-in URLSearchParams class. Use SvelteURLSearchParams instead.'
}

// svpsr_mutators are the methods whose call mutates an instance of each class.
const svpsr_mutators = {
	'Date':            ['setDate', 'setFullYear', 'setHours', 'setMilliseconds', 'setMinutes',
		'setMonth', 'setSeconds', 'setTime', 'setUTCDate', 'setUTCFullYear', 'setUTCHours',
		'setUTCMilliseconds', 'setUTCMinutes', 'setUTCMonth', 'setUTCSeconds', 'setYear']
	'Map':             ['clear', 'delete', 'set']
	'Set':             ['add', 'clear', 'delete']
	'URLSearchParams': ['append', 'delete', 'set', 'sort']
}

// svpsr_url_parts are the URL properties whose assignment mutates it.
const svpsr_url_parts = ['hash', 'host', 'hostname', 'href', 'password', 'pathname', 'port', 'protocol',
	'search', 'username']

// The rule runs ReferenceTracker's generators of @eslint-community/eslint-utils 4.9 the way it
// does: the checks of mutability iterate property references of a constructed instance with the
// tracker of the global references being iterated, so they share its variableStack; a check
// that stops at its first result (`.next().done`) leaves the variables it entered on the stack
// (its generator is not closed), and those are then skipped by the next checks (a second
// `new Map()` assigned to the same variable is not found mutable). SvpsrTracer replays that: one
// stack for the whole run, the global iteration calling the rule's body at each construction.

enum SvpsrMode {
	outer // iterateGlobalReferences: each construction runs the rule's body
	first // a `.next().done` check: stop at the first result, the stack left as it is
	all   // isURLMutable's for-of: every result (the iteration ends normally)
}

struct SvpsrTracer {
mut:
	stack    []int
	mode     SvpsrMode
	out      []EsTraced
	exported []int
	findings []Finding
}

// svpsr_yield is a result of the generators: true stops the iteration (a `first` check).
fn (mut c Checker) svpsr_yield(root C.vt_node, t &estree.EsTree, traced EsTraced, mut tr SvpsrTracer) bool {
	match tr.mode {
		.first {
			return true
		}
		.all {
			tr.out << traced
			return false
		}
		.outer {
			if traced.kind == 'construct' {
				c.svpsr_check(root, t, traced, mut tr)
			}
			return false
		}
	}
}

// svpsr_variable_refs is _iterateVariableReferences: on a stop the variable stays on the stack; at
// the end the top of the stack is popped (whichever variable it is).
fn (mut c Checker) svpsr_variable_refs(root C.vt_node, t &estree.EsTree, v int, path []string, trace EsTrace, report bool, mut tr SvpsrTracer) bool {
	if v in tr.stack {
		return false
	}
	tr.stack << v
	tree := c.scope_tree(root)
	for r in tree.variables[v].references {
		reference := tree.references[r]
		if !reference.read {
			continue
		}
		if report && trace.read && c.svpsr_yield(root, t, EsTraced{
			node: reference.identifier
			path: path
			kind: 'read'
		}, mut tr) {
			return true
		}
		if c.svpsr_property_refs(root, t, reference.identifier, path, trace, mut tr) {
			return true
		}
	}
	tr.stack.pop()
	return false
}

// svpsr_property_refs is _iteratePropertyReferences (es_trace_properties with generator stops).
fn (mut c Checker) svpsr_property_refs(root C.vt_node, t &estree.EsTree, from C.vt_node, path []string, trace EsTrace, mut tr SvpsrTracer) bool {
	mut node := from
	for es_is_pass_through(node) {
		node = cti_estree_parent(node) or { break }
		for node_kind(node) == 'sequence_expression' {
			outer := cti_estree_parent(node) or { break }
			if node_kind(outer) != 'sequence_expression' {
				break
			}
			node = outer
		}
	}
	parent := cti_estree_parent(node) or { return false }
	key := node_key(node)
	match node_kind(parent) {
		'member_expression', 'subscript_expression' {
			object := node_field(parent, 'object') or { return false }
			if node_key(unwrap_parens(object)) != key {
				return false
			}
			name := c.es_property_name_unscoped(parent) or { return false }
			next := trace.children[name] or { return false }
			mut next_path := path.clone()
			next_path << name
			if next.read && c.svpsr_yield(root, t, EsTraced{
				node: parent
				path: next_path
				kind: 'read'
			}, mut tr) {
				return true
			}
			return c.svpsr_property_refs(root, t, parent, next_path, next, mut tr)
		}
		'call_expression' {
			callee := node_field(parent, 'function') or { return false }
			args := node_field(parent, 'arguments') or { return false }
			if node_kind(args) == 'arguments' && node_key(unwrap_parens(callee)) == key && trace.call {
				return c.svpsr_yield(root, t, EsTraced{
					node: parent
					path: path
					kind: 'call'
				}, mut tr)
			}
		}
		'new_expression' {
			callee := node_field(parent, 'constructor') or { return false }
			if node_key(unwrap_parens(callee)) == key && trace.construct {
				return c.svpsr_yield(root, t, EsTraced{
					node: parent
					path: path
					kind: 'construct'
				}, mut tr)
			}
		}
		'assignment_expression' {
			right := node_field(parent, 'right') or { return false }
			if node_key(unwrap_parens(right)) == key {
				if c.svpsr_lhs_refs(root, t, node_field(parent, 'left') or { return false },
					path, trace, mut tr)
				{
					return true
				}
				return c.svpsr_property_refs(root, t, parent, path, trace, mut tr)
			}
		}
		'assignment_pattern', 'object_assignment_pattern' {
			right := node_field(parent, 'right') or { return false }
			if node_key(unwrap_parens(right)) == key {
				return c.svpsr_lhs_refs(root, t, node_field(parent, 'left') or { return false },
					path, trace, mut tr)
			}
		}
		'required_parameter', 'optional_parameter' {
			value := node_field(parent, 'value') or { return false }
			if node_key(unwrap_parens(value)) == key {
				return c.svpsr_lhs_refs(root, t, node_field(parent, 'pattern') or { return false },
					path, trace, mut tr)
			}
		}
		'variable_declarator' {
			value := node_field(parent, 'value') or { return false }
			if node_key(unwrap_parens(value)) == key {
				return c.svpsr_lhs_refs(root, t, node_field(parent, 'name') or { return false },
					path, trace, mut tr)
			}
		}
		else {}
	}
	return false
}

// svpsr_lhs_refs is _iterateLhsReferences (es_trace_lhs with generator stops).
fn (mut c Checker) svpsr_lhs_refs(root C.vt_node, t &estree.EsTree, pattern C.vt_node, path []string, trace EsTrace, mut tr SvpsrTracer) bool {
	match node_kind(pattern) {
		'identifier', 'shorthand_property_identifier_pattern' {
			tree := c.scope_tree(root)
			v := tree.find_variable(0, c.text(pattern), node_start(pattern))
			if v >= 0 {
				return c.svpsr_variable_refs(root, t, v, path, trace, false, mut tr)
			}
		}
		'object_pattern' {
			for property in named_children(pattern) {
				kind := node_kind(property)
				if kind !in ['pair_pattern', 'shorthand_property_identifier_pattern',
					'object_assignment_pattern'] {
					continue
				}
				name := c.es_static_key_name(property) or { continue }
				next := trace.children[name] or { continue }
				mut next_path := path.clone()
				next_path << name
				if next.read && c.svpsr_yield(root, t, EsTraced{
					node: property
					path: next_path
					kind: 'read'
				}, mut tr) {
					return true
				}
				value := match kind {
					'pair_pattern' { node_field(property, 'value') or { continue } }
					else { property }
				}
				if c.svpsr_lhs_refs(root, t, value, next_path, next, mut tr) {
					return true
				}
			}
		}
		'assignment_pattern', 'object_assignment_pattern' {
			return c.svpsr_lhs_refs(root, t, node_field(pattern, 'left') or { return false },
				path, trace, mut tr)
		}
		else {}
	}
	return false
}

// svpsr_is_mutable is isDateMutable and the others, with the shared stack.
fn (mut c Checker) svpsr_is_mutable(root C.vt_node, t &estree.EsTree, class string, ctor C.vt_node, mut tr SvpsrTracer) bool {
	mut children := map[string]EsTrace{}
	if class == 'URL' {
		for part in svpsr_url_parts {
			children[part] = EsTrace{
				read: true
			}
		}
	} else {
		for method in svpsr_mutators[class] or { []string{} } {
			children[method] = EsTrace{
				call: true
			}
		}
	}
	trace := EsTrace{
		children: children
	}
	saved_mode := tr.mode
	saved_out := tr.out.clone()
	defer {
		tr.mode = saved_mode
		tr.out = saved_out
	}
	if class != 'URL' {
		tr.mode = .first
		return c.svpsr_property_refs(root, t, ctor, []string{}, trace, mut tr)
	}
	// isURLMutable's for-of closes the generator when it returns: the stack is unwound either way.
	tr.mode = .all
	tr.out = []EsTraced{}
	depth := tr.stack.len
	c.svpsr_property_refs(root, t, ctor, []string{}, trace, mut tr)
	tr.stack.trim(depth)
	for traced in tr.out {
		member := c.es_index_of(t, traced.node) or { continue }
		parent := t.nodes[member].parent
		if parent >= 0 && t.typ(parent) == .assignment_expression
			&& (t.node(parent, .left) or { -1 }) == member {
			return true
		}
	}
	return false
}

// svpsr_check is the body of the rule's loop for a construction of a class.
fn (mut c Checker) svpsr_check(root C.vt_node, t &estree.EsTree, traced EsTraced, mut tr SvpsrTracer) {
	node := c.es_index_of(t, traced.node) or { return }
	class := traced.path[0]
	message_id := match class {
		'Date' { 'mutableDateUsed' }
		'Map' { 'mutableMapUsed' }
		'Set' { 'mutableSetUsed' }
		'URL' { 'mutableURLUsed' }
		else { 'mutableURLSearchParamsUsed' }
	}
	for container in tr.exported {
		if svpsr_is_in(t, node, container) {
			tr.findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: message_id
			}
		}
	}
	if c.svpsr_is_mutable(root, t, class, traced.node, mut tr) {
		tr.findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: message_id
		}
	}
}

// svpsr_definition_nodes are the def.node of the variable an identifier of the module refers to.
fn (mut c Checker) svpsr_definition_nodes(root C.vt_node, t &estree.EsTree, identifier int) []int {
	ts := t.ts_node(identifier) or { return [] }
	tree := c.scope_tree(root)
	name := t.string_of(identifier, .name) or { return [] }
	v := tree.find_variable(tree.get_scope(ts), name, t.nodes[identifier].start)
	if v < 0 {
		return []
	}
	mut out := []int{}
	for def in tree.variables[v].defs {
		out << c.es_index_of(t, def.node) or { continue }
	}
	return out
}

// svpsr_is_in is isIn: `haystack` is `needle` or one of its ancestors.
fn svpsr_is_in(t &estree.EsTree, needle int, haystack int) bool {
	mut node := needle
	for node >= 0 {
		if node == haystack {
			return true
		}
		node = t.nodes[node].parent
	}
	return false
}

fn (mut c Checker) lint_svelte_prefer_svelte_reactivity(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.svsc_runes_on(abs_path) {
		return []
	}
	t := c.es_tree(root, abs_path) or { return [] }
	mut exported := []int{}
	if sv_file_type(c.sv_file_path(abs_path)) == .module {
		for statement in t.list(t.root, .body) or { []int{} } {
			match t.typ(statement) {
				.export_named_declaration {
					if declaration := t.node(statement, .declaration) {
						exported << declaration
					}
					for specifier in t.list(statement, .specifiers) or { []int{} } {
						local := t.node(specifier, .local) or { continue }
						if t.typ(local) == .identifier {
							exported << c.svpsr_definition_nodes(root, t, local)
						}
					}
				}
				.export_default_declaration {
					declaration := t.node(statement, .declaration) or { continue }
					if t.typ(declaration) == .identifier {
						exported << c.svpsr_definition_nodes(root, t, declaration)
					} else {
						exported << declaration
					}
				}
				else {}
			}
		}
	}
	// iterateGlobalReferences, the rule's body run at each construction.
	tree := c.scope_tree(root)
	mut tr := SvpsrTracer{
		exported: exported
	}
	mut trace := map[string]EsTrace{}
	for class in ['Date', 'Map', 'Set', 'URL', 'URLSearchParams'] {
		trace[class] = EsTrace{
			construct: true
		}
	}
	for class in ['Date', 'Map', 'Set', 'URL', 'URLSearchParams'] {
		v := tree.own_variable(0, class)
		if es_is_modified_global(tree, v) {
			continue
		}
		c.svpsr_variable_refs(root, t, v, [class], trace[class], true, mut tr)
	}
	for name in ['global', 'globalThis', 'self', 'window'] {
		v := tree.own_variable(0, name)
		if es_is_modified_global(tree, v) {
			continue
		}
		c.svpsr_variable_refs(root, t, v, []string{}, EsTrace{ children: trace }, false, mut
			tr)
	}
	findings := tr.findings
	return c.svsc_moved(findings)
}
