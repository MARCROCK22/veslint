module rules

import time
import treesitter { named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-unmodified-loop-condition` rule of ESLint 10.6.0 (it has no options).

const nulc_messages = {
	'loopConditionNotModified': "'{{name}}' is not modified in this loop."
}

// NulcCondition is a reference in the test of a loop: the loop, the outermost group (binary or
// conditional expression without dynamic parts) it belongs to, and whether a write modifies it.
struct NulcCondition {
	reference int
	loop      C.TSNode
	group     ?C.TSNode
mut:
	modified bool
}

fn (mut c Checker) lint_no_unmodified_loop_condition(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	tree := c.scope_tree(root)
	mut findings := []Finding{}
	mut groups := map[u64][]NulcCondition{}
	mut group_order := []u64{}
	for variable in tree.variables {
		stats.checked++
		mut conditions := []NulcCondition{}
		for r in variable.references {
			if condition := nulc_loop_condition(tree, r) {
				conditions << condition
			}
		}
		if conditions.len == 0 {
			continue
		}
		modifiers := variable.references.filter(nulc_is_write_reference(tree, it))
		for mut condition in conditions {
			for m in modifiers {
				if condition.modified {
					break
				}
				condition.modified = c.nulc_has_modifier_in_loop(tree, condition, m)
			}
		}
		for condition in conditions {
			if group := condition.group {
				key := node_key(group)
				if key !in groups {
					group_order << key
				}
				groups[key] << condition
			} else if !condition.modified {
				findings << c.nulc_report(tree, condition)
			}
		}
	}
	for key in group_order {
		conditions := groups[key]
		if conditions.all(!it.modified) {
			for condition in conditions {
				findings << c.nulc_report(tree, condition)
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) nulc_report(tree &ScopeTree, condition NulcCondition) Finding {
	id := tree.references[condition.reference].identifier
	return Finding{
		stmt:       position_of(id)
		message_id: 'loopConditionNotModified'
		data:       {
			'name': c.identifier_name(id)
		}
	}
}

// nulc_is_write_reference ports isWriteReference: the initializer of a declaration only counts for
// `var`.
fn nulc_is_write_reference(tree &ScopeTree, r int) bool {
	reference := tree.references[r]
	if reference.init {
		if reference.resolved < 0 || tree.variables[reference.resolved].defs.len == 0 {
			return false
		}
		def := tree.variables[reference.resolved].defs[0]
		if def.kind != .variable || def.parent_kind != 'var' {
			return false
		}
	}
	return reference.write
}

// nulc_is_sentinel: SENTINEL_PATTERN, a call, class, function, member, new or yield expression, a
// statement or a declaration.
fn nulc_is_sentinel(n C.TSNode) bool {
	kind := node_kind(n)
	if kind.ends_with('_statement') || kind.ends_with('_declaration') {
		return true
	}
	match kind {
		'call_expression' {
			// Not a tagged template nor `import()`.
			arguments := node_field(n, 'arguments') or { return false }
			callee := node_field(n, 'function') or { return false }
			return node_kind(arguments) != 'template_string' && node_kind(callee) != 'import'
		}
		'statement_block', 'member_expression', 'subscript_expression', 'new_expression',
		'yield_expression', 'class', 'function_expression', 'generator_function', 'arrow_function',
		'method_definition', 'internal_module', 'module', 'class_body' {
			return true
		}
		else {
			return false
		}
	}
}

// nulc_is_group: GROUP_PATTERN, a binary (not logical) or conditional expression.
fn nulc_is_group(n C.TSNode) bool {
	match node_kind(n) {
		'binary_expression' { return operator_of(n) !in ['&&', '||', '??'] }
		'ternary_expression' { return true }
		else { return false }
	}
}

// nulc_has_dynamic_expressions ports hasDynamicExpressions: a call, member, new, tagged template
// or yield expression, outside of functions and classes.
fn nulc_has_dynamic_expressions(n C.TSNode) bool {
	kind := node_kind(n)
	match kind {
		'call_expression' {
			callee := node_field(n, 'function') or { return true }
			if node_kind(callee) != 'import' {
				return true
			}
		}
		'member_expression', 'subscript_expression', 'new_expression', 'yield_expression' {
			return true
		}
		'arrow_function', 'function_expression', 'generator_function', 'class' {
			return false
		}
		else {}
	}
	for child in named_children(n) {
		if nulc_has_dynamic_expressions(child) {
			return true
		}
	}
	return false
}

// nulc_loop_condition ports toLoopCondition.
fn nulc_loop_condition(tree &ScopeTree, r int) ?NulcCondition {
	reference := tree.references[r]
	if reference.init {
		return none
	}
	mut group := ?C.TSNode(none)
	mut child := reference.identifier
	mut node := node_parent(child) or { return none }
	for {
		if node_kind(node) != 'parenthesized_expression' {
			if nulc_is_sentinel(node) {
				if node_kind(node) in ['while_statement', 'do_statement', 'for_statement'] {
					if test := node_field(node, 'condition') {
						if node_key(unwrap_parens(test)) == node_key(child)
							&& node_kind(unwrap_parens(test)) == node_kind(child) {
							return NulcCondition{
								reference: r
								loop:      node
								group:     group
							}
						}
					}
				}
				return none
			}
			if nulc_is_group(node) {
				if nulc_has_dynamic_expressions(node) {
					return none
				}
				group = node
			}
			child = node
		}
		node = node_parent(node) or { return none }
	}
	return none
}

// nulc_is_in_loop ports isInLoop: the reference is in the loop (not in the init of a `for`).
fn nulc_is_in_loop(loop C.TSNode, id C.TSNode) bool {
	if !(node_start(loop) <= node_start(id) && node_end(id) <= node_end(loop)) {
		return false
	}
	if node_kind(loop) == 'for_statement' {
		if init := node_field(loop, 'initializer') {
			if node_start(init) <= node_start(id) && node_end(id) <= node_end(init) {
				return false
			}
		}
	}
	return true
}

// nulc_has_modifier_in_loop ports hasModifierInLoop: the write is in the loop, or in a function
// declaration called in the loop.
fn (c &Checker) nulc_has_modifier_in_loop(tree &ScopeTree, condition NulcCondition, modifier int) bool {
	id := tree.references[modifier].identifier
	if nulc_is_in_loop(condition.loop, id) {
		return true
	}
	// getEncloseFunctionDeclaration
	mut node := id
	mut function := ?C.TSNode(none)
	for {
		if node_kind(node) in ['function_declaration', 'generator_function_declaration'] {
			function = node
			break
		}
		node = node_parent(node) or { break }
	}
	f := function or { return false }
	name_node := node_field(f, 'name') or { return false }
	name := c.identifier_name(name_node)
	// getVariableByName from the upper scope of the modifier's scope.
	mut scope := tree.scopes[tree.references[modifier].from].upper
	for scope >= 0 {
		if v := tree.scopes[scope].set[name] {
			for r in tree.variables[v].references {
				if nulc_is_in_loop(condition.loop, tree.references[r].identifier) {
					return true
				}
			}
			return false
		}
		scope = tree.scopes[scope].upper
	}
	return false
}
