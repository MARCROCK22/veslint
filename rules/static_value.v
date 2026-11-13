module rules

import jsregexp
import math
import math.big
import treesitter { children, named_children, node_end, node_field, node_kind, node_parent, node_start }

// Port of getStaticValue from @eslint-community/eslint-utils 4.9.1 (what typescript-eslint's
// util.getStaticValue is), with getStaticPropertyNameValue, getStringIfConstant and
// getPropertyName, and the typescript-eslint entry points getStaticMemberAccessValue and
// isStaticMemberAccessOfValue (util/misc.js). It evaluates an ESTree expression on the
// tree-sitter tree with JavaScript semantics; identifiers are resolved with the scope analysis of
// scope.v (findVariable from the global scope, like the typescript-eslint rules). Where JavaScript
// would throw (a TypeError, a SyntaxError of RegExp, a stack overflow), the value is not static,
// like eslint-utils' try/catch: the exception ends the whole evaluation there, whatever was
// already evaluated, and so does veslint (StvContext.aborted), also where it finds something it
// does not evaluate.
//
// Values are modelled as far as the rules need them: primitives (strings as UTF-16 units),
// arrays, plain objects (with the prototype a `__proto__` key gives them), RegExp objects, Maps,
// Sets and the iterators of arrays, Maps and Sets, the objects of primitives, well-known symbols
// and those of Symbol.for, and the builtin functions and namespaces of eslint-utils'
// builtinNames. Every callAllowed function is evaluated but Date and Date.parse, most of whose
// values depend on the time zone, the locale or the clock: here (the string, array and Number
// methods are generic where JavaScript's are), in static_collections.v (Map, Set, Object and its
// static functions), static_builtins.v (the URI functions, String.fromCodePoint, String.raw
// called as a function, isPrototypeOf, Math.f16round, Number#toString with a radix),
// unicode_case.v (toUpperCase and toLowerCase), unicode_normalization.v (normalize) and
// js_math.v (V8's own transcendental Math functions and Math.hypot, to the last bit); the array
// methods that take a callback, when veslint tells the truth of what it returns
// (stv_callback_truth).
// Deviations from eslint-utils, which give "not static" where it computes a value
// (tests/static_value_cases.json has statements of each, with eslint-utils' values): Date and
// Date.parse; a builtin function outside callAllowed that a builtin calls (a callback, the join
// of Array#toString, the toString or valueOf of an object being converted: stv_native_call);
// properties read or defined with a symbol key; the prototype objects (`String.prototype`) and
// the properties of builtin methods (`'a'.slice.length`, which String.raw reads in
// `String.raw(String)`); a BigInt of more than stv_bigint_max_bits bits made by `**` or `<<`; a
// string of more than stv_string_max_length units made by padStart, padEnd or String.raw, or an
// array-like receiver of more elements; and expressions nested more than stv_max_depth levels.

// JsAnyKind is the type of a JsAny.
enum JsAnyKind {
	undefined_
	null_
	boolean_
	number_
	string_
	bigint_
	symbol_    // a well-known symbol (`name` is its description, `Symbol.iterator`) or, when `registered`, one of Symbol.for (`units` is its key)
	array_     // `elements`
	object_    // a plain object: `keys` and `values`, and `elements` holds its prototype when it is not Object.prototype (an object, or null)
	regexp_    // `regexp`
	function_  // a builtin function: `name` is its canonical path (`String.prototype.slice`)
	namespace_ // a builtin namespace object: `name` (`Math`, `JSON`, `Reflect`)
	hole_      // an array hole (only inside `elements`)
	map_       // a Map: `elements` are its keys and `values` its values
	set_       // a Set: `elements`
	iterator_  // an iterator of an array, a Map or a Set: `name` is its @@toStringTag (`Array Iterator`), `elements` what is left of it
	wrapper_   // the object of a primitive (`new String('a')`, `Object(1)`): `elements[0]` is the primitive
}

// JsAny is a JavaScript value as getStaticValue gives it.
struct JsAny {
	kind     JsAnyKind
	boolean  bool
	number   f64
	units    []u16  // a string
	digits   string // the decimal digits of a BigInt
	name     string
	id       int // identity of an array, object, RegExp, Map, Set or iterator
	elements []JsAny
	keys     []string
	values   []JsAny
	regexp   jsregexp.RegexpValue
	// A symbol of the registry of Symbol.for.
	registered bool
}

// StaticValue is the result of getStaticValue: `found` is false where eslint-utils returns null.
// `optional` is set when an optional chain short-circuited (ESLint's `{optional: true}`).
struct StaticValue {
	found    bool
	value    JsAny
	optional bool
}

// StvContext is the state of one evaluation: object identities and the recursion depth.
// `aborted` is set where eslint-utils' evaluation throws: its try/catch is around the whole
// getStaticValue, so the answer is null wherever the exception comes from, and nothing else is
// evaluated. veslint also sets it where it meets something it does not evaluate (the limits of
// the head of this file), so that what an exception would have decided is never guessed. A
// sub-expression that is only "not static" (eslint-utils' null) does not set it.
struct StvContext {
	no_scope  bool // getStaticValue without an initial scope: no identifier is static
	max_steps int  // a bound for tests on the sub-expressions one evaluation may visit (0: none)
mut:
	next_id   int
	depth     int
	aborted   bool
	steps     int
	exhausted bool // the evaluation was aborted by `max_steps`
	// What stv_mutated found for a variable (by its index in the file's scope tree) without
	// evaluating anything, which depends only on the tree.
	mutated map[int]bool
}

// abort ends the evaluation: the value is not static.
fn (mut ctx StvContext) abort() StaticValue {
	ctx.aborted = true
	return StaticValue{}
}

// stv_max_depth bounds the recursion (nested expressions and constants that refer to constants).
// JavaScript would overflow its stack thousands of levels deeper, which eslint-utils catches (not
// static); veslint stops at 100 levels, where its stack is safe even in debug builds (a level of a
// debug build takes about 33 KB of the 8 MB stack, of a -prod build about 12 KB). Like that
// overflow, reaching the limit aborts the whole evaluation: constants that refer to each other
// (`const a = [b, b]; const b = a + a`) are not evaluated any further.
const stv_max_depth = 100

fn stv_found(v JsAny) StaticValue {
	return StaticValue{
		found: true
		value: v
	}
}

fn js_any_undefined() JsAny {
	return JsAny{
		kind: .undefined_
	}
}

fn js_any_bool(b bool) JsAny {
	return JsAny{
		kind:    .boolean_
		boolean: b
	}
}

fn js_any_number(x f64) JsAny {
	return JsAny{
		kind:   .number_
		number: x
	}
}

fn js_any_string(units []u16) JsAny {
	return JsAny{
		kind:  .string_
		units: units
	}
}

fn js_any_text(s string) JsAny {
	return js_any_string(utf16_units(s))
}

fn js_any_bigint(n big.Integer) JsAny {
	return JsAny{
		kind:   .bigint_
		digits: n.str()
	}
}

fn js_any_function(name string) JsAny {
	return JsAny{
		kind: .function_
		name: name
	}
}

fn (mut ctx StvContext) new_id() int {
	ctx.next_id++
	return ctx.next_id
}

// stv_units_string converts UTF-16 units to a V string (a lone surrogate becomes U+FFFD).
fn stv_units_string(units []u16) string {
	mut runes := []rune{cap: units.len}
	mut i := 0
	for i < units.len {
		u := u32(units[i])
		if u >= 0xd800 && u <= 0xdbff && i + 1 < units.len && units[i + 1] >= 0xdc00
			&& units[i + 1] <= 0xdfff {
			runes << rune(0x10000 + ((u - 0xd800) << 10) + (u32(units[i + 1]) - 0xdc00))
			i += 2
			continue
		}
		runes << if u >= 0xd800 && u <= 0xdfff { rune(0xfffd) } else { rune(u) }
		i++
	}
	return runes.string()
}

// stv_key_string is a property key as a V string that keeps every UTF-16 unit: a surrogate
// without its pair is written like any other code point (three bytes, which UTF-8 does not
// allow), so two keys are the same string only if they are the same units. Such a string is
// only compared and read back with stv_key_units.
fn stv_key_string(units []u16) string {
	if units.all(it < 0x80) {
		return units.map(u8(it)).bytestr()
	}
	mut out := []u8{cap: units.len * 3}
	mut i := 0
	for i < units.len {
		mut code := u32(units[i])
		i++
		if code >= 0xd800 && code <= 0xdbff && i < units.len && units[i] >= 0xdc00
			&& units[i] <= 0xdfff {
			code = 0x10000 + ((code - 0xd800) << 10) + (u32(units[i]) - 0xdc00)
			i++
		}
		if code < 0x80 {
			out << u8(code)
		} else if code < 0x800 {
			out << u8(0xc0 | (code >> 6))
			out << u8(0x80 | (code & 0x3f))
		} else if code < 0x10000 {
			out << u8(0xe0 | (code >> 12))
			out << u8(0x80 | ((code >> 6) & 0x3f))
			out << u8(0x80 | (code & 0x3f))
		} else {
			out << u8(0xf0 | (code >> 18))
			out << u8(0x80 | ((code >> 12) & 0x3f))
			out << u8(0x80 | ((code >> 6) & 0x3f))
			out << u8(0x80 | (code & 0x3f))
		}
	}
	return out.bytestr()
}

// stv_key_units gives back the UTF-16 units of a key of stv_key_string (or of any V string).
fn stv_key_units(key string) []u16 {
	mut out := []u16{cap: key.len}
	mut i := 0
	for i < key.len {
		b := u32(key[i])
		mut code := b
		mut size := 1
		if b >= 0xf0 {
			code = b & 0x07
			size = 4
		} else if b >= 0xe0 {
			code = b & 0x0f
			size = 3
		} else if b >= 0xc0 {
			code = b & 0x1f
			size = 2
		}
		for j in 1 .. size {
			if i + j < key.len {
				code = (code << 6) | (u32(key[i + j]) & 0x3f)
			}
		}
		i += size
		jsregexp.append_utf16(mut out, code)
	}
	return out
}

// get_static_value ports getStaticValue(node, initialScope) on the ESTree view of `n`.
fn (mut c Checker) get_static_value(n C.TSNode) StaticValue {
	mut ctx := StvContext{}
	return c.stv_eval_top(n, mut ctx)
}

// stv_eval_top evaluates a whole expression: it is not static if the evaluation was aborted.
fn (mut c Checker) stv_eval_top(n C.TSNode, mut ctx StvContext) StaticValue {
	result := c.stv_eval(n, mut ctx)
	return if ctx.aborted { StaticValue{} } else { result }
}

// get_static_value_bounded is get_static_value with a bound on the sub-expressions visited, for
// tests: it also says whether the bound was reached, and how many were visited.
fn (mut c Checker) get_static_value_bounded(n C.TSNode, max_steps int) (StaticValue, bool, int) {
	mut ctx := StvContext{
		max_steps: max_steps
	}
	result := c.stv_eval_top(n, mut ctx)
	return result, ctx.exhausted, ctx.steps
}

// get_static_value_unscoped ports getStaticValue(node) without an initial scope: no identifier is
// static.
fn (mut c Checker) get_static_value_unscoped(n C.TSNode) StaticValue {
	mut ctx := StvContext{
		no_scope: true
	}
	return c.stv_eval_top(n, mut ctx)
}

// js_any_string_value ports String(value); none for a value veslint cannot convert.
fn js_any_string_value(v JsAny) ?string {
	if v.kind == .symbol_ {
		return stv_units_string(stv_symbol_string(v))
	}
	return stv_units_string(stv_to_string(v)?)
}

// static_member_name ports getStaticMemberAccessValue: the static name of a MemberExpression's
// property or of the key of a property, method or field (a symbol is none, as it never equals a
// name). A value that is not a string is converted like String(value).
fn (mut c Checker) static_member_name(n C.TSNode) ?string {
	key, computed := stv_member_key(n)?
	if !computed {
		match node_kind(key) {
			'property_identifier', 'identifier', 'shorthand_property_identifier' {
				return c.identifier_name(key)
			}
			'private_property_identifier' {
				return c.text(key).trim_left('#')
			}
			else {}
		}
	}
	result := c.get_static_value(key)
	if !result.found || result.value.kind == .symbol_ {
		return none
	}
	return js_any_string_value(result.value)
}

// static_member_string is getStaticMemberAccessValue for the callers that compare it with names
// (`===`, `Set#has`): a value that is not a string never equals one, so it is none.
fn (mut c Checker) static_member_string(n C.TSNode) ?string {
	key, computed := stv_member_key(n)?
	if computed || node_kind(key) !in ['property_identifier', 'identifier',
		'shorthand_property_identifier', 'private_property_identifier'] {
		result := c.get_static_value(key)
		if !result.found || result.value.kind != .string_ {
			return none
		}
	}
	return c.static_member_name(n)
}

// is_static_member_access_of_value ports isStaticMemberAccessOfValue.
fn (mut c Checker) is_static_member_access_of_value(n C.TSNode, values []string) bool {
	name := c.static_member_string(n) or { return false }
	return name in values
}

// stv_member_key gives the property or key node of a member access, property, method or field,
// and whether it is computed (the expression inside a computed key).
fn stv_member_key(n C.TSNode) ?(C.TSNode, bool) {
	match node_kind(n) {
		'member_expression' {
			return node_field(n, 'property')?, false
		}
		'subscript_expression' {
			return node_field(n, 'index')?, true
		}
		'pair', 'pair_pattern' {
			return stv_key_node(node_field(n, 'key')?)
		}
		'method_definition', 'public_field_definition', 'method_signature',
		'property_signature', 'abstract_method_signature' {
			return stv_key_node(node_field(n, 'name')?)
		}
		'shorthand_property_identifier', 'shorthand_property_identifier_pattern' {
			return n, false
		}
		else {
			return none
		}
	}
}

fn stv_key_node(key C.TSNode) ?(C.TSNode, bool) {
	if node_kind(key) == 'computed_property_name' {
		return first_named(key)?, true
	}
	return key, false
}

// property_name ports getPropertyName(node, initialScope) of eslint-utils for a
// MemberExpression, Property, MethodDefinition or PropertyDefinition.
fn (mut c Checker) property_name(n C.TSNode) ?string {
	key, computed := stv_member_key(n)?
	if computed {
		return c.string_if_constant(key)
	}
	match node_kind(key) {
		'private_property_identifier' {
			return none
		}
		'string', 'number' {
			value := c.get_static_value(key)
			return js_any_string_value(value.value)
		}
		else {
			return c.identifier_name(key)
		}
	}
}

// string_if_constant ports getStringIfConstant: a regular expression literal V8 rejects is
// `/pattern/flags`, anything else String(getStaticValue).
fn (mut c Checker) string_if_constant(n C.TSNode) ?string {
	return c.stv_string_if_constant(n, false)
}

// string_if_constant_unscoped is getStringIfConstant without an initial scope, as
// getFunctionNameWithKind calls it: no identifier is static.
fn (mut c Checker) string_if_constant_unscoped(n C.TSNode) ?string {
	return c.stv_string_if_constant(n, true)
}

fn (mut c Checker) stv_string_if_constant(n C.TSNode, no_scope bool) ?string {
	node := unwrap_parens(n)
	mut ctx := StvContext{
		no_scope: no_scope
	}
	result := c.stv_eval_top(node, mut ctx)
	if !result.found {
		return if node_kind(node) == 'regex' { c.text(node) } else { none }
	}
	return js_any_string_value(result.value)
}

// stv_eval ports getStaticValueR: the operations table by ESTree node type.
fn (mut c Checker) stv_eval(n C.TSNode, mut ctx StvContext) StaticValue {
	if ctx.aborted {
		return StaticValue{}
	}
	ctx.steps++
	if ctx.max_steps > 0 && ctx.steps > ctx.max_steps {
		ctx.exhausted = true
		return ctx.abort()
	}
	if ctx.depth > stv_max_depth {
		// JavaScript's stack overflows (a RangeError).
		return ctx.abort()
	}
	ctx.depth++
	mut result := c.stv_eval_node(n, mut ctx)
	ctx.depth--
	if ctx.aborted {
		return StaticValue{}
	}
	// A ChainExpression gives its expression's value without the `optional` mark.
	if result.optional && is_chain_element(n) && is_estree_chain_root(n) {
		result = StaticValue{
			found: result.found
			value: result.value
		}
	}
	return result
}

