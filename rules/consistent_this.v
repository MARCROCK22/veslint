module rules

import json2
import time
import treesitter { node_field, node_kind, position_of }

// Port of the `consistent-this` rule of ESLint 10.6.0, with its options (the aliases).

const cth_messages = {
	'aliasNotAssignedToThis': "Designated alias '{{name}}' is not assigned to 'this'."
	'unexpectedAlias':        "Unexpected alias '{{name}}' for 'this'."
}

// cth_aliases reads the aliases: names, "that" by default.
fn cth_aliases(options []json2.Any) ![]string {
	if options.len == 0 {
		return ['that']
	}
	mut out := []string{}
	for option in options {
		if option !is string {
			return error('the options of `${consistent_this}` must be names')
		}
		out << option.str()
	}
	return out
}

fn (mut c Checker) lint_consistent_this(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	aliases := cth_aliases(c.rule_options(consistent_this))!
	mut findings := []Finding{}
	kinds := ['variable_declarator', 'assignment_expression', 'augmented_assignment_expression',
		'function_declaration', 'function_expression', 'generator_function',
		'generator_function_declaration', 'method_definition']
	for node in c.nodes_of_kinds(root, kinds, []) {
		stats.checked++
		match node_kind(node) {
			'variable_declarator' {
				name := node_field(node, 'name') or { continue }
				value := node_field(node, 'value') or { continue }
				if node_kind(name) != 'identifier' {
					continue
				}
				cth_check(c, aliases, node, c.text(name), value, '', mut findings)
			}
			'assignment_expression', 'augmented_assignment_expression' {
				left := unwrap_parens(node_field(node, 'left') or { continue })
				right := node_field(node, 'right') or { continue }
				if node_kind(left) !in ['identifier', 'undefined'] {
					continue
				}
				cth_check(c, aliases, node, c.text(left), right, operator_of(node), mut
					findings)
			}
			else {
				c.cth_ensure_assigned(root, aliases, node, mut findings)
			}
		}
	}
	c.cth_ensure_assigned(root, aliases, root, mut findings)
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// cth_check ports checkAssignment: an alias is assigned `this` with `=`; nothing else is.
fn cth_check(c &Checker, aliases []string, node C.TSNode, name string, value C.TSNode, operator string, mut findings []Finding) {
	is_this := node_kind(unwrap_parens(value)) == 'this'
	if name in aliases {
		if !is_this || (operator != '' && operator != '=') {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'aliasNotAssignedToThis'
				data:       {
					'name': name
				}
			}
		}
	} else if is_this {
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'unexpectedAlias'
			data:       {
				'name': name
			}
		}
	}
}

// cth_ensure_assigned ports ensureWasAssigned: each alias of the scope (and of the module scope
// of a module) is initialized or assigned `this` in that scope.
fn (mut c Checker) cth_ensure_assigned(root C.TSNode, aliases []string, node C.TSNode, mut findings []Finding) {
	tree := c.scope_tree(root)
	scope := if node_kind(node) == 'program' {
		0
	} else {
		tree.get_scope(node_field(node, 'body') or { return })
	}
	mut scopes := [scope]
	if node_kind(node) == 'program' && tree.scopes.len > 1 && tree.scopes[1].kind == .esmodule {
		scopes << 1
	}
	for s in scopes {
		for alias in aliases {
			v := tree.own_variable(s, alias)
			if v < 0 {
				continue
			}
			variable := tree.variables[v]
			if variable.defs.any(node_kind(it.node) == 'variable_declarator'
				&& node_field(it.node, 'value') != none) {
				continue
			}
			assigned := variable.references.any(c.cth_assigns_this(tree, s, it))
			if !assigned {
				for def in variable.defs {
					findings << Finding{
						stmt:       position_of(def.node)
						message_id: 'aliasNotAssignedToThis'
						data:       {
							'name': alias
						}
					}
				}
			}
		}
	}
}

// cth_assigns_this: the reference, from that scope, writes `this` with `=`.
fn (c &Checker) cth_assigns_this(tree &ScopeTree, scope int, r int) bool {
	reference := tree.references[r]
	if reference.from != scope || !reference.write {
		return false
	}
	parent := cti_estree_parent(reference.identifier) or { return false }
	if node_kind(parent) != 'assignment_expression' {
		return false
	}
	right := node_field(parent, 'right') or { return false }
	return node_kind(unwrap_parens(right)) == 'this'
}
