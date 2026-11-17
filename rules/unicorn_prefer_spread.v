module rules

import estree
import jsregexp
import math
import treesitter
import time
import tsgo { TypeResponse }

// Port of the `unicorn/prefer-spread` rule of eslint-plugin-unicorn 79.0.0 (it has no options),
// with its fixes and suggestions, and of the helpers it imports from rules/shared/
// (array-concat-in-loop.js, array-range.js, buffer-reference.js, for-of-collection-loop.js and
// typed-array.js). Like unicorn, it reads TypeScript's types (here tsgo's) only when the parser
// has a program (withTypeInformation), and suggests a spread instead of fixing only in a TypeScript
// file (isTypeScriptFile, which a .vue file is not).

const upsp_messages = {
	'array-from':                 'Prefer the spread operator over `Array.from(…)`.'
	'array-concat':               'Prefer the spread operator over `Array#concat(…)`.'
	'array-slice':                'Prefer the spread operator over `Array#slice()`.'
	'array-to-spliced':           'Prefer the spread operator over `Array#toSpliced()`.'
	'for-of':                     'Prefer the spread operator over this `for…of` loop.'
	'spread':                     'Use the spread operator.'
	'argument-is-spreadable':     'First argument is an `array`.'
	'argument-is-not-spreadable': 'First argument is not an `array`.'
	'test-argument':              'Test first argument with `Array.isArray(…)`.'
	'spread-all-arguments':       'Spread all unknown arguments.'
}

// The three states of the rule's array tests: `true`, `false` and `undefined`.
const upsp_no = 0
const upsp_yes = 1
const upsp_unknown = -1

const upsp_ignored_slice_callee = ['arrayBuffer', 'blob', 'buffer', 'file', 'this']
const upsp_array_type_names = ['Array', 'ReadonlyArray']
const upsp_known_non_array_type_names = ['ApolloLink', 'Buffer']
const upsp_non_array_factory_names = ['String', 'Number', 'Boolean', 'BigInt', 'RegExp']
const upsp_unknown_type_names = ['any', 'error', 'unknown']
const upsp_type_annotation_expression_types = [estree.NodeType.ts_as_expression, .ts_type_assertion,
	.ts_satisfies_expression]
const upsp_non_array_type_annotation_types = [estree.NodeType.ts_never_keyword, .ts_void_keyword,
	.ts_null_keyword, .ts_undefined_keyword, .ts_string_keyword, .ts_number_keyword,
	.ts_boolean_keyword, .ts_big_int_keyword, .ts_symbol_keyword, .ts_object_keyword, .ts_type_literal,
	.ts_function_type, .ts_constructor_type, .ts_literal_type]

// upsp_typed_array_types is shared/typed-array.js.
const upsp_typed_array_types = ['Int8Array', 'Uint8Array', 'Uint8ClampedArray', 'Int16Array',
	'Uint16Array', 'Int32Array', 'Uint32Array', 'Float16Array', 'Float32Array', 'Float64Array',
	'BigInt64Array', 'BigUint64Array']

// TypedArray and ArrayBuffer constructors: they have `.slice()`, but spreading them either does not
// work (ArrayBuffer has no iterator) or changes the type (a TypedArray becomes number[]).
const upsp_typed_array_constructors = ['Int8Array', 'Uint8Array', 'Uint8ClampedArray', 'Int16Array',
	'Uint16Array', 'Int32Array', 'Uint32Array', 'Float16Array', 'Float32Array', 'Float64Array',
	'BigInt64Array', 'BigUint64Array', 'ArrayBuffer', 'SharedArrayBuffer']

// `ArrayBuffer` and `DataView` are array-like but not iterable: `Array.from()` accepts them.
const upsp_non_iterable_constructors = ['ArrayBuffer', 'SharedArrayBuffer', 'DataView']

// What shared/buffer-reference.js needs.
const upsp_buffer_import_sources = ['buffer', 'node:buffer']
const upsp_global_object_names = ['globalThis', 'window', 'self', 'global']

fn (mut c Checker) lint_unicorn_prefer_spread(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for node in 0 .. t.nodes.len {
		typ := t.typ(node)
		if typ == .for_of_statement {
			stats.checked++
			if f := c.upsp_for_of(mut ctx, node) {
				findings << f
			}
			continue
		}
		if typ != .call_expression {
			continue
		}
		stats.checked++
		if f := c.upsp_array_from(mut ctx, node) {
			findings << f
		}
		if f := c.upsp_concat(mut ctx, node) {
			findings << f
		}
		if f := c.upsp_slice(mut ctx, node) {
			findings << f
		}
		if f := c.upsp_to_spliced(mut ctx, node) {
			findings << f
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// --- Small syntax helpers

fn upsp_is_array_literal(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .array_expression
}

fn upsp_elements(t &estree.EsTree, node int) []int {
	return t.list(node, .elements) or { []int{} }
}

fn upsp_arguments(t &estree.EsTree, node int) []int {
	return t.list(node, .arguments) or { []int{} }
}

fn upsp_name(t &estree.EsTree, node int) string {
	if node < 0 || t.typ(node) != .identifier {
		return ''
	}
	return t.string_of(node, .name) or { '' }
}

// upsp_is_identifier_named ports isIdentifierNamed.
fn upsp_is_identifier_named(t &estree.EsTree, node int, name string) bool {
	return node >= 0 && t.typ(node) == .identifier && (t.string_of(node, .name) or { '' }) == name
}

fn upsp_is_function(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) in [.function_declaration, .function_expression,
		.arrow_function_expression]
}

fn upsp_is_loop(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) in [.do_while_statement, .for_in_statement, .for_of_statement,
		.for_statement, .while_statement]
}

// upsp_has_array_holes ports hasArrayHoles.
fn upsp_has_array_holes(t &estree.EsTree, node int) bool {
	return upsp_elements(t, node).any(it < 0)
}

// upsp_is_to_array_call ports isToArrayCall: `foo.toArray()`.
fn upsp_is_to_array_call(t &estree.EsTree, node int) bool {
	return un_is_method_call(t, node,
		methods:          ['toArray']
		arguments_length: 0
		optional_call:    false
		optional_member:  false
	)
}

// upsp_is_prefer_iterator_concat_array_literal ports isPreferIteratorConcatArrayLiteral: an array
// of two or more spread elements, none of a `.toArray()` (prefer-iterator-concat reports it).
fn upsp_is_prefer_iterator_concat_array_literal(t &estree.EsTree, node int) bool {
	if !upsp_is_array_literal(t, node) {
		return false
	}
	elements := upsp_elements(t, node)
	return elements.len >= 2 && elements.all(it >= 0 && t.typ(it) == .spread_element)
		&& elements.all(!upsp_is_to_array_call(t, t.node(it, .argument) or { -1 }))
}

// upsp_last_token_but_one is sourceCode.getLastToken(node, 1).
fn upsp_last_token_but_one(t &estree.EsTree, tokens &SourceTokens, node int) ?SourceToken {
	inside := tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
	if inside.len < 2 {
		return none
	}
	return inside[inside.len - 2]
}

// upsp_has_trailing_comma ports isArrayLiteralHasTrailingComma.
fn (c &Checker) upsp_has_trailing_comma(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	if un_is_empty_array(t, node) {
		return false
	}
	token := upsp_last_token_but_one(t, tokens, node) or { return false }
	return c.token_is(token, ',')
}

// upsp_comma_after is sourceCode.getTokenAfter(node, isCommaToken): the first comma after the
// node.
fn (c &Checker) upsp_comma_after(tokens &SourceTokens, offset int) ?SourceToken {
	mut at := offset
	for {
		token := tokens.after(at, false)?
		if c.token_is(token, ',') {
			return token
		}
		at = token.end
	}
	return none
}

// upsp_is_static_string ports isStaticString.
fn (mut c Checker) upsp_is_static_string(mut ctx UnCtx, node int) bool {
	value := c.un_static_value_if_no_side_effects(mut ctx, node) or { return false }
	return value.value.kind == .string_
}

// upsp_is_outer_comments_preservable ports isArrayLiteralOuterCommentsPreservable: an array
// literal without holes, in parentheses with comments between them and the array.
fn (c &Checker) upsp_is_outer_comments_preservable(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	if upsp_has_array_holes(t, node) {
		return false
	}
	parentheses := c.un_parentheses(t, tokens, node)
	if parentheses.len == 0 {
		return false
	}
	return tokens.comments_exist_between(parentheses[0].end, t.nodes[node].start)
		|| tokens.comments_exist_between(t.nodes[node].end, parentheses.last().start)
}

// --- Fixes

// UpspConcatArgument is an argument of `.concat()` as fixConcat merges it.
struct UpspConcatArgument {
	node             int
	is_array_literal bool
	is_spreadable    bool
	test_argument    bool
}

// upsp_fix_concat ports fixConcat: `array.concat(…)` becomes `[...array, …]`, with the first
// `fixable` arguments (all of them, or the first ones) merged into the array.
fn (mut c Checker) upsp_fix_concat(mut ctx UnCtx, node int, fixable []UpspConcatArgument) ?Fix {
	t := ctx.t
	tokens := ctx.tokens
	callee := t.node(node, .callee)?
	array := t.node(callee, .object)?
	arguments := upsp_arguments(t, node)
	array_start, array_end := c.un_parenthesized_range(t, tokens, array)
	is_array_literal := upsp_is_array_literal(t, array)
	array_has_trailing_comma := is_array_literal && c.upsp_has_trailing_comma(t, tokens, array)
	mut fixes := []Fix{}
	// The fixed code always starts with `[`.
	if !is_array_literal
		&& c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false), '[') {
		fixes << fix_insert_at(t.nodes[node].start, ';')
	}
	if arguments.len == fixable.len {
		fixes << c.un_remove_method_call(t, tokens, node)
	} else {
		// removeArguments
		first := arguments[0]
		last := arguments[fixable.len - 1]
		start, _ := c.un_parenthesized_range(t, tokens, first)
		comma := c.upsp_comma_after(tokens, t.nodes[last].end)?
		mut end := comma.end
		for r in c.src[end..].runes() {
			if !is_js_space(r) {
				break
			}
			end += r.length_in_bytes()
		}
		fixes << fix_remove_range(start, end)
	}
	text := c.upsp_concat_fixed_text(t, tokens, array, is_array_literal, array_has_trailing_comma,
		fixable)
	if is_array_literal {
		closing := un_last_token(t, tokens, array)?
		fixes << fix_insert_at(closing.start, text)
	} else {
		// The array is already accessing `.concat`: no extra `()` are needed.
		fixes << fix_insert_at(array_start, '[...')
		fixes << fix_insert_at(array_end, text)
		fixes << fix_insert_at(array_end, ']')
	}
	has_fix, fix := c.merge_fixes(fixes) or { return none }
	if !has_fix {
		return none
	}
	return fix
}

