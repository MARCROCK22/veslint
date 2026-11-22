module rules

import estree
import json2
import jsregexp
import math
import os
import time

// Port of the `perfectionist/sort-imports` rule of eslint-plugin-perfectionist 5.13.0 (with
// rules/sort-imports/): the imports (`import`, `import x = require()` and `const x = require()`)
// of each run with nothing but comments between them, sorted with the shared engine
// (perfectionist_utils*.v) by their groups (selectors and modifiers), in partitions, after the
// imports they depend on, with the comments above groups, all its options, the `perfectionist`
// settings and the fixes. The `tsconfig` option reads the compiler options of the closest
// tsconfig through tsgo (parseConfigFile) and resolves the module names with them
// (resolveModuleName); without it, a name is external unless TypeScript takes it as relative
// (isExternalModuleNameRelative). The builtin modules are those of Node 26 (builtinModules).

const pfsi_messages = {
	'missedCommentAboveImport':         'Missed comment "{{missedCommentAbove}}" above "{{right}}".'
	'unexpectedImportsDependencyOrder': 'Expected dependency "{{right}}" to come before "{{nodeDependentOnRight}}".'
	'missedSpacingBetweenImports':      'Missed spacing between "{{left}}" and "{{right}}".'
	'extraSpacingBetweenImports':       'Extra spacing between "{{left}}" and "{{right}}".'
	'unexpectedImportsGroupOrder':      'Expected "{{right}}" ({{rightGroup}}) to come before "{{left}}" ({{leftGroup}}).'
	'unexpectedImportsOrder':           'Expected "{{right}}" to come before "{{left}}".'
}

const pfsi_message_ids = PfMessageIds{
	missed_spacing:              'missedSpacingBetweenImports'
	extra_spacing:               'extraSpacingBetweenImports'
	unexpected_dependency_order: 'unexpectedImportsDependencyOrder'
	unexpected_group_order:      'unexpectedImportsGroupOrder'
	missed_comment_above:        'missedCommentAboveImport'
	unexpected_order:            'unexpectedImportsOrder'
}

// pfsi_all_selectors and pfsi_all_modifiers are allSelectors and allModifiers of
// sort-imports/types.ts.
const pfsi_all_selectors = ['side-effect-style', 'tsconfig-path', 'side-effect', 'external', 'internal',
	'builtin', 'sibling', 'subpath', 'import', 'parent', 'index', 'style', 'type']
const pfsi_all_modifiers = ['default', 'multiline', 'named', 'require', 'side-effect', 'singleline',
	'ts-equals', 'type', 'value', 'wildcard']

// The default options but maxLineLength (Infinity, which JSON has not): pfsi_max_line_length.
const pfsi_default_options = '{"groups":["type-import",["value-builtin","value-external"],"type-internal","value-internal",["type-parent","type-sibling","type-index"],["value-parent","value-sibling","value-index"],"ts-equals-import","unknown"],"internalPattern":["^~/.+","^@/.+","^#.+"],"useExperimentalDependencyDetection":true,"fallbackSort":{"type":"unsorted"},"partitionByComment":false,"partitionByNewLine":false,"specialCharacters":"keep","tsconfig":{"rootDir":""},"sortSideEffects":false,"type":"alphabetical","environment":"node","newlinesBetween":1,"newlinesInside":0,"customGroups":[],"ignoreCase":true,"locales":"en-US","sortBy":"path","alphabet":"","order":"asc"}'

// The JSON schemas of commonJsonSchemas of sort-imports that differ from the settings' ones: its
// `type` and its fallbackSort also take 'type-import-first', and its fallbackSort a `sortBy`.
const pfsi_common_json_schemas = '{"fallbackSort":{"properties":{"type":{"enum":["alphabetical","natural","line-length","custom","unsorted","subgroup-order","type-import-first"],"type":"string"},"order":{"enum":["asc","desc"],"type":"string"},"sortBy":{"enum":["specifier","path"],"type":"string"}},"additionalProperties":false,"required":["type"],"type":"object"},"type":{"enum":["alphabetical","natural","line-length","custom","unsorted","subgroup-order","type-import-first"],"type":"string"},"sortBy":{"enum":["specifier","path"],"type":"string"}}'

