module rules

import estree
import json2
import treesitter { node_start }
import time

// Port of the `perfectionist/sort-classes` rule of eslint-plugin-perfectionist 5.13.0 (with
// rules/sort-classes/): the members of a class body sorted with the shared engine
// (perfectionist_utils*.v) by their groups (selectors and modifiers), in partitions, after the
// members they depend on (the experimental dependency detection on the scopes of the file, or the
// deprecated one), the overload signatures of a method kept with its implementation, with all its
// options, the `perfectionist` settings and the fixes.

const pfsc_messages = {
	'unexpectedClassesDependencyOrder': 'Expected dependency "{{right}}" to come before "{{nodeDependentOnRight}}".'
	'missedSpacingBetweenClassMembers': 'Missed spacing between "{{left}}" and "{{right}}".'
	'extraSpacingBetweenClassMembers':  'Extra spacing between "{{left}}" and "{{right}}".'
	'unexpectedClassesGroupOrder':      'Expected "{{right}}" ({{rightGroup}}) to come before "{{left}}" ({{leftGroup}}).'
	'unexpectedClassesOrder':           'Expected "{{right}}" to come before "{{left}}".'
}

const pfsc_message_ids = PfMessageIds{
	missed_spacing:              'missedSpacingBetweenClassMembers'
	extra_spacing:               'extraSpacingBetweenClassMembers'
	unexpected_dependency_order: 'unexpectedClassesDependencyOrder'
	unexpected_group_order:      'unexpectedClassesGroupOrder'
	unexpected_order:            'unexpectedClassesOrder'
}

// pfsc_all_selectors and pfsc_all_modifiers are allSelectors and allModifiers of
// sort-classes/types.ts.
const pfsc_all_selectors = ['accessor-property', 'index-signature', 'constructor', 'static-block',
	'get-method', 'set-method', 'function-property', 'property', 'method']
const pfsc_all_modifiers = ['async', 'protected', 'private', 'public', 'static', 'abstract', 'override',
	'readonly', 'decorated', 'declare', 'optional']

const pfsc_default_options = '{"groups":["index-signature",["static-property","static-accessor-property"],["static-get-method","static-set-method"],["protected-static-property","protected-static-accessor-property"],["protected-static-get-method","protected-static-set-method"],["private-static-property","private-static-accessor-property"],["private-static-get-method","private-static-set-method"],"static-block",["property","accessor-property"],["get-method","set-method"],["protected-property","protected-accessor-property"],["protected-get-method","protected-set-method"],["private-property","private-accessor-property"],["private-get-method","private-set-method"],"constructor",["static-method","static-function-property"],["protected-static-method","protected-static-function-property"],["private-static-method","private-static-function-property"],["method","function-property"],["protected-method","protected-function-property"],["private-method","private-function-property"],"unknown"],"useExperimentalDependencyDetection":true,"ignoreCallbackDependenciesPatterns":[],"newlinesBetweenOverloadSignatures":0,"fallbackSort":{"type":"unsorted"},"newlinesInside":"newlinesBetween","partitionByComment":false,"partitionByNewLine":false,"newlinesBetween":"ignore","specialCharacters":"keep","useConfigurationIf":{},"type":"alphabetical","ignoreCase":true,"customGroups":[],"locales":"en-US","alphabet":"","order":"asc"}'

const pfsc_known_class_elements = [estree.NodeType.ts_abstract_property_definition,
	.ts_abstract_method_definition, .ts_abstract_accessor_property, .property_definition,
	.method_definition, .accessor_property, .ts_index_signature, .static_block]

fn (mut c Checker) lint_perfectionist_sort_classes(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut ctx := c.pf_context(t, perfectionist_sort_classes)
	tree := c.scope_tree(root)
	ctx.pf_sorters([.class_body], fn [tree] (mut ctx PfContext, node int, matched []string) ! {
		ctx.pfsc_sort_class(tree, node, matched)!
	})!
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return ctx.findings
}

// PfscNameDetails ports NodeNameDetails.
struct PfscNameDetails {
	name_without_starting_hash string
	has_private_hash           bool
	name                       string
}

