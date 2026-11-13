module rules

import json2
import jsregexp
import time
import treesitter { children, has_child_kind, named_children, node_field, node_kind, node_parent, nodes_of_kinds, position_of }

// Port of the `naming-convention` rule of typescript-eslint 8.62.0 (naming-convention.js and
// naming-convention-utils), with its options. The options given replace the default ones.

const nc_messages = {
	'doesNotMatchFormat':        '{{type}} name `{{name}}` must match one of the following formats: {{formats}}'
	'doesNotMatchFormatTrimmed': '{{type}} name `{{name}}` trimmed as `{{processedName}}` must match one of the following formats: {{formats}}'
	'missingAffix':              '{{type}} name `{{name}}` must have one of the following {{position}}es: {{affixes}}'
	'missingUnderscore':         '{{type}} name `{{name}}` must have {{count}} {{position}} underscore(s).'
	'satisfyCustom':             '{{type}} name `{{name}}` must {{regexMatch}} the RegExp: {{regex}}'
	'unexpectedUnderscore':      '{{type}} name `{{name}}` must not have a {{position}} underscore.'
}

// PredefinedFormats and UnderscoreOptions, by their value minus one.
const nc_formats = ['camelCase', 'strictCamelCase', 'PascalCase', 'StrictPascalCase', 'snake_case',
	'UPPER_CASE']
const nc_underscores = ['forbid', 'allow', 'require', 'requireDouble', 'allowDouble',
	'allowSingleOrDouble']

const nc_selectors = {
	'variable':              1
	'function':              2
	'parameter':             4
	'parameterProperty':     8
	'classicAccessor':       16
	'enumMember':            32
	'classMethod':           64
	'objectLiteralMethod':   128
	'typeMethod':            256
	'classProperty':         512
	'objectLiteralProperty': 1024
	'typeProperty':          2048
	'autoAccessor':          4096
	'class':                 8192
	'interface':             16384
	'typeAlias':             32768
	'enum':                  65536
	'typeParameter':         131072
	'import':                262144
}

const nc_meta_selectors = {
	'default':      -1
	'variableLike': 7
	'memberLike':   8184
	'typeLike':     253952
	'method':       448
	'property':     3584
	'accessor':     4112
}

const nc_modifiers = {
	'const':          1
	'readonly':       2
	'static':         4
	'public':         8
	'protected':      16
	'private':        32
	'#private':       64
	'abstract':       128
	'destructured':   256
	'global':         512
	'exported':       1024
	'unused':         2048
	'requiresQuotes': 4096
	'override':       8192
	'async':          16384
	'default':        32768
	'namespace':      65536
}

const nc_type_modifiers = {
	'boolean':  131072
	'string':   262144
	'number':   524288
	'function': 1048576
	'array':    2097152
}

// Selectors whose configurations may have `types`.
const nc_selectors_with_types = 1 | 4 | 512 | 1024 | 2048 | 8 | 16

struct NcRegex {
	has      bool
	is_match bool
	program  jsregexp.RegexpProgram
	text     string // RegExp.prototype.toString()
}

// NcConfig is a normalized option for one selector (normalizeOption).
struct NcConfig {
	selector        int
	modifier_weight int
	filter          NcRegex
	custom          NcRegex
	formats         []int
	leading         int
	trailing        int
	modifier_mask   int
	prefix          []string
	suffix          []string
	has_types       bool
	types           []string
	order           int
}

struct NcOptions {
	configs []NcConfig
}

// NcItem is a name to validate: its selector, its node and its modifiers.
struct NcItem {
	selector  string
	node      C.TSNode
	modifiers int
}

fn nc_strings(value json2.Any, what string) ![]string {
	if value !is []json2.Any {
		return error('`${what}` of `${naming_convention}` must be a list of texts')
	}
	mut out := []string{}
	for item in value.as_array() {
		if item !is string {
			return error('`${what}` of `${naming_convention}` must be a list of texts')
		}
		out << item as string
	}
	return out
}

// nc_regexp_text is RegExp.prototype.toString() of `new RegExp(pattern, 'u')`: the source, with
// its `/` and its line breaks escaped, between slashes.
fn nc_regexp_text(pattern string) string {
	if pattern == '' {
		return '/(?:)/u'
	}
	mut out := []rune{}
	mut escaped := false
	mut in_class := false
	for ch in pattern.runes() {
		if escaped {
			escaped = false
			out << ch
			continue
		}
		match ch {
			`\\` {
				escaped = true
				out << ch
			}
			`[` {
				in_class = true
				out << ch
			}
			`]` {
				in_class = false
				out << ch
			}
			`/` {
				if !in_class {
					out << `\\`
				}
				out << ch
			}
			`\n` {
				out << '\\n'.runes()
			}
			`\r` {
				out << '\\r'.runes()
			}
			else {
				out << ch
			}
		}
	}
	return '/${out.string()}/u'
}

