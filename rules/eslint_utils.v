module rules

import treesitter { children, named_children, node_end, node_field, node_kind, node_parent, node_start }

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
		re := regexp_new(utf16_units(c.text(pattern)), flags) or {
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
	is_field := parent_kind == 'public_field_definition'
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