fn (mut c Checker) stv_eval_node(n C.TSNode, mut ctx StvContext) StaticValue {
	match node_kind(n) {
		'parenthesized_expression', 'as_expression', 'satisfies_expression', 'non_null_expression',
		'instantiation_expression' {
			// Parentheses are not ESTree nodes; the TS wrappers give their expression's value.
			inner := first_named(n) or { return StaticValue{} }
			return c.stv_eval(inner, mut ctx)
		}
		'type_assertion' {
			named := named_children(n)
			if named.len < 2 {
				return StaticValue{}
			}
			return c.stv_eval(named.last(), mut ctx)
		}
		'array' {
			elements := c.stv_array_elements(n, mut ctx) or { return StaticValue{} }
			return stv_found(JsAny{
				kind:     .array_
				id:       ctx.new_id()
				elements: elements
			})
		}
		'assignment_expression' {
			right := node_field(n, 'right') or { return StaticValue{} }
			return c.stv_eval(right, mut ctx)
		}
		'binary_expression' {
			return c.stv_binary(n, mut ctx)
		}
		'call_expression' {
			return c.stv_call(n, mut ctx)
		}
		'ternary_expression' {
			test := c.stv_eval(node_field(n, 'condition') or { return StaticValue{} }, mut
				ctx)
			if !test.found {
				return StaticValue{}
			}
			branch := if stv_to_boolean(test.value) { 'consequence' } else { 'alternative' }
			return c.stv_eval(node_field(n, branch) or { return StaticValue{} }, mut ctx)
		}
		'identifier', 'undefined' {
			return c.stv_identifier(n, mut ctx)
		}
		'string', 'number', 'true', 'false', 'null', 'regex' {
			return c.stv_literal(n, mut ctx)
		}
		'template_string' {
			return c.stv_template(n, mut ctx)
		}
		'member_expression', 'subscript_expression' {
			return c.stv_member(n, mut ctx)
		}
		'new_expression' {
			return c.stv_new(n, mut ctx)
		}
		'object' {
			return c.stv_object(n, mut ctx)
		}
		'sequence_expression' {
			named := named_children(n)
			if named.len == 0 {
				return StaticValue{}
			}
			return c.stv_eval(named.last(), mut ctx)
		}
		'unary_expression' {
			return c.stv_unary(n, mut ctx)
		}
		else {
			return StaticValue{}
		}
	}
}

// stv_identifier ports the Identifier operation: a builtin global (a variable without
// definitions whose name is one of builtinNames) or a constant variable (one Variable definition,
// `const` or never written after its initializer, with an identifier name), whose initializer is
// evaluated; an object value is not static if a reference mutates one of its properties.
fn (mut c Checker) stv_identifier(n C.TSNode, mut ctx StvContext) StaticValue {
	if ctx.no_scope {
		return StaticValue{}
	}
	tree := c.stv_scope_tree(n)
	name := c.identifier_name(n)
	v := tree.find_variable(tree.global_scope(), name, node_start(n))
	if v < 0 {
		return StaticValue{}
	}
	variable := tree.variables[v]
	if variable.defs.len == 0 {
		builtin := stv_builtin_global(name) or { return StaticValue{} }
		return stv_found(builtin)
	}
	if variable.defs.len != 1 {
		return StaticValue{}
	}
	def := variable.defs[0]
	if def.kind != .variable || (def.parent_kind != 'const' && !stv_effectively_const(tree, variable)) {
		return StaticValue{}
	}
	id := def.decl_id or { return StaticValue{} }
	if node_kind(id) != 'identifier' {
		return StaticValue{}
	}
	init_node := def.init or { return StaticValue{} }
	init := c.stv_eval(init_node, mut ctx)
	if init.found
		&& init.value.kind in [.array_, .object_, .regexp_, .namespace_, .map_, .set_, .iterator_]
		&& c.stv_mutated(tree, v, variable, mut ctx) {
		return StaticValue{}
	}
	return init
}

// stv_mutated is stv_has_mutation_in_property for the variable of index `v`, kept for the rest of
// the evaluation when finding it evaluated nothing (no method name to compute): the answer then
// depends only on the tree, and a constant used again (`const b = [a, a]`) does not look at the
// parents of every reference of `a` at each use.
fn (mut c Checker) stv_mutated(tree &ScopeTree, v int, variable ScopeVariable, mut ctx StvContext) bool {
	if known := ctx.mutated[v] {
		return known
	}
	steps := ctx.steps
	mutated := c.stv_has_mutation_in_property(tree, variable, mut ctx)
	if ctx.steps == steps && !ctx.aborted {
		ctx.mutated[v] = mutated
	}
	return mutated
}

// stv_scope_tree is the scope tree of the file of `n`: the one the checker keeps (scope_tree
// builds it once per file, from the root), so that only the first identifier of a file climbs to
// the root (ts_node_parent descends from the root at every step).
fn (mut c Checker) stv_scope_tree(n C.TSNode) &ScopeTree {
	if c.file_scopes != unsafe { nil } {
		return c.file_scopes
	}
	mut root := n
	for {
		root = node_parent(root) or { break }
	}
	return c.scope_tree(root)
}

// stv_effectively_const ports isEffectivelyConst: one initializing write and only reads.
fn stv_effectively_const(tree &ScopeTree, variable ScopeVariable) bool {
	mut inits := 0
	mut reads := 0
	for r in variable.references {
		reference := tree.references[r]
		if reference.init {
			inits++
		} else if reference.is_read_only() {
			reads++
		}
	}
	return inits == 1 && reads + inits == variable.references.len
}

// stv_has_mutation_in_property ports hasMutationInProperty: a reference that, after the member
// accesses around it, is assigned, updated, or the callee of a mutating array method.
fn (mut c Checker) stv_has_mutation_in_property(tree &ScopeTree, variable ScopeVariable, mut ctx StvContext) bool {
	for r in variable.references {
		mut node := tree.references[r].identifier
		for {
			parent := estree_parent(node) or { break }
			if !is_member(parent) {
				break
			}
			node = parent
			// The ESTree parent of an optional chain is its ChainExpression.
			if is_estree_chain_root(node) {
				break
			}
		}
		if is_chain_element(node) && is_estree_chain_root(node) {
			continue
		}
		parent := estree_parent(node) or { continue }
		match node_kind(parent) {
			'assignment_expression', 'augmented_assignment_expression' {
				left := unwrap_parens(node_field(parent, 'left') or { continue })
				if node_key(left) == node_key(node) && node_kind(left) == node_kind(node) {
					return true
				}
			}
			'update_expression' {
				argument := unwrap_parens(node_field(parent, 'argument') or { continue })
				if node_key(argument) == node_key(node) && node_kind(argument) == node_kind(node) {
					return true
				}
			}
			'call_expression' {
				callee := unwrap_parens(node_field(parent, 'function') or { continue })
				args := node_field(parent, 'arguments') or { continue }
				if node_kind(args) != 'arguments' || !is_member(node)
					|| node_key(callee) != node_key(node) || node_kind(callee) != node_kind(node) {
					continue
				}
				key := c.stv_member_property(node, mut ctx) or {
					if ctx.aborted {
						// Evaluating the name of the method throws: so does the whole evaluation.
						return true
					}
					// A name that is not static is not the name of a mutating method.
					continue
				}
				if key.kind == .string_ && stv_units_string(key.units) in ['copyWithin', 'fill',
					'pop', 'push', 'reverse', 'shift', 'sort', 'splice', 'unshift'] {
					return true
				}
			}
			else {}
		}
	}
	return false
}

// stv_builtin_global is the value of a global of eslint-utils' builtinNames.
fn stv_builtin_global(name string) ?JsAny {
	return match name {
		'undefined' { js_any_undefined() }
		'NaN' { js_any_number(math.nan()) }
		'Infinity' { js_any_number(math.inf(1)) }
		'JSON', 'Math', 'Reflect' {
			JsAny{
				kind: .namespace_
				name: name
			}
		}
		'Array', 'ArrayBuffer', 'BigInt', 'BigInt64Array', 'BigUint64Array', 'Boolean', 'DataView',
		'Date', 'decodeURI', 'decodeURIComponent', 'encodeURI', 'encodeURIComponent', 'escape',
		'Float32Array', 'Float64Array', 'Function', 'Int16Array', 'Int32Array', 'Int8Array',
		'isFinite', 'isNaN', 'isPrototypeOf', 'Map', 'Number', 'Object', 'parseFloat', 'parseInt',
		'Promise', 'Proxy', 'RegExp', 'Set', 'String', 'Symbol', 'Uint16Array', 'Uint32Array',
		'Uint8Array', 'Uint8ClampedArray', 'unescape', 'WeakMap', 'WeakSet' {
			js_any_function(name)
		}
		else { none }
	}
}

// stv_literal ports the Literal operation with typescript-estree's values: a regular expression
// is a RegExp only if V8 accepts it (otherwise its value is null and it is not static).
fn (mut c Checker) stv_literal(n C.TSNode, mut ctx StvContext) StaticValue {
	match node_kind(n) {
		'string' {
			quoted := c.text(n)
			if quoted.len < 2 {
				return StaticValue{}
			}
			units := cooked_units(quoted[1..quoted.len - 1], false) or { return StaticValue{} }
			return stv_found(js_any_string(units))
		}
		'number' {
			text := c.text(n).replace('_', '')
			if text.ends_with('n') {
				value := integer_literal(text[..text.len - 1]) or { return StaticValue{} }
				return stv_found(js_any_bigint(value))
			}
			value := if small := small_decimal_literal(text) {
				small
			} else if is_integer_literal(text) {
				integer_to_f64(integer_literal(text) or { return StaticValue{} })
			} else {
				js_atof64(text) or { return StaticValue{} }
			}
			return stv_found(js_any_number(value))
		}
		'true', 'false' {
			return stv_found(js_any_bool(node_kind(n) == 'true'))
		}
		'null' {
			return stv_found(JsAny{
				kind: .null_
			})
		}
		else {
			pattern := node_field(n, 'pattern') or { return StaticValue{} }
			flags := if f := node_field(n, 'flags') { c.text(f) } else { '' }
			re := jsregexp.regexp_new(utf16_units(c.text(pattern)), flags) or { return StaticValue{} }
			return stv_found(JsAny{
				kind:   .regexp_
				id:     ctx.new_id()
				regexp: re
			})
		}
	}
}

// stv_quasis gives the raw texts of the parts of a template between its substitutions, and the
// substitution expressions.
fn (c &Checker) stv_quasis(n C.TSNode) ([]string, []C.TSNode) {
	mut raws := []string{}
	mut expressions := []C.TSNode{}
	mut start := node_start(n) + 1
	for child in children(n) {
		if node_kind(child) == 'template_substitution' {
			raws << c.src[start..node_start(child)]
			start = node_end(child)
			expressions << first_named(child) or { child }
		}
	}
	raws << c.src[start..node_end(n) - 1]
	return raws, expressions
}

// stv_template ports TemplateLiteral: the cooked parts joined with the values as strings.
fn (mut c Checker) stv_template(n C.TSNode, mut ctx StvContext) StaticValue {
	raws, expressions := c.stv_quasis(n)
	values := c.stv_values(expressions, mut ctx) or { return StaticValue{} }
	mut out := cooked_units(raws[0], true) or { return StaticValue{} }
	for i, v in values {
		out << stv_concat_string(v) or { return ctx.abort() }
		out << cooked_units(raws[i + 1], true) or { return StaticValue{} }
	}
	return stv_found(js_any_string(out))
}

// stv_concat_string is ToString(ToPrimitive(value)), what `string + value` appends.
fn stv_concat_string(v JsAny) ?[]u16 {
	return stv_to_string(stv_to_primitive(v)?)
}

// stv_values ports getElementValues on expressions (no holes nor spreads).
fn (mut c Checker) stv_values(nodes []C.TSNode, mut ctx StvContext) ?[]JsAny {
	mut out := []JsAny{}
	for node in nodes {
		v := c.stv_eval(node, mut ctx)
		if !v.found {
			return none
		}
		out << v.value
	}
	return out
}

// stv_element_values ports getElementValues on a list of elements that may include spreads.
fn (mut c Checker) stv_element_values(nodes []C.TSNode, mut ctx StvContext) ?[]JsAny {
	mut out := []JsAny{}
	for node in nodes {
		if node_kind(node) == 'spread_element' {
			arg := c.stv_eval(first_named(node)?, mut ctx)
			if !arg.found {
				return none
			}
			// What is not iterable throws.
			out << stv_iterate(arg.value, mut ctx) or {
				ctx.aborted = true
				return none
			}
			continue
		}
		v := c.stv_eval(node, mut ctx)
		if !v.found {
			return none
		}
		out << v.value
	}
	return out
}

// stv_iterate spreads an iterable: the elements of an array (holes are undefined), the code
// points of a string, the entries of a Map (a new array of the key and the value for each), the
// values of a Set or what is left of an iterator. Other values are not iterable (a TypeError),
// or are through a @@iterator property, which veslint does not read.
fn stv_iterate(v JsAny, mut ctx StvContext) ?[]JsAny {
	match v.kind {
		.array_ {
			return v.elements.map(if it.kind == .hole_ { js_any_undefined() } else { it })
		}
		.map_ {
			mut out := []JsAny{cap: v.elements.len}
			for i, key in v.elements {
				out << ctx.new_array([key, v.values[i]])
			}
			return out
		}
		.set_, .iterator_ {
			return v.elements
		}
		.wrapper_ {
			// A String object iterates as its string; the others are not iterable.
			if v.elements[0].kind == .string_ {
				return stv_iterate(v.elements[0], mut ctx)
			}
			return none
		}
		.object_ {
			// The @@iterator an array in its prototypes gives (Array.prototype.values, which
			// reads it as an array-like object); the others are not iterable here.
			mut prototype := v
			for prototype.kind == .object_ && prototype.elements.len > 0 {
				prototype = prototype.elements[0]
			}
			if prototype.kind != .array_ || prototype.id == v.id {
				return none
			}
			return (stv_array_like(v)?).map(if it.kind == .hole_ { js_any_undefined() } else { it })
		}
		.string_ {
			mut out := []JsAny{}
			mut i := 0
			for i < v.units.len {
				u := v.units[i]
				if u >= 0xd800 && u <= 0xdbff && i + 1 < v.units.len && v.units[i + 1] >= 0xdc00
					&& v.units[i + 1] <= 0xdfff {
					out << js_any_string(v.units[i..i + 2])
					i += 2
					continue
				}
				out << js_any_string([u])
				i++
			}
			return out
		}
		else {
			return none
		}
	}
}

// stv_array_elements gives the elements of an ArrayExpression, with its holes.
fn (mut c Checker) stv_array_elements(n C.TSNode, mut ctx StvContext) ?[]JsAny {
	mut out := []JsAny{}
	mut expect_element := true
	for child in children(n) {
		kind := node_kind(child)
		if kind == ',' {
			if expect_element {
				out << JsAny{
					kind: .hole_
				}
			}
			expect_element = true
			continue
		}
		if !C.ts_node_is_named(child) || kind == 'comment' {
			continue
		}
		out << c.stv_element_values([child], mut ctx)?
		expect_element = false
	}
	return out
}