fn nc_regex(pattern string, is_match bool) !NcRegex {
	program := jsregexp.regexp_compile(pattern) or {
		return error('`${naming_convention}`: veslint cannot use the regular expression `${pattern}`: ${err.msg()}')
	}
	return NcRegex{
		has:      true
		is_match: is_match
		program:  program
		text:     nc_regexp_text(pattern)
	}
}

// nc_options ports normalizeOption for each option.
fn nc_options(options []json2.Any) !NcOptions {
	mut configs := []NcConfig{}
	for option in options {
		if option !is map[string]json2.Any {
			return error('each option of `${naming_convention}` must be an object')
		}
		values := option.as_map()
		for key, _ in values {
			// `failureMessage` is in the schema of the rule, which does nothing with it.
			if key !in ['selector', 'format', 'custom', 'filter', 'leadingUnderscore',
				'trailingUnderscore', 'prefix', 'suffix', 'modifiers', 'types', 'failureMessage'] {
				return error('`${naming_convention}` has no option `${key}`')
			}
		}
		mut weight := 0
		mut modifier_mask := 0
		if value := values['modifiers'] {
			for name in nc_strings(value, 'modifiers')! {
				bit := nc_modifiers[name] or {
					return error('`${naming_convention}` has no modifier `${name}`')
				}
				weight |= bit
				modifier_mask |= bit
			}
		}
		mut types := []string{}
		mut has_types := false
		if value := values['types'] {
			has_types = true
			for name in nc_strings(value, 'types')! {
				bit := nc_type_modifiers[name] or {
					return error('`${naming_convention}` has no type `${name}`')
				}
				weight |= bit
				types << name
			}
		}
		mut filter := NcRegex{}
		if value := values['filter'] {
			if value is string {
				filter = nc_regex(value, true)!
			} else if value is map[string]json2.Any {
				object := value.as_map()
				regex := object['regex'] or { json2.Any('') }
				is_match := object['match'] or { json2.Any(false) }
				if regex !is string || is_match !is bool {
					return error('`filter` of `${naming_convention}` must have a `regex` text and a `match` that is true or false')
				}
				filter = nc_regex(regex as string, is_match as bool)!
			} else {
				return error('`filter` of `${naming_convention}` must be a text or an object')
			}
			weight |= 1 << 30
		}
		mut custom := NcRegex{}
		if value := values['custom'] {
			if value !is map[string]json2.Any {
				return error('`custom` of `${naming_convention}` must be an object')
			}
			object := value.as_map()
			regex := object['regex'] or { json2.Any('') }
			is_match := object['match'] or { json2.Any(false) }
			if regex !is string || is_match !is bool {
				return error('`custom` of `${naming_convention}` must have a `regex` text and a `match` that is true or false')
			}
			custom = nc_regex(regex as string, is_match as bool)!
		}
		mut formats := []int{}
		if value := values['format'] {
			if value !is json2.Null {
				for name in nc_strings(value, 'format')! {
					index := nc_formats.index(name)
					if index < 0 {
						return error('`${naming_convention}` has no format `${name}`')
					}
					formats << index + 1
				}
			}
		}
		mut underscores := [0, 0]
		for i, key in ['leadingUnderscore', 'trailingUnderscore'] {
			if value := values[key] {
				if value is string {
					index := nc_underscores.index(value)
					if index < 0 {
						return error('`${key}` of `${naming_convention}` cannot be `${value}`')
					}
					underscores[i] = index + 1
				} else {
					return error('`${key}` of `${naming_convention}` must be a text')
				}
			}
		}
		prefix := if value := values['prefix'] { nc_strings(value, 'prefix')! } else { []string{} }
		suffix := if value := values['suffix'] { nc_strings(value, 'suffix')! } else { []string{} }
		selector_value := values['selector'] or {
			return error('each option of `${naming_convention}` needs a `selector`')
		}
		selector_names := if selector_value is string {
			[selector_value]
		} else {
			nc_strings(selector_value, 'selector')!
		}
		for name in selector_names {
			selector := nc_meta_selectors[name] or {
				nc_selectors[name] or {
					return error('`${naming_convention}` has no selector `${name}`')
				}
			}
			configs << NcConfig{
				selector:        selector
				modifier_weight: weight
				filter:          filter
				custom:          custom
				formats:         formats
				leading:         underscores[0]
				trailing:        underscores[1]
				modifier_mask:   modifier_mask
				prefix:          prefix
				suffix:          suffix
				has_types:       has_types
				types:           types
				order:           configs.len
			}
		}
	}
	return NcOptions{
		configs: configs
	}
}

