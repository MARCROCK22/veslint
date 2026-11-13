module rules

import jsregexp
import treesitter { Ident, children, named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Ports of the helpers of ESLint 10.6.0's lib/rules/utils/ast-utils.js that the rules of ESLint
// core use. A tree-sitter node stands for the ESTree node it is without its parentheses, which
// are not ESTree nodes (unwrap_parens). There is no ChainExpression either: skipChainExpression is
// that too.

// es_is_specific_id ports isSpecificId: an Identifier with that name.
fn (c &Checker) es_is_specific_id(n C.TSNode, name string) bool {
	node := unwrap_parens(n)
	return node_kind(node) in ['identifier', 'undefined'] && c.identifier_name(node) == name
}

// es_static_property_name ports getStaticPropertyName for a MemberExpression: the name of a
// property that is not computed (a private one is not static), or getStaticStringValue of a
// computed one.
fn (c &Checker) es_static_property_name(n C.TSNode) ?string {
	node := unwrap_parens(n)
	match node_kind(node) {
		'member_expression' {
			property := node_field(node, 'property')?
			if node_kind(property) != 'property_identifier' {
				return none
			}
			return c.identifier_name(property)
		}
		'subscript_expression' {
			return c.es_static_string_value(node_field(node, 'index')?)
		}
		else {
			return none
		}
	}
}

// es_static_string_value ports getStaticStringValue: String(value) of a literal, and the cooked
// text of a template literal without substitutions. A regular expression that V8 rejects has no
// value: it is given as written.
fn (c &Checker) es_static_string_value(n C.TSNode) ?string {
	node := unwrap_parens(n)
	if node_kind(node) == 'regex' {
		pattern := node_field(node, 'pattern') or { return none }
		flags := if f := node_field(node, 'flags') { c.text(f) } else { '' }
		re := jsregexp.regexp_new(utf16_units(c.text(pattern)), flags) or {
			return '/${c.text(pattern)}/${flags}'
		}
		return '/${c.text(pattern)}/${re.flags}'
	}
	return c.literal_name(node)
}

// es_is_specific_member_access ports isSpecificMemberAccess: a MemberExpression whose object is
// the Identifier `object` (any object when it is '') and whose static property name is
// `property` (any property when it is '').
fn (c &Checker) es_is_specific_member_access(n C.TSNode, object string, property string) bool {
	node := unwrap_parens(n)
	if node_kind(node) !in ['member_expression', 'subscript_expression'] {
		return false
	}
	if object != '' && !c.es_is_specific_id(node_field(node, 'object') or { return false }, object) {
		return false
	}
	if property != '' {
		name := c.es_static_property_name(node) or { return false }
		return name == property
	}
	return true
}

// es_equal_tokens ports equalTokens: the tokens of the two nodes (comments aside) have the same
// types and values.
fn (mut c Checker) es_equal_tokens(a C.TSNode, b C.TSNode) bool {
	tokens := c.source_tokens(a)
	left := unwrap_parens(a)
	right := unwrap_parens(b)
	ta := tokens.inside(node_start(left), node_end(left), false)
	tb := tokens.inside(node_start(right), node_end(right), false)
	if ta.len != tb.len {
		return false
	}
	for i in 0 .. ta.len {
		if ta[i].kind != tb[i].kind || c.src[ta[i].start..ta[i].end] != c.src[tb[i].start..tb[i].end] {
			return false
		}
	}
	return true
}

// es_sequence_last is the last expression of a SequenceExpression (`expressions.at(-1)`), and the
// node itself when it is not one.
fn es_sequence_last(n C.TSNode) C.TSNode {
	mut node := unwrap_parens(n)
	for node_kind(node) == 'sequence_expression' {
		named := named_children(node).filter(node_kind(it) != 'comment')
		if named.len == 0 {
			break
		}
		node = unwrap_parens(named.last())
	}
	return node
}

// es_reference_type is the ESTree type isSameReference compares: Super, ThisExpression,
// Identifier, PrivateIdentifier, Literal and MemberExpression (`a.b` and `a?.b` alike: there is
// no ChainExpression); the tree-sitter kind otherwise.
fn es_reference_type(n C.TSNode) string {
	kind := node_kind(n)
	return match kind {
		'super' { 'Super' }
		'this' { 'ThisExpression' }
		'identifier', 'undefined', 'property_identifier', 'shorthand_property_identifier',
		'shorthand_property_identifier_pattern' {
			'Identifier'
		}
		'private_property_identifier' { 'PrivateIdentifier' }
		'string', 'number', 'true', 'false', 'null', 'regex' { 'Literal' }
		'member_expression', 'subscript_expression' { 'MemberExpression' }
		else { kind }
	}
}

// es_is_same_reference ports isSameReference: the two expressions reference the same value
// (`a.b` and `a["b"]`, `this.#x`, `a[0]` and `a[0]`).
fn (c &Checker) es_is_same_reference(a C.TSNode, b C.TSNode, disable_static_computed_key bool) bool {
	left := unwrap_parens(a)
	right := unwrap_parens(b)
	kind := es_reference_type(left)
	if kind != es_reference_type(right) {
		return false
	}
	match kind {
		'Super', 'ThisExpression' {
			return true
		}
		'Identifier', 'PrivateIdentifier' {
			return c.identifier_name(left) == c.identifier_name(right)
		}
		'Literal' {
			return c.es_equal_literal_value(left, right)
		}
		'MemberExpression' {
			left_object := node_field(left, 'object') or { return false }
			right_object := node_field(right, 'object') or { return false }
			if !disable_static_computed_key {
				if name := c.es_static_property_name(left) {
					return c.es_is_same_reference(left_object, right_object, disable_static_computed_key)
						&& (c.es_static_property_name(right) or { return false }) == name
				}
			}
			computed := node_kind(left) == 'subscript_expression'
			if computed != (node_kind(right) == 'subscript_expression') {
				return false
			}
			field := if computed { 'index' } else { 'property' }
			left_property := node_field(left, field) or { return false }
			right_property := node_field(right, field) or { return false }
			return c.es_is_same_reference(left_object, right_object, disable_static_computed_key)
				&& c.es_is_same_reference(left_property, right_property, disable_static_computed_key)
		}
		else {
			return false
		}
	}
}

// es_equal_literal_value ports equalLiteralValue: regular expressions by pattern and flags, BigInt
// literals by their `bigint` (the digits without `n` and separators), others by their value.
fn (c &Checker) es_equal_literal_value(a C.TSNode, b C.TSNode) bool {
	ka := node_kind(a)
	kb := node_kind(b)
	if ka == 'regex' || kb == 'regex' {
		return ka == kb && c.text(a) == c.text(b)
	}
	ta := c.text(a)
	tb := c.text(b)
	a_big := ka == 'number' && ta.ends_with('n')
	b_big := kb == 'number' && tb.ends_with('n')
	if a_big || b_big {
		return a_big && b_big && ta.replace('_', '') == tb.replace('_', '')
	}
	if ka == 'number' || kb == 'number' {
		if ka != kb {
			return false
		}
		x := number_literal_value(ta) or { return false }
		y := number_literal_value(tb) or { return false }
		return x == y
	}
	if ka == 'string' || kb == 'string' {
		return ka == kb && (c.literal_name(a) or { return false }) == (c.literal_name(b) or {
			return false
		})
	}
	return ka == kb
}

// EsElement is an element of an ArrayExpression or ArrayPattern, or a hole.
struct EsElement {
	node C.TSNode
	hole bool
}

// es_array_elements are the `elements` of an array literal or pattern, with its holes.
fn es_array_elements(n C.TSNode) []EsElement {
	mut out := []EsElement{}
	mut expect_element := true
	for child in children(n) {
		kind := node_kind(child)
		if kind == ',' {
			if expect_element {
				out << EsElement{
					hole: true
				}
			}
			expect_element = true
			continue
		}
		if !C.ts_node_is_named(child) || kind == 'comment' {
			continue
		}
		out << EsElement{
			node: child
		}
		expect_element = false
	}
	return out
}

// es_has_line_break: the text has one of ESLint's line breaks (`\n`, `\r`, U+2028, U+2029), so what
// is before it and after it are on different lines.
fn es_has_line_break(text string) bool {
	return text.contains('\n') || text.contains('\r') || text.contains(' ')
		|| text.contains(' ')
}

// es_end is where the ESTree node ends: at its last token (tree-sitter may put a comment that
// follows a node inside it, as in `{} /* c */`).
fn (c &Checker) es_end(n C.TSNode) int {
	return c.tokens.last_end(node_end(n))
}

// es_text ports sourceCode.getText(node): the text of the node without a trailing comment.
fn (c &Checker) es_text(n C.TSNode) string {
	return c.src[node_start(n)..c.es_end(n)]
}

// es_property_key is the key of an ESTree Property, MethodDefinition, PropertyDefinition,
// TSPropertySignature or TSMethodSignature (the expression inside the brackets of a computed one)
// and whether it is computed.
fn es_property_key(n C.TSNode) ?(C.TSNode, bool) {
	key := match node_kind(n) {
		'pair', 'pair_pattern' {
			node_field(n, 'key')?
		}
		'method_definition', 'method_signature', 'abstract_method_signature',
		'public_field_definition', 'property_signature' {
			node_field(n, 'name')?
		}
		'shorthand_property_identifier', 'shorthand_property_identifier_pattern' {
			n
		}
		'object_assignment_pattern' {
			node_field(n, 'left')?
		}
		else {
			return none
		}
	}
	if node_kind(key) == 'computed_property_name' {
		return unwrap_parens(first_named(key)?), true
	}
	return key, false
}

// es_static_key_name ports getStaticPropertyName for a Property, MethodDefinition,
// PropertyDefinition, TSPropertySignature or TSMethodSignature: the name of a key that is an
// identifier, and the static string value of any other (none for a private name).
fn (c &Checker) es_static_key_name(n C.TSNode) ?string {
	key, computed := es_property_key(n)?
	if !computed && node_kind(key) in ['property_identifier', 'shorthand_property_identifier',
		'shorthand_property_identifier_pattern', 'identifier'] {
		return c.identifier_name(key)
	}
	if node_kind(key) == 'private_property_identifier' {
		return none
	}
	return c.es_static_string_value(key)
}

// es_accessor_kind is the `kind` of a Property or MethodDefinition: 'get' or 'set' for an
// accessor, 'init' otherwise (a method named `get` is not an accessor).
fn es_accessor_kind(n C.TSNode) string {
	if node_kind(n) !in ['method_definition', 'method_signature', 'abstract_method_signature'] {
		return 'init'
	}
	name := node_field(n, 'name') or { return 'init' }
	for child in children(n) {
		if node_start(child) >= node_start(name) {
			break
		}
		if node_kind(child) in ['get', 'set'] {
			return node_kind(child)
		}
	}
	return 'init'
}

// es_is_static_member: a class member with `static`.
fn es_is_static_member(n C.TSNode) bool {
	for child in children(n) {
		if node_kind(child) == 'static' {
			return true
		}
		if C.ts_node_is_named(child) && node_kind(child) !in ['comment', 'decorator',
			'accessibility_modifier', 'override_modifier'] {
			return false
		}
	}
	return false
}

// es_can_tokens_be_adjacent ports canTokensBeAdjacent for two tokens: they can be written
// without a space between them and still be the same tokens.
fn (c &Checker) es_can_tokens_be_adjacent(left SourceToken, right SourceToken) bool {
	left_text := c.src[left.start..left.end]
	right_text := c.src[right.start..right.end]
	if left.kind == .shebang_comment {
		return false
	}
	if left.kind == .punctuator || right.kind == .punctuator {
		if left.kind == .punctuator && right.kind == .punctuator {
			plus := ['+', '++']
			minus := ['-', '--']
			return !((left_text in plus && right_text in plus)
				|| (left_text in minus && right_text in minus))
		}
		if left.kind == .punctuator && left_text == '/' {
			return right.kind !in [.block_comment, .line_comment, .regular_expression]
		}
		return true
	}
	if left.kind in [.string_, .template] || right.kind in [.string_, .template] {
		return true
	}
	if left.kind != .numeric && right.kind == .numeric && right_text.starts_with('.') {
		return true
	}
	if left.kind == .block_comment || right.kind in [.block_comment, .line_comment] {
		return true
	}
	return right.kind == .private_identifier
}

// es_function_parent is the ESTree parent of a function: the member a method is, or the parent
// without parentheses.
fn es_function_parent(f C.TSNode) ?C.TSNode {
	if node_kind(f) == 'method_definition' {
		return f
	}
	return cti_estree_parent(f)
}

// es_is_async_function and es_is_generator_function: the function has `async` or `*`.
fn es_is_async_function(f C.TSNode) bool {
	// The `async` before the name, the parameters or the body.
	mut name := f
	for field in ['name', 'parameters', 'parameter', 'body'] {
		if n := node_field(f, field) {
			name = n
			break
		}
	}
	for child in children(f) {
		if node_start(child) >= node_start(name) {
			break
		}
		if node_kind(child) == 'async' {
			return true
		}
	}
	return false
}

fn es_is_generator_function(f C.TSNode) bool {
	return node_kind(f) in ['generator_function', 'generator_function_declaration']
		|| (node_kind(f) == 'method_definition' && children(f).any(node_kind(it) == '*'))
}

// es_function_name_with_kind ports getFunctionNameWithKind of ESLint's ast-utils:
// "static async method 'x'", "getter 'y'", "arrow function", "function 'f'"…
fn (c &Checker) es_function_name_with_kind(f C.TSNode) string {
	mut tokens := []string{}
	kind := node_kind(f)
	parent := es_function_parent(f) or { f }
	parent_kind := node_kind(parent)
	is_method := kind == 'method_definition'
	in_class := is_method && node_kind(node_parent(f) or { f }) == 'class_body'
	is_field := parent_kind == 'public_field_definition' && !es_is_accessor_field(parent)
	is_property := (is_method && !in_class) || parent_kind == 'pair'
	mut private := false
	mut computed := false
	mut key := f
	if is_method || is_field || parent_kind == 'pair' {
		k, comp := es_property_key(parent) or { f, false }
		key = k
		computed = comp
		private = !computed && node_kind(key) == 'private_property_identifier'
	}
	if in_class || is_field {
		if es_is_static_member(parent) {
			tokens << 'static'
		}
		if private {
			tokens << 'private'
		}
	}
	if es_is_async_function(f) {
		tokens << 'async'
	}
	if es_is_generator_function(f) {
		tokens << 'generator'
	}
	if is_property || in_class {
		accessor := es_accessor_kind(f)
		if in_class && accessor == 'init' && !es_is_static_member(f) && !computed
			&& c.es_static_key_name(f) or { '' } == 'constructor' {
			return 'constructor'
		}
		tokens << match accessor {
			'get' { 'getter' }
			'set' { 'setter' }
			else { 'method' }
		}
	} else if is_field {
		tokens << 'method'
	} else {
		if kind == 'arrow_function' {
			tokens << 'arrow'
		}
		tokens << 'function'
	}
	if is_property || in_class || is_field {
		if private {
			tokens << c.text(key)
		} else if name := c.es_static_key_name(parent) {
			tokens << "'${name}'"
		} else if id := es_function_id(f) {
			tokens << "'${c.text(id)}'"
		}
	} else if id := es_function_id(f) {
		tokens << "'${c.text(id)}'"
	}
	return tokens.join(' ')
}

// es_function_id is the `id` of a function: the name of a function expression or declaration
// (methods and arrows have none).
fn es_function_id(f C.TSNode) ?C.TSNode {
	if node_kind(f) in ['function_expression', 'generator_function', 'function_declaration',
		'generator_function_declaration'] {
		return node_field(f, 'name')
	}
	return none
}

// es_is_parenthesised ports isParenthesised(sourceCode, node): the token before the node is `(`
// and the token after it `)`, the parentheses of a call around its only argument included.
fn (mut c Checker) es_is_parenthesised(n C.TSNode) bool {
	tokens := c.source_tokens(n)
	before := tokens.before(node_start(n), false) or { return false }
	after := tokens.after(c.es_end(n), false) or { return false }
	return c.src[before.start..before.end] == '(' && c.src[after.start..after.end] == ')'
}

// es_member_start is where an ESTree class member starts: at its first decorator (tree-sitter
// puts the decorators of a method before it, in the class body).
fn es_member_start(member C.TSNode) int {
	mut start := node_start(member)
	parent := node_parent(member) or { return start }
	if node_kind(parent) != 'class_body' {
		return start
	}
	mut previous := C.ts_node_prev_named_sibling(member)
	for !C.ts_node_is_null(previous) {
		kind := node_kind(previous)
		if kind == 'decorator' {
			start = node_start(previous)
		} else if kind != 'comment' {
			break
		}
		previous = C.ts_node_prev_named_sibling(previous)
	}
	return start
}

// es_is_accessor_field: a class field with `accessor`, an ESTree AccessorProperty (not a
// PropertyDefinition).
fn es_is_accessor_field(n C.TSNode) bool {
	return node_kind(n) == 'public_field_definition' && children(n).any(node_kind(it) == 'accessor')
}

// es_function_head ports the start of getFunctionHeadLoc of ESLint's ast-utils: the Property,
// MethodDefinition or PropertyDefinition the function is the value of (its decorators included),
// the `=>` of another arrow, or the start of the function.
fn (c &Checker) es_function_head(f C.TSNode) Ident {
	if node_kind(f) == 'method_definition' {
		return c.position_at(es_member_start(f))
	}
	if parent := cti_estree_parent(f) {
		kind := node_kind(parent)
		if kind == 'pair' || (kind == 'public_field_definition' && !es_is_accessor_field(parent)) {
			if value := node_field(parent, 'value') {
				if node_key(unwrap_parens(value)) == node_key(f) {
					return c.position_at(node_start(parent))
				}
			}
		}
	}
	if node_kind(f) == 'arrow_function' {
		for child in children(f) {
			if node_kind(child) == '=>' {
				return c.position_at(node_start(child))
			}
		}
	}
	return c.position_at(node_start(f))
}

// es_is_parenthesised_twice: two pairs of parentheses around the node (the token before the one
// before it is `(`, and the token after the one after it `)`).
fn (mut c Checker) es_is_parenthesised_twice(n C.TSNode) bool {
	if !c.es_is_parenthesised(n) {
		return false
	}
	tokens := c.source_tokens(n)
	before := tokens.before(node_start(n), false) or { return false }
	after := tokens.after(c.es_end(n), false) or { return false }
	outer_before := tokens.before(before.start, false) or { return false }
	outer_after := tokens.after(after.end, false) or { return false }
	return c.src[outer_before.start..outer_before.end] == '('
		&& c.src[outer_after.start..outer_after.end] == ')'
}

// es_precedence ports getPrecedence of ESLint's ast-utils for the ESTree node of `n`: 20 for the
// standard nodes it does not list, -1 for the others (TypeScript's).
fn es_precedence(n C.TSNode) int {
	node := unwrap_parens(n)
	kind := node_kind(node)
	match kind {
		'sequence_expression' {
			return 0
		}
		'assignment_expression', 'augmented_assignment_expression', 'arrow_function',
		'yield_expression' {
			return 1
		}
		'ternary_expression' {
			return 3
		}
		'binary_expression' {
			return match operator_of(node) {
				'||', '??' { 4 }
				'&&' { 5 }
				'|' { 6 }
				'^' { 7 }
				'&' { 8 }
				'==', '!=', '===', '!==' { 9 }
				'<', '<=', '>', '>=', 'in', 'instanceof' { 10 }
				'<<', '>>', '>>>' { 11 }
				'+', '-' { 12 }
				'*', '/', '%' { 13 }
				'**' { 15 }
				else { 16 }
			}
		}
		'unary_expression', 'await_expression' {
			return 16
		}
		'update_expression' {
			return 17
		}
		'call_expression' {
			// A tagged template is a TaggedTemplateExpression; an optional chain a ChainExpression.
			if args := node_field(node, 'arguments') {
				if node_kind(args) != 'arguments' {
					return 20
				}
			}
			return 18
		}
		'new_expression' {
			return 19
		}
		'member_expression', 'subscript_expression' {
			return if is_estree_chain_root(node) { 18 } else { 20 }
		}
		'as_expression', 'satisfies_expression', 'non_null_expression', 'type_assertion',
		'instantiation_expression' {
			return -1
		}
		else {
			return 20
		}
	}
}

// es_can_adjacent is canTokensBeAdjacent on the kinds and the texts of two tokens.
fn es_can_adjacent(lk SourceTokenKind, left_text string, rk SourceTokenKind, right_text string) bool {
	if lk == .shebang_comment {
		return false
	}
	if lk == .punctuator || rk == .punctuator {
		if lk == .punctuator && rk == .punctuator {
			plus := ['+', '++']
			minus := ['-', '--']
			return !((left_text in plus && right_text in plus)
				|| (left_text in minus && right_text in minus))
		}
		if lk == .punctuator && left_text == '/' {
			return rk !in [.block_comment, .line_comment, .regular_expression]
		}
		return true
	}
	if lk in [.string_, .template] || rk in [.string_, .template] {
		return true
	}
	if lk != .numeric && rk == .numeric && right_text.starts_with('.') {
		return true
	}
	if lk == .block_comment || rk in [.block_comment, .line_comment] {
		return true
	}
	return rk == .private_identifier
}

// es_property_name_unscoped ports getPropertyName of eslint-utils without a scope, for a
// MemberExpression: a name, or the constant of a computed key where no identifier is static.
fn (mut c Checker) es_property_name_unscoped(member C.TSNode) ?string {
	match node_kind(member) {
		'member_expression' {
			property := node_field(member, 'property')?
			if node_kind(property) == 'private_property_identifier' {
				return none
			}
			return c.text(property)
		}
		'subscript_expression' {
			return c.string_if_constant_unscoped(node_field(member, 'index')?)
		}
		else {
			return none
		}
	}
}

// EsTrace is a trace map of ReferenceTracker: what to report at a path (READ, CALL, CONSTRUCT)
// and the properties to follow.
struct EsTrace {
	read      bool
	call      bool
	construct bool
	children  map[string]EsTrace
}

// EsTraced is a reference ReferenceTracker reports: the node, its path and how it is used
// ('read', 'call' or 'construct').
struct EsTraced {
	node C.TSNode
	path []string
	kind string
}

// es_global_references ports ReferenceTracker#iterateGlobalReferences (mode "strict"): the reads,
// calls and constructions of the paths of the trace map from the global variables that are not
// modified, through `globalThis`, `global`, `self` and `window`, aliases and destructurings.
fn (mut c Checker) es_global_references(root C.TSNode, trace map[string]EsTrace) []EsTraced {
	mut out := []EsTraced{}
	tree := c.scope_tree(root)
	mut stack := []int{}
	for key, next in trace {
		v := tree.own_variable(0, key)
		if es_is_modified_global(tree, v) {
			continue
		}
		c.es_trace_variable(root, v, [key], next, true, mut stack, mut out)
	}
	root_trace := EsTrace{
		children: trace
	}
	for key in ['global', 'globalThis', 'self', 'window'] {
		v := tree.own_variable(0, key)
		if es_is_modified_global(tree, v) {
			continue
		}
		c.es_trace_variable(root, v, []string{}, root_trace, false, mut stack, mut out)
	}
	return out
}

fn es_is_modified_global(tree &ScopeTree, v int) bool {
	if v < 0 {
		return true
	}
	variable := tree.variables[v]
	return variable.defs.len > 0 || variable.references.any(tree.references[it].write)
}

fn (mut c Checker) es_trace_variable(root C.TSNode, v int, path []string, trace EsTrace, report bool, mut stack []int, mut out []EsTraced) {
	if v in stack {
		return
	}
	stack << v
	tree := c.scope_tree(root)
	for r in tree.variables[v].references {
		reference := tree.references[r]
		if !reference.read {
			continue
		}
		if report && trace.read {
			out << EsTraced{
				node: reference.identifier
				path: path
				kind: 'read'
			}
		}
		c.es_trace_properties(root, reference.identifier, path, trace, mut stack, mut out)
	}
	stack.pop()
}

// es_is_pass_through ports isPassThrough: the parent gives the value of the node.
fn es_is_pass_through(n C.TSNode) bool {
	parent := cti_estree_parent(n) or { return false }
	match node_kind(parent) {
		'ternary_expression' {
			key := node_key(n)
			consequence := node_field(parent, 'consequence') or { return false }
			alternative := node_field(parent, 'alternative') or { return false }
			return node_key(unwrap_parens(consequence)) == key
				|| node_key(unwrap_parens(alternative)) == key
		}
		'binary_expression' {
			return estree_binary_kind(parent) == 'LogicalExpression'
		}
		'sequence_expression' {
			return node_key(es_sequence_last(parent)) == node_key(n)
		}
		'as_expression', 'satisfies_expression', 'type_assertion', 'non_null_expression',
		'instantiation_expression' {
			return true
		}
		else {
			return false
		}
	}
}

fn (mut c Checker) es_trace_properties(root C.TSNode, from C.TSNode, path []string, trace EsTrace, mut stack []int, mut out []EsTraced) {
	mut node := from
	for es_is_pass_through(node) {
		node = cti_estree_parent(node) or { break }
		// A sequence nested by tree-sitter is one SequenceExpression.
		for node_kind(node) == 'sequence_expression' {
			outer := cti_estree_parent(node) or { break }
			if node_kind(outer) != 'sequence_expression' {
				break
			}
			node = outer
		}
	}
	parent := cti_estree_parent(node) or { return }
	key := node_key(node)
	match node_kind(parent) {
		'member_expression', 'subscript_expression' {
			object := node_field(parent, 'object') or { return }
			if node_key(unwrap_parens(object)) != key {
				return
			}
			name := c.es_property_name_unscoped(parent) or { return }
			next := trace.children[name] or { return }
			mut next_path := path.clone()
			next_path << name
			if next.read {
				out << EsTraced{
					node: parent
					path: next_path
					kind: 'read'
				}
			}
			c.es_trace_properties(root, parent, next_path, next, mut stack, mut out)
		}
		'call_expression' {
			callee := node_field(parent, 'function') or { return }
			args := node_field(parent, 'arguments') or { return }
			if node_kind(args) == 'arguments' && node_key(unwrap_parens(callee)) == key && trace.call {
				out << EsTraced{
					node: parent
					path: path
					kind: 'call'
				}
			}
		}
		'new_expression' {
			callee := node_field(parent, 'constructor') or { return }
			if node_key(unwrap_parens(callee)) == key && trace.construct {
				out << EsTraced{
					node: parent
					path: path
					kind: 'construct'
				}
			}
		}
		'assignment_expression' {
			right := node_field(parent, 'right') or { return }
			if node_key(unwrap_parens(right)) == key {
				c.es_trace_lhs(root, node_field(parent, 'left') or { return }, path, trace, mut
					stack, mut out)
				c.es_trace_properties(root, parent, path, trace, mut stack, mut out)
			}
		}
		'assignment_pattern', 'object_assignment_pattern' {
			right := node_field(parent, 'right') or { return }
			if node_key(unwrap_parens(right)) == key {
				c.es_trace_lhs(root, node_field(parent, 'left') or { return }, path, trace, mut
					stack, mut out)
			}
		}
		'required_parameter', 'optional_parameter' {
			value := node_field(parent, 'value') or { return }
			if node_key(unwrap_parens(value)) == key {
				c.es_trace_lhs(root, node_field(parent, 'pattern') or { return }, path, trace, mut
					stack, mut out)
			}
		}
		'variable_declarator' {
			value := node_field(parent, 'value') or { return }
			if node_key(unwrap_parens(value)) == key {
				c.es_trace_lhs(root, node_field(parent, 'name') or { return }, path, trace, mut
					stack, mut out)
			}
		}
		else {}
	}
}

// es_trace_lhs ports _iterateLhsReferences: a variable the value goes to, the properties of an
// object pattern, the target of a default value.
fn (mut c Checker) es_trace_lhs(root C.TSNode, pattern C.TSNode, path []string, trace EsTrace, mut stack []int, mut out []EsTraced) {
	match node_kind(pattern) {
		'identifier', 'shorthand_property_identifier_pattern' {
			tree := c.scope_tree(root)
			v := tree.find_variable(0, c.text(pattern), node_start(pattern))
			if v >= 0 {
				c.es_trace_variable(root, v, path, trace, false, mut stack, mut out)
			}
		}
		'object_pattern' {
			for property in named_children(pattern) {
				kind := node_kind(property)
				if kind !in ['pair_pattern', 'shorthand_property_identifier_pattern',
					'object_assignment_pattern'] {
					continue
				}
				name := c.es_static_key_name(property) or { continue }
				next := trace.children[name] or { continue }
				mut next_path := path.clone()
				next_path << name
				if next.read {
					out << EsTraced{
						node: property
						path: next_path
						kind: 'read'
					}
				}
				value := match kind {
					'pair_pattern' { node_field(property, 'value') or { continue } }
					else { property }
				}
				c.es_trace_lhs(root, value, next_path, next, mut stack, mut out)
			}
		}
		'assignment_pattern', 'object_assignment_pattern' {
			c.es_trace_lhs(root, node_field(pattern, 'left') or { return }, path, trace, mut stack, mut
				out)
		}
		else {}
	}
}

// es_binary_precedence is getPrecedence of a BinaryExpression with that operator.
fn es_binary_precedence(operator string) int {
	return match operator {
		'|' { 6 }
		'^' { 7 }
		'&' { 8 }
		'==', '!=', '===', '!==' { 9 }
		'<', '<=', '>', '>=', 'in', 'instanceof' { 10 }
		'<<', '>>', '>>>' { 11 }
		'+', '-' { 12 }
		'*', '/', '%' { 13 }
		'**' { 15 }
		else { 16 }
	}
}

// es_global_variable_references are the references of the global variable `name` when it has no
// definition (a builtin global), in order.
fn (mut c Checker) es_global_variable_references(root C.TSNode, name string) []C.TSNode {
	tree := c.scope_tree(root)
	v := tree.own_variable(0, name)
	if v < 0 || tree.variables[v].defs.len > 0 {
		return []C.TSNode{}
	}
	return tree.variables[v].references.map(tree.references[it].identifier)
}

// es_callee_of is the call or `new` whose callee the node is.
fn es_callee_of(n C.TSNode) ?C.TSNode {
	parent := cti_estree_parent(n)?
	field := match node_kind(parent) {
		'call_expression' { 'function' }
		'new_expression' { 'constructor' }
		else { return none }
	}
	if node_kind(parent) == 'call_expression' {
		args := node_field(parent, 'arguments')?
		if node_kind(args) != 'arguments' {
			return none
		}
	}
	callee := node_field(parent, field)?
	if node_key(unwrap_parens(callee)) != node_key(n) {
		return none
	}
	return parent
}

// es_valid_this_arg ports isValidThisArg of no-useless-call and prefer-spread: the `this` of the
// call is the object of the member applied, or null or undefined for another callee.
fn (mut c Checker) es_valid_this_arg(applied C.TSNode, this_arg C.TSNode) bool {
	arg := unwrap_parens(this_arg)
	if node_kind(applied) !in ['member_expression', 'subscript_expression'] {
		kind := node_kind(arg)
		return kind == 'null' || (kind in ['identifier', 'undefined'] && c.identifier_name(arg) == 'undefined')
			|| (kind == 'unary_expression' && operator_of(arg) == 'void')
	}
	expected := node_field(applied, 'object') or { return false }
	return c.es_equal_tokens(expected, arg)
}

// es_def_parent is the `parent` of an ESLint definition: the VariableDeclaration of a variable,
// the ImportDeclaration of an import; none for the others.
fn es_def_parent(def ScopeDefinition) ?C.TSNode {
	match def.kind {
		.variable {
			mut node := def.node
			for {
				node = node_parent(node)?
				if node_kind(node) in ['lexical_declaration', 'variable_declaration'] {
					return node
				}
				if node_kind(node) in ['for_in_statement', 'for_statement'] {
					return node
				}
			}
		}
		.import_binding {
			mut node := def.node
			for {
				node = node_parent(node)?
				if node_kind(node) == 'import_statement' {
					return node
				}
			}
		}
		else {}
	}
	return none
}

// es_declared_variables ports getDeclaredVariables: the variables with a definition whose node or
// parent is the node.
fn (mut c Checker) es_declared_variables(root C.TSNode, n C.TSNode) []int {
	tree := c.scope_tree(root)
	key := node_key(n)
	mut out := []int{}
	for v, variable in tree.variables {
		for def in variable.defs {
			if node_key(def.node) == key {
				out << v
				break
			}
			if parent := es_def_parent(def) {
				if node_key(parent) == key {
					out << v
					break
				}
			}
		}
	}
	return out
}

// es_modifying_references ports getModifyingReferences: the writes that are not the initializer,
// one per identifier (a destructuring default writes it twice).
fn es_modifying_references(tree &ScopeTree, v int) []int {
	mut out := []int{}
	references := tree.variables[v].references
	for i, r in references {
		reference := tree.references[r]
		if reference.init || !reference.write {
			continue
		}
		if i > 0 && node_key(tree.references[references[i - 1]].identifier) == node_key(reference.identifier) {
			continue
		}
		out << r
	}
	return out
}

// es_function_position is where the ESTree function starts: the function of a method starts at its
// type parameters or parameters.
fn es_function_position(f C.TSNode) Ident {
	if node_kind(f) == 'method_definition' {
		if type_parameters := node_field(f, 'type_parameters') {
			return position_of(type_parameters)
		}
		if parameters := node_field(f, 'parameters') {
			return position_of(parameters)
		}
	}
	return position_of(f)
}
