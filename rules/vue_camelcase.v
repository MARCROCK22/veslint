module rules

import estree
import jsregexp
import json2
import treesitter { node_parent }

// Port of the `camelcase` rule of ESLint 10.15.0 as `vue/camelcase` (eslint-plugin-vue 10.12.1's
// wrapCoreRule) runs it: its listeners on the template's snippets (vue_wrap.v), where
// getDeclaredVariables is the one of an eslint-scope analysis of the expression container (the
// scope tree of the snippet), and its `Program` listener, which wrapRuleModule moves to the root
// element of the template: there sourceCode.getScope(node) finds no scope of the template and
// gives the global scope of the script, so it reports the script's references to global
// variables (vncc_program). Options: allow, ignoreDestructuring, ignoreGlobals, ignoreImports and
// properties, over the rule's meta.defaultOptions.

const ccase_messages = {
	'notCamelCase':        "Identifier '{{name}}' is not in camel case."
	'notCamelCasePrivate': '#{{name}} is not in camel case.'
}

struct VnccOptions {
	allow                []string
	ignore_destructuring bool
	ignore_globals       bool
	ignore_imports       bool
	properties_never     bool
}

fn vncc_options(options []json2.Any) !VnccOptions {
	if options.len == 0 {
		return VnccOptions{}
	}
	first := options[0]
	if first !is map[string]json2.Any {
		return error('the option of `${vue_camelcase}` must be an object')
	}
	o := first as map[string]json2.Any
	mut allow := []string{}
	if list := o['allow'] {
		if list is []json2.Any {
			for item in list {
				if item is string {
					allow << item
				}
			}
		}
	}
	flag := fn [o] (key string) bool {
		value := o[key] or { return false }
		return value is bool && value
	}
	properties := o['properties'] or { json2.Any('always') }
	return VnccOptions{
		allow:                allow
		ignore_destructuring: flag('ignoreDestructuring')
		ignore_globals:       flag('ignoreGlobals')
		ignore_imports:       flag('ignoreImports')
		properties_never:     properties is string && properties == 'never'
	}
}

// vncc_is_underscored ports isUnderscored.
fn vncc_is_underscored(name string) bool {
	body := name.trim_left('_').trim_right('_')
	units := utf16_units(body)
	return body.contains('_') && jsregexp.js_to_upper(units) != units
}

// vncc_is_good_name ports isGoodName (with isAllowed: an entry equal to the name or a `u` regular
// expression it matches).
fn vncc_is_good_name(name string, o VnccOptions) bool {
	if !vncc_is_underscored(name) {
		return true
	}
	for entry in o.allow {
		if name == entry {
			return true
		}
		re := jsregexp.js_regex_new(entry, 'u') or { continue }
		if re.test(utf16_units(name)) or { false } {
			return true
		}
	}
	return false
}

// VnccCtx is what the listeners share: the tree, the options and the reported starts.
struct VnccCtx {
	t &estree.EsTree
	o VnccOptions
mut:
	reported map[int]bool
	findings []Finding
}

fn (mut x VnccCtx) report(c &Checker, node int) {
	start := x.t.nodes[node].start
	if start in x.reported {
		return
	}
	x.reported[start] = true
	x.findings << Finding{
		stmt:       c.es_tree_position(x.t, node)
		message_id: if x.t.typ(node) == .private_identifier {
			'notCamelCasePrivate'
		} else {
			'notCamelCase'
		}
		data:       {
			'name': x.t.string_of(node, .name) or { '' }
		}
	}
}

fn vncc_parent(t &estree.EsTree, node int) int {
	return t.nodes[node].parent
}

fn vncc_is(t &estree.EsTree, parent int, key estree.Key, node int) bool {
	return parent >= 0 && (t.node(parent, key) or { -1 }) == node
}