// PfscMember is what sortClass computes of a member besides its sorting node.
struct PfscMember {
mut:
	dependency_names []string
	dependencies     []string
	is_static        bool
}

// pfsc_identifier_name_details ports computeIdentifierNameDetails.
fn pfsc_identifier_name_details(t &estree.EsTree, node int) PfscNameDetails {
	return match t.typ(node) {
		.private_identifier {
			name := t.string_of(node, .name) or { '' }
			PfscNameDetails{
				name_without_starting_hash: name
				name:                       '#${name}'
				has_private_hash:           true
			}
		}
		.identifier {
			name := t.string_of(node, .name) or { '' }
			PfscNameDetails{
				name_without_starting_hash: name
				name:                       name
			}
		}
		else {
			name := pf_literal_string(t, node)
			PfscNameDetails{
				name_without_starting_hash: name
				name:                       name
			}
		}
	}
}

// pfsc_name_details ports computeMethodOrPropertyNameDetails.
fn (ctx &PfContext) pfsc_name_details(member int) PfscNameDetails {
	key := ctx.t.node(member, .key) or { return PfscNameDetails{} }
	if ctx.t.typ(key) in [.private_identifier, .identifier, .literal] {
		return pfsc_identifier_name_details(ctx.t, key)
	}
	text := ctx.text(key)
	return PfscNameDetails{
		name_without_starting_hash: text
		name:                       text
	}
}

// pfsc_dependency_name ports computeDependencyName.
fn pfsc_dependency_name(name_without_starting_hash string, has_private_hash bool, is_static bool) string {
	return '${if is_static { 'static ' } else { '' }}${if has_private_hash { '#' } else { '' }}${name_without_starting_hash}'
}

// pfsc_is_function_expression ports isFunctionExpression.
fn pfsc_is_function_expression(t &estree.EsTree, node ?int) bool {
	n := node or { return false }
	return t.typ(n) in [.arrow_function_expression, .function_expression]
}

fn pfsc_flag(t &estree.EsTree, node int, key estree.Key) bool {
	return t.flag(node, key) or { false }
}

// pfsc_accessibility_modifier ports computeAccessibilityModifier.
fn pfsc_accessibility_modifier(t &estree.EsTree, node int, has_private_hash bool) string {
	if has_private_hash {
		return 'private'
	}
	return match t.string_of(node, .accessibility) or { '' } {
		'protected' { 'protected' }
		'private' { 'private' }
		else { 'public' }
	}
}

fn pfsc_is_abstract(t &estree.EsTree, node int) bool {
	return t.typ(node) in [.ts_abstract_property_definition, .ts_abstract_method_definition,
		.ts_abstract_accessor_property]
}

