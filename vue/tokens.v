module vue

import treesitter { children, named_children, node_kind, node_parent }

// The tokens and comments typescript-estree 8.72.2 gives for a snippet (convertTokens,
// convertComments), from its tree-sitter tree. The same rules as rules/fix_tokens.v, which builds
// them for the rules of a whole file.

// Reserved words: the tokens typescript-estree gives the type Keyword.
const keyword_tokens = ['break', 'case', 'catch', 'class', 'const', 'continue', 'debugger', 'default',
	'delete', 'do', 'else', 'enum', 'export', 'extends', 'finally', 'for', 'function', 'if', 'import',
	'in', 'instanceof', 'new', 'return', 'super', 'switch', 'this', 'throw', 'try', 'typeof', 'var',
	'void', 'while', 'with', 'implements', 'interface', 'let', 'package', 'private', 'protected',
	'public', 'static', 'yield']

const name_kinds = ['identifier', 'property_identifier', 'shorthand_property_identifier',
	'shorthand_property_identifier_pattern', 'type_identifier', 'statement_identifier']

// Leaves that are one token per character for TypeScript.
const split_leaves = ['?:', '-?:', '+?:', '{|', '|}', '/>']

// SnipToken is a token or a comment of a snippet, in bytes of the snippet.
struct SnipToken {
	start int
	end   int
	typ   string
	node  C.TSNode
}

fn (t SnipToken) is_comment() bool {
	return t.typ == 'Line' || t.typ == 'Block'
}

// snippet_tokens gives the tokens and the comments of a snippet's tree, in order.
fn snippet_tokens(root C.TSNode, src string) ([]SnipToken, []SnipToken) {
	mut all := []SnipToken{}
	tokens_walk(root, src, mut all)
	if src.contains('<') {
		all = tokens_jsx(root, all)
	}
	mut tokens := []SnipToken{cap: all.len}
	mut comments := []SnipToken{}
	for t in all {
		if t.is_comment() {
			comments << t
		} else {
			tokens << t
		}
	}
	return tokens, comments
}

struct JsxGap {
	start int
	end   int
	node  C.TSNode
}

fn tokens_jsx(root C.TSNode, tokens []SnipToken) []SnipToken {
	mut gaps := []JsxGap{}
	mut cursor := C.ts_tree_cursor_new(root)
	defer {
		C.ts_tree_cursor_delete(&cursor)
	}
	for {
		node := C.ts_tree_cursor_current_node(&cursor)
		if node_kind(node) == 'jsx_element' {
			mut previous_end := -1
			for child in named_children(node) {
				if node_kind(child) in ['jsx_text', 'html_character_reference', 'comment'] {
					continue
				}
				if previous_end >= 0 && treesitter.node_start(child) > previous_end {
					gaps << JsxGap{previous_end, treesitter.node_start(child), node}
				}
				previous_end = treesitter.node_end(child)
			}
		}
		if C.ts_tree_cursor_goto_first_child(&cursor) {
			continue
		}
		mut done := false
		for !C.ts_tree_cursor_goto_next_sibling(&cursor) {
			if !C.ts_tree_cursor_goto_parent(&cursor) {
				done = true
				break
			}
		}
		if done {
			break
		}
	}
	mut out := []SnipToken{cap: tokens.len}
	for token in tokens {
		if gaps.any(token.start >= it.start && token.end <= it.end) {
			continue
		}
		parent_kind := node_kind(node_parent(token.node) or { token.node })
		if token.typ == 'String' && parent_kind == 'jsx_attribute' {
			out << SnipToken{token.start, token.end, 'JSXText', token.node}
			continue
		}
		if token.typ in ['Identifier', 'Keyword', 'Null', 'Boolean']
			&& parent_kind in ['jsx_opening_element', 'jsx_closing_element', 'jsx_self_closing_element',
				'jsx_attribute', 'jsx_member_expression', 'jsx_namespace_name'] {
			out << SnipToken{token.start, token.end, 'JSXIdentifier', token.node}
			continue
		}
		out << token
	}
	for gap in gaps {
		out << SnipToken{gap.start, gap.end, 'JSXText', gap.node}
	}
	out.sort_with_compare(fn (a &SnipToken, b &SnipToken) int {
		return a.start - b.start
	})
	return out
}

