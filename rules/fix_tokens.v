module rules

import treesitter { children, named_children, node_end, node_field, node_kind, node_parent, node_start }

// The tokens and comments of a file as ESLint's SourceCode has them with typescript-estree 8.62.0
// (convertTokens, convertComments), built from the tree-sitter tree on first use, and what fixers
// do with them: the token queries of SourceCode, eslint-utils' isParenthesized, and
// typescript-eslint's getTextWithParentheses, isStartOfExpressionStatement and
// needsPrecedingSemicolon.

// EsNode is an ESTree node on the tree-sitter tree. Parentheses are not nodes in ESTree, and the
// outermost element of an optional chain is two: its ChainExpression (`chain`) and the expression
// inside it. Both have the same range; they differ in their type and in their parent.
struct EsNode {
	node  C.TSNode // without parentheses
	chain bool     // the ChainExpression around `node`, not `node` itself
}

// es_child is the ESTree node a parent has in one of its children (an operand, an argument, an
// object, a callee…): without parentheses, and the ChainExpression if it is an optional chain.
fn es_child(n C.TSNode) EsNode {
	node := unwrap_parens(n)
	return EsNode{
		node:  node
		chain: is_chain_element(node) && is_estree_chain_root(node)
	}
}

// es_inner is the expression itself, which is what a selector like `CallExpression` or
// `MemberExpression` matches: for the outermost element of an optional chain, the expression
// inside the ChainExpression.
fn es_inner(n C.TSNode) EsNode {
	return EsNode{
		node: unwrap_parens(n)
	}
}

// parent is the ESTree parent: the ChainExpression of the outermost element of an optional chain
// or the tree-sitter parent, skipping the nodes ESTree does not have between an expression and its
// parent (parentheses, and the `arguments` of a call or a `new`).
fn (e EsNode) parent() ?EsNode {
	if !e.chain && is_chain_element(e.node) && is_estree_chain_root(e.node) {
		return EsNode{
			node:  e.node
			chain: true
		}
	}
	mut parent := node_parent(e.node)?
	for node_kind(parent) in ['parenthesized_expression', 'arguments'] {
		parent = node_parent(parent)?
	}
	return EsNode{
		node: parent
	}
}

// has_child tells whether `child` is what the field `field` of the node holds (`parent.left ===
// node`): never for a ChainExpression, whose only child is its expression.
fn (e EsNode) has_child(field string, child EsNode) bool {
	if e.chain {
		return false
	}
	value := node_field(e.node, field) or { return false }
	return es_child(value) == child
}

// == compares two ESTree nodes by identity.
fn (a EsNode) == (b EsNode) bool {
	return a.chain == b.chain && node_key(a.node) == node_key(b.node)
		&& node_kind(a.node) == node_kind(b.node)
}

// SourceTokenKind is the type of a token (AST_TOKEN_TYPES) or of a comment.
enum SourceTokenKind {
	punctuator
	keyword
	identifier
	string_
	template
	numeric
	regular_expression
	boolean
	null_
	private_identifier
	line_comment
	block_comment
	shebang_comment
}

// SourceToken is a token or a comment: a range of the source, in bytes.
struct SourceToken {
	start int
	end   int
	kind  SourceTokenKind
	node  C.TSNode // its leaf; for a string, a regular expression or a piece of a template, that node
}

fn (t SourceToken) is_comment() bool {
	return t.kind in [.line_comment, .block_comment, .shebang_comment]
}

// SourceTokens are the tokens and the comments of a file, in order.
@[heap]
struct SourceTokens {
	tokens   []SourceToken // without comments
	comments []SourceToken
	all      []SourceToken // tokens and comments
}

// Reserved words: the tokens typescript-estree gives the type Keyword (SyntaxKind.FirstKeyword to
// LastFutureReservedWord, but `null`, `true` and `false`). Other keywords (`as`, `async`, `await`,
// `of`, `type`, `string`…) are Identifier tokens.
const source_token_keywords = ['break', 'case', 'catch', 'class', 'const', 'continue', 'debugger',
	'default', 'delete', 'do', 'else', 'enum', 'export', 'extends', 'finally', 'for', 'function',
	'if', 'import', 'in', 'instanceof', 'new', 'return', 'super', 'switch', 'this', 'throw', 'try',
	'typeof', 'var', 'void', 'while', 'with', 'implements', 'interface', 'let', 'package', 'private',
	'protected', 'public', 'static', 'yield']