// pfsi_node_builtin_modules is builtinModules of node:module (Node 26).
const pfsi_node_builtin_modules = ['_http_agent', '_http_client', '_http_common', '_http_incoming',
	'_http_outgoing', '_http_server', '_tls_common', '_tls_wrap', 'assert', 'assert/strict',
	'async_hooks', 'buffer', 'child_process', 'cluster', 'console', 'constants', 'crypto', 'dgram',
	'diagnostics_channel', 'dns', 'dns/promises', 'domain', 'events', 'fs', 'fs/promises', 'http',
	'http2', 'https', 'inspector', 'inspector/promises', 'module', 'net', 'os', 'path', 'path/posix',
	'path/win32', 'perf_hooks', 'process', 'punycode', 'querystring', 'readline', 'readline/promises',
	'repl', 'stream', 'stream/consumers', 'stream/promises', 'stream/web', 'string_decoder', 'sys',
	'timers', 'timers/promises', 'tls', 'trace_events', 'tty', 'url', 'util', 'util/types', 'v8',
	'vm', 'wasi', 'worker_threads', 'zlib', 'node:ffi', 'node:sea', 'node:sqlite', 'node:test',
	'node:test/reporters']

// pfsi_builtin_prefix_only_modules is builtinPrefixOnlyModules: the builtin modules named only
// with `node:`.
const pfsi_builtin_prefix_only_modules = ['node:ffi', 'node:sea', 'node:sqlite', 'node:test',
	'node:test/reporters']

const pfsi_bun_modules = ['detect-libc', 'bun:sqlite', 'bun:test', 'bun:wrap', 'bun:ffi', 'bun:jsc',
	'undici', 'bun', 'ws']

const pfsi_index_modules = ['./index.d.js', './index.d.ts', './index.js', './index.ts', './index',
	'./', '.']

const pfsi_style_extensions = ['.less', '.scss', '.sass', '.styl', '.pcss', '.css', '.sss']

const pfsi_re_named_without_specifiers = jsregexp.js_regex_new('\\}\\s*from\\s+', 'u') or {
	panic(err)
}
const pfsi_re_node_prefix = jsregexp.js_regex_new('^(?:node:){1,2}', 'u') or { panic(err) }

// PfsiTsConfig ports ReadClosestTsConfigByPathValue: the tsconfig found and the keys of its
// `paths`.
struct PfsiTsConfig {
	path  string
	paths []string
}

// PfsiImport is what registerNode computes of an import besides its sorting node.
struct PfsiImport {
	dependency_names []string
	dependencies     []string
	is_type_import   bool
	is_ignored       bool
}

