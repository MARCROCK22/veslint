module rules

import time
import treesitter { node_end, node_field, node_kind, node_parent, node_start }

// Port of the `no-loop-func` rule of ESLint 10.6.0 (it has no options).

const nlf_messages = {
	'unsafeRefs': 'Function declared in a loop contains unsafe references to variable(s) {{ varNames }}.'
}

const nlf_functions = ['function_declaration', 'generator_function_declaration', 'function_expression',
	'generator_function', 'arrow_function', 'method_definition']

fn (mut c Checker) lint_no_loop_func(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut skipped := map[u64]bool{} // SKIPPED_IIFE_NODES
	for node in c.nodes_of_kinds(root, nlf_functions, []) {
		stats.checked++
		loop := nlf_containing_loop(node, skipped) or { continue }
		tree := c.scope_tree(root)
		scope := tree.function_scope_of(node)
		if scope < 0 {
			continue
		}
		references := tree.scopes[scope].through
		if !es_is_async_function(node) && !es_is_generator_function(node) && nlf_is_iife(node) {
			mut referenced := false
			if node_kind(node) in ['function_expression', 'generator_function'] {
				if name := node_field(node, 'name') {
					function_name := c.identifier_name(name)
					referenced = references.any(tree.references[it].name == function_name)
				}
			}
			if !referenced {
				skipped[node_key(node)] = true
				continue
			}
		}
		mut unsafe_names := []string{}
		for r in references {
			reference := tree.references[r]
			if reference.resolved < 0 || c.nlf_is_safe(tree, loop, reference, skipped) {
				continue
			}
			name := c.identifier_name(reference.identifier)
			if name !in unsafe_names {
				unsafe_names << name
			}
		}
		if unsafe_names.len > 0 {
			findings << Finding{
				stmt:       es_function_position(node)
				message_id: 'unsafeRefs'
				data:       {
					'varNames': "'${unsafe_names.join("', '")}'"
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nlf_is_iife ports isIIFE: a function or arrow expression that is the callee of a call.
fn nlf_is_iife(node C.TSNode) bool {
	if node_kind(node) !in ['function_expression', 'generator_function', 'arrow_function'] {
		return false
	}
	mut current := node
	mut parent := node_parent(current) or { return false }
	for node_kind(parent) == 'parenthesized_expression' {
		current = parent
		parent = node_parent(current) or { return false }
	}
	if node_kind(parent) != 'call_expression' {
		return false
	}
	callee := node_field(parent, 'function') or { return false }
	arguments := node_field(parent, 'arguments') or { return false }
	// A tagged template is not a CallExpression.
	return node_kind(arguments) != 'template_string' && node_key(callee) == node_key(current)
}

// nlf_containing_loop ports getContainingLoopNode.
fn nlf_containing_loop(node C.TSNode, skipped map[u64]bool) ?C.TSNode {
	mut current := node
	for {
		parent := node_parent(current) or { return none }
		match node_kind(parent) {
			'while_statement', 'do_statement' {
				return parent
			}
			'for_statement' {
				// `init` is outside of the loop.
				initializer := node_field(parent, 'initializer') or { return parent }
				if node_key(initializer) != node_key(current)
					|| node_kind(initializer) != node_kind(current) {
					return parent
				}
			}
			'for_in_statement' {
				// `right` is outside of the loop.
				right := node_field(parent, 'right') or { return parent }
				if node_key(right) != node_key(current) || node_kind(right) != node_kind(current) {
					return parent
				}
			}
			else {
				if node_kind(parent) in nlf_functions && !skipped[node_key(parent)] {
					return none
				}
			}
		}
		current = parent
	}
	return none
}

// nlf_top_loop ports getTopLoopNode.
fn nlf_top_loop(loop C.TSNode, border int, skipped map[u64]bool) C.TSNode {
	mut top := loop
	mut containing := ?C.TSNode(loop)
	for {
		node := containing or { break }
		if node_start(node) < border {
			break
		}
		top = node
		containing = nlf_containing_loop(node, skipped)
	}
	return top
}

// nlf_declaration is the VariableDeclaration of a definition: its kind and range ('' when it is
// not one).
fn (c &Checker) nlf_declaration(def ScopeDefinition) (string, int, int) {
	parent := es_def_parent(def) or { return '', 0, 0 }
	match node_kind(parent) {
		'variable_declaration' {
			return 'var', node_start(parent), c.es_end(parent)
		}
		'lexical_declaration' {
			kind_node := node_field(parent, 'kind') or { return '', 0, 0 }
			kind := c.text(kind_node)
			return if kind == 'await' { 'await using' } else { kind }, node_start(parent), c.es_end(parent)
		}
		'for_in_statement' {
			kind_node := node_field(parent, 'kind') or { return '', 0, 0 }
			left := node_field(parent, 'left') or { return '', 0, 0 }
			kind := c.text(kind_node)
			return if kind == 'await' {
				'await using'
			} else {
				kind
			}, node_start(kind_node), node_end(left)
		}
		else {
			return '', 0, 0
		}
	}
}

// nlf_is_safe ports isSafe.
fn (c &Checker) nlf_is_safe(tree &ScopeTree, loop C.TSNode, reference ScopeReference, skipped map[u64]bool) bool {
	variable := tree.variables[reference.resolved]
	mut kind := ''
	mut declaration_start := 0
	mut declaration_end := 0
	if variable.defs.len > 0 {
		kind, declaration_start, declaration_end = c.nlf_declaration(variable.defs[0])
	}
	if kind in ['const', 'using', 'await using'] {
		return true
	}
	// A `let` declared in the loop is a new binding on each iteration.
	if kind == 'let' && declaration_start > node_start(loop)
		&& declaration_end < c.es_end(loop) {
		return true
	}
	border := node_start(nlf_top_loop(loop, if kind == 'let' { declaration_end } else { 0 },
		skipped))
	variable_scope := tree.scopes[variable.scope].variable_scope
	for r in variable.references {
		upper := tree.references[r]
		if !upper.write {
			continue
		}
		if variable_scope == tree.scopes[upper.from].variable_scope
			&& node_start(upper.identifier) < border {
			continue
		}
		return false
	}
	return true
}
