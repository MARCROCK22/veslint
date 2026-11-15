module rules

import esquery
import estree
import json2
import jsregexp
import math
import treesitter { Ident }

// The shared engine of eslint-plugin-perfectionist 5.13.0 (utils/), which its sorting rules use:
// the options (complete, getSettings, the validations), the groups (computeGroup,
// doesCustomGroupMatch, getGroupIndex, computeOverriddenOptionsByGroupIndex), the partitions (by
// comment and by new line), the sort (sortNodes, sortNodesByGroups), the reports
// (reportAllErrors, reportErrors, getNewlinesBetweenErrors) and the fixes (makeFixes and the
// fixes it is made of, mergeFixes). Ported line by line on the ESTree of the estree module; the
// comparisons are in perfectionist_utils_compare.v. Offsets are bytes of the source.
//
// The options of the rules are JavaScript objects that the engine spreads over each other
// (`{ ...defaults, ...settings, ...options }`, the overrides of a group): they are kept as JSON
// objects (map[string]json2.Any) and read where the code reads them.

// PfSortingNode ports SortingNode: an element to sort. `node` (an ESTree node) is its identity.
struct PfSortingNode {
mut:
	node                             int
	name                             string
	value                            string // the value of the element (sortBy: 'value')
	group                            string
	size                             int
	partition_id                     int
	is_eslint_disabled               bool
	add_safety_semicolon_when_inline bool
	// implicitDecorators, when the node has decorators that are not its own `decorators`
	has_implicit_decorators bool
	implicit_decorators     []int
}

// PfMessageIds ports the availableMessageIds of reportAllErrors: '' for a message the rule does
// not have.
struct PfMessageIds {
	missed_spacing              string
	extra_spacing               string
	unexpected_dependency_order string
	unexpected_group_order      string
	missed_comment_above        string
	unexpected_order            string
}

// PfContext is what the engine reads of ESLint's rule context: the tree and its tokens, the id of
// the rule, its options as written (context.options) and the shared settings
// (context.settings); the reports go to `findings`.
@[heap]
struct PfContext {
	checker  &Checker
	t        &estree.EsTree
	tokens   &SourceTokens
	src      string
	rule     string
	options  []json2.Any
	settings map[string]json2.Any
mut:
	disabled_lines_done bool
	disabled_lines      map[int]bool
	findings            []Finding
}

fn (mut c Checker) pf_context(t &estree.EsTree, rule string) &PfContext {
	return &PfContext{
		checker:  c
		t:        t
		tokens:   c.un_tokens(t)
		src:      c.src
		rule:     rule
		options:  c.rule_options(rule)
		settings: c.settings
	}
}

// pf_line is the line (from 1) of an offset: `loc.start.line` of what starts there, or
// `loc.end.line` of what ends there.
fn (ctx &PfContext) pf_line(offset int) int {
	line, _ := ctx.t.line_column(offset)
	return line
}

fn (ctx &PfContext) start_line(node int) int {
	return ctx.pf_line(ctx.t.nodes[node].start)
}

fn (ctx &PfContext) end_line(node int) int {
	return ctx.pf_line(ctx.t.nodes[node].end)
}

fn (ctx &PfContext) text(node int) string {
	return ctx.src[ctx.t.nodes[node].start..ctx.t.nodes[node].end]
}

// --- Options -----------------------------------------------------------------------------------

// pf_truthy: the JSON value is truthy in JavaScript.
fn pf_truthy(value json2.Any) bool {
	return match value {
		json2.Null { false }
		bool { value }
		string { value != '' }
		[]json2.Any, map[string]json2.Any { true }
		else { json_number(value) != 0 }
	}
}

// pf_opt is the value of a key of an object, if it has the key.
fn pf_opt(options map[string]json2.Any, key string) ?json2.Any {
	if key in options {
		return options[key] or { json2.Any(json2.null) }
	}
	return none
}

fn pf_opt_string(options map[string]json2.Any, key string) string {
	value := options[key] or { return '' }
	return if value is string { value } else { '' }
}

fn pf_opt_truthy(options map[string]json2.Any, key string) bool {
	value := options[key] or { return false }
	return pf_truthy(value)
}

fn pf_opt_list(options map[string]json2.Any, key string) []json2.Any {
	value := options[key] or { return []json2.Any{} }
	return if value is []json2.Any { value } else { []json2.Any{} }
}

fn pf_opt_object(options map[string]json2.Any, key string) ?map[string]json2.Any {
	value := options[key] or { return none }
	return if value is map[string]json2.Any { value } else { none }
}

// pf_string_list: the strings of a list.
fn pf_string_list(value json2.Any) []string {
	if value is []json2.Any {
		return value.filter(it is string).map(it.str())
	}
	return []string{}
}

// pf_spread is `{ ...a, ...b }`.
fn pf_spread(a map[string]json2.Any, b map[string]json2.Any) map[string]json2.Any {
	mut out := a.clone()
	for key, value in b {
		out[key] = value
	}
	return out
}

// pf_is_newlines_between_option ports isNewlinesBetweenOption.
fn pf_is_newlines_between_option(group json2.Any) bool {
	return group is map[string]json2.Any && 'newlinesBetween' in group
}

// pf_is_group_with_overrides_option ports isGroupWithOverridesOption.
fn pf_is_group_with_overrides_option(group json2.Any) bool {
	return group is map[string]json2.Any && 'group' in group
}

// The JSON schemas of the settings (settingsJsonSchemas of get-settings.ts: the common options,
// newlinesBetween, newlinesInside, partitionByComment, partitionByNewLine and tsconfig), without
// their descriptions.
const pf_settings_json_schemas = '{"fallbackSort":{"properties":{"type":{"enum":["alphabetical","natural","line-length","custom","unsorted","subgroup-order"],"type":"string"},"order":{"enum":["asc","desc"],"type":"string"}},"additionalProperties":false,"required":["type"],"type":"object"},"type":{"enum":["alphabetical","natural","line-length","custom","unsorted","subgroup-order"],"type":"string"},"specialCharacters":{"enum":["remove","trim","keep"],"type":"string"},"ignoreCase":{"type":"boolean"},"alphabet":{"type":"string"},"locales":{"oneOf":[{"type":"string"},{"items":{"type":"string"},"type":"array"}]},"order":{"enum":["asc","desc"],"type":"string"},"newlinesBetween":{"oneOf":[{"enum":["ignore"],"type":"string"},{"type":"number","minimum":0}]},"newlinesInside":{"oneOf":[{"oneOf":[{"enum":["ignore"],"type":"string"},{"type":"number","minimum":0}]},{"enum":["newlinesBetween"],"type":"string"}]},"partitionByComment":{"oneOf":[{"type":"boolean"},{"oneOf":[{"items":{"oneOf":[{"properties":{"pattern":{"type":"string"},"flags":{"type":"string"}},"additionalProperties":false,"required":["pattern"],"type":"object"},{"type":"string"}]},"type":"array"},{"oneOf":[{"properties":{"pattern":{"type":"string"},"flags":{"type":"string"}},"additionalProperties":false,"required":["pattern"],"type":"object"},{"type":"string"}]}]},{"properties":{"block":{"oneOf":[{"type":"boolean"},{"oneOf":[{"items":{"oneOf":[{"properties":{"pattern":{"type":"string"},"flags":{"type":"string"}},"additionalProperties":false,"required":["pattern"],"type":"object"},{"type":"string"}]},"type":"array"},{"oneOf":[{"properties":{"pattern":{"type":"string"},"flags":{"type":"string"}},"additionalProperties":false,"required":["pattern"],"type":"object"},{"type":"string"}]}]}]},"line":{"oneOf":[{"type":"boolean"},{"oneOf":[{"items":{"oneOf":[{"properties":{"pattern":{"type":"string"},"flags":{"type":"string"}},"additionalProperties":false,"required":["pattern"],"type":"object"},{"type":"string"}]},"type":"array"},{"oneOf":[{"properties":{"pattern":{"type":"string"},"flags":{"type":"string"}},"additionalProperties":false,"required":["pattern"],"type":"object"},{"type":"string"}]}]}]}},"additionalProperties":false,"minProperties":1,"type":"object"}]},"partitionByNewLine":{"type":"boolean"},"tsconfig":{"properties":{"rootDir":{"type":"string"},"filename":{"type":"string"}},"additionalProperties":false,"required":["rootDir"],"type":"object"}}'