// stv_object ports ObjectExpression: init properties with static keys and values, and spreads.
fn (mut c Checker) stv_object(n C.TSNode, mut ctx StvContext) StaticValue {
	mut keys := []string{}
	mut values := []JsAny{}
	mut prototype := []JsAny{}
	for prop in named_children(n) {
		match node_kind(prop) {
			'pair' {
				key_node := node_field(prop, 'key') or { return StaticValue{} }
				key_value := c.stv_property_key(key_node, mut ctx) or { return StaticValue{} }
				value := c.stv_eval(node_field(prop, 'value') or { return StaticValue{} }, mut
					ctx)
				if !value.found {
					return StaticValue{}
				}
				// `object[key] = value`: the key is converted now (which may throw). A symbol key
				// is not modelled. eslint-utils defines every property with that assignment, so a
				// `__proto__` key calls Object.prototype's setter in any form (computed and
				// shorthand too): an object or null becomes the prototype, another value is
				// ignored.
				if key_value.kind == .symbol_ {
					return ctx.abort()
				}
				key := stv_key_string(stv_to_string(stv_to_primitive_hint(key_value, 'string') or {
					return ctx.abort()
				}) or { return ctx.abort() })
				stv_define(mut keys, mut values, mut prototype, key, value.value)
			}
			'shorthand_property_identifier' {
				value := c.stv_identifier(prop, mut ctx)
				if !value.found {
					return StaticValue{}
				}
				stv_define(mut keys, mut values, mut prototype, c.identifier_name(prop), value.value)
			}
			'spread_element' {
				arg := c.stv_eval(first_named(prop) or { return StaticValue{} }, mut ctx)
				if !arg.found {
					return StaticValue{}
				}
				stv_assign(mut keys, mut values, mut prototype, arg.value) or { return ctx.abort() }
			}
			else {
				// Methods, getters and setters are not static.
				return StaticValue{}
			}
		}
	}
	return stv_found(JsAny{
		kind:     .object_
		id:       ctx.new_id()
		keys:     keys
		values:   values
		elements: prototype
	})
}

// stv_define ports `object[key] = value` on the object literal being built: a `__proto__` key
// calls the setter of Object.prototype.__proto__ when the object still inherits it (an object or
// null becomes the prototype, another value is ignored), and is an own property otherwise.
fn stv_define(mut keys []string, mut values []JsAny, mut prototype []JsAny, key string, value JsAny) {
	if key == '__proto__' && key !in keys && stv_inherits_proto_setter(prototype) {
		if stv_is_object(value) || value.kind == .null_ {
			prototype = [value]
		}
		return
	}
	stv_set_key(mut keys, mut values, key, value)
}

// stv_inherits_proto_setter: the prototype chain reaches the `__proto__` accessor of
// Object.prototype, with no `__proto__` data property before it.
fn stv_inherits_proto_setter(prototype []JsAny) bool {
	if prototype.len == 0 {
		return true
	}
	p := prototype[0]
	return match p.kind {
		.null_ { false }
		.object_ { '__proto__' !in p.keys && stv_inherits_proto_setter(p.elements) }
		else { true }
	}
}

// stv_has_property ports HasProperty for an array index through the prototype chain: own
// elements of arrays and String objects, own keys of plain objects and of their prototypes.
fn stv_has_property(v JsAny, key string) bool {
	return match v.kind {
		.object_ {
			key in v.keys || (v.elements.len > 0 && stv_has_property(v.elements[0], key))
		}
		.array_ {
			i := stv_canonical_index(key)
			i >= 0 && i < v.elements.len && v.elements[i].kind != .hole_
		}
		.wrapper_ {
			i := stv_canonical_index(key)
			v.elements[0].kind == .string_ && i >= 0 && i < v.elements[0].units.len
		}
		else {
			false
		}
	}
}

// stv_to_string_tag is the @@toStringTag an object inherits through the prototypes of a plain
// object, as Object.prototype.toString reads it ('' when there is none).
fn stv_to_string_tag(v JsAny) string {
	return match v.kind {
		.object_ {
			if v.elements.len > 0 { stv_to_string_tag(v.elements[0]) } else { '' }
		}
		.map_ {
			'Map'
		}
		.set_ {
			'Set'
		}
		.iterator_, .namespace_ {
			v.name
		}
		.wrapper_ {
			match v.elements[0].kind {
				.symbol_ { 'Symbol' }
				.bigint_ { 'BigInt' }
				else { '' }
			}
		}
		else {
			''
		}
	}
}

// stv_property_key ports getStaticPropertyNameValue for a Property: its name, String(value) of a
// literal key, or the value of a computed key. none: the key is not static.
fn (mut c Checker) stv_property_key(key C.TSNode, mut ctx StvContext) ?JsAny {
	match node_kind(key) {
		'property_identifier' {
			return js_any_text(c.identifier_name(key))
		}
		'computed_property_name' {
			v := c.stv_eval(first_named(key)?, mut ctx)
			if !v.found {
				return none
			}
			return v.value
		}
		else {
			// A string or a number: its String(value).
			v := c.stv_eval(key, mut ctx)
			if !v.found {
				return none
			}
			return js_any_string(stv_to_string(v.value)?)
		}
	}
}

// stv_set_key sets a property of an object, with OrdinaryOwnPropertyKeys' order: array indexes
// first, ascending, then the other keys in insertion order.
fn stv_set_key(mut keys []string, mut values []JsAny, key string, value JsAny) {
	i := keys.index(key)
	if i >= 0 {
		values[i] = value
		return
	}
	index := stv_canonical_index(key)
	if index < 0 {
		keys << key
		values << value
		return
	}
	mut at := 0
	for at < keys.len {
		other := stv_canonical_index(keys[at])
		if other < 0 || other > index {
			break
		}
		at++
	}
	keys.insert(at, key)
	values.insert(at, value)
}

// stv_assign ports Object.assign(target, source) for the own enumerable properties of a source.
fn stv_assign(mut keys []string, mut values []JsAny, mut prototype []JsAny, source JsAny) ? {
	match source.kind {
		.array_ {
			for i, e in source.elements {
				if e.kind != .hole_ {
					stv_set_key(mut keys, mut values, i.str(), e)
				}
			}
		}
		.string_ {
			for i, u in source.units {
				stv_set_key(mut keys, mut values, i.str(), js_any_string([u]))
			}
		}
		.object_ {
			for i, k in source.keys {
				stv_define(mut keys, mut values, mut prototype, k, source.values[i])
			}
		}
		.wrapper_ {
			// The indexes of a String object; nothing from the others.
			stv_assign(mut keys, mut values, mut prototype, source.elements[0])?
		}
		.undefined_, .null_, .boolean_, .number_, .bigint_, .symbol_, .regexp_, .function_,
		.namespace_, .map_, .set_, .iterator_ {
		}
		.hole_ {
			return none
		}
	}
}

// stv_member ports MemberExpression.
fn (mut c Checker) stv_member(n C.TSNode, mut ctx StvContext) StaticValue {
	property := node_field(n, if node_kind(n) == 'member_expression' { 'property' } else { 'index' }) or {
		return StaticValue{}
	}
	if node_kind(property) == 'private_property_identifier' {
		return StaticValue{}
	}
	object := c.stv_eval(node_field(n, 'object') or { return StaticValue{} }, mut ctx)
	if !object.found {
		return StaticValue{}
	}
	if stv_is_nullish(object.value) && (object.optional || is_optional_element(n)) {
		return StaticValue{
			found:    true
			value:    js_any_undefined()
			optional: true
		}
	}
	key := c.stv_member_property(n, mut ctx) or { return StaticValue{} }
	if stv_rejected_getter(object.value, key, false) {
		return StaticValue{}
	}
	// A property of undefined or null throws.
	value := stv_get(object.value, key) or { return ctx.abort() }
	return stv_found(value)
}

// stv_rejected_getter: the property is a getter that eslint-utils' MemberExpression does not
// read: isGetter finds it in the object or in its prototypes, and it is not one of getterAllowed
// for the object. The member is then not static, without an exception. A primitive has no
// getter for isGetter. With `called`, the getter is one that a CallExpression runs to read the
// function it calls (`receiver[methodName]`) and that gives something else without throwing:
// not the ones of Function.prototype, which throw for a builtin function.
fn stv_rejected_getter(object JsAny, key_value JsAny, called bool) bool {
	if !stv_is_object(object) || key_value.kind == .symbol_ {
		return false
	}
	key := stv_key_string(stv_to_string(stv_to_primitive_hint(key_value, 'string') or {
		return false
	}) or {
		return false
	})
	// Object.prototype.__proto__, which an object literal may no longer inherit (a null
	// prototype) or may have as its own data property.
	if key == '__proto__' {
		return object.kind != .object_
			|| (key !in object.keys && stv_inherits_proto_setter(object.elements))
	}
	// getterAllowed has the names as strings: another value that names the getter
	// (`re[['source']]`) is not one of them.
	named := key_value.kind == .string_
	return match object.kind {
		.regexp_ { key == 'unicodeSets' || (key in stv_regexp_getters && !named) }
		.map_, .set_ { key == 'size' && !named }
		// Function.prototype.arguments and caller, and the legacy static properties of RegExp.
		.function_ {
			(!called && key in ['arguments', 'caller']) || (object.name == 'RegExp'
				&& key in stv_regexp_legacy_getters)
		}
		// Iterator.prototype.constructor, Symbol.prototype.description.
		.iterator_ { key == 'constructor' }
		.wrapper_ { object.elements[0].kind == .symbol_ && key == 'description' }
		else { false }
	}
}

// stv_member_property ports getStaticPropertyNameValue for a MemberExpression.
fn (mut c Checker) stv_member_property(n C.TSNode, mut ctx StvContext) ?JsAny {
	if node_kind(n) == 'subscript_expression' {
		v := c.stv_eval(node_field(n, 'index')?, mut ctx)
		if !v.found {
			return none
		}
		return v.value
	}
	return js_any_text(c.identifier_name(node_field(n, 'property')?))
}

fn stv_is_nullish(v JsAny) bool {
	return v.kind == .undefined_ || v.kind == .null_
}

// stv_new ports NewExpression: `new RegExp(…)`, `new Map(…)`, `new Set(…)` and `new Object(…)`
// are evaluated.
fn (mut c Checker) stv_new(n C.TSNode, mut ctx StvContext) StaticValue {
	callee := c.stv_eval(node_field(n, 'constructor') or { return StaticValue{} }, mut ctx)
	mut args := []JsAny{}
	if arguments := node_field(n, 'arguments') {
		args = c.stv_element_values(named_children(arguments), mut ctx) or {
			return StaticValue{}
		}
	}
	// Only a function of callAllowed is constructed.
	if !callee.found || callee.value.kind != .function_ || callee.value.name !in stv_call_allowed {
		return StaticValue{}
	}
	name := callee.value.name
	if name == 'RegExp' {
		return stv_found(stv_regexp_construct(args, true, mut ctx) or { return ctx.abort() })
	}
	if name in ['Map', 'Set'] {
		return stv_found(stv_collection_construct(name == 'Map', args, mut ctx) or {
			return ctx.abort()
		})
	}
	if name == 'Object' {
		return stv_found(stv_object_call(args, mut ctx) or { return ctx.abort() })
	}
	if name in ['String', 'Number', 'Boolean'] {
		// The object of the primitive the call gives; but `new String(symbol)` converts the
		// symbol with ToString, a TypeError.
		if name == 'String' && args.len > 0 && args[0].kind == .symbol_ {
			return ctx.abort()
		}
		p := stv_call_function(callee.value, js_any_undefined(), false, args, mut ctx) or {
			return ctx.abort()
		}
		return stv_found(JsAny{
			kind:     .wrapper_
			id:       ctx.new_id()
			elements: [p]
		})
	}
	// What is not a constructor throws; `new Date` is not evaluated.
	return ctx.abort()
}

// stv_call ports CallExpression and, for a tagged template, TaggedTemplateExpression.
fn (mut c Checker) stv_call(n C.TSNode, mut ctx StvContext) StaticValue {
	function := node_field(n, 'function') or { return StaticValue{} }
	args_node := node_field(n, 'arguments') or { return StaticValue{} }
	if node_kind(args_node) == 'template_string' {
		return c.stv_tagged_template(function, args_node, mut ctx)
	}
	args := c.stv_element_values(named_children(args_node), mut ctx) or { return StaticValue{} }
	optional_call := is_optional_element(n)
	callee := unwrap_parens(function)
	// `(a?.b)()`: the parentheses end the chain, so the callee is a ChainExpression and not a
	// MemberExpression: the function is called without a receiver.
	parenthesized_chain := node_key(callee) != node_key(function) && is_chain_element(callee)
		&& is_estree_chain_root(callee)
	if node_kind(callee) in ['member_expression', 'subscript_expression'] && !parenthesized_chain {
		property := node_field(callee, if node_kind(callee) == 'member_expression' {
			'property'
		} else {
			'index'
		}) or { return StaticValue{} }
		if node_kind(property) == 'private_property_identifier' {
			return StaticValue{}
		}
		object := c.stv_eval(node_field(callee, 'object') or { return StaticValue{} }, mut
			ctx)
		if !object.found {
			return StaticValue{}
		}
		if stv_is_nullish(object.value) && (object.optional || optional_call) {
			return StaticValue{
				found:    true
				value:    js_any_undefined()
				optional: true
			}
		}
		key := c.stv_member_property(callee, mut ctx) or { return StaticValue{} }
		// receiver[methodName] is a plain read: a getter runs, and what one of
		// stv_rejected_getter gives is not a function of callAllowed.
		method := stv_get(object.value, key) or {
			if stv_rejected_getter(object.value, key, true) {
				return StaticValue{}
			}
			return ctx.abort()
		}
		return stv_call_value(method, object.value, true, args, mut ctx)
	}
	callee_value := c.stv_eval(function, mut ctx)
	if !callee_value.found {
		return StaticValue{}
	}
	if stv_is_nullish(callee_value.value) && optional_call {
		return StaticValue{
			found:    true
			value:    js_any_undefined()
			optional: true
		}
	}
	return stv_call_value(callee_value.value, js_any_undefined(), false, args, mut ctx)
}

// stv_call_value ports what CallExpression does with the value of the callee: only a function of
// callAllowed or callPassThrough is called (anything else, like `undefined()`, is not static,
// without an exception); the call may throw.
fn stv_call_value(f JsAny, this JsAny, has_receiver bool, args []JsAny, mut ctx StvContext) StaticValue {
	if f.kind != .function_ || (f.name !in stv_call_allowed && f.name !in stv_call_pass_through) {
		return StaticValue{}
	}
	value := stv_call_function(f, this, has_receiver, args, mut ctx) or { return ctx.abort() }
	return stv_found(value)
}

// stv_tagged_template ports TaggedTemplateExpression: only String.raw.
fn (mut c Checker) stv_tagged_template(tag C.TSNode, template C.TSNode, mut ctx StvContext) StaticValue {
	tag_value := c.stv_eval(tag, mut ctx)
	raws, expressions := c.stv_quasis(template)
	values := c.stv_values(expressions, mut ctx) or { return StaticValue{} }
	if !tag_value.found || tag_value.value.kind != .function_
		|| tag_value.value.name != 'String.raw' {
		return StaticValue{}
	}
	mut out := []u16{}
	for i, raw in raws {
		out << utf16_units(raw.replace('\r\n', '\n').replace('\r', '\n'))
		if i < values.len {
			out << stv_to_string(values[i]) or { return ctx.abort() }
		}
	}
	return stv_found(js_any_string(out))
}

// stv_unary ports UnaryExpression.
fn (mut c Checker) stv_unary(n C.TSNode, mut ctx StvContext) StaticValue {
	operator := operator_of(n)
	if operator == 'delete' {
		return StaticValue{}
	}
	if operator == 'void' {
		return stv_found(js_any_undefined())
	}
	arg := c.stv_eval(node_field(n, 'argument') or { return StaticValue{} }, mut ctx)
	if !arg.found {
		return StaticValue{}
	}
	v := arg.value
	match operator {
		'-' {
			p := stv_to_numeric(v) or { return ctx.abort() }
			if p.kind == .bigint_ {
				return stv_found(js_any_bigint((js_bigint(p.digits) or { return StaticValue{} }).neg()))
			}
			return stv_found(js_any_number(-p.number))
		}
		'+' {
			// A TypeError for a BigInt.
			if v.kind == .bigint_ {
				return ctx.abort()
			}
			return stv_found(js_any_number(stv_to_number(v) or { return ctx.abort() }))
		}
		'!' {
			return stv_found(js_any_bool(!stv_to_boolean(v)))
		}
		'~' {
			p := stv_to_numeric(v) or { return ctx.abort() }
			if p.kind == .bigint_ {
				x := js_bigint(p.digits) or { return StaticValue{} }
				return stv_found(js_any_bigint(x.neg() - big.one_int))
			}
			return stv_found(js_any_number(f64(~stv_to_int32(p.number))))
		}
		'typeof' {
			return stv_found(js_any_text(stv_typeof(v)))
		}
		else {
			return StaticValue{}
		}
	}
}

