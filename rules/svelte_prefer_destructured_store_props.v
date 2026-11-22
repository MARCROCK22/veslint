module rules

import estree
import svelte

// Port of the `svelte/prefer-destructured-store-props` rule of eslint-plugin-svelte 3.24.1: a member
// access of a store outside the scripts (`{$foo.bar}`, `$foo['bar']`), whose identifiers all refer
// to top-level variables (or to none), is reported, with suggestions to use a `$: x = $foo.bar` /
// `$: ({ bar: x } = $foo)` variable that exists, or to add `$: ({ bar } = $foo);` at the end of the
// instance script. Runes are not stores in runes mode. It has no conditions: in a file without
// scripts (a .ts file) every such access is outside them.

const svpdsp_messages = {
	'useDestructuring':    'Destructure {{property}} from {{store}} for better change tracking & fewer redraws'
	'fixUseDestructuring': 'Using destructuring like \$: ({ {{property}} } = {{store}}); will run faster'
	'fixUseVariable':      'Using the predefined reactive variable {{variable}}'
}

// svpdsp_reserved is keyword.isReservedWordES6(name, true) or keyword.isRestrictedWord(name) of
// esutils.
fn svpdsp_reserved(name string) bool {
	return name in ['null', 'true', 'false', 'implements', 'interface', 'package', 'private',
		'protected', 'public', 'static', 'let', 'if', 'in', 'do', 'var', 'for', 'new', 'try', 'this',
		'else', 'case', 'void', 'with', 'enum', 'while', 'break', 'catch', 'throw', 'const', 'yield',
		'class', 'super', 'return', 'typeof', 'delete', 'switch', 'export', 'import', 'default',
		'finally', 'extends', 'function', 'continue', 'debugger', 'instanceof', 'eval', 'arguments']
}

// svpdsp_is_expression_identifier is isExpressionIdentifier (ast-utils.ts).
fn svpdsp_is_expression_identifier(t &estree.EsTree, id int, parent int) bool {
	if parent < 0 {
		return true
	}
	at := fn [t, id, parent] (key estree.Key) bool {
		return (t.node(parent, key) or { -1 }) == id
	}
	computed := t.flag(parent, .computed) or { false }
	return match t.typ(parent) {
		.member_expression { !computed || !at(.property) }
		.property, .method_definition, .property_definition { !computed || !at(.key) }
		.function_declaration, .function_expression, .class_declaration, .class_expression {
			!at(.id)
		}
		.labeled_statement, .break_statement, .continue_statement { !at(.label) }
		.meta_property { !at(.property) }
		.import_specifier { !at(.imported) }
		.export_specifier { !at(.exported) }
		else { true }
	}
}

// svpdsp_is_top_level: findVariable of the identifier gives no variable, or one of the module or
// global scope.
fn (mut c Checker) svpdsp_is_top_level(root C.vt_node, e &SvscEs, id int) bool {
	if e.svelte {
		v := c.sv_find_variable(id)
		if v < 0 {
			return true
		}
		info := &c.svelte.doc.scope
		return info.scopes[info.variables[v].scope].typ in ['module', 'global']
	}
	t := e.t
	ts := t.ts_node(id) or { return true }
	tree := c.scope_tree(root)
	name := t.string_of(id, .name) or { return true }
	scope := tree.get_scope(ts)
	mut v := tree.find_variable(scope, name, t.nodes[id].start)
	if v < 0 && name.starts_with('\$') {
		v = tree.find_variable(scope, name[1..], t.nodes[id].start)
	}
	if v < 0 {
		return true
	}
	return tree.scopes[tree.variables[v].scope].kind in [.esmodule, .global]
}

// svpdsp_property_name is getPropertyName of a Property of the document (no scope).
fn (c &Checker) svpdsp_property_name(property int) ?string {
	es := &c.svelte.doc.es
	key := es.node(property, .key)?
	if es.flag(property, .computed) or { false } {
		return c.sv_string_if_constant(key)
	}
	if es.typ(key) == .identifier {
		return es.string_of(key, .name)
	}
	if es.typ(key) == .literal {
		value := es.get(key, .value)
		if value is string {
			return value
		}
	}
	return none
}