// pf_settings_schema_map are those schemas, decoded once.
const pf_settings_schema_map = pf_settings_schemas()

fn pf_settings_schemas() map[string]json2.Any {
	decoded := json2.decode[json2.Any](pf_settings_json_schemas) or { return map[string]json2.Any{} }
	return decoded.as_map()
}

// pf_get_settings ports getSettings: the `perfectionist` settings, which may only have the
// settings perfectionist knows.
fn pf_get_settings(settings map[string]json2.Any) !map[string]json2.Any {
	perfectionist := settings['perfectionist'] or { return map[string]json2.Any{} }
	if !pf_truthy(perfectionist) {
		return map[string]json2.Any{}
	}
	mut keys := []string{}
	if perfectionist is map[string]json2.Any {
		keys = perfectionist.keys()
	} else if perfectionist is string {
		keys = []string{len: utf16_units(perfectionist).len, init: index.str()}
	}
	invalid := keys.filter(it !in pf_settings_schema_map)
	if invalid.len > 0 {
		return error('Invalid Perfectionist setting(s): ${invalid.join(', ')}')
	}
	return if perfectionist is map[string]json2.Any {
		perfectionist.as_map()
	} else {
		map[string]json2.Any{}
	}
}

// pf_complete ports complete: `{ ...defaults, ...settings, ...options }`, after
// validateSettingsValues (the settings a rule uses, that the options do not override, must fit
// their schema).
fn pf_complete(options map[string]json2.Any, defaults map[string]json2.Any, settings map[string]json2.Any) !map[string]json2.Any {
	given := options.clone()
	mut invalid := []string{}
	for key, value in settings {
		schema := pf_settings_schema_map[key] or { continue }
		if key in defaults && key !in given && !pf_matches_json_schema(value, schema) {
			invalid << key
		}
	}
	if invalid.len > 0 {
		return error('Invalid value(s) for Perfectionist setting(s): ${invalid.join(', ')}')
	}
	return pf_spread(pf_spread(defaults, settings), given)
}

// pf_matches_json_schema ports matchesJsonSchema.
fn pf_matches_json_schema(value json2.Any, schema_value json2.Any) bool {
	if schema_value !is map[string]json2.Any {
		return true
	}
	schema := schema_value.as_map()
	if one_of := schema['oneOf'] {
		if one_of is []json2.Any {
			if one_of.filter(pf_matches_json_schema(value, it)).len != 1 {
				return false
			}
		}
	}
	match pf_opt_string(schema, 'type') {
		'boolean' {
			return value is bool
		}
		'string' {
			if value !is string {
				return false
			}
			if values := schema['enum'] {
				if values is []json2.Any {
					return values.any(it is string && it.str() == value.str())
				}
			}
			return true
		}
		'number' {
			if json_kind(value) != .number {
				return false
			}
			minimum := if m := schema['minimum'] { json_number(m) } else { -math.max_f64 }
			return json_number(value) >= minimum
		}
		'object' {
			return value is map[string]json2.Any && pf_matches_object_json_schema(value.as_map(),
				schema)
		}
		'array' {
			if value !is []json2.Any {
				return false
			}
			items := schema['items'] or { return true }
			return value.as_array().all(pf_matches_json_schema(it, items))
		}
		else {
			return true
		}
	}
}

fn pf_matches_object_json_schema(value map[string]json2.Any, schema map[string]json2.Any) bool {
	minimum := if m := schema['minProperties'] { int(json_number(m)) } else { 0 }
	if value.len < minimum {
		return false
	}
	if required := schema['required'] {
		if required is []json2.Any {
			for key in required {
				if key.str() !in value {
					return false
				}
			}
		}
	}
	properties := pf_opt_object(schema, 'properties') or { map[string]json2.Any{} }
	for key, item in value {
		property := properties[key] or {
			additional := schema['additionalProperties'] or { json2.Any(true) }
			if additional is bool && !additional {
				return false
			}
			continue
		}
		if !pf_matches_json_schema(item, property) {
			return false
		}
	}
	return true
}

// pf_validate_custom_sort_config ports validateCustomSortConfig.
fn pf_validate_custom_sort_config(options map[string]json2.Any) ! {
	mut uses_custom := pf_opt_string(options, 'type') == 'custom'
	if !uses_custom {
		for group in pf_opt_list(options, 'groups') {
			if pf_is_group_with_overrides_option(group)
				&& pf_opt_string(group.as_map(), 'type') == 'custom' {
				uses_custom = true
			}
		}
	}
	if !uses_custom {
		return
	}
	if utf16_units(pf_opt_string(options, 'alphabet')).len == 0 {
		return error('`alphabet` option must not be empty')
	}
}

// pf_validate_groups_config ports validateGroupsConfig (with validateNoDuplicatedGroups and
// validateObjectsInsideGroups).
fn pf_validate_groups_config(options map[string]json2.Any, selectors []string, modifiers []string) ! {
	custom_group_names := pf_opt_list(options, 'customGroups').map(if it is map[string]json2.Any {
		pf_opt_string(it, 'groupName')
	} else {
		''
	})
	groups := pf_opt_list(options, 'groups')
	invalid := pf_compute_groups_names(groups).filter(!pf_is_predefined_group(selectors,
		modifiers, it) && it !in custom_group_names)
	if invalid.len > 0 {
		return error('Invalid group(s): ${invalid.join(', ')}')
	}
	mut seen := []string{}
	mut duplicated := []string{}
	for name in pf_compute_groups_names(groups) {
		if name in seen {
			if name !in duplicated {
				duplicated << name
			}
		} else {
			seen << name
		}
	}
	if duplicated.len > 0 {
		return error('Duplicated group(s): ${duplicated.join(', ')}')
	}
	mut previous_non_group := false
	for group in groups {
		names := pf_compute_groups_names([group])
		if names.len > 0 && names[0] != '' {
			previous_non_group = false
			continue
		}
		if previous_non_group {
			return error('Consecutive `newlinesBetween` objects are not allowed')
		}
		previous_non_group = true
	}
}

// pf_is_predefined_group ports isPredefinedGroup: `unknown`, or a selector after modifiers, each
// once.
fn pf_is_predefined_group(selectors []string, modifiers []string, input string) bool {
	if input == 'unknown' {
		return true
	}
	elements := input.split('-')
	selector_words := pf_longest_allowed_word(elements, selectors) or { return false }
	mut to_parse := elements[..elements.len - selector_words].clone()
	mut parsed := []string{}
	for to_parse.len > 0 {
		count := pf_longest_allowed_word(to_parse, modifiers) or { return false }
		word := to_parse[to_parse.len - count..].join('-')
		if word in parsed {
			return false
		}
		parsed << word
		to_parse = to_parse[..to_parse.len - count].clone()
	}
	return true
}

// pf_longest_allowed_word ports computeLongestAllowedWord: how many of the last elements (3, 2
// or 1) make an allowed word.
fn pf_longest_allowed_word(elements []string, allowed []string) ?int {
	for count in [3, 2, 1] {
		if elements.len < count {
			continue
		}
		word := elements[elements.len - count..].join('-')
		if word != '' && word in allowed {
			return count
		}
	}
	return none
}

// pf_validate_newlines_and_partition_config ports validateNewlinesAndPartitionConfig.
fn pf_validate_newlines_and_partition_config(options map[string]json2.Any) ! {
	if !pf_opt_truthy(options, 'partitionByNewLine') {
		return
	}
	newlines_between_error := "The 'partitionByNewLine' and 'newlinesBetween' options cannot be used together"
	newlines_inside_error := "The 'partitionByNewLine' and 'newlinesInside' options cannot be used together"
	if pf_opt_string(options, 'newlinesBetween') != 'ignore' {
		return error(newlines_between_error)
	}
	groups := pf_opt_list(options, 'groups')
	for group in groups {
		if pf_is_newlines_between_option(group) {
			value := group.as_map()['newlinesBetween'] or { json2.Any('') }
			if !(value is string && value.str() == 'ignore') {
				return error(newlines_between_error)
			}
		}
	}
	inside := options['newlinesInside'] or { json2.Any(json2.null) }
	if !(inside is string && inside.str() in ['newlinesBetween', 'ignore']) {
		return error(newlines_inside_error)
	}
	is_valid := fn (value ?json2.Any) bool {
		v := value or { return true }
		return v is string && v.str() == 'ignore'
	}
	for group in groups {
		if !pf_is_group_with_overrides_option(group) {
			continue
		}
		if !is_valid(pf_opt(group.as_map(), 'newlinesInside')) {
			return error(newlines_inside_error)
		}
	}
	for custom_group in pf_opt_list(options, 'customGroups') {
		if custom_group is map[string]json2.Any {
			if !is_valid(pf_opt(custom_group, 'newlinesInside')) {
				return error(newlines_inside_error)
			}
		}
	}
}