fn stv_typeof(v JsAny) string {
	return match v.kind {
		.undefined_, .hole_ { 'undefined' }
		.null_, .array_, .object_, .regexp_, .namespace_, .map_, .set_, .iterator_, .wrapper_ {
			'object'
		}
		.boolean_ { 'boolean' }
		.number_ { 'number' }
		.string_ { 'string' }
		.bigint_ { 'bigint' }
		.symbol_ { 'symbol' }
		.function_ { 'function' }
	}
}

// stv_binary ports LogicalExpression and BinaryExpression.
fn (mut c Checker) stv_binary(n C.TSNode, mut ctx StvContext) StaticValue {
	operator := operator_of(n)
	left_node := node_field(n, 'left') or { return StaticValue{} }
	right_node := node_field(n, 'right') or { return StaticValue{} }
	if operator in ['&&', '||', '??'] {
		left := c.stv_eval(left_node, mut ctx)
		if !left.found {
			return StaticValue{}
		}
		truthy := stv_to_boolean(left.value)
		if (operator == '||' && truthy) || (operator == '&&' && !truthy)
			|| (operator == '??' && !stv_is_nullish(left.value)) {
			return left
		}
		right := c.stv_eval(right_node, mut ctx)
		return if right.found { right } else { StaticValue{} }
	}
	if operator in ['in', 'instanceof'] {
		return StaticValue{}
	}
	left := c.stv_eval(left_node, mut ctx)
	right := c.stv_eval(right_node, mut ctx)
	if !left.found || !right.found {
		return StaticValue{}
	}
	value := stv_binary_operation(operator, left.value, right.value) or { return ctx.abort() }
	return stv_found(value)
}

// stv_binary_operation applies a binary operator with JavaScript semantics; none when it
// throws.
fn stv_binary_operation(operator string, a JsAny, b JsAny) ?JsAny {
	match operator {
		'===' {
			return js_any_bool(stv_strict_equal(a, b))
		}
		'!==' {
			return js_any_bool(!stv_strict_equal(a, b))
		}
		'==' {
			return js_any_bool(stv_loose_equal(a, b)?)
		}
		'!=' {
			return js_any_bool(!stv_loose_equal(a, b)?)
		}
		'<', '>', '<=', '>=' {
			x := stv_to_primitive_hint(a, 'number')?
			y := stv_to_primitive_hint(b, 'number')?
			if x.kind == .symbol_ || y.kind == .symbol_ {
				return none
			}
			if x.kind == .string_ && y.kind == .string_ {
				less := stv_units_less(x.units, y.units)
				greater := stv_units_less(y.units, x.units)
				return js_any_bool(match operator {
					'<' { less }
					'>' { greater }
					'<=' { !greater }
					else { !less }
				})
			}
			return js_any_bool(js_compare(stv_js_value(x)?, operator, stv_js_value(y)?))
		}
		'+' {
			x := stv_to_primitive(a)?
			y := stv_to_primitive(b)?
			if x.kind == .string_ || y.kind == .string_ {
				mut out := stv_to_string(x)?.clone()
				out << stv_to_string(y)?
				return js_any_string(out)
			}
			return stv_numeric_operation(operator, x, y)
		}
		'-', '*', '/', '%', '**', '<<', '>>', '>>>', '&', '|', '^' {
			return stv_numeric_operation(operator, stv_to_primitive_hint(a, 'number')?,
				stv_to_primitive_hint(b, 'number')?)
		}
		else {
			return none
		}
	}
}

fn stv_units_less(a []u16, b []u16) bool {
	for i in 0 .. math.min(a.len, b.len) {
		if a[i] != b[i] {
			return a[i] < b[i]
		}
	}
	return a.len < b.len
}

// stv_numeric_operation applies an arithmetic, shift or bitwise operator to two primitives.
fn stv_numeric_operation(operator string, a JsAny, b JsAny) ?JsAny {
	x := stv_to_numeric(a)?
	y := stv_to_numeric(b)?
	if x.kind != y.kind {
		return none
	}
	if x.kind == .bigint_ {
		return stv_bigint_operation(operator, js_bigint(x.digits)?, js_bigint(y.digits)?)
	}
	p := x.number
	q := y.number
	return js_any_number(match operator {
		'+' {
			p + q
		}
		'-' {
			p - q
		}
		'*' {
			p * q
		}
		'/' {
			p / q
		}
		'%' {
			stv_remainder(p, q)
		}
		'**' {
			stv_power(p, q)
		}
		'<<' {
			f64(stv_to_int32(p) << (stv_to_uint32(q) & 31))
		}
		'>>' {
			f64(stv_to_int32(p) >> (stv_to_uint32(q) & 31))
		}
		'>>>' {
			f64(stv_to_uint32(p) >> (stv_to_uint32(q) & 31))
		}
		'&' {
			f64(stv_to_int32(p) & stv_to_int32(q))
		}
		'|' {
			f64(stv_to_int32(p) | stv_to_int32(q))
		}
		else {
			f64(stv_to_int32(p) ^ stv_to_int32(q))
		}
	})
}

// stv_remainder is JavaScript's `%` (the sign of the dividend, like C's fmod).
fn stv_remainder(p f64, q f64) f64 {
	if math.is_nan(p) || math.is_nan(q) || math.is_inf(p, 0) || q == 0 {
		return math.nan()
	}
	if math.is_inf(q, 0) || p == 0 {
		return p
	}
	return math.fmod(p, q)
}

// stv_power is Number::exponentiate as V8 computes it, for `**` and for Math.pow: it differs from
// C's pow with NaN and ±1 ** ±Infinity, and V8 does not call pow for the exponents 2 and 0.5,
// where the C library's result may be one unit in the last place away.
fn stv_power(p f64, q f64) f64 {
	if math.is_nan(q) {
		return math.nan()
	}
	if q == 0 {
		return 1
	}
	if (p == 1 || p == -1) && math.is_inf(q, 0) {
		return math.nan()
	}
	if q == 2 {
		return p * p
	}
	if q == 0.5 {
		// V8's sqrt(p + 0), and Infinity for both infinities: +0 for -0, where sqrt keeps the sign.
		if math.is_inf(p, 0) {
			return math.inf(1)
		}
		if p == 0 {
			return 0
		}
		return math.sqrt(p)
	}
	return math.pow(p, q)
}

fn stv_bigint_operation(operator string, x big.Integer, y big.Integer) ?JsAny {
	match operator {
		'+' {
			return js_any_bigint(x + y)
		}
		'-' {
			return js_any_bigint(x - y)
		}
		'*' {
			return js_any_bigint(x * y)
		}
		'/', '%' {
			if y.signum == 0 {
				return none
			}
			// math.big truncates toward zero and gives the remainder the dividend's sign, like
			// JavaScript.
			return js_any_bigint(if operator == '/' { x / y } else { x % y })
		}
		'**' {
			// A RangeError for a negative exponent; 0n, 1n and -1n to any power are computed
			// before V8 looks at the size of the exponent. Above stv_bigint_max_bits the value
			// is not evaluated (V8 computes up to 2^30 bits, and throws beyond).
			if y.signum < 0 {
				return none
			}
			if y.signum == 0 {
				return js_any_bigint(big.one_int)
			}
			if x.signum == 0 {
				return js_any_bigint(x)
			}
			if x.abs_cmp(big.one_int) == 0 {
				return js_any_bigint(if x.signum < 0 && !y.is_odd() { big.one_int } else { x })
			}
			if y.bit_len() > 31 {
				return none
			}
			e := u32(y.int())
			if u64(x.bit_len() - 1) * u64(e) >= stv_bigint_max_bits {
				return none
			}
			return js_any_bigint(x.pow(e))
		}
		'<<', '>>' {
			// A negative amount shifts the other way. Left: a RangeError beyond 2^30 bits, and
			// not evaluated beyond stv_bigint_max_bits; right: rounded toward minus infinity, 0n
			// or -1n for any amount past the bits of x.
			left := (operator == '<<') == (y.signum >= 0)
			amount := y.abs()
			if x.signum == 0 || amount.signum == 0 {
				return js_any_bigint(x)
			}
			if left {
				if amount.bit_len() > 31
					|| u64(x.bit_len()) + u64(amount.int()) > stv_bigint_max_bits {
					return none
				}
				return js_any_bigint(x.left_shift(u32(amount.int())))
			}
			if amount.bit_len() > 31 || amount.int() >= x.bit_len() {
				return js_any_bigint(if x.signum < 0 { big.one_int.neg() } else { big.zero_int })
			}
			n := u32(amount.int())
			if x.signum < 0 {
				return js_any_bigint(x.bitwise_com().right_shift(n).bitwise_com())
			}
			return js_any_bigint(x.right_shift(n))
		}
		'&', '|', '^' {
			return js_any_bigint(stv_bigint_bitwise(operator, x, y))
		}
		else {
			return none
		}
	}
}

// stv_bigint_max_bits bounds the BigInts veslint computes with `**` and `<<`: V8 goes up to 2^30
// bits, but writing the decimal digits of a BigInt takes a time that grows with the square of its
// length (17 ms for 2^16 bits, 3.6 s for 2^20).
const stv_bigint_max_bits = u64(1) << 16

// stv_bigint_bitwise ports `&`, `|` and `^` on BigInts, which work on infinite two's complement.
// math.big works on magnitudes: with a = x or ~x and b = y or ~y, whichever is not negative,
// each case is an operation on a and b (~v = -v - 1).
fn stv_bigint_bitwise(operator string, x big.Integer, y big.Integer) big.Integer {
	x_negative := x.signum < 0
	y_negative := y.signum < 0
	a := if x_negative { x.bitwise_com() } else { x }
	b := if y_negative { y.bitwise_com() } else { y }
	match operator {
		'&' {
			if !x_negative && !y_negative {
				return a.bitwise_and(b)
			}
			if x_negative && y_negative {
				// ~a & ~b = ~(a | b)
				return a.bitwise_or(b).bitwise_com()
			}
			// ~a & b = b - (a & b), and a & ~b = a - (a & b).
			return if x_negative { b - a.bitwise_and(b) } else { a - a.bitwise_and(b) }
		}
		'|' {
			if !x_negative && !y_negative {
				return a.bitwise_or(b)
			}
			if x_negative && y_negative {
				// ~a | ~b = ~(a & b)
				return a.bitwise_and(b).bitwise_com()
			}
			// ~a | b = ~(a & ~b) = ~(a - (a & b)), and a | ~b = ~(b - (a & b)).
			return if x_negative {
				(a - a.bitwise_and(b)).bitwise_com()
			} else {
				(b - a.bitwise_and(b)).bitwise_com()
			}
		}
		else {
			// ~a ^ b = ~(a ^ b), and ~a ^ ~b = a ^ b.
			r := a.bitwise_xor(b)
			return if x_negative != y_negative { r.bitwise_com() } else { r }
		}
	}
}

fn stv_to_uint32(x f64) u32 {
	if math.is_nan(x) || math.is_inf(x, 0) {
		return 0
	}
	t := math.trunc(x)
	m := math.fmod(t, 4294967296.0)
	return u32(i64(if m < 0 { m + 4294967296.0 } else { m }))
}

fn stv_to_int32(x f64) i32 {
	return i32(stv_to_uint32(x))
}

// stv_js_value converts a primitive to the JsValue of js_values.v; none for a symbol.
fn stv_js_value(v JsAny) ?JsValue {
	return match v.kind {
		.undefined_, .hole_ {
			JsValue{
				kind: .undefined_
			}
		}
		.null_ {
			JsValue{
				kind: .null_
			}
		}
		.boolean_ {
			JsValue{
				kind:    .boolean_
				boolean: v.boolean
			}
		}
		.number_ {
			JsValue{
				kind:   .number_
				number: v.number
			}
		}
		.string_ {
			JsValue{
				kind: .string_
				text: stv_units_string(v.units)
			}
		}
		.bigint_ {
			JsValue{
				kind: .bigint_
				text: v.digits
			}
		}
		else { none }
	}
}

fn stv_is_object(v JsAny) bool {
	return v.kind in [.array_, .object_, .regexp_, .function_, .namespace_, .map_, .set_, .iterator_,
		.wrapper_]
}

// stv_same_object: two object values are the same object.
fn stv_same_object(a JsAny, b JsAny) bool {
	if a.kind != b.kind {
		return false
	}
	return match a.kind {
		.function_, .namespace_ { a.name == b.name }
		else { a.id == b.id }
	}
}

// stv_same_symbol: two symbols are the same symbol, a well-known one by its name and one of
// Symbol.for by its key.
fn stv_same_symbol(a JsAny, b JsAny) bool {
	return a.kind == .symbol_ && b.kind == .symbol_ && a.registered == b.registered
		&& a.name == b.name && a.units == b.units
}

// stv_symbol_description is the [[Description]] of a symbol.
fn stv_symbol_description(v JsAny) []u16 {
	return if v.registered { v.units } else { utf16_units(v.name) }
}

// stv_symbol_string is SymbolDescriptiveString: `Symbol(` and the description and `)`.
fn stv_symbol_string(v JsAny) []u16 {
	mut out := utf16_units('Symbol(')
	out << stv_symbol_description(v)
	out << u16(`)`)
	return out
}

// stv_strict_equal ports IsStrictlyEqual.
fn stv_strict_equal(a JsAny, b JsAny) bool {
	if stv_is_object(a) || stv_is_object(b) {
		return stv_same_object(a, b)
	}
	if a.kind == .symbol_ || b.kind == .symbol_ {
		return stv_same_symbol(a, b)
	}
	if a.kind == .string_ && b.kind == .string_ {
		return a.units == b.units
	}
	x := stv_js_value(a) or { return false }
	y := stv_js_value(b) or { return false }
	return js_strict_equal(x, y)
}

// stv_loose_equal ports IsLooselyEqual; none when ToPrimitive throws.
fn stv_loose_equal(a JsAny, b JsAny) ?bool {
	if stv_is_object(a) && stv_is_object(b) {
		return stv_same_object(a, b)
	}
	if stv_is_nullish(a) || stv_is_nullish(b) || a.kind == .hole_ || b.kind == .hole_ {
		return (stv_is_nullish(a) || a.kind == .hole_) && (stv_is_nullish(b) || b.kind == .hole_)
	}
	x := if stv_is_object(a) { stv_to_primitive(a)? } else { a }
	y := if stv_is_object(b) { stv_to_primitive(b)? } else { b }
	if x.kind == .symbol_ || y.kind == .symbol_ {
		return stv_same_symbol(x, y)
	}
	if x.kind == .string_ && y.kind == .string_ {
		return x.units == y.units
	}
	return js_loose_equal(stv_js_value(x)?, stv_js_value(y)?)
}

// stv_to_boolean ports ToBoolean.
fn stv_to_boolean(v JsAny) bool {
	return match v.kind {
		.undefined_, .null_, .hole_ { false }
		.boolean_ { v.boolean }
		.number_ { v.number != 0 && !math.is_nan(v.number) }
		.string_ { v.units.len > 0 }
		.bigint_ { v.digits != '0' }
		else { true }
	}
}

// stv_to_primitive ports ToPrimitive for the modelled objects: an array is its join, a plain
// object `[object Object]`, a RegExp its toString, a builtin function its native source, and a
// Map, a Set or an iterator `[object ` and its @@toStringTag.
// An object with its own toString or valueOf is converted by them (stv_ordinary_to_primitive),
// in the order the hint asks.
fn stv_to_primitive(v JsAny) ?JsAny {
	return stv_to_primitive_hint(v, 'default')
}

