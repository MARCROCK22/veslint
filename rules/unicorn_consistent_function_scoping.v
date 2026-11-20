module rules

import estree
import json2
import time
import treesitter { node_kind, node_start }

// Port of the `unicorn/consistent-function-scoping` rule of eslint-plugin-unicorn 79.0.0, with its
// option `checkArrowFunctions`. The scopes are veslint's ScopeTree (scope.v), whose blocks are
// tree-sitter nodes: ucfs_acquire ports ScopeManager#acquire for an ESTree node.

const ucfs_messages = {
	'consistent-function-scoping': 'Move {{functionNameWithKind}} to the outer scope.'
}

// https://reactjs.org/docs/hooks-reference.html
const ucfs_react_hooks = ['useState', 'React.useState', 'useEffect', 'React.useEffect', 'useContext',
	'React.useContext', 'useReducer', 'React.useReducer', 'useCallback', 'React.useCallback', 'useMemo',
	'React.useMemo', 'useRef', 'React.useRef', 'useImperativeHandle', 'React.useImperativeHandle',
	'useLayoutEffect', 'React.useLayoutEffect', 'useDebugValue', 'React.useDebugValue']

fn ucfs_options(options []json2.Any) !bool {
	o := option_object(unicorn_consistent_function_scoping, options, ['checkArrowFunctions'])!
	if 'checkArrowFunctions' !in o.values {
		return true
	}
	return o.bool_value('checkArrowFunctions')!
}