// --- Regular expressions -----------------------------------------------------------------------

// pf_new_regexp ports `new RegExp(pattern, flags)` for a test: the flags `g` and `d` do not
// change it, and `y` makes it match at the start only (pf_regexp_test).
fn pf_new_regexp(pattern string, flags string) !jsregexp.JsRegex {
	mut kept := ''
	for f in flags {
		if f in [`g`, `d`, `y`] {
			if flags.count(f.ascii_str()) > 1 {
				return error("Invalid flags supplied to RegExp constructor '${flags}'")
			}
			continue
		}
		kept += f.ascii_str()
	}
	return jsregexp.js_regex_new(pattern, kept)
}

// pf_regexp_test ports `new RegExp(pattern, flags).test(value)`.
fn pf_regexp_test(pattern string, flags string, value string) !bool {
	re := pf_new_regexp(pattern, flags)!
	units := utf16_units(value)
	if flags.contains('y') {
		found, start, _, _ := re.exec(units, 0)!
		return found && start == 0
	}
	return re.test(units)!
}

// pf_matches ports matches: the value matches the pattern (a string, an object with `pattern`
// and `flags`, or a list of them, any of which).
fn pf_matches(value string, regex_option json2.Any) !bool {
	if regex_option is []json2.Any {
		for option in regex_option {
			if pf_matches(value, option)! {
				return true
			}
		}
		return false
	}
	if regex_option is string {
		return pf_regexp_test(regex_option, '', value)
	}
	if regex_option is map[string]json2.Any {
		pattern := regex_option['pattern'] or { json2.Any('undefined') }
		flags := pf_opt_string(regex_option, 'flags')
		return pf_regexp_test(if pattern is string { pattern } else { pattern.str() }, flags,
			value)
	}
	return pf_regexp_test(regex_option.str(), '', value)
}

// --- Groups ------------------------------------------------------------------------------------

// pf_compute_group_names ports computeGroupNames of compute-groups-names.ts: the names of an
// element of `groups`.
fn pf_compute_group_names(group json2.Any) []string {
	if group is string {
		return [group]
	}
	if group is []json2.Any {
		return pf_string_list(group)
	}
	if pf_is_group_with_overrides_option(group) {
		return pf_compute_group_names(group.as_map()['group'] or { json2.Any([]json2.Any{}) })
	}
	return []string{}
}

// pf_compute_groups_names ports computeGroupsNames.
fn pf_compute_groups_names(groups []json2.Any) []string {
	mut out := []string{}
	for group in groups {
		out << pf_compute_group_names(group)
	}
	return out
}

// pf_compute_group_name ports computeGroupName: the name of a group that is a single one.
fn pf_compute_group_name(group json2.Any) ?string {
	if group is string {
		return group
	}
	if pf_is_group_with_overrides_option(group) {
		inner := group.as_map()['group'] or { return none }
		if inner is string {
			return inner
		}
	}
	return none
}

// pf_get_group_index ports getGroupIndex: the index of the element of `groups` that has the
// group, or the number of groups.
fn pf_get_group_index(groups []json2.Any, group_name string) int {
	for i, group in groups {
		if pf_does_group_match(group, group_name) {
			return i
		}
	}
	return groups.len
}

fn pf_does_group_match(group json2.Any, group_name string) bool {
	if group is string {
		return group == group_name
	}
	if group is []json2.Any {
		return group_name in pf_string_list(group)
	}
	if pf_is_group_with_overrides_option(group) {
		return pf_does_group_match(group.as_map()['group'] or { json2.Any(json2.null) }, group_name)
	}
	return false
}

// pf_generate_predefined_groups ports generatePredefinedGroups: for each selector, every
// permutation of every combination of the modifiers before it (the most modifiers first), then the
// selector alone.
fn pf_generate_predefined_groups(selectors []string, modifiers []string) []string {
	mut combinations := [][]string{}
	for i := modifiers.len; i > 0; i-- {
		combinations << pf_array_combinations(modifiers, i)
	}
	mut permutations := [][]string{}
	for combination in combinations {
		permutations << pf_permutations(combination)
	}
	mut out := []string{}
	for selector in selectors {
		for permutation in permutations {
			mut parts := permutation.clone()
			parts << selector
			out << parts.join('-')
		}
		out << selector
	}
	return out
}

// pf_array_combinations ports getArrayCombinations.
fn pf_array_combinations(array []string, number int) [][]string {
	mut result := [][]string{}
	mut comb := []string{}
	pf_combinations_backtrack(array, number, 0, mut comb, mut result)
	return result
}

fn pf_combinations_backtrack(array []string, number int, start int, mut comb []string, mut result [][]string) {
	if comb.len == number {
		result << comb.clone()
		return
	}
	for i in start .. array.len {
		comb << array[i]
		pf_combinations_backtrack(array, number, i + 1, mut comb, mut result)
		comb.delete_last()
	}
}

// pf_permutations ports getPermutations (by swaps, in its order).
fn pf_permutations(elements []string) [][]string {
	mut items := elements.clone()
	mut result := [][]string{}
	pf_permutations_backtrack(mut items, 0, mut result)
	return result
}

fn pf_permutations_backtrack(mut elements []string, first int, mut result [][]string) {
	if first == elements.len {
		result << elements.clone()
		return
	}
	for i in first .. elements.len {
		elements[first], elements[i] = elements[i], elements[first]
		pf_permutations_backtrack(mut elements, first + 1, mut result)
		elements[first], elements[i] = elements[i], elements[first]
	}
}

// PfElement is what doesCustomGroupMatch reads of an element.
struct PfElement {
	name            string
	selectors       []string
	modifiers       []string
	value           ?string
	decorator_names []string
}

// pf_compute_group ports computeGroup: the first custom group in `groups` the element matches,
// or its first predefined group in `groups`, or `unknown`.
fn pf_compute_group(options map[string]json2.Any, predefined_groups []string, element PfElement) !string {
	groups_set := pf_compute_groups_names(pf_opt_list(options, 'groups'))
	for custom_group in pf_opt_list(options, 'customGroups') {
		if custom_group !is map[string]json2.Any {
			continue
		}
		group_name := pf_opt_string(custom_group.as_map(), 'groupName')
		if pf_does_custom_group_match(custom_group.as_map(), element)! && group_name in groups_set {
			return group_name
		}
	}
	for group in predefined_groups {
		if group in groups_set {
			return group
		}
	}
	return 'unknown'
}

// pf_does_custom_group_match ports doesCustomGroupMatch.
fn pf_does_custom_group_match(custom_group map[string]json2.Any, element PfElement) !bool {
	if 'anyOf' in custom_group {
		for subgroup in pf_opt_list(custom_group, 'anyOf') {
			if subgroup is map[string]json2.Any {
				if pf_does_single_custom_group_match(subgroup.as_map(), element)! {
					return true
				}
			}
		}
		return false
	}
	return pf_does_single_custom_group_match(custom_group, element)
}

fn pf_does_single_custom_group_match(custom_group map[string]json2.Any, element PfElement) !bool {
	if selector := custom_group['selector'] {
		if pf_truthy(selector) && selector.str() !in element.selectors {
			return false
		}
	}
	if modifiers := custom_group['modifiers'] {
		if modifiers is []json2.Any {
			for modifier in modifiers {
				if modifier.str() !in element.modifiers {
					return false
				}
			}
		}
	}
	if pattern := custom_group['elementNamePattern'] {
		if pf_truthy(pattern) && !pf_matches(element.name, pattern)! {
			return false
		}
	}
	if pattern := custom_group['elementValuePattern'] {
		if pf_truthy(pattern) && !pf_matches(element.value or { '' }, pattern)! {
			return false
		}
	}
	if pattern := custom_group['decoratorNamePattern'] {
		if pf_truthy(pattern) {
			mut matched := false
			for decorator in element.decorator_names {
				if pf_matches(decorator, pattern)! {
					matched = true
					break
				}
			}
			if !matched {
				return false
			}
		}
	}
	return true
}