fn stv_to_primitive_hint(v JsAny, hint string) ?JsAny {
	match v.kind {
		.array_ {
			return js_any_string(stv_join(v, [u16(`,`)])?)
		}
		.object_ {
			if 'toString' in v.keys || 'valueOf' in v.keys || v.elements.len > 0 {
				return stv_ordinary_to_primitive(v, hint)
			}
			return js_any_text('[object Object]')
		}
		.regexp_ {
			mut out := [u16(`/`)]
			out << v.regexp.source
			out << u16(`/`)
			out << utf16_units(v.regexp.flags)
			return js_any_string(out)
		}
		.function_ {
			short := v.name.all_after_last('.')
			return js_any_text('function ${short}() { [native code] }')
		}
		.namespace_ {
			return js_any_text('[object ${v.name}]')
		}
		.map_ {
			return js_any_text('[object Map]')
		}
		.set_ {
			return js_any_text('[object Set]')
		}
		.iterator_ {
			return js_any_text('[object ${v.name}]')
		}
		.hole_ {
			return js_any_undefined()
		}
		.wrapper_ {
			// valueOf gives the primitive and toString, first for the hint `string`, its string;
			// the object of a symbol gives the symbol for any hint (its @@toPrimitive).
			p := v.elements[0]
			if hint == 'string' && p.kind in [.number_, .boolean_, .bigint_] {
				return js_any_string(stv_to_string(p)?)
			}
			return p
		}
		else {
			return v
		}
	}
}

// stv_ordinary_to_primitive ports OrdinaryToPrimitive for a plain object: valueOf then toString
// (toString first for the hint `string`), its own or Object.prototype's; the first callable one
// that returns a primitive gives it, and none does is a TypeError.
fn stv_ordinary_to_primitive(v JsAny, hint string) ?JsAny {
	for name in if hint == 'string' { ['toString', 'valueOf'] } else { ['valueOf', 'toString'] } {
		method := stv_get(v, js_any_text(name))?
		if method.kind != .function_ {
			continue
		}
		result := stv_native_call(method, v, []JsAny{})?
		if !stv_is_object(result) {
			return result
		}
	}
	return none
}

// stv_native_call calls a builtin function as a builtin does (not as eslint-utils' callAllowed
// does): Object.prototype's valueOf and toString of a plain object, and the functions veslint
// evaluates; none for the others (the native-call limit) and where the call throws. Only a
// primitive result is meant to be kept: the identities of objects made here are not those of the
// evaluation. The methods that convert their receiver (those of String, and Array's toString,
// which calls its join) are not called: as the toString or valueOf of the object being converted,
// they convert it again, without end (a RangeError in V8) or through a join that does not.
fn stv_native_call(f JsAny, this JsAny, args []JsAny) ?JsAny {
	if f.name.starts_with('String.prototype.') || f.name == 'Array.prototype.toString' {
		return none
	}
	match f.name {
		'Object.prototype.valueOf' {
			return this
		}
		'Object.prototype.toString' {
			if this.kind == .object_ {
				tag := stv_to_string_tag(this)
				return js_any_text('[object ${if tag == '' { 'Object' } else { tag }}]')
			}
			return none
		}
		else {}
	}
	if f.name !in stv_call_allowed && f.name !in stv_call_pass_through {
		return none
	}
	mut ctx := StvContext{}
	return stv_call_function(f, this, true, args, mut ctx)
}

// stv_to_string ports ToString; none for a symbol (a TypeError).
fn stv_to_string(v JsAny) ?[]u16 {
	match v.kind {
		.undefined_, .hole_ {
			return utf16_units('undefined')
		}
		.null_ {
			return utf16_units('null')
		}
		.boolean_ {
			return utf16_units(if v.boolean { 'true' } else { 'false' })
		}
		.number_ {
			return utf16_units(js_number_to_string(v.number))
		}
		.string_ {
			return v.units
		}
		.bigint_ {
			return utf16_units(v.digits)
		}
		.symbol_ {
			return none
		}
		else {
			return stv_to_string(stv_to_primitive_hint(v, 'string')?)
		}
	}
}

// stv_to_numeric ports ToNumeric: a number or a BigInt primitive.
fn stv_to_numeric(v JsAny) ?JsAny {
	p := stv_to_primitive_hint(v, 'number')?
	if p.kind == .bigint_ {
		return p
	}
	return js_any_number(stv_to_number(p)?)
}

// stv_to_number ports ToNumber; none for a BigInt or a symbol (a TypeError).
fn stv_to_number(v JsAny) ?f64 {
	match v.kind {
		.undefined_, .hole_ {
			return math.nan()
		}
		.null_ {
			return 0
		}
		.boolean_ {
			return if v.boolean { 1 } else { 0 }
		}
		.number_ {
			return v.number
		}
		.string_ {
			return js_string_to_number(stv_units_string(v.units))
		}
		.bigint_, .symbol_ {
			return none
		}
		else {
			return stv_to_number(stv_to_primitive_hint(v, 'number')?)
		}
	}
}

// stv_number_to_bigint ports NumberToBigInt: the exact value of an integral number; none for the
// RangeError of any other one.
fn stv_number_to_bigint(x f64) ?big.Integer {
	if math.is_nan(x) || math.is_inf(x, 0) || x != math.trunc(x) {
		return none
	}
	if x == 0 {
		return big.zero_int
	}
	bits := math.f64_bits(math.abs(x))
	biased := int((bits >> 52) & 0x7ff)
	fraction := bits & 0xfffffffffffff
	mantissa := if biased == 0 { fraction } else { fraction | (u64(1) << 52) }
	exponent := if biased == 0 { -1074 } else { biased - 1075 }
	mut value := big.integer_from_u64(mantissa)
	value = if exponent >= 0 {
		value.left_shift(u32(exponent))
	} else {
		value.right_shift(u32(-exponent))
	}
	return if x < 0 { value.neg() } else { value }
}

// stv_bigint_to_number ports Number(bigint): the nearest double, ties to even.
fn stv_bigint_to_number(v JsAny) ?f64 {
	n := js_bigint(v.digits)?
	value := integer_to_f64(n.abs())
	return if n.signum < 0 { -value } else { value }
}

// stv_to_integer ports ToIntegerOrInfinity.
fn stv_to_integer(v JsAny) ?f64 {
	n := stv_to_number(v)?
	if math.is_nan(n) {
		return 0
	}
	if math.is_inf(n, 0) {
		return n
	}
	return math.trunc(n) + 0
}

// stv_join ports Array.prototype.join.
fn stv_join(v JsAny, separator []u16) ?[]u16 {
	mut out := []u16{}
	for i, e in v.elements {
		if i > 0 {
			out << separator
		}
		if e.kind !in [.undefined_, .null_, .hole_] {
			out << stv_to_string(e)?
		}
	}
	return out
}

// stv_canonical_index gives the array index a property key names (`'1'`, not `'01'`), or -1.
fn stv_canonical_index(key string) int {
	if key == '0' {
		return 0
	}
	if key == '' || key.len > 10 || key[0] == `0` || !key.bytes().all(it.is_digit()) {
		return -1
	}
	n := key.i64()
	return if n < 4294967295 { int(n) } else { -1 }
}

// Own properties of the builtins veslint models (Node 26), and the members of the prototypes.
const stv_object_prototype = ['constructor', '__defineGetter__', '__defineSetter__', 'hasOwnProperty',
	'__lookupGetter__', '__lookupSetter__', 'isPrototypeOf', 'propertyIsEnumerable', 'toString',
	'valueOf', '__proto__', 'toLocaleString']
const stv_function_prototype = ['length', 'name', 'constructor', 'apply', 'bind', 'call', 'toString',
	'arguments', 'caller', 'prototype']
const stv_math_functions = ['abs', 'acos', 'acosh', 'asin', 'asinh', 'atan', 'atanh', 'atan2',
	'ceil', 'cbrt', 'expm1', 'clz32', 'cos', 'cosh', 'exp', 'floor', 'fround', 'hypot', 'imul',
	'log', 'log1p', 'log2', 'log10', 'max', 'min', 'pow', 'random', 'round', 'sign', 'sin', 'sinh',
	'sqrt', 'tan', 'tanh', 'trunc', 'f16round']
const stv_static_functions = {
	'Number':      ['isFinite', 'isInteger', 'isNaN', 'isSafeInteger', 'parseFloat', 'parseInt']
	'String':      ['fromCharCode', 'fromCodePoint', 'raw']
	'Array':       ['isArray', 'from', 'fromAsync', 'of']
	'Symbol':      ['for', 'keyFor']
	'Object':      ['assign', 'getOwnPropertyDescriptor', 'getOwnPropertyDescriptors',
		'getOwnPropertyNames', 'getOwnPropertySymbols', 'hasOwn', 'is', 'preventExtensions', 'seal',
		'create', 'defineProperties', 'defineProperty', 'freeze', 'getPrototypeOf', 'setPrototypeOf',
		'isExtensible', 'isFrozen', 'isSealed', 'keys', 'entries', 'fromEntries', 'values', 'groupBy']
	'JSON':        ['parse', 'stringify', 'rawJSON', 'isRawJSON']
	'Date':        ['now', 'parse', 'UTC']
	'Promise':     ['all', 'allSettled', 'any', 'race', 'resolve', 'reject', 'withResolvers', 'try']
	'BigInt':      ['asUintN', 'asIntN']
	'ArrayBuffer': ['isView']
	'Proxy':       ['revocable']
	'Map':         ['groupBy']
	'RegExp':      ['escape']
	'Uint8Array':  ['fromBase64', 'fromHex']
	'Reflect':     ['defineProperty', 'deleteProperty', 'apply', 'construct', 'get',
		'getOwnPropertyDescriptor', 'getPrototypeOf', 'has', 'isExtensible', 'ownKeys',
		'preventExtensions', 'set', 'setPrototypeOf']
}
// `length` (arity) of the builtin functions of eslint-utils' builtinNames (Node 26).
const stv_builtin_lengths = {
	'Array':              1
	'ArrayBuffer':        1
	'BigInt':             1
	'BigInt64Array':      3
	'BigUint64Array':     3
	'Boolean':            1
	'DataView':           1
	'Date':               7
	'decodeURI':          1
	'decodeURIComponent': 1
	'encodeURI':          1
	'encodeURIComponent': 1
	'escape':             1
	'Float32Array':       3
	'Float64Array':       3
	'Function':           1
	'Int16Array':         3
	'Int32Array':         3
	'Int8Array':          3
	'isFinite':           1
	'isNaN':              1
	'isPrototypeOf':      1
	'Map':                0
	'Number':             1
	'Object':             1
	'parseFloat':         1
	'parseInt':           2
	'Promise':            1
	'Proxy':              2
	'RegExp':             2
	'Set':                0
	'String':             1
	'Symbol':             0
	'Uint16Array':        3
	'Uint32Array':        3
	'Uint8Array':         3
	'Uint8ClampedArray':  3
	'unescape':           1
	'WeakMap':            0
	'WeakSet':            0
}
const stv_regexp_legacy_getters = ['input', r'$_', 'lastMatch', r'$&', 'lastParen', r'$+', 'leftContext',
	r'$`', 'rightContext', r"$'", r'$1', r'$2', r'$3', r'$4', r'$5', r'$6', r'$7', r'$8', r'$9']
const stv_well_known_symbols = ['asyncIterator', 'hasInstance', 'isConcatSpreadable', 'iterator',
	'match', 'matchAll', 'replace', 'search', 'species', 'split', 'toPrimitive', 'toStringTag',
	'unscopables', 'dispose', 'asyncDispose']
const stv_string_methods = ['constructor', 'anchor', 'at', 'big', 'blink', 'bold', 'charAt',
	'charCodeAt', 'codePointAt', 'concat', 'endsWith', 'fontcolor', 'fontsize', 'fixed', 'includes',
	'indexOf', 'isWellFormed', 'italics', 'lastIndexOf', 'link', 'localeCompare', 'match', 'matchAll',
	'normalize', 'padEnd', 'padStart', 'repeat', 'replace', 'replaceAll', 'search', 'slice', 'small',
	'split', 'strike', 'sub', 'substr', 'substring', 'sup', 'startsWith', 'toString', 'toWellFormed',
	'trim', 'trimStart', 'trimLeft', 'trimEnd', 'trimRight', 'toLocaleLowerCase', 'toLocaleUpperCase',
	'toLowerCase', 'toUpperCase', 'valueOf']
const stv_array_methods = ['constructor', 'at', 'concat', 'copyWithin', 'fill', 'find', 'findIndex',
	'findLast', 'findLastIndex', 'lastIndexOf', 'pop', 'push', 'reverse', 'shift', 'unshift', 'slice',
	'sort', 'splice', 'includes', 'indexOf', 'join', 'keys', 'entries', 'values', 'forEach', 'filter',
	'flat', 'flatMap', 'map', 'every', 'some', 'reduce', 'reduceRight', 'toReversed', 'toSorted',
	'toSpliced', 'with', 'toLocaleString', 'toString']
const stv_number_methods = ['toExponential', 'toFixed', 'toPrecision', 'toString', 'valueOf',
	'toLocaleString']
const stv_boolean_methods = ['toString', 'valueOf']
const stv_bigint_methods = ['toLocaleString', 'toString', 'valueOf']
const stv_symbol_methods = ['toString', 'valueOf']
const stv_regexp_getters = ['dotAll', 'flags', 'global', 'hasIndices', 'ignoreCase', 'multiline',
	'source', 'sticky', 'unicode']
const stv_regexp_methods = ['constructor', 'exec', 'unicodeSets', 'compile', 'toString', 'test']
// The methods of %IteratorPrototype% with a string key (Node 26).
const stv_iterator_helpers = ['reduce', 'toArray', 'forEach', 'some', 'every', 'find', 'map', 'filter',
	'take', 'drop', 'flatMap']

// stv_call_allowed are the functions of eslint-utils' callAllowed, by the names veslint gives them
// (rules/static_value_test.v checks the list against eslint-utils' own): the only ones a
// CallExpression or a NewExpression calls. Calling any other value is not static, without an
// exception. Not all of them are evaluated here (see the head of this file).
const stv_call_allowed = ['Array.isArray', 'Array.of', 'Array.prototype.at', 'Array.prototype.concat',
	'Array.prototype.entries', 'Array.prototype.every', 'Array.prototype.filter', 'Array.prototype.find',
	'Array.prototype.findIndex', 'Array.prototype.flat', 'Array.prototype.includes',
	'Array.prototype.indexOf', 'Array.prototype.join', 'Array.prototype.keys',
	'Array.prototype.lastIndexOf', 'Array.prototype.slice', 'Array.prototype.some',
	'Array.prototype.toString', 'Array.prototype.values', 'BigInt', 'Boolean', 'Date', 'Date.parse',
	'decodeURI', 'decodeURIComponent', 'encodeURI', 'encodeURIComponent', 'escape', 'isFinite',
	'isNaN', 'isPrototypeOf', 'Map', 'Map.prototype.entries', 'Map.prototype.get', 'Map.prototype.has',
	'Map.prototype.keys', 'Map.prototype.values', 'Math.abs', 'Math.acos', 'Math.acosh', 'Math.asin',
	'Math.asinh', 'Math.atan', 'Math.atanh', 'Math.atan2', 'Math.ceil', 'Math.cbrt', 'Math.expm1',
	'Math.clz32', 'Math.cos', 'Math.cosh', 'Math.exp', 'Math.floor', 'Math.fround', 'Math.hypot',
	'Math.imul', 'Math.log', 'Math.log1p', 'Math.log2', 'Math.log10', 'Math.max', 'Math.min', 'Math.pow',
	'Math.round', 'Math.sign', 'Math.sin', 'Math.sinh', 'Math.sqrt', 'Math.tan', 'Math.tanh',
	'Math.trunc', 'Math.f16round', 'Number', 'Number.isFinite', 'Number.isNaN', 'parseFloat', 'parseInt',
	'Number.prototype.toExponential', 'Number.prototype.toFixed', 'Number.prototype.toPrecision',
	'Number.prototype.toString', 'Object', 'Object.entries', 'Object.is', 'Object.isExtensible',
	'Object.isFrozen', 'Object.isSealed', 'Object.keys', 'Object.values', 'RegExp', 'Set',
	'Set.prototype.entries', 'Set.prototype.has', 'Set.prototype.values', 'String',
	'String.fromCharCode', 'String.fromCodePoint', 'String.raw', 'String.prototype.at',
	'String.prototype.charAt', 'String.prototype.charCodeAt', 'String.prototype.codePointAt',
	'String.prototype.concat', 'String.prototype.endsWith', 'String.prototype.includes',
	'String.prototype.indexOf', 'String.prototype.lastIndexOf', 'String.prototype.normalize',
	'String.prototype.padEnd', 'String.prototype.padStart', 'String.prototype.slice',
	'String.prototype.startsWith', 'String.prototype.substr', 'String.prototype.substring',
	'String.prototype.toLowerCase', 'String.prototype.toString', 'String.prototype.toUpperCase',
	'String.prototype.trim', 'String.prototype.trimEnd', 'String.prototype.trimStart', 'Symbol.for',
	'Symbol.keyFor', 'unescape']
