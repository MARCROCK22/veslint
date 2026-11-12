module rules

import json2
import math

// ESLint validates the options of a rule against the JSON schema of its meta with ajv 6.15.0
// (lib/shared/ajv.js: verbose, without allErrors) and words the errors itself
// (Config.validateRulesConfig). This ports what the validator ajv compiles does (lib/dot/*.jst) for
// the keywords the schemas of the ported rules use and their closest relatives
// (tools/rule_schema_support.mjs lists them, and the generator of rule_schemas.v rejects any
// other): the same errors, in the same order.
//
// ajv stops at the first error, except inside `oneOf`, `anyOf` and `not` (a "composite rule"):
// there the errors of every branch are kept, and they are dropped when the keyword passes.

// SchemaProblem is one error of ajv, with what ESLint prints of it.
struct SchemaProblem {
	keyword string
	message string
	data    json2.Any
	// Of an `additionalProperties` error: the property the schema does not have and, when the
	// schema has `properties` (error.parentSchema.properties), their names.
	additional   string
	has_expected bool
	expected     []string
}

struct SchemaValidator {
	root json2.Any
mut:
	problems []SchemaProblem
}

const schema_ref = '\$ref'

// schema_rule_keywords are the keys of ajv's RULES.all (lib/compile/rules.js): a schema without
// any of them accepts everything.
const schema_rule_keywords = ['type', '\$comment', 'maximum', 'exclusiveMaximum', 'minimum',
	'exclusiveMinimum', 'multipleOf', 'format', 'maxLength', 'minLength', 'pattern', 'maxItems',
	'minItems', 'items', 'contains', 'uniqueItems', 'maxProperties', 'minProperties', 'required',
	'dependencies', 'propertyNames', 'properties', 'additionalProperties', 'patternProperties',
	schema_ref, 'const', 'enum', 'not', 'anyOf', 'oneOf', 'allOf', 'if']

// The rules of each group of ajv's RULES that this validator implements, in ajv's order. A group
// with a type only runs on data of that type.
const schema_string_rules = ['maxLength', 'minLength']
const schema_array_rules = ['maxItems', 'minItems', 'items', 'uniqueItems']
const schema_object_rules = ['maxProperties', 'minProperties', 'required', 'properties',
	'additionalProperties']
const schema_any_rules = ['const', 'enum', 'not', 'anyOf', 'oneOf', 'allOf']

// rule_options_problems validates the options of a ported rule like ESLint does, under the
// default options of the rule's meta: the lines Config.validateRulesConfig makes of ajv's errors
// (each one `\tValue <JSON> <message>.\n`), or '' when the options fit the schema.
pub fn rule_options_problems(name string, options []json2.Any) string {
	text := rule_option_schemas[name] or { return '' }
	schema := json2.decode[json2.Any](text) or { return '' }
	return schema_problem_lines(schema, json2.Any(options_over_meta_defaults(name, options)))
}

// rule_options_inline_reason is what ESLint says of those options in a configuration comment:
// the linter takes the message of the error from after the rule, trimmed.
pub fn rule_options_inline_reason(name string, options []json2.Any) string {
	return js_trim(rule_options_problems(name, options))
}

// options_over_meta_defaults are the options ESLint validates and gives the rule: the configured
// ones over the meta.defaultOptions of the rule (deepMergeArrays).
fn options_over_meta_defaults(name string, options []json2.Any) []json2.Any {
	return deep_merge_arrays(eslint_default_options(name), options)
}

// eslint_default_options are the meta.defaultOptions of a rule of ESLint or of typescript-eslint,
// by its id; none for a rule without them or of another plugin.
fn eslint_default_options(id string) []json2.Any {
	text := eslint_rule_default_options[id] or { return []json2.Any{} }
	return (json2.decode[json2.Any](text) or { return []json2.Any{} }).as_array()
}

// normalized_rule_config ports what Config's #normalizeRulesConfig makes of the value of a rule in
// a configuration: a list with the severity as a number and then the options, over the default
// ones of the rule's meta.
pub fn normalized_rule_config(key string, value json2.Any) (string, json2.Any) {
	id := key
	items := if value is []json2.Any { value.as_array() } else { [value] }
	if items.len == 0 {
		return id, value
	}
	severity := rule_severity_of(items[0])
	mut normalized := [if severity < 0 { items[0] } else { json2.Any(severity) }]
	for option in deep_merge_arrays(eslint_default_options(id), items[1..]) {
		normalized << option
	}
	return id, json2.Any(normalized)
}