// pfsc_sort_class ports sortClass.
fn (mut ctx PfContext) pfsc_sort_class(tree &ScopeTree, node int, matched_ast_selectors []string) ! {
	t := ctx.t
	class_elements := (t.list(node, .body) or { []int{} }).filter(t.typ(it) in pfsc_known_class_elements)
	if class_elements.len <= 1 {
		return
	}
	settings := pf_get_settings(ctx.settings)!
	mut node_names := []string{}
	for element in class_elements {
		if t.typ(element) !in [.static_block, .ts_index_signature] {
			node_names << ctx.pfsc_name_details(element).name
		}
	}
	_, matched := ctx.pf_matched_context_options(node_names, matched_ast_selectors)!
	options := pf_complete(matched, pf_decode_defaults(pfsc_default_options), settings)!
	pf_validate_custom_sort_config(options)!
	pf_validate_groups_config(options, pfsc_all_selectors, pfsc_all_modifiers)!
	pf_validate_newlines_and_partition_config(options)!
	use_experimental := pf_opt_truthy(options, 'useExperimentalDependencyDetection')
	ignore_patterns := options['ignoreCallbackDependenciesPatterns'] or { json2.Any(json2.null) }
	class_node := t.nodes[node].parent
	mut class_name := ?string(none)
	mut class_id := -1
	if class_node >= 0 {
		if id := t.node(class_node, .id) {
			class_id = id
			class_name = t.string_of(id, .name)
		}
	}
	has_parent_declare := class_node >= 0 && pfsc_flag(t, class_node, .declare_)
	mut members := map[int]PfscMember{}
	mut groups_of_nodes := [][]PfSortingNode{len: 1}
	for member in class_elements {
		mut decorator_names := []string{}
		for decorator in t.list(member, .decorators) or { []int{} } {
			mut full_name := ctx.text(decorator)
			if full_name.starts_with('@') {
				full_name = full_name[1..]
			}
			decorator_names << full_name.all_before('(')
		}
		is_decorated := decorator_names.len > 0
		mut add_safety_semicolon_when_inline := true
		mut name := ''
		mut member_value := ?string(none)
		mut modifiers := []string{}
		mut selectors := []string{}
		mut info := PfscMember{}
		match t.typ(member) {
			.ts_abstract_property_definition, .property_definition {
				details := ctx.pfsc_name_details(member)
				value := t.node(member, .value)
				is_function := pfsc_is_function_expression(t, value)
				if pfsc_flag(t, member, .static_) {
					modifiers << 'static'
				}
				if pfsc_flag(t, member, .declare_) {
					modifiers << 'declare'
				}
				if pfsc_is_abstract(t, member) {
					modifiers << 'abstract'
				}
				if is_decorated {
					modifiers << 'decorated'
				}
				if pfsc_flag(t, member, .override) {
					modifiers << 'override'
				}
				if pfsc_flag(t, member, .readonly) {
					modifiers << 'readonly'
				}
				modifiers << pfsc_accessibility_modifier(t, member, details.has_private_hash)
				if pfsc_flag(t, member, .optional) {
					modifiers << 'optional'
				}
				if is_function {
					if pfsc_flag(t, value or { -1 }, .async) {
						modifiers << 'async'
					}
				}
				info.dependency_names = [
					pfsc_dependency_name(details.name_without_starting_hash, details.has_private_hash,
						'static' in modifiers),
				]
				if !is_function {
					if v := value {
						info.dependencies = ctx.pfsc_old_dependencies(v, ignore_patterns,
							use_experimental, pfsc_flag(t, member, .static_), class_name)!
						member_value = ctx.text(v)
					}
				}
				if is_function {
					selectors << 'function-property'
				}
				selectors << 'property'
				info.is_static = pfsc_flag(t, member, .static_)
				name = details.name
			}
			.ts_abstract_method_definition, .method_definition {
				details := ctx.pfsc_name_details(member)
				if pfsc_flag(t, member, .static_) {
					modifiers << 'static'
				}
				if pfsc_is_abstract(t, member) {
					modifiers << 'abstract'
				}
				if is_decorated {
					modifiers << 'decorated'
				}
				if pfsc_flag(t, member, .override) {
					modifiers << 'override'
				}
				modifiers << pfsc_accessibility_modifier(t, member, details.has_private_hash)
				if pfsc_flag(t, member, .optional) {
					modifiers << 'optional'
				}
				if value := t.node(member, .value) {
					if pfsc_flag(t, value, .async) {
						modifiers << 'async'
					}
				}
				add_safety_semicolon_when_inline = if t.typ(member) == .ts_abstract_method_definition {
					true
				} else {
					has_parent_declare
				}
				match t.string_of(member, .kind) or { '' } {
					'constructor' { selectors << 'constructor' }
					'set' { selectors << 'set-method' }
					'get' { selectors << 'get-method' }
					else {}
				}
				selectors << 'method'
				info.is_static = pfsc_flag(t, member, .static_)
				name = details.name
			}
			.ts_abstract_accessor_property, .accessor_property {
				details := ctx.pfsc_name_details(member)
				if pfsc_flag(t, member, .static_) {
					modifiers << 'static'
				}
				if pfsc_is_abstract(t, member) {
					modifiers << 'abstract'
				}
				if is_decorated {
					modifiers << 'decorated'
				}
				if pfsc_flag(t, member, .override) {
					modifiers << 'override'
				}
				modifiers << pfsc_accessibility_modifier(t, member, details.has_private_hash)
				info.dependency_names = [
					pfsc_dependency_name(details.name_without_starting_hash, details.has_private_hash,
						'static' in modifiers),
				]
				value := t.node(member, .value)
				if !pfsc_is_function_expression(t, value) {
					if v := value {
						info.dependencies = ctx.pfsc_old_dependencies(v, ignore_patterns,
							use_experimental, pfsc_flag(t, member, .static_), class_name)!
					}
				}
				selectors << 'accessor-property'
				info.is_static = pfsc_flag(t, member, .static_)
				name = details.name
			}
			.ts_index_signature {
				end := if annotation := t.node(member, .type_annotation) {
					t.nodes[annotation].start
				} else {
					t.nodes[member].end
				}
				name = ctx.src[t.nodes[member].start..end]
				if pfsc_flag(t, member, .static_) {
					modifiers << 'static'
				}
				if pfsc_flag(t, member, .readonly) {
					modifiers << 'readonly'
				}
				selectors << 'index-signature'
			}
			else {
				// StaticBlock
				add_safety_semicolon_when_inline = false
				name = 'static'
				info.is_static = true
				info.dependencies = ctx.pfsc_old_dependencies(member, ignore_patterns, use_experimental,
					true, class_name)!
				selectors << 'static-block'
			}
		}
		predefined_groups := pf_generate_predefined_groups(selectors, modifiers)
		group := pf_compute_group(options, predefined_groups, PfElement{
			name:            name
			selectors:       selectors
			modifiers:       modifiers
			value:           member_value
			decorator_names: decorator_names
		})!
		mut last_node := ?int(none)
		last_part := groups_of_nodes.last()
		if last_part.len > 0 {
			last_node = last_part.last().node
		}
		if ctx.pf_should_partition(options, last_node, member, '')! {
			groups_of_nodes << []PfSortingNode{}
		}
		groups_of_nodes[groups_of_nodes.len - 1] << PfSortingNode{
			node:                             member
			name:                             name
			group:                            group
			size:                             ctx.pf_range_to_diff(member)
			is_eslint_disabled:               ctx.pf_is_node_eslint_disabled(member)
			add_safety_semicolon_when_inline: add_safety_semicolon_when_inline
			partition_id:                     groups_of_nodes.len
		}
		members[member] = info
	}
	// populateSortingNodeGroupsWithOverloadSignature: the overload signatures take the fields of
	// their implementation (but addSafetySemicolonWhenInline, isEslintDisabled and node).
	overload_groups := pfsc_overload_signature_groups(t, class_elements)
	mut implementation_of := map[int]int{}
	for p, part in groups_of_nodes {
		mut by_node := map[int]PfSortingNode{}
		for sorting_node in part {
			by_node[sorting_node.node] = sorting_node
		}
		for s, sorting_node in part {
			implementation := pfsc_overload_implementation(overload_groups, sorting_node.node) or {
				continue
			}
			implementation_node := by_node[implementation] or { continue }
			groups_of_nodes[p][s] = PfSortingNode{
				...implementation_node
				node:                             sorting_node.node
				is_eslint_disabled:               sorting_node.is_eslint_disabled
				add_safety_semicolon_when_inline: sorting_node.add_safety_semicolon_when_inline
			}
			members[sorting_node.node] = members[implementation] or { PfscMember{} }
			implementation_of[sorting_node.node] = implementation
		}
	}
	mut dependencies := PfDependencies{}
	mut flat := []PfSortingNode{}
	for part in groups_of_nodes {
		flat << part
	}
	for sorting_node in flat {
		member := members[sorting_node.node] or { PfscMember{} }
		dependencies.names[sorting_node.node] = member.dependency_names
		dependencies.deps[sorting_node.node] = member.dependencies
	}
	if use_experimental {
		dependencies_by_node := ctx.pfsc_dependencies_by_sorting_node(tree, flat, members,
			ignore_patterns, class_id)!
		dependencies.pf_populate_dependencies(flat, dependencies_by_node)
	}
	groups := pf_opt_list(options, 'groups')
	is_node_ignored := fn [groups] (sorting_node PfSortingNode) bool {
		return pf_get_group_index(groups, sorting_node.group) == groups.len
	}
	mut sorted := []PfSortingNode{}
	mut sorted_excluding_disabled := []PfSortingNode{}
	for part in groups_of_nodes {
		sorted << pf_sort_nodes_by_groups_with(part, pf_default_comparator_computer, options,
			false, is_node_ignored, unsafe { nil })
		sorted_excluding_disabled << pf_sort_nodes_by_groups_with(part, pf_default_comparator_computer,
			options, true, is_node_ignored, unsafe { nil })
	}
	sorted = dependencies.pf_sort_nodes_by_dependencies(sorted, false)
	sorted_excluding_disabled = dependencies.pf_sort_nodes_by_dependencies(sorted_excluding_disabled,
		true)
	newlines_between_overload_signatures := pf_newlines_value(options['newlinesBetweenOverloadSignatures'] or {
		json2.Any('ignore')
	})
	newlines_getter := fn [implementation_of, newlines_between_overload_signatures] (computed f64, left PfSortingNode, right PfSortingNode) f64 {
		if left_implementation := implementation_of[left.node] {
			if right_implementation := implementation_of[right.node] {
				if left_implementation == right_implementation {
					return newlines_between_overload_signatures
				}
			}
		}
		return computed
	}
	ctx.pf_report_all_errors_full(flat, sorted, sorted_excluding_disabled, options, pfsc_message_ids,
		PfReportExtras{
			dependencies:    dependencies
			newlines_getter: newlines_getter
		})!
}

