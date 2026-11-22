module rules

import estree
import encoding.utf8
import math
import tsgo { TypeResponse }
import treesitter { node_end }

// The helpers of eslint-plugin-unicorn 79.0.0 that tell what a value is without running the code
// (rules/utils/get-static-value.js, jsdoc.js, parse-jsdoc-type.js, jsdoc-type.js, type-helpers.js,
// types.js, is-array.js, is-bigint.js, is-string.js, is-reg-exp.js and
// should-skip-known-non-array-receiver.js), on the ESTree of the estree module. They are a part
// of unicorn_utils.v kept in a file of its own. Like unicorn's, they read the types of TypeScript
// (here tsgo's) when the file has them, as ESLint does with typescript-eslint's `projectService`.

// UnCtx is the file the helpers look at, and what they remember of it while a rule runs.
struct UnCtx {
	root     C.vt_node
	t        &estree.EsTree
	tokens   &SourceTokens
	abs_path string
mut:
	// 0 not looked yet, 1 the file has JSDoc comments, 2 it has none (hasJSDocumentComments).
	jsdoc_state int
	// The parsed tags of each JSDoc comment, by its start (getCommentTags).
	comment_tags map[int][]UnJsdocTag
}

// un_ctx is the UnCtx of the file of the tree.
fn (mut c Checker) un_ctx(root C.vt_node, t &estree.EsTree, tokens &SourceTokens, abs_path string) UnCtx {
	return unsafe {
		UnCtx{
			root:     root
			t:        t
			tokens:   tokens
			abs_path: abs_path
		}
	}
}

// un_find_variable ports findVariable(sourceCode.getScope(node), node) for an Identifier: its
// variable in the scope tree, -1 if none.
fn (mut c Checker) un_find_variable(ctx &UnCtx, node int) int {
	t := ctx.t
	if node < 0 || t.typ(node) != .identifier {
		return -1
	}
	ts := t.ts_node(node) or { return -1 }
	tree := c.scope_tree(ctx.root)
	return tree.find_variable(tree.get_scope(ts), t.string_of(node, .name) or { return -1 },
		t.nodes[node].start)
}

// un_only_definition is the only definition of a variable (`variable?.defs.length === 1 ?
// variable.defs[0] : undefined`).
fn (mut c Checker) un_only_definition(ctx &UnCtx, v int) ?ScopeDefinition {
	if v < 0 {
		return none
	}
	tree := c.scope_tree(ctx.root)
	if tree.variables[v].defs.len != 1 {
		return none
	}
	return tree.variables[v].defs[0]
}

// un_def_names_itself: `definition.node.id === definition.name` of a variable definition (not a
// destructuring).
fn un_def_names_itself(def ScopeDefinition) bool {
	decl_id := def.decl_id or { return false }
	return node_key(decl_id) == node_key(def.name)
}

// un_es_of is the ESTree node of a tree-sitter node of the file, -1 if none.
fn (mut c Checker) un_es_of(ctx &UnCtx, n ?C.vt_node) int {
	node := n or { return -1 }
	return c.es_index_of(ctx.t, node) or { -1 }
}

// un_is_global_identifier ports isGlobalIdentifier: an Identifier that references a global, or
// that resolves to no variable.
fn (mut c Checker) un_is_global_identifier(ctx &UnCtx, node int) bool {
	t := ctx.t
	if node < 0 || t.typ(node) != .identifier {
		return false
	}
	ts := t.ts_node(node) or { return false }
	return c.es_is_global_reference(ctx.root, ts) || c.un_find_variable(ctx, node) < 0
}

// UnConstDefinition is what getConstVariableDefinition gives: the variable and its initializer.
struct UnConstDefinition {
	variable    int
	initializer int
}

// un_const_definition ports getConstVariableDefinition of get-static-value.js: the variable of an
// Identifier with one `const` definition that has an initializer.
fn (mut c Checker) un_const_definition(ctx &UnCtx, node int) ?UnConstDefinition {
	if node < 0 || ctx.t.typ(node) != .identifier {
		return none
	}
	v := c.un_find_variable(ctx, node)
	def := c.un_only_definition(ctx, v)?
	if def.kind != .variable || def.parent_kind != 'const' || !un_def_names_itself(def) {
		return none
	}
	init := c.un_es_of(ctx, def.init)
	if init < 0 {
		return none
	}
	return UnConstDefinition{v, init}
}

// un_evaluated_children ports getEvaluatedChildNodes: the children without the names that are not
// evaluated (non-computed member properties and property keys).
fn un_evaluated_children(t &estree.EsTree, node int) []int {
	computed := t.flag(node, .computed) or { false }
	typ := t.typ(node)
	if computed || typ !in [.member_expression, .property, .property_definition, .method_definition] {
		return t.children(node)
	}
	skipped := if typ == .member_expression {
		t.node(node, .property) or { -1 }
	} else {
		t.node(node, .key) or { -1 }
	}
	return t.children(node).filter(it != skipped)
}

const un_unevaluated_types = [estree.NodeType.function_expression, .arrow_function_expression,
	.class_expression]

const un_static_global_properties = {
	'Math':   ['E', 'LN2', 'LN10', 'LOG2E', 'LOG10E', 'PI', 'SQRT1_2', 'SQRT2']
	'Number': ['EPSILON', 'MAX_SAFE_INTEGER', 'MAX_VALUE', 'MIN_SAFE_INTEGER', 'MIN_VALUE', 'NaN',
		'NEGATIVE_INFINITY', 'POSITIVE_INFINITY']
	'String': ['raw']
	'Symbol': ['asyncIterator', 'hasInstance', 'isConcatSpreadable', 'iterator', 'match', 'matchAll',
		'replace', 'search', 'species', 'split', 'toPrimitive', 'toStringTag', 'unscopables']
}

// un_is_safe_static_global_member ports isSafeStaticGlobalMember: `Math.PI` and the like, on the
// globals.
fn (mut c Checker) un_is_safe_static_global_member(ctx &UnCtx, node int) bool {
	t := ctx.t
	if t.typ(node) != .member_expression || (t.flag(node, .optional) or { false }) {
		return false
	}
	object := t.node(node, .object) or { return false }
	if t.typ(object) != .identifier || !c.un_is_global_identifier(ctx, object) {
		return false
	}
	properties := un_static_global_properties[t.string_of(object, .name) or { '' }] or {
		return false
	}
	property := t.node(node, .property) or { return false }
	name := if t.flag(node, .computed) or { false } {
		un_static_string_value(t, property) or { return false }
	} else if t.typ(property) == .identifier {
		t.string_of(property, .name) or { return false }
	} else {
		return false
	}
	return name in properties
}

// un_is_safe_static_pass_through_call ports isSafeStaticPassThroughCall: `Object.freeze(x)`,
// `Object.seal(x)` or `Object.preventExtensions(x)` of a static value.
fn (mut c Checker) un_is_safe_static_pass_through_call(mut ctx UnCtx, from int, mut visited map[int]bool) bool {
	t := ctx.t
	node := un_unwrap_ts_expression(t, from)
	if node < 0 || t.typ(node) != .call_expression {
		return false
	}
	callee := un_unwrap_ts_expression(t, t.node(node, .callee) or { return false })
	if (t.flag(node, .optional) or { false }) || t.typ(callee) != .member_expression {
		return false
	}
	args := t.list(node, .arguments) or { return false }
	if args.len != 1 || t.typ(args[0]) == .spread_element || (t.flag(callee, .computed) or { false })
		|| (t.flag(callee, .optional) or { false }) {
		return false
	}
	object := un_unwrap_ts_expression(t, t.node(callee, .object) or { return false })
	property := t.node(callee, .property) or { return false }
	return t.typ(object) == .identifier && (t.string_of(object, .name) or { '' }) == 'Object'
		&& c.un_is_global_identifier(ctx, object) && t.typ(property) == .identifier
		&& (t.string_of(property, .name) or { '' }) in ['freeze', 'preventExtensions', 'seal']
		&& c.un_static_value_no_side_effects_in(mut ctx, args[0], mut visited) != none
}

// un_is_branch_expression ports isBranchExpression.
fn un_is_branch_expression(t &estree.EsTree, from int) bool {
	mut node := un_unwrap_ts_expression(t, from)
	for node >= 0 && t.typ(node) == .unary_expression {
		node = un_unwrap_ts_expression(t, t.node(node, .argument) or { return false })
	}
	return node >= 0 && t.typ(node) in [.conditional_expression, .logical_expression]
}

// un_has_side_effectful_const_reference ports hasSideEffectfulConstReference.
fn (mut c Checker) un_has_side_effectful_const_reference(mut ctx UnCtx, node int, mut visited map[int]bool) bool {
	t := ctx.t
	if t.typ(node) == .identifier {
		return c.un_has_side_effectful_const_initializer(mut ctx, node, mut visited)
	}
	if t.typ(node) in un_unevaluated_types {
		return false
	}
	for child in un_evaluated_children(t, node) {
		if c.un_has_side_effectful_const_reference(mut ctx, child, mut visited) {
			return true
		}
	}
	return false
}

// un_has_side_effectful_const_initializer ports hasSideEffectfulConstInitializer: the node is (or
// refers to) a `const` whose initializer has a side effect, getters included.
fn (mut c Checker) un_has_side_effectful_const_initializer(mut ctx UnCtx, node int, mut visited map[int]bool) bool {
	t := ctx.t
	definition := c.un_const_definition(ctx, node) or {
		return t.typ(node) != .identifier
			&& c.un_has_side_effectful_const_reference(mut ctx, node, mut visited)
	}
	if definition.variable in visited {
		return true
	}
	visited[definition.variable] = true
	result := (!c.un_is_safe_static_pass_through_call(mut ctx, definition.initializer, mut
		visited) && un_has_side_effect(t, definition.initializer, consider_getters: true))
		|| c.un_has_side_effectful_const_reference(mut ctx, definition.initializer, mut visited)
	visited.delete(definition.variable)
	return result
}

// un_static_key_name is getStaticPropertyName of get-static-value.js without a context: the name
// of a non-computed identifier key, or a string or number literal.
fn un_static_key_name(t &estree.EsTree, node int, property int) ?string {
	if t.typ(property) == .identifier && !(t.flag(node, .computed) or { false }) {
		return t.string_of(property, .name)
	}
	if t.typ(property) == .literal {
		value := t.get(property, .value)
		if value is string {
			return value
		}
		if value is f64 {
			return js_number_to_string(value)
		}
	}
	return none
}

// un_static_property_value_name ports getStaticPropertyName with a context: also a computed key
// with a static string or number value (an identifier only when it is a `const`).
fn (mut c Checker) un_static_property_value_name(ctx &UnCtx, node int, property int) ?string {
	t := ctx.t
	if name := un_static_key_name(t, node, property) {
		return name
	}
	if !(t.flag(node, .computed) or { false }) {
		return none
	}
	if t.typ(property) == .identifier && c.un_const_definition(ctx, property) == none {
		return none
	}
	result := c.un_static_value(t, property)
	if result.found && result.value.kind in [.string_, .number_] {
		return js_any_string_value(result.value)
	}
	return none
}

// un_is_safe_static_object_member ports isSafeStaticObjectMember.
fn (mut c Checker) un_is_safe_static_object_member(mut ctx UnCtx, node int, property_name ?string, mut visited map[int]bool) bool {
	t := ctx.t
	name := property_name or { return false }
	properties := t.list(node, .properties) or { []int{} }
	for property in properties {
		if t.typ(property) != .property || (t.flag(property, .computed) or { false }) {
			return false
		}
		key := t.node(property, .key) or { return false }
		if (t.string_of(key, .name) or { '' }) == '__proto__' || un_is_literal_string(t, key, '__proto__') {
			return false
		}
		value := t.node(property, .value) or { return false }
		if c.un_has_potentially_mutable_member_access(mut ctx, value, mut visited) {
			return false
		}
	}
	mut found := -1
	for candidate in properties {
		key := t.node(candidate, .key) or { continue }
		if candidate_name := un_static_key_name(t, candidate, key) {
			if candidate_name == name {
				found = candidate
			}
		}
	}
	return found >= 0 && (t.string_of(found, .kind) or { '' }) == 'init'
		&& !(t.flag(found, .method) or { false })
}

// un_array_index ports `Number(name)` checked as a safe, non-negative integer written as it is.
fn un_array_index(name string) ?int {
	if name == '' || !name.bytes().all(it.is_digit()) || (name.len > 1 && name[0] == `0`)
		|| name.len > 15 {
		return none
	}
	return name.int()
}

// un_is_safe_static_array_member ports isSafeStaticArrayMember.
fn (mut c Checker) un_is_safe_static_array_member(mut ctx UnCtx, node int, property_name ?string, mut visited map[int]bool) bool {
	t := ctx.t
	elements := t.list(node, .elements) or { []int{} }
	for element in elements {
		if element < 0 {
			continue
		}
		if t.typ(element) == .spread_element
			|| c.un_has_potentially_mutable_member_access(mut ctx, element, mut visited) {
			return false
		}
	}
	name := property_name or { return false }
	if name == 'length' {
		return true
	}
	index := un_array_index(name) or { return false }
	return index < elements.len && elements[index] >= 0
}

// un_is_safe_static_member_object ports isSafeStaticMemberObject.
fn (mut c Checker) un_is_safe_static_member_object(mut ctx UnCtx, node int, property_name ?string, mut visited map[int]bool) bool {
	t := ctx.t
	mut primitive := un_static_string_value(t, node)
	if primitive == none {
		if definition := c.un_const_definition(ctx, node) {
			primitive = un_static_string_value(t, definition.initializer)
		}
	}
	if text := primitive {
		name := property_name or { return false }
		if name == 'length' {
			return true
		}
		index := un_array_index(name) or { return false }
		return index < estree.utf16_units(text).len
	}
	if t.typ(node) == .array_expression {
		return c.un_is_safe_static_array_member(mut ctx, node, property_name, mut visited)
	}
	if t.typ(node) == .object_expression {
		return c.un_is_safe_static_object_member(mut ctx, node, property_name, mut visited)
	}
	return false
}

// un_is_safe_static_member ports isSafeStaticMember.
fn (mut c Checker) un_is_safe_static_member(mut ctx UnCtx, node int, mut visited map[int]bool) bool {
	t := ctx.t
	property := t.node(node, .property) or { return false }
	property_name := c.un_static_property_value_name(ctx, node, property)
	if (t.flag(node, .computed) or { false })
		&& c.un_has_potentially_mutable_member_access(mut ctx, property, mut visited) {
		return false
	}
	return c.un_is_safe_static_member_object(mut ctx, t.node(node, .object) or { return false },
		property_name, mut visited)
}

// un_has_potentially_mutable_member_access ports hasPotentiallyMutableMemberAccess: reading the
// node reads a member that may have changed since getStaticValue saw it.
fn (mut c Checker) un_has_potentially_mutable_member_access(mut ctx UnCtx, from int, mut visited map[int]bool) bool {
	t := ctx.t
	mut node := un_unwrap_ts_expression(t, from)
	if node < 0 {
		return false
	}
	if t.typ(node) == .chain_expression {
		node = t.node(node, .expression) or { return false }
	}
	if c.un_is_safe_static_pass_through_call(mut ctx, node, mut visited) {
		return false
	}
	if definition := c.un_const_definition(ctx, node) {
		if definition.variable in visited {
			return true
		}
		visited[definition.variable] = true
		result := c.un_has_potentially_mutable_member_access(mut ctx, definition.initializer, mut
			visited)
		visited.delete(definition.variable)
		return result
	}
	if t.typ(node) == .member_expression {
		return !c.un_is_safe_static_global_member(ctx, node)
			&& !c.un_is_safe_static_member(mut ctx, node, mut visited)
	}
	for child in un_evaluated_children(t, node) {
		if c.un_has_potentially_mutable_member_access(mut ctx, child, mut visited) {
			return true
		}
	}
	return false
}

// un_has_unsafe_binding_in_evaluated_path ports hasUnsafeBindingInEvaluatedPath: on a path that
// can be evaluated, a binding that is not a `const`, or a `const` read before its declaration
// ends.
fn (mut c Checker) un_has_unsafe_binding_in_evaluated_path(mut ctx UnCtx, from int, mut visited map[int]bool) bool {
	t := ctx.t
	node := un_unwrap_ts_expression(t, from)
	if node < 0 {
		return false
	}
	match t.typ(node) {
		.identifier {
			v := c.un_find_variable(ctx, node)
			def := c.un_only_definition(ctx, v) or { return false }
			if def.kind != .variable {
				return false
			}
			if def.parent_kind != 'const' {
				return true
			}
			if node_end(def.node) > t.nodes[node].start {
				return true
			}
			init := c.un_es_of(ctx, def.init)
			if init < 0 || v in visited {
				return false
			}
			visited[v] = true
			result := c.un_has_unsafe_binding_in_evaluated_path(mut ctx, init, mut visited)
			visited.delete(v)
			return result
		}
		.conditional_expression {
			test := t.node(node, .test) or { return false }
			consequent := t.node(node, .consequent) or { return false }
			alternate := t.node(node, .alternate) or { return false }
			if c.un_has_unsafe_binding_in_evaluated_path(mut ctx, test, mut visited) {
				return true
			}
			if value := c.un_static_value_no_side_effects_in(mut ctx, test, mut visited) {
				return c.un_has_unsafe_binding_in_evaluated_path(mut ctx, if stv_to_boolean(value.value) {
					consequent
				} else {
					alternate
				}, mut visited)
			}
			return c.un_has_unsafe_binding_in_evaluated_path(mut ctx, consequent, mut visited)
				|| c.un_has_unsafe_binding_in_evaluated_path(mut ctx, alternate, mut visited)
		}
		.logical_expression {
			left := t.node(node, .left) or { return false }
			right := t.node(node, .right) or { return false }
			if c.un_has_unsafe_binding_in_evaluated_path(mut ctx, left, mut visited) {
				return true
			}
			if value := c.un_static_value_no_side_effects_in(mut ctx, left, mut visited) {
				operator := t.string_of(node, .operator) or { '' }
				evaluates_right := match operator {
					'&&' { stv_to_boolean(value.value) }
					'||' { !stv_to_boolean(value.value) }
					else { value.value.kind in [.null_, .undefined_] }
				}
				return evaluates_right
					&& c.un_has_unsafe_binding_in_evaluated_path(mut ctx, right, mut visited)
			}
			return c.un_has_unsafe_binding_in_evaluated_path(mut ctx, right, mut visited)
		}
		.sequence_expression {
			for expression in t.list(node, .expressions) or { []int{} } {
				if c.un_has_unsafe_binding_in_evaluated_path(mut ctx, expression, mut visited) {
					return true
				}
			}
			return false
		}
		else {}
	}
	if t.typ(node) in un_unevaluated_types {
		return false
	}
	for child in un_evaluated_children(t, node) {
		if c.un_has_unsafe_binding_in_evaluated_path(mut ctx, child, mut visited) {
			return true
		}
	}
	return false
}