// vncc_is_assignment_target ports isAssignmentTarget.
fn vncc_is_assignment_target(t &estree.EsTree, node int) bool {
	parent := vncc_parent(t, node)
	if parent < 0 {
		return false
	}
	return match t.typ(parent) {
		.assignment_expression, .assignment_pattern {
			vncc_is(t, parent, .left, node)
		}
		.property {
			grand := vncc_parent(t, parent)
			grand >= 0 && t.typ(grand) == .object_pattern && vncc_is(t, parent, .value, node)
		}
		.array_pattern, .rest_element {
			true
		}
		else {
			false
		}
	}
}

// vncc_equals_to_original_name ports equalsToOriginalName.
fn vncc_equals_to_original_name(t &estree.EsTree, node int) bool {
	local := t.string_of(node, .name) or { '' }
	mut value := node
	if vncc_parent(t, node) >= 0 && t.typ(vncc_parent(t, node)) == .assignment_pattern {
		value = vncc_parent(t, node)
	}
	parent := vncc_parent(t, value)
	if parent < 0 {
		return false
	}
	match t.typ(parent) {
		.property {
			grand := vncc_parent(t, parent)
			key := t.node(parent, .key) or { return false }
			return grand >= 0 && t.typ(grand) in [.object_pattern, .object_expression]
				&& vncc_is(t, parent, .value, value) && !(t.flag(parent, .computed) or { false })
				&& t.typ(key) == .identifier && (t.string_of(key, .name) or { '' }) == local
		}
		.import_specifier {
			imported := t.node(parent, .imported) or { return false }
			name := if t.typ(imported) == .identifier {
				t.string_of(imported, .name) or { '' }
			} else {
				t.string_of(imported, .value) or { '' }
			}
			return vncc_is(t, parent, .local, node) && name == local
		}
		else {
			return false
		}
	}
}

// vncc_is_import_attribute_key ports isImportAttributeKey.
fn vncc_is_import_attribute_key(t &estree.EsTree, node int) bool {
	parent := vncc_parent(t, node)
	return parent >= 0 && t.typ(parent) == .import_attribute && vncc_is(t, parent, .key, node)
}

// report_reference_id ports reportReferenceId.
fn (mut x VnccCtx) report_reference_id(c &Checker, node int) {
	t := x.t
	parent := vncc_parent(t, node)
	if parent >= 0 && t.typ(parent) in [.call_expression, .new_expression] {
		return
	}
	if parent >= 0 && t.typ(parent) == .assignment_pattern && vncc_is(t, parent, .right, node) {
		return
	}
	if x.o.ignore_destructuring && vncc_equals_to_original_name(t, node) {
		return
	}
	if vncc_is_import_attribute_key(t, node) {
		return
	}
	x.report(c, node)
}

// vncc_declared_variables ports getDeclaredVariables of a declaration, a function, a class or a
// catch clause: the variables whose definitions that node makes.
fn vncc_declared_variables(tree &ScopeTree, t &estree.EsTree, node int) []int {
	ts := t.nodes[node].ts
	typ := t.typ(node)
	mut out := []int{}
	for v, variable in tree.variables {
		for def in variable.defs {
			hit := match typ {
				.variable_declaration {
					def.kind == .variable && if p := node_parent(def.node) {
						node_key(p) == node_key(ts)
					} else {
						false
					}
				}
				.catch_clause {
					def.kind == .catch_clause && node_key(def.node) == node_key(ts)
				}
				.class_declaration, .class_expression {
					def.kind == .class_name && node_key(def.node) == node_key(ts)
				}
				else {
					def.kind in [.parameter, .function_name] && node_key(def.node) == node_key(ts)
				}
			}
			if hit {
				out << v
				break
			}
		}
	}
	return out
}

