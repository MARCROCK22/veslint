module rules

import estree
import json2
import treesitter { node_end, node_start }

// The dependencies of eslint-plugin-perfectionist 5.13.0 (utils/): the sorting nodes with
// dependencies (SortingNodeWithDependencies: what a node is known by, `dependencyNames`, and the
// names it uses, `dependencies`), computeDependenciesBySortingNode on the scopes of the file
// (computeDeepScopeReferences), populateSortingNodeGroupsWithDependencies, sortNodesByDependencies,
// computeNodesInCircularDependencies, isNodeDependentOnOtherNode and isNodeInsideDeferredFunction.
// A sorting node is its ESTree node (`node`), which keys the maps.

// PfDependencies holds the `dependencyNames` and the `dependencies` of the sorting nodes.
struct PfDependencies {
mut:
	names map[int][]string
	deps  map[int][]string
}

fn (d &PfDependencies) names_of(node int) []string {
	return d.names[node] or { []string{} }
}

fn (d &PfDependencies) deps_of(node int) []string {
	return d.deps[node] or { []string{} }
}

// pf_is_node_dependent_on_other_node ports isNodeDependentOnOtherNode: a name of the first node is
// a dependency of the second one.
fn (d &PfDependencies) pf_is_node_dependent_on_other_node(first int, second int) bool {
	if first == second {
		return false
	}
	deps := d.deps_of(second)
	return d.names_of(first).any(it in deps)
}

// pf_nodes_in_circular_dependencies ports computeNodesInCircularDependencies.
fn (d &PfDependencies) pf_nodes_in_circular_dependencies(elements []PfSortingNode) map[int]bool {
	mut state := PfCycleState{}
	for element in elements {
		if element.node !in state.visited {
			d.pf_cycles_dfs(elements, element.node, []int{}, mut state)
		}
	}
	return state.in_cycles
}

struct PfCycleState {
mut:
	in_cycles map[int]bool
	visiting  map[int]bool
	visited   map[int]bool
}

fn (d &PfDependencies) pf_cycles_dfs(elements []PfSortingNode, element int, path []int, mut state PfCycleState) {
	if element in state.visited {
		return
	}
	if element in state.visiting {
		start := path.index(element)
		if start != -1 {
			for node in path[start..] {
				state.in_cycles[node] = true
			}
		}
		return
	}
	state.visiting[element] = true
	mut current_path := path.clone()
	current_path << element
	for dependency in d.deps_of(element) {
		for candidate in elements {
			if candidate.node != element && dependency in d.names_of(candidate.node) {
				d.pf_cycles_dfs(elements, candidate.node, current_path.clone(), mut state)
				break
			}
		}
	}
	state.visiting.delete(element)
	state.visited[element] = true
}

// pf_sort_nodes_by_dependencies ports sortNodesByDependencies: each node after the nodes it
// depends on (but those in circular dependencies).
fn (d &PfDependencies) pf_sort_nodes_by_dependencies(nodes []PfSortingNode, ignore_eslint_disabled bool) []PfSortingNode {
	circular := d.pf_nodes_in_circular_dependencies(nodes)
	mut result := []PfSortingNode{}
	mut visited := map[int]bool{}
	for node in nodes {
		d.pf_visit_by_dependencies(nodes, node, circular, ignore_eslint_disabled, mut visited, mut
			result)
	}
	return result
}

fn (d &PfDependencies) pf_visit_by_dependencies(nodes []PfSortingNode, sorting_node PfSortingNode, circular map[int]bool, ignore_eslint_disabled bool, mut visited map[int]bool, mut result []PfSortingNode) {
	if sorting_node.node in visited {
		return
	}
	for node in nodes {
		if node.node in circular || !d.pf_is_node_dependent_on_other_node(node.node, sorting_node.node) {
			continue
		}
		if !ignore_eslint_disabled || !node.is_eslint_disabled {
			d.pf_visit_by_dependencies(nodes, node, circular, ignore_eslint_disabled, mut visited, mut
				result)
		}
	}
	visited[sorting_node.node] = true
	result << sorting_node
}