// nc_validator_configs ports the configurations of createValidator for a selector: the ones for
// it, most specific first.
fn nc_validator_configs(selector string, all []NcConfig) []NcConfig {
	selector_type := nc_selectors[selector] or { 0 }
	mut configs := all.filter((it.selector & selector_type) != 0 || it.selector == -1)
	configs.sort_with_compare(fn (a &NcConfig, b &NcConfig) int {
		order := nc_compare_configs(a, b)
		// JavaScript's sort is stable.
		return if order != 0 { order } else { a.order - b.order }
	})
	return configs
}

fn nc_is_meta_selector(selector int) bool {
	return selector in [-1, 7, 8184, 253952, 448, 3584, 4112]
}

fn nc_compare_configs(a &NcConfig, b &NcConfig) int {
	if a.selector == b.selector {
		// The most specific configuration (the one with most modifiers) first.
		return b.modifier_weight - a.modifier_weight
	}
	a_meta := nc_is_meta_selector(a.selector)
	b_meta := nc_is_meta_selector(b.selector)
	if a_meta && !b_meta {
		return 1
	}
	if !a_meta && b_meta {
		return -1
	}
	a_method_or_property := a.selector in [448, 3584]
	b_method_or_property := b.selector in [448, 3584]
	if a_method_or_property && !b_method_or_property {
		return -1
	}
	if !a_method_or_property && b_method_or_property {
		return 1
	}
	return b.selector - a.selector
}

fn (mut c Checker) lint_naming_convention(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	options := nc_options(c.rule_options(naming_convention))!
	mut sw := time.new_stopwatch()
	// The `unused` modifier needs the variables nothing uses.
	c.nc_unused = if options.configs.any(it.modifier_mask & 2048 != 0) {
		c.unused_variables(root, c.scope_tree(root))
	} else {
		map[int]bool{}
	}
	items := c.nc_items(root)
	mut validators := map[string][]NcConfig{}
	mut needs_types := false
	for selector, bit in nc_selectors {
		validators[selector] = nc_validator_configs(selector, options.configs)
		if bit & nc_selectors_with_types != 0 && validators[selector].any(it.has_types) {
			needs_types = true
		}
	}
	if needs_types {
		mut spans := []Span{}
		for item in items {
			bit := nc_selectors[item.selector] or { 0 }
			if bit & nc_selectors_with_types != 0 && validators[item.selector].any(it.has_types) {
				spans << node_span(item.node)
			}
		}
		c.resolve_spans(spans, abs_path, mut stats)!
	}
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for item in items {
		findings << c.nc_validate(item, validators[item.selector])!
	}
	findings.sort_with_compare(compare_findings)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += items.len
	return findings
}

// nc_name is the name the validator checks: that of an identifier or of a `#name`, or the value
// of a literal as text.
fn (c &Checker) nc_name(node C.TSNode) string {
	match node_kind(node) {
		'private_property_identifier' {
			return c.text(node).trim_left('#')
		}
		'string' {
			return c.literal_string_value(node) or { c.text(node) }
		}
		'number' {
			return js_number_string(c.text(node)) or { c.text(node) }
		}
		'this' {
			return 'this'
		}
		else {
			return c.identifier_name(node)
		}
	}
}