// svpdsp_reactive_variables is findReactiveVariable: the variables `$: x = $foo.prop` or
// `$: ({ prop: x } = $foo)` define (identifiers of the document, without repeats).
fn (c &Checker) svpdsp_reactive_variables(object int, prop string) []int {
	doc := c.svelte.doc
	es := &doc.es
	info := &doc.scope
	v := c.sv_find_variable(object)
	if v < 0 {
		return []
	}
	object_name := es.string_of(object, .name) or { '' }
	is_reactive := fn [doc] (i int) bool {
		return i >= 0 && i in doc.reactive
	}
	mut out := []int{}
	for r in info.variables[v].references {
		id := info.references[r].identifier
		if es.typ(id) != .identifier || (es.string_of(id, .name) or { '' }) != object_name {
			continue
		}
		parent := es.nodes[id].parent
		if parent < 0 {
			continue
		}
		if es.typ(parent) == .member_expression && (es.node(parent, .object) or { -1 }) == id
			&& (c.svsc_property_name(parent) or { '\x00' }) == prop {
			assignment := es.nodes[parent].parent
			if assignment >= 0 && es.typ(assignment) == .assignment_expression
				&& (es.node(assignment, .right) or { -1 }) == parent {
				left := es.node(assignment, .left) or { continue }
				statement := es.nodes[assignment].parent
				if es.typ(left) == .identifier && statement >= 0
					&& es.typ(statement) == .expression_statement
					&& is_reactive(es.nodes[statement].parent) {
					if left !in out {
						out << left
					}
				}
			}
		} else if es.typ(parent) == .assignment_expression
			&& (es.node(parent, .right) or { -1 }) == id {
			left := es.node(parent, .left) or { continue }
			statement := es.nodes[parent].parent
			if es.typ(left) != .object_pattern || statement < 0
				|| es.typ(statement) != .expression_statement
				|| !is_reactive(es.nodes[statement].parent) {
				continue
			}
			for property in es.list(left, .properties) or { []int{} } {
				if es.typ(property) != .property {
					continue
				}
				value := es.node(property, .value) or { continue }
				if es.typ(value) == .identifier
					&& (c.svpdsp_property_name(property) or { '\x00' }) == prop {
					if value !in out {
						out << value
					}
					break
				}
			}
		}
	}
	return out
}

// svpdsp_may_have_store_access: the text has a `$` followed by the start of a name other than `$`
// (a `$foo` the rule may look at; the `${` of a template literal is not one).
fn svpdsp_may_have_store_access(src string) bool {
	mut i := src.index_u8(`$`)
	for i >= 0 && i + 1 < src.len {
		next := src[i + 1]
		if next.is_letter() || next == `_` || next >= 0x80 {
			return true
		}
		j := src[i + 1..].index_u8(`$`)
		i = if j < 0 { -1 } else { i + 1 + j }
	}
	return false
}

struct SvpdspAccess {
	node int
mut:
	identifiers []int
}