// pf_first_unordered_node_dependent_on ports getFirstUnorderedNodeDependentOn of reportAllErrors:
// the first node that depends on `node` (not in a circular dependency) and is before it.
fn (d &PfDependencies) pf_first_unordered_node_dependent_on(node PfSortingNode, nodes []PfSortingNode, circular map[int]bool) ?PfSortingNode {
	index_of_node := nodes.map(it.node).index(node.node)
	for index, current in nodes {
		if current.node in circular || !d.pf_is_node_dependent_on_other_node(node.node, current.node) {
			continue
		}
		if index < index_of_node {
			return current
		}
	}
	return none
}

// pf_populate_dependencies ports populateSortingNodeGroupsWithDependencies: the dependencies of
// each node are the dependency names of the nodes it references.
fn (mut d PfDependencies) pf_populate_dependencies(nodes []PfSortingNode, dependencies_by_node map[int][]int) {
	for node in nodes {
		mut deps := []string{}
		if referenced := dependencies_by_node[node.node] {
			for other in referenced {
				deps << d.names_of(other)
			}
		}
		d.deps[node.node] = deps
	}
}

// --- Dependencies from the scopes ----------------------------------------------------------------

// PfDependencyComputers are the optional callbacks of computeDependenciesBySortingNode (nil when
// not given): shouldIgnoreSortingNodeComputer, shouldIgnoreIdentifierComputer (with the ESTree
// identifier, -1 when the reference has none) and additionalIdentifierDependenciesComputer (with
// the reference, an index into the ScopeTree).
struct PfDependencyComputers {
	should_ignore_sorting_node fn (node PfSortingNode) bool                                  = unsafe { nil }
	should_ignore_identifier   fn (identifier int, referencing PfSortingNode) bool           = unsafe { nil }
	additional                 fn (reference int, referencing PfSortingNode) []PfSortingNode = unsafe { nil }
}

// pf_dependencies_by_sorting_node ports computeDependenciesBySortingNode of utils/: for each node
// that references something, the other nodes that declare what it references (in the order of the
// references, with repetitions).
fn (ctx &PfContext) pf_dependencies_by_sorting_node(tree &ScopeTree, sorting_nodes []PfSortingNode, computers PfDependencyComputers) map[int][]int {
	mut out := map[int][]int{}
	references := ctx.pf_deep_scope_references(tree, sorting_nodes.map(it.node))
	for reference in references {
		ref := tree.references[reference]
		if ref.resolved < 0 {
			continue
		}
		identifier_start := node_start(ref.identifier)
		identifier_end := node_end(ref.identifier)
		referencing := pf_sorting_node_containing(ctx.t, sorting_nodes, identifier_start,
			identifier_end) or { continue }
		if computers.should_ignore_sorting_node != unsafe { nil }
			&& computers.should_ignore_sorting_node(referencing) {
			continue
		}
		mut referenced_nodes := out[referencing.node] or { []int{} }
		referenced_nodes << ctx.pf_main_identifier_dependencies(tree, sorting_nodes, computers,
			referencing, ref)
		if computers.additional != unsafe { nil } {
			for node in computers.additional(reference, referencing) {
				referenced_nodes << node.node
			}
		}
		out[referencing.node] = referenced_nodes
	}
	return out
}

// pf_main_identifier_dependencies ports computeMainIdentifierDependencies: the node that declares
// the variable the reference resolves to, if it is another node.
fn (ctx &PfContext) pf_main_identifier_dependencies(tree &ScopeTree, sorting_nodes []PfSortingNode, computers PfDependencyComputers, referencing PfSortingNode, ref ScopeReference) []int {
	if computers.should_ignore_identifier != unsafe { nil } {
		identifier := pf_estree_identifier_at(ctx.t, node_start(ref.identifier)) or { -1 }
		if computers.should_ignore_identifier(identifier, referencing) {
			return []int{}
		}
	}
	variable := tree.variables[ref.resolved]
	if variable.identifiers.len == 0 {
		return []int{}
	}
	first := variable.identifiers[0]
	referenced := pf_sorting_node_containing(ctx.t, sorting_nodes, node_start(first),
		node_end(first)) or { return []int{} }
	if computers.should_ignore_sorting_node != unsafe { nil }
		&& computers.should_ignore_sorting_node(referenced) {
		return []int{}
	}
	if referenced.node == referencing.node {
		return []int{}
	}
	return [referenced.node]
}