// un_static_value_no_side_effects_in ports getStaticValueIfNoSideEffectsInternal.
fn (mut c Checker) un_static_value_no_side_effects_in(mut ctx UnCtx, from int, mut visited map[int]bool) ?StaticValue {
	t := ctx.t
	node := un_unwrap_ts_expression(t, from)
	if node < 0 {
		return none
	}
	// Static evaluation runs allowed builtins: reject side effects first.
	if (un_has_side_effect(t, node)
		&& !c.un_is_safe_static_pass_through_call(mut ctx, node, mut visited))
		|| c.un_has_side_effectful_const_initializer(mut ctx, node, mut visited) {
		return none
	}
	value := c.un_static_value(t, node)
	if !value.found {
		return none
	}
	if c.un_has_potentially_mutable_member_access(mut ctx, node, mut visited) {
		return none
	}
	return value
}

// un_static_value_if_no_side_effects ports getStaticValueIfNoSideEffects: the static value of a
// node only when evaluating it has no side effects or mutable member reads.
fn (mut c Checker) un_static_value_if_no_side_effects(mut ctx UnCtx, node int) ?StaticValue {
	mut visited := map[int]bool{}
	return c.un_static_value_no_side_effects_in(mut ctx, node, mut visited)
}

// un_static_value_for_control_flow ports getStaticValueForControlFlow: getStaticValue is not
// flow-sensitive, so mutable bindings and constants read before their declaration completes on an
// evaluated path have none.
fn (mut c Checker) un_static_value_for_control_flow(mut ctx UnCtx, node int) ?StaticValue {
	value := c.un_static_value_if_no_side_effects(mut ctx, node)?
	mut visited := map[int]bool{}
	if c.un_has_unsafe_binding_in_evaluated_path(mut ctx, node, mut visited) {
		return none
	}
	return value
}

// ---- JSDoc (jsdoc.js, parse-jsdoc-type.js and jsdoc-type.js). Texts are arrays of code points,
// as the `v` regular expressions of unicorn read them.

// UnJsdocType is a type parseJSDocumentType reads: `kind` is 'unknown', 'name' (`name`),
// 'nullish' (`name` is null or undefined), 'non-primitive', 'function' (`elements[0]` is its
// return type), 'union' and 'intersection' (`elements`), 'optional' and 'nullable'
// (`elements[0]`).
struct UnJsdocType {
	kind     string
	name     string
	elements []UnJsdocType
}

// UnJsdocTag is a tag parseTag gives: its name, and for the ones with a type, the type, the name
// of a parameter and whether it is optional.
struct UnJsdocTag {
	tag      string
	name     string
	has_type bool
	typ      UnJsdocType
	optional bool
}

// UnJsdocAnnotation is what getAnnotation gives: the type of the tag and whether it is optional.
struct UnJsdocAnnotation {
	has_type bool
	typ      UnJsdocType
	optional bool
}

fn un_jsdoc_unknown() UnJsdocType {
	return UnJsdocType{
		kind: 'unknown'
	}
}

fn un_jsdoc_name(name string) UnJsdocType {
	return UnJsdocType{
		kind: 'name'
		name: name
	}
}

fn un_is_id_start_rune(r rune) bool {
	return r == `$` || r == `_` || ts_is_identifier_start(u32(r))
}

fn un_is_id_part_rune(r rune) bool {
	return r == `$` || r == 0x200c || r == 0x200d || ts_is_identifier_part(u32(r))
}

// un_is_jsdoc_identifier: /^[\p{ID_Start}$_][\p{ID_Continue}$\u{200C}\u{200D}]*$/v.
fn un_is_jsdoc_identifier(text string) bool {
	runes := text.runes()
	if runes.len == 0 || !un_is_id_start_rune(runes[0]) {
		return false
	}
	return runes[1..].all(un_is_id_part_rune(it))
}

// un_jsdoc_primitive is primitiveTypes of parse-jsdoc-type.js.
fn un_jsdoc_primitive(name string) ?UnJsdocType {
	normalized := match name {
		'Boolean' { 'boolean' }
		'String' { 'string' }
		'Number' { 'number' }
		'Void' { 'void' }
		'Null' { 'null' }
		'Undefined' { 'undefined' }
		'boolean', 'string', 'number', 'bigint', 'symbol', 'void', 'null', 'undefined', 'true',
		'false', 'any', 'unknown', 'never' { name }
		else { return none }
	}
	if normalized in ['any', 'unknown', 'never'] {
		return un_jsdoc_unknown()
	}
	if normalized in ['null', 'undefined'] {
		return UnJsdocType{
			kind: 'nullish'
			name: normalized
		}
	}
	return un_jsdoc_name(if normalized in ['true', 'false'] { 'boolean' } else { normalized })
}

const un_jsdoc_primitive_names = ['boolean', 'string', 'number', 'bigint', 'symbol', 'void', 'null',
	'undefined', 'true', 'false', 'Boolean', 'String', 'Number', 'Void', 'Null', 'Undefined', 'any',
	'unknown', 'never']
const un_jsdoc_reserved_names = ['import', 'typeof', 'extends', 'new']
const un_jsdoc_unsupported_names = ['import', 'typeof', 'extends', 'new', 'keyof', 'infer', 'asserts',
	'is', 'readonly']

fn un_is_hex_rune(r rune) bool {
	return (r >= `0` && r <= `9`) || (r >= `a` && r <= `f`) || (r >= `A` && r <= `F`)
}

fn un_is_digit_rune(r rune) bool {
	return r >= `0` && r <= `9`
}

// un_digits_with_separators matches `d(?:_?d)*` at i for the digit predicate: the end, or -1.
fn un_digits_with_separators(text []rune, i int, is_digit fn (rune) bool) int {
	if i >= text.len || !is_digit(text[i]) {
		return -1
	}
	mut j := i + 1
	for {
		if j < text.len && is_digit(text[j]) {
			j++
		} else if j + 1 < text.len && text[j] == `_` && is_digit(text[j + 1]) {
			j += 2
		} else {
			break
		}
	}
	return j
}

// un_jsdoc_exponent matches `(?:[Ee][+\-]?\d(?:_?\d)*)?` at i: its end.
fn un_jsdoc_exponent(text []rune, i int) int {
	if i < text.len && text[i] in [`e`, `E`] {
		mut j := i + 1
		if j < text.len && text[j] in [`+`, `-`] {
			j++
		}
		end := un_digits_with_separators(text, j, un_is_digit_rune)
		if end >= 0 {
			return end
		}
	}
	return i
}

// un_jsdoc_number_token matches the numeric alternative of tokenPattern at i: its end, or -1.
fn un_jsdoc_number_token(text []rune, i int) int {
	mut end := -1
	if i + 1 < text.len && text[i] == `0` && text[i + 1] in [`x`, `X`, `b`, `B`, `o`, `O`] {
		predicate := match text[i + 1] {
			`x`, `X` { un_is_hex_rune }
			`b`, `B` { fn (r rune) bool {
					return r == `0` || r == `1`
				} }
			else { fn (r rune) bool {
					return r >= `0` && r <= `7`
				} }
		}
		end = un_digits_with_separators(text, i + 2, predicate)
	}
	if end < 0 && i < text.len {
		if text[i] == `0` || (text[i] >= `1` && text[i] <= `9`) {
			// `(?:0|[1-9](?:_?\d)*)(?:\.(?:\d(?:_?\d)*)?)?` and the exponent.
			mut j := if text[i] == `0` { i + 1 } else { un_digits_with_separators(text, i, un_is_digit_rune) }
			if j < text.len && text[j] == `.` {
				fraction := un_digits_with_separators(text, j + 1, un_is_digit_rune)
				j = if fraction >= 0 { fraction } else { j + 1 }
			}
			end = un_jsdoc_exponent(text, j)
		} else if text[i] == `.` {
			fraction := un_digits_with_separators(text, i + 1, un_is_digit_rune)
			if fraction >= 0 {
				end = un_jsdoc_exponent(text, fraction)
			}
		}
	}
	if end < 0 {
		return -1
	}
	if end < text.len && text[end] == `n` {
		end++
	}
	return end
}

// un_jsdoc_string_token matches `"(?:\\[^\n\r]|[^\n\r"\\])*"` (or with `'`) at i: its end, or -1.
fn un_jsdoc_string_token(text []rune, i int) int {
	quote := text[i]
	mut j := i + 1
	for j < text.len {
		r := text[j]
		if r == `\\` {
			if j + 1 < text.len && text[j + 1] !in [`\n`, `\r`] {
				j += 2
				continue
			}
			return -1
		}
		if r in [`\n`, `\r`] {
			return -1
		}
		if r == quote {
			return j + 1
		}
		j++
	}
	return -1
}

// un_jsdoc_tokens splits a type like tokenPattern: the tokens without white space, and the
// indexes of the tokens that a line break precedes. None when a string token is malformed.
fn un_jsdoc_tokens(text []rune) ?([]string, map[int]bool) {
	mut tokens := []string{}
	mut line_breaks := map[int]bool{}
	mut i := 0
	for i < text.len {
		r := text[i]
		mut end := i + 1
		if is_js_space(r) {
			for end < text.len && is_js_space(text[end]) {
				end++
			}
			if text[i..end].any(it in [`\n`, `\r`, 0x2028, 0x2029]) {
				line_breaks[tokens.len] = true
			}
			i = end
			continue
		}
		if r == `=` && i + 1 < text.len && text[i + 1] == `>` {
			end = i + 2
		} else if r == `.` && i + 2 < text.len && text[i + 1] == `.` && text[i + 2] == `.` {
			end = i + 3
		} else if un_is_id_start_rune(r) {
			for end < text.len && un_is_id_part_rune(text[end]) {
				end++
			}
		} else if number_end := un_jsdoc_number_or_none(text, i) {
			end = number_end
		} else if r in [`"`, `'`] {
			string_end := un_jsdoc_string_token(text, i)
			if string_end < 0 {
				// The token is the quote alone.
				return none
			}
			token := text[i..string_end].string()
			if !un_jsdoc_valid_string_escapes(token) {
				return none
			}
			end = string_end
		}
		tokens << text[i..end].string()
		i = end
	}
	return tokens, line_breaks
}

fn un_jsdoc_number_or_none(text []rune, i int) ?int {
	end := un_jsdoc_number_token(text, i)
	return if end < 0 { none } else { end }
}

// un_jsdoc_valid_string_escapes ports hasValidStringEscapes.
fn un_jsdoc_valid_string_escapes(token string) bool {
	runes := token.runes()
	mut i := 0
	for i + 1 < runes.len {
		if runes[i] != `\\` {
			i++
			continue
		}
		escaped := runes[i + 1]
		following := if i + 2 <= runes.len - 1 { runes[i + 2..runes.len - 1] } else { []rune{} }
		if escaped == `x` && !(following.len >= 2 && un_is_hex_rune(following[0])
			&& un_is_hex_rune(following[1])) {
			return false
		}
		if escaped == `u` {
			four := following.len >= 4 && following[..4].all(un_is_hex_rune(it))
			mut code_point := false
			if following.len >= 3 && following[0] == `{` {
				mut j := 1
				for j < following.len && j <= 6 && un_is_hex_rune(following[j]) {
					j++
				}
				if j > 1 && j < following.len && following[j] == `}` {
					code_point = following[1..j].string().parse_int(16, 64) or { 0x110000 } <= 0x10ffff
				}
			}
			if !four && !code_point {
				return false
			}
		}
		i += 2
	}
	return true
}

// UnJsdocParser is the state of parseJSDocumentType.
struct UnJsdocParser {
	tokens       []string
	line_breaks  map[int]bool
	paren_closes map[int]int
mut:
	index int
}

fn (p &UnJsdocParser) at(i int) string {
	return if i >= 0 && i < p.tokens.len { p.tokens[i] } else { '' }
}

fn (p &UnJsdocParser) has(i int) bool {
	return i >= 0 && i < p.tokens.len
}

fn (mut p UnJsdocParser) consume(token string) bool {
	if p.has(p.index) && p.tokens[p.index] == token {
		p.index++
		return true
	}
	return false
}

fn (mut p UnJsdocParser) expect(token string) ! {
	if !p.consume(token) {
		return error('Unsupported JSDoc type')
	}
}

fn (mut p UnJsdocParser) parse_optional() !UnJsdocType {
	typ := p.parse_union()!
	if p.consume('=') {
		return UnJsdocType{
			kind:     'optional'
			elements: [typ]
		}
	}
	return typ
}

fn (mut p UnJsdocParser) parse_union() !UnJsdocType {
	p.consume('|')
	mut elements := [p.parse_intersection()!]
	for p.consume('|') {
		elements << p.parse_intersection()!
	}
	return if elements.len == 1 {
		elements[0]
	} else {
		UnJsdocType{
			kind:     'union'
			elements: elements
		}
	}
}

fn (mut p UnJsdocParser) parse_intersection() !UnJsdocType {
	p.consume('&')
	mut elements := [p.parse_postfix()!]
	for p.consume('&') {
		elements << p.parse_postfix()!
	}
	return if elements.len == 1 {
		elements[0]
	} else {
		UnJsdocType{
			kind:     'intersection'
			elements: elements
		}
	}
}

fn (mut p UnJsdocParser) parse_postfix() !UnJsdocType {
	mut typ := UnJsdocType{}
	if p.consume('?') {
		if p.at(p.index) in ['?', '!'] && p.has(p.index) {
			return error('Unsupported JSDoc type')
		}
		typ = if !p.has(p.index) || p.at(p.index) in [')', '>', ']', '}', ',', ';', '|', '&'] {
			un_jsdoc_unknown()
		} else {
			UnJsdocType{
				kind:     'nullable'
				elements: [p.parse_postfix()!]
			}
		}
	} else if p.consume('!') {
		if p.has(p.index) && p.at(p.index) == '!' {
			return error('Unsupported JSDoc type')
		}
		typ = p.parse_postfix()!
	} else if p.consume('...') {
		p.parse_postfix()!
		typ = UnJsdocType{
			kind: 'non-primitive'
		}
	} else if p.consume('readonly') {
		typ = p.parse_postfix()!
		if typ.kind != 'name' || typ.name !in ['Array', 'ReadonlyArray'] {
			return error('Unsupported JSDoc type')
		}
	} else {
		typ = p.parse_primary()!
	}
	for p.at(p.index) == '[' && p.at(p.index + 1) == ']' {
		p.index += 2
		typ = un_jsdoc_name('Array')
	}
	if p.consume('?') {
		return UnJsdocType{
			kind:     'nullable'
			elements: [typ]
		}
	}
	p.consume('!')
	return typ
}

// UnJsdocMember says which member parser parse_list calls.
enum UnJsdocMember {
	union_
	arrow_parameter
	function_parameter
	tuple_member
}

fn (mut p UnJsdocParser) parse_member(member UnJsdocMember) ! {
	match member {
		.union_ {
			p.parse_union()!
		}
		.arrow_parameter {
			p.consume('...')
			token := p.at(p.index)
			if !un_is_jsdoc_identifier(token) || token in un_jsdoc_reserved_names {
				return error('Unsupported JSDoc parameter')
			}
			p.index++
			p.consume('?')
			if p.consume(':') {
				p.parse_union()!
			}
		}
		.function_parameter {
			if p.consume('this') {
				p.expect(':')!
			}
			p.parse_optional()!
		}
		.tuple_member {
			name_index := p.index + if p.at(p.index) == '...' { 1 } else { 0 }
			colon_index := name_index + if p.at(name_index + 1) == '?' { 2 } else { 1 }
			if un_is_jsdoc_identifier(p.at(name_index)) && p.at(colon_index) == ':' {
				p.index = colon_index + 1
			}
			p.parse_optional()!
		}
	}
}

fn (mut p UnJsdocParser) parse_list(opening string, closing string, member UnJsdocMember) ! {
	p.expect(opening)!
	if p.consume(closing) {
		return
	}
	for {
		p.parse_member(member)!
		if p.consume(closing) {
			return
		}
		p.expect(',')!
		if p.consume(closing) {
			return
		}
	}
}