fn (mut c Checker) lint_perfectionist_sort_imports(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut ctx := c.pf_context(t, perfectionist_sort_imports)
	settings := pf_get_settings(ctx.settings)!
	user_options := if ctx.options.len > 0 && ctx.options[0] is map[string]json2.Any {
		ctx.options[0].as_map()
	} else {
		map[string]json2.Any{}
	}
	defaults := pf_decode_defaults(pfsi_default_options)
	first := pfsi_complete(user_options, defaults, settings)!
	mut options := if pf_opt_truthy(first, 'partitionByNewLine') {
		mut partition_defaults := defaults.clone()
		partition_defaults['newlinesBetween'] = json2.Any('ignore')
		partition_defaults['newlinesInside'] = json2.Any('ignore')
		pfsi_complete(user_options, partition_defaults, settings)!
	} else {
		first
	}
	options = pfsi_options_with_clean_groups(options)
	pf_validate_groups_config(options, pfsi_all_selectors, pfsi_all_modifiers)!
	pf_validate_custom_sort_config(options)!
	pf_validate_newlines_and_partition_config(options)!
	pfsi_validate_side_effects_config(options)!
	mut ts_config := ?PfsiTsConfig(none)
	if tsconfig_option := pf_opt_object(options, 'tsconfig') {
		root_dir := pf_opt_string(tsconfig_option, 'rootDir')
		if root_dir != '' {
			filename := if 'filename' in tsconfig_option {
				pf_opt_string(tsconfig_option, 'filename')
			} else {
				'tsconfig.json'
			}
			ts_config = c.pfsi_read_closest_ts_config(filename, root_dir, abs_path)!
		}
	}
	mut flat_groups := []string{}
	for group in pf_opt_list(options, 'groups') {
		if group is string {
			flat_groups << group
		} else if group is []json2.Any {
			flat_groups << pf_string_list(group)
		}
	}
	should_regroup_side_effect_nodes := 'side-effect' in flat_groups
	should_regroup_side_effect_style_nodes := 'side-effect-style' in flat_groups
	sort_side_effects := pf_opt_truthy(options, 'sortSideEffects')
	use_experimental := pf_opt_truthy(options, 'useExperimentalDependencyDetection')
	max_line_length := if value := options['maxLineLength'] {
		json_number(value)
	} else {
		pfsi_infinity
	}
	mut sorting_nodes := []PfSortingNode{}
	mut imports := map[int]PfsiImport{}
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.variable_declaration {
				if !pfsi_is_require_declaration(t, node) {
					continue
				}
			}
			.ts_import_equals_declaration, .import_declaration {}
			else {
				continue
			}
		}
		// registerNode
		name := ctx.pfsi_node_name(node)
		common_selectors := c.pfsi_common_selectors(ts_config, abs_path, options, name)!
		mut selectors := []string{}
		mut modifiers := []string{}
		if t.typ(node) != .variable_declaration
			&& (t.string_of(node, .import_kind) or { '' }) == 'type' {
			selectors << 'type'
			modifiers << 'type'
		}
		is_side_effect := ctx.pfsi_is_side_effect_import(node)!
		is_style_value := pfsi_is_style(name)
		is_style_side_effect := is_side_effect && is_style_value
		if !pfsi_is_non_external_reference_ts_import_equals(t, node) {
			if is_style_side_effect {
				selectors << 'side-effect-style'
			}
			if is_side_effect {
				selectors << 'side-effect'
				modifiers << 'side-effect'
			}
			if is_style_value {
				selectors << 'style'
			}
			selectors << common_selectors
		}
		selectors << 'import'
		if 'type' !in modifiers {
			modifiers << 'value'
		}
		if t.typ(node) == .ts_import_equals_declaration {
			modifiers << 'ts-equals'
		}
		if t.typ(node) == .variable_declaration {
			modifiers << 'require'
		}
		modifiers << pfsi_specifier_modifiers(t, node)
		modifiers << if ctx.start_line(node) == ctx.end_line(node) {
			'singleline'
		} else {
			'multiline'
		}
		group := pf_compute_group(options, pf_generate_predefined_groups(selectors, modifiers),
			PfElement{
				name:      name
				selectors: selectors
				modifiers: modifiers
			})!
		specifiers := if t.typ(node) == .import_declaration {
			t.list(node, .specifiers) or { []int{} }
		} else {
			[]int{}
		}
		mut size := ctx.pf_range_to_diff(node)
		if specifiers.len > 1 && f64(size) > max_line_length {
			size = utf16_units(name).len + 10
		}
		specifier_name := ctx.pfsi_specifier_name(node)
		sorting_nodes << PfSortingNode{
			node:                             node
			name:                             name
			value:                            specifier_name or { '' }
			group:                            group
			size:                             size
			is_eslint_disabled:               ctx.pf_is_node_eslint_disabled(node)
			add_safety_semicolon_when_inline: true
		}
		imports[node] = PfsiImport{
			dependency_names: ctx.pfsi_dependency_names(node)
			dependencies:     if use_experimental {
				[]string{}
			} else {
				pfsi_old_dependencies(t, node)
			}
			is_type_import:   'type' in modifiers
			is_ignored:       !sort_side_effects && is_side_effect
				&& !should_regroup_side_effect_nodes
				&& (!is_style_side_effect || !should_regroup_side_effect_style_nodes)
		}
	}
	if sorting_nodes.len > 0 {
		tree := c.scope_tree(root)
		ctx.pfsi_sort_import_nodes(tree, sorting_nodes, imports, options)!
	}
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return ctx.findings
}

const pfsi_infinity = math.inf(1)