// pf_sorting_node_containing ports findSortingNodeContainingIdentifier: the first node whose
// range contains [start, end).
fn pf_sorting_node_containing(t &estree.EsTree, sorting_nodes []PfSortingNode, start int, end int) ?PfSortingNode {
	for sorting_node in sorting_nodes {
		if t.nodes[sorting_node.node].start <= start && t.nodes[sorting_node.node].end >= end {
			return sorting_node
		}
	}
	return none
}

// pf_estree_identifier_at is the ESTree node of a reference's identifier: the innermost node at
// its start.
fn pf_estree_identifier_at(t &estree.EsTree, start int) ?int {
	return un_node_by_range_index(t, start)
}

// pf_deep_scope_references ports computeDeepScopeReferences: the references in the range of the
// nodes, of the scope of each node and of its child scopes that overlap that range, depth first.
fn (ctx &PfContext) pf_deep_scope_references(tree &ScopeTree, nodes []int) []int {
	if nodes.len == 0 {
		return []int{}
	}
	mut range_start := ctx.t.nodes[nodes[0]].start
	mut range_end := ctx.t.nodes[nodes[0]].end
	for node in nodes {
		if ctx.t.nodes[node].start < range_start {
			range_start = ctx.t.nodes[node].start
		}
		if ctx.t.nodes[node].end > range_end {
			range_end = ctx.t.nodes[node].end
		}
	}
	mut visited := map[int]bool{}
	mut references := []int{}
	for node in nodes {
		ts := ctx.t.ts_node(node) or { continue }
		pf_collect_scope_references(tree, tree.get_scope(ts), range_start, range_end, mut visited, mut
			references)
	}
	return references
}

fn pf_collect_scope_references(tree &ScopeTree, scope int, range_start int, range_end int, mut visited map[int]bool, mut references []int) {
	if scope in visited {
		return
	}
	visited[scope] = true
	for reference in tree.scopes[scope].references {
		identifier := tree.references[reference].identifier
		if range_start <= node_start(identifier) && range_end >= node_end(identifier) {
			references << reference
		}
	}
	for child in tree.scopes[scope].children {
		if range_start < tree.scopes[child].end && tree.scopes[child].start < range_end {
			pf_collect_scope_references(tree, child, range_start, range_end, mut visited, mut
				references)
		}
	}
}

// --- Deferred functions ----------------------------------------------------------------------------

// pf_parent_nodes_with_types ports computeParentNodesWithTypes: the ancestors of the node (below
// max_parent) of those types; with consecutive_only, up to the first one of another type.
fn pf_parent_nodes_with_types(t &estree.EsTree, node int, max_parent int, allowed_types []estree.NodeType, consecutive_only bool) []int {
	mut out := []int{}
	mut parent := t.nodes[node].parent
	for parent >= 0 {
		if parent == max_parent {
			break
		}
		if t.typ(parent) in allowed_types {
			out << parent
		} else if consecutive_only {
			break
		}
		parent = t.nodes[parent].parent
	}
	return out
}

// pf_is_node_immediately_called ports isNodeImmediatelyCalled: the function is the callee of a
// call or a `new`.
fn pf_is_node_immediately_called(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) !in [.call_expression, .new_expression] {
		return false
	}
	callee := t.node(parent, .callee) or { return false }
	return callee == node
}

// pf_is_node_inside_deferred_function ports isNodeInsideDeferredFunction: the node is in a callback
// of a call whose callee matches ignoreCallbackDependenciesPatterns, or in a function (below
// max_parent) that is neither called right away nor an argument of a call.
fn pf_is_node_inside_deferred_function(t &estree.EsTree, ignore_callback_dependencies_patterns json2.Any, max_parent int, node int) !bool {
	if pf_truthy(ignore_callback_dependencies_patterns) {
		for call in pf_parent_nodes_with_types(t, node, max_parent, [.call_expression], false) {
			callee := t.node(call, .callee) or { continue }
			// 'name' in callExpression.callee: an Identifier (or a JSXIdentifier, a
			// PrivateIdentifier…).
			name := t.string_of(callee, .name) or { continue }
			if pf_matches(name, ignore_callback_dependencies_patterns)! {
				return true
			}
		}
	}
	for function in pf_parent_nodes_with_types(t, node, max_parent, [
		.function_expression,
		.arrow_function_expression,
	], false) {
		if pf_is_node_immediately_called(t, function) {
			continue
		}
		parent := t.nodes[function].parent
		if parent < 0 || t.typ(parent) != .call_expression {
			return true
		}
	}
	return false
}