// PfscOverloadGroup ports OverloadSignatureGroup.
struct PfscOverloadGroup {
	implementation      int
	overload_signatures []int
}

// pfsc_overload_signature_groups ports computeOverloadSignatureGroups: the methods (kind
// `method`, named by an identifier) with the same name and staticness, when there are several.
fn pfsc_overload_signature_groups(t &estree.EsTree, class_elements []int) []PfscOverloadGroup {
	mut method_names := []string{}
	mut by_name := map[string][]int{}
	mut static_names := []string{}
	mut static_by_name := map[string][]int{}
	for element in class_elements {
		if t.typ(element) !in [.method_definition, .ts_abstract_method_definition] {
			continue
		}
		if (t.string_of(element, .kind) or { '' }) != 'method' {
			continue
		}
		key := t.node(element, .key) or { continue }
		if t.typ(key) != .identifier {
			continue
		}
		name := t.string_of(key, .name) or { '' }
		if pfsc_flag(t, element, .static_) {
			if name !in static_by_name {
				static_names << name
			}
			static_by_name[name] << element
		} else {
			if name !in by_name {
				method_names << name
			}
			by_name[name] << element
		}
	}
	mut lists := [][]int{}
	for name in method_names {
		lists << by_name[name]
	}
	for name in static_names {
		lists << static_by_name[name]
	}
	mut out := []PfscOverloadGroup{}
	for methods in lists {
		if methods.len <= 1 {
			continue
		}
		is_implementation := fn [t] (method int) bool {
			value := t.node(method, .value) or { return false }
			return t.typ(value) == .function_expression
		}
		mut implementation := methods.last()
		for method in methods {
			if is_implementation(method) {
				implementation = method
				break
			}
		}
		out << PfscOverloadGroup{
			implementation:      implementation
			overload_signatures: methods.filter(!is_implementation(it))
		}
	}
	return out
}