// upsp_array_elements_text ports getArrayLiteralElementsText: the text inside the brackets,
// without the trailing comma unless it is kept.
fn (c &Checker) upsp_array_elements_text(t &estree.EsTree, tokens &SourceTokens, node int, keep_trailing_comma bool) string {
	start := t.nodes[node].start
	if !keep_trailing_comma && c.upsp_has_trailing_comma(t, tokens, node) {
		comma := upsp_last_token_but_one(t, tokens, node) or { return '' }
		return c.src[start + 1..comma.start]
	}
	return c.src[start + 1..t.nodes[node].end - 1]
}

// upsp_concat_fixed_text ports getFixedText of fixConcat.
fn (c &Checker) upsp_concat_fixed_text(t &estree.EsTree, tokens &SourceTokens, array int, is_array_literal bool, array_has_trailing_comma bool, fixable []UpspConcatArgument) string {
	non_empty := fixable.filter(!it.is_array_literal || !un_is_empty_array(t, it.node))
	if non_empty.len == 0 {
		return ''
	}
	last := non_empty.last()
	mut parts := []string{}
	for argument in non_empty {
		if argument.is_array_literal {
			parts << if c.upsp_is_outer_comments_preservable(t, tokens, argument.node) {
				'...${c.un_parenthesized_text(t, tokens, argument.node)}'
			} else {
				c.upsp_array_elements_text(t, tokens, argument.node, argument.node == last.node)
			}
			continue
		}
		text := c.un_parenthesized_text(t, tokens, argument.node)
		if argument.test_argument {
			parts << '...(Array.isArray(${text}) ? ${text} : [${text}])'
			continue
		}
		parts << if argument.is_spreadable { '...${text}' } else { text }
	}
	mut text := parts.join(', ')
	if text == '' {
		return ''
	}
	if is_array_literal {
		if !un_is_empty_array(t, array) {
			text = ' ${text}'
			if !array_has_trailing_comma {
				text = ',${text}'
			}
			if array_has_trailing_comma && (!last.is_array_literal
				|| !c.upsp_has_trailing_comma(t, tokens, last.node)) {
				text += ','
			}
		}
	} else {
		text = ', ${text}'
	}
	return text
}

// upsp_concat_argument_spreadable ports getConcatArgumentSpreadable: none for an argument that is
// not known to be an array or not.
fn (mut c Checker) upsp_concat_argument_spreadable(mut ctx UnCtx, node int) ?UpspConcatArgument {
	t := ctx.t
	if t.typ(node) == .spread_element || c.upsp_is_array_constructor_with_one_argument(mut ctx, node) {
		return none
	}
	if upsp_is_array_literal(t, node) {
		return UpspConcatArgument{
			node:             node
			is_array_literal: true
		}
	}
	value := c.un_static_value_if_no_side_effects(mut ctx, node)?
	return UpspConcatArgument{
		node:          node
		is_spreadable: value.value.kind == .array_
	}
}

// upsp_concat_fixable_arguments ports getConcatFixableArguments: the leading arguments that are
// known to be arrays or not.
fn (mut c Checker) upsp_concat_fixable_arguments(mut ctx UnCtx, arguments []int) []UpspConcatArgument {
	mut fixable := []UpspConcatArgument{}
	for node in arguments {
		result := c.upsp_concat_argument_spreadable(mut ctx, node) or { break }
		fixable << result
	}
	return fixable
}

// upsp_fix_array_from ports fixArrayFrom: `Array.from(x)` becomes `[...x]`.
fn (mut c Checker) upsp_fix_array_from(mut ctx UnCtx, node int) ?Fix {
	t := ctx.t
	tokens := ctx.tokens
	object := upsp_arguments(t, node)[0]
	mut fixes := []Fix{}
	if c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false), '[') {
		fixes << fix_insert_at(t.nodes[node].start, ';')
	}
	// `Array.from` densifies holes: a holey array literal must be spread, not used directly.
	object_text := if upsp_is_array_literal(t, object) && !upsp_has_array_holes(t, object) {
		c.src[t.nodes[object].start..t.nodes[object].end]
	} else {
		'[...${c.un_parenthesized_text(t, tokens, object)}]'
	}
	fixes << fix_replace_range(t.nodes[node].start, t.nodes[node].end, object_text)
	has_fix, fix := c.merge_fixes(fixes) or { return none }
	if !has_fix {
		return none
	}
	return fix
}

// upsp_method_call_to_spread ports methodCallToSpread: `array.slice()` becomes `[...array]`.
fn (mut c Checker) upsp_method_call_to_spread(mut ctx UnCtx, node int) ?Fix {
	t := ctx.t
	tokens := ctx.tokens
	mut fixes := []Fix{}
	if c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false), '[') {
		fixes << fix_insert_at(t.nodes[node].start, ';')
	}
	fixes << fix_insert_at(t.nodes[node].start, '[...')
	fixes << fix_insert_at(t.nodes[node].end, ']')
	// The receiver is already accessing `.slice` or `.toSpliced`: no extra `()` are needed.
	fixes << c.un_remove_method_call(t, tokens, node)
	has_fix, fix := c.merge_fixes(fixes) or { return none }
	if !has_fix {
		return none
	}
	return fix
}

// upsp_should_suggest_spread ports shouldSuggestSpread: removing the outer call can change the
// contextual typing of an inline source expression, so the fix is a suggestion unless the call
// initializes an unannotated variable and the types say that the copy has the type of the source.
fn (mut c Checker) upsp_should_suggest_spread(mut ctx UnCtx, node int, array int) bool {
	// Neither a TypeScript file nor a SourceFile of ScriptKind TS or TSX.
	if !c.is_typescript_file() && !c.is_ts_script_kind() {
		return false
	}
	t := ctx.t
	parent := t.nodes[node].parent
	if array < 0 || t.typ(array) != .identifier || parent < 0
		|| t.typ(parent) != .variable_declarator || (t.node(parent, .init) or { -1 }) != node {
		return true
	}
	id := t.node(parent, .id) or { return true }
	if t.typ(id) != .identifier || t.node(id, .type_annotation) != none {
		return true
	}
	// Array literals can infer different types through contextual typing or const assertions,
	// unlike the original array-producing call.
	typ := c.un_ts_type(ctx, node) or { return true }
	source_type := c.un_ts_type(ctx, array) or { return true }
	if !(c.is_array(typ) or { return true }) {
		return true
	}
	symbol := c.symbol_of(typ) or { return true }
	if symbol.name != 'Array' || !(c.from_default_library(symbol.declarations) or { return true }) {
		return true
	}
	if !((c.is_array(source_type) or { return true }) || source_type.is_tuple_type) {
		return true
	}
	index := c.number_index_type(typ) or { return true }
	source_index := c.number_index_type(source_type) or { return true }
	return index.id != source_index.id
}