fn un_is_jsdoc_numeric_token(token string) bool {
	if token == '' {
		return false
	}
	runes := token.runes()
	if !(un_is_digit_rune(runes[0]) || (runes[0] == `.` && runes.len > 1
		&& un_is_digit_rune(runes[1]))) {
		return false
	}
	if !token.ends_with('n') {
		return true
	}
	lower := token.to_lower()
	return lower.starts_with('0b') || lower.starts_with('0o') || lower.starts_with('0x')
		|| (!lower.contains('.') && !lower.contains('e'))
}

fn (mut p UnJsdocParser) parse_record() !UnJsdocType {
	p.expect('{')!
	if p.consume('}') {
		return un_jsdoc_unknown()
	}
	mut signatures := []UnJsdocType{}
	for !p.consume('}') {
		if p.at(p.index) == 'readonly' && p.has(p.index)
			&& !(p.has(p.index + 1) && p.at(p.index + 1) in [':', '?', '(', ',', ';', '}']) {
			p.index++
		}
		if p.at(p.index) == '(' {
			p.parse_list('(', ')', .arrow_parameter)!
			p.expect(':')!
			signatures << UnJsdocType{
				kind:     'function'
				elements: [p.parse_union()!]
			}
		} else if p.consume('[') {
			key := p.at(p.index)
			p.index++
			if !un_is_jsdoc_identifier(key) {
				return error('Unsupported JSDoc index signature')
			}
			p.expect(':')!
			p.parse_union()!
			p.expect(']')!
			p.expect(':')!
			p.parse_union()!
		} else {
			key := p.at(p.index)
			p.index++
			if !un_is_jsdoc_identifier(key) && !(key.starts_with('"') || key.starts_with("'"))
				&& !un_is_jsdoc_numeric_token(key) {
				return error('Unsupported JSDoc property')
			}
			p.consume('?')
			if p.at(p.index) == '(' {
				p.parse_list('(', ')', .arrow_parameter)!
			}
			if p.consume(':') {
				p.parse_union()!
			}
		}
		if !p.consume(',') && !p.consume(';') && p.at(p.index) != '}' && p.index !in p.line_breaks {
			return error('Unsupported JSDoc property')
		}
	}
	if signatures.len == 0 {
		return UnJsdocType{
			kind: 'non-primitive'
		}
	}
	return if signatures.len == 1 {
		signatures[0]
	} else {
		UnJsdocType{
			kind:     'intersection'
			elements: signatures
		}
	}
}

fn (mut p UnJsdocParser) parse_primary() !UnJsdocType {
	token := p.at(p.index)
	if token == '(' && p.has(p.index) {
		if close := p.paren_closes[p.index] {
			if p.at(close + 1) == '=>' {
				p.parse_list('(', ')', .arrow_parameter)!
				p.expect('=>')!
				return UnJsdocType{
					kind:     'function'
					elements: [p.parse_union()!]
				}
			}
		}
		p.index++
		typ := p.parse_optional()!
		p.expect(')')!
		return typ
	}
	if token == '[' {
		p.parse_list('[', ']', .tuple_member)!
		return un_jsdoc_name('Array')
	}
	if token == '{' {
		return p.parse_record()!
	}
	if token == 'function' && p.at(p.index + 1) == '(' {
		p.index++
		p.parse_list('(', ')', .function_parameter)!
		return UnJsdocType{
			kind:     'function'
			elements: [if p.consume(':') { p.parse_union()! } else { un_jsdoc_unknown() }]
		}
	}
	if token == '*' {
		p.index++
		return un_jsdoc_unknown()
	}
	if token.starts_with('"') || token.starts_with("'") {
		p.index++
		return un_jsdoc_name('string')
	}
	runes := token.runes()
	if token == '-' || (runes.len > 0 && (un_is_digit_rune(runes[0]) || (runes[0] == `.`
		&& runes.len > 1 && un_is_digit_rune(runes[1])))) {
		p.consume('-')
		literal := p.at(p.index)
		p.index++
		if !un_is_jsdoc_numeric_token(literal) {
			return error('Unsupported JSDoc literal')
		}
		return un_jsdoc_name(if literal.ends_with('n') { 'bigint' } else { 'number' })
	}
	return p.parse_named_type()!
}

fn (mut p UnJsdocParser) parse_named_type() !UnJsdocType {
	token := p.at(p.index)
	if !un_is_jsdoc_identifier(token) || token in un_jsdoc_unsupported_names {
		return error('Unsupported JSDoc type')
	}
	mut name := token
	p.index++
	for p.consume('.') {
		if p.at(p.index) == '<' {
			break
		}
		if !un_is_jsdoc_identifier(p.at(p.index)) {
			return error('Unsupported JSDoc type name')
		}
		name += '.${p.at(p.index)}'
		p.index++
	}
	if p.at(p.index) == '<' {
		if p.at(p.index + 1) == '>' || name in un_jsdoc_primitive_names {
			return error('Unsupported JSDoc generic')
		}
		p.parse_list('<', '>', .union_)!
		if name == 'Object' {
			return UnJsdocType{
				kind: 'non-primitive'
			}
		}
	}
	return un_jsdoc_primitive(name) or { un_jsdoc_name(name) }
}

// un_parse_jsdoc_type ports parseJSDocumentType: the facts the rules need of a type;
// unsupported or malformed syntax is 'unknown'.
fn un_parse_jsdoc_type(text []rune) UnJsdocType {
	trimmed := js_trim(text.string())
	if primitive := un_jsdoc_primitive(trimmed) {
		return primitive
	}
	if un_is_jsdoc_identifier(trimmed) {
		return if trimmed in un_jsdoc_unsupported_names {
			un_jsdoc_unknown()
		} else {
			un_jsdoc_name(trimmed)
		}
	}
	tokens, line_breaks := un_jsdoc_tokens(text) or { return un_jsdoc_unknown() }
	mut paren_closes := map[int]int{}
	mut openings := []int{}
	for index, token in tokens {
		if token in ['(', '[', '{', '<'] {
			openings << index
		} else if token in [')', ']', '}', '>'] {
			if openings.len == 0 {
				return un_jsdoc_unknown()
			}
			opening := openings.pop()
			expected := match tokens[opening] {
				'(' { ')' }
				'[' { ']' }
				'{' { '}' }
				else { '>' }
			}
			if expected != token {
				return un_jsdoc_unknown()
			}
			if tokens[opening] == '(' {
				paren_closes[opening] = index
			}
		}
	}
	if openings.len > 0 {
		return un_jsdoc_unknown()
	}
	mut p := UnJsdocParser{
		tokens:       tokens
		line_breaks:  line_breaks
		paren_closes: paren_closes
	}
	typ := p.parse_optional() or { return un_jsdoc_unknown() }
	return if p.index == tokens.len { typ } else { un_jsdoc_unknown() }
}

// un_jsdoc_line_end ports getLineEndIndex: the next `\n` from i, or the end.
fn un_jsdoc_line_end(text []rune, i int) int {
	for j in i .. text.len {
		if text[j] == `\n` {
			return j
		}
	}
	return text.len
}

fn un_is_horizontal_space(r rune) bool {
	return r != `\n` && is_js_space(r)
}

// un_jsdoc_skip_template_whitespace ports skipJSDocumentTemplateWhitespace: white space, and line
// breaks with the `*` that starts the next line.
fn un_jsdoc_skip_template_whitespace(text []rune, from int, end int) int {
	mut start := from
	for start < end {
		for start < end && un_is_horizontal_space(text[start]) {
			start++
		}
		if start >= text.len || text[start] != `\n` {
			return start
		}
		start++
		for start < end && un_is_horizontal_space(text[start]) {
			start++
		}
		if start < text.len && text[start] == `*` {
			start++
		}
	}
	return start
}

// un_jsdoc_delimited_end ports getJSDocumentDelimitedEnd: the index after the bracket that closes
// the one at `start` (skipping quoted text), or -1.
fn un_jsdoc_delimited_end(text []rune, start int, end int, opening rune) int {
	closing := match opening {
		`{` { `}` }
		`[` { `]` }
		else { `)` }
	}
	mut depth := 0
	mut quote := rune(0)
	mut index := start
	for index < end {
		character := text[index]
		if quote != 0 {
			if character == `\\` {
				index += 2
				continue
			}
			if character == quote {
				quote = 0
			}
			index++
			continue
		}
		if character in [`"`, `'`, `\``] {
			quote = character
			index++
			continue
		}
		if character == opening {
			depth++
		} else if character == closing {
			depth--
			if depth == 0 {
				return index + 1
			}
		}
		index++
	}
	return -1
}

// UnJsdocTagHead is a tag getJSDocumentTag finds at the start of a line.
struct UnJsdocTagHead {
	name          string
	content_start int
	line_start    int
}

// un_jsdoc_tag ports getJSDocumentTag on the line [start, end):
// /^\s*(?:\*\s*)?(?<tag>@[\d\p{Letter}][\d\p{Letter}\-]*!?)(?=\s|\{|$)/v.
fn un_jsdoc_tag(text []rune, start int, end int) ?UnJsdocTagHead {
	is_space := fn (r rune) bool {
		return is_js_space(r) || r in [0x2028, 0x2029]
	}
	is_letter_or_digit := fn (r rune) bool {
		return un_is_digit_rune(r) || utf8.is_letter(r)
	}
	// The optional `*` makes the regular expression try both ways: with it first.
	mut candidates := []int{}
	mut i := start
	for i < end && is_space(text[i]) {
		i++
	}
	if i < end && text[i] == `*` {
		mut j := i + 1
		for j < end && is_space(text[j]) {
			j++
		}
		candidates << j
	}
	candidates << i
	for at in candidates {
		if at >= end || text[at] != `@` || at + 1 >= end || !is_letter_or_digit(text[at + 1]) {
			continue
		}
		mut j := at + 2
		for j < end && (is_letter_or_digit(text[j]) || text[j] == `-`) {
			j++
		}
		mut tag_end := j
		if j < end && text[j] == `!` {
			tag_end = j + 1
		}
		// The lookahead; without it the `!` (and the `-`s) can be given back.
		mut found := -1
		for k := tag_end; k > at + 1; k-- {
			if k == end || is_space(text[k]) || text[k] == `{` {
				found = k
				break
			}
			// Only a shorter tag made by giving back `!` or trailing letters can match: the
			// regular expression backtracks over every repetition.
		}
		if found < 0 {
			continue
		}
		mut name := text[at + 1..found].string().to_lower()
		if name.ends_with('!') {
			name = name[..name.len - 1]
		}
		return UnJsdocTagHead{
			name:          name
			content_start: found
			line_start:    start
		}
	}
	return none
}

// un_jsdoc_tags ports getJSDocumentTags: the tags at the start of the lines of a comment.
fn un_jsdoc_tags(text []rune) []UnJsdocTagHead {
	mut tags := []UnJsdocTagHead{}
	mut line_start := 0
	for line_start < text.len {
		line_end := un_jsdoc_line_end(text, line_start)
		if tag := un_jsdoc_tag(text, line_start, line_end) {
			tags << tag
		}
		line_start = line_end + 1
	}
	return tags
}

// un_jsdoc_tag_type ports parseTagType: the type in braces at `start`, and the index after it.
fn un_jsdoc_tag_type(text []rune, start int, end int) ?(UnJsdocType, int) {
	if start >= text.len || text[start] != `{` {
		return none
	}
	type_end := un_jsdoc_delimited_end(text, start, end, `{`)
	if type_end < 0 {
		return none
	}
	// `.replaceAll(/\r?\n[^\S\n]*\*?/gv, '\n')`
	inner := text[start + 1..type_end - 1]
	mut cleaned := []rune{}
	mut i := 0
	for i < inner.len {
		mut line_break := -1
		if inner[i] == `\n` {
			line_break = i + 1
		} else if inner[i] == `\r` && i + 1 < inner.len && inner[i + 1] == `\n` {
			line_break = i + 2
		}
		if line_break < 0 {
			cleaned << inner[i]
			i++
			continue
		}
		mut j := line_break
		for j < inner.len && un_is_horizontal_space(inner[j]) {
			j++
		}
		if j < inner.len && inner[j] == `*` {
			j++
		}
		cleaned << `\n`
		i = j
	}
	return un_parse_jsdoc_type(cleaned), type_end
}

// un_jsdoc_parse_tag ports parseTag (the range of the name aside); none where it gives
// undefined.
fn un_jsdoc_parse_tag(text []rune, tag UnJsdocTagHead, end int) ?UnJsdocTag {
	is_parameter := tag.name in ['param', 'arg', 'argument']
	if !is_parameter && tag.name != 'type' && tag.name !in ['return', 'returns'] {
		return none
	}
	mut start := un_jsdoc_skip_template_whitespace(text, tag.content_start, end)
	mut has_type := false
	mut typ := UnJsdocType{}
	if start < text.len && text[start] == `{` {
		parsed, parsed_end := un_jsdoc_tag_type(text, start, end) or {
			return UnJsdocTag{
				tag: tag.name
			}
		}
		has_type = true
		typ = parsed
		start = un_jsdoc_skip_template_whitespace(text, parsed_end, end)
	} else if !is_parameter {
		return UnJsdocTag{
			tag: tag.name
		}
	}
	mut optional := false
	mut name := ''
	if is_parameter {
		optional = start < text.len && text[start] == `[`
		name_end := if optional { un_jsdoc_delimited_end(text, start, end, `[`) } else { end }
		if name_end < 0 || (name_end < end && !is_js_space(text[name_end])) {
			return none
		}
		if optional {
			start++
		}
		// parameterNamePattern: /^[\p{ID_Start}$_][\p{ID_Continue}$\u{200C}\u{200D}]*/v
		if start >= name_end || !un_is_id_start_rune(text[start]) {
			return none
		}
		mut after_name := start + 1
		for after_name < name_end && un_is_id_part_rune(text[after_name]) {
			after_name++
		}
		name = text[start..after_name].string()
		next := un_jsdoc_skip_template_whitespace(text, after_name, name_end)
		if optional {
			if next >= text.len || text[next] !in [`]`, `=`] {
				return none
			}
		} else if after_name < end && !is_js_space(text[after_name]) {
			return none
		}
		if !has_type {
			type_start := un_jsdoc_skip_template_whitespace(text, if optional {
				name_end
			} else {
				after_name
			}, end)
			if parsed, _ := un_jsdoc_tag_type(text, type_start, end) {
				has_type = true
				typ = parsed
			}
		}
	}
	return UnJsdocTag{
		tag:      tag.name
		name:     name
		has_type: has_type
		typ:      typ
		optional: optional
	}
}

// un_has_jsdoc_comments ports hasJSDocumentComments: the file has a block comment that starts
// with `*`.
fn (c &Checker) un_has_jsdoc_comments(mut ctx UnCtx) bool {
	if ctx.jsdoc_state == 0 {
		ctx.jsdoc_state = if ctx.tokens.comments.any(it.kind == .block_comment
			&& c.src[it.start + 2..].starts_with('*')) {
			1
		} else {
			2
		}
	}
	return ctx.jsdoc_state == 1
}

// un_comment_tags ports getCommentTags: the parsed tags of a JSDoc comment (none when it has a
// typedef, a callback or an overload).
fn (c &Checker) un_comment_tags(mut ctx UnCtx, comment SourceToken) []UnJsdocTag {
	if tags := ctx.comment_tags[comment.start] {
		return tags
	}
	text := c.src[comment.start + 2..comment.end - 2].runes()
	heads := un_jsdoc_tags(text)
	mut parsed := []UnJsdocTag{}
	if !heads.any(it.name in ['typedef', 'callback', 'overload']) {
		for index, head in heads {
			end := if index + 1 < heads.len { heads[index + 1].line_start } else { text.len }
			if tag := un_jsdoc_parse_tag(text, head, end) {
				parsed << tag
			}
		}
	}
	ctx.comment_tags[comment.start] = parsed
	return parsed
}

// un_documentation_tags ports getDocumentationTags: the tags of the comment right before the
// first of the nodes that has one.
fn (c &Checker) un_documentation_tags(mut ctx UnCtx, nodes []int) []UnJsdocTag {
	for node in nodes {
		comments := ctx.tokens.comments_before(ctx.t.nodes[node].start)
		if comments.len > 0 {
			comment := comments.last()
			return if comment.kind == .block_comment && c.src[comment.start + 2..].starts_with('*') {
				c.un_comment_tags(mut ctx, comment)
			} else {
				[]UnJsdocTag{}
			}
		}
	}
	return []UnJsdocTag{}
}

// un_with_export ports withExport.
fn un_with_export(t &estree.EsTree, node int) []int {
	parent := t.nodes[node].parent
	if parent >= 0 && t.typ(parent) in [.export_named_declaration, .export_default_declaration] {
		return [node, parent]
	}
	return [node]
}

// un_function_owners ports getFunctionOwners: the function and what its documentation may be on.
fn un_function_owners(t &estree.EsTree, function int) []int {
	mut owners := [function]
	mut node := function
	for {
		parent := t.nodes[node].parent
		if parent < 0 || !un_is_ts_expression_wrapper(t, parent)
			|| (t.node(parent, .expression) or { -1 }) != node {
			break
		}
		node = parent
		owners << node
	}
	parent := t.nodes[node].parent
	if parent < 0 {
		return owners
	}
	typ := t.typ(parent)
	if typ == .variable_declarator && (t.node(parent, .init) or { -1 }) == node {
		declaration := t.nodes[parent].parent
		if (t.list(declaration, .declarations) or { []int{} }).len == 1 {
			owners << parent
			owners << un_with_export(t, declaration)
			return owners
		}
		owners << parent
		return owners
	}
	if typ == .assignment_expression && (t.string_of(parent, .operator) or { '' }) == '='
		&& (t.node(parent, .right) or { -1 }) == node
		&& t.typ(t.nodes[parent].parent) == .expression_statement {
		owners << parent
		owners << t.nodes[parent].parent
		return owners
	}
	if typ in [.property, .property_definition, .accessor_property, .method_definition]
		&& (t.node(parent, .value) or { -1 }) == node {
		owners << parent
		return owners
	}
	if typ in [.export_named_declaration, .export_default_declaration] {
		owners << parent
	}
	return owners
}

