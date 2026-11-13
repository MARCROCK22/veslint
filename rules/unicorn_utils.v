module rules

import estree
import treesitter { Ident }

// Helpers of eslint-plugin-unicorn 64.0.0 (rules/utils, rules/fix and rules/ast) that its ported
// rules share, on the ESTree of the estree module and the tokens of fix_tokens.v. Offsets are
// bytes of the source.

// un_tokens are the tokens of the file of the tree.
fn (mut c Checker) un_tokens(t &estree.EsTree) &SourceTokens {
	return c.source_tokens(t.nodes[t.root].ts)
}

// un_first_token ports getFirstToken(node, skip): the token `skip` tokens after the first one of
// the node.
fn un_first_token(t &estree.EsTree, tokens &SourceTokens, node int, skip int) ?SourceToken {
	inside := tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
	if skip >= inside.len {
		return none
	}
	return inside[skip]
}

// un_last_token ports getLastToken(node).
fn un_last_token(t &estree.EsTree, tokens &SourceTokens, node int) ?SourceToken {
	return tokens.before(t.nodes[node].end, false)
}

// un_token_after_punctuator ports getTokenAfter(node, isOpeningParenToken) and the like: the first
// token at or after `offset` that is that punctuator.
fn (c &Checker) un_token_after_punctuator(tokens &SourceTokens, offset int, punctuator string) ?SourceToken {
	for i := source_tokens_index(tokens.tokens, offset); i < tokens.tokens.len; i++ {
		if c.token_is(tokens.tokens[i], punctuator) {
			return tokens.tokens[i]
		}
	}
	return none
}

// un_parent_syntax_paren ports getParentSyntaxOpeningParenthesis: the `(` of the syntax of the
// parent that has the node right after it (`if (a)`, the only argument of a call…).
fn (c &Checker) un_parent_syntax_paren(t &estree.EsTree, tokens &SourceTokens, node int) ?SourceToken {
	parent := t.nodes[node].parent
	if parent < 0 {
		return none
	}
	match t.typ(parent) {
		.call_expression, .new_expression {
			args := t.list(parent, .arguments) or { []int{} }
			if args.len == 1 && args[0] == node {
				before := t.node(parent, .type_arguments) or { t.node(parent, .callee)? }
				return c.un_token_after_punctuator(tokens, t.nodes[before].end, '(')
			}
		}
		.do_while_statement {
			if t.node(parent, .test) or { -1 } == node {
				return c.un_token_after_punctuator(tokens, t.nodes[t.node(parent, .body)?].end,
					'(')
			}
		}
		.if_statement, .while_statement {
			if t.node(parent, .test) or { -1 } == node {
				return un_first_token(t, tokens, parent, 1)
			}
		}
		.import_expression {
			if t.node(parent, .source) or { -1 } == node {
				return un_first_token(t, tokens, parent, 1)
			}
		}
		.switch_statement {
			if t.node(parent, .discriminant) or { -1 } == node {
				return un_first_token(t, tokens, parent, 1)
			}
		}
		.with_statement {
			if t.node(parent, .object) or { -1 } == node {
				return un_first_token(t, tokens, parent, 1)
			}
		}
		else {}
	}
	return none
}

// un_parentheses ports getParentheses (iterateSurroundingParentheses): the `(` and `)` around the
// node that are not part of the syntax of its parent, the outermost first and last.
fn (c &Checker) un_parentheses(t &estree.EsTree, tokens &SourceTokens, node int) []SourceToken {
	parent := t.nodes[node].parent
	if parent < 0 || (t.typ(parent) == .catch_clause && t.node(parent, .param) or { -1 } == node) {
		return []
	}
	mut opening := []SourceToken{}
	mut closing := []SourceToken{}
	mut head := t.nodes[node].start
	mut tail := t.nodes[node].end
	mut syntax_found := false
	mut syntax := ?SourceToken(none)
	for {
		before := tokens.before(head, false) or { break }
		if !c.token_is(before, '(') {
			break
		}
		after := tokens.after(tail, false) or { break }
		if !c.token_is(after, ')') {
			break
		}
		if !syntax_found {
			syntax = c.un_parent_syntax_paren(t, tokens, node)
			syntax_found = true
		}
		if s := syntax {
			if s.start == before.start {
				break
			}
		}
		opening << before
		closing << after
		head = before.start
		tail = after.end
	}
	mut out := opening.reverse()
	out << closing
	return out
}