// pfsc_overload_implementation ports computeOverloadSignatureImplementation: the implementation of
// the first group the node belongs to.
fn pfsc_overload_implementation(groups []PfscOverloadGroup, node int) ?int {
	for group in groups {
		if node in group.overload_signatures || group.implementation == node {
			return group.implementation
		}
	}
	return none
}

// --- Dependencies --------------------------------------------------------------------------------

// pfsc_dependencies_by_sorting_node ports computeDependenciesBySortingNode of sort-classes: the
// references of the members to other members (through the class name for the static ones) and
// the `this.member` expressions.
fn (ctx &PfContext) pfsc_dependencies_by_sorting_node(tree &ScopeTree, sorting_nodes []PfSortingNode, members map[int]PfscMember, ignore_patterns json2.Any, class_id int) !map[int][]int {
	t := ctx.t
	static_sorting_nodes := sorting_nodes.filter((members[it.node] or { PfscMember{} }).is_static)
	non_static_sorting_nodes := sorting_nodes.filter(!(members[it.node] or { PfscMember{} }).is_static)
	should_ignore := fn [t] (sorting_node PfSortingNode) bool {
		return pfsc_should_ignore_dependency_computation(t, sorting_node.node)
	}
	// The errors of the patterns are thrown where they are met: the callbacks keep the first one.
	mut first_error := &PfscError{}
	additional := fn [ctx, tree, ignore_patterns, static_sorting_nodes, class_id, mut first_error] (reference int, referencing PfSortingNode) []PfSortingNode {
		ref := tree.references[reference]
		variable := tree.variables[ref.resolved]
		if variable.identifiers.len == 0 {
			return []PfSortingNode{}
		}
		if class_id < 0 || node_start(variable.identifiers[0]) != ctx.t.nodes[class_id].start {
			return []PfSortingNode{}
		}
		identifier := pf_estree_identifier_at(ctx.t, node_start(ref.identifier)) or {
			return []PfSortingNode{}
		}
		found, dependency := ctx.pfsc_identifier_or_this_dependency(ignore_patterns, static_sorting_nodes,
			referencing.node, identifier) or {
			if first_error.message == '' {
				first_error.message = err.msg()
			}
			return []PfSortingNode{}
		}
		return if found { [dependency] } else { []PfSortingNode{} }
	}
	mut out := ctx.pf_dependencies_by_sorting_node(tree, sorting_nodes, PfDependencyComputers{
		should_ignore_sorting_node: should_ignore
		additional:                 additional
	})
	if first_error.message != '' {
		return error(first_error.message)
	}
	// computeThisExpressionDependenciesBySortingNode
	for sorting_node in sorting_nodes {
		if pfsc_should_ignore_dependency_computation(t, sorting_node.node) {
			continue
		}
		is_static := (members[sorting_node.node] or { PfscMember{} }).is_static
		candidates := if is_static { static_sorting_nodes } else { non_static_sorting_nodes }
		mut this_dependencies := []int{}
		for token in ctx.tokens.inside(t.nodes[sorting_node.node].start, t.nodes[sorting_node.node].end,
			false) {
			if ctx.src[token.start..token.end] != 'this' {
				continue
			}
			this_node := un_node_by_range_index(t, token.start) or { continue }
			if t.typ(this_node) != .this_expression {
				continue
			}
			found, dependency := ctx.pfsc_identifier_or_this_dependency(ignore_patterns, candidates,
				sorting_node.node, this_node)!
			if found {
				this_dependencies << dependency.node
			}
		}
		if this_dependencies.len == 0 {
			continue
		}
		mut existing := out[sorting_node.node] or { []int{} }
		existing << this_dependencies
		out[sorting_node.node] = existing
	}
	return out
}

