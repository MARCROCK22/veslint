module rules

import time
import treesitter { children, named_children, node_field, node_kind, node_parent, position_of }

// Port of the `vars-on-top` rule of ESLint 10.6.0 (it has no options).

const vot_messages = {
	'top': "All 'var' declarations must be at the top of the function scope."
}

fn (mut c Checker) lint_vars_on_top(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['variable_declaration', 'for_in_statement'], []) {
		// `for (var a in b)`: the declaration is part of the for-in for tree-sitter, and is never
		// on top.
		if node_kind(node) == 'for_in_statement' {
			kind := node_field(node, 'kind') or { continue }
			if node_kind(kind) == 'var' {
				stats.checked++
				findings << Finding{
					stmt:       position_of(kind)
					message_id: 'top'
				}
			}
			continue
		}
		stats.checked++
		// A `declare var` is one ESTree node with its `declare`.
		mut estree := node
		mut parent := node_parent(node) or { continue }
		if node_kind(parent) == 'ambient_declaration' {
			estree = parent
			parent = node_parent(parent) or { continue }
		}
		mut on_top := false
		if node_kind(parent) == 'export_statement' {
			// globalVarCheck on the export and its parent (the program, or a namespace's body).
			if container := node_parent(parent) {
				on_top = vot_is_on_top(parent, container, false)
			}
			if !on_top {
				findings << Finding{
					stmt:       position_of(parent)
					message_id: 'top'
				}
			}
			continue
		}
		if node_kind(parent) == 'program' {
			on_top = vot_is_on_top(estree, parent, false)
		} else if node_kind(parent) == 'statement_block' {
			if owner := node_parent(parent) {
				if node_kind(owner) in function_kinds {
					on_top = vot_is_on_top(estree, parent, false)
				} else if node_kind(owner) == 'class_static_block' {
					on_top = vot_is_on_top(estree, parent, true)
				}
			}
		}
		if !on_top {
			findings << Finding{
				stmt:       position_of(estree)
				message_id: 'top'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vot_is_on_top ports isVarOnTop: only directives, imports (unless in a static block) and variable
// declarations come before the node in the body.
fn vot_is_on_top(node C.TSNode, body C.TSNode, static_block bool) bool {
	statements := named_children(body).filter(node_kind(it) != 'comment')
	mut i := 0
	if !static_block {
		for i < statements.len && (vot_looks_like_directive(statements[i])
			|| vot_looks_like_import(statements[i])) {
			i++
		}
	}
	for ; i < statements.len; i++ {
		if !vot_is_variable_declaration(statements[i]) {
			return false
		}
		if node_key(statements[i]) == node_key(node) {
			return true
		}
	}
	return false
}

fn vot_looks_like_directive(n C.TSNode) bool {
	if node_kind(n) != 'expression_statement' {
		return false
	}
	expressions := named_children(n).filter(node_kind(it) != 'comment')
	return expressions.len == 1 && node_kind(unwrap_parens(expressions[0])) == 'string'
}

fn vot_looks_like_import(n C.TSNode) bool {
	// `import a = require('b')` is a TSImportEqualsDeclaration.
	return node_kind(n) == 'import_statement'
		&& !children(n).any(node_kind(it) == 'import_require_clause')
}

// vot_is_variable_declaration: a VariableDeclaration (`declare` ones too) or an export of one.
fn vot_is_variable_declaration(n C.TSNode) bool {
	mut node := n
	if node_kind(node) == 'export_statement' {
		node = node_field(node, 'declaration') or { return false }
	}
	if node_kind(node) == 'ambient_declaration' {
		node = named_children(node).filter(node_kind(it) in ['variable_declaration',
			'lexical_declaration'])[0] or { return false }
	}
	return node_kind(node) in ['variable_declaration', 'lexical_declaration']
}