// pfsi_complete ports complete with the commonJsonSchemas of sort-imports.
fn pfsi_complete(options map[string]json2.Any, defaults map[string]json2.Any, settings map[string]json2.Any) !map[string]json2.Any {
	common := pf_decode_defaults(pfsi_common_json_schemas)
	mut invalid := []string{}
	for key, value in settings {
		schema := common[key] or { pf_settings_schema_map[key] or { continue } }
		if key in defaults && key !in options && !pf_matches_json_schema(value, schema) {
			invalid << key
		}
	}
	if invalid.len > 0 {
		return error('Invalid value(s) for Perfectionist setting(s): ${invalid.join(', ')}')
	}
	return pf_spread(pf_spread(defaults, settings), options)
}

// pfsi_options_with_clean_groups ports getOptionsWithCleanGroups: no empty list of groups, and a
// list of one group as that group.
fn pfsi_options_with_clean_groups(options map[string]json2.Any) map[string]json2.Any {
	mut groups := []json2.Any{}
	for group in pf_opt_list(options, 'groups') {
		if group is []json2.Any {
			list := group.as_array()
			if list.len == 0 {
				continue
			}
			if list.len == 1 && pf_truthy(list[0]) {
				groups << list[0]
				continue
			}
		}
		groups << group
	}
	mut out := options.clone()
	out['groups'] = json2.Any(groups)
	return out
}

// pfsi_is_string_group_side_effect_only_group ports isStringGroupSideEffectOnlyGroup.
fn pfsi_is_string_group_side_effect_only_group(group_name string) bool {
	return group_name == 'side-effect' || group_name == 'side-effect-style'
}

// pfsi_is_side_effect_only_group ports isSideEffectOnlyGroup.
// A group that does not exist (`undefined`) is not one.
fn pfsi_is_side_effect_only_group(value json2.Any) bool {
	if !pf_truthy(value) {
		return false
	}
	group_names := pf_compute_groups_names([value])
	if group_names.len == 0 {
		return false
	}
	return group_names.all(pfsi_is_string_group_side_effect_only_group(it))
}

// pfsi_validate_side_effects_config ports validateSideEffectsConfig.
fn pfsi_validate_side_effects_config(options map[string]json2.Any) ! {
	if pf_opt_truthy(options, 'sortSideEffects') {
		return
	}
	for group in pf_opt_list(options, 'groups') {
		nested := pf_compute_groups_names([group])
		has_side_effect_group := nested.any(pfsi_is_string_group_side_effect_only_group(it))
		// isSideEffectOnlyGroup of the list of names: a list that is not empty, all of them side
		// effect groups.
		is_side_effect_only := nested.len > 0
			&& nested.all(pfsi_is_string_group_side_effect_only_group(it))
		if has_side_effect_group && !is_side_effect_only {
			return error("Side effect groups cannot be nested with non side effect groups when 'sortSideEffects' is 'false'.")
		}
	}
}

// pfsi_is_require_declaration: `const x = require('…')`, the declaration the VariableDeclaration
// listener registers.
fn pfsi_is_require_declaration(t &estree.EsTree, node int) bool {
	declarations := t.list(node, .declarations) or { return false }
	if declarations.len == 0 {
		return false
	}
	init := t.node(declarations[0], .init) or { return false }
	if t.typ(init) != .call_expression {
		return false
	}
	callee := t.node(init, .callee) or { return false }
	if t.typ(callee) != .identifier || (t.string_of(callee, .name) or { '' }) != 'require' {
		return false
	}
	arguments := t.list(init, .arguments) or { return false }
	return arguments.len > 0 && t.typ(arguments[0]) == .literal
}

// pfsi_node_name ports computeNodeName: the module name of the import.
fn (ctx &PfContext) pfsi_node_name(node int) string {
	t := ctx.t
	match t.typ(node) {
		.ts_import_equals_declaration {
			reference := t.node(node, .module_reference) or { return '' }
			if t.typ(reference) == .ts_external_module_reference {
				expression := t.node(reference, .expression) or { return '' }
				return pf_literal_string(t, expression)
			}
			return ctx.text(reference)
		}
		.variable_declaration {
			declarations := t.list(node, .declarations) or { return '' }
			init := t.node(declarations[0], .init) or { return '' }
			arguments := t.list(init, .arguments) or { return '' }
			return pf_literal_string(t, arguments[0])
		}
		else {
			source := t.node(node, .source) or { return '' }
			return pf_literal_string(t, source)
		}
	}
}