// un_jsdoc_annotation ports getAnnotation: the one tag that matches.
fn un_jsdoc_annotation(tags []UnJsdocTag, predicate fn (UnJsdocTag) bool) ?UnJsdocAnnotation {
	matches := tags.filter(predicate(it))
	if matches.len != 1 {
		return none
	}
	return UnJsdocAnnotation{
		has_type: matches[0].has_type
		typ:      matches[0].typ
		optional: matches[0].optional
	}
}

// un_jsdoc_parameter_annotation ports getParameterAnnotation: the inline or named tag of a
// simple parameter.
fn (mut c Checker) un_jsdoc_parameter_annotation(mut ctx UnCtx, node int) ?UnJsdocAnnotation {
	t := ctx.t
	if !c.un_has_jsdoc_comments(mut ctx) {
		return none
	}
	parent := t.nodes[node].parent
	mut parameter := if parent >= 0 && t.typ(parent) == .assignment_pattern
		&& (t.node(parent, .left) or { -1 }) == node {
		parent
	} else {
		node
	}
	if t.nodes[parameter].parent >= 0 && t.typ(t.nodes[parameter].parent) == .ts_parameter_property {
		parameter = t.nodes[parameter].parent
	}
	function := t.nodes[parameter].parent
	if function < 0 || t.typ(function) !in [.function_declaration, .function_expression,
		.arrow_function_expression] || parameter !in (t.list(function, .params) or { []int{} }) {
		return none
	}
	name := t.string_of(node, .name) or { '' }
	inline := un_jsdoc_annotation(c.un_documentation_tags(mut ctx, [node, parameter]), fn (tag UnJsdocTag) bool {
		return tag.tag == 'type'
	})
	named := un_jsdoc_annotation(c.un_documentation_tags(mut ctx, un_function_owners(t, function)),
		fn [name] (tag UnJsdocTag) bool {
		return tag.tag in ['param', 'arg', 'argument'] && tag.name == name
	})
	mut annotation := UnJsdocAnnotation{}
	if i := inline {
		if i.has_type {
			annotation = i
		} else {
			annotation = named?
		}
	} else {
		annotation = named?
	}
	mut optional := t.flag(node, .optional) or { false }
	for a in [inline, named] {
		if b := a {
			if b.optional || (b.has_type && b.typ.kind == 'optional') {
				optional = true
			}
		}
	}
	typ := if annotation.has_type && annotation.typ.kind == 'optional' {
		annotation.typ.elements[0]
	} else {
		annotation.typ
	}
	return UnJsdocAnnotation{
		has_type: annotation.has_type
		typ:      typ
		optional: optional
	}
}

// un_has_native_type_assertion ports hasNativeTypeAssertion: `as` or `<T>` among the wrappers.
fn un_has_native_type_assertion(t &estree.EsTree, from int) bool {
	mut node := from
	for un_is_ts_expression_wrapper(t, node) {
		if t.typ(node) in [.ts_as_expression, .ts_type_assertion] {
			return true
		}
		node = t.node(node, .expression) or { return false }
	}
	return false
}

// un_jsdoc_type_annotation ports getJSDocumentTypeAnnotation: the documented type of a binding or
// property, through the declaration of an identifier.
fn (mut c Checker) un_jsdoc_type_annotation(mut ctx UnCtx, node int) ?UnJsdocAnnotation {
	t := ctx.t
	if node < 0 || !c.un_has_jsdoc_comments(mut ctx) || t.node(node, .type_annotation) != none {
		return none
	}
	parent := t.nodes[node].parent
	mut owners := []int{}
	if t.typ(node) in [.property, .property_definition, .accessor_property] {
		if un_has_native_type_assertion(t, t.node(node, .value) or { -1 }) {
			return none
		}
		owners = [node]
	} else if t.typ(node) == .identifier {
		if parent >= 0 && t.typ(parent) == .variable_declarator
			&& (t.node(parent, .id) or { -1 }) == node {
			if un_has_native_type_assertion(t, t.node(parent, .init) or { -1 }) {
				return none
			}
			declaration := t.nodes[parent].parent
			owners = if (t.list(declaration, .declarations) or { []int{} }).len == 1 {
				mut list := [node, parent]
				list << un_with_export(t, declaration)
				list
			} else {
				[node, parent]
			}
		} else {
			if annotation := c.un_jsdoc_parameter_annotation(mut ctx, node) {
				if annotation.has_type {
					return annotation
				}
			}
			v := c.un_find_variable(ctx, node)
			def := c.un_only_definition(ctx, v) or { return none }
			name := c.un_es_of(ctx, def.name)
			if name < 0 || name == node {
				return none
			}
			return c.un_jsdoc_type_annotation(mut ctx, name)
		}
	} else {
		return none
	}
	annotation := un_jsdoc_annotation(c.un_documentation_tags(mut ctx, owners), fn (tag UnJsdocTag) bool {
		return tag.tag == 'type'
	})?
	return if annotation.has_type { annotation } else { none }
}

// un_jsdoc_return_type ports getJSDocumentReturnType: the documented return type of a function.
fn (mut c Checker) un_jsdoc_return_type(mut ctx UnCtx, function int) ?UnJsdocAnnotation {
	t := ctx.t
	if function < 0 || !c.un_has_jsdoc_comments(mut ctx) || t.node(function, .return_type) != none {
		return none
	}
	owners := un_function_owners(t, function)
	for owner in owners {
		if t.typ(owner) == .variable_declarator {
			if id := t.node(owner, .id) {
				if t.node(id, .type_annotation) != none {
					return none
				}
			}
		} else if t.typ(owner) in [.property, .property_definition, .accessor_property]
			&& t.node(owner, .type_annotation) != none {
			return none
		}
	}
	parent := t.nodes[function].parent
	is_getter := parent >= 0 && (t.string_of(parent, .kind) or { '' }) == 'get'
		&& (t.node(parent, .value) or { -1 }) == function
	annotation := un_jsdoc_annotation(c.un_documentation_tags(mut ctx, owners), fn [is_getter] (tag UnJsdocTag) bool {
		return tag.tag in ['return', 'returns'] || (tag.tag == 'type' && is_getter)
	})?
	return if annotation.has_type { annotation } else { none }
}

// ---- type-helpers.js and types.js

// UnType is what getType tells of a value: it is the target, it is not, it is null or undefined,
// or nothing is known.
enum UnType {
	target
	non_target
	nullish
	unknown
}

// UnTypeKind names the type checkers the rules use: they give the callbacks of their options
// (isTargetNode, isNonTargetNode, isTargetTypeAnnotation, isTargetType, getStaticType).
enum UnTypeKind {
	array              // isArray, isKnownNonArray (is-array.js)
	indexed_collection // isIndexedCollection, isKnownNonIndexedCollection
	bigint_typed_array // isKnownBigIntTypedArray
	bigint             // is-bigint.js
	string_            // is-string.js
	date               // createBuiltinTypeCheckers({name: 'Date'}) of is-string.js and is-number.js
	regexp             // is-reg-exp.js
	number_            // isNumberTarget, isKnownNonNumber (is-number.js)
	sized_collection   // isSizedCollection (is-number.js)
}

// UnTypeOptions are the options of createTypeCheckers (targetTypeImports and
// targetTypeNamespaceImports aside: no checker of the ported rules sets them).
struct UnTypeOptions {
	kind                              UnTypeKind
	check_class_heritage              bool = true
	check_class_syntax                bool
	prefer_type_reference_definitions bool
	treat_mixed_union_as_target       bool
	treat_mixed_union_as_non_target   bool
	allow_nullish_in_mixed_union      bool
	target_type_names                 []string
	non_target_type_names             []string
	type_reference_aliases            map[string]string
	target_call_names                 []string
	target_constructor_names          []string
}

const un_known_non_indexed_collection_names = ['Map', 'ReadonlyMap', 'WeakMap', 'Set', 'ReadonlySet',
	'WeakSet', 'URLSearchParams', 'Headers', 'FormData', 'CanvasRenderingContext2D',
	'OffscreenCanvasRenderingContext2D']

// un_type_options are the options of each checker.
fn un_type_options(kind UnTypeKind) UnTypeOptions {
	return match kind {
		.array {
			UnTypeOptions{
				kind:                              kind
				check_class_heritage:              false
				prefer_type_reference_definitions: true
				target_type_names:                 ['Array', 'ReadonlyArray']
				non_target_type_names:             [...un_typed_arrays, ...un_known_non_indexed_collection_names]
				target_call_names:                 ['Array']
				target_constructor_names:          ['Array']
			}
		}
		.indexed_collection {
			UnTypeOptions{
				kind:                              kind
				check_class_heritage:              false
				prefer_type_reference_definitions: true
				target_type_names:                 ['Array', 'ReadonlyArray', ...un_typed_arrays]
				non_target_type_names:             un_known_non_indexed_collection_names
				target_call_names:                 ['Array']
				target_constructor_names:          ['Array', ...un_typed_arrays]
			}
		}
		.bigint_typed_array {
			UnTypeOptions{
				kind:                        kind
				treat_mixed_union_as_target: true
				target_type_names:           ['BigInt64Array', 'BigUint64Array']
				target_constructor_names:    ['BigInt64Array', 'BigUint64Array']
			}
		}
		.bigint {
			UnTypeOptions{
				kind:              kind
				target_type_names: ['bigint']
				target_call_names: ['BigInt']
			}
		}
		.string_ {
			UnTypeOptions{
				kind:              kind
				target_type_names: ['string']
				target_call_names: ['String', 'Date', 'encodeURI', 'encodeURIComponent', 'decodeURI',
					'decodeURIComponent', 'atob', 'btoa']
			}
		}
		.date {
			UnTypeOptions{
				kind:                     kind
				check_class_heritage:     false
				target_type_names:        ['Date']
				target_constructor_names: ['Date']
			}
		}
		.regexp {
			UnTypeOptions{
				kind:                     kind
				target_type_names:        ['RegExp']
				target_call_names:        ['RegExp']
				target_constructor_names: ['RegExp']
			}
		}
		.number_ {
			UnTypeOptions{
				kind:              kind
				target_type_names: ['number']
				target_call_names: ['Number']
			}
		}
		.sized_collection {
			UnTypeOptions{
				kind:                     kind
				check_class_heritage:     false
				target_type_names:        ['Map', 'Set', 'ReadonlyMap', 'ReadonlySet']
				target_constructor_names: ['Map', 'Set']
			}
		}
	}
}

fn un_normalize_type(typ UnType) UnType {
	return if typ == .nullish { .non_target } else { typ }
}

// un_combine_union ports combineUnionTypes.
fn un_combine_union(from []UnType, o UnTypeOptions) UnType {
	types := if o.allow_nullish_in_mixed_union {
		from.filter(it != .nullish)
	} else {
		from.map(un_normalize_type(it))
	}
	if types.len == 0 {
		return .non_target
	}
	if (o.treat_mixed_union_as_target && types.contains(.target))
		|| (!o.treat_mixed_union_as_target && types.all(it == .target)) {
		return .target
	}
	if (o.treat_mixed_union_as_non_target && types.contains(.non_target))
		|| (!o.treat_mixed_union_as_non_target && types.all(it == .non_target)) {
		return .non_target
	}
	return .unknown
}

// un_combine_intersection ports combineIntersectionTypes: an unknown member may be `any`.
fn un_combine_intersection(from []UnType) UnType {
	types := from.map(un_normalize_type(it))
	if types.contains(.unknown) {
		return .unknown
	}
	return if types.contains(.target) { .target } else { .non_target }
}

// un_scope_of ports sourceCode.getScope(node) for an ESTree node (through its closest ancestor
// with a tree-sitter node).
fn (mut c Checker) un_scope_of(ctx &UnCtx, from int) int {
	t := ctx.t
	tree := c.scope_tree(ctx.root)
	mut node := from
	for node >= 0 {
		if ts := t.ts_node(node) {
			return tree.get_scope(ts)
		}
		node = t.nodes[node].parent
	}
	return 0
}

// UnTypeDefinition is a definition getTypeReferenceDefinition finds, with its variable and scope.
struct UnTypeDefinition {
	def      ScopeDefinition
	variable int
	scope    int
}

// un_type_reference_definition ports getTypeReferenceDefinition: the nearest class, import, enum,
// type alias, interface or type parameter of the name, from `scope` up.
fn (mut c Checker) un_type_reference_definition(ctx &UnCtx, name string, from_scope int) ?UnTypeDefinition {
	tree := c.scope_tree(ctx.root)
	mut scope := from_scope
	for scope >= 0 {
		if v := tree.set_get(scope, name) {
			for def in tree.variables[v].defs {
				if def.kind in [.class_name, .import_binding, .ts_enum_name, .type_definition] {
					return UnTypeDefinition{def, v, scope}
				}
			}
		}
		scope = tree.scopes[scope].upper
	}
	return none
}

// un_type_name ports getTypeName: `Foo` or `Foo.Bar` of a type name.
fn un_type_name(t &estree.EsTree, node int) ?string {
	if node < 0 {
		return none
	}
	if t.typ(node) == .identifier {
		return t.string_of(node, .name)
	}
	if t.typ(node) == .ts_qualified_name {
		left := un_type_name(t, t.node(node, .left) or { return none })?
		right := t.node(node, .right) or { return none }
		return '${left}.${t.string_of(right, .name) or { '' }}'
	}
	return none
}

// un_known_type_reference_type ports getKnownTypeReferenceType.
fn un_known_type_reference_type(name string, o UnTypeOptions) UnType {
	alias := o.type_reference_aliases[name] or { '' }
	if name in o.target_type_names || (alias != '' && alias in o.target_type_names) {
		return .target
	}
	return if name in o.non_target_type_names { .non_target } else { .unknown }
}

// un_has_jsdoc_type_reference ports hasJSDocumentTypeReference: an explicit JSDoc annotation in
// the node, through aliases and larger expressions.
fn (mut c Checker) un_has_jsdoc_type_reference(mut ctx UnCtx, from int, mut visited map[int]bool) bool {
	t := ctx.t
	if !c.un_has_jsdoc_comments(mut ctx) {
		return false
	}
	node := un_unwrap_ts_expression(t, from)
	if node < 0 {
		return false
	}
	if t.typ(node) == .identifier {
		if _ := c.un_jsdoc_type_annotation(mut ctx, node) {
			return true
		}
		v := c.un_find_variable(ctx, node)
		def := c.un_only_definition(ctx, v) or { return false }
		init := c.un_es_of(ctx, def.init)
		if def.kind != .variable || !un_def_names_itself(def) || init < 0 || v in visited {
			return false
		}
		visited[v] = true
		return c.un_has_jsdoc_type_reference(mut ctx, init, mut visited)
	}
	if t.typ(node) in [.function_declaration, .function_expression, .arrow_function_expression,
		.class_declaration, .class_expression] {
		return false
	}
	for child in un_evaluated_children(t, node) {
		if c.un_has_jsdoc_type_reference(mut ctx, child, mut visited) {
			return true
		}
	}
	return false
}

// un_jsdoc_type_members ports getJSDocumentTypeMembers: the members of a union or intersection,
// flattened through groups of the same kind.
fn un_jsdoc_type_members(typ UnJsdocType) []UnJsdocType {
	mut out := []UnJsdocType{}
	for element in typ.elements {
		if element.kind == typ.kind {
			out << un_jsdoc_type_members(element)
		} else {
			out << element
		}
	}
	return out
}

// un_jsdoc_type_node_type ports getJSDocumentTypeNodeType.
fn un_jsdoc_type_node_type(typ UnJsdocType, has bool, o UnTypeOptions) UnType {
	if !has {
		return .unknown
	}
	match typ.kind {
		'nullable', 'optional' {
			return un_combine_union([un_jsdoc_type_node_type(typ.elements[0], true, o), .nullish],
				o)
		}
		'union' {
			return un_combine_union(un_jsdoc_type_members(typ).map(un_jsdoc_type_node_type(it,
				true, o)), o)
		}
		'intersection' {
			return un_combine_intersection(typ.elements.map(un_jsdoc_type_node_type(it, true, o)))
		}
		'nullish' {
			return .nullish
		}
		else {
			if typ.kind == 'name' {
				known := un_known_type_reference_type(typ.name, o)
				if known != .unknown {
					return known
				}
				if typ.name in ['boolean', 'string', 'number', 'bigint', 'symbol', 'void'] {
					return .non_target
				}
			}
			return if typ.kind in ['non-primitive', 'function'] { .non_target } else { .unknown }
		}
	}
}

// un_jsdoc_type ports getJSDocumentType: an annotation classified like a native one.
fn un_jsdoc_type(annotation UnJsdocAnnotation, o UnTypeOptions) UnType {
	typ := un_jsdoc_type_node_type(annotation.typ, annotation.has_type, o)
	return if annotation.optional { un_combine_union([typ, .nullish], o) } else { typ }
}

// un_jsdoc_callable_return_type ports getJSDocumentCallableReturnType: the return type of a
// documented function type (a union for several), none when it is not a function.
fn un_jsdoc_callable_return_type(typ UnJsdocType) ?UnJsdocType {
	if typ.kind == 'function' {
		return typ.elements[0]
	}
	if typ.kind !in ['union', 'intersection'] {
		return none
	}
	members := if typ.kind == 'intersection' {
		un_jsdoc_type_members(typ).filter(it.kind != 'non-primitive')
	} else {
		typ.elements
	}
	mut return_types := []UnJsdocType{}
	for member in members {
		return_types << un_jsdoc_callable_return_type(member)?
	}
	if return_types.len == 0 {
		return none
	}
	return UnJsdocType{
		kind:     'union'
		elements: return_types
	}
}