// schema_problem_lines validates `data` against `schema` and words ajv's errors like
// Config.validateRulesConfig.
fn schema_problem_lines(schema json2.Any, data json2.Any) string {
	mut validator := SchemaValidator{
		root: schema
	}
	validator.validate(schema, data, false)
	mut out := ''
	for problem in validator.problems {
		out += '\tValue ${js_json_stringify(problem.data)} ${problem.message}.\n'
		if problem.keyword == 'additionalProperties' && problem.has_expected {
			expected := problem.expected.map('"${it}"').join(', ')
			out += '\t\tUnexpected property "${problem.additional}". Expected properties: ${expected}.\n'
		}
	}
	return out
}

// validate ports lib/dot/validate.jst: the code of one schema. It adds the errors of `data` and
// tells whether there were none. `composite` is ajv's it.compositeRule.
fn (mut v SchemaValidator) validate(schema json2.Any, data json2.Any, composite bool) bool {
	if schema is bool {
		if schema {
			return true
		}
		v.problems << SchemaProblem{
			keyword: 'false schema'
			message: 'boolean schema is false'
			data:    data
		}
		return false
	}
	if schema !is map[string]json2.Any {
		return true
	}
	s := schema.as_map()
	reference := schema_string(s, schema_ref)
	if reference == '' && !schema_has_rules(schema) {
		return true
	}
	start := v.problems.len
	// The type is checked first when no rule of its group would: a list of types, a type without
	// rules of its own, or one whose rules the schema does not use. Inside a composite rule the
	// other keywords are checked all the same.
	types := schema_types(s)
	single := if types.len == 1 { types[0] } else { '' }
	if types.len > 0 && (single == '' || !schema_uses_group_of(s, single)) {
		if !types.any(json_is_type(data, it)) {
			v.add('type', 'should be ${types.join(',')}', data)
			if !composite {
				return false
			}
		}
	}
	// A `$ref` is validated alone: ajv ignores the keywords next to it (extendRefs).
	if reference != '' {
		v.validate_ref(reference, data, composite)
		return v.problems.len == start
	}
	if schema_uses(s, schema_string_rules) {
		if data is string {
			v.string_rules(s, data)
		} else if single == 'string' {
			v.add('type', 'should be string', data)
		}
		if v.problems.len != start {
			return false
		}
	}
	if schema_uses(s, schema_array_rules) {
		if data is []json2.Any {
			v.array_rules(s, data, composite)
		} else if single == 'array' {
			v.add('type', 'should be array', data)
		}
		if v.problems.len != start {
			return false
		}
	}
	if schema_uses(s, schema_object_rules) {
		if data is map[string]json2.Any {
			v.object_rules(s, data, composite)
		} else if single == 'object' {
			v.add('type', 'should be object', data)
		}
		if v.problems.len != start {
			return false
		}
	}
	if schema_uses(s, schema_any_rules) {
		v.any_rules(s, data, composite)
	}
	return v.problems.len == start
}

fn (mut v SchemaValidator) add(keyword string, message string, data json2.Any) {
	v.problems << SchemaProblem{
		keyword: keyword
		message: message
		data:    data
	}
}

// validate_ref ports lib/dot/ref.jst. A schema without a `$ref` inside is compiled in place, and
// keeps the composite rule it is in; any other is a function of its own, which stops at its first
// error. A reference that resolves to nothing is ignored (missingRefs: "ignore").
fn (mut v SchemaValidator) validate_ref(reference string, data json2.Any, composite bool) bool {
	if reference in ['#', '#/'] {
		return v.validate(v.root, data, false)
	}
	target := v.resolve(reference, 0) or { return true }
	return v.validate(target, data, composite && schema_has_no_ref(target))
}