// pf_overridden_options_by_group_index ports computeOverriddenOptionsByGroupIndex: the options
// with those of the group at that index (a group with overrides) and of its custom group.
fn pf_overridden_options_by_group_index(options map[string]json2.Any, group_index int) map[string]json2.Any {
	groups := pf_opt_list(options, 'groups')
	matching_group := if group_index >= 0 && group_index < groups.len {
		?json2.Any(groups[group_index])
	} else {
		?json2.Any(none)
	}
	mut matching_group_name := ?string(none)
	if group := matching_group {
		matching_group_name = pf_compute_group_name(group)
	}
	mut custom_group := ?map[string]json2.Any(none)
	for current in pf_opt_list(options, 'customGroups') {
		if current is map[string]json2.Any {
			current_name := current['groupName'] or { json2.Any(json2.null) }
			if name := matching_group_name {
				if current_name is string && current_name.str() == name {
					custom_group = current.as_map()
					break
				}
			}
		}
	}
	mut out := options.clone()
	if group := matching_group {
		if pf_is_group_with_overrides_option(group) {
			out = pf_override_options(out, group.as_map(), ['newlinesInside', 'commentAbove',
				'fallbackSort', 'group'])
		}
	}
	if group := custom_group {
		out = pf_override_options(out, group, ['elementNamePattern', 'newlinesInside', 'fallbackSort',
			'groupName'])
	}
	return out
}

// pf_override_options is `{ ...options, ...relevantFields, fallbackSort: { ...options.fallbackSort,
// ...overrides.fallbackSort } }`, the relevant fields being those of `overrides` but `left_out`.
fn pf_override_options(options map[string]json2.Any, overrides map[string]json2.Any, left_out []string) map[string]json2.Any {
	mut out := options.clone()
	for key, value in overrides {
		if key !in left_out {
			out[key] = value
		}
	}
	mut fallback := map[string]json2.Any{}
	if base := options['fallbackSort'] {
		if base is map[string]json2.Any {
			fallback = base.as_map().clone()
		}
	}
	if extra := overrides['fallbackSort'] {
		if extra is map[string]json2.Any {
			for key, value in extra.as_map() {
				fallback[key] = value
			}
		}
	}
	out['fallbackSort'] = json2.Any(fallback)
	return out
}

// --- Newlines between --------------------------------------------------------------------------

// A NewlinesBetweenOption: a number of lines, or 'ignore' (pf_ignore).
const pf_ignore = -1.0

fn pf_newlines_value(value json2.Any) f64 {
	if value is string {
		return pf_ignore
	}
	return json_number(value)
}

// pf_get_newlines_between_option ports getNewlinesBetweenOption: the lines between a node of a
// group and the next one, of the next group.
fn pf_get_newlines_between_option(options map[string]json2.Any, node_group_index int, next_node_group_index int) f64 {
	if node_group_index == next_node_group_index {
		return pf_newlines_inside_option(options, node_group_index)
	}
	if next_node_group_index >= node_group_index + 2 {
		return pf_newlines_between_different_groups(options, node_group_index, next_node_group_index)
	}
	return pf_newlines_value(options['newlinesBetween'] or { json2.Any('ignore') })
}

fn pf_newlines_between_different_groups(options map[string]json2.Any, node_group_index int, next_node_group_index int) f64 {
	groups := pf_opt_list(options, 'groups')
	global := options['newlinesBetween'] or { json2.Any('ignore') }
	if next_node_group_index == node_group_index + 2 {
		group_between := groups[node_group_index + 1]
		if pf_is_newlines_between_option(group_between) {
			return pf_newlines_value(group_between.as_map()['newlinesBetween'] or {
				json2.Any('ignore')
			})
		}
		return pf_newlines_value(global)
	}
	end := if next_node_group_index + 1 < groups.len {
		next_node_group_index + 1
	} else {
		groups.len
	}
	relevant := if node_group_index < end { groups[node_group_index..end] } else { []json2.Any{} }
	// buildGroupsWithAllNewlinesBetween: the global option between two groups without one.
	mut values := []f64{}
	for i, group in relevant {
		if !pf_is_newlines_between_option(group) && i > 0
			&& !pf_is_newlines_between_option(relevant[i - 1]) {
			values << pf_newlines_value(global)
		}
		if pf_is_newlines_between_option(group) {
			values << pf_newlines_value(group.as_map()['newlinesBetween'] or { json2.Any('ignore') })
		}
	}
	mut max := pf_ignore
	mut has_number := false
	mut has_ignore := false
	for value in values {
		if value == pf_ignore {
			has_ignore = true
			continue
		}
		if !has_number || value > max {
			max = value
		}
		has_number = true
	}
	if has_number && max >= 1 {
		return max
	}
	if has_ignore {
		return pf_ignore
	}
	return 0
}

// pf_newlines_inside_option ports computeNewlinesInsideOption.
fn pf_newlines_inside_option(options map[string]json2.Any, group_index int) f64 {
	inside := options['newlinesInside'] or { json2.Any('newlinesBetween') }
	global := if inside is string {
		if inside == 'newlinesBetween' {
			between := options['newlinesBetween'] or { json2.Any('ignore') }
			if between is string { pf_ignore } else { 0.0 }
		} else {
			pf_ignore
		}
	} else {
		json_number(inside)
	}
	groups := pf_opt_list(options, 'groups')
	if group_index < 0 || group_index >= groups.len {
		return global
	}
	group := groups[group_index]
	group_name := pf_compute_group_name(group)
	for custom_group in pf_opt_list(options, 'customGroups') {
		if custom_group is map[string]json2.Any {
			name := custom_group['groupName'] or { json2.Any(json2.null) }
			matches_name := if gn := group_name {
				name is string && name.str() == gn
			} else {
				// `null === groupName` never holds for a custom group's name.
				false
			}
			if matches_name {
				if value := custom_group['newlinesInside'] {
					if value !is json2.Null {
						return pf_newlines_value(value)
					}
				}
				break
			}
		}
	}
	if pf_is_group_with_overrides_option(group) {
		if value := group.as_map()['newlinesInside'] {
			if value !is json2.Null {
				return pf_newlines_value(value)
			}
		}
	}
	return global
}

// pf_lines_between ports getLinesBetween: the blank lines between the end of one node and the
// start of the other.
fn (ctx &PfContext) pf_lines_between(left int, right int) int {
	from := ctx.end_line(left)
	to := ctx.start_line(right) - 1
	mut count := 0
	for line in from .. to {
		if js_trim(ctx.line_text(line)).len == 0 {
			count++
		}
	}
	return count
}

// line_text is `sourceCode.lines[index]`: the text of a line (from 0), without its terminator.
fn (ctx &PfContext) line_text(index int) string {
	starts := ctx.t.line_starts
	if starts.len == 0 {
		return if index == 0 { ctx.src } else { '' }
	}
	if index < 0 || index >= starts.len {
		return ''
	}
	start := starts[index]
	end := if index + 1 < starts.len { starts[index + 1] } else { ctx.src.len }
	// The terminator is white space: trim takes it away anyway.
	return ctx.src[start..end]
}

// pf_newlines_between_errors ports getNewlinesBetweenErrors.
fn (ctx &PfContext) pf_newlines_between_errors(options map[string]json2.Any, left PfSortingNode, right PfSortingNode, left_group_index int, right_group_index int, ids PfMessageIds) []string {
	if left_group_index > right_group_index || left.partition_id != right.partition_id {
		return []string{}
	}
	newlines_between := pf_get_newlines_between_option(options, left_group_index, right_group_index)
	if newlines_between == pf_ignore {
		return []string{}
	}
	lines := f64(ctx.pf_lines_between(left.node, right.node))
	if lines < newlines_between {
		return [ids.missed_spacing]
	}
	if lines > newlines_between {
		return [ids.extra_spacing]
	}
	return []string{}
}