// nc_validate ports the validator: the first configuration that applies to the name decides.
// It gives the finding, if there is one.
fn (mut c Checker) nc_validate(item NcItem, configs []NcConfig) ![]Finding {
	original := c.nc_name(item.node)
	for config in configs {
		if config.filter.has {
			if jsregexp.regexp_test(config.filter.program, original)! != config.filter.is_match {
				continue
			}
		}
		if config.modifier_mask & ~item.modifiers != 0 {
			continue
		}
		if !c.nc_is_correct_type(item, config)! {
			continue
		}
		mut data := {
			'type': nc_selector_message(item.selector)
			'name': original
		}
		mut name := original
		// validateUnderscore
		for position in ['leading', 'trailing'] {
			option := if position == 'leading' { config.leading } else { config.trailing }
			if option == 0 {
				continue
			}
			single := if position == 'leading' {
				name.starts_with('_')
			} else {
				name.ends_with('_')
			}
			double := if position == 'leading' {
				name.starts_with('__')
			} else {
				name.ends_with('__')
			}
			trim := fn [position] (text string, count int) string {
				if count > text.len {
					return ''
				}
				return if position == 'leading' { text[count..] } else { text[..text.len - count] }
			}
			data['position'] = position
			match nc_underscores[option - 1] {
				'allow' {
					if single {
						name = trim(name, 1)
					}
				}
				'allowDouble' {
					if double {
						name = trim(name, 2)
					}
				}
				'allowSingleOrDouble' {
					if double {
						name = trim(name, 2)
					} else if single {
						name = trim(name, 1)
					}
				}
				'forbid' {
					if single {
						data['count'] = 'one'
						return [nc_finding(item, 'unexpectedUnderscore', data)]
					}
				}
				'require' {
					if !single {
						data['count'] = 'one'
						return [nc_finding(item, 'missingUnderscore', data)]
					}
					name = trim(name, 1)
				}
				'requireDouble' {
					if !double {
						data['count'] = 'two'
						return [nc_finding(item, 'missingUnderscore', data)]
					}
					name = trim(name, 2)
				}
				else {}
			}
		}
		// validateAffix
		for position in ['prefix', 'suffix'] {
			affixes := if position == 'prefix' { config.prefix } else { config.suffix }
			if affixes.len == 0 {
				continue
			}
			mut found := false
			for affix in affixes {
				if position == 'prefix' && name.starts_with(affix) {
					name = name[affix.len..]
					found = true
					break
				}
				if position == 'suffix' && name.ends_with(affix) {
					// `name.slice(0, -affix.length)`: with an empty affix, the empty text.
					name = if affix.len == 0 { '' } else { name[..name.len - affix.len] }
					found = true
					break
				}
			}
			if !found {
				data['position'] = position
				data['affixes'] = affixes.join(', ')
				return [nc_finding(item, 'missingAffix', data)]
			}
		}
		// validateCustom
		if config.custom.has {
			if jsregexp.regexp_test(config.custom.program, name)! != config.custom.is_match {
				data['regex'] = config.custom.text
				data['regexMatch'] = if config.custom.is_match { 'match' } else { 'not match' }
				return [nc_finding(item, 'satisfyCustom', data)]
			}
		}
		// validatePredefinedFormat: a name that needs quotes fits no format.
		if config.formats.len > 0 {
			mut fits := false
			if item.modifiers & nc_modifiers['requiresQuotes'] == 0 {
				for format in config.formats {
					if nc_fits_format(name, format) {
						fits = true
						break
					}
				}
			}
			if !fits {
				data['formats'] = config.formats.map(nc_formats[it - 1]).join(', ')
				data['processedName'] = name
				return [
					nc_finding(item, if original == name {
						'doesNotMatchFormat'
					} else {
						'doesNotMatchFormatTrimmed'
					}, data),
				]
			}
		}
		return []Finding{}
	}
	return []Finding{}
}

fn nc_finding(item NcItem, message_id string, data map[string]string) Finding {
	return Finding{
		stmt:       position_of(item.node)
		message_id: message_id
		data:       data
	}
}

// nc_selector_message ports selectorTypeToMessageString: 'classProperty' is 'Class Property'.
fn nc_selector_message(selector string) string {
	mut out := []u8{}
	for i, ch in selector.bytes() {
		if ch >= `A` && ch <= `Z` {
			out << ` `
		}
		out << if i == 0 && ch >= `a` && ch <= `z` { ch - 32 } else { ch }
	}
	return out.bytestr()
}

// nc_is_correct_type ports isCorrectType: with `types`, the type of the name must be one of them.
fn (mut c Checker) nc_is_correct_type(item NcItem, config NcConfig) !bool {
	if !config.has_types {
		return true
	}
	bit := nc_selectors[item.selector] or { 0 }
	if bit & nc_selectors_with_types == 0 {
		return true
	}
	node_type := c.node_type(item.node) or { return false }
	t := c.client.non_nullable_type(c.snapshot, c.project, node_type.id)!
	parts := if t.flags & type_flag_union != 0 { c.members_of(t)! } else { [t] }
	for allowed in config.types {
		match allowed {
			'array' {
				mut all := true
				for part in parts {
					if !c.is_array(part)! && !c.is_tuple(part)! {
						all = false
						break
					}
				}
				if all {
					return true
				}
			}
			'function' {
				mut all := true
				for part in parts {
					if c.signatures_of(part, signature_kind_call)!.len == 0 {
						all = false
						break
					}
				}
				if all {
					return true
				}
			}
			else {
				base := c.client.base_type_of_literal(c.snapshot, c.project, t.id)!
				widened := c.client.widened_type(c.snapshot, c.project, base.id)!
				if c.type_string(widened)! == allowed {
					return true
				}
			}
		}
	}
	return false
}

// The format checks of naming-convention-utils/format.js. They look at the UTF-16 units of the
// name (`name[0]`, `name[i]`): half of a surrogate pair is neither upper nor lower case.