fn (mut c Checker) lint_svelte_prefer_destructured_store_props(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() && !svpdsp_may_have_store_access(c.src) {
		return []
	}
	e := c.svsc_es(root, abs_path) or { return [] }
	t := e.t
	runes := c.svsc_runes(abs_path) == .yes
	mut main_script := -1
	mut in_script := false
	mut stack := []SvpdspAccess{}
	mut reports := []int{}
	// The events: the document's (Svelte nodes too) for a .svelte file, the ESTree's otherwise.
	mut steps := []svelte.Ref{}
	mut leaves := []bool{}
	if e.svelte {
		for step in c.sv_steps() {
			steps << step.node
			leaves << step.leave
		}
	} else {
		for step in e.steps {
			steps << sv_es_ref(step.node)
			leaves << step.leave
		}
	}
	for k, ref in steps {
		leave := leaves[k]
		if !ref.es {
			if c.svelte.doc.nodes[ref.idx].typ == .script_element {
				in_script = !leave
				if !leave && !c.sv_is_module_script(ref.idx) {
					main_script = ref.idx
				}
			}
			continue
		}
		i := ref.idx
		if t.typ(i) == .member_expression {
			object := t.node(i, .object) or { -1 }
			name := if object >= 0 && t.typ(object) == .identifier {
				t.string_of(object, .name) or { '' }
			} else {
				''
			}
			if name.len >= 2 && name[0] == `$` && name[1] != `$` {
				if !leave {
					if !in_script && !(runes && name in sv_rune_names) {
						stack.insert(0, SvpdspAccess{
							node: i
						})
					}
				} else if stack.len > 0 && stack[0].node == i {
					access := stack[0]
					stack.delete(0)
					mut top_level := true
					for id in access.identifiers {
						if !svpdsp_is_expression_identifier(t, id, c.svsc_parent(&e, id)) {
							continue
						}
						if !c.svpdsp_is_top_level(root, &e, id) {
							top_level = false
							break
						}
					}
					if top_level {
						reports << i
					}
				}
			}
		}
		if !leave && t.typ(i) == .identifier && stack.len > 0 {
			stack[0].identifiers << i
		}
	}
	mut findings := []Finding{}
	for node in reports {
		object := t.node(node, .object) or { continue }
		property := t.node(node, .property) or { continue }
		store := t.string_of(object, .name) or { '' }
		computed := t.flag(node, .computed) or { false }
		mut suggestions := []Suggestion{}
		property_name := if computed { '' } else { t.string_of(property, .name) or { '' } }
		if !computed && e.svelte {
			for variable in c.svpdsp_reactive_variables(object, property_name) {
				variable_name := t.string_of(variable, .name) or { '' }
				suggestions << Suggestion{
					message_id: 'fixUseVariable'
					data:       {
						'variable': variable_name
					}
					fix:        fix_replace_range(t.nodes[node].start, t.nodes[node].end,
						variable_name)
				}
			}
			end_tag := if main_script >= 0 { c.svelte.doc.nodes[main_script].end_tag } else { -1 }
			if end_tag >= 0 {
				base := if property_name.starts_with('\$') {
					property_name[1..]
				} else {
					property_name
				}
				mut variable_name := base
				mut suffix := 0
				if svpdsp_reserved(variable_name) {
					suffix++
					variable_name = '${base}${suffix}'
				}
				tree := c.scope_tree(root)
				module_scope := if tree.scopes.len > 1 && tree.scopes[1].kind == .esmodule {
					1
				} else {
					-1
				}
				for tree.own_variable(0, variable_name) >= 0 || (module_scope >= 0
					&& tree.own_variable(module_scope, variable_name) >= 0) {
					suffix++
					variable_name = '${base}${suffix}'
				}
				at := c.svelte.doc.nodes[end_tag].start
				renamed := if property_name != variable_name { ': ${variable_name}' } else { '' }
				has, fix := c.merge_fixes([
					fix_insert_at(at, '\$: ({ ${property_name}${renamed} } = ${store});\n'),
					fix_replace_range(t.nodes[node].start, t.nodes[node].end, variable_name),
				]) or { false, Fix{} }
				if has {
					suggestions << Suggestion{
						message_id: 'fixUseDestructuring'
						data:       {
							'store':    store
							'property': property_name
						}
						fix:        fix
					}
				}
			}
		}
		shown := if computed {
			c.svsc_text(&e, property).split_any(' \t\n\r\f\v').filter(it != '').join(' ')
		} else {
			property_name
		}
		findings << Finding{
			...c.svsc_report(&e, node, 'useDestructuring', {
				'store':    store
				'property': shown
			})
			suggestions: suggestions
		}
	}
	return findings
}