// --- Comments and partitions -------------------------------------------------------------------

// pf_comment_value is the `value` of a comment: its text without `//`, or `/*` and `*/`.
fn (ctx &PfContext) pf_comment_value(comment SourceToken) string {
	if comment.kind == .block_comment {
		return ctx.src[comment.start + 2..comment.end - 2]
	}
	return ctx.src[comment.start + 2..comment.end]
}

// PfDisabledRules ports the result of getEslintDisabledRules.
struct PfDisabledRules {
	directive string
	all       bool
	rules     []string
}

const pf_eslint_disable_directives = ['eslint-disable', 'eslint-enable', 'eslint-disable-line',
	'eslint-disable-next-line']
const pf_re_justification = jsregexp.js_regex_new('\\s-{2,}\\s', 'u') or { panic(err) }

// pf_get_eslint_disabled_rules ports getEslintDisabledRules: the directive of a comment and the
// rules it names (all of them without names).
fn pf_get_eslint_disabled_rules(comment string) ?PfDisabledRules {
	if !comment.contains('eslint-') {
		return none
	}
	directive_part := pf_directive_part(comment)
	for directive in pf_eslint_disable_directives {
		if directive_part == directive {
			return PfDisabledRules{
				directive: directive
				all:       true
			}
		}
		// `^${directive} ((?:.|\s)*)$`: the directive, a space and something.
		prefix := directive + ' '
		if directive_part.starts_with(prefix) && directive_part.len > prefix.len {
			names := directive_part[prefix.len..].split(',').map(js_trim(it)).filter(it != '')
			return PfDisabledRules{
				directive: directive
				rules:     names
			}
		}
	}
	return none
}

// pf_directive_part ports getDirectivePart: the comment before its justification (` -- `),
// trimmed.
fn pf_directive_part(comment string) string {
	units := utf16_units(comment)
	found, start, _, _ := pf_re_justification.exec(units, 0) or { return js_trim(comment) }
	if !found {
		return js_trim(comment)
	}
	// In the `u` mode the index counts code points.
	points := jsregexp.utf16_code_points(units)
	mut before := []u16{}
	for c in points[..start] {
		jsregexp.append_utf16(mut before, c)
	}
	return js_trim(stv_units_string(before))
}

// pf_eslint_disabled_lines ports getEslintDisabledLines: the lines where a comment disables the
// rule.
fn (mut ctx PfContext) pf_eslint_disabled_lines() map[int]bool {
	if ctx.disabled_lines_done {
		return ctx.disabled_lines
	}
	mut out := map[int]bool{}
	mut permanently_disabled := 0
	for comment in ctx.tokens.comments {
		if comment.kind == .shebang_comment {
			continue
		}
		disabled := pf_get_eslint_disabled_rules(ctx.pf_comment_value(comment)) or { continue }
		if !disabled.all && ctx.rule !in disabled.rules {
			continue
		}
		match disabled.directive {
			'eslint-disable-next-line' {
				out[ctx.pf_line(comment.end) + 1] = true
			}
			'eslint-disable-line' {
				out[ctx.pf_line(comment.start)] = true
			}
			'eslint-disable' {
				if permanently_disabled == 0 {
					permanently_disabled = ctx.pf_line(comment.start)
				}
			}
			else {
				if permanently_disabled == 0 {
					continue
				}
				for line in permanently_disabled + 1 .. ctx.pf_line(comment.start) + 1 {
					out[line] = true
				}
				permanently_disabled = 0
			}
		}
	}
	ctx.disabled_lines = out.clone()
	ctx.disabled_lines_done = true
	return out
}

// pf_is_node_eslint_disabled ports isNodeEslintDisabled.
fn (mut ctx PfContext) pf_is_node_eslint_disabled(node int) bool {
	return ctx.start_line(node) in ctx.pf_eslint_disabled_lines()
}

// pf_comments_before_offset ports getRelevantCommentsBeforeNodeOrToken: the comments right before
// what starts at `offset`, but a shebang and a comment on the line of the token before it.
fn (ctx &PfContext) pf_comments_before_offset(offset int) []SourceToken {
	mut out := []SourceToken{}
	for comment in ctx.tokens.comments_before(offset) {
		if comment.kind == .shebang_comment {
			continue
		}
		if before := ctx.tokens.before(comment.start, false) {
			if ctx.pf_line(before.end) == ctx.pf_line(comment.start) {
				continue
			}
		}
		out << comment
	}
	return out
}

// pf_get_comments_before ports getCommentsBefore: those comments of the node or, when it has none
// and the token before it is `token_value_to_ignore_before`, of that token.
fn (ctx &PfContext) pf_get_comments_before(node int, token_value_to_ignore_before string) []SourceToken {
	comments := ctx.pf_comments_before_offset(ctx.t.nodes[node].start)
	if token_value_to_ignore_before == '' || comments.len > 0 {
		return comments
	}
	before := ctx.tokens.before(ctx.t.nodes[node].start, false) or { return comments }
	if ctx.src[before.start..before.end] != token_value_to_ignore_before {
		return comments
	}
	return ctx.pf_comments_before_offset(before.start)
}

// pf_is_partition_comment ports isPartitionComment.
fn (ctx &PfContext) pf_is_partition_comment(partition_by_comment json2.Any, comment SourceToken) !bool {
	value := ctx.pf_comment_value(comment)
	if !pf_truthy(partition_by_comment) {
		return false
	}
	if _ := pf_get_eslint_disabled_rules(value) {
		return false
	}
	trimmed := js_trim(value)
	if partition_by_comment is bool || partition_by_comment is string
		|| partition_by_comment is []json2.Any {
		return pf_trimmed_comment_is_partition(partition_by_comment, trimmed)
	}
	if partition_by_comment !is map[string]json2.Any {
		return false
	}
	object := partition_by_comment.as_map()
	mut relevant := ?json2.Any(none)
	if comment.kind == .block_comment && 'block' in object {
		relevant = object['block'] or { json2.Any(json2.null) }
	}
	if comment.kind == .line_comment && 'line' in object {
		relevant = object['line'] or { json2.Any(json2.null) }
	}
	option := relevant or { return false }
	return pf_trimmed_comment_is_partition(option, trimmed)
}

fn pf_trimmed_comment_is_partition(partition_by_comment json2.Any, trimmed string) !bool {
	if partition_by_comment is bool {
		return partition_by_comment
	}
	return pf_matches(trimmed, partition_by_comment)
}

// pf_should_partition ports shouldPartition: a partition comment before the node, or (with
// partitionByNewLine) a blank line between it and the last one.
fn (ctx &PfContext) pf_should_partition(options map[string]json2.Any, last_node ?int, node int, token_value_to_ignore_before string) !bool {
	partition_by_comment := options['partitionByComment'] or { json2.Any(false) }
	if pf_truthy(partition_by_comment) {
		for comment in ctx.pf_get_comments_before(node, token_value_to_ignore_before) {
			if ctx.pf_is_partition_comment(partition_by_comment, comment)! {
				return true
			}
		}
	}
	last := last_node or { return false }
	return pf_opt_truthy(options, 'partitionByNewLine') && ctx.pf_lines_between(last, node) != 0
}

// --- Sort --------------------------------------------------------------------------------------

// pf_stable_sort sorts the indexes of `nodes` by the comparators, keeping the order of equal ones
// (Array.prototype.toSorted is stable): a merge sort.
fn pf_stable_sort(nodes []PfSortingNode, comparators []PfComparator) []PfSortingNode {
	if nodes.len < 2 || comparators.len == 0 {
		return nodes.clone()
	}
	cmp := fn [comparators] (a &PfSortingNode, b &PfSortingNode) int {
		for comparator in comparators {
			// unsortedComparator gives 0.
			if comparator.unsorted {
				continue
			}
			result := comparator.cmp(a, b)
			if result != 0 {
				return result
			}
		}
		return 0
	}
	mut items := nodes.clone()
	mut buffer := []PfSortingNode{len: items.len}
	mut width := 1
	for width < items.len {
		mut lo := 0
		for lo < items.len {
			mid := if lo + width < items.len { lo + width } else { items.len }
			hi := if lo + 2 * width < items.len { lo + 2 * width } else { items.len }
			mut i := lo
			mut j := mid
			mut k := lo
			for i < mid && j < hi {
				if unsafe { cmp(&items[j], &items[i]) } < 0 {
					buffer[k] = items[j]
					j++
				} else {
					buffer[k] = items[i]
					i++
				}
				k++
			}
			for i < mid {
				buffer[k] = items[i]
				i++
				k++
			}
			for j < hi {
				buffer[k] = items[j]
				j++
				k++
			}
			lo = hi
		}
		unsafe {
			items, buffer = buffer, items
		}
		width *= 2
	}
	return items
}