// stv_call_pass_through are the functions of its callPassThrough: not called, their first
// argument is the value.
const stv_call_pass_through = ['Object.freeze', 'Object.preventExtensions', 'Object.seal']

// stv_canonical_function is the name of a builtin function object: aliases are the same object.
fn stv_canonical_function(name string) string {
	return match name {
		'String.prototype.trimLeft' { 'String.prototype.trimStart' }
		'String.prototype.trimRight' { 'String.prototype.trimEnd' }
		'Number.parseInt' { 'parseInt' }
		'Number.parseFloat' { 'parseFloat' }
		'Set.prototype.keys' { 'Set.prototype.values' }
		'Object.prototype.isPrototypeOf' { 'isPrototypeOf' }
		else { name }
	}
}

// stv_get ports `object[key]` with eslint-utils' getter rule; none when JavaScript would throw,
// when the property is a getter eslint-utils does not allow, or when veslint does not model it.
fn stv_get(object JsAny, key_value JsAny) ?JsAny {
	if key_value.kind == .symbol_ || stv_is_nullish(object) {
		return none
	}
	key := stv_key_string(stv_to_string(stv_to_primitive_hint(key_value, 'string')?)?)
	if key == 'constructor' {
		match object.kind {
			.string_ { return js_any_function('String') }
			.array_ { return js_any_function('Array') }
			.regexp_ { return js_any_function('RegExp') }
			.object_ {
				if key !in object.keys && object.elements.len == 0 {
					return js_any_function('Object')
				}
			}
			.namespace_ { return js_any_function('Object') }
			.number_ { return js_any_function('Number') }
			.boolean_ { return js_any_function('Boolean') }
			.bigint_ { return js_any_function('BigInt') }
			.symbol_ { return js_any_function('Symbol') }
			.map_ { return js_any_function('Map') }
			.set_ { return js_any_function('Set') }
			.wrapper_ { return stv_get(object.elements[0], key_value) }
			else {}
		}
	}
	match object.kind {
		.string_ {
			if key == 'length' {
				return js_any_number(object.units.len)
			}
			i := stv_canonical_index(key)
			if i >= 0 {
				return if i < object.units.len {
					js_any_string([object.units[i]])
				} else {
					js_any_undefined()
				}
			}
			if key in stv_string_methods {
				return js_any_function(stv_canonical_function('String.prototype.${key}'))
			}
			return stv_missing(key)
		}
		.array_ {
			if key == 'length' {
				return js_any_number(object.elements.len)
			}
			i := stv_canonical_index(key)
			if i >= 0 {
				return if i < object.elements.len && object.elements[i].kind != .hole_ {
					object.elements[i]
				} else {
					js_any_undefined()
				}
			}
			if key in stv_array_methods {
				return js_any_function('Array.prototype.${key}')
			}
			return stv_missing(key)
		}
		.object_ {
			i := object.keys.index(key)
			if i >= 0 {
				return object.values[i]
			}
			if object.elements.len > 0 {
				// Through the prototype: nothing after null; a getter of a RegExp, a Map or a Set
				// called on what is not one is a TypeError.
				prototype := object.elements[0]
				if prototype.kind == .null_ {
					return js_any_undefined()
				}
				if (prototype.kind == .regexp_
					&& (key in stv_regexp_getters || key == 'unicodeSets'))
					|| (prototype.kind in [.map_, .set_] && key == 'size') {
					return none
				}
				return stv_get(prototype, key_value)
			}
			return stv_missing(key)
		}
		.regexp_ {
			if key == 'lastIndex' {
				return js_any_number(0)
			}
			if key in stv_regexp_getters {
				// getterAllowed has the names as strings: another value that names the getter
				// (`re[['source']]`) is not one of them.
				if key_value.kind != .string_ {
					return none
				}
				return stv_regexp_getter(object.regexp, key)
			}
			if key in stv_regexp_methods {
				// unicodeSets is a getter eslint-utils does not allow.
				return if key == 'unicodeSets' {
					none
				} else {
					js_any_function('RegExp.prototype.${key}')
				}
			}
			return stv_missing(key)
		}
		.map_, .set_ {
			if key == 'size' {
				// A getter of getterAllowed, like the ones of a RegExp.
				if key_value.kind != .string_ {
					return none
				}
				return js_any_number(object.elements.len)
			}
			class := if object.kind == .map_ { 'Map' } else { 'Set' }
			if key in (if object.kind == .map_ { stv_map_methods } else { stv_set_methods }) {
				return js_any_function(stv_canonical_function('${class}.prototype.${key}'))
			}
			return stv_missing(key)
		}
		.namespace_ {
			if object.name == 'Math' {
				if key in stv_math_functions {
					return js_any_function('Math.${key}')
				}
				constant := match key {
					'E' { math.e }
					'LN10' { math.ln10 }
					'LN2' { math.ln2 }
					// V8's log10(E): 1 / math.ln10 is one unit in the last place below it.
					'LOG10E' { 0.4342944819032518 }
					'LOG2E' { 1 / math.ln2 }
					'PI' { math.pi }
					'SQRT1_2' { math.sqrt2 / 2 }
					'SQRT2' { math.sqrt2 }
					else { -1 }
				}
				if constant >= 0 {
					return js_any_number(constant)
				}
			} else if key in stv_static_functions[object.name] {
				return js_any_function('${object.name}.${key}')
			}
			return stv_missing(key)
		}
		.function_ {
			// `length`, `name` and `prototype`, and Function.prototype's members.
			if key in stv_function_prototype {
				if length := stv_builtin_lengths[object.name] {
					if key == 'length' {
						return js_any_number(length)
					}
					if key == 'name' {
						return js_any_text(object.name)
					}
				}
				return none
			}
			statics := stv_static_functions[object.name] or { []string{} }
			if key in statics {
				return js_any_function(stv_canonical_function('${object.name}.${key}'))
			}
			if object.name.ends_with('Array') && object.name != 'Array' {
				if key in ['of', 'from'] {
					return js_any_function('TypedArray.${key}')
				}
				if key == 'BYTES_PER_ELEMENT' {
					return js_any_number(match object.name {
						'Int8Array', 'Uint8Array', 'Uint8ClampedArray' { 1 }
						'Int16Array', 'Uint16Array' { 2 }
						'Int32Array', 'Uint32Array', 'Float32Array' { 4 }
						else { 8 }
					})
				}
			}
			if object.name == 'Number' {
				constant := match key {
					'MAX_VALUE' { math.max_f64 }
					'MIN_VALUE' { 5e-324 }
					'NaN' { math.nan() }
					'NEGATIVE_INFINITY' { math.inf(-1) }
					'POSITIVE_INFINITY' { math.inf(1) }
					'MAX_SAFE_INTEGER' { 9007199254740991.0 }
					'MIN_SAFE_INTEGER' { -9007199254740991.0 }
					'EPSILON' { math.pow(2, -52) }
					else { 0 }
				}
				if key in ['MAX_VALUE', 'MIN_VALUE', 'NaN', 'NEGATIVE_INFINITY', 'POSITIVE_INFINITY',
					'MAX_SAFE_INTEGER', 'MIN_SAFE_INTEGER', 'EPSILON'] {
					return js_any_number(constant)
				}
			}
			if object.name == 'Symbol' && key in stv_well_known_symbols {
				return JsAny{
					kind: .symbol_
					name: 'Symbol.${key}'
				}
			}
			// The legacy static accessors of RegExp are getters eslint-utils does not allow.
			if object.name == 'RegExp' && key in stv_regexp_legacy_getters {
				return none
			}
			if object.name.contains('.') {
				// Members of methods (`'a'.slice.x`) are not modelled.
				return none
			}
			return stv_missing(key)
		}
		.number_, .boolean_, .bigint_, .symbol_ {
			methods := match object.kind {
				.number_ { stv_number_methods }
				.boolean_ { stv_boolean_methods }
				.bigint_ { stv_bigint_methods }
				else { stv_symbol_methods }
			}
			if key in methods {
				prefix := match object.kind {
					.number_ { 'Number' }
					.boolean_ { 'Boolean' }
					.bigint_ { 'BigInt' }
					else { 'Symbol' }
				}
				return js_any_function('${prefix}.prototype.${key}')
			}
			if object.kind == .symbol_ && key == 'description' {
				return js_any_string(stv_symbol_description(object))
			}
			return stv_missing(key)
		}
		.wrapper_ {
			// The own length and indexes of a String object and the members of the prototype of
			// its primitive are what the primitive has; but Symbol.prototype.description is a
			// getter eslint-utils does not allow on an object.
			if object.elements[0].kind == .symbol_ && key == 'description' {
				return none
			}
			return stv_get(object.elements[0], key_value)
		}
		.iterator_ {
			// The next of %ArrayIteratorPrototype% (or of the one of Map or Set iterators), the
			// helpers of %IteratorPrototype%, whose constructor is a getter, and Object.prototype.
			if key == 'next' {
				prototype := match object.name {
					'Map Iterator' { '%MapIteratorPrototype%' }
					'Set Iterator' { '%SetIteratorPrototype%' }
					else { '%ArrayIteratorPrototype%' }
				}
				return js_any_function('${prototype}.next')
			}
			if key in stv_iterator_helpers {
				return js_any_function('%IteratorPrototype%.${key}')
			}
			if key == 'constructor' {
				return none
			}
			return stv_missing(key)
		}
		else {
			return none
		}
	}
}

// stv_missing is a property not found among the own and prototype members veslint lists: an
// Object.prototype method, or undefined. `__proto__` is a getter eslint-utils does not allow.
fn stv_missing(key string) ?JsAny {
	if key == '__proto__' {
		return none
	}
	if key in stv_object_prototype {
		return js_any_function(stv_canonical_function('Object.prototype.${key}'))
	}
	return js_any_undefined()
}

fn stv_regexp_getter(re jsregexp.RegexpValue, key string) JsAny {
	return match key {
		'source' { js_any_string(re.source) }
		'flags' { js_any_text(re.flags) }
		'dotAll' { js_any_bool(re.flags.contains('s')) }
		'global' { js_any_bool(re.flags.contains('g')) }
		'hasIndices' { js_any_bool(re.flags.contains('d')) }
		'ignoreCase' { js_any_bool(re.flags.contains('i')) }
		'multiline' { js_any_bool(re.flags.contains('m')) }
		'sticky' { js_any_bool(re.flags.contains('y')) }
		else { js_any_bool(re.flags.contains('u')) }
	}
}