// resolve ports getJsonPointer of lib/compile/resolve.js for a pointer into the root schema: a
// schema on the way that is a `$ref` is followed, except right under the names of
// PREVENT_SCOPE_CHANGE.
fn (v &SchemaValidator) resolve(reference string, depth int) ?json2.Any {
	if !reference.starts_with('#/') || depth > 32 {
		return none
	}
	mut schema := v.root
	for part in reference[2..].split('/') {
		if part == '' {
			continue
		}
		schema = json_child(schema, json_pointer_part(part)) or { return none }
		if part !in ['properties', 'patternProperties', 'enum', 'dependencies', 'definitions'] {
			inner := json_child(schema, schema_ref) or { json2.Any(json2.null) }
			if inner is string && inner != '' {
				if followed := v.resolve(inner, depth + 1) {
					schema = followed
				}
			}
		}
	}
	return schema
}

// json_child is `value[name]` of an object or an array.
fn json_child(value json2.Any, name string) ?json2.Any {
	if value is map[string]json2.Any {
		return value[name] or { return none }
	}
	if value is []json2.Any {
		if is_array_index_key(name) && name.int() < value.len {
			return value[name.int()]
		}
	}
	return none
}

// json_pointer_part is a part of a JSON pointer in a URI fragment, decoded (unescapeFragment):
// the `%XX` of the fragment, then `~1` and `~0`.
fn json_pointer_part(part string) string {
	mut bytes := []u8{cap: part.len}
	mut i := 0
	for i < part.len {
		if part[i] == `%` && i + 2 < part.len && part[i + 1].is_hex_digit()
			&& part[i + 2].is_hex_digit() {
			bytes << u8(('0x' + part[i + 1..i + 3]).int())
			i += 3
			continue
		}
		bytes << part[i]
		i++
	}
	return bytes.bytestr().replace('~1', '/').replace('~0', '~')
}

// schema_has_no_ref ports checkNoRef of lib/compile/resolve.js: no key is `$ref`, at any depth.
fn schema_has_no_ref(schema json2.Any) bool {
	if schema is []json2.Any {
		for item in schema {
			if !schema_has_no_ref(item) {
				return false
			}
		}
	} else if schema is map[string]json2.Any {
		for key, value in schema {
			if key == schema_ref || !schema_has_no_ref(value) {
				return false
			}
		}
	}
	return true
}

// string_rules are maxLength and minLength (lib/dot/_limitLength.jst); the length is counted in
// code points (ucs2length).
fn (mut v SchemaValidator) string_rules(s map[string]json2.Any, data json2.Any) bool {
	length := f64(data.str().runes().len)
	if limit := schema_number(s, 'maxLength') {
		if length > limit {
			v.add('maxLength', 'should NOT be longer than ${js_number_to_string(limit)} characters',
				data)
			return false
		}
	}
	if limit := schema_number(s, 'minLength') {
		if length < limit {
			v.add('minLength', 'should NOT be shorter than ${js_number_to_string(limit)} characters',
				data)
			return false
		}
	}
	return true
}

// array_rules are maxItems, minItems (lib/dot/_limitItems.jst), items and uniqueItems.
fn (mut v SchemaValidator) array_rules(s map[string]json2.Any, data json2.Any, composite bool) bool {
	items := data.as_array()
	if limit := schema_number(s, 'maxItems') {
		if f64(items.len) > limit {
			v.add('maxItems', 'should NOT have more than ${js_number_to_string(limit)} items',
				data)
			return false
		}
	}
	if limit := schema_number(s, 'minItems') {
		if f64(items.len) < limit {
			v.add('minItems', 'should NOT have fewer than ${js_number_to_string(limit)} items',
				data)
			return false
		}
	}
	if !v.items_rule(s, data, composite) {
		return false
	}
	return v.unique_items_rule(s, data)
}

// items_rule ports lib/dot/items.jst: a list of schemas is for the items at those places, with
// `additionalItems` for the rest; one schema is for every item.
fn (mut v SchemaValidator) items_rule(s map[string]json2.Any, data json2.Any, composite bool) bool {
	schema := s['items'] or { return true }
	items := data.as_array()
	if schema is []json2.Any {
		additional := s['additionalItems'] or { json2.Any(true) }
		if additional is bool && !(additional as bool) && items.len > schema.len {
			v.add('additionalItems', 'should NOT have more than ${schema.len} items',
				data)
			return false
		}
		for i, sub in schema {
			if i < items.len && !v.validate(sub, items[i], composite) {
				return false
			}
		}
		if additional is map[string]json2.Any && schema_has_rules(additional) {
			for i in schema.len .. items.len {
				if !v.validate(additional, items[i], composite) {
					return false
				}
			}
		}
		return true
	}
	for item in items {
		if !v.validate(schema, item, composite) {
			return false
		}
	}
	return true
}