// pf_sort_nodes ports sortNodes: the nodes sorted by the comparators of the options, the ignored
// ones (eslint-disabled ones with `ignore_eslint_disabled`, and those of `ignored`) left where
// they are.
fn pf_sort_nodes(nodes []PfSortingNode, computer PfComparatorComputer, options map[string]json2.Any, ignore_eslint_disabled bool, ignored []int) []PfSortingNode {
	mut non_ignored := []PfSortingNode{}
	mut ignored_indices := []int{}
	for index, node in nodes {
		if (ignore_eslint_disabled && node.is_eslint_disabled) || node.node in ignored {
			ignored_indices << index
		} else {
			non_ignored << node
		}
	}
	mut sorted := pf_stable_sort(non_ignored, pf_compute_comparators(computer, options))
	for index in ignored_indices {
		sorted.insert(if index <= sorted.len { index } else { sorted.len }, nodes[index])
	}
	return sorted
}

// pf_sort_nodes_by_groups ports sortNodesByGroups: the nodes by the index of their group, each
// group sorted with its own options (pf_overridden_options_by_group_index).
fn pf_sort_nodes_by_groups(nodes []PfSortingNode, computer PfComparatorComputer, options map[string]json2.Any, ignore_eslint_disabled bool) []PfSortingNode {
	groups := pf_opt_list(options, 'groups')
	mut by_group := map[int][]PfSortingNode{}
	mut ignored_indices := []int{}
	for index, node in nodes {
		if ignore_eslint_disabled && node.is_eslint_disabled {
			ignored_indices << index
			continue
		}
		group_index := pf_get_group_index(groups, node.group)
		by_group[group_index] << node
	}
	mut indexes := by_group.keys()
	indexes.sort()
	mut sorted := []PfSortingNode{}
	for group_index in indexes {
		group_options := pf_overridden_options_by_group_index(options, group_index)
		sorted << pf_sort_nodes(by_group[group_index], computer, group_options, false, [])
	}
	for index in ignored_indices {
		sorted.insert(if index <= sorted.len { index } else { sorted.len }, nodes[index])
	}
	return sorted
}

// pf_can_report_errors ports canReportErrors for rules without dependencies or a
// newlinesBetweenValueGetter.
fn pf_can_report_errors(options map[string]json2.Any, computer PfComparatorComputer, ids PfMessageIds) bool {
	has_groups := pf_opt_list(options, 'groups').len > 0
	if ids.unexpected_order != '' && (has_groups || pf_compute_comparators(computer, options).len > 0) {
		return true
	}
	can_report_spacing := has_groups || pf_get_newlines_between_option(options, 0, 0) != pf_ignore
	if ids.missed_spacing != '' && can_report_spacing {
		return true
	}
	if ids.extra_spacing != '' && can_report_spacing {
		return true
	}
	if ids.unexpected_group_order != '' && has_groups {
		return true
	}
	if ids.missed_comment_above != '' && has_groups {
		return true
	}
	return false
}

// --- Reports -----------------------------------------------------------------------------------

// pf_report_all_errors ports reportAllErrors (without the dependencies and the comments above
// groups, which these rules do not have): `sorted` and `sorted_excluding_disabled` are what
// sortNodesExcludingEslintDisabled gives with false and with true.
fn (mut ctx PfContext) pf_report_all_errors(nodes []PfSortingNode, sorted []PfSortingNode, sorted_excluding_disabled []PfSortingNode, options map[string]json2.Any, ids PfMessageIds) ! {
	groups := pf_opt_list(options, 'groups')
	mut index_of := map[int]int{}
	for index, node in sorted {
		index_of[node.node] = index
	}
	mut has_fix := false
	mut fix := Fix{}
	mut fix_done := false
	for i, right in nodes {
		mut message_ids := []string{}
		right_group_index := pf_get_group_index(groups, right.group)
		right_index := index_of[right.node] or { 0 }
		mut left_group_index := 0
		if i > 0 {
			left := nodes[i - 1]
			left_group_index = pf_get_group_index(groups, left.group)
			left_index := index_of[left.node] or { 0 }
			index_of_right_excluding_disabled := sorted_excluding_disabled.map(it.node).index(right.node)
			if left_index > right_index
				|| (left.is_eslint_disabled && left_index >= index_of_right_excluding_disabled) {
				message_ids << if left_group_index == right_group_index
					|| ids.unexpected_group_order == '' {
					ids.unexpected_order
				} else {
					ids.unexpected_group_order
				}
			}
			if ids.missed_spacing != '' && ids.extra_spacing != '' {
				message_ids << ctx.pf_newlines_between_errors(options, left, right, left_group_index,
					right_group_index, ids)
			}
		}
		if message_ids.len == 0 {
			continue
		}
		if !fix_done {
			has_fix, fix = ctx.pf_merge_fixes(ctx.pf_make_fixes(nodes, sorted_excluding_disabled,
				options, false))!
			fix_done = true
		}
		for message_id in message_ids {
			mut data := {
				'left':       if i > 0 { pf_to_single_line(nodes[i - 1].name) } else { '' }
				'right':      pf_to_single_line(right.name)
				'rightGroup': right.group
			}
			if i > 0 {
				data['leftGroup'] = nodes[i - 1].group
			}
			ctx.findings << Finding{
				stmt:       Ident{
					start_byte: ctx.t.nodes[right.node].start
					end_byte:   ctx.t.nodes[right.node].end
				}
				message_id: message_id
				data:       data
				has_fix:    has_fix
				fix:        fix
			}
		}
	}
}

const pf_re_spaces = jsregexp.js_regex_new('\\s{2,}', 'u') or { panic(err) }

// pf_to_single_line ports toSingleLine: runs of white space as one space, trimmed.
fn pf_to_single_line(value string) string {
	replaced := pf_regex_replace(pf_re_spaces, utf16_units(value), true, true, fn (_ []u16) []u16 {
		return [u16(` `)]
	})
	return js_trim(stv_units_string(replaced))
}

// --- Fixes -------------------------------------------------------------------------------------

// pf_make_fixes ports makeFixes (without the comments above groups): the order fixes and, when
// the comments after nodes do not move, the fixes of the new lines between the nodes.
fn (ctx &PfContext) pf_make_fixes(nodes []PfSortingNode, sorted []PfSortingNode, options map[string]json2.Any, ignore_first_node_highest_block_comment bool) []Fix {
	order_fixes := ctx.pf_make_order_fixes(nodes, sorted, options, ignore_first_node_highest_block_comment)
	comment_after_fixes := ctx.pf_make_comment_after_fixes(nodes, sorted)
	if comment_after_fixes.len > 0 {
		mut out := order_fixes.clone()
		out << comment_after_fixes
		return out
	}
	if 'groups' in options {
		newlines_fixes := ctx.pf_make_newlines_between_fixes(nodes, sorted, options)
		if newlines_fixes.len > 0 {
			mut out := order_fixes.clone()
			out << newlines_fixes
			return out
		}
	}
	return order_fixes
}

// pf_merge_fixes ports mergeFixes and ESLint's merge of the fixes of a report: one fix from the
// start of the first to the end of the last, with the text in between; none (false) without
// fixes. Overlapping fixes make ESLint throw.
fn (ctx &PfContext) pf_merge_fixes(fixes []Fix) !(bool, Fix) {
	if fixes.len == 0 {
		return false, Fix{}
	}
	if fixes.len == 1 {
		return true, fixes[0]
	}
	mut sorted := fixes.clone()
	sorted.sort_with_compare(fn (a &Fix, b &Fix) int {
		if a.start != b.start {
			return a.start - b.start
		}
		return a.end - b.end
	})
	start := sorted[0].start
	end := sorted.last().end
	mut last := start
	mut text := ''
	for fix in sorted {
		if fix.start < last {
			return error('Fix objects must not be overlapped in a report.')
		}
		text += ctx.src[last..fix.start] + fix.text
		last = fix.end
	}
	return true, Fix{
		start: start
		end:   end
		text:  text
	}
}