// stv_call_function calls a builtin function with a receiver (`has_receiver`: a member call);
// none when the function is not one veslint evaluates or when the call throws.
fn stv_call_function(f JsAny, this JsAny, has_receiver bool, args []JsAny, mut ctx StvContext) ?JsAny {
	if f.kind != .function_ {
		return none
	}
	arg := fn [args] (i int) JsAny {
		return if i < args.len { args[i] } else { js_any_undefined() }
	}
	if f.name.starts_with('String.prototype.') {
		// The methods are generic: RequireObjectCoercible and ToString of the receiver; but
		// toString, which only takes a string.
		if !has_receiver || stv_is_nullish(this) || (f.name == 'String.prototype.toString'
			&& this.kind != .string_ && !(this.kind == .wrapper_ && this.elements[0].kind == .string_)) {
			return none
		}
		s := if this.kind == .string_ { this.units } else { stv_to_string(this)? }
		return stv_string_method(f.name.all_after_last('.'), s, args)
	}
	if f.name.starts_with('Array.prototype.') {
		// The methods are generic too (stv_array_like).
		if !has_receiver || stv_is_nullish(this) {
			return none
		}
		return stv_array_method(f.name.all_after_last('.'), this, args, mut ctx)
	}
	// thisNumberValue: the methods of Number.prototype take a number or the object of one.
	number := if this.kind == .wrapper_ { this.elements[0] } else { this }
	if f.name.starts_with('Map.prototype.') || f.name.starts_with('Set.prototype.') {
		if !has_receiver {
			return none
		}
		return stv_collection_method(f.name, this, args, mut ctx)
	}
	match f.name {
		'String' {
			if args.len == 0 {
				return js_any_string([]u16{})
			}
			if args[0].kind == .symbol_ {
				return js_any_string(stv_symbol_string(args[0]))
			}
			return js_any_string(stv_to_string(args[0])?)
		}
		'Number' {
			if args.len == 0 {
				return js_any_number(0)
			}
			p := stv_to_numeric(args[0])?
			if p.kind == .bigint_ {
				return js_any_number(stv_bigint_to_number(p)?)
			}
			return p
		}
		'Boolean' {
			return js_any_bool(stv_to_boolean(arg(0)))
		}
		'BigInt' {
			// BigInt(value): NumberToBigInt for a number (a RangeError unless it is an integer),
			// ToBigInt for the rest (a TypeError for undefined, null and symbols, and a
			// SyntaxError for a string that is not an integer).
			p := stv_to_primitive_hint(arg(0), 'number')?
			match p.kind {
				.bigint_ {
					return p
				}
				.boolean_ {
					return js_any_bigint(if p.boolean { big.one_int } else { big.zero_int })
				}
				.number_ {
					return js_any_bigint(stv_number_to_bigint(p.number)?)
				}
				.string_ {
					return js_any_bigint(js_string_to_bigint(stv_units_string(p.units))?)
				}
				else {
					return none
				}
			}
		}
		'RegExp' {
			return stv_regexp_construct(args, false, mut ctx)
		}
		'parseInt' {
			return js_any_number(stv_parse_int(stv_to_string(arg(0))?, arg(1))?)
		}
		'parseFloat' {
			return js_any_number(stv_parse_float(stv_to_string(arg(0))?))
		}
		'isNaN' {
			return js_any_bool(math.is_nan(stv_to_number(arg(0))?))
		}
		'isFinite' {
			n := stv_to_number(arg(0))?
			return js_any_bool(!math.is_nan(n) && !math.is_inf(n, 0))
		}
		'Number.isNaN' {
			a := arg(0)
			return js_any_bool(a.kind == .number_ && math.is_nan(a.number))
		}
		'Number.isFinite' {
			a := arg(0)
			return js_any_bool(a.kind == .number_ && !math.is_nan(a.number)
				&& !math.is_inf(a.number, 0))
		}
		'Array.isArray' {
			return js_any_bool(arg(0).kind == .array_)
		}
		'Array.of' {
			return JsAny{
				kind:     .array_
				id:       ctx.new_id()
				elements: args
			}
		}
		'Object.freeze', 'Object.preventExtensions', 'Object.seal' {
			return arg(0)
		}
		'Object.keys', 'Object.values', 'Object.entries' {
			// The own enumerable properties of ToObject(value), in OrdinaryOwnPropertyKeys' order.
			keys, values := stv_own_enumerable(arg(0))?
			mut elements := []JsAny{cap: keys.len}
			for i, key in keys {
				name := js_any_string(stv_key_units(key))
				elements << match f.name {
					'Object.keys' { name }
					'Object.values' { values[i] }
					else { ctx.new_array([name, values[i]]) }
				}
			}
			return ctx.new_array(elements)
		}
		'Object' {
			return stv_object_call(args, mut ctx)
		}
		'Object.isExtensible' {
			// No object here is frozen, sealed or not extensible: Object.freeze and its like are
			// not called (callPassThrough), and no builtin object of Node is.
			return js_any_bool(stv_is_object(arg(0)))
		}
		'Object.isFrozen', 'Object.isSealed' {
			return js_any_bool(!stv_is_object(arg(0)))
		}
		'Object.is' {
			// SameValue: like `===`, but NaN is NaN and +0 is not -0.
			a := arg(0)
			b := arg(1)
			if a.kind == .number_ && b.kind == .number_ {
				if math.is_nan(a.number) || math.is_nan(b.number) {
					return js_any_bool(math.is_nan(a.number) && math.is_nan(b.number))
				}
				return js_any_bool(a.number == b.number
					&& math.signbit(a.number) == math.signbit(b.number))
			}
			return js_any_bool(stv_strict_equal(a, b))
		}
		'String.fromCharCode' {
			mut units := []u16{cap: args.len}
			for a in args {
				units << u16(stv_to_uint32(stv_to_number(a)?))
			}
			return js_any_string(units)
		}
		'String.fromCodePoint' {
			return js_any_string(stv_from_code_point(args)?)
		}
		'Symbol.for' {
			// The symbol of the registry with that key: the same one for the same key.
			return JsAny{
				kind:       .symbol_
				units:      stv_to_string(arg(0))?
				registered: true
			}
		}
		'Symbol.keyFor' {
			// A TypeError for what is not a symbol; undefined for one that is not registered.
			a := arg(0)
			if a.kind != .symbol_ {
				return none
			}
			return if a.registered { js_any_string(a.units) } else { js_any_undefined() }
		}
		'String.raw' {
			return js_any_string(stv_string_raw_call(args)?)
		}
		'encodeURI', 'encodeURIComponent' {
			extra := if f.name == 'encodeURI' { stv_uri_reserved } else { '' }
			return js_any_string(stv_uri_encode(stv_to_string(arg(0))?, extra)?)
		}
		'decodeURI', 'decodeURIComponent' {
			preserve := if f.name == 'decodeURI' { stv_uri_reserved } else { '' }
			return js_any_string(stv_uri_decode(stv_to_string(arg(0))?, preserve)?)
		}
		'escape' {
			return js_any_string(stv_escape(stv_to_string(arg(0))?))
		}
		'unescape' {
			return js_any_string(stv_unescape(stv_to_string(arg(0))?))
		}
		'isPrototypeOf' {
			return js_any_bool(stv_is_prototype_of(this, has_receiver, arg(0))?)
		}
		'Math.f16round' {
			return js_any_number(stv_f16round(stv_to_number(arg(0))?))
		}
		'Math.acos', 'Math.acosh', 'Math.asin', 'Math.asinh', 'Math.atan', 'Math.atanh', 'Math.cbrt',
		'Math.cos', 'Math.cosh', 'Math.exp', 'Math.expm1', 'Math.log', 'Math.log1p', 'Math.log2',
		'Math.log10', 'Math.sin', 'Math.sinh', 'Math.tan', 'Math.tanh' {
			// V8's fdlibm, to the last bit (js_math.v).
			return js_any_number(js_math_function(f.name, stv_to_number(arg(0))?)?)
		}
		'Math.atan2' {
			y := stv_to_number(arg(0))?
			return js_any_number(js_math_atan2(y, stv_to_number(arg(1))?))
		}
		'Math.hypot' {
			// ToNumber of every argument, in order, before anything else.
			mut numbers := []f64{cap: args.len}
			for a in args {
				numbers << stv_to_number(a)?
			}
			return js_any_number(js_math_hypot(numbers))
		}
		'Number.prototype.toString' {
			if !has_receiver || number.kind != .number_ {
				return none
			}
			return js_any_text(stv_number_to_string(number.number, arg(0))?)
		}
		'Number.prototype.toFixed' {
			if !has_receiver || number.kind != .number_ {
				return none
			}
			return js_any_text(stv_to_fixed(number.number, stv_to_integer(arg(0))?)?)
		}
		'Number.prototype.toExponential' {
			if !has_receiver || number.kind != .number_ {
				return none
			}
			digits := stv_to_integer(arg(0))?
			return js_any_text(stv_to_exponential(number.number, digits, arg(0).kind == .undefined_)?)
		}
		'Number.prototype.toPrecision' {
			if !has_receiver || number.kind != .number_ {
				return none
			}
			if arg(0).kind == .undefined_ {
				return js_any_text(js_number_to_string(number.number))
			}
			return js_any_text(stv_to_precision(number.number, stv_to_integer(arg(0))?)?)
		}
		'Math.abs', 'Math.ceil', 'Math.floor', 'Math.round', 'Math.sign', 'Math.trunc' {
			return js_any_number(stv_math_unary(f.name, stv_to_number(arg(0))?))
		}
		'Math.sqrt' {
			// IEEE 754 square root is correctly rounded, in V8 as in C.
			return js_any_number(math.sqrt(stv_to_number(arg(0))?))
		}
		'Math.fround' {
			return js_any_number(f64(f32(stv_to_number(arg(0))?)))
		}
		'Math.clz32' {
			x := stv_to_uint32(stv_to_number(arg(0))?)
			mut n := 32
			for v := x; v != 0; v >>= 1 {
				n--
			}
			return js_any_number(n)
		}
		'Math.imul' {
			a := stv_to_int32(stv_to_number(arg(0))?)
			b := stv_to_int32(stv_to_number(arg(1))?)
			return js_any_number(f64(i32(u32(a) * u32(b))))
		}
		'Math.pow' {
			base := stv_to_number(arg(0))?
			return js_any_number(stv_power(base, stv_to_number(arg(1))?))
		}
		'Math.max', 'Math.min' {
			mut numbers := []f64{}
			for a in args {
				numbers << stv_to_number(a)?
			}
			return js_any_number(stv_math_extreme(f.name == 'Math.max', numbers))
		}
		else {
			return none
		}
	}
}

// stv_to_fixed ports Number.prototype.toFixed with exact arithmetic; none for the RangeError of a
// number of digits outside 0..100.
fn stv_to_fixed(x f64, digits f64) ?string {
	if math.is_nan(digits) || digits < 0 || digits > 100 {
		return none
	}
	if math.is_nan(x) || math.is_inf(x, 0) || math.abs(x) >= 1e21 {
		return js_number_to_string(x)
	}
	f := int(digits)
	// |x| is mantissa × 2^exponent.
	bits := math.f64_bits(math.abs(x))
	biased := int((bits >> 52) & 0x7ff)
	fraction := bits & 0xfffffffffffff
	mantissa := if biased == 0 { fraction } else { fraction | (u64(1) << 52) }
	exponent := if biased == 0 { -1074 } else { biased - 1075 }
	mut n := big.integer_from_u64(mantissa) * big.integer_from_int(10).pow(u32(f))
	if exponent >= 0 {
		n = n.left_shift(u32(exponent))
	} else {
		divisor := big.one_int.left_shift(u32(-exponent))
		quotient, remainder := n.div_mod(divisor)
		// The integer closest to x × 10^f; of two equally close, the larger one.
		n = if remainder.left_shift(1) >= divisor { quotient + big.one_int } else { quotient }
	}
	mut text := n.str()
	if f > 0 {
		if text.len <= f {
			text = '0'.repeat(f + 1 - text.len) + text
		}
		text = text[..text.len - f] + '.' + text[text.len - f..]
	}
	return if x < 0 { '-' + text } else { text }
}

// stv_significant gives, for a finite x > 0, the integer n of `count` decimal digits and the
// exponent e with n × 10^(e - count + 1) as close to x as possible (of two, the larger one): the
// digits of toExponential and toPrecision, with exact arithmetic.
fn stv_significant(x f64, count int) (string, int) {
	bits := math.f64_bits(x)
	biased := int((bits >> 52) & 0x7ff)
	fraction := bits & 0xfffffffffffff
	mantissa := if biased == 0 { fraction } else { fraction | (u64(1) << 52) }
	exponent := if biased == 0 { -1074 } else { biased - 1075 }
	// x = numerator / denominator
	mut numerator := big.integer_from_u64(mantissa)
	mut denominator := big.one_int
	if exponent >= 0 {
		numerator = numerator.left_shift(u32(exponent))
	} else {
		denominator = denominator.left_shift(u32(-exponent))
	}
	ten := big.integer_from_int(10)
	// e with 10^e <= x < 10^(e + 1), from an estimate corrected exactly.
	mut e := int(math.floor(math.log10(x)))
	for {
		low_ok := if e >= 0 {
			numerator >= ten.pow(u32(e)) * denominator
		} else {
			numerator * ten.pow(u32(-e)) >= denominator
		}
		if !low_ok {
			e--
			continue
		}
		high_ok := if e + 1 >= 0 {
			numerator < ten.pow(u32(e + 1)) * denominator
		} else {
			numerator * ten.pow(u32(-(e + 1))) < denominator
		}
		if !high_ok {
			e++
			continue
		}
		break
	}
	// n = round(x / 10^k), half up.
	k := e - count + 1
	mut dividend := numerator
	mut divisor := denominator
	if k >= 0 {
		divisor = divisor * ten.pow(u32(k))
	} else {
		dividend = dividend * ten.pow(u32(-k))
	}
	quotient, remainder := dividend.div_mod(divisor)
	mut n := if remainder.left_shift(1) >= divisor { quotient + big.one_int } else { quotient }
	if n == ten.pow(u32(count)) {
		n = ten.pow(u32(count - 1))
		e++
	}
	return n.str(), e
}

// stv_exponent_text is the `e+N` or `e-N` of an exponential notation.
fn stv_exponent_text(e int) string {
	return if e < 0 { 'e-${-e}' } else { 'e+${e}' }
}

// stv_to_exponential ports Number.prototype.toExponential; none for the RangeError of a number of
// digits outside 0..100. Without digits, the shortest ones that give the number back.
fn stv_to_exponential(x f64, digits f64, shortest bool) ?string {
	if math.is_nan(x) || math.is_inf(x, 0) {
		return js_number_to_string(x)
	}
	if digits < 0 || digits > 100 {
		return none
	}
	sign := if x < 0 { '-' } else { '' }
	value := math.abs(x)
	mut text := ''
	mut e := 0
	if value == 0 {
		text = '0'.repeat(if shortest { 1 } else { int(digits) + 1 })
	} else if shortest {
		// The digits of Number::toString: its text without the point, the exponent and the zeros
		// at both ends.
		shown := js_number_to_string(value)
		mantissa := shown.all_before('e')
		shown_exponent := if shown.contains('e') { shown.all_after('e').int() } else { 0 }
		point := mantissa.index('.') or { mantissa.len }
		all_digits := mantissa.replace('.', '')
		leading := all_digits.len - all_digits.trim_left('0').len
		text = all_digits.trim_left('0').trim_right('0')
		e = point - 1 - leading + shown_exponent
	} else {
		text, e = stv_significant(value, int(digits) + 1)
	}
	if text.len > 1 {
		text = text[..1] + '.' + text[1..]
	}
	return sign + text + stv_exponent_text(e)
}

// stv_to_precision ports Number.prototype.toPrecision with a precision; none for the RangeError of
// one outside 1..100.
fn stv_to_precision(x f64, precision f64) ?string {
	if math.is_nan(x) || math.is_inf(x, 0) {
		return js_number_to_string(x)
	}
	if precision < 1 || precision > 100 {
		return none
	}
	p := int(precision)
	sign := if x < 0 { '-' } else { '' }
	value := math.abs(x)
	mut text := '0'.repeat(p)
	mut e := 0
	if value != 0 {
		text, e = stv_significant(value, p)
		if e < -6 || e >= p {
			if p > 1 {
				text = text[..1] + '.' + text[1..]
			}
			return sign + text + stv_exponent_text(e)
		}
	}
	if e == p - 1 {
		return sign + text
	}
	if e >= 0 {
		return sign + text[..e + 1] + '.' + text[e + 1..]
	}
	return sign + '0.' + '0'.repeat(-(e + 1)) + text
}

fn stv_math_unary(name string, x f64) f64 {
	if math.is_nan(x) {
		return x
	}
	return match name {
		'Math.abs' {
			// The sign bit cleared: Math.abs(-0) is +0, where math.abs gives -0.
			math.f64_from_bits(math.f64_bits(x) & 0x7fffffffffffffff)
		}
		'Math.ceil' {
			math.ceil(x)
		}
		'Math.floor' {
			math.floor(x)
		}
		'Math.sign' {
			if x > 0 {
				1
			} else if x < 0 {
				-1
			} else {
				x
			}
		}
		'Math.trunc' {
			math.trunc(x)
		}
		else {
			// Math.round: ties toward +Infinity, and -0 for -0.5 <= x < 0.
			if math.is_inf(x, 0) || x == math.floor(x) {
				x
			} else if x < 0 && x >= -0.5 {
				-0.0
			} else {
				r := math.floor(x)
				if x - r >= 0.5 { r + 1 } else { r }
			}
		}
	}
}

fn stv_math_extreme(max bool, numbers []f64) f64 {
	mut result := if max { math.inf(-1) } else { math.inf(1) }
	for n in numbers {
		if math.is_nan(n) {
			return n
		}
		if max {
			if n > result || (n == 0 && result == 0 && !math.signbit(n)) {
				result = n
			}
		} else if n < result || (n == 0 && result == 0 && math.signbit(n)) {
			result = n
		}
	}
	return result
}

// stv_regexp_construct ports RegExp(pattern, flags) and `new RegExp(…)`; none when it throws.
fn stv_regexp_construct(args []JsAny, is_new bool, mut ctx StvContext) ?JsAny {
	pattern := if args.len > 0 { args[0] } else { js_any_undefined() }
	flags := if args.len > 1 { args[1] } else { js_any_undefined() }
	mut source := []u16{}
	mut flag_text := ''
	if pattern.kind == .regexp_ {
		if !is_new && flags.kind == .undefined_ {
			return pattern
		}
		source = pattern.regexp.pattern.clone()
		flag_text = if flags.kind == .undefined_ {
			pattern.regexp.flags
		} else {
			stv_units_string(stv_to_string(flags)?)
		}
	} else {
		if pattern.kind != .undefined_ {
			source = stv_to_string(pattern)?.clone()
		}
		if flags.kind != .undefined_ {
			flag_text = stv_units_string(stv_to_string(flags)?)
		}
	}
	re := jsregexp.regexp_new(source, flag_text)?
	return JsAny{
		kind:   .regexp_
		id:     ctx.new_id()
		regexp: re
	}
}

// stv_parse_int ports parseInt(string, radix).
fn stv_parse_int(input []u16, radix_value JsAny) ?f64 {
	mut s := stv_units_string(input)
	s = s.trim_left(' \t\n\r\v\f                 　﻿')
	mut negative := false
	if s.starts_with('-') || s.starts_with('+') {
		negative = s[0] == `-`
		s = s[1..]
	}
	mut radix := int(stv_to_int32(stv_to_number(radix_value)?))
	mut strip_prefix := true
	if radix != 0 {
		if radix < 2 || radix > 36 {
			return math.nan()
		}
		if radix != 16 {
			strip_prefix = false
		}
	} else {
		radix = 10
	}
	if strip_prefix && s.len >= 2 && s[0] == `0` && (s[1] == `x` || s[1] == `X`) {
		s = s[2..]
		radix = 16
	}
	mut end := 0
	for end < s.len {
		ch := s[end]
		digit := if ch >= `0` && ch <= `9` {
			int(ch - `0`)
		} else if ch >= `a` && ch <= `z` {
			int(ch - `a`) + 10
		} else if ch >= `A` && ch <= `Z` {
			int(ch - `A`) + 10
		} else {
			99
		}
		if digit >= radix {
			break
		}
		end++
	}
	if end == 0 {
		return math.nan()
	}
	n := big.integer_from_radix(s[..end].to_lower(), u32(radix)) or { return none }
	value := integer_to_f64(n)
	return if negative { -value } else { value }
}