fn tokens_walk(root C.TSNode, src string, mut out []SnipToken) {
	mut cursor := C.ts_tree_cursor_new(root)
	defer {
		C.ts_tree_cursor_delete(&cursor)
	}
	for {
		node := C.ts_tree_cursor_current_node(&cursor)
		if tokens_visit(node, src, mut out) && C.ts_tree_cursor_goto_first_child(&cursor) {
			continue
		}
		for !C.ts_tree_cursor_goto_next_sibling(&cursor) {
			if !C.ts_tree_cursor_goto_parent(&cursor) {
				return
			}
		}
	}
}

// tokens_visit appends the token a node is, if it is one, and tells whether its children are
// still to be visited. Zero-width leaves (automatic `;`, MISSING nodes) are not tokens.
fn tokens_visit(node C.TSNode, src string, mut out []SnipToken) bool {
	start := treesitter.node_start(node)
	end := treesitter.node_end(node)
	kind := if C.ts_node_is_named(node) { node_kind(node) } else { '' }
	match kind {
		'comment', 'html_comment' {
			block := src[start..end].starts_with('/*')
			out << SnipToken{start, end, if block { 'Block' } else { 'Line' }, node}
			return false
		}
		'hash_bang_line' {
			return false
		}
		'string' {
			out << SnipToken{start, end, 'String', node}
			return false
		}
		'regex' {
			out << SnipToken{start, end, 'RegularExpression', node}
			return false
		}
		'template_string', 'template_literal_type' {
			tokens_template(node, src, mut out)
			return false
		}
		else {}
	}
	if C.ts_node_child_count(node) > 0 {
		return true
	}
	if end <= start {
		return false
	}
	text := src[start..end]
	if text in split_leaves {
		for i in start .. end {
			out << SnipToken{i, i + 1, 'Punctuator', node}
		}
		return false
	}
	out << SnipToken{start, end, if token_is_name(node, text) {
		'Identifier'
	} else {
		token_kind(kind, text)
	}, node}
	return false
}

// token_is_name tells the reserved words TypeScript parses as an identifier: the `const` of a
// const assertion, and `this` as a parameter or in a type query.
fn token_is_name(leaf C.TSNode, text string) bool {
	if text !in ['const', 'this'] {
		return false
	}
	mut parent := node_parent(leaf) or { return false }
	if text == 'const' {
		return node_kind(parent) == 'as_expression' || (node_kind(parent) == 'type_arguments'
			&& node_kind(node_parent(parent) or { return false }) == 'type_assertion')
	}
	if node_kind(parent) in ['required_parameter', 'optional_parameter'] {
		return true
	}
	for node_kind(parent) in ['member_expression', 'instantiation_expression'] {
		parent = node_parent(parent) or { return false }
	}
	return node_kind(parent) == 'type_query'
}

fn tokens_template(node C.TSNode, src string, mut out []SnipToken) {
	mut piece := treesitter.node_start(node)
	for child in children(node) {
		if node_kind(child) !in ['template_substitution', 'template_type'] {
			continue
		}
		out << SnipToken{piece, treesitter.node_start(child) + 2, 'Template', node}
		for part in children(child) {
			if node_kind(part) !in ['\${', '}'] {
				tokens_walk(part, src, mut out)
			}
		}
		piece = treesitter.node_end(child) - 1
	}
	out << SnipToken{piece, treesitter.node_end(node), 'Template', node}
}

// token_kind ports getTokenType for a leaf of that kind and text.
fn token_kind(kind string, text string) string {
	if kind == 'number' {
		return 'Numeric'
	}
	if kind == 'private_property_identifier' {
		return 'PrivateIdentifier'
	}
	if kind in name_kinds {
		return 'Identifier'
	}
	if text == 'null' {
		return 'Null'
	}
	if text == 'true' || text == 'false' {
		return 'Boolean'
	}
	if text in keyword_tokens {
		return 'Keyword'
	}
	first := text[0]
	if first.is_letter() || first == `_` || first == `$` || first >= 0x80 {
		return 'Identifier'
	}
	return 'Punctuator'
}