// unique_items_rule ports lib/dot/uniqueItems.jst. When the items have a type that is neither
// object nor array, ajv looks from the last item for one of that type it has seen, by its text as
// a property name; otherwise it compares every pair. The message names the two places, in the
// order each way finds them.
fn (mut v SchemaValidator) unique_items_rule(s map[string]json2.Any, data json2.Any) bool {
	unique := s['uniqueItems'] or { return true }
	if unique !is bool || !(unique as bool) {
		return true
	}
	items := data.as_array()
	if items.len < 2 {
		return true
	}
	mut item_types := []string{}
	mut type_list := false
	if item_schema := s['items'] {
		if item_schema is map[string]json2.Any {
			item_types = schema_types(item_schema.as_map())
			type_list = (item_schema.as_map()['type'] or { json2.Any(json2.null) }) is []json2.Any
		}
	}
	mut first := -1
	mut second := -1
	if item_types.len == 0 || 'object' in item_types || 'array' in item_types {
		outer: for i := items.len - 1; i >= 0; i-- {
			for j := i - 1; j >= 0; j-- {
				if json_deep_equal(items[i], items[j]) {
					first = j
					second = i
					break outer
				}
			}
		}
	} else {
		mut seen := map[string]int{}
		for i := items.len - 1; i >= 0; i-- {
			item := items[i]
			if !item_types.any(json_is_type(item, it)) {
				continue
			}
			mut key := js_property_key(item)
			if type_list && item is string {
				key = '"' + key
			}
			// The places are properties of a plain object, which `__proto__` is not.
			if key == '__proto__' {
				continue
			}
			if key in seen {
				first = seen[key]
				second = i
				break
			}
			seen[key] = i
		}
	}
	if first < 0 {
		return true
	}
	v.add('uniqueItems', 'should NOT have duplicate items (items ## ${first} and ${second} are identical)',
		data)
	return false
}

// object_rules are maxProperties, minProperties (lib/dot/_limitProperties.jst), required and
// properties.
fn (mut v SchemaValidator) object_rules(s map[string]json2.Any, data json2.Any, composite bool) bool {
	object := data.as_map()
	if limit := schema_number(s, 'maxProperties') {
		if f64(object.len) > limit {
			v.add('maxProperties', 'should NOT have more than ${js_number_to_string(limit)} properties',
				data)
			return false
		}
	}
	if limit := schema_number(s, 'minProperties') {
		if f64(object.len) < limit {
			v.add('minProperties', 'should NOT have fewer than ${js_number_to_string(limit)} properties',
				data)
			return false
		}
	}
	properties := schema_map(s, 'properties')
	required := schema_strings(s, 'required')
	// lib/dot/required.jst: the required properties that have a schema are left to `properties`,
	// and the message of the others names the property as code would (`.name`).
	for name in required {
		if properties.len > 0 {
			if sub := properties[name] {
				if schema_has_rules(sub) {
					continue
				}
			}
		}
		if name !in object {
			v.add('required', "should have required property '${ajv_property(name)}'",
				data)
			return false
		}
	}
	if 'properties' !in s && 'additionalProperties' !in s {
		return true
	}
	// lib/dot/properties.jst: first the properties the schema does not have, in the order of the
	// data; then each property of the schema, in its order.
	property_names := js_object_keys(properties).filter(it != '__proto__')
	additional := s['additionalProperties'] or { json2.Any(true) }
	forbidden := additional is bool && !(additional as bool)
	checked := additional is map[string]json2.Any && additional.as_map().len > 0
	if forbidden || checked {
		for key in js_object_keys(object) {
			if key in property_names {
				continue
			}
			if forbidden {
				v.problems << SchemaProblem{
					keyword:      'additionalProperties'
					message:      'should NOT have additional properties'
					data:         data
					additional:   key
					has_expected: 'properties' in s
					expected:     js_object_keys(properties)
				}
				return false
			}
			if !v.validate(additional, object[key] or { json2.Any(json2.null) }, composite) {
				return false
			}
		}
	}
	for name in property_names {
		sub := properties[name] or { continue }
		if !schema_has_rules(sub) {
			continue
		}
		value := object[name] or {
			if name in required {
				v.add('required', "should have required property '${name}'", data)
				return false
			}
			continue
		}
		if !v.validate(sub, value, composite) {
			return false
		}
	}
	return true
}