// vncc_id_of is the ESTree Identifier of a variable's name or reference: of a shorthand
// property, which has its key and its value on the same tree-sitter node, the value.
fn (mut c Checker) vncc_id_of(t &estree.EsTree, n C.TSNode) ?int {
	id := c.es_index_of(t, n)?
	parent := vncc_parent(t, id)
	if parent >= 0 && t.typ(parent) == .property && vncc_is(t, parent, .key, id) {
		if value := t.node(parent, .value) {
			if t.nodes[value].start == t.nodes[id].start && t.typ(value) == .identifier {
				return value
			}
			if t.typ(value) == .assignment_pattern {
				left := t.node(value, .left) or { return id }
				if t.nodes[left].start == t.nodes[id].start {
					return left
				}
			}
		}
	}
	return id
}

fn (mut c Checker) lint_camelcase_base(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	o := vncc_options(c.rule_options(vue_wrap_camelcase))!
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	tree := c.scope_tree(t.nodes[t.root].ts)
	mut x := VnccCtx{
		t: t
		o: o
	}
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		parent := vncc_parent(t, node)
		match t.typ(node) {
			.variable_declaration, .function_declaration, .function_expression,
			.arrow_function_expression, .class_declaration, .class_expression, .catch_clause {
				stats.checked++
				for v in vncc_declared_variables(tree, t, node) {
					variable := tree.variables[v]
					if vncc_is_good_name(variable.name, o) || variable.identifiers.len == 0 {
						continue
					}
					id := c.vncc_id_of(t, variable.identifiers[0]) or { continue }
					if !(o.ignore_destructuring && vncc_equals_to_original_name(t, id)) {
						x.report(c, id)
					}
					for r in variable.references {
						reference := tree.references[r]
						if reference.init {
							continue
						}
						ref := c.vncc_id_of(t, reference.identifier) or { continue }
						x.report_reference_id(c, ref)
					}
				}
			}
			.identifier, .private_identifier {
				if parent < 0 || !vncc_is(t, parent, .key, node) && !vncc_is(t, parent, .property, node) {
					continue
				}
				computed := t.flag(parent, .computed) or { false }
				ptyp := t.typ(parent)
				grand := vncc_parent(t, parent)
				if ptyp == .member_expression {
					// MemberExpression[computed!=true] > Identifier.property
					if computed || t.typ(node) != .identifier || o.properties_never
						|| !vncc_is_assignment_target(t, parent)
						|| vncc_is_good_name(t.string_of(node, .name) or { '' }, o) {
						continue
					}
					x.report(c, node)
					continue
				}
				keyed := if t.typ(node) == .private_identifier {
					ptyp in [.method_definition, .property_definition]
				} else {
					!computed && (ptyp in [.method_definition, .property_definition]
						|| (ptyp == .property && grand >= 0 && t.typ(grand) == .object_expression))
				}
				if !keyed || o.properties_never || vncc_is_import_attribute_key(t, node)
					|| vncc_is_good_name(t.string_of(node, .name) or { '' }, o) {
					continue
				}
				x.report(c, node)
			}
			else {}
		}
	}
	return x.findings
}

// vncc_program ports the `Program` listener as it runs on the template: on the global scope of
// the script (its globals without declarations and the references that resolve to nothing).
fn (mut c Checker) vncc_program(root C.TSNode, abs_path string) ![]Finding {
	o := vncc_options(c.rule_options(vue_camelcase))!
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	tree := c.scope_tree(root)
	mut x := VnccCtx{
		t: t
		o: o
	}
	if tree.scopes.len == 0 {
		return []Finding{}
	}
	if !o.ignore_globals {
		for v in tree.scopes[tree.global_scope()].variables {
			variable := tree.variables[v]
			if variable.identifiers.len > 0 || vncc_is_good_name(variable.name, o) {
				continue
			}
			for r in variable.references {
				ref := c.vncc_id_of(t, tree.references[r].identifier) or { continue }
				x.report_reference_id(c, ref)
			}
		}
	}
	for r in tree.through {
		reference := tree.references[r]
		id := c.vncc_id_of(t, reference.identifier) or { continue }
		if vncc_is_good_name(reference.name, o) || vncc_is_import_attribute_key(t, id) {
			continue
		}
		x.report_reference_id(c, id)
	}
	return x.findings
}