// un_is_parenthesized ports isParenthesized of unicorn's utils/parentheses.
fn (c &Checker) un_is_parenthesized(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	return c.un_parentheses(t, tokens, node).len > 0
}

// un_parenthesized_range ports getParenthesizedRange.
fn (c &Checker) un_parenthesized_range(t &estree.EsTree, tokens &SourceTokens, node int) (int, int) {
	parens := c.un_parentheses(t, tokens, node)
	if parens.len == 0 {
		return t.nodes[node].start, t.nodes[node].end
	}
	return parens[0].start, parens.last().end
}

// un_parenthesized_text ports getParenthesizedText.
fn (c &Checker) un_parenthesized_text(t &estree.EsTree, tokens &SourceTokens, node int) string {
	start, end := c.un_parenthesized_range(t, tokens, node)
	return c.src[start..end]
}

// un_remove_spaces_after ports removeSpacesAfter: removes the white space (`\s`) that follows the
// offset.
fn (c &Checker) un_remove_spaces_after(offset int) Fix {
	mut end := offset
	for r in c.src[offset..].runes() {
		if !is_js_space(r) {
			break
		}
		end += r.length_in_bytes()
	}
	return fix_remove_range(offset, end)
}

// un_node_by_range_index ports SourceCode#getNodeByRangeIndex: the innermost node whose range
// holds the offset (the first child in the order of the visitor keys at each level); none when the
// Program does not.
fn un_node_by_range_index(t &estree.EsTree, offset int) ?int {
	mut current := t.root
	if !(t.nodes[current].start <= offset && offset < t.nodes[current].end) {
		return none
	}
	outer: for {
		for child in t.children(current) {
			if t.nodes[child].start <= offset && offset < t.nodes[child].end {
				current = child
				continue outer
			}
		}
		break
	}
	return current
}

// un_needs_semicolon ports needsSemicolon: whether code that starts with `code` and goes right
// after the token `before` needs a `;` first. An empty `code` never does; none is any code.
fn (c &Checker) un_needs_semicolon(t &estree.EsTree, tokens &SourceTokens, before ?SourceToken, code ?string) bool {
	if text := code {
		if text == '' || text[0] !in [`[`, `(`, `/`, `\``, `+`, `-`, `*`, `,`, `.`] {
			return false
		}
	}
	token := before or { return false }
	value := c.token_text(token)
	last_block := un_node_by_range_index(t, token.start) or { t.root }
	if token.kind == .punctuator {
		if value == ';' {
			return false
		}
		if value == ']' {
			return true
		}
		if value == ')' {
			body_key := match t.typ(last_block) {
				.if_statement {
					?estree.Key(estree.Key.consequent)
				}
				.for_statement, .for_in_statement, .for_of_statement, .while_statement,
				.do_while_statement, .with_statement {
					?estree.Key(estree.Key.body)
				}
				else {
					?estree.Key(none)
				}
			}
			if key := body_key {
				if body := t.node(last_block, key) {
					if previous := tokens.before(t.nodes[body].start, false) {
						if previous.start == token.start {
							return false
						}
					}
				}
			}
			return true
		}
	}
	if token.kind in [.string_, .null_, .boolean, .numeric, .regular_expression] {
		return true
	}
	if token.kind == .template {
		return value.ends_with('`')
	}
	if t.typ(last_block) == .object_expression {
		return true
	}
	if token.kind == .identifier {
		if value == 'of' && t.typ(last_block) == .for_of_statement {
			return false
		}
		if value == 'await' && t.typ(last_block) == .await_expression {
			return false
		}
		return true
	}
	return false
}

// un_same_line ports isOnSameLine: both offsets start on the same line.
fn un_same_line(t &estree.EsTree, a int, b int) bool {
	line_a, _ := t.line_column(a)
	line_b, _ := t.line_column(b)
	return line_a == line_b
}