// un_import_binding_type ports getImportBindingType without targetTypeImports.
fn un_import_binding_type(t &estree.EsTree, node int, o UnTypeOptions) UnType {
	if node < 0 {
		return .unknown
	}
	local := t.node(node, .local) or { return .unknown }
	local_name := t.string_of(local, .name) or { '' }
	if t.typ(node) == .import_default_specifier {
		return if un_known_type_reference_type(local_name, o) == .unknown {
			.unknown
		} else {
			.non_target
		}
	}
	imported := t.node(node, .imported) or { return .unknown }
	imported_name := t.string_of(imported, .name) or {
		un_static_string_value(t, imported) or { return .unknown }
	}
	if imported_name == '' {
		return .unknown
	}
	// getKnownImportedType
	if un_known_type_reference_type(imported_name, o) != .unknown
		|| un_known_type_reference_type(local_name, o) != .unknown {
		return .non_target
	}
	return .unknown
}

// un_type_reference_type ports getTypeReferenceType for a type name node.
fn (mut c Checker) un_type_reference_type(mut ctx UnCtx, type_name int, scope int, o UnTypeOptions, mut visited map[string]bool) UnType {
	t := ctx.t
	name := un_type_name(t, type_name) or { return .unknown }
	// getNamespaceImportBindingType needs targetTypeNamespaceImports: unknown.
	if !o.prefer_type_reference_definitions {
		known := un_known_type_reference_type(name, o)
		if known != .unknown {
			return known
		}
	}
	found := c.un_type_reference_definition(ctx, name, scope) or {
		return un_known_type_reference_type(name, o)
	}
	key := '${found.variable}:${node_key(found.def.name)}'
	if key in visited {
		return .unknown
	}
	visited[key] = true
	def := found.def
	definition_node := c.un_es_of(ctx, def.node)
	mut typ := UnType.unknown
	if def.kind == .import_binding {
		typ = un_import_binding_type(t, definition_node, o)
	}
	if typ == .unknown && definition_node >= 0 {
		if def.kind == .type_definition && t.typ(definition_node) == .ts_type_alias_declaration {
			typ = c.un_type_annotation_type(mut ctx, t.node(definition_node, .type_annotation) or {
				-1
			}, found.scope, o, mut visited)
		} else if def.kind == .type_definition && t.typ(definition_node) == .ts_type_parameter {
			typ = c.un_type_annotation_type(mut ctx, t.node(definition_node, .constraint) or { -1 },
				found.scope, o, mut visited)
		} else if def.kind == .type_definition
			&& t.typ(definition_node) == .ts_interface_declaration {
			// getInterfaceType
			heritage := t.list(definition_node, .extends_) or { []int{} }
			typ = if heritage.len == 0 {
				.non_target
			} else {
				un_combine_intersection(heritage.map(c.un_type_reference_type(mut ctx,
					t.node(it, .expression) or { -1 }, found.scope, o, mut visited)))
			}
		} else if def.kind == .class_name {
			typ = c.un_class_heritage_type(mut ctx, definition_node, found.scope, o, mut visited)
		}
	}
	visited.delete(key)
	return typ
}

// un_class_heritage_type ports getClassHeritageType.
fn (mut c Checker) un_class_heritage_type(mut ctx UnCtx, class int, scope int, o UnTypeOptions, mut visited map[string]bool) UnType {
	t := ctx.t
	super_class := t.node(class, .super_class) or { return .non_target }
	if !o.check_class_heritage {
		return .non_target
	}
	if t.typ(super_class) != .identifier {
		return .unknown
	}
	return c.un_class_reference_type(mut ctx, super_class, scope, o, mut visited)
}

// un_class_type ports getClassType.
fn (mut c Checker) un_class_type(mut ctx UnCtx, class int, scope int, o UnTypeOptions, mut visited map[string]bool) UnType {
	super_class := ctx.t.node(class, .super_class) or { return .non_target }
	if !o.check_class_heritage {
		return .non_target
	}
	return c.un_class_reference_type(mut ctx, super_class, scope, o, mut visited)
}

// un_class_reference_type ports getClassReferenceTypeFromScope.
fn (mut c Checker) un_class_reference_type(mut ctx UnCtx, node int, scope int, o UnTypeOptions, mut visited map[string]bool) UnType {
	t := ctx.t
	if node < 0 {
		return .unknown
	}
	if t.typ(node) == .identifier {
		name := t.string_of(node, .name) or { '' }
		if !o.check_class_heritage {
			return un_known_type_reference_type(name, o)
		}
		tree := c.scope_tree(ctx.root)
		v := tree.find_variable(scope, name, -1)
		if v < 0 || tree.variables[v].defs.len == 0 {
			return un_known_type_reference_type(name, o)
		}
		def := tree.variables[v].defs[0]
		key := '${v}:${node_key(def.name)}'
		if key in visited {
			return .unknown
		}
		visited[key] = true
		mut typ := UnType.unknown
		variable_scope := tree.variables[v].scope
		init := c.un_es_of(ctx, def.init)
		if def.kind == .variable && def.parent_kind == 'const' && un_def_names_itself(def)
			&& init >= 0 {
			typ = c.un_class_reference_type(mut ctx, init, variable_scope, o, mut visited)
		} else if def.kind == .class_name {
			class := c.un_es_of(ctx, def.node)
			if class >= 0 {
				typ = c.un_class_type(mut ctx, class, variable_scope, o, mut visited)
			}
		}
		visited.delete(key)
		return typ
	}
	if t.typ(node) in [.class_declaration, .class_expression] {
		return c.un_class_type(mut ctx, node, scope, o, mut visited)
	}
	return .unknown
}

// un_is_target_type_annotation is the isTargetTypeAnnotation of the checker.
fn un_is_target_type_annotation(t &estree.EsTree, node int, o UnTypeOptions) bool {
	if node < 0 {
		return false
	}
	return match o.kind {
		.array, .indexed_collection {
			t.typ(node) in [.ts_array_type, .ts_tuple_type]
		}
		.bigint {
			un_is_bigint_type_annotation(t, node)
		}
		.string_ {
			un_is_string_type_annotation(t, node)
		}
		.number_ {
			un_is_number_type_annotation(t, node)
		}
		else {
			false
		}
	}
}

// un_is_number_type_annotation ports isNumberTypeAnnotation of is-number.js: `number` or a numeric
// literal type.
fn un_is_number_type_annotation(t &estree.EsTree, node int) bool {
	if node < 0 {
		return false
	}
	if t.typ(node) == .ts_number_keyword {
		return true
	}
	if t.typ(node) == .ts_literal_type {
		literal := t.node(node, .literal) or { return false }
		return t.typ(literal) == .literal && t.get(literal, .value) is f64
	}
	return false
}

// un_is_bigint_type_annotation ports isBigIntTypeAnnotation: `bigint` or a BigInt literal type.
fn un_is_bigint_type_annotation(t &estree.EsTree, node int) bool {
	if node < 0 {
		return false
	}
	if t.typ(node) == .ts_big_int_keyword {
		return true
	}
	if t.typ(node) == .ts_literal_type {
		literal := t.node(node, .literal) or { return false }
		return t.typ(literal) == .literal && t.string_of(literal, .bigint) != none
	}
	return false
}

// un_is_string_type_annotation ports isStringTypeAnnotation: `string` or a string literal type.
fn un_is_string_type_annotation(t &estree.EsTree, node int) bool {
	if node < 0 {
		return false
	}
	if t.typ(node) == .ts_string_keyword {
		return true
	}
	if t.typ(node) == .ts_literal_type {
		return un_static_string_value(t, t.node(node, .literal) or { return false }) != none
	}
	return false
}

// un_type_annotation_type ports getTypeAnnotationType.
fn (mut c Checker) un_type_annotation_type(mut ctx UnCtx, node int, scope int, o UnTypeOptions, mut visited map[string]bool) UnType {
	t := ctx.t
	if node < 0 {
		return .unknown
	}
	match t.typ(node) {
		.ts_type_annotation {
			return c.un_type_annotation_type(mut ctx, t.node(node, .type_annotation) or { -1 },
				scope, o, mut visited)
		}
		.ts_type_operator {
			return if (t.string_of(node, .operator) or { '' }) == 'readonly' {
				c.un_type_annotation_type(mut ctx, t.node(node, .type_annotation) or { -1 },
					scope, o, mut visited)
			} else {
				.unknown
			}
		}
		.ts_type_reference {
			return c.un_type_reference_type(mut ctx, t.node(node, .type_name) or { -1 }, scope,
				o, mut visited)
		}
		.ts_union_type {
			types := t.list(node, .types) or { []int{} }
			return un_combine_union(types.map(c.un_type_annotation_type(mut ctx, it, scope, o, mut
				visited)), o)
		}
		.ts_intersection_type {
			types := t.list(node, .types) or { []int{} }
			return un_combine_intersection(types.map(c.un_type_annotation_type(mut ctx, it,
				scope, o, mut visited)))
		}
		else {
			if un_is_target_type_annotation(t, node, o) {
				return .target
			}
			if t.typ(node) in [.ts_null_keyword, .ts_undefined_keyword] {
				return .nullish
			}
			return if t.typ(node) in [.ts_big_int_keyword, .ts_boolean_keyword, .ts_never_keyword,
				.ts_number_keyword, .ts_string_keyword, .ts_symbol_keyword, .ts_void_keyword,
				.ts_array_type, .ts_literal_type, .ts_tuple_type, .ts_type_literal,
				.ts_function_type, .ts_constructor_type] {
				.non_target
			} else {
				.unknown
			}
		}
	}
}

// un_ts_type is parserServices.getTypeAtLocation(node) through withTypeInformation: none when the
// parser has no program (LanguageOptions.type_information) or tsgo has no type for it.
fn (mut c Checker) un_ts_type(ctx &UnCtx, node int) ?TypeResponse {
	if !c.scope_setup.type_information {
		return none
	}
	ts := ctx.t.ts_node(node) or { return none }
	mut stats := Stats{}
	c.resolve_node_types([ts], ctx.abs_path, mut stats) or { return none }
	return c.node_type(ts)
}

// un_ts_type_symbol_name ports getTypeSymbol(type).getName(): its symbol, or else its alias
// symbol.
fn (mut c Checker) un_ts_type_symbol_name(typ TypeResponse) ?string {
	if typ.symbol != 0 {
		symbol := c.symbol_of(typ) or { return none }
		if symbol.id != 0 || symbol.name != '' {
			return symbol.name
		}
	}
	if typ.alias_symbol != 0 {
		symbol := c.alias_symbol_of(typ) or { return none }
		return symbol.name
	}
	return none
}

// un_ts_base_types ports getBaseTypes(type, checker): the base types of a class or interface,
// none for the other types (TypeScript throws, which unicorn catches).
fn (mut c Checker) un_ts_base_types(typ TypeResponse) []TypeResponse {
	if typ.symbol == 0 || typ.is_tuple_type {
		return []
	}
	symbol := c.symbol_of(typ) or { return [] }
	if symbol.flags & (symbol_flag_class | symbol_flag_interface) == 0 {
		return []
	}
	return c.bases_of(symbol.id) or { [] }
}

// un_is_target_ts_type is the isTargetType of the checker.
fn (mut c Checker) un_is_target_ts_type(typ TypeResponse, o UnTypeOptions) bool {
	return match o.kind {
		.array, .indexed_collection {
			(c.is_array(typ) or { false }) || typ.is_tuple_type
		}
		.bigint {
			// The base type of a BigInt literal type is `bigint`.
			typ.flags & (type_flag_bigint | type_flag_bigint_literal) != 0
		}
		.string_ {
			typ.flags & type_flag_string_literal != 0 || typ.intrinsic_name == 'string'
		}
		.number_ {
			typ.flags & type_flag_number_literal != 0 || typ.intrinsic_name == 'number'
		}
		else {
			false
		}
	}
}

// un_ts_type_kind ports getTypeScriptType.
fn (mut c Checker) un_ts_type_kind(typ TypeResponse, o UnTypeOptions, depth int) UnType {
	if depth > 50 {
		return .unknown
	}
	if typ.intrinsic_name in ['any', 'error', 'unknown'] {
		return .unknown
	}
	if typ.intrinsic_name in ['null', 'undefined'] {
		return .nullish
	}
	if typ.flags & type_flag_type_parameter != 0 {
		constraint := c.base_constraint(typ) or { return .unknown }
		return if constraint.is_null() {
			.unknown
		} else {
			c.un_ts_type_kind(constraint, o, depth + 1)
		}
	}
	if typ.flags & type_flag_union != 0 {
		members := c.members_of(typ) or { return .unknown }
		return un_combine_union(members.map(c.un_ts_type_kind(it, o, depth + 1)), o)
	}
	if typ.flags & type_flag_intersection != 0 {
		members := c.members_of(typ) or { return .unknown }
		return un_combine_intersection(members.map(c.un_ts_type_kind(it, o, depth + 1)))
	}
	if c.un_is_target_ts_type(typ, o) {
		return .target
	}
	constraint := c.base_constraint(typ) or { TypeResponse{} }
	if !constraint.is_null() && constraint.id != typ.id {
		return c.un_ts_type_kind(constraint, o, depth + 1)
	}
	if o.check_class_heritage
		&& c.un_ts_base_types(typ).any(c.un_ts_type_kind(it, o, depth + 1) == .target) {
		return .target
	}
	if typ.intrinsic_name != '' {
		return .non_target
	}
	name := c.un_ts_type_symbol_name(typ) or { return .unknown }
	alias := o.type_reference_aliases[name] or { '' }
	return if name in o.target_type_names || (alias != '' && alias in o.target_type_names) {
		.target
	} else {
		.non_target
	}
}

// un_type_from_type_information ports getTypeFromTypeInformation.
fn (mut c Checker) un_type_from_type_information(ctx &UnCtx, node int, o UnTypeOptions) UnType {
	typ := c.un_ts_type(ctx, node) or { return .unknown }
	return c.un_ts_type_kind(typ, o, 0)
}

// un_static_type is the getStaticType of the checker for a static value.
fn un_static_type(value JsAny, t &estree.EsTree, node int, o UnTypeOptions) UnType {
	return match o.kind {
		.array, .indexed_collection {
			if value.kind == .array_ {
				.target
			} else if t.typ(node) in [.identifier, .member_expression] {
				.unknown
			} else {
				.non_target
			}
		}
		.bigint {
			if value.kind == .bigint_ { .target } else { .unknown }
		}
		.string_ {
			if value.kind == .string_ { .target } else { .unknown }
		}
		.regexp {
			if value.kind == .regexp_ { .target } else { .unknown }
		}
		else {
			.unknown
		}
	}
}

// un_type_from_static_value ports getTypeFromStaticValue.
fn (mut c Checker) un_type_from_static_value(mut ctx UnCtx, node int, o UnTypeOptions) UnType {
	if o.kind !in [.array, .indexed_collection, .bigint, .string_, .regexp] {
		return .unknown
	}
	result := c.un_static_value_for_control_flow(mut ctx, node) or { return .unknown }
	typ := un_static_type(result.value, ctx.t, node, o)
	mut visited := map[int]bool{}
	return if typ != .unknown && c.un_has_jsdoc_type_reference(mut ctx, node, mut visited) {
		.unknown
	} else {
		typ
	}
}

// un_type_from_variable ports getTypeFromVariable.
fn (mut c Checker) un_type_from_variable(mut ctx UnCtx, node int, o UnTypeOptions, mut visited map[int]bool) UnType {
	t := ctx.t
	v := c.un_find_variable(ctx, node)
	tree := c.scope_tree(ctx.root)
	if v < 0 || v in visited || tree.variables[v].defs.len != 1 {
		return .unknown
	}
	visited[v] = true
	def := tree.variables[v].defs[0]
	name := c.un_es_of(ctx, def.name)
	mut from_annotation := UnType.unknown
	if name >= 0 {
		mut type_visited := map[string]bool{}
		from_annotation = c.un_type_annotation_type(mut ctx, t.node(name, .type_annotation) or {
			-1
		}, c.un_scope_of(ctx, name), o, mut type_visited)
		if t.flag(name, .optional) or { false } {
			from_annotation = un_combine_union([from_annotation, .nullish], o)
		}
	}
	mut typ := UnType.unknown
	init := c.un_es_of(ctx, def.init)
	if from_annotation != .unknown {
		typ = from_annotation
	} else if def.kind == .variable && def.parent_kind == 'const' && un_def_names_itself(def)
		&& init >= 0 {
		typ = c.un_get_type(mut ctx, init, o, mut visited)
	}
	visited.delete(v)
	return typ
}

// un_definition_initializer ports getDefinitionInitializer: the initializer of a variable, or the
// default value of a simple parameter.
fn (mut c Checker) un_definition_initializer(ctx &UnCtx, def ScopeDefinition) int {
	if def.kind == .variable {
		return c.un_es_of(ctx, def.init)
	}
	if def.kind != .parameter {
		return -1
	}
	t := ctx.t
	name := c.un_es_of(ctx, def.name)
	if name < 0 {
		return -1
	}
	parent := t.nodes[name].parent
	if parent >= 0 && t.typ(parent) == .assignment_pattern && (t.node(parent, .left) or { -1 }) == name {
		return t.node(parent, .right) or { -1 }
	}
	return -1
}