fn (mut c Checker) lint_unicorn_consistent_function_scoping(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	check_arrow_functions := ucfs_options(c.rule_options(unicorn_consistent_function_scoping))!
	t := c.es_tree(root, abs_path) or { return findings }
	tree := c.scope_tree(root)
	for node in 0 .. t.nodes.len {
		if t.typ(node) !in [.function_declaration, .function_expression, .arrow_function_expression] {
			continue
		}
		stats.checked++
		if t.typ(node) == .arrow_function_expression && !check_arrow_functions {
			continue
		}
		if c.ucfs_should_skip_function(tree, t, node) {
			continue
		}
		findings << Finding{
			stmt:       c.un_function_head_location(t, node)
			message_id: 'consistent-function-scoping'
			data:       {
				'functionNameWithKind': c.un_function_name_with_kind(t, node)
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ucfs_acquire ports ScopeManager#acquire(node): the first scope the node creates, -1 if none. A
// tree-sitter node that several ESTree nodes are made from (a method and its function) creates
// the scopes of the innermost one.
fn (mut c Checker) ucfs_acquire(tree &ScopeTree, t &estree.EsTree, node int) int {
	if node < 0 {
		return -1
	}
	if t.typ(node) == .program {
		return 0
	}
	ts := t.ts_node(node) or { return -1 }
	if c.es_index_of(t, ts) or { -1 } != node {
		return -1
	}
	scopes := tree.scopes_of_block(ts) or { return -1 }
	return if scopes.len > 0 { scopes[0] } else { -1 }
}

// ucfs_acquire_ts is ScopeManager#acquire for a tree-sitter node (the `node` of a definition).
fn ucfs_acquire_ts(tree &ScopeTree, ts C.TSNode) int {
	scopes := tree.scopes_of_block(ts) or { return -1 }
	return if scopes.len > 0 { scopes[0] } else { -1 }
}

// ucfs_is_same_scope ports isSameScope: the same scope, or scopes of the same block.
fn ucfs_is_same_scope(tree &ScopeTree, a int, b int) bool {
	if a < 0 || b < 0 {
		return false
	}
	return a == b
		|| (node_key(tree.scopes[a].block) == node_key(tree.scopes[b].block)
			&& node_kind(tree.scopes[a].block) == node_kind(tree.scopes[b].block))
}

fn ucfs_is_same_scope_as_any(tree &ScopeTree, scopes []int, scope int) bool {
	return scopes.any(ucfs_is_same_scope(tree, it, scope))
}

// ucfs_check_references ports checkReferences.
fn (mut c Checker) ucfs_check_references(tree &ScopeTree, t &estree.EsTree, scope int, parent_scopes []int) bool {
	mut seen := map[int]bool{}
	for s in un_scopes(tree, scope) {
		for r in tree.scopes[s].references {
			v := tree.references[r].resolved
			if v < 0 || v in seen {
				continue
			}
			seen[v] = true
			variable := tree.variables[v]
			if c.ucfs_hit_reference(tree, variable, parent_scopes)
				|| ucfs_hit_definitions(tree, variable, parent_scopes)
				|| c.ucfs_hit_identifier(tree, t, variable, scope, parent_scopes) {
				return true
			}
		}
	}
	return false
}

fn (c &Checker) ucfs_hit_reference(tree &ScopeTree, variable ScopeVariable, parent_scopes []int) bool {
	for r in variable.references {
		if ucfs_is_same_scope_as_any(tree, parent_scopes, tree.references[r].from) {
			return true
		}
		// Skip a recursive function name.
		if variable.defs.len > 0 && variable.defs[0].kind == .function_name {
			continue
		}
		if ucfs_is_same_scope_as_any(tree, parent_scopes, variable.scope) {
			return true
		}
	}
	return false
}

fn ucfs_hit_definitions(tree &ScopeTree, variable ScopeVariable, parent_scopes []int) bool {
	return variable.defs.any(ucfs_is_same_scope_as_any(tree, parent_scopes, ucfs_acquire_ts(tree,
		it.node)))
}

// ucfs_hit_identifier looks for neighboring function definitions: the name or a parameter of a
// FunctionDeclaration next to the reference being checked.
fn (mut c Checker) ucfs_hit_identifier(tree &ScopeTree, t &estree.EsTree, variable ScopeVariable, scope int, parent_scopes []int) bool {
	for ts in variable.identifiers {
		identifier := un_node_by_range_index(t, node_start(ts)) or { continue }
		if t.typ(identifier) != .identifier || t.nodes[identifier].start != node_start(ts) {
			continue
		}
		parent := t.nodes[identifier].parent
		// Only look at identifiers that live in a FunctionDeclaration.
		if parent < 0 || t.typ(parent) != .function_declaration {
			continue
		}
		// A `FunctionDeclaration` always has its own scope.
		parent_scope := c.ucfs_acquire(tree, t, parent)
		if parent_scope < 0 {
			continue
		}
		// Ignore identifiers from our own scope.
		if ucfs_is_same_scope(tree, scope, parent_scope) {
			continue
		}
		if ucfs_is_same_scope_as_any(tree, parent_scopes, tree.scopes[parent_scope].upper) {
			return true
		}
	}
	return false
}

// ucfs_is_react_hook ports isReactHook for a scope whose block is `block`.
fn ucfs_is_react_hook(t &estree.EsTree, block int) bool {
	parent := t.nodes[block].parent
	if parent < 0 {
		return false
	}
	callee := t.node(parent, .callee) or { return false }
	return un_is_node_matches(t, callee, ucfs_react_hooks)
}

// ucfs_is_node_contains_lexical_this ports isNodeContainsLexicalThis: `this`, `super` or
// `new.target`, the bindings an arrow function inherits.
fn ucfs_is_node_contains_lexical_this(t &estree.EsTree, node int) bool {
	match t.typ(node) {
		.this_expression, .super {
			return true
		}
		.meta_property {
			meta := t.node(node, .meta) or { -1 }
			property := t.node(node, .property) or { -1 }
			if meta >= 0 && property >= 0 && t.string_of(meta, .name) or { '' } == 'new'
				&& t.string_of(property, .name) or { '' } == 'target' {
				return true
			}
		}
		// `this` inside non-arrow functions is rebound.
		.function_declaration, .function_expression {
			return false
		}
		// Class bodies create their own `this`, but computed keys and the superclass are evaluated
		// in the outer scope.
		.class_declaration, .class_expression {
			if super_class := t.node(node, .super_class) {
				if ucfs_is_node_contains_lexical_this(t, super_class) {
					return true
				}
			}
			body := t.node(node, .body) or { return false }
			for element in t.list(body, .body) or { []int{} } {
				if t.flag(element, .computed) or { false } {
					if key := t.node(element, .key) {
						if ucfs_is_node_contains_lexical_this(t, key) {
							return true
						}
					}
				}
			}
			return false
		}
		else {}
	}
	return t.children(node).any(ucfs_is_node_contains_lexical_this(t, it))
}

// ucfs_is_inside_hoisted_factory ports isInsideHoistedFactory: the factory of `jest.mock`,
// `vi.mock` or `vi.hoisted`.
fn ucfs_is_inside_hoisted_factory(t &estree.EsTree, node int) bool {
	mut current := node
	for t.nodes[current].parent >= 0 {
		parent := t.nodes[current].parent
		if t.typ(parent) == .call_expression && t.typ(un_unwrap_ts_expression(t, current)) in [
			.function_declaration,
			.function_expression,
			.arrow_function_expression,
		] {
			arguments := t.list(parent, .arguments) or { []int{} }
			callee := t.node(parent, .callee) or { -1 }
			if (arguments.len > 1 && arguments[1] == current
				&& un_is_node_matches(t, callee, ['jest.mock', 'vi.mock']))
				|| (arguments.len > 0 && arguments[0] == current
					&& un_is_node_matches(t, callee, ['vi.hoisted'])) {
				return true
			}
		}
		current = parent
	}
	return false
}

fn ucfs_is_loop_body_block(t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) != .block_statement {
		return false
	}
	parent := t.nodes[node].parent
	return parent >= 0 && t.typ(parent) in [.do_while_statement, .for_in_statement, .for_of_statement,
		.for_statement, .while_statement]
		&& t.node(parent, .body) or { -1 } == node
}

// ucfs_loop_body_block_chain ports getLoopBodyBlockChain.
fn ucfs_loop_body_block_chain(t &estree.EsTree, from int) []int {
	mut blocks := []int{}
	mut node := from
	for node >= 0 && t.typ(node) == .block_statement {
		blocks << node
		if ucfs_is_loop_body_block(t, node) {
			return blocks
		}
		node = t.nodes[node].parent
	}
	return []int{}
}

// ucfs_relevant_parent_scopes ports getRelevantParentScopes.
fn (mut c Checker) ucfs_relevant_parent_scopes(tree &ScopeTree, t &estree.EsTree, parent_scope int, block_node int) []int {
	mut parent_scopes := []int{}
	if parent_scope >= 0 {
		parent_scopes << parent_scope
	}
	chain := ucfs_loop_body_block_chain(t, block_node)
	if chain.len == 0 {
		return parent_scopes
	}
	loop_statement_scope := c.ucfs_acquire(tree, t, t.nodes[chain.last()].parent)
	if loop_statement_scope >= 0 {
		parent_scopes << loop_statement_scope
	}
	for block in chain {
		block_scope := c.ucfs_acquire(tree, t, block)
		if block_scope >= 0 {
			parent_scopes << block_scope
		}
	}
	return parent_scopes
}

fn ucfs_is_iife(t &estree.EsTree, node int) bool {
	if t.typ(node) !in [.function_expression, .arrow_function_expression] {
		return false
	}
	parent := t.nodes[node].parent
	return parent >= 0 && t.typ(parent) == .call_expression
		&& t.node(parent, .callee) or { -1 } == node
}

// ucfs_parent_after_nested_arrow_functions ports getParentNodeAfterNestedArrowFunctions: skips
// the arrow functions of `return next => action => { … }`.
fn ucfs_parent_after_nested_arrow_functions(t &estree.EsTree, parent_node int, node int) int {
	mut parent := parent_node
	if parent >= 0 && t.typ(parent) == .arrow_function_expression
		&& t.typ(node) == .arrow_function_expression {
		mut ancestor := parent
		for ancestor >= 0 && t.typ(ancestor) == .arrow_function_expression {
			ancestor = t.nodes[ancestor].parent
		}
		if ancestor >= 0 && t.typ(ancestor) == .return_statement {
			for t.typ(parent) == .arrow_function_expression {
				parent = t.nodes[parent].parent
			}
			if t.typ(parent) == .return_statement {
				parent = t.nodes[parent].parent
			}
		}
	}
	return parent
}

// ucfs_should_skip_function ports shouldSkipFunction.
fn (mut c Checker) ucfs_should_skip_function(tree &ScopeTree, t &estree.EsTree, node int) bool {
	scope := c.ucfs_acquire(tree, t, node)
	if scope < 0 || ucfs_is_inside_hoisted_factory(t, node) {
		return true
	}
	mut parent_node := t.nodes[node].parent
	mut block_node := -1
	// Skip over junk like the block statement inside of a function declaration or the pieces of
	// an arrow function.
	if parent_node >= 0 && t.typ(parent_node) == .variable_declarator {
		parent_node = t.nodes[parent_node].parent
	}
	if parent_node >= 0 && t.typ(parent_node) == .variable_declaration {
		parent_node = t.nodes[parent_node].parent
	}
	// Only skip a ReturnStatement for arrow functions.
	if parent_node >= 0 && t.typ(parent_node) == .return_statement
		&& t.typ(node) == .arrow_function_expression {
		parent_node = t.nodes[parent_node].parent
	}
	parent_node = ucfs_parent_after_nested_arrow_functions(t, parent_node, node)
	if parent_node >= 0 && t.typ(parent_node) == .block_statement {
		block_node = parent_node
		parent_node = t.nodes[parent_node].parent
	}
	parent_scope := c.ucfs_acquire(tree, t, parent_node)
	parent_scopes := c.ucfs_relevant_parent_scopes(tree, t, parent_scope, block_node)
	if parent_scopes.len == 0 || parent_scopes.any(tree.scopes[it].kind == .global)
		|| (parent_scope >= 0 && ucfs_is_react_hook(t, parent_node))
		|| (parent_scope >= 0 && ucfs_is_iife(t, parent_node)) {
		return true
	}
	// Checked last, since it walks the whole function body.
	return (t.typ(node) == .arrow_function_expression && ucfs_is_node_contains_lexical_this(t, node))
		|| c.ucfs_check_references(tree, t, scope, parent_scopes)
}