// un_remove_parentheses ports removeParentheses: removes the parentheses around the node.
fn (c &Checker) un_remove_parentheses(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	return c.un_parentheses(t, tokens, node).map(fix_remove_range(it.start, it.end))
}

// un_problematic_token: a keyword in lower case, `of` or `await`, which code right next to it
// would join (isProblematicToken of fix-space-around-keywords.js).
fn (c &Checker) un_problematic_token(token SourceToken) bool {
	text := c.token_text(token)
	if token.kind == .keyword {
		return text.bytes().all(it >= `a` && it <= `z`)
	}
	return token.kind == .identifier && text in ['of', 'await']
}

// un_fix_space_around_keyword ports fixSpaceAroundKeyword: a space between the node (with its
// parentheses) and a keyword right before or after it.
fn (c &Checker) un_fix_space_around_keyword(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	start, end := c.un_parenthesized_range(t, tokens, node)
	mut fixes := []Fix{}
	if before := tokens.before(start, true) {
		if start == before.end && c.un_problematic_token(before) {
			fixes << fix_insert_at(before.end, ' ')
		}
	}
	if after := tokens.after(end, true) {
		if end == after.start && c.un_problematic_token(after) {
			fixes << fix_insert_at(after.start, ' ')
		}
	}
	return fixes
}

// un_add_parens_to_return_or_throw ports addParenthesizesToReturnOrThrowExpression: `return (…)`.
fn (c &Checker) un_add_parens_to_return_or_throw(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	if t.typ(node) !in [.return_statement, .throw_statement] {
		return []
	}
	first := un_first_token(t, tokens, node, 0) or { return [] }
	last := un_last_token(t, tokens, node) or { return [] }
	if !c.token_is(last, ';') {
		return [fix_insert_at(first.end, ' ('), fix_insert_at(t.nodes[node].end, ')')]
	}
	return [fix_insert_at(first.end, ' ('), fix_insert_at(last.start, ')')]
}

// un_unwrap ports unwrapNode of is-same-reference.js: without `?.` chains and TypeScript
// assertions (`as`, `<T>`, `!`).
fn un_unwrap(t &estree.EsTree, node int) int {
	mut n := node
	for t.typ(n) in [.chain_expression, .ts_as_expression, .ts_type_assertion, .ts_non_null_expression] {
		n = t.node(n, .expression) or { return n }
	}
	return n
}

// un_static_property_name ports getStaticPropertyName of is-same-reference.js: the name of the
// property of a member expression, the value of getStaticValue (without a scope) as a string when
// it is computed; none when it is not static.
fn (mut c Checker) un_static_property_name(t &estree.EsTree, node int) ?string {
	property := match t.typ(node) {
		.member_expression { t.node(node, .property)? }
		.chain_expression { return c.un_static_property_name(t, t.node(node, .expression)?) }
		.property, .method_definition { t.node(node, .key)? }
		else { return none }
	}
	if t.typ(property) == .identifier && !(t.flag(node, .computed) or { false }) {
		return t.string_of(property, .name)
	}
	ts := t.ts_node(property)?
	result := c.get_static_value_unscoped(ts)
	if !result.found {
		return none
	}
	return js_any_string_value(result.value)
}

// un_equal_literal_value ports equalLiteralValue: the same regular expression, BigInt or value
// (`===`).
fn un_equal_literal_value(t &estree.EsTree, left int, right int) bool {
	left_regex := t.get(left, .regex)
	right_regex := t.get(right, .regex)
	if left_regex is estree.RegexInfo || right_regex is estree.RegexInfo {
		if left_regex is estree.RegexInfo && right_regex is estree.RegexInfo {
			return left_regex.pattern == right_regex.pattern && left_regex.flags == right_regex.flags
		}
		return false
	}
	left_bigint := t.string_of(left, .bigint) or { '' }
	right_bigint := t.string_of(right, .bigint) or { '' }
	if left_bigint != '' || right_bigint != '' {
		return left_bigint == right_bigint
	}
	a := t.get(left, .value)
	b := t.get(right, .value)
	return match a {
		string { b is string && a == b }
		f64 { b is f64 && a == b }
		bool { b is bool && a == b }
		estree.Null { b is estree.Null }
		else { false }
	}
}

