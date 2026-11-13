module rules

import json2
import time
import treesitter { node_field, node_kind, node_parent, position_of }

// Port of the `no-inner-declarations` rule of ESLint 10.6.0.

const nid_messages = {
	'moveDeclToRoot': 'Move {{type}} declaration to {{body}} root.'
}

struct NidOptions {
	both     bool
	disallow bool // blockScopedFunctions: "disallow"
}

fn nid_options(options []json2.Any) !NidOptions {
	mode := if options.len > 0 { options[0] } else { json2.Any('functions') }
	if mode !is string || mode.str() !in ['functions', 'both'] {
		return error('the first option of `${no_inner_declarations}` must be "functions" or "both"')
	}
	o := option_object(no_inner_declarations, if options.len > 1 {
		options[1..]
	} else {
		[]json2.Any{}
	}, ['blockScopedFunctions'])!
	block_scoped := o.string_value('blockScopedFunctions', ['allow', 'disallow'])!
	return NidOptions{
		both:     mode.str() == 'both'
		disallow: block_scoped == 'disallow'
	}
}

fn (mut c Checker) lint_no_inner_declarations(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nid_options(c.rule_options(no_inner_declarations))!
	mut findings := []Finding{}
	mut kinds := ['function_declaration', 'generator_function_declaration']
	if o.both {
		kinds << ['variable_declaration', 'for_in_statement']
	}
	for node in c.nodes_of_kinds(root, kinds, []) {
		stats.checked++
		mut estree := node
		mut parent := node_parent(node) or { continue }
		mut position := if node_kind(node) == 'variable_declaration' {
			c.es_declaration_position(node)
		} else {
			position_of(node)
		}
		match node_kind(node) {
			'for_in_statement' {
				// `for (var a in b)`: the declaration is part of the for-in for tree-sitter.
				kind := node_field(node, 'kind') or { continue }
				if node_kind(kind) != 'var' {
					continue
				}
				parent = node
				position = c.es_declaration_position(node)
			}
			'function_declaration', 'generator_function_declaration' {
				tree := c.scope_tree(root)
				scope := tree.get_scope(node)
				if !o.disallow && c.ecma_version >= 2015
					&& tree.is_strict(tree.scopes[scope].upper) {
					continue
				}
			}
			else {
				// A `declare var` is one ESTree node with its `declare`.
				if node_kind(parent) == 'ambient_declaration' {
					estree = parent
					position = position_of(parent)
					parent = node_parent(parent) or { continue }
				}
			}
		}
		if nid_valid_parent(parent) {
			continue
		}
		findings << Finding{
			stmt:       position
			message_id: 'moveDeclToRoot'
			data:       {
				'type': if node_kind(node) in ['function_declaration', 'generator_function_declaration'] {
					'function'
				} else {
					'variable'
				}
				'body': nid_body_description(estree)
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nid_valid_parent: the program, an export, a static block or the body of a function.
fn nid_valid_parent(parent C.TSNode) bool {
	match node_kind(parent) {
		'program', 'export_statement' {
			return true
		}
		'statement_block' {
			owner := node_parent(parent) or { return false }
			return node_kind(owner) in function_kinds || node_kind(owner) == 'class_static_block'
		}
		else {
			return false
		}
	}
}

// nid_body_description ports getAllowedBodyDescription.
fn nid_body_description(node C.TSNode) string {
	mut current := node
	for {
		current = node_parent(current) or { break }
		if node_kind(current) == 'class_static_block' {
			return 'class static block body'
		}
		if node_kind(current) in function_kinds {
			return 'function body'
		}
	}
	return 'program'
}