// any_rules are the rules for data of any type: const, enum, not, anyOf, oneOf and allOf.
fn (mut v SchemaValidator) any_rules(s map[string]json2.Any, data json2.Any, composite bool) bool {
	if constant := s['const'] {
		if !json_deep_equal(data, constant) {
			v.add('const', 'should be equal to constant', data)
			return false
		}
	}
	if allowed := s['enum'] {
		if !allowed.as_array().any(json_deep_equal(data, it)) {
			v.add('enum', 'should be equal to one of the allowed values', data)
			return false
		}
	}
	if sub := s['not'] {
		// lib/dot/not.jst
		start := v.problems.len
		if !schema_has_rules(sub) || v.validate(sub, data, true) {
			v.add('not', 'should NOT be valid', data)
			return false
		}
		v.problems.trim(start)
	}
	if list := s['anyOf'] {
		// lib/dot/anyOf.jst: with a schema that accepts everything there is nothing to check.
		branches := list.as_array()
		if branches.all(schema_has_rules(it)) {
			start := v.problems.len
			mut valid := false
			for sub in branches {
				if v.validate(sub, data, true) {
					valid = true
					break
				}
			}
			if !valid {
				v.add('anyOf', 'should match some schema in anyOf', data)
				return false
			}
			v.problems.trim(start)
		}
	}
	if list := s['oneOf'] {
		// lib/dot/oneOf.jst: the branches after the second one that passes are not looked at.
		start := v.problems.len
		mut passing := 0
		for sub in list.as_array() {
			if v.validate(sub, data, true) {
				passing++
				if passing == 2 {
					break
				}
			}
		}
		if passing != 1 {
			v.add('oneOf', 'should match exactly one schema in oneOf', data)
			return false
		}
		v.problems.trim(start)
	}
	if list := s['allOf'] {
		for sub in list.as_array() {
			if !v.validate(sub, data, composite) {
				return false
			}
		}
	}
	return true
}

// schema_has_rules ports ajv's schemaHasRules with RULES.all (its "non-empty schema").
fn schema_has_rules(schema json2.Any) bool {
	if schema is bool {
		return !schema
	}
	if schema is map[string]json2.Any {
		for key, _ in schema {
			if key in schema_rule_keywords {
				return true
			}
		}
	}
	return false
}

fn schema_uses(s map[string]json2.Any, keywords []string) bool {
	for keyword in keywords {
		if keyword in s {
			return true
		}
	}
	return false
}

// schema_uses_group_of: the schema has a rule of the group of that type (RULES.types). The types
// without a group of rules, and `number`, whose rules are not implemented, have none.
fn schema_uses_group_of(s map[string]json2.Any, type_name string) bool {
	return match type_name {
		'string' { schema_uses(s, schema_string_rules) }
		'array' { schema_uses(s, schema_array_rules) }
		'object' { schema_uses(s, schema_object_rules) }
		else { false }
	}
}

// schema_types are the types of the `type` of a schema: one, or a list.
fn schema_types(s map[string]json2.Any) []string {
	value := s['type'] or { return []string{} }
	if value is string {
		return if value == '' { []string{} } else { [value] }
	}
	if value is []json2.Any {
		return value.map(it.str())
	}
	return []string{}
}

fn schema_string(s map[string]json2.Any, key string) string {
	value := s[key] or { return '' }
	return if value is string { value } else { '' }
}

fn schema_number(s map[string]json2.Any, key string) ?f64 {
	value := s[key] or { return none }
	if json_kind(value) != .number {
		return none
	}
	return json_number(value)
}