// pfsi_specifier_name ports computeSpecifierName: the name of the first specifier (or what the
// require is assigned to).
fn (ctx &PfContext) pfsi_specifier_name(node int) ?string {
	t := ctx.t
	match t.typ(node) {
		.ts_import_equals_declaration {
			id := t.node(node, .id)?
			return t.string_of(id, .name)
		}
		.variable_declaration {
			declarations := t.list(node, .declarations)?
			id := t.node(declarations[0], .id)?
			match t.typ(id) {
				.object_pattern {
					properties := t.list(id, .properties)?
					if properties.len == 0 {
						return none
					}
					property := properties[0]
					if t.typ(property) == .rest_element {
						return ctx.text(t.node(property, .argument)?)
					}
					return ctx.text(t.node(property, .value)?)
				}
				.array_pattern {
					elements := t.list(id, .elements)?
					if elements.len == 0 || elements[0] < 0 {
						return none
					}
					return ctx.text(elements[0])
				}
				else {
					return t.string_of(id, .name)
				}
			}
		}
		else {
			specifiers := t.list(node, .specifiers)?
			if specifiers.len == 0 {
				return none
			}
			local := t.node(specifiers[0], .local)?
			return t.string_of(local, .name)
		}
	}
}

// pfsi_specifier_modifiers ports computeSpecifierModifiers.
fn pfsi_specifier_modifiers(t &estree.EsTree, node int) []string {
	if t.typ(node) != .import_declaration {
		return []string{}
	}
	specifiers := t.list(node, .specifiers) or { []int{} }
	mut out := []string{}
	if specifiers.any(t.typ(it) == .import_default_specifier) {
		out << 'default'
	}
	if specifiers.any(t.typ(it) == .import_namespace_specifier) {
		out << 'wildcard'
	}
	if specifiers.any(t.typ(it) == .import_specifier) {
		out << 'named'
	}
	return out
}

// pfsi_dependency_names ports computeDependencyNames: the names an import declares (the imported
// name of a named import).
fn (ctx &PfContext) pfsi_dependency_names(node int) []string {
	t := ctx.t
	match t.typ(node) {
		.ts_import_equals_declaration {
			id := t.node(node, .id) or { return []string{} }
			return [t.string_of(id, .name) or { '' }]
		}
		.variable_declaration {
			return []string{}
		}
		else {
			mut out := []string{}
			for specifier in t.list(node, .specifiers) or { []int{} } {
				key := if t.typ(specifier) == .import_specifier {
					estree.Key.imported
				} else {
					estree.Key.local
				}
				name := t.node(specifier, key) or { continue }
				out << ctx.text(name)
			}
			return out
		}
	}
}

// pfsi_old_dependencies ports computeDependencies of sort-imports (without
// useExperimentalDependencyDetection): the first name of the qualified name of an
// `import x = a.b`.
fn pfsi_old_dependencies(t &estree.EsTree, node int) []string {
	if t.typ(node) != .ts_import_equals_declaration {
		return []string{}
	}
	reference := t.node(node, .module_reference) or { return []string{} }
	if t.typ(reference) != .ts_qualified_name {
		return []string{}
	}
	mut current := reference
	for t.typ(current) == .ts_qualified_name {
		current = t.node(current, .left) or { return []string{} }
	}
	if t.typ(current) != .identifier {
		return []string{}
	}
	return [t.string_of(current, .name) or { '' }]
}

// pfsi_is_side_effect_import ports isSideEffectImport: an import without specifiers (but
// `import {} from`).
fn (ctx &PfContext) pfsi_is_side_effect_import(node int) !bool {
	if ctx.t.typ(node) != .import_declaration {
		return false
	}
	specifiers := ctx.t.list(node, .specifiers) or { []int{} }
	return specifiers.len == 0
		&& !pfsi_re_named_without_specifiers.test(utf16_units(ctx.text(node)))!
}

// pfsi_is_style ports isStyle: the name (before a `?`) ends with the extension of a style sheet.
fn pfsi_is_style(value string) bool {
	cleaned := value.all_before('?')
	return pfsi_style_extensions.any(cleaned.ends_with(it))
}