// pf_make_order_fixes ports makeOrderFixes: each node replaced by the one sorted at its place.
fn (ctx &PfContext) pf_make_order_fixes(nodes []PfSortingNode, sorted []PfSortingNode, options map[string]json2.Any, ignore_first_node_highest_block_comment bool) []Fix {
	mut fixes := []Fix{}
	if nodes.len == 0 {
		return fixes
	}
	first := nodes[0].node
	for i, sorting_node in nodes {
		sorted_sorting_node := sorted[i]
		node := sorting_node.node
		sorted_node := sorted_sorting_node.node
		if node == sorted_node {
			continue
		}
		sorted_start, sorted_end := ctx.pf_get_node_range(sorted_node, options, ignore_first_node_highest_block_comment
			&& sorted_node == first, sorted_sorting_node)
		mut sorted_node_code := ctx.src[sorted_start..sorted_end]
		sorted_node_text := ctx.text(sorted_node)
		next_token := ctx.tokens.after(ctx.t.nodes[node].end, false)
		sorted_next_node_ends_with_safe_character := sorted_node_text.ends_with(';')
			|| sorted_node_text.ends_with(',')
		mut is_next_token_on_same_line := false
		mut is_next_token_safe_character := false
		if token := next_token {
			is_next_token_on_same_line = ctx.pf_line(token.start) == ctx.end_line(node)
			value := ctx.src[token.start..token.end]
			is_next_token_safe_character = value == ';' || value == ','
		}
		following_token := if i + 1 < sorted.len {
			ctx.tokens.after(ctx.t.nodes[sorted[i + 1].node].start, false)
		} else {
			next_token
		}
		mut is_followed_by_expression_continuation := false
		if pf_does_node_end_with_expression(ctx.t, sorted_node) {
			if token := following_token {
				value := ctx.src[token.start..token.end]
				is_followed_by_expression_continuation = value.len > 0
					&& value[0] in [`[`, `(`, `\``, `*`, `+`, `-`, `/`, `<`]
			}
		}
		if sorted_sorting_node.add_safety_semicolon_when_inline
			&& !sorted_next_node_ends_with_safe_character && !is_next_token_safe_character
			&& (is_next_token_on_same_line || is_followed_by_expression_continuation) {
			sorted_node_code += ';'
		}
		start, end := ctx.pf_get_node_range(node, options, ignore_first_node_highest_block_comment
			&& node == first, sorting_node)
		fixes << fix_replace_range(start, end, sorted_node_code)
	}
	return fixes
}

// pf_does_node_end_with_expression ports doesNodeEndWithExpression.
fn pf_does_node_end_with_expression(t &estree.EsTree, node int) bool {
	return match t.typ(node) {
		.variable_declaration {
			true
		}
		.property_definition, .accessor_property {
			if value := t.node(node, .value) { value >= 0 } else { false }
		}
		else {
			false
		}
	}
}

// pf_get_node_range ports getNodeRange: the node with its decorators, its parentheses and the
// comments right above it (up to a partition comment, an eslint-disable or eslint-enable comment,
// or a blank line).
fn (ctx &PfContext) pf_get_node_range(node int, options map[string]json2.Any, ignore_highest_block_comment bool, sorting_node PfSortingNode) (int, int) {
	t := ctx.t
	mut start := t.nodes[node].start
	mut end := t.nodes[node].end
	decorators := if sorting_node.has_implicit_decorators && sorting_node.node == node {
		sorting_node.implicit_decorators
	} else {
		t.list(node, .decorators) or { []int{} }
	}
	if decorators.len > 0 {
		decorator := decorators[0]
		if t.nodes[decorator].start < start {
			start = t.nodes[decorator].start
		}
		if top := ctx.pf_highest_comment_start(ctx.pf_get_comments_before(decorator, ''),
			ctx.start_line(decorator), ignore_highest_block_comment, options)
		{
			if top < start {
				start = top
			}
		}
	}
	tokens := ctx.tokens
	// ASTUtils.isParenthesized(node, sourceCode) of eslint-utils.
	if ctx.checker.un_is_parenthesized(t, tokens, node) {
		opening := pf_token_before_value(tokens, ctx.src, t.nodes[node].start, '(') or {
			SourceToken{
				start: start
			}
		}
		closing := pf_token_after_value(tokens, ctx.src, t.nodes[node].end, ')') or {
			SourceToken{
				end: end
			}
		}
		if opening.start < start {
			start = opening.start
		}
		end = closing.end
	}
	if top := ctx.pf_highest_comment_start(ctx.pf_get_comments_before(node, ''), ctx.start_line(node),
		ignore_highest_block_comment, options)
	{
		if top < start {
			start = top
		}
	}
	return start, end
}

// pf_token_before_value ports getTokenBefore(node, filter): the last token before `offset` with
// that text.
fn pf_token_before_value(tokens &SourceTokens, src string, offset int, value string) ?SourceToken {
	mut index := source_tokens_index(tokens.tokens, offset) - 1
	for index >= 0 {
		token := tokens.tokens[index]
		if src[token.start..token.end] == value {
			return token
		}
		index--
	}
	return none
}

// pf_token_after_value ports getTokenAfter(node, filter): the first token from `offset` with that
// text.
fn pf_token_after_value(tokens &SourceTokens, src string, offset int, value string) ?SourceToken {
	for index := source_tokens_index(tokens.tokens, offset); index < tokens.tokens.len; index++ {
		token := tokens.tokens[index]
		if src[token.start..token.end] == value {
			return token
		}
	}
	return none
}

// pf_highest_comment_start ports computeHighestCommentStart: the start of the highest comment of
// the block of comments right above the anchor line.
fn (ctx &PfContext) pf_highest_comment_start(comments []SourceToken, anchor_line int, ignore_highest_block_comment bool, options map[string]json2.Any) ?int {
	mut highest_block := -1
	for i, comment in comments {
		if comment.kind == .block_comment {
			highest_block = i
			break
		}
	}
	partition_by_comment := options['partitionByComment'] or { json2.Any(false) }
	mut highest := ?int(none)
	for i := comments.len - 1; i >= 0; i-- {
		comment := comments[i]
		if ignore_highest_block_comment && i == highest_block {
			break
		}
		is_partition := ctx.pf_is_partition_comment(partition_by_comment, comment) or { false }
		mut is_disable_or_enable := false
		if disabled := pf_get_eslint_disabled_rules(ctx.pf_comment_value(comment)) {
			is_disable_or_enable = disabled.directive in ['eslint-disable', 'eslint-enable']
		}
		if is_partition || is_disable_or_enable {
			break
		}
		previous_line := if i == comments.len - 1 {
			anchor_line
		} else {
			ctx.pf_line(comments[i + 1].start)
		}
		if ctx.pf_line(comment.end) != previous_line - 1 {
			break
		}
		highest = comment.start
	}
	return highest
}

// pf_make_comment_after_fixes ports makeCommentAfterFixes.
fn (ctx &PfContext) pf_make_comment_after_fixes(nodes []PfSortingNode, sorted []PfSortingNode) []Fix {
	mut fixes := []Fix{}
	for i, sorting_node in nodes {
		node := sorting_node.node
		sorted_node := sorted[i].node
		if node == sorted_node {
			continue
		}
		fixes << ctx.pf_make_single_node_comment_after_fixes(ctx.t.nodes[node].start, ctx.t.nodes[node].end,
			ctx.t.nodes[sorted_node].end)
	}
	return fixes
}