fn schema_map(s map[string]json2.Any, key string) map[string]json2.Any {
	value := s[key] or { return map[string]json2.Any{} }
	return if value is map[string]json2.Any { value.as_map() } else { map[string]json2.Any{} }
}

fn schema_strings(s map[string]json2.Any, key string) []string {
	value := s[key] or { return []string{} }
	return if value is []json2.Any { value.map(it.str()) } else { []string{} }
}

// ajv_property ports getProperty of lib/compile/util.js: how code reads a property with that name.
fn ajv_property(name string) string {
	mut identifier := name.len > 0
	for i, ch in name {
		if !(ch.is_letter() || ch == `$` || ch == `_` || (i > 0 && ch.is_digit())) {
			identifier = false
			break
		}
	}
	return if identifier { '.${name}' } else { "['${ajv_escape_quotes(name)}']" }
}

// ajv_escape_quotes ports escapeQuotes of lib/compile/util.js.
fn ajv_escape_quotes(name string) string {
	return name.replace_each(['\\', '\\\\', "'", "\\'", '\n', '\\n', '\r', '\\r', '\f', '\\f',
		'\t', '\\t'])
}

// JsonKind is what JavaScript's typeof and Array.isArray tell of a JSON value.
enum JsonKind {
	null
	boolean
	number
	string
	array
	object
}

fn json_kind(value json2.Any) JsonKind {
	return match value {
		json2.Null { .null }
		bool { .boolean }
		string { .string }
		[]json2.Any { .array }
		map[string]json2.Any { .object }
		else { .number }
	}
}

fn json_number(value json2.Any) f64 {
	return match value {
		f64 { value }
		f32 { f64(value) }
		i64 { f64(value) }
		int { f64(value) }
		i32 { f64(value) }
		i16 { f64(value) }
		i8 { f64(value) }
		u64 { f64(value) }
		u32 { f64(value) }
		u16 { f64(value) }
		u8 { f64(value) }
		else { 0 }
	}
}

// json_is_type ports checkDataType of lib/compile/util.js.
fn json_is_type(value json2.Any, type_name string) bool {
	kind := json_kind(value)
	return match type_name {
		'null' {
			kind == .null
		}
		'boolean' {
			kind == .boolean
		}
		'string' {
			kind == .string
		}
		'array' {
			kind == .array
		}
		'object' {
			kind == .object
		}
		'number' {
			kind == .number
		}
		'integer' {
			number := json_number(value)
			kind == .number && math.trunc(number) == number
		}
		else {
			false
		}
	}
}

// json_deep_equal ports fast-deep-equal for JSON values.
fn json_deep_equal(a json2.Any, b json2.Any) bool {
	kind := json_kind(a)
	if kind != json_kind(b) {
		return false
	}
	match kind {
		.null {
			return true
		}
		.boolean {
			return a.bool() == b.bool()
		}
		.number {
			return json_number(a) == json_number(b)
		}
		.string {
			return a.str() == b.str()
		}
		.array {
			left := a.as_array()
			right := b.as_array()
			if left.len != right.len {
				return false
			}
			for i, item in left {
				if !json_deep_equal(item, right[i]) {
					return false
				}
			}
			return true
		}
		.object {
			left := a.as_map()
			right := b.as_map()
			if left.len != right.len {
				return false
			}
			for key, value in left {
				other := right[key] or { return false }
				if !json_deep_equal(value, other) {
					return false
				}
			}
			return true
		}
	}
}

// js_object_keys are the keys of an object in JavaScript's order (Object.keys, for-in): the array
// indexes first, ascending, then the other names as they were added.
fn js_object_keys(object map[string]json2.Any) []string {
	mut indexes := []string{}
	mut others := []string{}
	for key, _ in object {
		if is_array_index_key(key) {
			indexes << key
		} else {
			others << key
		}
	}
	if indexes.len == 0 {
		return others
	}
	indexes.sort_with_compare(fn (a &string, b &string) int {
		return int(a.u64() > b.u64()) - int(a.u64() < b.u64())
	})
	indexes << others
	return indexes
}