fn nc_fits_format(name string, format int) bool {
	if name.len == 0 {
		return true
	}
	units := utf16_units(name)
	first := units[..1]
	return match nc_formats[format - 1] {
		'camelCase' { jsregexp.js_to_lower(first) == first && !name.contains('_') }
		'strictCamelCase' {
			jsregexp.js_to_lower(first) == first && nc_has_strict_camel_humps(units, false)
		}
		'PascalCase' { jsregexp.js_to_upper(first) == first && !name.contains('_') }
		'StrictPascalCase' {
			jsregexp.js_to_upper(first) == first && nc_has_strict_camel_humps(units, true)
		}
		'snake_case' { jsregexp.js_to_lower(units) == units && nc_valid_underscores(name) }
		else { jsregexp.js_to_upper(units) == units && nc_valid_underscores(name) }
	}
}

fn nc_has_strict_camel_humps(units []u16, starts_upper bool) bool {
	if units.len > 0 && units[0] == `_` {
		return false
	}
	mut is_upper := starts_upper
	for i in 1 .. units.len {
		if units[i] == `_` {
			return false
		}
		letter := units[i..i + 1]
		is_uppercase_char := jsregexp.js_to_upper(letter) == letter && jsregexp.js_to_lower(letter) != letter
		if is_upper == is_uppercase_char {
			if is_upper {
				return false
			}
		} else {
			is_upper = !is_upper
		}
	}
	return true
}

fn nc_valid_underscores(name string) bool {
	if name.starts_with('_') {
		return false
	}
	mut was_underscore := false
	for i in 1 .. name.len {
		if name[i] == `_` {
			if was_underscore {
				return false
			}
			was_underscore = true
		} else {
			was_underscore = false
		}
	}
	return !was_underscore
}

// The selectors: which names of the file are validated, as what and with which modifiers.

// nc_estree_parent is the parent of a declaration in ESTree: `declare` is not a node there.
fn nc_estree_parent(node C.TSNode) ?C.TSNode {
	mut parent := node_parent(node)?
	for node_kind(parent) == 'ambient_declaration' {
		parent = node_parent(parent)?
	}
	return parent
}

// nc_is_exported ports isExported: the declaration is in an `export`, or the variable with that
// name of the scope has a reference in an `export default` or in an export specifier.
fn (c &Checker) nc_is_exported(declaration C.TSNode, name string, tree &ScopeTree, scope int) bool {
	if parent := nc_estree_parent(declaration) {
		if node_kind(parent) == 'export_statement' {
			return true
		}
	}
	if scope < 0 {
		return false
	}
	variable := tree.own_variable(scope, name)
	if variable < 0 {
		return false
	}
	for index in tree.variables[variable].references {
		parent := node_parent(tree.references[index].identifier) or { continue }
		if node_kind(parent) in ['export_statement', 'export_specifier'] {
			return true
		}
	}
	return false
}

fn nc_is_global(tree &ScopeTree, scope int) bool {
	return scope >= 0 && tree.scopes[scope].kind in [.global, .esmodule]
}

// nc_pattern_identifiers ports getIdentifiersFromPattern: the names a pattern declares.
fn nc_pattern_identifiers(pattern C.TSNode, mut out []C.TSNode) {
	match node_kind(pattern) {
		'identifier', 'shorthand_property_identifier_pattern', 'this' {
			out << pattern
		}
		'required_parameter', 'optional_parameter' {
			if inner := node_field(pattern, 'pattern') {
				nc_pattern_identifiers(inner, mut out)
			}
		}
		'object_pattern', 'array_pattern' {
			for child in named_children(pattern) {
				nc_pattern_identifiers(child, mut out)
			}
		}
		'pair_pattern' {
			if value := node_field(pattern, 'value') {
				nc_pattern_identifiers(value, mut out)
			}
		}
		'assignment_pattern', 'object_assignment_pattern' {
			if left := node_field(pattern, 'left') {
				nc_pattern_identifiers(left, mut out)
			}
		}
		'rest_pattern' {
			for child in named_children(pattern) {
				nc_pattern_identifiers(child, mut out)
				break
			}
		}
		else {}
	}
}

// nc_is_function_value: the value of a property is an arrow function or a function expression.
fn nc_is_function_value(value ?C.TSNode) bool {
	node := value or { return false }
	return node_kind(unwrap_parens(node)) in ['arrow_function', 'function_expression',
		'generator_function']
}

fn nc_is_async_value(value ?C.TSNode) bool {
	node := value or { return false }
	return has_child_kind(unwrap_parens(node), 'async')
}

// nc_member_modifiers ports getMemberModifiers.
fn (c &Checker) nc_member_modifiers(member C.TSNode, key ?C.TSNode) int {
	mut modifiers := 0
	mut accessibility := 'public'
	for child in children(member) {
		match node_kind(child) {
			'accessibility_modifier' { accessibility = c.text(child) }
			'static' { modifiers |= nc_modifiers['static'] }
			'readonly' { modifiers |= nc_modifiers['readonly'] }
			'override_modifier' { modifiers |= nc_modifiers['override'] }
			'abstract' { modifiers |= nc_modifiers['abstract'] }
			else {}
		}
	}
	if node_kind(member) == 'abstract_method_signature' {
		modifiers |= nc_modifiers['abstract']
	}
	mut is_hash_private := false
	if k := key {
		is_hash_private = node_kind(k) == 'private_property_identifier'
	}
	modifiers |= if is_hash_private {
		nc_modifiers['#private']
	} else {
		nc_modifiers[accessibility]
	}
	return modifiers
}