// Leaves that are names: Identifier tokens whatever their text (`a.class`, `{ default: 1 }`).
const source_token_name_kinds = ['identifier', 'property_identifier', 'shorthand_property_identifier',
	'shorthand_property_identifier_pattern', 'type_identifier', 'statement_identifier']

// Leaves of the grammar that are several tokens for TypeScript, one per character.
const source_token_split_leaves = ['?:', '-?:', '+?:', '{|', '|}']

// source_tokens gives the tokens of the file `n` belongs to, built on first use.
fn (mut c Checker) source_tokens(n C.TSNode) &SourceTokens {
	if c.file_tokens == unsafe { nil } {
		mut root := n
		for {
			root = node_parent(root) or { break }
		}
		c.file_tokens = build_source_tokens(root, c.src)
	}
	return c.file_tokens
}

fn build_source_tokens(root C.TSNode, src string) &SourceTokens {
	mut all := []SourceToken{}
	source_tokens_walk(root, src, mut all)
	return &SourceTokens{
		tokens:   all.filter(!it.is_comment())
		comments: all.filter(it.is_comment())
		all:      all
	}
}

// source_tokens_walk appends the tokens and comments of a subtree, in order.
fn source_tokens_walk(root C.TSNode, src string, mut out []SourceToken) {
	mut cursor := C.ts_tree_cursor_new(root)
	defer {
		C.ts_tree_cursor_delete(&cursor)
	}
	for {
		node := C.ts_tree_cursor_current_node(&cursor)
		if source_tokens_visit(node, src, mut out) && C.ts_tree_cursor_goto_first_child(&cursor) {
			continue
		}
		for !C.ts_tree_cursor_goto_next_sibling(&cursor) {
			if !C.ts_tree_cursor_goto_parent(&cursor) {
				return
			}
		}
	}
}