// pfsi_is_non_external_reference_ts_import_equals ports isNonExternalReferenceTsImportEquals.
fn pfsi_is_non_external_reference_ts_import_equals(t &estree.EsTree, node int) bool {
	if t.typ(node) != .ts_import_equals_declaration {
		return false
	}
	reference := t.node(node, .module_reference) or { return false }
	return t.typ(reference) != .ts_external_module_reference
}

// --- Selectors -----------------------------------------------------------------------------------

// pfsi_common_selectors ports computeCommonSelectors.
fn (mut c Checker) pfsi_common_selectors(ts_config ?PfsiTsConfig, filename string, options map[string]json2.Any, name string) ![]string {
	mut matches_internal_pattern := false
	for pattern in pf_opt_list(options, 'internalPattern') {
		if pf_matches(name, pattern)! {
			matches_internal_pattern = true
			break
		}
	}
	internal_external_group := if matches_internal_pattern {
		'internal'
	} else {
		c.pfsi_internal_or_external_group(ts_config, filename, name)!
	}
	mut out := []string{}
	if config := ts_config {
		if pfsi_matches_tsconfig_paths(config, name)! {
			out << 'tsconfig-path'
		}
	}
	if name in pfsi_index_modules {
		out << 'index'
	}
	if name.starts_with('./') {
		out << 'sibling'
	}
	if name.starts_with('..') {
		out << 'parent'
	}
	if name.starts_with('#') {
		out << 'subpath'
	}
	if internal_external_group == 'internal' {
		out << 'internal'
	}
	if pfsi_is_core_module(name, pf_opt_string(options, 'environment')) {
		out << 'builtin'
	}
	if internal_external_group == 'external' {
		out << 'external'
	}
	return out
}

// pfsi_internal_or_external_group ports getInternalOrExternalGroup with TypeScript: a relative
// name is neither; without a tsconfig, any other is external; with one, a name is internal when
// it resolves to a file that is not of an external library.
fn (mut c Checker) pfsi_internal_or_external_group(ts_config ?PfsiTsConfig, filename string, name string) !string {
	if pfsi_is_external_module_name_relative(name) {
		return ''
	}
	config := ts_config or { return 'external' }
	if c.client == unsafe { nil } {
		return 'external'
	}
	resolution := c.client.resolve_module(config.path, name, os.dir(filename))!
	if !resolution.has_external_library_import {
		return 'external'
	}
	return if resolution.is_external_library_import { 'external' } else { 'internal' }
}

// pfsi_is_external_module_name_relative ports TypeScript's isExternalModuleNameRelative: `.` or
// `..` alone or before a separator, or a rooted path (pathIsRelative, isRootedDiskPath).
fn pfsi_is_external_module_name_relative(name string) bool {
	if name == '.' || name == '..' || name.starts_with('./') || name.starts_with('.\\')
		|| name.starts_with('../') || name.starts_with('..\\') {
		return true
	}
	return pfsi_encoded_root_length(name) > 0
}

// pfsi_encoded_root_length ports TypeScript's getEncodedRootLength (negative for a URL).
fn pfsi_encoded_root_length(path string) int {
	if path.len == 0 {
		return 0
	}
	ch0 := path[0]
	if ch0 == `/` || ch0 == `\\` {
		if path.len < 2 || path[1] != ch0 {
			return 1
		}
		separator := if ch0 == `/` { '/' } else { '\\' }
		p1 := path.index_after(separator, 2) or { return path.len }
		return p1 + 1
	}
	if path.len >= 2 && pfsi_is_volume_character(ch0) && path[1] == `:` {
		if path.len > 2 && (path[2] == `/` || path[2] == `\\`) {
			return 3
		}
		if path.len == 2 {
			return 2
		}
	}
	scheme_end := path.index('://') or { return 0 }
	authority_start := scheme_end + 3
	authority_end := path.index_after('/', authority_start) or { return -path.len - 1 }
	scheme := path[..scheme_end]
	authority := path[authority_start..authority_end]
	if scheme == 'file' && (authority == '' || authority == 'localhost')
		&& authority_end + 1 < path.len && pfsi_is_volume_character(path[authority_end + 1]) {
		volume_separator_end := pfsi_file_url_volume_separator_end(path, authority_end + 2)
		if volume_separator_end != -1 {
			if volume_separator_end < path.len && path[volume_separator_end] == `/` {
				return -(volume_separator_end + 1) - 1
			}
			if volume_separator_end == path.len {
				return -volume_separator_end - 1
			}
		}
	}
	return -(authority_end + 1) - 1
}