// nc_member ports handleMember: the key of a member, with `requiresQuotes` if it needs them.
fn (c &Checker) nc_member(selector string, key C.TSNode, modifiers int) NcItem {
	mut mask := modifiers
	if requires_quoting(c.nc_name(key)) {
		mask |= nc_modifiers['requiresQuotes']
	}
	return NcItem{
		selector:  selector
		node:      key
		modifiers: mask
	}
}

// nc_items collects the names every selector of the rule validates.
fn (mut c Checker) nc_items(root C.TSNode) []NcItem {
	tree := c.scope_tree(root)
	mut items := []NcItem{}
	for node in c.nodes_of_kinds(root, ['function_declaration', 'generator_function_declaration',
		'function_signature', 'function_expression', 'generator_function', 'arrow_function',
		'method_definition', 'method_signature', 'abstract_method_signature', 'import_statement',
		'variable_declarator', 'for_in_statement', 'class_declaration', 'abstract_class_declaration',
		'class', 'object', 'object_type', 'interface_body', 'enum_declaration', 'interface_declaration',
		'type_alias_declaration', 'type_parameter', 'public_field_definition', 'property_signature'],
		[]string{}) {
		kind := node_kind(node)
		parent_kind := if parent := node_parent(node) { node_kind(parent) } else { '' }
		match kind {
			'function_declaration', 'generator_function_declaration', 'function_signature',
			'function_expression', 'generator_function' {
				c.nc_function_name(node, tree, mut items)
				c.nc_parameters(node, tree, mut items)
			}
			'arrow_function' {
				c.nc_parameters(node, tree, mut items)
			}
			'method_definition', 'method_signature', 'abstract_method_signature' {
				in_class := parent_kind == 'class_body'
				in_object := parent_kind == 'object'
				// The parameters of the function of a class or object method (also without a
				// body), not those of a method of a type.
				if in_class || in_object {
					c.nc_parameters(node, tree, mut items)
				}
				key := node_field(node, 'name') or { continue }
				if node_kind(key) == 'computed_property_name' {
					continue
				}
				is_accessor := has_child_kind(node, 'get') || has_child_kind(node, 'set')
				if in_class {
					if c.pfa_is_constructor(node) {
						continue
					}
					mut modifiers := c.nc_member_modifiers(node, key)
					if is_accessor {
						items << c.nc_member('classicAccessor', key, modifiers)
					} else {
						if has_child_kind(node, 'async') {
							modifiers |= nc_modifiers['async']
						}
						items << c.nc_member('classMethod', key, modifiers)
					}
				} else if in_object {
					mut modifiers := nc_modifiers['public']
					if is_accessor {
						items << c.nc_member('classicAccessor', key, modifiers)
					} else {
						if has_child_kind(node, 'async') {
							modifiers |= nc_modifiers['async']
						}
						items << c.nc_member('objectLiteralMethod', key, modifiers)
					}
				} else {
					items << c.nc_member('typeMethod', key, nc_modifiers['public'])
				}
			}
			'public_field_definition' {
				key := node_field(node, 'name') or { continue }
				modifiers := c.nc_member_modifiers(node, key)
				if has_child_kind(node, 'accessor') {
					// An AccessorProperty, also with a computed key.
					mut name_node := key
					if node_kind(key) == 'computed_property_name' {
						name_node = unwrap_parens(first_named(key) or { continue })
					}
					items << c.nc_member('autoAccessor', name_node, modifiers)
					continue
				}
				if node_kind(key) == 'computed_property_name' {
					continue
				}
				value := node_field(node, 'value')
				if nc_is_function_value(value) {
					async := if nc_is_async_value(value) { nc_modifiers['async'] } else { 0 }
					items << c.nc_member('classMethod', key, modifiers | async)
				} else {
					items << c.nc_member('classProperty', key, modifiers)
				}
			}
			'property_signature' {
				key := node_field(node, 'name') or { continue }
				if node_kind(key) == 'computed_property_name' {
					continue
				}
				mut is_function_type := false
				if annotation := node_field(node, 'type') {
					if inner := first_named(annotation) {
						is_function_type = node_kind(unwrap_type_parens(inner)) == 'function_type'
					}
				}
				if is_function_type {
					items << c.nc_member('typeMethod', key, nc_modifiers['public'])
				} else {
					readonly := if has_child_kind(node, 'readonly') {
						nc_modifiers['readonly']
					} else {
						0
					}
					items << c.nc_member('typeProperty', key, nc_modifiers['public'] | readonly)
				}
			}
			'object' {
				for property in named_children(node) {
					match node_kind(property) {
						'pair' {
							key := node_field(property, 'key') or { continue }
							if node_kind(key) == 'computed_property_name' {
								continue
							}
							value := node_field(property, 'value')
							if nc_is_function_value(value) {
								async := if nc_is_async_value(value) {
									nc_modifiers['async']
								} else {
									0
								}
								items << c.nc_member('objectLiteralMethod', key, nc_modifiers['public'] | async)
							} else {
								items << c.nc_member('objectLiteralProperty', key, nc_modifiers['public'])
							}
						}
						'shorthand_property_identifier' {
							items << c.nc_member('objectLiteralProperty', property, nc_modifiers['public'])
						}
						else {}
					}
				}
			}
			'import_statement' {
				c.nc_imports(node, mut items)
			}
			'variable_declarator' {
				declaration := node_parent(node) or { continue }
				id := node_field(node, 'name') or { continue }
				is_const := has_child_kind(declaration, 'const')
				c.nc_variables(node, id, declaration, is_const, node_field(node, 'value'), tree, mut
					items)
			}
			'for_in_statement' {
				// `for (const x of y)`: a declaration without a declarator node.
				kind_node := node_field(node, 'kind') or { continue }
				left := node_field(node, 'left') or { continue }
				c.nc_variables(left, left, node, c.text(kind_node) == 'const', none, tree, mut
					items)
			}
			'class_declaration', 'abstract_class_declaration', 'class' {
				id := node_field(node, 'name') or { continue }
				upper := tree.scopes[tree.get_scope(node)].upper
				name := c.identifier_name(id)
				mut modifiers := 0
				if kind == 'abstract_class_declaration' {
					modifiers |= nc_modifiers['abstract']
				}
				if c.nc_is_exported(node, name, tree, upper) {
					modifiers |= nc_modifiers['exported']
				}
				if c.nc_is_unused(name, tree, upper) {
					modifiers |= nc_modifiers['unused']
				}
				items << NcItem{'class', id, modifiers}
			}
			'enum_declaration' {
				id := node_field(node, 'name') or { continue }
				upper := tree.scopes[tree.get_scope(node)].upper
				name := c.identifier_name(id)
				mut modifiers := 0
				if c.nc_is_exported(node, name, tree, upper) {
					modifiers |= nc_modifiers['exported']
				}
				if c.nc_is_unused(name, tree, upper) {
					modifiers |= nc_modifiers['unused']
				}
				items << NcItem{'enum', id, modifiers}
				if body := node_field(node, 'body') {
					for member in named_children(body) {
						mut member_id := member
						if node_kind(member) == 'enum_assignment' {
							member_id = node_field(member, 'name') or { continue }
						}
						if node_kind(member_id) == 'computed_property_name' {
							member_id = unwrap_parens(first_named(member_id) or { continue })
						}
						if node_kind(member_id) !in ['property_identifier', 'string'] {
							continue
						}
						items << c.nc_member('enumMember', member_id, 0)
					}
				}
			}
			'interface_declaration', 'type_alias_declaration' {
				id := node_field(node, 'name') or { continue }
				scope := tree.get_scope(node)
				name := c.identifier_name(id)
				mut modifiers := 0
				if c.nc_is_exported(node, name, tree, scope) {
					modifiers |= nc_modifiers['exported']
				}
				if c.nc_is_unused(name, tree, scope) {
					modifiers |= nc_modifiers['unused']
				}
				items << NcItem{if kind == 'interface_declaration' {
					'interface'
				} else {
					'typeAlias'
				}, id, modifiers}
			}
			'type_parameter' {
				// 'TSTypeParameterDeclaration > TSTypeParameter': not the one of `infer`.
				if parent_kind != 'type_parameters' {
					continue
				}
				id := node_field(node, 'name') or { continue }
				mut modifiers := 0
				if c.nc_is_unused(c.identifier_name(id), tree, tree.get_scope(node)) {
					modifiers |= nc_modifiers['unused']
				}
				items << NcItem{'typeParameter', id, modifiers}
			}
			else {}
		}
	}
	return items
}