// un_type_from_function_call ports getTypeFromFunctionCall: the documented or annotated return type
// of the local function a call calls.
fn (mut c Checker) un_type_from_function_call(mut ctx UnCtx, node int, o UnTypeOptions) UnType {
	t := ctx.t
	callee := t.node(node, .callee) or { return .unknown }
	if t.typ(callee) != .identifier {
		return .unknown
	}
	v := c.un_find_variable(ctx, callee)
	tree := c.scope_tree(ctx.root)
	if v < 0 || tree.variables[v].defs.len != 1
		|| tree.variables[v].references.any(tree.references[it].write && !tree.references[it].init) {
		return .unknown
	}
	def := tree.variables[v].defs[0]
	name := c.un_es_of(ctx, def.name)
	if name >= 0 && t.node(name, .type_annotation) != none {
		return .unknown
	}
	initializer := c.un_definition_initializer(ctx, def)
	value := if def.kind == .function_name {
		c.un_es_of(ctx, def.node)
	} else if initializer >= 0 {
		un_unwrap_ts_expression(t, initializer)
	} else {
		-1
	}
	if value >= 0 && ((t.flag(value, .async) or { false }) || (t.flag(value, .generator) or { false })
		|| (def.kind == .parameter && (t.node(value, .return_type) != none
		|| un_has_native_type_assertion(t, initializer)))) {
		return .unknown
	}
	mut function := -1
	if def.kind == .function_name {
		function = c.un_es_of(ctx, def.node)
	} else if def.kind == .variable && un_def_names_itself(def) {
		mut init := c.un_es_of(ctx, def.init)
		for init >= 0 && t.typ(init) in [.ts_satisfies_expression, .ts_non_null_expression] {
			init = t.node(init, .expression) or { -1 }
		}
		if init >= 0 && t.typ(init) in [.function_declaration, .function_expression,
			.arrow_function_expression] {
			function = init
		}
	}
	if function >= 0 && t.node(function, .type_parameters) != none {
		return .unknown
	}
	if function >= 0 {
		if return_type := t.node(function, .return_type) {
			scope := c.un_scope_of(ctx, function)
			tree2 := c.scope_tree(ctx.root)
			mut type_visited := map[string]bool{}
			return c.un_type_annotation_type(mut ctx, return_type, tree2.scopes[scope].upper, o, mut
				type_visited)
		}
	}
	if name >= 0 {
		if annotation := c.un_jsdoc_type_annotation(mut ctx, name) {
			if annotation.optional {
				return .unknown
			}
			return_type := un_jsdoc_callable_return_type(annotation.typ) or {
				return un_jsdoc_type(UnJsdocAnnotation{}, o)
			}
			return un_jsdoc_type(UnJsdocAnnotation{
				has_type: true
				typ:      return_type
			}, o)
		}
	}
	return_annotation := c.un_jsdoc_return_type(mut ctx, function) or { UnJsdocAnnotation{} }
	return un_jsdoc_type(return_annotation, o)
}

// un_is_typed_array_factory ports isTypedArrayFactory: `Uint8Array.from(…)`, `Int8Array.of(…)`.
fn un_is_typed_array_factory(t &estree.EsTree, node int) bool {
	return un_is_method_call(t, node,
		objects:         un_typed_arrays
		methods:         ['from', 'of']
		optional_call:   false
		optional_member: false
	)
}

// un_is_rest_parameter ports isRestParameter: a rest parameter that is never written.
fn (mut c Checker) un_is_rest_parameter(ctx &UnCtx, node int) bool {
	t := ctx.t
	if t.typ(node) != .identifier {
		return false
	}
	v := c.un_find_variable(ctx, node)
	def := c.un_only_definition(ctx, v) or { return false }
	if def.kind != .parameter {
		return false
	}
	name := c.un_es_of(ctx, def.name)
	if name < 0 {
		return false
	}
	parameter := t.nodes[name].parent
	function := c.un_es_of(ctx, def.node)
	if parameter < 0 || t.typ(parameter) != .rest_element || function < 0
		|| t.typ(function) !in [.function_declaration, .function_expression, .arrow_function_expression]
		|| parameter !in (t.list(function, .params) or { []int{} }) {
		return false
	}
	tree := c.scope_tree(ctx.root)
	return tree.variables[v].references.all(!tree.references[it].write)
}

// un_is_target_node is the isTargetNode of the checker; `o` gives isTarget for the operands.
fn (mut c Checker) un_is_target_node(mut ctx UnCtx, node int, o UnTypeOptions, mut visited map[int]bool) bool {
	t := ctx.t
	match o.kind {
		.array {
			return c.un_is_array_node(mut ctx, node, o, mut visited)
		}
		.indexed_collection {
			mut array_visited := map[int]bool{}
			return c.un_is_array_node(mut ctx, node, un_type_options(.array), mut array_visited)
				|| un_is_typed_array_factory(t, node)
		}
		.bigint_typed_array {
			if !un_is_typed_array_factory(t, node) {
				return false
			}
			callee := t.node(node, .callee) or { return false }
			object := t.node(callee, .object) or { return false }
			return (t.string_of(object, .name) or { '' }) in ['BigInt64Array', 'BigUint64Array']
		}
		.bigint {
			return c.un_is_bigint_node(mut ctx, node, o, mut visited)
		}
		.string_ {
			return c.un_is_string_node(mut ctx, node, o, mut visited)
		}
		.regexp {
			return un_is_regex_literal(t, node)
		}
		.date, .number_, .sized_collection {
			return false
		}
	}
}

// un_is_array_node ports isArrayNode (`o` is the checker of `isTarget`).
fn (mut c Checker) un_is_array_node(mut ctx UnCtx, node int, o UnTypeOptions, mut visited map[int]bool) bool {
	t := ctx.t
	if t.typ(node) == .array_expression || c.un_is_rest_parameter(ctx, node) {
		return true
	}
	if un_is_method_call(t, node,
		objects:         ['Array']
		methods:         ['from', 'of']
		optional_call:   false
		optional_member: false
	) || un_is_method_call(t, node,
		objects:         ['Object']
		methods:         ['keys', 'values', 'entries', 'getOwnPropertyNames', 'getOwnPropertySymbols']
		optional_call:   false
		optional_member: false
	) {
		return true
	}
	if un_is_method_call(t, node,
		methods:         ['copyWithin', 'fill', 'reverse', 'sort', 'toReversed', 'toSorted', 'toSpliced',
			'with']
		optional_call:   false
		optional_member: false
	) {
		callee := t.node(node, .callee) or { return false }
		object := t.node(callee, .object) or { return false }
		return c.un_get_type(mut ctx, object, o, mut visited) == .target
	}
	return false
}

// un_is_non_target_node is the isNonTargetNode of the checker.
fn un_is_non_target_node(t &estree.EsTree, node int, o UnTypeOptions) bool {
	if o.kind !in [.array, .indexed_collection] {
		return false
	}
	return t.typ(node) in [.new_expression, .object_expression, .function_expression,
		.arrow_function_expression, .class_expression, .template_literal]
		|| un_is_typed_array_factory(t, node)
}

// un_type_from_expression ports getTypeFromExpression (without checkClassSyntax: no checker of
// the ported rules sets it, and `this`, `super` and `new` are unknown).
fn (mut c Checker) un_type_from_expression(mut ctx UnCtx, node int, o UnTypeOptions, mut visited map[int]bool) UnType {
	t := ctx.t
	match t.typ(node) {
		.identifier {
			return c.un_type_from_variable(mut ctx, node, o, mut visited)
		}
		.call_expression {
			return c.un_type_from_function_call(mut ctx, node, o)
		}
		.assignment_expression {
			return if (t.string_of(node, .operator) or { '' }) == '=' {
				c.un_get_type(mut ctx, t.node(node, .right) or { -1 }, o, mut visited)
			} else {
				.unknown
			}
		}
		.ts_as_expression, .ts_type_assertion {
			annotation := t.node(node, .type_annotation) or { -1 }
			mut type_visited := map[string]bool{}
			from_annotation := c.un_type_annotation_type(mut ctx, annotation, c.un_scope_of(ctx,
				node), o, mut type_visited)
			return if from_annotation == .unknown && annotation >= 0
				&& t.typ(annotation) in [.ts_any_keyword, .ts_unknown_keyword] {
				c.un_get_type(mut ctx, t.node(node, .expression) or { -1 }, o, mut visited)
			} else {
				from_annotation
			}
		}
		.ts_non_null_expression {
			return c.un_get_type(mut ctx, t.node(node, .expression) or { -1 }, o, mut visited)
		}
		.sequence_expression {
			expressions := t.list(node, .expressions) or { []int{} }
			return if expressions.len > 0 {
				c.un_get_type(mut ctx, expressions.last(), o, mut visited)
			} else {
				.unknown
			}
		}
		.logical_expression {
			return un_combine_union([
				c.un_get_type(mut ctx, t.node(node, .left) or { -1 }, o, mut visited),
				c.un_get_type(mut ctx, t.node(node, .right) or { -1 }, o, mut visited),
			], o)
		}
		.conditional_expression {
			return un_combine_union([
				c.un_get_type(mut ctx, t.node(node, .consequent) or { -1 }, o, mut visited),
				c.un_get_type(mut ctx, t.node(node, .alternate) or { -1 }, o, mut visited),
			], o)
		}
		else {
			return .unknown
		}
	}
}

// un_get_type ports getType.
fn (mut c Checker) un_get_type(mut ctx UnCtx, node int, o UnTypeOptions, mut visited map[int]bool) UnType {
	t := ctx.t
	if node < 0 {
		return .unknown
	}
	if t.typ(node) == .ts_satisfies_expression {
		return c.un_get_type(mut ctx, t.node(node, .expression) or { -1 }, o, mut visited)
	}
	if annotation := t.node(node, .type_annotation) {
		mut type_visited := map[string]bool{}
		from_annotation := c.un_type_annotation_type(mut ctx, annotation, c.un_scope_of(ctx, node),
			o, mut type_visited)
		if from_annotation != .unknown {
			return from_annotation
		}
	} else if annotation := c.un_jsdoc_type_annotation(mut ctx, node) {
		typ := un_jsdoc_type(annotation, o)
		return if typ == .unknown { c.un_type_from_type_information(ctx, node, o) } else { typ }
	}
	from_expression := c.un_type_from_expression(mut ctx, node, o, mut visited)
	if from_expression != .unknown {
		return from_expression
	}
	if t.typ(node) != .identifier {
		from_static := c.un_type_from_static_value(mut ctx, node, o)
		if from_static != .unknown {
			return from_static
		}
	}
	if c.un_is_target_node(mut ctx, node, o, mut visited) {
		return .target
	}
	if o.target_constructor_names.any(un_is_new(t, node, names: [it]))
		|| o.target_call_names.any(un_is_call(t, node, names: [it])) {
		return .target
	}
	from_types := c.un_type_from_type_information(ctx, node, o)
	if from_types != .unknown {
		return from_types
	}
	return if un_is_non_target_node(t, node, o) { .non_target } else { .unknown }
}

// un_type_of is createTypeCheckers(…).getType: the type, with nullish as non-target.
fn (mut c Checker) un_type_of(mut ctx UnCtx, node int, o UnTypeOptions) UnType {
	mut visited := map[int]bool{}
	return un_normalize_type(c.un_get_type(mut ctx, node, o, mut visited))
}

// un_is_target is createTypeCheckers(…).isTarget.
fn (mut c Checker) un_is_target(mut ctx UnCtx, node int, o UnTypeOptions) bool {
	mut visited := map[int]bool{}
	return c.un_get_type(mut ctx, node, o, mut visited) == .target
}

// un_is_known_non_target is createTypeCheckers(…).isKnownNonTarget.
fn (mut c Checker) un_is_known_non_target(mut ctx UnCtx, node int, o UnTypeOptions) bool {
	return c.un_type_of(mut ctx, node, o) == .non_target
}

// ---- is-bigint.js, is-string.js, is-reg-exp.js, is-array.js and
// should-skip-known-non-array-receiver.js

// un_is_static_bigint_call ports isBigIntCall and isBigIntMethodCall: `BigInt(…)`,
// `BigInt.asIntN(…)`, `BigInt.asUintN(…)`.
fn un_is_static_bigint_call(t &estree.EsTree, node int) bool {
	if un_is_function_call(t, node, 'BigInt') {
		return true
	}
	return t.typ(node) == .call_expression && !(t.flag(node, .optional) or { false })
		&& un_is_static_properties(t, t.node(node, .callee) or { return false }, 'BigInt', [
		'asIntN',
		'asUintN',
	])
}

// un_is_bigint_node ports isBigIntNode.
fn (mut c Checker) un_is_bigint_node(mut ctx UnCtx, node int, o UnTypeOptions, mut visited map[int]bool) bool {
	t := ctx.t
	if (t.typ(node) == .literal && t.string_of(node, .bigint) != none)
		|| un_is_static_bigint_call(t, node) {
		return true
	}
	operator := t.string_of(node, .operator) or { '' }
	match t.typ(node) {
		.unary_expression {
			return operator in ['-', '~']
				&& c.un_get_type(mut ctx, t.node(node, .argument) or { -1 }, o, mut visited) == .target
		}
		.binary_expression {
			return operator in ['+', '-', '*', '/', '%', '**', '<<', '>>', '|', '^', '&']
				&& c.un_get_type(mut ctx, t.node(node, .left) or { -1 }, o, mut visited) == .target
				&& c.un_get_type(mut ctx, t.node(node, .right) or { -1 }, o, mut visited) == .target
		}
		.update_expression {
			return c.un_get_type(mut ctx, t.node(node, .argument) or { -1 }, o, mut visited) == .target
		}
		else {
			return false
		}
	}
}

// un_is_bigint ports isBigInt (is-bigint.js) with options of the bigint checker given by the
// caller (prefer-math-min-max sets treatMixedUnionAsTarget).
fn (mut c Checker) un_is_bigint(mut ctx UnCtx, node int, o UnTypeOptions) bool {
	t := ctx.t
	if node < 0 {
		return false
	}
	if t.typ(node) == .ts_satisfies_expression
		&& un_is_bigint_type_annotation(t, t.node(node, .type_annotation) or { -1 }) {
		return true
	}
	if c.un_is_target(mut ctx, node, o) {
		return true
	}
	value := c.un_static_value_if_no_side_effects(mut ctx, node) or { return false }
	mut visited := map[int]bool{}
	return value.value.kind == .bigint_ && !c.un_has_jsdoc_type_reference(mut ctx, node, mut visited)
}

const un_string_returning_methods = ['charAt', 'concat', 'normalize', 'padEnd', 'padStart', 'repeat',
	'slice', 'substring', 'toLocaleLowerCase', 'toLocaleUpperCase', 'toLowerCase', 'toString',
	'toUpperCase', 'toWellFormed', 'trim', 'trimEnd', 'trimStart', 'valueOf']
const un_date_string_returning_methods = ['toDateString', 'toISOString', 'toLocaleDateString',
	'toLocaleString', 'toLocaleTimeString', 'toString', 'toTimeString', 'toUTCString']

// un_is_unmodified_mutable_variable ports isUnmodifiedMutableVariable: a `let` or `var` with an
// initializer that is never written again.
fn (mut c Checker) un_is_unmodified_mutable_variable(ctx &UnCtx, node int) bool {
	if ctx.t.typ(node) != .identifier {
		return false
	}
	v := c.un_find_variable(ctx, node)
	def := c.un_only_definition(ctx, v) or { return false }
	tree := c.scope_tree(ctx.root)
	return def.kind == .variable && def.parent_kind in ['let', 'var'] && un_def_names_itself(def)
		&& def.init != none
		&& tree.variables[v].references.all(!tree.references[it].write || tree.references[it].init)
}

// un_is_string_with ports isString (is-string.js) with the checker options of `isTarget`.
fn (mut c Checker) un_is_string_with(mut ctx UnCtx, node int, o UnTypeOptions, mut visited map[int]bool) bool {
	t := ctx.t
	if node < 0 {
		return false
	}
	if t.typ(node) == .ts_satisfies_expression
		&& un_is_string_type_annotation(t, t.node(node, .type_annotation) or { -1 }) {
		return true
	}
	if c.un_get_type(mut ctx, node, o, mut visited) == .target {
		return true
	}
	value := if c.un_is_unmodified_mutable_variable(ctx, node) {
		c.un_static_value_if_no_side_effects(mut ctx, node)
	} else {
		c.un_static_value_for_control_flow(mut ctx, node)
	}
	static_value := value or { return false }
	mut jsdoc_visited := map[int]bool{}
	return static_value.value.kind == .string_
		&& !c.un_has_jsdoc_type_reference(mut ctx, node, mut jsdoc_visited)
}

// un_is_string ports isString with its own checker.
fn (mut c Checker) un_is_string(mut ctx UnCtx, node int) bool {
	mut visited := map[int]bool{}
	return c.un_is_string_with(mut ctx, node, un_type_options(.string_), mut visited)
}