// stv_parse_float ports parseFloat(string): the longest StrDecimalLiteral prefix.
fn stv_parse_float(input []u16) f64 {
	s := js_trim(stv_units_string(input)) + ' '
	mut i := 0
	if s[i] == `+` || s[i] == `-` {
		i++
	}
	if s[i..].starts_with('Infinity') {
		return if s[0] == `-` { math.inf(-1) } else { math.inf(1) }
	}
	mut digits := 0
	for i < s.len && s[i].is_digit() {
		i++
		digits++
	}
	if i < s.len && s[i] == `.` {
		i++
		for i < s.len && s[i].is_digit() {
			i++
			digits++
		}
	}
	if digits == 0 {
		return math.nan()
	}
	mut end := i
	if i < s.len && (s[i] == `e` || s[i] == `E`) {
		mut j := i + 1
		if j < s.len && (s[j] == `+` || s[j] == `-`) {
			j++
		}
		start := j
		for j < s.len && s[j].is_digit() {
			j++
		}
		if j > start {
			end = j
		}
	}
	mut text := s[..end]
	if text.ends_with('.') {
		text += '0'
	}
	if text.starts_with('.') || text.starts_with('-.') || text.starts_with('+.') {
		text = text.replace('.', '0.')
	}
	return js_atof64(text) or { math.nan() }
}

// stv_clamp_index ports the relative index of slice/at: negatives count from the end.
fn stv_relative(value f64, len int) int {
	if value < 0 {
		return int(math.max(f64(len) + value, 0))
	}
	return int(math.min(value, f64(len)))
}

fn stv_clamp(value f64, len int) int {
	return int(math.min(math.max(value, 0), f64(len)))
}

// stv_string_max_length bounds strings built by padStart/padEnd.
const stv_string_max_length = 1 << 20

fn stv_index_of(s []u16, search []u16, from int) int {
	if search.len == 0 {
		return if from <= s.len { from } else { -1 }
	}
	for i := from; i + search.len <= s.len; i++ {
		if s[i..i + search.len] == search {
			return i
		}
	}
	return -1
}

fn stv_trim_units(s []u16, start bool, end bool) []u16 {
	mut a := 0
	mut b := s.len
	if start {
		for a < b && is_js_space(rune(s[a])) {
			a++
		}
	}
	if end {
		for b > a && is_js_space(rune(s[b - 1])) {
			b--
		}
	}
	return s[a..b].clone()
}

// stv_string_method calls a String.prototype method on the string `s`.
fn stv_string_method(name string, s []u16, args []JsAny) ?JsAny {
	arg := fn [args] (i int) JsAny {
		return if i < args.len { args[i] } else { js_any_undefined() }
	}
	len := s.len
	match name {
		'at' {
			rel := stv_to_integer(arg(0))?
			k := if rel >= 0 { rel } else { f64(len) + rel }
			if k < 0 || k >= len {
				return js_any_undefined()
			}
			return js_any_string([s[int(k)]])
		}
		'charAt', 'charCodeAt', 'codePointAt' {
			pos := stv_to_integer(arg(0))?
			if pos < 0 || pos >= len {
				return match name {
					'charAt' { js_any_string([]u16{}) }
					'charCodeAt' { js_any_number(math.nan()) }
					else { js_any_undefined() }
				}
			}
			i := int(pos)
			if name == 'charAt' {
				return js_any_string([s[i]])
			}
			mut code := u32(s[i])
			if name == 'codePointAt' && code >= 0xd800 && code <= 0xdbff && i + 1 < len
				&& s[i + 1] >= 0xdc00 && s[i + 1] <= 0xdfff {
				code = 0x10000 + ((code - 0xd800) << 10) + (u32(s[i + 1]) - 0xdc00)
			}
			return js_any_number(code)
		}
		'concat' {
			mut out := s.clone()
			for a in args {
				out << stv_to_string(a)?
			}
			return js_any_string(out)
		}
		'endsWith', 'startsWith', 'includes' {
			if arg(0).kind == .regexp_ {
				return none
			}
			search := stv_to_string(arg(0))?
			if name == 'endsWith' {
				end := if arg(1).kind == .undefined_ {
					len
				} else {
					stv_clamp(stv_to_integer(arg(1))?, len)
				}
				start := end - search.len
				return js_any_bool(start >= 0 && s[start..end] == search)
			}
			start := stv_clamp(stv_to_integer(arg(1))?, len)
			if name == 'startsWith' {
				return js_any_bool(start + search.len <= len && s[start..start + search.len] == search)
			}
			return js_any_bool(stv_index_of(s, search, start) >= 0)
		}
		'indexOf' {
			search := stv_to_string(arg(0))?
			start := stv_clamp(stv_to_integer(arg(1))?, len)
			return js_any_number(stv_index_of(s, search, start))
		}
		'lastIndexOf' {
			search := stv_to_string(arg(0))?
			num := stv_to_number(arg(1))?
			pos := if math.is_nan(num) { math.inf(1) } else { stv_to_integer(js_any_number(num))? }
			start := stv_clamp(pos, len)
			for i := math.min(start, len - search.len); i >= 0; i-- {
				if s[i..i + search.len] == search {
					return js_any_number(i)
				}
			}
			return js_any_number(-1)
		}
		'padEnd', 'padStart' {
			max_length := stv_to_integer(arg(0))?
			if max_length <= len {
				return js_any_string(s)
			}
			fill := if arg(1).kind == .undefined_ { [u16(` `)] } else { stv_to_string(arg(1))? }
			if fill.len == 0 {
				return js_any_string(s)
			}
			if max_length > stv_string_max_length {
				return none
			}
			mut pad := []u16{}
			for pad.len < int(max_length) - len {
				pad << fill
			}
			pad = pad[..int(max_length) - len].clone()
			mut out := []u16{}
			if name == 'padStart' {
				out << pad
				out << s
			} else {
				out << s
				out << pad
			}
			return js_any_string(out)
		}
		'slice' {
			from := stv_relative(stv_to_integer(arg(0))?, len)
			to := if arg(1).kind == .undefined_ {
				len
			} else {
				stv_relative(stv_to_integer(arg(1))?, len)
			}
			return js_any_string(if from < to { s[from..to].clone() } else { []u16{} })
		}
		'substring' {
			a := stv_clamp(stv_to_integer(arg(0))?, len)
			b := if arg(1).kind == .undefined_ {
				len
			} else {
				stv_clamp(stv_to_integer(arg(1))?, len)
			}
			return js_any_string(s[math.min(a, b)..math.max(a, b)].clone())
		}
		'substr' {
			mut start := stv_to_integer(arg(0))?
			if math.is_inf(start, -1) {
				start = 0
			} else if start < 0 {
				start = math.max(f64(len) + start, 0)
			} else {
				start = math.min(start, f64(len))
			}
			size := if arg(1).kind == .undefined_ {
				f64(len)
			} else {
				math.min(math.max(stv_to_integer(arg(1))?, 0), f64(len))
			}
			end := math.min(start + size, f64(len))
			return js_any_string(if start < end { s[int(start)..int(end)].clone() } else { []u16{} })
		}
		'toString' {
			return js_any_string(s)
		}
		'toUpperCase' {
			return js_any_string(jsregexp.js_to_upper(s))
		}
		'normalize' {
			// ToString(form), NFC when it is undefined; a RangeError for another form
			// (unicode_normalization.v).
			form := if arg(0).kind == .undefined_ {
				'NFC'
			} else {
				stv_units_string(stv_to_string(arg(0))?)
			}
			if form !in ['NFC', 'NFD', 'NFKC', 'NFKD'] {
				return none
			}
			return js_any_string(js_normalize(s, form))
		}
		'toLowerCase' {
			return js_any_string(jsregexp.js_to_lower(s))
		}
		'trim' {
			return js_any_string(stv_trim_units(s, true, true))
		}
		'trimStart' {
			return js_any_string(stv_trim_units(s, true, false))
		}
		'trimEnd' {
			return js_any_string(stv_trim_units(s, false, true))
		}
		else {
			return none
		}
	}
}

// stv_same_value_zero ports SameValueZero (Array.prototype.includes).
fn stv_same_value_zero(a JsAny, b JsAny) bool {
	if a.kind == .number_ && b.kind == .number_ && math.is_nan(a.number) && math.is_nan(b.number) {
		return true
	}
	return stv_strict_equal(a, b)
}

// stv_array_like is what the generic array methods read from their receiver: the elements of an
// array, or of an object with a length (a hole where an index is missing); none for another
// receiver, and for more than stv_string_max_length elements.
fn stv_array_like(object JsAny) ?[]JsAny {
	if object.kind == .array_ {
		return object.elements
	}
	if object.kind != .object_ {
		return none
	}
	length := stv_length_of_array_like(object)?
	if length > f64(stv_string_max_length) {
		return none
	}
	mut out := []JsAny{cap: int(length)}
	for i in 0 .. int(length) {
		key := i.str()
		out << if stv_has_property(object, key) {
			stv_get(object, js_any_text(key))?
		} else {
			JsAny{
				kind: .hole_
			}
		}
	}
	return out
}

// stv_callback_truth calls a builtin function as a callback of the array methods, for the truth
// of what it returns; none where the call throws, or where veslint does not tell what it returns:
// the functions it evaluates, those whose result is truthy whatever the arguments (Object an
// object, Date a string, Array an array of three, Symbol a symbol), and Number.isInteger and
// Number.isSafeInteger; not the other builtins (the callback limit).
fn stv_callback_truth(f JsAny, this JsAny, args []JsAny, mut ctx StvContext) ?bool {
	match f.name {
		'Object', 'Date', 'Array' {
			return true
		}
		'Symbol' {
			// ToString(description) unless it is undefined.
			if args.len > 0 && args[0].kind != .undefined_ {
				stv_to_string(args[0])?
			}
			return true
		}
		'Number.isInteger', 'Number.isSafeInteger' {
			a := if args.len > 0 { args[0] } else { js_any_undefined() }
			if a.kind != .number_ || math.is_nan(a.number) || math.is_inf(a.number, 0)
				|| a.number != math.trunc(a.number) {
				return false
			}
			return f.name == 'Number.isInteger' || math.abs(a.number) <= 9007199254740991
		}
		else {}
	}
	if f.name !in stv_call_allowed && f.name !in stv_call_pass_through {
		return none
	}
	return stv_to_boolean(stv_call_function(f, this, true, args, mut ctx)?)
}

// stv_array_method calls an Array.prototype method on the array `this`.
fn stv_array_method(name string, this JsAny, args []JsAny, mut ctx StvContext) ?JsAny {
	arg := fn [args] (i int) JsAny {
		return if i < args.len { args[i] } else { js_any_undefined() }
	}
	elements := stv_array_like(this)?
	len := elements.len
	match name {
		'at' {
			rel := stv_to_integer(arg(0))?
			k := if rel >= 0 { rel } else { f64(len) + rel }
			if k < 0 || k >= len || elements[int(k)].kind == .hole_ {
				return js_any_undefined()
			}
			return elements[int(k)]
		}
		'concat' {
			// A receiver that is not an array is not spread: it is the first element.
			mut out := if this.kind == .array_ { elements.clone() } else { [this] }
			for a in args {
				if a.kind == .array_ {
					out << a.elements
				} else {
					out << a
				}
			}
			return JsAny{
				kind:     .array_
				id:       ctx.new_id()
				elements: out
			}
		}
		'includes', 'indexOf' {
			if len == 0 {
				return if name == 'includes' { js_any_bool(false) } else { js_any_number(-1) }
			}
			n := stv_to_integer(arg(1))?
			start := if n >= 0 {
				int(math.min(n, f64(len)))
			} else {
				int(math.max(f64(len) + n, 0))
			}
			for i in start .. len {
				e := elements[i]
				if name == 'includes' {
					value := if e.kind == .hole_ { js_any_undefined() } else { e }
					if stv_same_value_zero(value, arg(0)) {
						return js_any_bool(true)
					}
				} else if e.kind != .hole_ && stv_strict_equal(e, arg(0)) {
					return js_any_number(i)
				}
			}
			return if name == 'includes' { js_any_bool(false) } else { js_any_number(-1) }
		}
		'lastIndexOf' {
			if len == 0 {
				return js_any_number(-1)
			}
			n := if args.len > 1 { stv_to_integer(arg(1))? } else { f64(len - 1) }
			start := if n >= 0 { math.min(n, f64(len - 1)) } else { f64(len) + n }
			for i := int(start); i >= 0; i-- {
				if elements[i].kind != .hole_ && stv_strict_equal(elements[i], arg(0)) {
					return js_any_number(i)
				}
			}
			return js_any_number(-1)
		}
		'keys', 'values', 'entries' {
			// An Array Iterator: the indexes, the elements (a hole is undefined) or both.
			mut items := []JsAny{cap: len}
			for i, e in elements {
				value := if e.kind == .hole_ { js_any_undefined() } else { e }
				items << match name {
					'keys' { js_any_number(i) }
					'values' { value }
					else { ctx.new_array([js_any_number(i), value]) }
				}
			}
			return ctx.new_iterator('Array Iterator', items)
		}
		'join', 'toString' {
			if name == 'toString' && this.kind != .array_ {
				// The join of the receiver, called; Object.prototype.toString when it has none.
				join := stv_get(this, js_any_text('join'))?
				if join.kind != .function_ {
					return js_any_text('[object Object]')
				}
				// A join that is this toString again calls itself without end (a RangeError in V8).
				if join.name !in stv_call_allowed || join.name == 'Array.prototype.toString' {
					return none
				}
				return stv_call_function(join, this, true, []JsAny{}, mut ctx)
			}
			separator := if name == 'toString' || arg(0).kind == .undefined_ {
				[u16(`,`)]
			} else {
				stv_to_string(arg(0))?
			}
			return js_any_string(stv_join(JsAny{ kind: .array_, elements: elements }, separator)?)
		}
		'slice' {
			from := stv_relative(stv_to_integer(arg(0))?, len)
			to := if arg(1).kind == .undefined_ {
				len
			} else {
				stv_relative(stv_to_integer(arg(1))?, len)
			}
			return JsAny{
				kind:     .array_
				id:       ctx.new_id()
				elements: if from < to { elements[from..to].clone() } else { []JsAny{} }
			}
		}
		'every', 'some', 'filter', 'find', 'findIndex' {
			// The callback is called with the element, its index and the array, and `thisArg` as
			// `this`; every, some and filter skip the holes, find and findIndex take them as
			// undefined. Only the truth of what it returns matters (stv_callback_truth).
			callback := arg(0)
			if callback.kind != .function_ {
				return none
			}
			mut kept := []JsAny{}
			for i, e in elements {
				if e.kind == .hole_ && name !in ['find', 'findIndex'] {
					continue
				}
				value := if e.kind == .hole_ { js_any_undefined() } else { e }
				truth := stv_callback_truth(callback, arg(1), [value, js_any_number(i), this], mut
					ctx)?
				match name {
					'every' {
						if !truth {
							return js_any_bool(false)
						}
					}
					'some' {
						if truth {
							return js_any_bool(true)
						}
					}
					'find' {
						if truth {
							return value
						}
					}
					'findIndex' {
						if truth {
							return js_any_number(i)
						}
					}
					else {
						if truth {
							kept << value
						}
					}
				}
			}
			return match name {
				'every' { js_any_bool(true) }
				'some' { js_any_bool(false) }
				'find' { js_any_undefined() }
				'findIndex' { js_any_number(-1) }
				else { ctx.new_array(kept) }
			}
		}
		'flat' {
			// ToIntegerOrInfinity(depth), 1 when it is undefined and 0 when it is negative.
			mut depth := 1.0
			if arg(0).kind != .undefined_ {
				depth = math.max(stv_to_integer(arg(0))?, 0.0)
			}
			mut out := []JsAny{}
			stv_flatten(mut out, elements, depth, 0)?
			return ctx.new_array(out)
		}
		else {
			return none
		}
	}
}