@[heap]
struct PfscError {
mut:
	message string
}

// pfsc_identifier_or_this_dependency ports computeIdentifierOrThisExpressionDependency: the member
// named by the member expression of the class name or `this`, unless it is in a deferred function
// (false when there is none).
fn (ctx &PfContext) pfsc_identifier_or_this_dependency(ignore_patterns json2.Any, sorting_nodes []PfSortingNode, class_element int, node int) !(bool, PfSortingNode) {
	t := ctx.t
	if t.typ(class_element) != .static_block
		&& pf_is_node_inside_deferred_function(t, ignore_patterns, class_element, node)! {
		return false, PfSortingNode{}
	}
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .member_expression {
		return false, PfSortingNode{}
	}
	property := t.node(parent, .property) or { return false, PfSortingNode{} }
	if t.typ(property) !in [.private_identifier, .identifier, .literal] {
		return false, PfSortingNode{}
	}
	dependency_name := pfsc_identifier_name_details(t, property).name
	for sorting_node in sorting_nodes {
		if sorting_node.name == dependency_name {
			return true, sorting_node
		}
	}
	return false, PfSortingNode{}
}

// pfsc_should_ignore_dependency_computation ports shouldIgnoreDependencyComputation: methods and
// index signatures.
fn pfsc_should_ignore_dependency_computation(t &estree.EsTree, node int) bool {
	return t.typ(node) in [.method_definition, .ts_index_signature]
}