// js_property_key is String(value) of a primitive JSON value, as a property name.
fn js_property_key(value json2.Any) string {
	return match json_kind(value) {
		.number { js_number_to_string(json_number(value)) }
		.string { value.str() }
		.boolean { value.bool().str() }
		else { 'null' }
	}
}

// js_json_stringify ports JSON.stringify(value) for a JSON value.
fn js_json_stringify(value json2.Any) string {
	match json_kind(value) {
		.null {
			return 'null'
		}
		.boolean {
			return value.bool().str()
		}
		.number {
			number := json_number(value)
			// NaN and the infinities, which JSON does not have.
			if number != number || number - number != 0 {
				return 'null'
			}
			return js_number_to_string(number)
		}
		.string {
			return js_json_quote(value.str())
		}
		.array {
			return '[' + value.as_array().map(js_json_stringify(it)).join(',') + ']'
		}
		.object {
			object := value.as_map()
			mut parts := []string{cap: object.len}
			for key in js_object_keys(object) {
				parts << js_json_quote(key) + ':' +
					js_json_stringify(object[key] or { json2.Any(json2.null) })
			}
			return '{' + parts.join(',') + '}'
		}
	}
}

// json_for_error ports stringifyValueForError of ESLint's messages/shared.js: a value that is
// false for JavaScript as its text (`present` is false for undefined), any other as
// JSON.stringify(value, null, 4) with every line after the first indented.
pub fn json_for_error(value json2.Any, present bool, indentation int) string {
	if !present {
		return 'undefined'
	}
	falsy := match json_kind(value) {
		.null { true }
		.boolean { !value.bool() }
		.number { json_number(value) == 0 }
		.string { value.str() == '' }
		else { false }
	}
	if falsy {
		return if value is string { '' } else { js_json_stringify(value) }
	}
	return js_json_indented(value, '').replace('\n', '\n' + ' '.repeat(indentation))
}

// js_json_indented ports JSON.stringify(value, null, 4).
fn js_json_indented(value json2.Any, indent string) string {
	inner := indent + '    '
	if value is []json2.Any {
		if value.len == 0 {
			return '[]'
		}
		return '[\n' + value.map(inner + js_json_indented(it, inner)).join(',\n') + '\n' + indent +
			']'
	}
	if value is map[string]json2.Any {
		if value.len == 0 {
			return '{}'
		}
		mut parts := []string{cap: value.len}
		for key in js_object_keys(value) {
			parts << inner + js_json_quote(key) + ': ' +
				js_json_indented(value[key] or { json2.Any(json2.null) }, inner)
		}
		return '{\n' + parts.join(',\n') + '\n' + indent + '}'
	}
	return js_json_stringify(value)
}

// json_is_number: typeof value is "number".
pub fn json_is_number(value json2.Any) bool {
	return json_kind(value) == .number
}

// rule_severity_of is the severity of a value of a rule (the ruleSeverities of
// flat-config-schema.js): 0, 1 or 2 for those numbers and for "off", "warn" and "error", or -1.
pub fn rule_severity_of(value json2.Any) int {
	if value is string {
		return ['off', 'warn', 'error'].index(value)
	}
	if json_kind(value) == .number {
		number := json_number(value)
		return if number == 0 {
			0
		} else if number == 1 {
			1
		} else if number == 2 {
			2
		} else {
			-1
		}
	}
	return -1
}

// js_json_quote ports QuoteJSONString: the quotes, the backslash and the control characters are
// escaped; everything else is written as it is.
fn js_json_quote(text string) string {
	mut out := []u8{cap: text.len + 2}
	out << `"`
	for ch in text.bytes() {
		match ch {
			`"` {
				out << '\\"'.bytes()
			}
			`\\` {
				out << '\\\\'.bytes()
			}
			0x08 {
				out << '\\b'.bytes()
			}
			0x0c {
				out << '\\f'.bytes()
			}
			`\n` {
				out << '\\n'.bytes()
			}
			`\r` {
				out << '\\r'.bytes()
			}
			`\t` {
				out << '\\t'.bytes()
			}
			else {
				if ch < 0x20 {
					out << '\\u00${ch.hex()}'.bytes()
				} else {
					out << ch
				}
			}
		}
	}
	out << `"`
	return out.bytestr()
}
