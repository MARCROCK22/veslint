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

const keyword_set = build_set(keyword_tokens)

fn build_set(words []string) map[string]bool {
	mut m := map[string]bool{}
	for w in words {
		m[w] = true
	}
	return m
}

const name_kinds = ['identifier', 'property_identifier', 'shorthand_property_identifier',
	'shorthand_property_identifier_pattern', 'type_identifier', 'statement_identifier']

// Leaves that are one token per character for TypeScript (`</` of a JSX closing tag is `<` and
// `/`).
const split_leaves = ['?:', '-?:', '+?:', '{|', '|}', '/>', '</']

// SnipToken is a token or a comment of a snippet, in bytes of the snippet. `reserved`: an
// `identifier` whose text is a reserved word (see reserved_identifier).
struct SnipToken {
	start    int
	end      int
	typ      string
	node     C.vt_node
	reserved bool
}

fn (t SnipToken) is_comment() bool {
	return t.typ == 'Line' || t.typ == 'Block'
}

// snippet_tokens gives the tokens and the comments of a snippet's tree, in order.
fn snippet_tokens(root C.vt_node, src string, tsx bool) ([]SnipToken, []SnipToken) {
	mut all := []SnipToken{}
	tokens_walk(root, src, mut all)
	if tsx && src.contains('<') {
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
	node  C.vt_node
}

fn tokens_jsx(root C.vt_node, tokens []SnipToken) []SnipToken {
	mut gaps := []JsxGap{}
	first, last := treesitter.flat_range(root)
	for i in first .. last + 1 {
		node := treesitter.flat_node(root, i)
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
	}
	mut out := []SnipToken{cap: tokens.len}
	for token in tokens {
		if gaps.any(token.start >= it.start && token.end <= it.end) {
			continue
		}
		parent_kind := node_kind(node_parent(token.node) or { token.node })
		if token.typ == 'String' && parent_kind == 'jsx_attribute' {
			out << SnipToken{token.start, token.end, 'JSXText', token.node, false}
			continue
		}
		if token.typ in ['Identifier', 'Keyword', 'Null', 'Boolean']
			&& parent_kind in ['jsx_opening_element', 'jsx_closing_element', 'jsx_self_closing_element',
				'jsx_attribute', 'jsx_member_expression', 'jsx_namespace_name'] {
			out << SnipToken{token.start, token.end, 'JSXIdentifier', token.node, false}
			continue
		}
		out << token
	}
	for gap in gaps {
		out << SnipToken{gap.start, gap.end, 'JSXText', gap.node, false}
	}
	out.sort_with_compare(fn (a &SnipToken, b &SnipToken) int {
		return a.start - b.start
	})
	return out
}

// tokens_walk visits the subtree in preorder; the subtree of a node whose children are not
// visited is jumped over.
fn tokens_walk(root C.vt_node, src string, mut out []SnipToken) {
	first, last := treesitter.flat_range(root)
	mut i := first
	for i <= last {
		i = if tokens_visit(treesitter.flat_node(root, i), src, mut out) {
			i + 1
		} else {
			treesitter.flat_last(root, i) + 1
		}
	}
}

// tokens_visit appends the token a node is, if it is one, and tells whether its children are
// still to be visited. Zero-width leaves (automatic `;`, MISSING nodes) are not tokens.
fn tokens_visit(node C.vt_node, src string, mut out []SnipToken) bool {
	start := treesitter.node_start(node)
	end := treesitter.node_end(node)
	kind := if C.vt_node_is_named(node) { node_kind(node) } else { '' }
	match kind {
		'comment', 'html_comment' {
			block := src[start..end].starts_with('/*')
			out << SnipToken{start, end, if block { 'Block' } else { 'Line' }, node, false}
			return false
		}
		'hash_bang_line' {
			return false
		}
		'string' {
			out << SnipToken{start, end, 'String', node, false}
			return false
		}
		'regex' {
			out << SnipToken{start, end, 'RegularExpression', node, false}
			return false
		}
		'template_string', 'template_literal_type' {
			tokens_template(node, src, mut out)
			return false
		}
		else {}
	}
	if C.vt_node_child_count(node) > 0 {
		return true
	}
	if end <= start {
		return false
	}
	text := unsafe { tos(src.str + start, end - start) }
	if text.len <= 2 && text in split_leaves {
		for i in start .. end {
			out << SnipToken{i, i + 1, 'Punctuator', node, false}
		}
		return false
	}
	typ := if (text == 'const' || text == 'this') && token_is_name(node, text) {
		'Identifier'
	} else {
		token_kind(kind, text)
	}
	out << SnipToken{start, end, typ, node, kind == 'identifier' && text in reserved_set}
	return false
}

// token_is_name tells the reserved words TypeScript parses as an identifier: the `const` of a
// const assertion, and `this` as a parameter or in a type query.
fn token_is_name(leaf C.vt_node, text string) bool {
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

fn tokens_template(node C.vt_node, src string, mut out []SnipToken) {
	mut piece := treesitter.node_start(node)
	for child in children(node) {
		if node_kind(child) !in ['template_substitution', 'template_type'] {
			continue
		}
		out << SnipToken{piece, treesitter.node_start(child) + 2, 'Template', node, false}
		for part in children(child) {
			if node_kind(part) !in ['\${', '}'] {
				tokens_walk(part, src, mut out)
			}
		}
		piece = treesitter.node_end(child) - 1
	}
	out << SnipToken{piece, treesitter.node_end(node), 'Template', node, false}
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
	if text in keyword_set {
		return 'Keyword'
	}
	first := text[0]
	if first.is_letter() || first == `_` || first == `$` || first >= 0x80 {
		return 'Identifier'
	}
	return 'Punctuator'
}