// upsp_spread_fix ports getSpreadFix: the fix, or a suggestion with it.
fn (mut c Checker) upsp_spread_fix(mut ctx UnCtx, finding Finding, node int, fix ?Fix, array int) Finding {
	f := fix or { return finding }
	if c.upsp_should_suggest_spread(mut ctx, node, array) {
		return Finding{
			...finding
			suggestions: [Suggestion{
				message_id: 'spread'
				fix:        f
			}]
		}
	}
	return Finding{
		...finding
		has_fix: true
		fix:     f
	}
}

// --- What a receiver is

// upsp_is_class_name ports isClassName: `Foo` or `foo.Foo`, a name that starts with a capital
// letter and is not all in capitals.
fn upsp_is_class_name(t &estree.EsTree, from int) bool {
	mut node := from
	if t.typ(node) == .member_expression {
		node = t.node(node, .property) or { return false }
	}
	if t.typ(node) != .identifier {
		return false
	}
	name := t.string_of(node, .name) or { return false }
	if name.len < 2 || name[0] < `A` || name[0] > `Z` {
		return false
	}
	units := utf16_units(name)
	return jsregexp.js_to_upper(units) != units
}

// upsp_is_global_identifier_named ports isGlobalIdentifierNamed.
fn (mut c Checker) upsp_is_global_identifier_named(mut ctx UnCtx, node int, name string) bool {
	return node >= 0 && upsp_name(ctx.t, node) == name && c.un_is_global_identifier(ctx, node)
}

// upsp_is_global_member_expression ports isGlobalMemberExpression: `global.Array`,
// `globalThis['Array']`.
fn (mut c Checker) upsp_is_global_member_expression(mut ctx UnCtx, node int, object_name string, property_name string) bool {
	t := ctx.t
	if t.typ(node) != .member_expression
		|| !c.upsp_is_global_identifier_named(mut ctx, t.node(node, .object) or { -1 }, object_name) {
		return false
	}
	property := t.node(node, .property) or { return false }
	if !(t.flag(node, .computed) or { false }) {
		return upsp_name(t, property) == property_name
	}
	value := c.un_static_value_if_no_side_effects(mut ctx, property) or { return false }
	return value.value.kind == .string_ && (js_any_string_value(value.value) or { '' }) == property_name
}

// upsp_is_global_array_reference ports isGlobalArrayReference.
fn (mut c Checker) upsp_is_global_array_reference(mut ctx UnCtx, node int) bool {
	return c.upsp_is_global_identifier_named(mut ctx, node, 'Array')
		|| c.upsp_is_global_member_expression(mut ctx, node, 'global', 'Array')
		|| c.upsp_is_global_member_expression(mut ctx, node, 'globalThis', 'Array')
}

// upsp_is_array_constructor_call ports isArrayConstructorCall: `Array(…)`, `new Array(…)`.
fn (mut c Checker) upsp_is_array_constructor_call(mut ctx UnCtx, from int) bool {
	t := ctx.t
	node := un_unwrap_chain_and_ts_expression(t, from)
	return node >= 0 && t.typ(node) in [.call_expression, .new_expression]
		&& c.upsp_is_global_array_reference(mut ctx, t.node(node, .callee) or { return false })
}

// upsp_is_array_constructor_with_one_argument ports isArrayConstructorWithOneArgument of the rule:
// `Array(n)` makes an array of n holes.
fn (mut c Checker) upsp_is_array_constructor_with_one_argument(mut ctx UnCtx, from int) bool {
	t := ctx.t
	node := un_unwrap_chain_and_ts_expression(t, from)
	return node >= 0 && t.typ(node) in [.call_expression, .new_expression]
		&& upsp_arguments(t, node).len == 1
		&& c.upsp_is_global_array_reference(mut ctx, t.node(node, .callee) or { return false })
}

