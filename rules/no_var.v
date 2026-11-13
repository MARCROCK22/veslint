module rules

import time
import treesitter { children, named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-var` rule of ESLint 10.6.0 (it has no options).

const nvar_messages = {
	'unexpectedVar': 'Unexpected var, use let or const instead.'
}

fn (mut c Checker) lint_no_var(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['variable_declaration', 'for_in_statement'], []) {
		// `for (var a in b)`: the declaration is part of the for-in for tree-sitter.
		mut var_token := node
		if node_kind(node) == 'for_in_statement' {
			kind := node_field(node, 'kind') or { continue }
			if node_kind(kind) != 'var' {
				continue
			}
			var_token = kind
		} else {
			var_token = children(node).filter(node_kind(it) == 'var')[0] or { continue }
		}
		stats.checked++
		// `declare global { var x }` is skipped.
		if node_kind(node) == 'variable_declaration' {
			if block := node_parent(node) {
				if node_kind(block) == 'statement_block' {
					if parent := node_parent(block) {
						if node_kind(parent) == 'ambient_declaration'
							&& children(parent).any(node_kind(it) == 'global') {
							continue
						}
					}
				}
			}
		}
		// A `declare var` is one ESTree node with its `declare`.
		mut estree := node
		if parent := node_parent(node) {
			if node_kind(parent) == 'ambient_declaration' {
				estree = parent
			}
		}
		has_fix := c.nvar_can_fix(root, node, estree)
		findings << Finding{
			stmt:       if node_kind(node) == 'for_in_statement' || node_key(estree) == node_key(node) {
				c.es_declaration_position(node)
			} else {
				position_of(estree)
			}
			message_id: 'unexpectedVar'
			has_fix:    has_fix
			fix:        if has_fix {
				Fix{node_start(var_token), node_end(var_token), 'let'}
			} else {
				Fix{}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nvar_is_block_statement: an ESTree BlockStatement (not the body of a static block or a
// namespace).
fn nvar_is_block_statement(n C.TSNode) bool {
	if node_kind(n) != 'statement_block' {
		return false
	}
	parent := node_parent(n) or { return true }
	return node_kind(parent) !in ['class_static_block', 'internal_module', 'module',
		'ambient_declaration']
}

// nvar_can_fix ports canFix. `node` is the declaration (or the for-in of `for (var a in b)`, the
// ESTree parent of its declaration) and `estree` the ESTree node of a declaration.
fn (mut c Checker) nvar_can_fix(root C.TSNode, node C.TSNode, estree C.TSNode) bool {
	tree := c.scope_tree(root)
	variables := c.es_declared_variables(root, node)
	loop_assignee := node_kind(node) == 'for_in_statement'
	parent := if loop_assignee { node } else { node_parent(estree) or { return false } }
	if node_kind(parent) in ['switch_case', 'switch_default'] {
		return false
	}
	if !loop_assignee {
		for declarator in named_children(node) {
			if node_kind(declarator) == 'variable_declarator'
				&& c.nvar_self_reference_in_tdz(root, declarator) {
				return false
			}
		}
	}
	// getScopeNode: the closest program, block, switch or loop.
	mut scope_node := node
	for {
		kind := node_kind(scope_node)
		if kind in ['program', 'switch_statement', 'for_statement', 'for_in_statement']
			|| nvar_is_block_statement(scope_node) {
			break
		}
		scope_node = node_parent(scope_node) or { break }
	}
	scope_start := node_start(scope_node)
	scope_end := c.es_end(scope_node)
	for v in variables {
		variable := tree.variables[v]
		if tree.scopes[variable.scope].kind == .global || variable.defs.len >= 2
			|| variable.name == 'let' {
			return false
		}
		for r in variable.references {
			id := tree.references[r].identifier
			if node_start(id) < scope_start || node_end(id) > scope_end {
				return false
			}
		}
		// hasReferenceBeforeDeclaration
		if variable.defs.len > 0 {
			declaration_start := node_start(variable.defs[0].node)
			for r in variable.references {
				if !tree.references[r].init
					&& node_start(tree.references[r].identifier) < declaration_start {
					return false
				}
			}
		}
	}
	if nvar_is_in_loop(estree) {
		for v in variables {
			if nvar_is_referenced_in_closure(tree, v) {
				return false
			}
		}
		if !loop_assignee {
			for declarator in named_children(node) {
				if node_kind(declarator) == 'variable_declarator'
					&& node_field(declarator, 'value') == none {
					return false
				}
			}
		}
	}
	if loop_assignee {
		return true
	}
	if node_kind(parent) == 'for_statement' {
		// The initializer, not the body.
		body := node_field(parent, 'body') or { return true }
		return node_key(body) != node_key(node)
	}
	return node_kind(parent) in ['program', 'statement_block']
}

// nvar_self_reference_in_tdz ports hasSelfReferenceInTDZ.
fn (mut c Checker) nvar_self_reference_in_tdz(root C.TSNode, declarator C.TSNode) bool {
	init := unwrap_parens(node_field(declarator, 'value') or { return false })
	tree := c.scope_tree(root)
	init_start := node_start(init)
	init_end := c.es_end(init)
	init_is_function := node_kind(init) in function_kinds
	for v in c.es_declared_variables(root, declarator) {
		variable := tree.variables[v]
		if variable.defs.len == 0 {
			continue
		}
		id := variable.defs[0].name
		id_start := node_start(id)
		mut default_value := ?C.TSNode(none)
		if id_parent := node_parent(id) {
			if node_kind(id_parent) in ['assignment_pattern', 'object_assignment_pattern'] {
				if left := node_field(id_parent, 'left') {
					if node_key(left) == node_key(id) {
						default_value = node_field(id_parent, 'right')
					}
				}
			}
		}
		for r in variable.references {
			reference := tree.references[r]
			if reference.init {
				continue
			}
			start := node_start(reference.identifier)
			end := node_end(reference.identifier)
			if start < id_start {
				return true
			}
			if dv := default_value {
				if start >= node_start(dv) && end <= c.es_end(dv) {
					return true
				}
			}
			if !init_is_function && start >= init_start && end <= init_end {
				return true
			}
		}
	}
	return false
}

// nvar_is_in_loop ports astUtils.isInLoop.
fn nvar_is_in_loop(n C.TSNode) bool {
	mut current := n
	for {
		kind := node_kind(current)
		if kind in function_kinds {
			return false
		}
		if kind in ['do_statement', 'for_statement', 'for_in_statement', 'while_statement'] {
			return true
		}
		current = node_parent(current) or { return false }
	}
	return false
}

// nvar_enclosing_function_scope ports getEnclosingFunctionScope.
fn nvar_enclosing_function_scope(tree &ScopeTree, scope int) int {
	mut s := scope
	for s > 0 && tree.scopes[s].kind != .function {
		s = tree.scopes[s].upper
	}
	return s
}

// nvar_is_referenced_in_closure ports isReferencedInClosure.
fn nvar_is_referenced_in_closure(tree &ScopeTree, v int) bool {
	enclosing := nvar_enclosing_function_scope(tree, tree.variables[v].scope)
	for r in tree.variables[v].references {
		if nvar_enclosing_function_scope(tree, tree.references[r].from) != enclosing {
			return true
		}
	}
	return false
}