// pf_make_single_node_comment_after_fixes ports makeSingleNodeCommentAfterFixes for the node
// (what spans [node_start, node_end)) and the sorted node (what ends at sorted_end): the comment
// after the sorted node, on its line, moves after the node.
fn (ctx &PfContext) pf_make_single_node_comment_after_fixes(node_start int, node_end int, sorted_end int) []Fix {
	comment_after := ctx.pf_comment_after(sorted_end) or { return []Fix{} }
	if ctx.pf_line(node_start) == ctx.pf_line(sorted_end) {
		return []Fix{}
	}
	mut fixes := []Fix{}
	token_before := ctx.tokens.before(comment_after.start, false) or { return []Fix{} }
	range_start := token_before.end
	range_end := comment_after.end
	fixes << fix_replace_range(range_start, range_end, '')
	// computeNodeToInsertAfter: the `,` or `:` right after the node on its line, or the node.
	mut insert_end := node_end
	mut insert_line := ctx.pf_line(node_end)
	if after := ctx.tokens.after(node_end, false) {
		value := ctx.src[after.start..after.end]
		if after.kind == .punctuator && value in [',', ':']
			&& ctx.pf_line(after.end) == ctx.pf_line(node_end) {
			insert_end = after.end
			insert_line = ctx.pf_line(after.end)
		}
	}
	mut comment_text := ctx.src[range_start..range_end]
	if comment_after.kind == .line_comment {
		if after_insertion := ctx.tokens.after(insert_end, false) {
			if ctx.pf_line(after_insertion.start) == insert_line {
				comment_text += '\n'
			}
		}
	}
	fixes << fix_replace_range(insert_end, insert_end, comment_text)
	return fixes
}

// pf_comment_after ports getCommentAfter: the first token or comment after `offset` that is not a
// `,`, `;` or `:` punctuator, when it is a comment that ends on the line of `offset`.
fn (ctx &PfContext) pf_comment_after(offset int) ?SourceToken {
	for index := source_tokens_index(ctx.tokens.all, offset); index < ctx.tokens.all.len; index++ {
		token := ctx.tokens.all[index]
		if token.kind == .punctuator && ctx.src[token.start..token.end] in [',', ';', ':'] {
			continue
		}
		if token.kind in [.block_comment, .line_comment]
			&& ctx.pf_line(offset) == ctx.pf_line(token.end) {
			return token
		}
		return none
	}
	return none
}

// pf_make_newlines_between_fixes ports makeNewlinesBetweenFixes.
fn (ctx &PfContext) pf_make_newlines_between_fixes(nodes []PfSortingNode, sorted []PfSortingNode, options map[string]json2.Any) []Fix {
	mut fixes := []Fix{}
	groups := pf_opt_list(options, 'groups')
	for i := 0; i < sorted.len - 1; i++ {
		sorting_node := nodes[i]
		next_sorting_node := nodes[i + 1]
		sorted_sorting_node := sorted[i]
		next_sorted_sorting_node := sorted[i + 1]
		if sorted_sorting_node.partition_id != next_sorted_sorting_node.partition_id {
			continue
		}
		node_group_index := pf_get_group_index(groups, sorted_sorting_node.group)
		next_node_group_index := pf_get_group_index(groups, next_sorted_sorting_node.group)
		if node_group_index > next_node_group_index {
			continue
		}
		newlines_between := pf_get_newlines_between_option(options, node_group_index, next_node_group_index)
		if newlines_between == pf_ignore {
			continue
		}
		_, current_end := ctx.pf_get_node_range(sorting_node.node, map[string]json2.Any{},
			false, PfSortingNode{ node: -1 })
		next_start, _ := ctx.pf_get_node_range(next_sorting_node.node, map[string]json2.Any{},
			false, PfSortingNode{ node: -1 })
		lines_between := ctx.pf_lines_between(sorting_node.node, next_sorting_node.node)
		if f64(lines_between) == newlines_between {
			continue
		}
		text_between := ctx.src[current_end..next_start]
		is_on_same_line := ctx.end_line(sorting_node.node) == ctx.start_line(next_sorting_node.node)
		fixes << fix_replace_range(current_end, next_start, pf_range_replacement(text_between,
			newlines_between, is_on_same_line))
	}
	return fixes
}

// pf_range_replacement ports computeRangeReplacement.
fn pf_range_replacement(text_between string, newlines_between f64, is_on_same_line bool) string {
	without_invalid := pf_without_invalid_newlines(text_between)
	if newlines_between == 0 {
		return without_invalid
	}
	mut replacement := without_invalid
	for index := 0; f64(index) < newlines_between; index++ {
		replacement = pf_add_newline_before_first_newline(replacement)
	}
	if !is_on_same_line {
		return replacement
	}
	return pf_add_newline_before_first_newline(replacement)
}

fn pf_add_newline_before_first_newline(value string) string {
	index := value.index('\n') or { return value + '\n' }
	return value[..index] + '\n' + value[index..]
}

const pf_re_blank_lines = jsregexp.js_regex_new('\\n\\s*\\n', 'u') or { panic(err) }
const pf_re_newlines = jsregexp.js_regex_new('\\n+', 'u') or { panic(err) }

// pf_without_invalid_newlines ports getStringWithoutInvalidNewlines:
// `value.replaceAll(/\n\s*\n/gu, '\n').replaceAll(/\n+/gu, '\n')`.
fn pf_without_invalid_newlines(value string) string {
	newline := fn (_ []u16) []u16 {
		return [u16(`\n`)]
	}
	first := pf_regex_replace(pf_re_blank_lines, utf16_units(value), true, true, newline)
	second := pf_regex_replace(pf_re_newlines, first, true, true, newline)
	return stv_units_string(second)
}

// --- Listeners ---------------------------------------------------------------------------------

// pf_matched_ast_selectors ports what buildAstListeners collects: for each node of those types,
// the `useConfigurationIf.matchesAstSelector` of the options that match it.
fn (ctx &PfContext) pf_matched_ast_selectors(node_types []estree.NodeType) !map[int][]string {
	mut selectors := []string{}
	for option in ctx.options {
		if option is map[string]json2.Any {
			if condition := pf_opt_object(option, 'useConfigurationIf') {
				selector := condition['matchesAstSelector'] or { continue }
				if selector is string && selector.str() !in selectors {
					selectors << selector.str()
				}
			}
		}
	}
	mut out := map[int][]string{}
	if selectors.len == 0 {
		return out
	}
	for m in esquery.run(ctx.t, selectors)! {
		if ctx.t.typ(m.node) !in node_types {
			continue
		}
		selector := selectors[m.selector]
		if selector !in out[m.node] {
			out[m.node] << selector
		}
	}
	return out
}

// pf_is_context_option_matching ports isContextOptionMatching: the option has no
// useConfigurationIf, or all the names match its allNamesMatchPattern and the node matched its
// matchesAstSelector.
fn pf_is_context_option_matching(option map[string]json2.Any, node_names []string, matched_ast_selectors []string) !bool {
	condition := option['useConfigurationIf'] or { return true }
	if !pf_truthy(condition) || condition !is map[string]json2.Any {
		return true
	}
	object := condition.as_map()
	if pattern := object['allNamesMatchPattern'] {
		if pf_truthy(pattern) {
			for name in node_names {
				if !pf_matches(name, pattern)! {
					return false
				}
			}
		}
	}
	if selector := object['matchesAstSelector'] {
		if pf_truthy(selector) && selector.str() !in matched_ast_selectors {
			return false
		}
	}
	return true
}

// pf_matched_context_options ports the computeMatchedContextOptions of the rules: the first
// option that matches the names.
fn (ctx &PfContext) pf_matched_context_options(node_names []string, matched_ast_selectors []string) !(bool, map[string]json2.Any) {
	for option in ctx.options {
		object := if option is map[string]json2.Any {
			option.as_map()
		} else {
			map[string]json2.Any{}
		}
		if pf_is_context_option_matching(object, node_names, matched_ast_selectors)! {
			return true, object
		}
	}
	return false, map[string]json2.Any{}
}

// pf_range_to_diff ports rangeToDiff: the length of the node (UTF-16 units), without a last `;`
// or `,`.
fn (ctx &PfContext) pf_range_to_diff(node int) int {
	text := ctx.text(node)
	ends_with_comma_or_semicolon := text.ends_with(';') || text.ends_with(',')
	length := ctx.t.utf16_offset(ctx.t.nodes[node].end) - ctx.t.utf16_offset(ctx.t.nodes[node].start)
	return length - if ends_with_comma_or_semicolon { 1 } else { 0 }
}