// un_is_string_node ports isStringNode.
fn (mut c Checker) un_is_string_node(mut ctx UnCtx, node int, o UnTypeOptions, mut visited map[int]bool) bool {
	t := ctx.t
	if un_is_string_literal(t, node) || un_is_function_call(t, node, 'String') {
		return true
	}
	if t.typ(node) == .call_expression && !(t.flag(node, .optional) or { false })
		&& un_is_static_properties(t, t.node(node, .callee) or { return false }, 'String', [
		'fromCharCode',
		'fromCodePoint',
		'raw',
	]) {
		return true
	}
	operator := t.string_of(node, .operator) or { '' }
	match t.typ(node) {
		.member_expression {
			return un_is_member(t, node, properties: ['source', 'flags'], optional: false)
				&& c.un_is_target(mut ctx, t.node(node, .object) or { -1 }, UnTypeOptions{
				...un_type_options(.regexp)
				check_class_heritage: false
			})
		}
		.tagged_template_expression {
			return un_is_member(t, t.node(node, .tag) or { -1 },
				objects:    ['String']
				properties: ['raw']
				optional:   false
			)
		}
		.call_expression {
			callee := t.node(node, .callee) or { return false }
			if un_is_method_call(t, node, methods: ['join'], optional_call: false, optional_member: false) {
				return c.un_is_target(mut ctx, t.node(callee, .object) or { -1 }, un_type_options(.indexed_collection))
			}
			if un_is_method_call(t, node,
				methods:         un_date_string_returning_methods
				optional_call:   false
				optional_member: false
			) && c.un_is_target(mut ctx, t.node(callee, .object) or { -1 }, un_type_options(.date)) {
				return true
			}
			return un_is_method_call(t, node,
				methods:         un_string_returning_methods
				optional_call:   false
				optional_member: false
			) && c.un_is_string_with(mut ctx, t.node(callee, .object) or { -1 }, o, mut visited)
		}
		.template_literal {
			return true
		}
		.unary_expression {
			return operator == 'typeof'
		}
		.binary_expression, .assignment_expression {
			if operator == '=' {
				return c.un_is_string_with(mut ctx, t.node(node, .right) or { -1 }, o, mut visited)
			}
			return operator in ['+', '+=']
				&& (c.un_is_string_with(mut ctx, t.node(node, .left) or { -1 }, o, mut visited)
				|| c.un_is_string_with(mut ctx, t.node(node, .right) or { -1 }, o, mut visited))
		}
		else {
			return false
		}
	}
}

// un_is_known_non_string ports isKnownNonString.
fn (mut c Checker) un_is_known_non_string(mut ctx UnCtx, node int) bool {
	return c.un_is_known_non_target(mut ctx, node, un_type_options(.string_))
}

// un_is_array ports isArray (is-array.js).
fn (mut c Checker) un_is_array(mut ctx UnCtx, node int) bool {
	return c.un_is_target(mut ctx, node, un_type_options(.array))
}

// un_is_known_non_array ports isKnownNonArray.
fn (mut c Checker) un_is_known_non_array(mut ctx UnCtx, node int) bool {
	return c.un_is_known_non_target(mut ctx, node, un_type_options(.array))
}

// un_is_indexed_collection ports isIndexedCollection: an array or a typed array.
fn (mut c Checker) un_is_indexed_collection(mut ctx UnCtx, node int) bool {
	return c.un_is_target(mut ctx, node, un_type_options(.indexed_collection))
}

// un_is_known_non_indexed_collection ports isKnownNonIndexedCollection.
fn (mut c Checker) un_is_known_non_indexed_collection(mut ctx UnCtx, node int) bool {
	return c.un_is_known_non_target(mut ctx, node, un_type_options(.indexed_collection))
}

// un_is_known_bigint_typed_array ports isKnownBigIntTypedArray.
fn (mut c Checker) un_is_known_bigint_typed_array(mut ctx UnCtx, node int) bool {
	return c.un_is_target(mut ctx, node, un_type_options(.bigint_typed_array))
}

// un_should_skip_known_non_array_receiver ports shouldSkipKnownNonArrayReceiver: the receiver of an
// array method is known to be neither an array nor a typed array (a literal, array, object,
// function or template is still reported).
fn (mut c Checker) un_should_skip_known_non_array_receiver(mut ctx UnCtx, node int) bool {
	t := ctx.t
	if node < 0 || t.typ(node) in [.array_expression, .function_expression, .literal,
		.object_expression, .template_literal] {
		return false
	}
	return c.un_is_known_non_indexed_collection(mut ctx, node)
}

// ---- is-number.js

const un_string_number_methods = ['charCodeAt', 'indexOf', 'lastIndexOf', 'localeCompare']
const un_indexed_collection_number_methods = ['indexOf', 'lastIndexOf', 'findIndex', 'findLastIndex']
const un_date_number_returning_methods = ['getDate', 'getDay', 'getFullYear', 'getHours',
	'getMilliseconds', 'getMinutes', 'getMonth', 'getSeconds', 'getTime', 'getTimezoneOffset',
	'getUTCDate', 'getUTCDay', 'getUTCFullYear', 'getUTCHours', 'getUTCMilliseconds', 'getUTCMinutes',
	'getUTCMonth', 'getUTCSeconds', 'setDate', 'setFullYear', 'setHours', 'setMilliseconds',
	'setMinutes', 'setMonth', 'setSeconds', 'setTime', 'setUTCDate', 'setUTCFullYear', 'setUTCHours',
	'setUTCMilliseconds', 'setUTCMinutes', 'setUTCMonth', 'setUTCSeconds', 'valueOf']