fn pfsi_is_volume_character(ch u8) bool {
	return (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
}

// pfsi_file_url_volume_separator_end ports getFileUrlVolumeSeparatorEnd.
fn pfsi_file_url_volume_separator_end(url string, start int) int {
	if start >= url.len {
		return -1
	}
	ch0 := url[start]
	if ch0 == `:` {
		return start + 1
	}
	if ch0 == `%` && start + 2 < url.len && url[start + 1] == `3` {
		ch2 := url[start + 2]
		if ch2 == `a` || ch2 == `A` {
			return start + 3
		}
	}
	return -1
}

// pfsi_is_core_module ports isCoreModule: a builtin module of Node (with or without `node:`), or
// of Bun in its environment.
fn pfsi_is_core_module(value string, environment string) bool {
	base_path := value.all_before('/')
	clean_value := pfsi_clean_node_prefix(value)
	clean_base := pfsi_clean_node_prefix(base_path)
	if clean_value in pfsi_node_builtin_modules || clean_base in pfsi_node_builtin_modules {
		return true
	}
	if value.starts_with('node:') && ('node:${clean_value}' in pfsi_builtin_prefix_only_modules
		|| 'node:${clean_base}' in pfsi_builtin_prefix_only_modules) {
		return true
	}
	return environment == 'bun' && value in pfsi_bun_modules
}

// pfsi_clean_node_prefix is `value.replace(/^(?:node:){1,2}/u, '')`.
fn pfsi_clean_node_prefix(value string) string {
	mut out := value
	for _ in 0 .. 2 {
		if out.starts_with('node:') {
			out = out[5..]
		}
	}
	return out
}

// pfsi_matches_tsconfig_paths ports matchesTsconfigPaths: a key of `paths`, its `*` matching
// anything, matches the name.
fn pfsi_matches_tsconfig_paths(config PfsiTsConfig, name string) !bool {
	for key in config.paths {
		mut escaped := ''
		for ch in key {
			if ch in [`$`, `+`, `.`, `?`, `[`, `\\`, `]`] {
				escaped += '\\'
			}
			escaped += ch.ascii_str()
		}
		pattern := '^${escaped.replace('*', '(.+)')}$'
		if pf_regexp_test(pattern, '', name)! {
			return true
		}
	}
	return false
}

// pfsi_read_closest_ts_config ports readClosestTsConfigByPath: the closest `filename` above the
// file, up to the length of `root_dir`.
fn (mut c Checker) pfsi_read_closest_ts_config(filename string, root_dir string, file_path string) !PfsiTsConfig {
	mut directory := os.dir(file_path)
	for {
		tsconfig_path := os.norm_path(os.join_path(directory, filename))
		if os.exists(tsconfig_path) {
			mut paths := []string{}
			if c.client != unsafe { nil } {
				paths = c.client.config_path_keys(tsconfig_path)!
			}
			return PfsiTsConfig{
				path:  tsconfig_path
				paths: paths
			}
		}
		parent := os.dir(directory)
		if parent == directory {
			break
		}
		directory = parent
		if !(directory.len > 1 && directory.len >= root_dir.len) {
			break
		}
	}
	return error("Couldn't find any ${filename} relative to '${file_path}' within '${root_dir}'.")
}

// --- Sort ----------------------------------------------------------------------------------------

// pfsi_sort_import_nodes ports sortImportNodes: the imports in runs without code between them, in
// partitions, sorted and reported.
fn (mut ctx PfContext) pfsi_sort_import_nodes(tree &ScopeTree, nodes []PfSortingNode, imports map[int]PfsiImport, options map[string]json2.Any) ! {
	mut content_separated := [][][]PfSortingNode{len: 1, init: [][]PfSortingNode{len: 1}}
	for node in nodes {
		last_run := content_separated[content_separated.len - 1]
		last_group := last_run[last_run.len - 1]
		mut last_node := ?int(none)
		if last_group.len > 0 {
			last_node = last_group[last_group.len - 1].node
		}
		if last := last_node {
			if ctx.tokens.inside(ctx.t.nodes[last].end, ctx.t.nodes[node.node].start, false).len > 0 {
				content_separated << [][]PfSortingNode{len: 1}
			} else if ctx.pf_should_partition(options, last, node.node, '')! {
				content_separated[content_separated.len - 1] << []PfSortingNode{}
			}
		} else if ctx.pf_should_partition(options, none, node.node, '')! {
			content_separated[content_separated.len - 1] << []PfSortingNode{}
		}
		last_index := content_separated.len - 1
		run_len := content_separated[last_index].len
		content_separated[last_index][run_len - 1] << PfSortingNode{
			...node
			partition_id: run_len
		}
	}
	groups := pf_opt_list(options, 'groups')
	sort_side_effects := pf_opt_truthy(options, 'sortSideEffects')
	type_imports := imports.keys().filter(imports[it].is_type_import)
	computer := fn [type_imports] (options map[string]json2.Any) PfComparator {
		return pfsi_comparator(options, type_imports)
	}
	ignored_nodes := imports.keys().filter(imports[it].is_ignored)
	is_node_ignored := fn [ignored_nodes] (node PfSortingNode) bool {
		return node.node in ignored_nodes
	}
	is_node_ignored_for_group := fn [sort_side_effects, groups] (_ map[string]json2.Any, group_index int, _ PfSortingNode) bool {
		if sort_side_effects {
			return false
		}
		if group_index >= groups.len {
			return false
		}
		return pfsi_is_side_effect_only_group(groups[group_index])
	}
	for run in content_separated {
		mut flat := []PfSortingNode{}
		for part in run {
			flat << part
		}
		mut dependencies := PfDependencies{}
		for sorting_node in flat {
			info := imports[sorting_node.node] or { PfsiImport{} }
			dependencies.names[sorting_node.node] = info.dependency_names
			dependencies.deps[sorting_node.node] = info.dependencies
		}
		if pf_opt_truthy(options, 'useExperimentalDependencyDetection') {
			dependencies_by_node := ctx.pf_dependencies_by_sorting_node(tree, flat, PfDependencyComputers{})
			dependencies.pf_populate_dependencies(flat, dependencies_by_node)
		}
		mut sorted := []PfSortingNode{}
		mut sorted_excluding_disabled := []PfSortingNode{}
		for part in run {
			sorted << pf_sort_nodes_by_groups_with(part, computer, options, false, is_node_ignored,
				is_node_ignored_for_group)
			sorted_excluding_disabled << pf_sort_nodes_by_groups_with(part, computer, options,
				true, is_node_ignored, is_node_ignored_for_group)
		}
		sorted = dependencies.pf_sort_nodes_by_dependencies(sorted, false)
		sorted_excluding_disabled = dependencies.pf_sort_nodes_by_dependencies(sorted_excluding_disabled,
			true)
		ctx.pf_report_all_errors_full(flat, sorted, sorted_excluding_disabled, options,
			pfsi_message_ids, PfReportExtras{
				dependencies: dependencies
			})!
	}
}

// pfsi_comparator ports comparatorByOptionsComputer of sort-imports: type imports first
// (`type-import-first`), or by the name of the first specifier (`sortBy: 'specifier'`, the
// `value` of the sorting nodes) or by the module name.
fn pfsi_comparator(options map[string]json2.Any, type_imports []int) PfComparator {
	if pf_opt_string(options, 'type') == 'type-import-first' {
		order := pf_opt_string(options, 'order')
		return PfComparator{
			cmp: fn [type_imports, order] (a &PfSortingNode, b &PfSortingNode) int {
				a_type := a.node in type_imports
				b_type := b.node in type_imports
				if a_type == b_type {
					return 0
				}
				return pf_ordered_value(if a_type { -1 } else { 1 }, order)
			}
		}
	}
	if pf_opt_string(options, 'sortBy') == 'specifier' {
		return pf_value_comparator_computer(options)
	}
	return pf_default_comparator_computer(options)
}