// source_tokens_visit appends the token a node is, if it is one, and tells whether its children
// are still to be visited. Zero-width leaves (automatic `;`, MISSING nodes) are not tokens.
fn source_tokens_visit(node C.TSNode, src string, mut out []SourceToken) bool {
	start := node_start(node)
	end := node_end(node)
	// An anonymous leaf has its text as kind: the keywords `string` and `number` are not literals.
	kind := if C.ts_node_is_named(node) { node_kind(node) } else { '' }
	match kind {
		'comment', 'html_comment' {
			block := src[start..end].starts_with('/*')
			out << SourceToken{start, end, if block { .block_comment } else { .line_comment }, node}
			return false
		}
		'hash_bang_line' {
			out << SourceToken{start, end, .shebang_comment, node}
			return false
		}
		'string' {
			out << SourceToken{start, end, .string_, node}
			return false
		}
		'regex' {
			out << SourceToken{start, end, .regular_expression, node}
			return false
		}
		'template_string', 'template_literal_type' {
			source_tokens_template(node, src, mut out)
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
	if text in source_token_split_leaves {
		for i in start .. end {
			out << SourceToken{i, i + 1, .punctuator, node}
		}
		return false
	}
	out << SourceToken{start, end, if source_token_is_name(node, text) {
		.identifier
	} else {
		source_token_kind(kind, text)
	}, node}
	return false
}

// source_token_is_name tells the reserved words TypeScript parses as an identifier: the `const`
// of a const assertion, and `this` as a parameter or in a type query (`typeof this.x`).
fn source_token_is_name(leaf C.TSNode, text string) bool {
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

// source_tokens_template appends the tokens of a template: its text up to each `${`, the tokens of
// each substitution, and its text from each `}`.
fn source_tokens_template(node C.TSNode, src string, mut out []SourceToken) {
	mut piece := node_start(node)
	for child in children(node) {
		if node_kind(child) !in ['template_substitution', 'template_type'] {
			continue
		}
		out << SourceToken{piece, node_start(child) + 2, .template, node}
		for part in children(child) {
			if node_kind(part) !in ['\${', '}'] {
				source_tokens_walk(part, src, mut out)
			}
		}
		piece = node_end(child) - 1
	}
	out << SourceToken{piece, node_end(node), .template, node}
}

// source_token_kind ports getTokenType for a leaf of that kind and text.
fn source_token_kind(kind string, text string) SourceTokenKind {
	if kind == 'number' {
		return .numeric
	}
	if kind == 'private_property_identifier' {
		return .private_identifier
	}
	if kind in source_token_name_kinds {
		return .identifier
	}
	if text == 'null' {
		return .null_
	}
	if text in ['true', 'false'] {
		return .boolean
	}
	if text in source_token_keywords {
		return .keyword
	}
	first := text[0]
	if first.is_letter() || first in [`_`, `$`] || first >= 0x80 {
		return .identifier
	}
	return .punctuator
}

// source_tokens_index is the index of the first token of the list that starts at `offset` or
// after (the length of the list if there is none).
fn source_tokens_index(list []SourceToken, offset int) int {
	mut lo := 0
	mut hi := list.len
	for lo < hi {
		mid := (lo + hi) / 2
		if list[mid].start < offset {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo
}

// before is the last token that starts before `offset`: getTokenBefore of the node or token that
// starts there.
fn (t &SourceTokens) before(offset int, include_comments bool) ?SourceToken {
	list := if include_comments { t.all } else { t.tokens }
	index := source_tokens_index(list, offset)
	if index == 0 {
		return none
	}
	return list[index - 1]
}

// after is the first token that starts at `offset` or after: getTokenAfter of the node or token
// that ends there, and getFirstToken of the node that starts there.
fn (t &SourceTokens) after(offset int, include_comments bool) ?SourceToken {
	list := if include_comments { t.all } else { t.tokens }
	index := source_tokens_index(list, offset)
	if index >= list.len {
		return none
	}
	return list[index]
}

// inside are the tokens that start in [start, end): getTokens of the node with that range, and
// getTokensBetween of what ends at `start` and what starts at `end`.
fn (t &SourceTokens) inside(start int, end int, include_comments bool) []SourceToken {
	list := if include_comments { t.all } else { t.tokens }
	first := source_tokens_index(list, start)
	last := source_tokens_index(list, end)
	if last <= first {
		return []SourceToken{}
	}
	return list[first..last]
}

// comments_before are the comments right before `offset`, with no token in between:
// getCommentsBefore of the node or token that starts there.
fn (t &SourceTokens) comments_before(offset int) []SourceToken {
	last := source_tokens_index(t.all, offset)
	mut first := last
	for first > 0 && t.all[first - 1].is_comment() {
		first--
	}
	return t.all[first..last]
}

// comments_after are the comments right after `offset`, with no token in between:
// getCommentsAfter of the node or token that ends there.
fn (t &SourceTokens) comments_after(offset int) []SourceToken {
	first := source_tokens_index(t.all, offset)
	mut last := first
	for last < t.all.len && t.all[last].is_comment() {
		last++
	}
	return t.all[first..last]
}

// comments_inside are the comments that start in [start, end): getCommentsInside of the node with
// that range.
fn (t &SourceTokens) comments_inside(start int, end int) []SourceToken {
	first := source_tokens_index(t.comments, start)
	last := source_tokens_index(t.comments, end)
	if last <= first {
		return []SourceToken{}
	}
	return t.comments[first..last]
}

// comments_exist_between ports commentsExistBetween(left, right) for what ends at `left_end` and
// what starts at `right_start`.
fn (t &SourceTokens) comments_exist_between(left_end int, right_start int) bool {
	index := source_tokens_index(t.comments, left_end)
	return index < t.comments.len && t.comments[index].end <= right_start
}

// is_space_between ports isSpaceBetween for two tokens with nothing but comments between them:
// there is whitespace somewhere from the end of the left one to the start of the right one.
fn (t &SourceTokens) is_space_between(left_end int, right_start int) bool {
	mut end := left_end
	for token in t.inside(left_end, right_start, true) {
		if token.start != end {
			return true
		}
		end = token.end
	}
	return end != right_start
}

// token_text is the `value` of a token: its text.
fn (c &Checker) token_text(t SourceToken) string {
	return c.src[t.start..t.end]
}

// token_is tells whether the token is that punctuator (isOpeningParenToken and the like).
fn (c &Checker) token_is(t SourceToken, punctuator string) bool {
	return t.kind == .punctuator && c.token_text(t) == punctuator
}

// token_before ports getTokenBefore(node).
fn (mut c Checker) token_before(n C.TSNode) ?SourceToken {
	return c.source_tokens(n).before(node_start(n), false)
}

// token_after ports getTokenAfter(node).
fn (mut c Checker) token_after(n C.TSNode) ?SourceToken {
	return c.source_tokens(n).after(node_end(n), false)
}

// first_token ports getFirstToken(node).
fn (mut c Checker) first_token(n C.TSNode) ?SourceToken {
	token := c.source_tokens(n).after(node_start(n), false)?
	if token.start >= node_end(n) {
		return none
	}
	return token
}

// last_token ports getLastToken(node): a comment tree-sitter leaves at the end of the node is not
// a token.
fn (mut c Checker) last_token(n C.TSNode) ?SourceToken {
	token := c.source_tokens(n).before(node_end(n), false)?
	if token.start < node_start(n) {
		return none
	}
	return token
}

// node_tokens ports getTokens(node).
fn (mut c Checker) node_tokens(n C.TSNode) []SourceToken {
	return c.source_tokens(n).inside(node_start(n), node_end(n), false)
}

// is_parenthesized ports eslint-utils' isParenthesized(node, sourceCode): the node is between a
// `(` and a `)` that are not part of the syntax of its parent (the parentheses of a call with that
// single argument, or of `if`, `while`, `do`, `switch`, `with` and `import()`). Like the original
// it only looks at the tokens around the node, so it is also true for the only parameter of a
// function, among others.
fn (mut c Checker) is_parenthesized(e EsNode) bool {
	parent := e.parent() or { return false }
	if parent.has_child('parameter', e) && node_kind(parent.node) == 'catch_clause' {
		return false
	}
	tokens := c.source_tokens(e.node)
	left := tokens.before(node_start(e.node), false) or { return false }
	right := tokens.after(node_end(e.node), false) or { return false }
	if !c.token_is(left, '(') || !c.token_is(right, ')') {
		return false
	}
	if syntax_paren := c.parent_syntax_paren(e, parent) {
		return syntax_paren.start != left.start
	}
	return true
}

// parent_syntax_paren ports getParentSyntaxParen: the `(` that belongs to the syntax of the parent
// and has the node right after it.
fn (mut c Checker) parent_syntax_paren(e EsNode, parent EsNode) ?SourceToken {
	if parent.chain {
		return none
	}
	p := parent.node
	tokens := c.source_tokens(p)
	match node_kind(p) {
		'call_expression', 'new_expression' {
			list := node_field(p, 'arguments')?
			if node_kind(list) != 'arguments' {
				return none
			}
			args := named_children(list)
			if precedence_is_import_call(p) {
				// ImportExpression: its source.
				if args.len == 0 || es_child(args[0]) != e {
					return none
				}
				return source_tokens_nth(tokens, p, 1)
			}
			if args.len != 1 || es_child(args[0]) != e {
				return none
			}
			// The first `(` after the type arguments or, without them, after the callee.
			if type_arguments := node_field(p, 'type_arguments') {
				return c.source_token_after(type_arguments, '(')
			}
			callee := node_field(p, if node_kind(p) == 'new_expression' {
				'constructor'
			} else {
				'function'
			})?
			return c.source_token_after(unwrap_parens(callee), '(')
		}
		'do_statement' {
			if !parent.has_child('condition', e) {
				return none
			}
			return c.source_token_after(node_field(p, 'body')?, '(')
		}
		'if_statement', 'while_statement' {
			if !parent.has_child('condition', e) {
				return none
			}
			return source_tokens_nth(tokens, p, 1)
		}
		'switch_statement' {
			if !parent.has_child('value', e) {
				return none
			}
			return source_tokens_nth(tokens, p, 1)
		}
		'with_statement' {
			if !parent.has_child('object', e) {
				return none
			}
			return source_tokens_nth(tokens, p, 1)
		}
		else {
			return none
		}
	}
}

// source_tokens_nth ports getFirstToken(node, skip): the token `skip` tokens after the first one
// of the node.
fn source_tokens_nth(tokens &SourceTokens, n C.TSNode, skip int) ?SourceToken {
	inside := tokens.inside(node_start(n), node_end(n), false)
	if skip >= inside.len {
		return none
	}
	return inside[skip]
}

// source_token_after ports getTokenAfter(node, filter) for a punctuator: the first token after
// the node that is it.
fn (mut c Checker) source_token_after(n C.TSNode, punctuator string) ?SourceToken {
	tokens := c.source_tokens(n)
	for i := source_tokens_index(tokens.tokens, node_end(n)); i < tokens.tokens.len; i++ {
		if c.token_is(tokens.tokens[i], punctuator) {
			return tokens.tokens[i]
		}
	}
	return none
}

// text_with_parentheses ports getTextWithParentheses: the text of the node with the parentheses
// right around it, if is_parenthesized.
fn (mut c Checker) text_with_parentheses(e EsNode) string {
	if c.is_parenthesized(e) {
		tokens := c.source_tokens(e.node)
		left := tokens.before(node_start(e.node), false) or { return c.text(e.node) }
		right := tokens.after(node_end(e.node), false) or { return c.text(e.node) }
		return c.src[left.start..right.end]
	}
	return c.text(e.node)
}

// is_start_of_expression_statement ports isStartOfExpressionStatement: an ancestor that starts
// where the node does is an ExpressionStatement.
fn is_start_of_expression_statement(n C.TSNode) bool {
	start := node_start(n)
	mut ancestor := n
	for {
		ancestor = node_parent(ancestor) or { return false }
		if node_start(ancestor) != start {
			return false
		}
		if node_kind(ancestor) == 'expression_statement' {
			return true
		}
	}
}

// Keywords a statement or expression starts with, and the tree-sitter node whose first token each
// one is (NODE_TYPES_BY_KEYWORD; `else` belongs to the IfStatement).
const semicolon_keyword_nodes = {
	'break':    'break_statement'
	'continue': 'continue_statement'
	'debugger': 'debugger_statement'
	'do':       'do_statement'
	'else':     'else_clause'
	'return':   'return_statement'
	'yield':    'yield_expression'
}

// needs_preceding_semicolon ports needsPrecedingSemicolon: code that starts with `(`, `[`, a
// template, `+`, `-` or a regular expression and takes the place of the node would continue the
// previous token, unless a `;` goes first. It looks at the token before the node and at the
// innermost ESTree node that token is in (getNodeByRangeIndex).
fn (mut c Checker) needs_preceding_semicolon(n C.TSNode) bool {
	previous := c.token_before(n) or { return false }
	text := c.token_text(previous)
	if previous.kind == .punctuator && text in ['--', ';', ':', '{', '++', '=>'] {
		return false
	}
	owner := node_parent(previous.node) or { return false }
	owner_kind := node_kind(owner)
	if c.token_is(previous, ')') {
		// Not the `)` of the head of a statement (STATEMENTS).
		if owner_kind in ['for_statement', 'for_in_statement'] {
			return false
		}
		if owner_kind == 'parenthesized_expression' {
			statement := node_parent(owner) or { return true }
			return node_kind(statement) !in ['if_statement', 'while_statement', 'do_statement',
				'with_statement']
		}
		return true
	}
	if c.token_is(previous, '}') {
		// The end of a function expression that is not a class method, of a class expression or of
		// an object.
		outer := node_parent(owner) or { return false }
		return match owner_kind {
			'statement_block' {
				match node_kind(outer) {
					'function_expression', 'generator_function' {
						true
					}
					'method_definition' {
						holder := node_parent(outer) or { return false }
						node_kind(holder) == 'object'
					}
					else {
						false
					}
				}
			}
			'class_body' {
				node_kind(outer) == 'class'
			}
			'object' {
				true
			}
			else {
				false
			}
		}
	}
	if previous.kind in [.identifier, .keyword] {
		// The label of a `break` or a `continue`.
		if node_kind(previous.node) == 'statement_identifier'
			&& owner_kind in ['break_statement', 'continue_statement'] {
			return false
		}
		expected := semicolon_keyword_nodes[text] or { return true }
		if node_kind(previous.node) in source_token_name_kinds {
			return true
		}
		return owner_kind != expected && node_kind(previous.node) != expected
	}
	if previous.kind == .string_ {
		// The source of an import or of an export (DECLARATIONS).
		if owner_kind in ['import_statement', 'export_statement'] {
			source := node_field(owner, 'source') or { return true }
			return node_key(source) != node_key(previous.node)
		}
		return true
	}
	return true
}