// nc_function_name is the selector of FunctionDeclaration, TSDeclareFunction and
// FunctionExpression with a name.
fn (mut c Checker) nc_function_name(node C.TSNode, tree &ScopeTree, mut items []NcItem) {
	id := node_field(node, 'name') or { return }
	upper := tree.scopes[tree.get_scope(node)].upper
	name := c.identifier_name(id)
	mut modifiers := 0
	if nc_is_global(tree, upper) {
		modifiers |= nc_modifiers['global']
	}
	if c.nc_is_exported(node, name, tree, upper) {
		modifiers |= nc_modifiers['exported']
	}
	if c.nc_is_unused(name, tree, upper) {
		modifiers |= nc_modifiers['unused']
	}
	if has_child_kind(node, 'async') {
		modifiers |= nc_modifiers['async']
	}
	items << NcItem{'function', id, modifiers}
}

// nc_parameters is the selector of the parameters of a function, and of TSParameterProperty.
fn (mut c Checker) nc_parameters(node C.TSNode, tree &ScopeTree, mut items []NcItem) {
	mut parameters := []C.TSNode{}
	if list := node_field(node, 'parameters') {
		parameters = named_children(list).filter(node_kind(it) in ['required_parameter',
			'optional_parameter'])
	} else if single := node_field(node, 'parameter') {
		parameters = [single]
	}
	for parameter in parameters {
		mut identifiers := []C.TSNode{}
		nc_pattern_identifiers(parameter, mut identifiers)
		is_property := has_child_kind(parameter, 'accessibility_modifier')
			|| has_child_kind(parameter, 'readonly') || has_child_kind(parameter, 'override_modifier')
		if is_property {
			modifiers := c.nc_member_modifiers(parameter, none)
			for id in identifiers {
				items << NcItem{'parameterProperty', id, modifiers}
			}
			continue
		}
		for id in identifiers {
			mut modifiers := 0
			if node_kind(id) == 'shorthand_property_identifier_pattern' {
				modifiers |= nc_modifiers['destructured']
			}
			if c.nc_is_unused(c.nc_name(id), tree, tree.get_scope(id)) {
				modifiers |= nc_modifiers['unused']
			}
			items << NcItem{'parameter', id, modifiers}
		}
	}
}

