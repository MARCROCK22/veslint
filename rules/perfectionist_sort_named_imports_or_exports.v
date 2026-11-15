module rules

import estree
import json2

// What sort-named-imports and sort-named-exports of eslint-plugin-perfectionist 5.13.0 have in
// common (rules/sort-named-imports/sort-named-import.ts, rules/sort-named-exports/
// sort-named-export.ts, their computeNodeName, computeImportKindModifier and
// computeExportKindModifier, and their own computeMatchedContextOptions): the specifiers of an
// import or an export sorted by their names, with the `import` or `export` selector and the
// `value` or `type` modifier.

// The defaultOptions of both rules.
const pfne_default_options = '{"fallbackSort":{"type":"unsorted"},"newlinesInside":"newlinesBetween","specialCharacters":"keep","partitionByNewLine":false,"partitionByComment":false,"newlinesBetween":"ignore","useConfigurationIf":{},"type":"alphabetical","ignoreAlias":false,"customGroups":[],"ignoreCase":true,"locales":"en-US","alphabet":"","order":"asc","groups":[]}'

// allModifiers of both rules.
const pfne_all_modifiers = ['value', 'type']

// pfne_module_name is the name of an Identifier or the value of a string Literal.
fn (ctx &PfContext) pfne_module_name(node int) string {
	t := ctx.t
	if t.typ(node) == .identifier {
		return t.string_of(node, .name) or { '' }
	}
	return pf_literal_string(t, node)
}

// pfne_node_name ports computeNodeName of both rules: of an import specifier, its local name, or
// with `ignoreAlias` the imported one; of an export specifier, its exported name, or with
// `ignoreAlias` the local one.
fn (ctx &PfContext) pfne_node_name(specifier int, is_import bool, ignore_alias bool) string {
	key := if is_import {
		if ignore_alias { estree.Key.imported } else { estree.Key.local }
	} else {
		if ignore_alias { estree.Key.local } else { estree.Key.exported }
	}
	return ctx.pfne_module_name(ctx.t.node(specifier, key) or { return '' })
}

// pfne_kind_modifier ports computeImportKindModifier and computeExportKindModifier.
fn (ctx &PfContext) pfne_kind_modifier(specifier int, is_import bool) string {
	kind := ctx.t.string_of(specifier, if is_import { .import_kind } else { .export_kind }) or {
		'value'
	}
	return if kind == 'type' { 'type' } else { 'value' }
}

// pfne_sort ports sortNamedImport and sortNamedExport: `specifiers` are the import specifiers
// of the import, or the specifiers of the export.
fn (mut ctx PfContext) pfne_sort(specifiers []int, matched_ast_selectors []string, is_import bool, ids PfMessageIds) ! {
	// isSortable: more than one.
	if specifiers.len <= 1 {
		return
	}
	settings := pf_get_settings(ctx.settings)!
	// computeMatchedContextOptions: the names an option sees depend on its ignoreAlias.
	mut matched := map[string]json2.Any{}
	for option in ctx.options {
		object := if option is map[string]json2.Any {
			option.as_map()
		} else {
			map[string]json2.Any{}
		}
		ignore_alias := pf_opt_truthy(object, 'ignoreAlias')
		node_names := specifiers.map(ctx.pfne_node_name(it, is_import, ignore_alias))
		if pf_is_context_option_matching(object, node_names, matched_ast_selectors)! {
			matched = object.clone()
			break
		}
	}
	options := pf_complete(matched, pf_decode_defaults(pfne_default_options), settings)!
	selector := if is_import { 'import' } else { 'export' }
	pf_validate_custom_sort_config(options)!
	pf_validate_groups_config(options, [selector], pfne_all_modifiers)!
	pf_validate_newlines_and_partition_config(options)!
	if !pf_can_report_errors(options, pf_default_comparator_computer, ids) {
		return
	}
	ignore_alias := pf_opt_truthy(options, 'ignoreAlias')
	mut formatted_members := [][]PfSortingNode{len: 1}
	for specifier in specifiers {
		name := ctx.pfne_node_name(specifier, is_import, ignore_alias)
		modifiers := [ctx.pfne_kind_modifier(specifier, is_import)]
		group := pf_compute_group(options, pf_generate_predefined_groups([selector], modifiers),
			PfElement{
				name:      name
				selectors: [selector]
				modifiers: modifiers
			})!
		mut last_node := ?int(none)
		last_part := formatted_members.last()
		if last_part.len > 0 {
			last_node = last_part.last().node
		}
		if ctx.pf_should_partition(options, last_node, specifier, '')! {
			formatted_members << []PfSortingNode{}
		}
		formatted_members[formatted_members.len - 1] << PfSortingNode{
			node:               specifier
			name:               name
			group:              group
			size:               ctx.pf_range_to_diff(specifier)
			is_eslint_disabled: ctx.pf_is_node_eslint_disabled(specifier)
			partition_id:       formatted_members.len
		}
	}
	mut sorted := []PfSortingNode{}
	mut sorted_excluding_disabled := []PfSortingNode{}
	mut nodes := []PfSortingNode{}
	for part in formatted_members {
		sorted << pf_sort_nodes_by_groups(part, pf_default_comparator_computer, options,
			false)
		sorted_excluding_disabled << pf_sort_nodes_by_groups(part, pf_default_comparator_computer,
			options, true)
		nodes << part
	}
	ctx.pf_report_all_errors(nodes, sorted, sorted_excluding_disabled, options, ids)!
}