// un_is_same_reference ports isSameReference: two expressions that reference the same value
// (`a`, `a.b`, `a['b']`, `a[0]`, `this`…).
fn (mut c Checker) un_is_same_reference(t &estree.EsTree, left_node int, right_node int) bool {
	left := un_unwrap(t, left_node)
	right := un_unwrap(t, right_node)
	if t.typ(left) != t.typ(right) {
		return false
	}
	match t.typ(left) {
		.super, .this_expression {
			return true
		}
		.identifier, .private_identifier {
			return t.string_of(left, .name) or { '' } == t.string_of(right, .name) or { '' }
		}
		.literal {
			return un_equal_literal_value(t, left, right)
		}
		.member_expression {
			left_object := t.node(left, .object) or { return false }
			right_object := t.node(right, .object) or { return false }
			if name := c.un_static_property_name(t, left) {
				// `x.y` and `x["y"]`
				return c.un_is_same_reference(t, left_object, right_object)
					&& name == c.un_static_property_name(t, right) or { return false }
			}
			return (t.flag(left, .computed) or { false }) == (t.flag(right, .computed) or { false })
				&& c.un_is_same_reference(t, left_object, right_object)
				&& c.un_is_same_reference(t, t.node(left, .property) or { return false }, t.node(right,
				.property) or { return false })
		}
		else {
			return false
		}
	}
}

// un_text is sourceCode.getText(node).
fn (c &Checker) un_text(t &estree.EsTree, node int) string {
	return c.src[t.nodes[node].start..t.nodes[node].end]
}

// un_logical_child_needs_parens ports shouldAddParenthesesToLogicalExpressionChild.
fn un_logical_child_needs_parens(t &estree.EsTree, node int, operator string) bool {
	typ := t.typ(node)
	if typ == .logical_expression && (t.string_of(node, .operator) or { '' }) == operator {
		return false
	}
	return typ in [.await_expression, .binary_expression, .logical_expression,
		.conditional_expression, .assignment_expression, .arrow_function_expression,
		.yield_expression, .sequence_expression]
}

// un_enter_order are the nodes of the tree in the order ESLint's traversal enters them.
fn un_enter_order(t &estree.EsTree) []int {
	return t.steps().filter(!it.leave).map(it.node)
}

// un_indent_string ports getIndentString: the white space right before the node on its line.
fn (c &Checker) un_indent_string(t &estree.EsTree, node int) string {
	start := t.nodes[node].start
	mut line_start := start
	for line_start > 0 && c.src[line_start - 1] !in [`\n`, `\r`] {
		line_start--
	}
	before := c.src[line_start..start].runes()
	mut i := before.len
	for i > 0 && is_js_space(before[i - 1]) {
		i--
	}
	return before[i..].string()
}

// Words getAvailableVariableName never gives: Babel's keywords, its reserved words in strict code
// and in a module (`await`, `enum`, `eval`, `arguments`), and TypeScript's reserved words.
const un_reserved_names = ['break', 'case', 'catch', 'continue', 'debugger', 'default', 'do', 'else',
	'finally', 'for', 'function', 'if', 'return', 'switch', 'throw', 'try', 'var', 'const', 'while',
	'with', 'new', 'this', 'super', 'class', 'extends', 'export', 'import', 'null', 'true', 'false',
	'in', 'instanceof', 'typeof', 'void', 'delete', 'implements', 'interface', 'let', 'package',
	'private', 'protected', 'public', 'static', 'yield', 'await', 'enum', 'eval', 'arguments', 'as',
	'any', 'boolean', 'constructor', 'declare', 'get', 'module', 'require', 'number', 'set', 'string',
	'symbol', 'type', 'from', 'of']

// un_valid_identifier ports isValidIdentifier of get-available-variable-name.js for an ASCII name
// (the names veslint's rules generate).
fn un_valid_identifier(name string) bool {
	if name == '' || name in un_reserved_names || name[0].is_digit() {
		return false
	}
	return name.bytes().all(it.is_letter() || it.is_digit() || it in [`_`, `$`])
}