// nc_imports is the selector of the default and namespace imports, and of `{ default as x }`.
fn (mut c Checker) nc_imports(node C.TSNode, mut items []NcItem) {
	for clause in named_children(node) {
		if node_kind(clause) != 'import_clause' {
			continue
		}
		for child in named_children(clause) {
			match node_kind(child) {
				'identifier' {
					items << NcItem{'import', child, nc_modifiers['default']}
				}
				'namespace_import' {
					for id in named_children(child) {
						if node_kind(id) == 'identifier' {
							items << NcItem{'import', id, nc_modifiers['namespace']}
						}
					}
				}
				'named_imports' {
					for specifier in named_children(child) {
						if node_kind(specifier) != 'import_specifier' {
							continue
						}
						imported := node_field(specifier, 'name') or { continue }
						if node_kind(imported) == 'identifier' && c.text(imported) != 'default' {
							continue
						}
						local := node_field(specifier, 'alias') or { imported }
						items << NcItem{'import', local, nc_modifiers['default']}
					}
				}
				else {}
			}
		}
	}
}

// nc_variables is the selector of VariableDeclarator: every name its pattern declares.
fn (mut c Checker) nc_variables(declarator C.TSNode, id C.TSNode, declaration C.TSNode, is_const bool, init ?C.TSNode, tree &ScopeTree, mut items []NcItem) {
	mut base := 0
	if is_const {
		base |= nc_modifiers['const']
	}
	if nc_is_global(tree, tree.get_scope(declarator)) {
		base |= nc_modifiers['global']
	}
	mut identifiers := []C.TSNode{}
	nc_pattern_identifiers(id, mut identifiers)
	for identifier in identifiers {
		mut modifiers := base
		if node_kind(identifier) == 'shorthand_property_identifier_pattern' {
			modifiers |= nc_modifiers['destructured']
		}
		name := c.nc_name(identifier)
		scope := tree.get_scope(identifier)
		if c.nc_is_exported(declaration, name, tree, scope) {
			modifiers |= nc_modifiers['exported']
		}
		if c.nc_is_unused(name, tree, scope) {
			modifiers |= nc_modifiers['unused']
		}
		// isAsyncVariableIdentifier: the name is the whole pattern and its value an async function.
		if node_key(identifier) == node_key(id) && nc_is_async_value(init) && nc_is_function_value(init) {
			modifiers |= nc_modifiers['async']
		}
		items << NcItem{'variable', identifier, modifiers}
	}
}

// nc_is_unused ports isUnused: the variable with that name, from the scope outwards, is one that
// nothing uses.
fn (mut c Checker) nc_is_unused(name string, tree &ScopeTree, initial_scope int) bool {
	mut scope := initial_scope
	for scope >= 0 {
		variable := tree.own_variable(scope, name)
		if variable >= 0 {
			return c.nc_unused[variable] or { false }
		}
		scope = tree.scopes[scope].upper
	}
	return false
}