// upsp_is_typed_array_construction ports isTypedArrayConstruction: `new Uint8Array(…)`,
// `Uint8Array.from(…)`.
fn upsp_is_typed_array_construction(t &estree.EsTree, node int) bool {
	if t.typ(node) == .call_expression && !(t.flag(node, .optional) or { false }) {
		callee := t.node(node, .callee) or { return false }
		if t.typ(callee) != .member_expression || (t.flag(callee, .computed) or { false })
			|| (t.flag(callee, .optional) or { false }) {
			return false
		}
		object := t.node(callee, .object) or { return false }
		property := t.node(callee, .property) or { return false }
		return t.typ(object) == .identifier && upsp_name(t, object) in upsp_typed_array_constructors
			&& upsp_name(t, property) in ['from', 'of']
	}
	if t.typ(node) != .new_expression {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	return upsp_name(t, callee) in upsp_typed_array_constructors
}

// upsp_is_non_iterable_construction ports isNonIterableConstruction: `new ArrayBuffer(…)`.
fn upsp_is_non_iterable_construction(t &estree.EsTree, node int) bool {
	if t.typ(node) != .new_expression {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	return upsp_name(t, callee) in upsp_non_iterable_constructors
}

// upsp_is_method_named ports isMethodNamed: `foo.name(…)`.
fn upsp_is_method_named(t &estree.EsTree, node int, name string) bool {
	if t.typ(node) != .call_expression {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	return t.typ(callee) == .member_expression
		&& upsp_name(t, t.node(callee, .property) or { -1 }) == name
}

// upsp_is_not_array ports isNotArray.
fn (mut c Checker) upsp_is_not_array(mut ctx UnCtx, node int) bool {
	t := ctx.t
	// `super` is not a value, `[...super]` does not parse.
	if t.typ(node) in [.template_literal, .literal, .binary_expression, .super]
		|| upsp_is_class_name(t, node) || upsp_is_method_named(t, node, 'join') {
		return true
	}
	value := c.un_static_value_if_no_side_effects(mut ctx, node) or { return false }
	return value.value.kind != .array_
}

// upsp_buffer_import_specifier ports getBufferImportSpecifier: the specifier of the only
// definition of the identifier, an import of `buffer` or `node:buffer`.
fn (mut c Checker) upsp_buffer_import_specifier(mut ctx UnCtx, identifier int) int {
	t := ctx.t
	if identifier < 0 || t.typ(identifier) != .identifier {
		return -1
	}
	v := c.un_find_variable(ctx, identifier)
	def := c.un_only_definition(ctx, v) or { return -1 }
	if def.kind != .import_binding {
		return -1
	}
	specifier := c.upsp_definition_node(ctx, def)
	if specifier < 0 {
		return -1
	}
	declaration := t.nodes[specifier].parent
	if declaration < 0 || t.typ(declaration) != .import_declaration {
		return -1
	}
	source := t.node(declaration, .source) or { return -1 }
	if (t.string_of(source, .value) or { '' }) !in upsp_buffer_import_sources {
		return -1
	}
	return specifier
}

// upsp_is_buffer_reference ports isBufferReference: the `Buffer` constructor, as a global,
// `globalThis.Buffer`, or an import.
fn (mut c Checker) upsp_is_buffer_reference(mut ctx UnCtx, node int) bool {
	t := ctx.t
	reference := un_unwrap_ts_expression(t, node)
	if un_is_member(t, reference, properties: ['Buffer'], computed: false) {
		object := un_unwrap_ts_expression(t, t.node(reference, .object) or { return false })
		specifier := c.upsp_buffer_import_specifier(mut ctx, object)
		return (upsp_name(t, object) in upsp_global_object_names
			&& c.un_is_global_identifier(ctx, object)) || (specifier >= 0
			&& t.typ(specifier) in [.import_namespace_specifier, .import_default_specifier])
	}
	if t.typ(reference) != .identifier {
		return false
	}
	specifier := c.upsp_buffer_import_specifier(mut ctx, reference)
	if upsp_name(t, reference) == 'Buffer' && c.un_is_global_identifier(ctx, reference) {
		return true
	}
	if specifier < 0 || t.typ(specifier) != .import_specifier {
		return false
	}
	return upsp_name(t, t.node(specifier, .imported) or { -1 }) == 'Buffer'
}

// upsp_is_known_non_array_call ports isKnownNonArrayCall: `Buffer.concat(…)`, `String(…)`.
fn (mut c Checker) upsp_is_known_non_array_call(mut ctx UnCtx, node int) bool {
	t := ctx.t
	if un_is_method_call(t, node, methods: ['concat'], optional_call: false, optional_member: false)
		&& c.upsp_is_buffer_reference(mut ctx, t.node(t.node(node, .callee) or { return false }, .object) or {
			return false
		}) {
		return true
	}
	if t.typ(node) != .call_expression {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	if t.typ(callee) != .identifier || upsp_name(t, callee) !in upsp_non_array_factory_names {
		return false
	}
	ts := t.ts_node(callee) or { return false }
	return c.es_is_global_reference(ctx.root, ts)
}

// upsp_is_known_non_array_construction ports isKnownNonArrayConstruction: `new Foo()` other than
// `new Array()`, written or bound to a `const` (one level).
fn (mut c Checker) upsp_is_known_non_array_construction(mut ctx UnCtx, from int) bool {
	t := ctx.t
	node := c.un_const_initializer(ctx.root, t, from) or { from }
	if node < 0 || t.typ(node) != .new_expression {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	if t.typ(callee) != .identifier {
		return false
	}
	return !c.upsp_is_global_identifier_named(mut ctx, callee, 'Array')
}

// upsp_is_same_binding ports isSameBinding: two identifiers of the same variable, or two
// unresolved identifiers of the same name.
fn (mut c Checker) upsp_is_same_binding(mut ctx UnCtx, left int, right int) bool {
	left_variable := c.un_find_variable(ctx, left)
	right_variable := c.un_find_variable(ctx, right)
	if left_variable >= 0 || right_variable >= 0 {
		return left_variable == right_variable
	}
	return upsp_name(ctx.t, left) == upsp_name(ctx.t, right)
}

// upsp_is_same_receiver_reference ports isSameReceiverReference.
fn (mut c Checker) upsp_is_same_receiver_reference(mut ctx UnCtx, left_node int, right_node int) bool {
	t := ctx.t
	left := un_unwrap_chain_and_ts_expression(t, left_node)
	right := un_unwrap_chain_and_ts_expression(t, right_node)
	if !c.un_is_same_reference(t, left, right) {
		return false
	}
	if t.typ(left) == .identifier && t.typ(right) == .identifier {
		return c.upsp_is_same_binding(mut ctx, left, right)
	}
	if t.typ(left) == .member_expression && t.typ(right) == .member_expression {
		if !c.upsp_is_same_receiver_reference(mut ctx, t.node(left, .object) or { -1 }, t.node(right,
			.object) or { -1 })
		{
			return false
		}
		return !(t.flag(left, .computed) or { false }) || !(t.flag(right, .computed) or { false })
			|| c.upsp_is_same_receiver_reference(mut ctx, t.node(left, .property) or { -1 },
				t.node(right, .property) or { -1 })
	}
	return true
}

// upsp_is_declarator_write_to_receiver ports isVariableDeclaratorWriteToReceiver.
fn upsp_is_declarator_write_to_receiver(t &estree.EsTree, node int, receiver int) bool {
	if t.node(node, .init) == none {
		return false
	}
	id := t.node(node, .id) or { return true }
	if t.typ(id) != .identifier || t.typ(receiver) != .identifier {
		return true
	}
	return upsp_name(t, id) == upsp_name(t, receiver)
}

// upsp_has_write_before_node ports hasWriteBeforeNode: an assignment, update or declarator
// (outside functions) between the start of `start_node` and the start of `end_node`.
fn upsp_has_write_before_node(t &estree.EsTree, start_node int, end_node int) bool {
	return upsp_has_write_in(t, start_node, t.nodes[start_node].start, t.nodes[end_node].start,
		end_node)
}

fn upsp_has_write_in(t &estree.EsTree, node int, start int, end int, receiver int) bool {
	node_start, node_end := t.nodes[node].start, t.nodes[node].end
	if node_end <= start || node_start >= end || upsp_is_function(t, node) {
		return false
	}
	if node_end <= end && (t.typ(node) in [.assignment_expression, .update_expression]
		|| (t.typ(node) == .variable_declarator
			&& upsp_is_declarator_write_to_receiver(t, node, receiver))) {
		return true
	}
	return t.children(node).any(upsp_has_write_in(t, it, start, end, receiver))
}

// upsp_is_array_is_array_call_with_argument ports isArrayIsArrayCallWithArgument:
// `Array.isArray(argument)`.
fn (mut c Checker) upsp_is_array_is_array_call_with_argument(mut ctx UnCtx, node int, argument int) bool {
	t := ctx.t
	if !un_is_method_call(t, node,
		objects:          ['Array']
		methods:          ['isArray']
		arguments_length: 1
		optional_call:    false
		optional_member:  false
	) {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	return c.upsp_is_global_identifier_named(mut ctx, t.node(callee, .object) or { -1 }, 'Array')
		&& c.upsp_is_same_receiver_reference(mut ctx, upsp_arguments(t, node)[0], argument)
}

// upsp_array_is_array_test_state ports getArrayIsArrayTestState.
fn (mut c Checker) upsp_array_is_array_test_state(mut ctx UnCtx, node int, argument int) int {
	t := ctx.t
	if c.upsp_is_array_is_array_call_with_argument(mut ctx, node, argument) {
		return upsp_yes
	}
	if t.typ(node) == .unary_expression && (t.string_of(node, .operator) or { '' }) == '!'
		&& c.upsp_is_array_is_array_call_with_argument(mut ctx, t.node(node, .argument) or { -1 },
			argument) {
		return upsp_no
	}
	return upsp_unknown
}

// upsp_is_descendant_of ports isDescendantOf.
fn upsp_is_descendant_of(t &estree.EsTree, from int, ancestor int) bool {
	mut node := from
	for node >= 0 {
		if node == ancestor {
			return true
		}
		node = t.nodes[node].parent
	}
	return false
}

// upsp_is_not_array_by_array_is_array_test ports isNotArrayByArrayIsArrayTest: the node is in the
// branch of an `if (Array.isArray(node))` where it is not an array, and nothing is written there
// before it.
fn (mut c Checker) upsp_is_not_array_by_array_is_array_test(mut ctx UnCtx, node int) bool {
	t := ctx.t
	mut ancestor := t.nodes[node].parent
	for ; ancestor >= 0; ancestor = t.nodes[ancestor].parent {
		if upsp_is_function(t, ancestor) {
			break
		}
		if t.typ(ancestor) != .if_statement {
			continue
		}
		array_state := c.upsp_array_is_array_test_state(mut ctx, t.node(ancestor, .test) or {
			continue
		}, node)
		non_array_branch := if array_state == upsp_no {
			t.node(ancestor, .consequent) or { -1 }
		} else {
			t.node(ancestor, .alternate) or { -1 }
		}
		if non_array_branch < 0 || !upsp_is_descendant_of(t, node, non_array_branch)
			|| upsp_has_write_before_node(t, non_array_branch, node) {
			continue
		}
		if array_state != upsp_unknown {
			return true
		}
	}
	return false
}

// upsp_syntactic_receiver_array_state ports getSyntacticReceiverArrayState.
fn (mut c Checker) upsp_syntactic_receiver_array_state(mut ctx UnCtx, node int) int {
	t := ctx.t
	if upsp_is_array_literal(t, node) || c.upsp_is_array_constructor_call(mut ctx, node) {
		return upsp_yes
	}
	if c.upsp_is_not_array(mut ctx, node)
		|| t.typ(node) in [.object_expression, .function_expression, .arrow_function_expression,
			.class_expression]
		|| c.upsp_is_known_non_array_call(mut ctx, node)
		|| c.upsp_is_known_non_array_construction(mut ctx, node)
		|| c.upsp_is_not_array_by_array_is_array_test(mut ctx, node) {
		return upsp_no
	}
	return upsp_unknown
}

// --- What a type annotation says

// upsp_union_array_state ports getUnionArrayState.
fn upsp_union_array_state(states []int) int {
	if states.all(it == upsp_yes) {
		return upsp_yes
	}
	return if states.contains(upsp_unknown) || states.contains(upsp_yes) {
		upsp_unknown
	} else {
		upsp_no
	}
}

// upsp_intersection_array_state ports getIntersectionArrayState.
fn upsp_intersection_array_state(states []int) int {
	if states.contains(upsp_yes) {
		return upsp_yes
	}
	return if states.contains(upsp_unknown) { upsp_unknown } else { upsp_no }
}

// upsp_type_name_identifier_name ports getTypeNameIdentifierName: the last name of `A.B.C`.
fn upsp_type_name_identifier_name(t &estree.EsTree, node int) string {
	if node >= 0 && t.typ(node) == .ts_qualified_name {
		return upsp_type_name_identifier_name(t, t.node(node, .right) or { -1 })
	}
	return upsp_name(t, node)
}

// upsp_type_name_namespace_identifier_name ports getTypeNameNamespaceIdentifierName: the first
// name of `A.B.C`.
fn upsp_type_name_namespace_identifier_name(t &estree.EsTree, node int) string {
	if node >= 0 && t.typ(node) == .ts_qualified_name {
		return upsp_type_name_namespace_identifier_name(t, t.node(node, .left) or { -1 })
	}
	return upsp_name(t, node)
}

// upsp_definition_node is definition.node of a definition whose name is the node's own name (a
// declarator, an import specifier, a type alias, interface or type parameter): the parent of
// the ESTree node of the name.
fn (mut c Checker) upsp_definition_node(ctx &UnCtx, def ScopeDefinition) int {
	name := c.un_es_of(ctx, def.name)
	return if name < 0 { -1 } else { ctx.t.nodes[name].parent }
}

// upsp_first_definition is `variable?.defs[0]`.
fn (mut c Checker) upsp_first_definition(ctx &UnCtx, v int) ?ScopeDefinition {
	if v < 0 {
		return none
	}
	tree := c.scope_tree(ctx.root)
	if tree.variables[v].defs.len == 0 {
		return none
	}
	return tree.variables[v].defs[0]
}

// upsp_type_reference_definition_state ports getTypeReferenceDefinitionState.
fn (mut c Checker) upsp_type_reference_definition_state(mut ctx UnCtx, type_name string, v int, mut visited []int) int {
	t := ctx.t
	def := c.upsp_first_definition(ctx, v) or {
		return if type_name in upsp_known_non_array_type_names { upsp_no } else { upsp_unknown }
	}
	match def.kind {
		.class_name {
			return upsp_no
		}
		.import_binding {
			specifier := c.upsp_definition_node(ctx, def)
			mut imported_name := type_name
			if specifier >= 0 && t.typ(specifier) == .import_specifier {
				imported := t.node(specifier, .imported) or { -1 }
				if imported >= 0 && t.typ(imported) == .identifier {
					imported_name = upsp_name(t, imported)
				}
			}
			return if imported_name in upsp_known_non_array_type_names {
				upsp_no
			} else {
				upsp_unknown
			}
		}
		.type_definition {}
		else {
			return upsp_unknown
		}
	}
	node := c.upsp_definition_node(ctx, def)
	if node < 0 {
		return upsp_unknown
	}
	scope := c.scope_tree(ctx.root).variables[v].scope
	match t.typ(node) {
		.ts_type_alias_declaration {
			return c.upsp_type_annotation_array_state(mut ctx, t.node(node, .type_annotation) or {
				-1
			}, scope, mut visited)
		}
		.ts_type_parameter {
			constraint := t.node(node, .constraint) or { return upsp_unknown }
			return c.upsp_type_annotation_array_state(mut ctx, constraint, scope, mut visited)
		}
		.ts_interface_declaration {
			return upsp_no
		}
		else {
			return upsp_unknown
		}
	}
}

// upsp_type_reference_array_state ports getTypeReferenceArrayState.
fn (mut c Checker) upsp_type_reference_array_state(mut ctx UnCtx, node int, scope int, mut visited []int) int {
	t := ctx.t
	type_name := t.node(node, .type_name) or { return upsp_unknown }
	tree := c.scope_tree(ctx.root)
	if t.typ(type_name) == .ts_qualified_name {
		if upsp_type_name_identifier_name(t, type_name) in upsp_known_non_array_type_names {
			namespace := tree.find_variable(scope, upsp_type_name_namespace_identifier_name(t,
				type_name), -1)
			def := c.upsp_first_definition(ctx, namespace) or { return upsp_unknown }
			if def.kind != .import_binding {
				return upsp_unknown
			}
			specifier := c.upsp_definition_node(ctx, def)
			return if specifier >= 0 && t.typ(specifier) == .import_namespace_specifier {
				upsp_no
			} else {
				upsp_unknown
			}
		}
		return upsp_unknown
	}
	name := upsp_name(t, type_name)
	if name in upsp_array_type_names {
		return upsp_yes
	}
	v := tree.find_variable(scope, name, -1)
	if v in visited {
		return upsp_unknown
	}
	visited << v
	state := c.upsp_type_reference_definition_state(mut ctx, name, v, mut visited)
	visited.delete(visited.index(v))
	return state
}

// upsp_type_annotation_array_state ports getTypeAnnotationArrayState: whether a type annotation
// is an array type (upsp_yes), not one (upsp_no), or may be one.
fn (mut c Checker) upsp_type_annotation_array_state(mut ctx UnCtx, node int, scope int, mut visited []int) int {
	t := ctx.t
	if node < 0 || t.typ(node) in [.ts_any_keyword, .ts_unknown_keyword] {
		return upsp_unknown
	}
	match t.typ(node) {
		.ts_type_annotation {
			return c.upsp_type_annotation_array_state(mut ctx, t.node(node, .type_annotation) or {
				-1
			}, scope, mut visited)
		}
		.ts_array_type, .ts_tuple_type {
			return upsp_yes
		}
		.ts_type_operator {
			if (t.string_of(node, .operator) or { '' }) != 'readonly' {
				return upsp_no
			}
			return c.upsp_type_annotation_array_state(mut ctx, t.node(node, .type_annotation) or {
				-1
			}, scope, mut visited)
		}
		.ts_type_reference {
			return c.upsp_type_reference_array_state(mut ctx, node, scope, mut visited)
		}
		else {}
	}
	if t.typ(node) == .ts_import_type {
		if qualifier := t.node(node, .qualifier) {
			if upsp_type_name_identifier_name(t, qualifier) in upsp_known_non_array_type_names {
				return upsp_no
			}
		}
	}
	if t.typ(node) in [.ts_union_type, .ts_intersection_type] {
		mut states := []int{}
		for typ in t.list(node, .types) or { []int{} } {
			states << c.upsp_type_annotation_array_state(mut ctx, typ, scope, mut visited)
		}
		return if t.typ(node) == .ts_union_type {
			upsp_union_array_state(states)
		} else {
			upsp_intersection_array_state(states)
		}
	}
	if t.typ(node) in upsp_non_array_type_annotation_types {
		return upsp_no
	}
	return upsp_unknown
}

// upsp_identifier_annotation_array_state ports getIdentifierAnnotationArrayState: what the type
// annotation of the first definition that has a telling one says.
fn (mut c Checker) upsp_identifier_annotation_array_state(mut ctx UnCtx, node int) int {
	t := ctx.t
	v := c.un_find_variable(ctx, node)
	if v < 0 {
		return upsp_unknown
	}
	defs := c.scope_tree(ctx.root).variables[v].defs.clone()
	for def in defs {
		name := c.un_es_of(ctx, def.name)
		if name < 0 {
			continue
		}
		annotation := t.node(name, .type_annotation) or { -1 }
		mut visited := []int{}
		state := c.upsp_type_annotation_array_state(mut ctx, annotation, c.un_scope_of(ctx,
			name), mut visited)
		if state != upsp_unknown {
			return state
		}
	}
	return upsp_unknown
}

// upsp_receiver_annotation_array_state ports getReceiverAnnotationArrayState: what the type
// assertions around the receiver, or the annotation of its variable, say.
fn (mut c Checker) upsp_receiver_annotation_array_state(mut ctx UnCtx, from int) int {
	t := ctx.t
	mut node := from
	for node >= 0 {
		if t.typ(node) in upsp_type_annotation_expression_types {
			mut visited := []int{}
			state := c.upsp_type_annotation_array_state(mut ctx, t.node(node, .type_annotation) or {
				-1
			}, c.un_scope_of(ctx, node), mut visited)
			if state != upsp_unknown {
				return state
			}
		}
		if un_is_ts_expression_wrapper(t, node) || t.typ(node) == .chain_expression {
			node = t.node(node, .expression) or { -1 }
			continue
		}
		break
	}
	if node >= 0 && t.typ(node) == .identifier {
		return c.upsp_identifier_annotation_array_state(mut ctx, node)
	}
	return upsp_unknown
}

// --- What the types say

// upsp_type_symbol is `type.getSymbol() ?? type.aliasSymbol`.
fn (mut c Checker) upsp_type_symbol(typ TypeResponse) ?tsgo.SymbolResponse {
	if typ.symbol != 0 {
		symbol := c.symbol_of(typ) or { return none }
		if !symbol.is_null() {
			return symbol
		}
	}
	if typ.alias_symbol != 0 {
		symbol := c.alias_symbol_of(typ) or { return none }
		if !symbol.is_null() {
			return symbol
		}
	}
	return none
}

// upsp_type_array_state ports getTypeArrayState.
fn (mut c Checker) upsp_type_array_state(typ TypeResponse, depth int) int {
	if depth > 50 || typ.intrinsic_name in upsp_unknown_type_names {
		return upsp_unknown
	}
	if typ.flags & type_flag_union != 0 {
		members := c.members_of(typ) or { return upsp_unknown }
		states := members.map(c.upsp_type_array_state(it, depth + 1))
		if states.contains(upsp_unknown) {
			return upsp_unknown
		}
		if states.all(it == upsp_yes) {
			return upsp_yes
		}
		return if states.contains(upsp_yes) { upsp_unknown } else { upsp_no }
	}
	// Before the base constraint, which would make an unconstrained type parameter of `T & {…}`
	// `unknown`, and the intersection a non-array.
	if typ.flags & type_flag_intersection != 0 {
		members := c.members_of(typ) or { return upsp_unknown }
		states := members.map(c.upsp_type_array_state(it, depth + 1))
		if states.contains(upsp_yes) {
			return upsp_yes
		}
		return if states.contains(upsp_unknown) { upsp_unknown } else { upsp_no }
	}
	constraint := c.base_constraint(typ) or { return upsp_unknown }
	if !constraint.is_null() && constraint.id != typ.id {
		return c.upsp_type_array_state(constraint, depth + 1)
	}
	if typ.flags & type_flag_type_parameter != 0 {
		return upsp_unknown
	}
	if (c.is_array(typ) or { return upsp_unknown }) || typ.is_tuple_type {
		return upsp_yes
	}
	symbol := c.upsp_type_symbol(typ) or { return upsp_no }
	if symbol.name !in upsp_array_type_names {
		return upsp_no
	}
	return if c.from_default_library(symbol.declarations) or { return upsp_unknown } {
		upsp_yes
	} else {
		upsp_no
	}
}

// upsp_concat_receiver_array_state ports getConcatReceiverArrayState: the types, then the type
// annotations, then the syntax.
fn (mut c Checker) upsp_concat_receiver_array_state(mut ctx UnCtx, node int) int {
	if typ := c.un_ts_type(ctx, node) {
		state := c.upsp_type_array_state(typ, 0)
		if state != upsp_unknown {
			return state
		}
	}
	annotation_state := c.upsp_receiver_annotation_array_state(mut ctx, node)
	if annotation_state != upsp_unknown {
		return annotation_state
	}
	return c.upsp_syntactic_receiver_array_state(mut ctx, un_unwrap_chain_and_ts_expression(ctx.t,
		node))
}

// --- shared/array-range.js and shared/array-concat-in-loop.js

// upsp_is_valid_array_length ports isValidArrayLength.
fn upsp_is_valid_array_length(value JsAny) bool {
	return value.kind == .number_ && value.number >= 0 && value.number <= 4294967295
		&& math.floor(value.number) == value.number
}

// upsp_has_array_range_length ports `Boolean(getArrayRangeLength(node, context))`:
// `Array(length).keys()` with a valid length.
fn (mut c Checker) upsp_has_array_range_length(mut ctx UnCtx, from int) bool {
	t := ctx.t
	node := un_unwrap_ts_expression(t, from)
	if !un_is_method_call(t, node,
		methods:          ['keys']
		arguments_length: 0
		optional_call:    false
		optional_member:  false
	) {
		return false
	}
	receiver := un_unwrap_ts_expression(t, t.node(t.node(node, .callee) or { return false }, .object) or {
		return false
	})
	if !(un_is_call(t, receiver, names: ['Array'], arguments_length: 1, optional: false)
		|| un_is_new(t, receiver, names: ['Array'], arguments_length: 1)) {
		return false
	}
	callee := t.node(receiver, .callee) or { return false }
	if !c.es_is_global_reference(ctx.root, t.ts_node(callee) or { return false }) {
		return false
	}
	length := upsp_arguments(t, receiver)[0]
	// hasInvalidStaticArrayLength
	invalid := if value := c.un_static_value_if_no_side_effects(mut ctx, length) {
		!upsp_is_valid_array_length(value.value)
	} else {
		mut visited := map[int]bool{}
		c.un_has_potentially_mutable_member_access(mut ctx, length, mut visited)
	}
	return !invalid
}

// upsp_is_array_concat_in_loop_call ports isArrayConcatInLoopCall: `array = array.concat(…)` in
// a loop, for an empty array declared with `let` or `var` outside of it (prefer-array-push...
// reports it).
fn (mut c Checker) upsp_is_array_concat_in_loop_call(mut ctx UnCtx, call int) bool {
	t := ctx.t
	child := un_outermost_ts_expression(t, call)
	assignment := t.nodes[child].parent
	if assignment < 0 || t.typ(assignment) != .assignment_expression
		|| (t.node(assignment, .right) or { -1 }) != child {
		return false
	}
	// getArrayConcatInLoop
	if (t.string_of(assignment, .operator) or { '' }) != '=' {
		return false
	}
	left := t.node(assignment, .left) or { return false }
	call_expression := un_unwrap_ts_expression(t, t.node(assignment, .right) or { return false })
	if t.typ(left) != .identifier || call_expression != call || !un_is_method_call(t,
		call_expression,
		methods:           ['concat']
		minimum_arguments: 1
		optional_call:     false
		optional_member:   false
		computed:          false
	) {
		return false
	}
	receiver := un_unwrap_ts_expression(t, t.node(t.node(call, .callee) or { return false }, .object) or {
		return false
	})
	if t.typ(receiver) != .identifier {
		return false
	}
	v := c.un_find_variable(ctx, left)
	if v < 0 || v != c.un_find_variable(ctx, receiver) {
		return false
	}
	// isReassignableEmptyArrayVariable
	tree := c.scope_tree(ctx.root)
	variable := tree.variables[v]
	if variable.defs.len != 1 || tree.scopes[variable.scope].kind == .global {
		return false
	}
	def := variable.defs[0]
	if def.kind != .variable || def.parent_kind !in ['let', 'var'] {
		return false
	}
	declarator := c.upsp_definition_node(ctx, def)
	if declarator < 0 || t.typ(declarator) != .variable_declarator
		|| t.typ(t.node(declarator, .id) or { return false }) != .identifier {
		return false
	}
	init := t.node(declarator, .init) or { return false }
	if !un_is_empty_array(t, un_unwrap_ts_expression(t, init)) {
		return false
	}
	// getNearestLoop
	mut loop := -1
	mut ancestor := t.nodes[assignment].parent
	for ancestor >= 0 {
		if upsp_is_function(t, ancestor) {
			break
		}
		if upsp_is_loop(t, ancestor) {
			loop = ancestor
			break
		}
		ancestor = t.nodes[ancestor].parent
	}
	if loop < 0 {
		return false
	}
	body := t.node(loop, .body) or { return false }
	// isNodeInside(definition.node, loop.body)
	return !(t.nodes[declarator].start >= t.nodes[body].start
		&& t.nodes[declarator].end <= t.nodes[body].end)
}

// --- shared/for-of-collection-loop.js

// UpspForOfBinding is what getForOfBinding gives: `element`, and `index` (-1 without one).
struct UpspForOfBinding {
	element int
	index   int = -1
}

// upsp_empty_array_declarator ports getEmptyArrayDeclarator: the declarator of `const array = [];`
// or `let array = [];`.
fn upsp_empty_array_declarator(t &estree.EsTree, node int) int {
	if node < 0 || t.typ(node) != .variable_declaration
		|| (t.string_of(node, .kind) or { '' }) !in ['const', 'let'] {
		return -1
	}
	declarations := t.list(node, .declarations) or { return -1 }
	if declarations.len != 1 {
		return -1
	}
	declarator := declarations[0]
	id := t.node(declarator, .id) or { return -1 }
	init := t.node(declarator, .init) or { return -1 }
	if t.typ(id) != .identifier || !un_is_empty_array(t, init) {
		return -1
	}
	return declarator
}

// upsp_for_of_binding ports getForOfBinding: `element` of `for (const element of …)`, or `index`
// and `element` of `for (const [index, element] of …)`.
fn upsp_for_of_binding(t &estree.EsTree, node int) ?UpspForOfBinding {
	left := t.node(node, .left)?
	if t.typ(left) != .variable_declaration
		|| (t.string_of(left, .kind) or { '' }) !in ['const', 'let'] {
		return none
	}
	declarations := t.list(left, .declarations)?
	if declarations.len != 1 {
		return none
	}
	pattern := t.node(declarations[0], .id)?
	if t.typ(pattern) == .identifier {
		return UpspForOfBinding{
			element: pattern
		}
	}
	// isPairPattern
	if t.typ(pattern) == .array_pattern {
		elements := t.list(pattern, .elements) or { []int{} }
		if elements.len == 2 && elements.all(it >= 0 && t.typ(it) == .identifier) {
			return UpspForOfBinding{
				index:   elements[0]
				element: elements[1]
			}
		}
	}
	return none
}

// upsp_only_expression ports getOnlyExpression: the expression of the only statement of a body.
fn upsp_only_expression(t &estree.EsTree, node int) int {
	mut statement := node
	if node >= 0 && t.typ(node) == .block_statement {
		body := t.list(node, .body) or { []int{} }
		if body.len != 1 {
			return -1
		}
		statement = body[0]
	}
	if statement < 0 || t.typ(statement) != .expression_statement {
		return -1
	}
	return t.node(statement, .expression) or { -1 }
}

// upsp_for_of_iterable_node ports getForOfIterableNode: what the loop copies into the array.
fn (mut c Checker) upsp_for_of_iterable_node(mut ctx UnCtx, node int, array_name string) int {
	t := ctx.t
	expression := upsp_only_expression(t, t.node(node, .body) or { -1 })
	if expression < 0 {
		return -1
	}
	binding := upsp_for_of_binding(t, node) or { return -1 }
	element_name := upsp_name(t, binding.element)
	if element_name == array_name
		|| (binding.index >= 0 && upsp_name(t, binding.index) == array_name) {
		return -1
	}
	right := t.node(node, .right) or { return -1 }
	if binding.index < 0 && un_is_method_call(t, expression,
		methods:          ['push']
		arguments_length: 1
		optional_call:    false
		optional_member:  false
	) && upsp_is_identifier_named(t, t.node(t.node(expression, .callee) or { -1 }, .object) or {
		-1
	}, array_name) && upsp_is_identifier_named(t, upsp_arguments(t, expression)[0], element_name) {
		return right
	}
	if binding.index < 0 || !un_is_method_call(t, right,
		methods:          ['entries']
		arguments_length: 0
		optional_call:    false
		optional_member:  false
	) {
		return -1
	}
	object := t.node(t.node(right, .callee) or { return -1 }, .object) or { return -1 }
	if c.upsp_concat_receiver_array_state(mut ctx, object) != upsp_yes
		|| t.typ(expression) != .assignment_expression
		|| (t.string_of(expression, .operator) or { '' }) != '=' {
		return -1
	}
	left := t.node(expression, .left) or { return -1 }
	if t.typ(left) != .member_expression || !(t.flag(left, .computed) or { false })
		|| !upsp_is_identifier_named(t, t.node(left, .object) or { -1 }, array_name)
		|| !upsp_is_identifier_named(t, t.node(left, .property) or { -1 }, upsp_name(t, binding.index))
		|| !upsp_is_identifier_named(t, t.node(expression, .right) or { -1 }, element_name) {
		return -1
	}
	return object
}

// upsp_has_identifier_name ports hasIdentifierName: an Identifier of that name in the node.
fn upsp_has_identifier_name(t &estree.EsTree, node int, name string) bool {
	if t.typ(node) == .identifier && (t.string_of(node, .name) or { '' }) == name {
		return true
	}
	return t.children(node).any(upsp_has_identifier_name(t, it, name))
}

// upsp_is_referenced_by_nested_function ports isReferencedByNestedFunction: a reference to the
// variable from another function that can run during the loop (created before its end, or a
// hoisted function declaration).
fn (mut c Checker) upsp_is_referenced_by_nested_function(ctx &UnCtx, v int, loop int) bool {
	t := ctx.t
	tree := c.scope_tree(ctx.root)
	loop_end := t.nodes[loop].end
	own_variable_scope := tree.scopes[tree.variables[v].scope].variable_scope
	for r in tree.variables[v].references {
		reference := tree.references[r]
		scope := tree.scopes[reference.from].variable_scope
		if scope == own_variable_scope {
			continue
		}
		if treesitter.node_start(reference.identifier) < loop_end {
			return true
		}
		block := c.un_es_of(ctx, tree.scopes[scope].block)
		if block >= 0 && t.typ(block) == .function_declaration {
			return true
		}
	}
	return false
}

// --- The listeners

// upsp_for_of is the `ForOfStatement` listener: `const array = []; for (const x of y)
// array.push(x);`.
fn (mut c Checker) upsp_for_of(mut ctx UnCtx, node int) ?Finding {
	t := ctx.t
	tokens := ctx.tokens
	if t.flag(node, .await_) or { false } {
		return none
	}
	declaration := unb_sibling(t, node, -1)
	declarator := upsp_empty_array_declarator(t, declaration)
	if declarator < 0 {
		return none
	}
	id := t.node(declarator, .id)?
	array_name := upsp_name(t, id)
	iterable := c.upsp_for_of_iterable_node(mut ctx, node, array_name)
	if iterable < 0 || upsp_has_identifier_name(t, iterable, array_name) {
		return none
	}
	finding := Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: 'for-of'
	}
	// getForOfCopyFix
	iterable_start, iterable_end := c.un_parenthesized_range(t, tokens, iterable)
	replace_start, replace_end := t.nodes[declaration].start, t.nodes[node].end
	if un_would_remove_comments(tokens, replace_start, replace_end, [
		UnRange{iterable_start, iterable_end},
	]) {
		return finding
	}
	kind := t.string_of(declaration, .kind) or { '' }
	fix := fix_replace_range(replace_start, replace_end,
		'${kind} ${c.src[t.nodes[id].start..t.nodes[id].end]} = [...${c.src[iterable_start..iterable_end]}];')
	// A function that can run during the loop and reads the array would then run while the
	// iterable is spread, before the array is initialized.
	ts_id := t.ts_node(id)?
	v := c.scope_tree(ctx.root).declared_variable(ts_id)
	if v >= 0 && c.upsp_is_referenced_by_nested_function(ctx, v, node) {
		return Finding{
			...finding
			suggestions: [Suggestion{
				message_id: 'spread'
				fix:        fix
			}]
		}
	}
	return Finding{
		...finding
		has_fix: true
		fix:     fix
	}
}

// upsp_array_from is the listener of `Array.from()`.
fn (mut c Checker) upsp_array_from(mut ctx UnCtx, node int) ?Finding {
	t := ctx.t
	tokens := ctx.tokens
	if !un_is_method_call(t, node,
		objects:          ['Array']
		methods:          ['from']
		arguments_length: 1
		optional_call:    false
		optional_member:  false
	) {
		return none
	}
	callee := t.node(node, .callee)?
	object := t.node(callee, .object)?
	if !c.es_is_global_reference(ctx.root, t.ts_node(object)?) {
		return none
	}
	first := upsp_arguments(t, node)[0]
	// `Array.from({length})`
	if t.typ(first) == .object_expression || c.upsp_has_array_range_length(mut ctx, first) {
		return none
	}
	// `Array.from(5)` is `[]` but `[...5]` throws: only a string is a known iterable.
	if t.typ(first) == .literal && t.get(first, .value) !is string {
		return none
	}
	// `Array.from(new ArrayBuffer(8))` is `[]` but `[...new ArrayBuffer(8)]` throws.
	if upsp_is_non_iterable_construction(t, first)
		|| upsp_is_prefer_iterator_concat_array_literal(t, first) {
		return none
	}
	preserved_start, preserved_end := if upsp_is_array_literal(t, first) {
		t.nodes[first].start, t.nodes[first].end
	} else {
		c.un_parenthesized_range(t, tokens, first)
	}
	finding := Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: 'array-from'
	}
	if un_would_remove_comments(tokens, t.nodes[node].start, t.nodes[node].end, [
		UnRange{preserved_start, preserved_end},
	]) {
		return finding
	}
	return c.upsp_spread_fix(mut ctx, finding, node, c.upsp_fix_array_from(mut ctx, node), first)
}

// upsp_concat_preserved_ranges ports getConcatPreservedRanges: the ranges whose comments the
// concat-to-spread fix keeps.
fn (mut c Checker) upsp_concat_preserved_ranges(mut ctx UnCtx, node int, fixed_count int) ?[]UnRange {
	t := ctx.t
	tokens := ctx.tokens
	arguments := upsp_arguments(t, node)
	fixed := arguments[..fixed_count]
	// To know whether a trailing comma comment can stay in place.
	mut last_non_empty := -1
	for i := fixed.len - 1; i >= 0; i-- {
		if !upsp_is_array_literal(t, fixed[i]) || !un_is_empty_array(t, fixed[i]) {
			last_non_empty = fixed[i]
			break
		}
	}
	callee := t.node(node, .callee)?
	object_start, object_end := c.un_parenthesized_range(t, tokens, t.node(callee, .object)?)
	mut ranges := [UnRange{object_start, object_end}]
	for argument in fixed {
		if upsp_is_array_literal(t, argument) {
			if un_is_empty_array(t, argument) {
				continue
			}
			if c.upsp_is_outer_comments_preservable(t, tokens, argument) {
				start, end := c.un_parenthesized_range(t, tokens, argument)
				ranges << UnRange{start, end}
				continue
			}
			if c.upsp_has_trailing_comma(t, tokens, argument) && argument != last_non_empty {
				comma := upsp_last_token_but_one(t, tokens, argument)?
				// The comments after the last element and before the trailing comma: the comma
				// itself disappears when the argument is flattened.
				ranges << UnRange{t.nodes[argument].start + 1, comma.start}
				continue
			}
			if upsp_has_array_holes(t, argument) {
				// The holes must stay where they are: the whole literal.
				ranges << un_range(t, argument)
				continue
			}
		}
		start, end := c.un_parenthesized_range(t, tokens, argument)
		ranges << UnRange{start, end}
	}
	if fixed_count < arguments.len {
		// The comments between `.concat(` and the first fixed argument can move to the remaining
		// arguments with the partial fix: they are not kept.
		comma := c.upsp_comma_after(tokens, t.nodes[fixed.last()].end)?
		ranges << UnRange{comma.end, t.nodes[node].end}
	}
	return ranges
}

// upsp_concat is the listener of `array.concat()`.
fn (mut c Checker) upsp_concat(mut ctx UnCtx, node int) ?Finding {
	t := ctx.t
	tokens := ctx.tokens
	if !un_is_method_call(t, node,
		methods:         ['concat']
		optional_call:   false
		optional_member: false
	)
		|| c.upsp_is_array_concat_in_loop_call(mut ctx, node) {
		return none
	}
	callee := t.node(node, .callee)?
	object := t.node(callee, .object)?
	arguments := upsp_arguments(t, node)
	receiver_state := c.upsp_concat_receiver_array_state(mut ctx, object)
	if receiver_state == upsp_no {
		return none
	}
	if receiver_state != upsp_yes && arguments.len > 0
		&& arguments.all(c.upsp_is_static_string(mut ctx, it)) {
		return none
	}
	mut finding := Finding{
		stmt:       c.es_tree_position(t, t.node(callee, .property)?)
		message_id: 'array-concat'
	}
	fixable := c.upsp_concat_fixable_arguments(mut ctx, arguments)
	mut visited := map[int]bool{}
	is_receiver_safe_to_spread := !c.un_has_potentially_mutable_member_access(mut ctx, object, mut
		visited) && !c.upsp_is_array_constructor_with_one_argument(mut ctx, object)
	if fixable.len > 0 || arguments.len == 0 {
		if is_receiver_safe_to_spread {
			preserved := c.upsp_concat_preserved_ranges(mut ctx, node, fixable.len) or {
				return finding
			}
			if !un_would_remove_comments(tokens, t.nodes[node].start, t.nodes[node].end, preserved) {
				fix := c.upsp_fix_concat(mut ctx, node, fixable)
				// Spreading reads the receiver before the later arguments are evaluated: an argument
				// that can run code could change what is read.
				if arguments.any(un_has_possible_side_effect(t, it)) {
					f := fix or { return finding }
					return Finding{
						...finding
						suggestions: [Suggestion{
							message_id: 'spread'
							fix:        f
						}]
					}
				}
				return c.upsp_spread_fix(mut ctx, finding, node, fix, if arguments.len == 0 {
					object
				} else {
					-1
				})
			}
		}
		return finding
	}
	first := arguments[0]
	rest := arguments[1..]
	if t.typ(first) == .spread_element || !is_receiver_safe_to_spread
		|| c.upsp_is_array_constructor_with_one_argument(mut ctx, first) {
		return finding
	}
	fixable_after_first := c.upsp_concat_fixable_arguments(mut ctx, rest)
	has_unsafe_array_constructor_rest_argument := rest.any(c.upsp_is_array_constructor_with_one_argument(mut ctx, it))
	mut variants := [UpspConcatArgument{
		node:          first
		is_spreadable: true
	}, UpspConcatArgument{
		node: first
	}]
	mut message_ids := ['argument-is-spreadable', 'argument-is-not-spreadable']
	if !un_has_side_effect(t, first, UnSideEffect{}) {
		variants << UpspConcatArgument{
			node:          first
			test_argument: true
		}
		message_ids << 'test-argument'
	}
	mut suggestions := []Suggestion{}
	for index, variant in variants {
		// A suggestion also merges the fixable arguments after the first one.
		mut merged := [variant]
		merged << fixable_after_first
		if fix := c.upsp_fix_concat(mut ctx, node, merged) {
			suggestions << Suggestion{
				message_id: message_ids[index]
				fix:        fix
			}
		}
	}
	if !has_unsafe_array_constructor_rest_argument && fixable_after_first.len < rest.len
		&& rest.all(t.typ(it) != .spread_element) {
		mut all := []UpspConcatArgument{}
		for argument in arguments {
			all << c.upsp_concat_argument_spreadable(mut ctx, argument) or {
				UpspConcatArgument{
					node:          argument
					is_spreadable: true
				}
			}
		}
		if fix := c.upsp_fix_concat(mut ctx, node, all) {
			suggestions << Suggestion{
				message_id: 'spread-all-arguments'
				fix:        fix
			}
		}
	}
	finding = Finding{
		...finding
		suggestions: suggestions
	}
	return finding
}

// upsp_slice is the listener of `array.slice()`.
fn (mut c Checker) upsp_slice(mut ctx UnCtx, node int) ?Finding {
	t := ctx.t
	tokens := ctx.tokens
	if !un_is_method_call(t, node,
		methods:           ['slice']
		minimum_arguments: 0
		maximum_arguments: 1
		optional_call:     false
		optional_member:   false
	) {
		return none
	}
	callee := t.node(node, .callee)?
	object := t.node(callee, .object)?
	if upsp_is_array_literal(t, object)
		|| c.un_has_unparenthesized_optional_chain_element(t, tokens, object) {
		return none
	}
	// `.slice()` only exists on an array: a receiver known not to be one cannot be sliced.
	if un_is_node_matches(t, object, upsp_ignored_slice_callee) || c.upsp_is_not_array(mut ctx, object)
		|| c.upsp_is_known_non_array_construction(mut ctx, object) {
		return none
	}
	// Spreading a TypedArray or ArrayBuffer construction fails or changes the type.
	if upsp_is_typed_array_construction(t, object) {
		return none
	}
	arguments := upsp_arguments(t, node)
	if arguments.len > 0 && !unb_is_number_literal_of(t, arguments[0], 0) {
		return none
	}
	return c.upsp_method_problem(mut ctx, node, callee, object, 'array-slice')
}

// upsp_method_problem is the problem of `.slice()` and `.toSpliced()`, with the fix or
// suggestion unless comments would be removed.
fn (mut c Checker) upsp_method_problem(mut ctx UnCtx, node int, callee int, object int, message_id string) ?Finding {
	t := ctx.t
	tokens := ctx.tokens
	finding := Finding{
		stmt:       c.es_tree_position(t, t.node(callee, .property)?)
		message_id: message_id
	}
	object_start, object_end := c.un_parenthesized_range(t, tokens, object)
	if un_would_remove_comments(tokens, t.nodes[node].start, t.nodes[node].end, [
		UnRange{object_start, object_end},
	]) {
		return finding
	}
	return c.upsp_spread_fix(mut ctx, finding, node, c.upsp_method_call_to_spread(mut ctx, node),
		object)
}

// upsp_to_spliced is the listener of `array.toSpliced()`.
fn (mut c Checker) upsp_to_spliced(mut ctx UnCtx, node int) ?Finding {
	t := ctx.t
	tokens := ctx.tokens
	if !un_is_method_call(t, node,
		methods:          ['toSpliced']
		arguments_length: 0
		optional_call:    false
		optional_member:  false
	) {
		return none
	}
	callee := t.node(node, .callee)?
	object := t.node(callee, .object)?
	// The same hazard as `Array#slice()`.
	if t.typ(object) == .array_expression || upsp_is_typed_array_construction(t, object)
		|| un_is_node_matches(t, object, upsp_ignored_slice_callee)
		|| c.upsp_is_not_array(mut ctx, object)
		|| c.upsp_is_known_non_array_construction(mut ctx, object)
		|| c.un_has_unparenthesized_optional_chain_element(t, tokens, object) {
		return none
	}
	return c.upsp_method_problem(mut ctx, node, callee, object, 'array-to-spliced')
}