// un_scopes ports getScopes: the scope and all the scopes inside it, depth first.
fn un_scopes(tree &ScopeTree, scope int) []int {
	mut out := [scope]
	for child in tree.scopes[scope].children {
		out << un_scopes(tree, child)
	}
	return out
}

// un_resolve_variable_name ports resolveVariableName: a variable of that name in the scope or an
// upper one.
fn un_resolve_variable_name(tree &ScopeTree, name string, scope int) bool {
	mut s := scope
	for s >= 0 {
		if name in tree.scopes[s].set {
			return true
		}
		s = tree.scopes[s].upper
	}
	return false
}

// un_is_unresolved_name ports isUnresolvedName: a reference of the scope or of a scope inside it
// to that name resolves to no variable.
fn un_is_unresolved_name(tree &ScopeTree, name string, scope int) bool {
	for s in un_scopes(tree, scope) {
		for r in tree.scopes[s].references {
			if tree.references[r].name == name && tree.references[r].resolved < 0 {
				return true
			}
		}
	}
	return false
}

// un_available_variable_name ports getAvailableVariableName: `name`, with `_` added until no
// scope of `scopes` sees a variable or an unresolved reference of that name and `is_safe` takes it.
fn un_available_variable_name(tree &ScopeTree, base string, scopes []int, is_safe fn (string) bool) ?string {
	mut name := base
	if !un_valid_identifier(name) {
		name += '_'
		if !un_valid_identifier(name) {
			return none
		}
	}
	for scopes.any(un_resolve_variable_name(tree, name, it) || un_is_unresolved_name(tree, name, it))
		|| !is_safe(name) {
		name += '_'
	}
	return name
}

// un_has_side_effect ports hasSideEffect of eslint-utils with its default options: the node or a
// node inside it (not inside a function) assigns, awaits, calls, imports, deletes, updates or
// yields.
fn un_has_side_effect(t &estree.EsTree, node int) bool {
	match t.typ(node) {
		.arrow_function_expression, .function_expression {
			return false
		}
		.assignment_expression, .await_expression, .call_expression, .import_expression,
		.new_expression, .update_expression, .yield_expression {
			return true
		}
		.unary_expression {
			if (t.string_of(node, .operator) or { '' }) == 'delete' {
				return true
			}
		}
		else {}
	}
	return t.children(node).any(un_has_side_effect(t, it))
}

// un_replace_token_and_spaces_before ports replaceNodeOrTokenAndSpacesBefore for a token (which has
// no parentheses): the token and the white space before it become the replacement, after the
// first line break of that white space when it starts with one.
fn (c &Checker) un_replace_token_and_spaces_before(token SourceToken, replacement string) Fix {
	before := c.src[..token.start].runes()
	mut i := before.len
	for i > 0 && is_js_space(before[i - 1]) {
		i--
	}
	spaces := before[i..].string()
	line_break := if spaces.starts_with('\r\n') {
		'\r\n'
	} else if spaces.starts_with('\n') || spaces.starts_with('\r') {
		spaces[..1]
	} else {
		''
	}
	return fix_replace_range(token.start - spaces.len, token.end, line_break + replacement)
}

// un_is_empty_node ports isEmptyNode (without `additionalEmpty`): an empty statement, or a block
// of empty nodes.
fn un_is_empty_node(t &estree.EsTree, node int) bool {
	return match t.typ(node) {
		.block_statement { (t.list(node, .body) or { []int{} }).all(un_is_empty_node(t, it)) }
		.empty_statement { true }
		else { false }
	}
}

// un_switch_case_head ports getSwitchCaseHeadLocation: from the start of the case to its `:`.
fn (c &Checker) un_switch_case_head(t &estree.EsTree, tokens &SourceTokens, node int) ?Ident {
	start := if test := t.node(node, .test) {
		t.nodes[test].end
	} else {
		(un_first_token(t, tokens, node, 0)?).end
	}
	colon := c.un_token_after_punctuator(tokens, start, ':')?
	return c.position_range(t.nodes[node].start, colon.end)
}