// pfsc_old_dependencies ports computeDependencies of sort-classes (the deprecated detection, used
// without useExperimentalDependencyDetection): the members an expression reads through `this` or
// the class name.
fn (ctx &PfContext) pfsc_old_dependencies(expression int, ignore_patterns json2.Any, use_experimental bool, is_member_static bool, class_name ?string) ![]string {
	if use_experimental {
		return []string{}
	}
	mut dependencies := []string{}
	ctx.pfsc_old_check_node(expression, ignore_patterns, is_member_static, class_name, mut
		dependencies)!
	return dependencies
}

fn (ctx &PfContext) pfsc_old_traverse(nodes []int, ignore_patterns json2.Any, is_member_static bool, class_name ?string, mut dependencies []string) ! {
	for node in nodes {
		ctx.pfsc_old_check_node(node, ignore_patterns, is_member_static, class_name, mut dependencies)!
	}
}

// pfsc_old_children are the nodes of a property (`'key' in node && node.key`): one node, or the
// nodes of a list (but its holes).
fn pfsc_old_children(t &estree.EsTree, node int, key estree.Key) []int {
	value := t.get(node, key)
	return match value {
		estree.NodeRef { [value.index] }
		estree.NodeList { value.items.filter(it >= 0) }
		else { []int{} }
	}
}

fn (ctx &PfContext) pfsc_old_check_node(node int, ignore_patterns json2.Any, is_member_static bool, class_name ?string, mut dependencies []string) ! {
	t := ctx.t
	match t.typ(node) {
		.conditional_expression {
			for key in [estree.Key.test, .consequent, .alternate] {
				ctx.pfsc_old_traverse(pfsc_old_children(t, node, key), ignore_patterns,
					is_member_static, class_name, mut dependencies)!
			}
		}
		.member_expression {
			dependencies << pfsc_member_expression_dependencies(t, node, is_member_static,
				class_name)
		}
		.call_expression {
			callee := t.node(node, .callee) or { -1 }
			mut traverse_arguments := true
			if callee >= 0 {
				if name := t.string_of(callee, .name) {
					if pf_matches(name, ignore_patterns)! {
						traverse_arguments = false
					}
				}
			}
			if traverse_arguments {
				ctx.pfsc_old_traverse(pfsc_old_children(t, node, .arguments), ignore_patterns,
					is_member_static, class_name, mut dependencies)!
			}
		}
		.new_expression {
			ctx.pfsc_old_traverse(pfsc_old_children(t, node, .arguments), ignore_patterns,
				is_member_static, class_name, mut dependencies)!
		}
		.property {
			for key in [estree.Key.key, .value] {
				ctx.pfsc_old_traverse(pfsc_old_children(t, node, key), ignore_patterns,
					is_member_static, class_name, mut dependencies)!
			}
		}
		else {}
	}
	for key in [estree.Key.argument, .body, .callee, .declarations, .elements, .expression,
		.expressions, .init, .left, .object, .properties, .right] {
		ctx.pfsc_old_traverse(pfsc_old_children(t, node, key), ignore_patterns, is_member_static,
			class_name, mut dependencies)!
	}
}

// pfsc_member_expression_dependencies ports computeMemberExpressionDependencies: `this.member`, or
// `ClassName.member`.
fn pfsc_member_expression_dependencies(t &estree.EsTree, node int, is_member_static bool, class_name ?string) []string {
	object := t.node(node, .object) or { return []string{} }
	match t.typ(object) {
		.this_expression {}
		.identifier {
			name := class_name or { return []string{} }
			if (t.string_of(object, .name) or { '' }) != name {
				return []string{}
			}
		}
		else {
			return []string{}
		}
	}
	property := t.node(node, .property) or { return []string{} }
	if t.typ(property) !in [.private_identifier, .identifier, .literal] {
		return []string{}
	}
	details := pfsc_identifier_name_details(t, property)
	return [
		pfsc_dependency_name(details.name_without_starting_hash, details.has_private_hash,
			is_member_static || t.typ(object) == .identifier),
	]
}
