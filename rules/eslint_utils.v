module rules

import treesitter { children, named_children, node_end, node_field, node_kind, node_start }

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