// un_is_number_returning_method_call ports isNumberReturningMethodCall: `s.indexOf()` of a string,
// `a.push()` of an array, `a.findIndex()` of an indexed collection, `d.getTime()` of a Date.
fn (mut c Checker) un_is_number_returning_method_call(mut ctx UnCtx, node int) bool {
	t := ctx.t
	if t.typ(node) != .call_expression || (t.flag(node, .optional) or { false }) {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	if t.typ(callee) != .member_expression || (t.flag(callee, .computed) or { false })
		|| (t.flag(callee, .optional) or { false }) {
		return false
	}
	property := t.node(callee, .property) or { return false }
	if t.typ(property) != .identifier {
		return false
	}
	name := t.string_of(property, .name) or { '' }
	object := t.node(callee, .object) or { return false }
	return (name in un_string_number_methods && c.un_is_string(mut ctx, object))
		|| (name in ['push', 'unshift'] && c.un_is_array(mut ctx, object))
		|| (name in un_indexed_collection_number_methods && c.un_is_indexed_collection(mut ctx, object))
		|| (name in un_date_number_returning_methods
		&& c.un_is_target(mut ctx, object, un_type_options(.date)))
}

// un_is_numeric_property ports isNumericProperty: the `length` of a function, a string or an
// indexed collection, the `size` of a Map or a Set.
fn (mut c Checker) un_is_numeric_property(mut ctx UnCtx, node int) bool {
	t := ctx.t
	if t.typ(node) != .member_expression || (t.flag(node, .computed) or { false })
		|| (t.flag(node, .optional) or { false }) {
		return false
	}
	property := t.node(node, .property) or { return false }
	if t.typ(property) != .identifier {
		return false
	}
	object := t.node(node, .object) or { return false }
	name := t.string_of(property, .name) or { '' }
	if name == 'length' {
		return t.typ(object) in [.function_declaration, .function_expression, .arrow_function_expression]
			|| c.un_is_string(mut ctx, object) || c.un_is_indexed_collection(mut ctx, object)
	}
	return name == 'size' && c.un_is_target(mut ctx, object, un_type_options(.sized_collection))
}

// un_has_number_type_annotation ports hasNumberTypeAnnotation (hasTypeAnnotation of type-check.js):
// a definition of the variable annotated `number` (not optional).
fn (mut c Checker) un_has_number_type_annotation(ctx &UnCtx, node int) bool {
	t := ctx.t
	v := c.un_find_variable(ctx, node)
	if v < 0 {
		return false
	}
	tree := c.scope_tree(ctx.root)
	for def in tree.variables[v].defs {
		name := c.un_es_of(ctx, def.name)
		if name < 0 || (t.flag(name, .optional) or { false }) {
			continue
		}
		annotation := t.node(name, .type_annotation) or { continue }
		if un_is_number_type_annotation(t, t.node(annotation, .type_annotation) or { -1 }) {
			return true
		}
	}
	return false
}

// un_is_number ports isNumber of utils/is-number.js: the expression is surely a number (not a
// BigInt), by its syntax, its static value or its type.
fn (mut c Checker) un_is_number(mut ctx UnCtx, node int) bool {
	t := ctx.t
	if node < 0 {
		return false
	}
	typ := t.typ(node)
	if typ == .literal && t.get(node, .value) is f64 {
		return true
	}
	if un_is_static_properties(t, node, 'Math', un_math_properties)
		|| un_is_static_properties(t, node, 'Number', un_number_properties) {
		return true
	}
	if typ == .call_expression && !(t.flag(node, .optional) or { false }) {
		callee := t.node(node, .callee) or { -1 }
		if un_is_static_properties(t, callee, 'Math', un_math_methods)
			|| un_is_static_properties(t, callee, 'Number', ['parseFloat', 'parseInt'])
			|| un_is_static_properties(t, callee, 'Date', ['now', 'parse', 'UTC']) {
			return true
		}
	}
	if un_is_function_call(t, node, 'Number') || un_is_function_call(t, node, 'parseInt')
		|| un_is_function_call(t, node, 'parseFloat')
		|| c.un_is_number_returning_method_call(mut ctx, node)
		|| c.un_is_numeric_property(mut ctx, node) {
		return true
	}
	mut operator := t.string_of(node, .operator) or { '' }
	match typ {
		.assignment_expression, .binary_expression {
			left := t.node(node, .left) or { -1 }
			right := t.node(node, .right) or { -1 }
			if typ == .assignment_expression {
				if operator == '=' && c.un_is_number(mut ctx, right) {
					return true
				}
				operator = operator[..operator.len - 1]
			}
			if operator == '+' && c.un_is_number(mut ctx, left) && c.un_is_number(mut ctx, right) {
				return true
			}
			// `>>>` cannot be used on a BigInt.
			if operator == '>>>' {
				return true
			}
			// `a * b` may be a BigInt: one side must be a number.
			if operator in ['-', '*', '/', '%', '**', '<<', '>>', '|', '^', '&']
				&& (c.un_is_number(mut ctx, left) || c.un_is_number(mut ctx, right)) {
				return true
			}
		}
		.unary_expression {
			// `+` cannot be used on a BigInt.
			if operator == '+' {
				return true
			}
			if operator in ['-', '~'] && c.un_is_number(mut ctx, t.node(node, .argument) or { -1 }) {
				return true
			}
		}
		.update_expression {
			if c.un_is_number(mut ctx, t.node(node, .argument) or { -1 }) {
				return true
			}
		}
		.conditional_expression {
			consequent := c.un_is_number(mut ctx, t.node(node, .consequent) or { -1 })
			alternate := c.un_is_number(mut ctx, t.node(node, .alternate) or { -1 })
			if consequent && alternate {
				return true
			}
			test_node := t.node(node, .test) or { -1 }
			if test := c.un_static_value_for_control_flow(mut ctx, test_node) {
				mut visited := map[int]bool{}
				if !c.un_has_jsdoc_type_reference(mut ctx, test_node, mut visited)
					&& ((consequent && stv_to_boolean(test.value))
					|| (alternate && !stv_to_boolean(test.value))) {
					return true
				}
			}
		}
		.sequence_expression {
			expressions := t.list(node, .expressions) or { []int{} }
			if expressions.len > 0 && c.un_is_number(mut ctx, expressions.last()) {
				return true
			}
		}
		.identifier {
			if c.un_has_number_type_annotation(ctx, node) {
				return true
			}
		}
		.ts_as_expression, .ts_satisfies_expression, .ts_type_assertion {
			if un_is_number_type_annotation(t, t.node(node, .type_annotation) or { -1 }) {
				return true
			}
		}
		.ts_non_null_expression {
			if c.un_is_number(mut ctx, t.node(node, .expression) or { -1 }) {
				return true
			}
		}
		else {}
	}
	if c.un_is_target(mut ctx, node, un_type_options(.number_)) {
		return true
	}
	mut visited := map[int]bool{}
	if c.un_has_jsdoc_type_reference(mut ctx, node, mut visited) {
		return false
	}
	result := c.un_static_value_for_control_flow(mut ctx, node) or { return false }
	return result.value.kind == .number_
}

// ---- boolean.js (with the context of eslint-plugin-unicorn 79.0.0)

// un_is_global_boolean_call ports isGlobalBooleanCall: `Boolean(x)` of the global `Boolean`.
fn (mut c Checker) un_is_global_boolean_call(ctx &UnCtx, node int) bool {
	t := ctx.t
	if node < 0 || t.typ(node) != .call_expression || (t.flag(node, .optional) or { false }) {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	args := t.list(node, .arguments) or { return false }
	if t.typ(callee) != .identifier || (t.string_of(callee, .name) or { '' }) != 'Boolean'
		|| args.len != 1 || t.typ(args[0]) == .spread_element {
		return false
	}
	// isGlobalReference
	ts := t.ts_node(callee) or { return false }
	if c.es_is_global_reference(ctx.root, ts) {
		return true
	}
	v := c.un_find_variable(ctx, callee)
	return v < 0 || c.scope_tree(ctx.root).variables[v].defs.len == 0
}

// un_is_boolean_call_argument ports isBooleanCallArgument.
fn (mut c Checker) un_is_boolean_call_argument(ctx &UnCtx, node int) bool {
	parent := ctx.t.nodes[node].parent
	return c.un_is_global_boolean_call(ctx, parent)
		&& (ctx.t.list(parent, .arguments) or { []int{} })[0] == node
}

// un_is_boolean_expression_in ports isBooleanExpression (79.0.0).
fn (mut c Checker) un_is_boolean_expression_in(ctx &UnCtx, node int) bool {
	t := ctx.t
	parent := t.nodes[node].parent
	if un_is_logic_not(t, node)
		|| (un_is_logic_not(t, parent) && (t.node(parent, .argument) or { -1 }) == node)
		|| c.un_is_global_boolean_call(ctx, node) || c.un_is_boolean_call_argument(ctx, node) {
		return true
	}
	return un_is_logical(t, parent) && c.un_is_boolean_expression_in(ctx, parent)
}

// un_is_boolean_context ports isBooleanContext: the value of the node is only used for its
// truthiness.
fn (mut c Checker) un_is_boolean_context(ctx &UnCtx, node int) bool {
	return c.un_is_boolean_expression_in(ctx, node) || un_is_control_flow_test(ctx.t, node)
}

// un_boolean_ancestor_in ports getBooleanAncestor (79.0.0): through `!` and the global
// `Boolean()`, and whether the count of `!` is odd.
fn (mut c Checker) un_boolean_ancestor_in(ctx &UnCtx, start int) (int, bool) {
	t := ctx.t
	mut node := start
	mut negative := false
	for {
		parent := t.nodes[node].parent
		if un_is_logic_not(t, parent) && (t.node(parent, .argument) or { -1 }) == node {
			negative = !negative
			node = parent
		} else if c.un_is_boolean_call_argument(ctx, node) {
			node = parent
		} else {
			break
		}
	}
	return node, negative
}

// un_logical_operands ports getLogicalExpressionOperands: the operands of a chain of the operator,
// from left to right.
fn un_logical_operands(t &estree.EsTree, node int, operator string) []int {
	if node < 0 || t.typ(node) != .logical_expression
		|| (t.string_of(node, .operator) or { '' }) != operator {
		return [node]
	}
	mut out := un_logical_operands(t, t.node(node, .left) or { -1 }, operator)
	out << un_logical_operands(t, t.node(node, .right) or { -1 }, operator)
	return out
}

// un_logical_root ports getLogicalExpressionRoot: the outermost logical expression of the
// operator that has the node as an operand, or the node.
fn un_logical_root(t &estree.EsTree, from int, operator string) int {
	mut node := from
	for {
		parent := t.nodes[node].parent
		if parent < 0 || t.typ(parent) != .logical_expression
			|| (t.string_of(parent, .operator) or { '' }) != operator {
			break
		}
		node = parent
	}
	return node
}

// ---- length-or-size.js

// un_is_length_or_size_member ports isLengthOrSizeMemberExpression: `x.length` or `x.size`.
fn un_is_length_or_size_member(t &estree.EsTree, node int) bool {
	return un_is_member(t, node, properties: ['length', 'size'], optional: false)
}

// un_string_if_constant_in ports getStringIfConstant(node, scope) of eslint-utils.
fn (mut c Checker) un_string_if_constant_in(t &estree.EsTree, node int) ?string {
	if t.typ(node) == .literal {
		regex := t.get(node, .regex)
		if regex is estree.RegexInfo {
			return '/${regex.pattern}/${regex.flags}'
		}
		if bigint := t.string_of(node, .bigint) {
			return bigint
		}
	}
	result := c.un_static_value(t, node)
	if !result.found {
		return none
	}
	return js_any_string_value(result.value)
}

// un_property_name_in ports getPropertyName(node, scope) of eslint-utils: the name of a member
// expression, property, method or field; none when it is not static.
fn (mut c Checker) un_property_name_in(t &estree.EsTree, node int) ?string {
	computed := t.flag(node, .computed) or { false }
	match t.typ(node) {
		.member_expression {
			property := t.node(node, .property)?
			if computed {
				return c.un_string_if_constant_in(t, property)
			}
			if t.typ(property) == .private_identifier {
				return none
			}
			return t.string_of(property, .name)
		}
		.property, .method_definition, .property_definition {
			key := t.node(node, .key)?
			if computed {
				return c.un_string_if_constant_in(t, key)
			}
			if t.typ(key) == .literal {
				value := t.get(key, .value)
				return match value {
					string { value }
					f64 { js_number_to_string(value) }
					bool { value.str() }
					estree.Null { 'null' }
					else { c.un_string_if_constant_in(t, key) }
				}
			}
			if t.typ(key) == .private_identifier {
				return none
			}
			return t.string_of(key, .name)
		}
		else {
			return none
		}
	}
}

// un_is_accessor_descriptor ports isAccessorDescriptor: `{get() {}}` or `{set() {}}`.
fn (mut c Checker) un_is_accessor_descriptor(t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) != .object_expression {
		return false
	}
	properties := t.list(node, .properties) or { []int{} }
	return properties.all(t.typ(it) != .spread_element) && properties.any(t.typ(it) == .property
		&& (c.un_property_name_in(t, it) or { '' }) in ['get', 'set'])
}

// un_object_method_call ports getObjectMethodCallExpression: `Object.<method>(reference, …)` of
// a global.
fn (mut c Checker) un_object_method_call(ctx &UnCtx, identifier int) ?int {
	t := ctx.t
	call := t.nodes[identifier].parent
	if call < 0 || t.typ(call) != .call_expression || (t.flag(call, .optional) or { false }) {
		return none
	}
	callee := t.node(call, .callee)?
	if t.typ(callee) != .member_expression || (t.flag(callee, .optional) or { false }) {
		return none
	}
	object := t.node(callee, .object)?
	args := t.list(call, .arguments) or { return none }
	if t.typ(object) != .identifier || !c.un_is_global_identifier(ctx, object) || args.len == 0
		|| args[0] != identifier {
		return none
	}
	return call
}

// un_last_object_property ports getLastObjectProperty: the last property with the name, none
// when a spread or an unknown computed key comes after it.
fn (mut c Checker) un_last_object_property(t &estree.EsTree, object int, name string) ?int {
	properties := t.list(object, .properties) or { return none }
	for i := properties.len - 1; i >= 0; i-- {
		property := properties[i]
		if t.typ(property) == .spread_element {
			return none
		}
		property_name := c.un_property_name_in(t, property) or { return none }
		if property_name == name {
			return property
		}
	}
	return none
}

fn un_argument_at(t &estree.EsTree, call int, i int) int {
	args := t.list(call, .arguments) or { return -1 }
	return if i < args.len { args[i] } else { -1 }
}

// un_has_unknown_object_property ports hasUnknownObjectProperty.
fn (mut c Checker) un_has_unknown_object_property(t &estree.EsTree, object int) bool {
	if object < 0 || t.typ(object) != .object_expression {
		return true
	}
	for property in t.list(object, .properties) or { []int{} } {
		if t.typ(property) == .spread_element {
			return true
		}
		if t.typ(property) == .property && (t.flag(property, .computed) or { false })
			&& c.un_property_name_in(t, property) == none {
			return true
		}
	}
	return false
}

// un_is_unconditional_switch_case ports isUnconditionallyExecutedSwitchCase.
fn un_is_unconditional_switch_case(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .switch_case || t.node(parent, .test) != none {
		return false
	}
	return (t.list(t.nodes[parent].parent, .cases) or { []int{} }).len == 1
}

// un_object_property_definition ports getObjectPropertyDefinition: the descriptor of
// `Object.defineProperty(x, name, …)` or `Object.defineProperties(x, {name: …})`.
fn (mut c Checker) un_object_property_definition(mut ctx UnCtx, identifier int, name string) ?int {
	t := ctx.t
	call := c.un_object_method_call(ctx, identifier)?
	method := c.un_property_name_in(t, t.node(call, .callee)?) or { '' }
	if method == 'defineProperty' {
		key := un_argument_at(t, call, 1)
		if key < 0 {
			return none
		}
		value := c.un_static_value_for_control_flow(mut ctx, key)?
		if value.value.kind == .string_ && (js_any_string_value(value.value) or { '' }) == name {
			descriptor := un_argument_at(t, call, 2)
			return if descriptor >= 0 { descriptor } else { none }
		}
		return none
	}
	definitions := un_argument_at(t, call, 1)
	if method != 'defineProperties' || definitions < 0 || t.typ(definitions) != .object_expression {
		return none
	}
	property := c.un_last_object_property(t, definitions, name)?
	return t.node(property, .value)
}

// un_object_assign_property_value ports getObjectAssignPropertyValue: the value `Object.assign(x,
// {name: …})` gives.
fn (mut c Checker) un_object_assign_property_value(ctx &UnCtx, identifier int, name string) ?int {
	t := ctx.t
	call := c.un_object_method_call(ctx, identifier)?
	args := t.list(call, .arguments) or { return none }
	if (c.un_property_name_in(t, t.node(call, .callee)?) or { '' }) != 'assign' || args.len != 2
		|| t.typ(args[1]) != .object_expression
		|| (t.list(args[1], .properties) or { []int{} }).any(t.typ(it) == .spread_element) {
		return none
	}
	property := c.un_last_object_property(t, args[1], name)?
	return t.node(property, .value)
}

// un_assignment_value ports getAssignmentValue: the value a destructuring or assignment writes to
// the node.
fn (mut c Checker) un_assignment_value(t &estree.EsTree, node int) ?int {
	mut path := []string{} // `[<index>` or `.<name>`
	mut current := node
	for {
		parent := t.nodes[current].parent
		if parent < 0 {
			return none
		}
		match t.typ(parent) {
			.assignment_expression {
				if (t.node(parent, .left) or { -1 }) != current
					|| (t.string_of(parent, .operator) or { '' }) != '=' {
					return none
				}
				mut value := t.node(parent, .right) or { return none }
				for i := path.len - 1; i >= 0; i-- {
					if value < 0 {
						return none
					}
					part := path[i]
					if part.starts_with('[') {
						elements := t.list(value, .elements) or { []int{} }
						index := part[1..].int()
						value = if t.typ(value) == .array_expression && index >= 0 && index < elements.len {
							elements[index]
						} else {
							-1
						}
					} else {
						value = if t.typ(value) == .object_expression {
							property := c.un_last_object_property(t, value, part[1..]) or { -1 }
							if property >= 0 { t.node(property, .value) or { -1 } } else { -1 }
						} else {
							-1
						}
					}
				}
				return if value >= 0 { value } else { none }
			}
			.array_pattern {
				path << '[${(t.list(parent, .elements) or { []int{} }).index(current)}'
			}
			.rest_element, .assignment_pattern {
				return none
			}
			else {
				if t.typ(parent) == .property && t.typ(t.nodes[parent].parent) == .object_pattern {
					path << '.${c.un_property_name_in(t, parent) or { '' }}'
				}
			}
		}
		current = parent
	}
	return none
}

// un_is_known_non_negative_integer ports isKnownNonNegativeInteger.
fn (mut c Checker) un_is_known_non_negative_integer(mut ctx UnCtx, node int) bool {
	if node < 0 {
		return false
	}
	value := c.un_static_value_for_control_flow(mut ctx, node) or { return false }
	return un_is_safe_non_negative_integer(value.value)
}

fn un_is_safe_non_negative_integer(value JsAny) bool {
	return value.kind == .number_ && value.number >= 0 && value.number == math.trunc(value.number)
		&& value.number <= 9007199254740991.0
}

// un_referenced_member ports getReferencedMemberExpression: the outermost member expression whose
// object chain starts with the identifier.
fn un_referenced_member(t &estree.EsTree, identifier int) ?int {
	mut node := identifier
	for {
		parent := t.nodes[node].parent
		if parent < 0 || t.typ(parent) != .member_expression
			|| (t.node(parent, .object) or { -1 }) != node {
			break
		}
		node = parent
	}
	return if t.typ(node) == .member_expression { node } else { none }
}

// un_is_known_numeric_property_mutation ports isKnownNumericPropertyMutation.
fn (mut c Checker) un_is_known_numeric_property_mutation(mut ctx UnCtx, identifier int, name string) bool {
	t := ctx.t
	if descriptor := c.un_object_property_definition(mut ctx, identifier, name) {
		if t.typ(descriptor) == .object_expression {
			property := c.un_last_object_property(t, descriptor, 'value') or { -1 }
			value := if property >= 0 { t.node(property, .value) or { -1 } } else { -1 }
			return c.un_is_known_non_negative_integer(mut ctx, value)
		}
	}
	node := un_referenced_member(t, identifier) or {
		value := c.un_object_assign_property_value(ctx, identifier, name) or { -1 }
		return c.un_is_known_non_negative_integer(mut ctx, value)
	}
	parent := t.nodes[node].parent
	if t.typ(parent) == .for_of_statement {
		right := t.node(parent, .right) or { return false }
		value := c.un_static_value_for_control_flow(mut ctx, right) or { return false }
		return value.value.kind == .array_ && value.value.elements.len > 0
			&& value.value.elements.all(un_is_safe_non_negative_integer(it))
	}
	value := c.un_assignment_value(t, node) or { -1 }
	return c.un_is_known_non_negative_integer(mut ctx, value)
}

// un_enclosing_execution_context ports getEnclosingExecutionContext: the function, method, field
// or static block around the node, -1 at the top.
fn un_enclosing_execution_context(t &estree.EsTree, node int) int {
	mut current := t.nodes[node].parent
	for current >= 0 {
		if t.typ(current) in [.function_declaration, .function_expression, .arrow_function_expression,
			.accessor_property, .method_definition, .property_definition, .static_block,
			.ts_abstract_accessor_property, .ts_abstract_method_definition,
			.ts_abstract_property_definition] {
			return current
		}
		current = t.nodes[current].parent
	}
	return -1
}

// un_is_conditionally_executed ports isConditionallyExecuted.
fn (mut c Checker) un_is_conditionally_executed(mut ctx UnCtx, node int) bool {
	t := ctx.t
	mut current := node
	for t.nodes[current].parent >= 0 {
		parent := t.nodes[current].parent
		typ := t.typ(parent)
		is_key := fn [t, parent, current] (key estree.Key) bool {
			return (t.node(parent, key) or { -1 }) == current
		}
		if typ in [.if_statement, .conditional_expression] && (is_key(.consequent) || is_key(.alternate)) {
			if value := c.un_static_value_for_control_flow(mut ctx, t.node(parent, .test) or { -1 }) {
				if stv_to_boolean(value.value) == is_key(.consequent) {
					current = parent
					continue
				}
			}
			return true
		}
		if (typ == .logical_expression && is_key(.right))
			|| (typ == .for_statement && (is_key(.body) || is_key(.update)))
			|| (typ in [.while_statement, .for_in_statement, .for_of_statement] && is_key(.body))
			|| (typ == .switch_case && current in (t.list(parent, .consequent) or { []int{} })
			&& !un_is_unconditional_switch_case(t, current))
			|| (typ == .catch_clause && is_key(.body)) || (typ == .try_statement && is_key(.block))
			|| (typ == .assignment_pattern && is_key(.right))
			|| (typ == .member_expression && (t.flag(parent, .computed) or { false })
			&& is_key(.property) && un_has_optional_chain_element(t, parent))
			|| (typ == .call_expression && ((t.flag(parent, .optional) or { false })
			|| un_has_optional_chain_element(t, t.node(parent, .callee) or { -1 }))
			&& current in (t.list(parent, .arguments) or { []int{} })) {
			return true
		}
		current = parent
	}
	return false
}

// un_is_property_mutation ports isPropertyMutation.
fn (mut c Checker) un_is_property_mutation(mut ctx UnCtx, identifier int, name string) bool {
	t := ctx.t
	if descriptor := c.un_object_property_definition(mut ctx, identifier, name) {
		return !c.un_is_accessor_descriptor(t, descriptor)
	}
	if call := c.un_object_method_call(ctx, identifier) {
		method := c.un_property_name_in(t, t.node(call, .callee) or { -1 }) or { '' }
		args := t.list(call, .arguments) or { []int{} }
		if method == 'assign' {
			if args.len < 2 {
				return false
			}
			if _ := c.un_object_assign_property_value(ctx, identifier, name) {
				return true
			}
			return args.len != 2 || c.un_has_unknown_object_property(t, args[1])
		}
		if method == 'defineProperty' {
			key := un_argument_at(t, call, 1)
			if key < 0 {
				return true
			}
			value := c.un_static_value_for_control_flow(mut ctx, key) or { return true }
			return value.value.kind == .string_ && (js_any_string_value(value.value) or { '' }) == name
		}
		if method == 'defineProperties' {
			return c.un_has_unknown_object_property(t, un_argument_at(t, call, 1))
		}
	}
	node := un_referenced_member(t, identifier) or { return false }
	if (c.un_property_name_in(t, node) or { return false }) != name {
		return false
	}
	return un_is_left_hand_side(t, node)
}

// un_is_for_in_property_mutation ports isForInPropertyMutation: `for (x.length in …)`.
fn (mut c Checker) un_is_for_in_property_mutation(t &estree.EsTree, identifier int, name string) bool {
	node := un_referenced_member(t, identifier) or { return false }
	parent := t.nodes[node].parent
	return (c.un_property_name_in(t, node) or { return false }) == name
		&& t.typ(parent) == .for_in_statement && (t.node(parent, .left) or { -1 }) == node
}

// un_is_property_read ports isPropertyRead.
fn (mut c Checker) un_is_property_read(ctx &UnCtx, identifier int, name string) bool {
	t := ctx.t
	member := un_referenced_member(t, identifier) or { -1 }
	member_name := if member >= 0 { c.un_property_name_in(t, member) or { '\x00' } } else { '\x00' }
	if member < 0 || member_name != name {
		call := c.un_object_method_call(ctx, identifier) or { return false }
		method := c.un_property_name_in(t, t.node(call, .callee) or { -1 }) or { '' }
		return method in ['assign', 'defineProperty', 'defineProperties']
	}
	parent := t.nodes[member].parent
	return !((t.typ(parent) in [.call_expression, .new_expression]
		&& (t.node(parent, .callee) or { -1 }) == member)
		|| (t.typ(parent) == .tagged_template_expression && (t.node(parent, .tag) or { -1 }) == member))
}

// un_has_same_object_shape_property_check ports hasSameObjectShapePropertyCheck: `x.width &&
// x.length` looks at a shape, not a collection.
fn (mut c Checker) un_has_same_object_shape_property_check(t &estree.EsTree, node int, length int) bool {
	root := un_logical_root(t, node, '&&')
	if t.typ(root) != .logical_expression || (t.string_of(root, .operator) or { '' }) != '&&' {
		return false
	}
	object := t.node(length, .object) or { return false }
	for operand in un_logical_operands(t, root, '&&') {
		if operand == node || !un_is_member(t, operand, computed: false, optional: false) {
			continue
		}
		property := t.node(operand, .property) or { continue }
		if t.typ(property) == .identifier
			&& (t.string_of(property, .name) or { '' }) in ['depth', 'height', 'width']
			&& c.un_is_same_reference(t, t.node(operand, .object) or { continue }, object) {
			return true
		}
	}
	return false
}

// un_is_known_non_collection_length_or_size ports isKnownNonCollectionLengthOrSize: the `length`
// or `size` is known not to be a count (a static value that is not a non-negative integer, an
// accessor, a property of an object literal…).
fn (mut c Checker) un_is_known_non_collection_length_or_size(mut ctx UnCtx, member int) bool {
	t := ctx.t
	if value := c.un_static_value_if_no_side_effects(mut ctx, member) {
		return !un_is_safe_integer(value.value) || value.value.number < 0
	}
	object := t.node(member, .object) or { return false }
	if t.typ(object) != .identifier {
		return false
	}
	v := c.un_find_variable(ctx, object)
	def := c.un_only_definition(ctx, v) or { return false }
	init := c.un_es_of(ctx, def.init)
	if def.kind != .variable || init < 0 || t.typ(init) != .object_expression {
		return false
	}
	name := c.un_property_name_in(t, member) or { '\x00none' }
	// A getter or setter of the object literal itself.
	for property in t.list(init, .properties) or { []int{} } {
		if t.typ(property) == .property && (t.string_of(property, .kind) or { '' }) in ['get', 'set']
			&& (c.un_property_name_in(t, property) or { '\x00other' }) == name {
			return true
		}
	}
	tree := c.scope_tree(ctx.root)
	context := un_enclosing_execution_context(t, member)
	mut unknown_effect := false
	mut known_numeric_mutation := false
	mut accessor_definition := false
	for r in tree.variables[v].references {
		reference := tree.references[r]
		if reference.init {
			continue
		}
		identifier := c.es_index_of(t, reference.identifier) or { continue }
		in_unknown_context := un_enclosing_execution_context(t, identifier) != context
			|| c.un_is_conditionally_executed(mut ctx, identifier)
		if !in_unknown_context && t.nodes[identifier].start > t.nodes[member].start {
			continue
		}
		if c.un_is_for_in_property_mutation(t, identifier, name) {
			unknown_effect = true
			continue
		}
		if c.un_is_property_mutation(mut ctx, identifier, name) {
			if !in_unknown_context && c.un_is_known_numeric_property_mutation(mut ctx, identifier, name) {
				known_numeric_mutation = true
			} else {
				unknown_effect = true
			}
			continue
		}
		// isAccessorDefinition
		if descriptor := c.un_object_property_definition(mut ctx, identifier, name) {
			if c.un_is_accessor_descriptor(t, descriptor) {
				if in_unknown_context {
					unknown_effect = true
				} else {
					accessor_definition = true
				}
				continue
			}
		}
		if !c.un_is_property_read(ctx, identifier, name) {
			if in_unknown_context {
				unknown_effect = true
				continue
			}
			return false
		}
	}
	if unknown_effect {
		return true
	}
	if known_numeric_mutation {
		return false
	}
	if accessor_definition {
		return true
	}
	static_object := c.un_static_value_if_no_side_effects(mut ctx, init) or { return false }
	if static_object.value.kind != .object_ {
		return false
	}
	index := static_object.value.keys.index(name)
	if index < 0 {
		// `undefined` is not a safe integer.
		return true
	}
	property_value := static_object.value.values[index]
	return !un_is_safe_integer(property_value) || property_value.number < 0
}

fn un_is_safe_integer(value JsAny) bool {
	return value.kind == .number_ && value.number == math.trunc(value.number)
		&& math.abs(value.number) <= 9007199254740991.0
}
