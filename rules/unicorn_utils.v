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
	return c.un_replace_range_and_spaces_before(token.start, token.end, replacement)
}

// un_replace_node_and_spaces_before ports replaceNodeOrTokenAndSpacesBefore for a node: its
// parentheses go too, each with the white space before it.
fn (c &Checker) un_replace_node_and_spaces_before(t &estree.EsTree, tokens &SourceTokens, node int, replacement string) []Fix {
	mut fixes := c.un_parentheses(t, tokens, node).map(c.un_replace_range_and_spaces_before(it.start,
		it.end, ''))
	fixes << c.un_replace_range_and_spaces_before(t.nodes[node].start, t.nodes[node].end,
		replacement)
	return fixes
}

fn (c &Checker) un_replace_range_and_spaces_before(start int, end int, replacement string) Fix {
	token := SourceToken{
		start: start
		end:   end
	}
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

// UnCall are the options of isCallExpression, isNewExpression and isCallOrNewExpression
// (ast/call-or-new-expression.js); -1 is no limit.
@[params]
struct UnCall {
	names             []string
	arguments_length  int = -1
	minimum_arguments int
	maximum_arguments int = -1
	allow_spread      bool
	optional          ?bool
}

fn un_is_call_or_new_of(t &estree.EsTree, node int, o UnCall, types []estree.NodeType) bool {
	if node < 0 || t.typ(node) !in types {
		return false
	}
	if want := o.optional {
		if (t.flag(node, .optional) or { false }) != want {
			return false
		}
	}
	args := t.list(node, .arguments) or { []int{} }
	if o.arguments_length >= 0 && args.len != o.arguments_length {
		return false
	}
	if o.minimum_arguments != 0 && args.len < o.minimum_arguments {
		return false
	}
	if o.maximum_arguments >= 0 && args.len > o.maximum_arguments {
		return false
	}
	if !o.allow_spread {
		limit := if o.maximum_arguments >= 0 { o.maximum_arguments } else { o.arguments_length }
		if limit >= 0 {
			for i, arg in args {
				if i < limit && t.typ(arg) == .spread_element {
					return false
				}
			}
		}
	}
	if o.names.len > 0 {
		callee := t.node(node, .callee) or { return false }
		if t.typ(callee) != .identifier || (t.string_of(callee, .name) or { '' }) !in o.names {
			return false
		}
	}
	return true
}

// un_is_call ports isCallExpression.
fn un_is_call(t &estree.EsTree, node int, o UnCall) bool {
	return un_is_call_or_new_of(t, node, o, [.call_expression])
}

// un_is_new ports isNewExpression.
fn un_is_new(t &estree.EsTree, node int, o UnCall) bool {
	return un_is_call_or_new_of(t, node, o, [.new_expression])
}

// un_is_call_or_new ports isCallOrNewExpression.
fn un_is_call_or_new(t &estree.EsTree, node int, o UnCall) bool {
	return un_is_call_or_new_of(t, node, o, [.call_expression, .new_expression])
}

// UnMember are the options of isMemberExpression (ast/is-member-expression.js).
@[params]
struct UnMember {
	properties []string
	objects    []string
	optional   ?bool
	computed   ?bool
}

// un_is_member ports isMemberExpression.
fn un_is_member(t &estree.EsTree, node int, o UnMember) bool {
	if node < 0 || t.typ(node) != .member_expression {
		return false
	}
	if want := o.optional {
		if (t.flag(node, .optional) or { false }) != want {
			return false
		}
	}
	mut computed := o.computed
	if o.properties.len > 0 {
		property := t.node(node, .property) or { return false }
		if t.typ(property) != .identifier
			|| (t.string_of(property, .name) or { '' }) !in o.properties {
			return false
		}
		if computed == none {
			computed = false
		}
	}
	if want := computed {
		if (t.flag(node, .computed) or { false }) != want {
			return false
		}
	}
	if o.objects.len > 0 {
		object := t.node(node, .object) or { return false }
		if t.typ(object) != .identifier || (t.string_of(object, .name) or { '' }) !in o.objects {
			return false
		}
	}
	return true
}

// UnMethodCall are the options of isMethodCall (ast/is-method-call.js).
@[params]
struct UnMethodCall {
	methods           []string
	objects           []string
	arguments_length  int = -1
	minimum_arguments int
	maximum_arguments int = -1
	allow_spread      bool
	optional_call     ?bool
	optional_member   ?bool
	computed          ?bool
}

// un_is_method_call ports isMethodCall: a call of a member expression.
fn un_is_method_call(t &estree.EsTree, node int, o UnMethodCall) bool {
	return un_is_call(t, node, UnCall{
		arguments_length:  o.arguments_length
		minimum_arguments: o.minimum_arguments
		maximum_arguments: o.maximum_arguments
		allow_spread:      o.allow_spread
		optional:          o.optional_call
	}) && un_is_member(t, t.node(node, .callee) or { -1 }, UnMember{
		objects:    o.objects
		computed:   o.computed
		properties: o.methods
		optional:   o.optional_member
	})
}

// un_new_callee_needs_parens ports shouldAddParenthesesToNewExpressionCallee: a member expression
// whose innermost object is a call (`new (a().b)()`).
fn un_new_callee_needs_parens(t &estree.EsTree, node int) bool {
	if t.typ(node) != .member_expression {
		return false
	}
	mut current := t.node(node, .object) or { return false }
	for t.typ(current) == .member_expression {
		current = t.node(current, .object) or { return false }
	}
	return t.typ(current) == .call_expression
}

// un_switch_call_to_new ports switchCallExpressionToNewExpression: `Error()` becomes `new Error()`.
fn (c &Checker) un_switch_call_to_new(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	mut fixes := c.un_fix_space_around_keyword(t, tokens, node)
	fixes << fix_insert_at(t.nodes[node].start, 'new ')
	callee := t.node(node, .callee) or { return fixes }
	if !c.un_is_parenthesized(t, tokens, callee) && un_new_callee_needs_parens(t, callee) {
		fixes << fix_insert_at(t.nodes[callee].start, '(')
		fixes << fix_insert_at(t.nodes[callee].end, ')')
	}
	return fixes
}

// un_remove_method_call ports removeMethodCall: `a.b()` becomes `a`.
fn (c &Checker) un_remove_method_call(t &estree.EsTree, tokens &SourceTokens, call int) []Fix {
	member := t.node(call, .callee) or { return [] }
	object := t.node(member, .object) or { return [] }
	_, object_end := c.un_parenthesized_range(t, tokens, object)
	_, member_end := c.un_parenthesized_range(t, tokens, member)
	return [fix_remove_range(object_end, t.nodes[member].end),
		fix_remove_range(member_end, t.nodes[call].end)]
}

// un_static_value is getStaticValue(node, scope) of the ESTree node; not found when it has no
// tree-sitter node.
fn (mut c Checker) un_static_value(t &estree.EsTree, node int) StaticValue {
	ts := t.ts_node(node) or { return StaticValue{} }
	return c.get_static_value(ts)
}

// un_is_static_properties ports isStaticProperties of utils/is-number.js: `object.property`.
fn un_is_static_properties(t &estree.EsTree, node int, object string, properties []string) bool {
	if t.typ(node) != .member_expression || (t.flag(node, .computed) or { false })
		|| (t.flag(node, .optional) or { false }) {
		return false
	}
	o := t.node(node, .object) or { return false }
	p := t.node(node, .property) or { return false }
	return t.typ(o) == .identifier && (t.string_of(o, .name) or { '' }) == object
		&& t.typ(p) == .identifier && (t.string_of(p, .name) or { '' }) in properties
}

fn un_is_function_call(t &estree.EsTree, node int, name string) bool {
	if t.typ(node) != .call_expression || (t.flag(node, .optional) or { false }) {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	return t.typ(callee) == .identifier && (t.string_of(callee, .name) or { '' }) == name
}

const un_math_properties = ['E', 'LN2', 'LN10', 'LOG2E', 'LOG10E', 'PI', 'SQRT1_2', 'SQRT2']
const un_math_methods = ['abs', 'acos', 'acosh', 'asin', 'asinh', 'atan', 'atanh', 'atan2', 'cbrt',
	'ceil', 'clz32', 'cos', 'cosh', 'exp', 'expm1', 'floor', 'fround', 'hypot', 'imul', 'log', 'log1p',
	'log10', 'log2', 'max', 'min', 'pow', 'random', 'round', 'sign', 'sin', 'sinh', 'sqrt', 'tan',
	'tanh', 'trunc']
const un_number_properties = ['EPSILON', 'MAX_SAFE_INTEGER', 'MAX_VALUE', 'MIN_SAFE_INTEGER',
	'MIN_VALUE', 'NaN', 'NEGATIVE_INFINITY', 'POSITIVE_INFINITY']

// un_is_number ports isNumber of utils/is-number.js: the expression is surely a number (not a
// BigInt).
fn (mut c Checker) un_is_number(t &estree.EsTree, node int) bool {
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
			|| un_is_static_properties(t, callee, 'Number', ['parseFloat', 'parseInt']) {
			return true
		}
	}
	if un_is_function_call(t, node, 'Number') || un_is_function_call(t, node, 'parseInt')
		|| un_is_function_call(t, node, 'parseFloat') {
		return true
	}
	// `.length`
	if typ == .member_expression && !(t.flag(node, .computed) or { false })
		&& !(t.flag(node, .optional) or { false }) {
		property := t.node(node, .property) or { -1 }
		if property >= 0 && t.typ(property) == .identifier
			&& (t.string_of(property, .name) or { '' }) == 'length' {
			return true
		}
	}
	mut operator := t.string_of(node, .operator) or { '' }
	match typ {
		.assignment_expression, .binary_expression {
			left := t.node(node, .left) or { -1 }
			right := t.node(node, .right) or { -1 }
			if typ == .assignment_expression {
				if operator == '=' && c.un_is_number(t, right) {
					return true
				}
				operator = operator[..operator.len - 1]
			}
			if operator == '+' && c.un_is_number(t, left) && c.un_is_number(t, right) {
				return true
			}
			// `>>>` cannot be used on a BigInt.
			if operator == '>>>' {
				return true
			}
			// `a * b` may be a BigInt: one side must be a number.
			if operator in ['-', '*', '/', '%', '**', '<<', '>>', '|', '^', '&']
				&& (c.un_is_number(t, left) || c.un_is_number(t, right)) {
				return true
			}
		}
		.unary_expression {
			// `+` cannot be used on a BigInt.
			if operator == '+' {
				return true
			}
			if operator in ['-', '~'] && c.un_is_number(t, t.node(node, .argument) or { -1 }) {
				return true
			}
		}
		.update_expression {
			if c.un_is_number(t, t.node(node, .argument) or { -1 }) {
				return true
			}
		}
		.conditional_expression {
			consequent := c.un_is_number(t, t.node(node, .consequent) or { -1 })
			alternate := c.un_is_number(t, t.node(node, .alternate) or { -1 })
			if consequent && alternate {
				return true
			}
			test := c.un_static_value(t, t.node(node, .test) or { -1 })
			if test.found && ((consequent && stv_to_boolean(test.value))
				|| (alternate && !stv_to_boolean(test.value))) {
				return true
			}
		}
		.sequence_expression {
			expressions := t.list(node, .expressions) or { []int{} }
			if expressions.len > 0 && c.un_is_number(t, expressions.last()) {
				return true
			}
		}
		else {}
	}
	result := c.un_static_value(t, node)
	return result.found && result.value.kind == .number_
}

// un_new_with_parentheses ports isNewExpressionWithParentheses: `new Foo()` rather than `new Foo`.
fn (c &Checker) un_new_with_parentheses(t &estree.EsTree, tokens &SourceTokens, node int) bool {
	if (t.list(node, .arguments) or { []int{} }).len > 0 {
		return true
	}
	inside := tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
	if inside.len < 2 {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	return c.token_is(inside[inside.len - 2], '(') && c.token_is(inside.last(), ')')
		&& t.nodes[callee].end < t.nodes[node].end
}

// un_switch_new_to_call ports switchNewExpressionToCallExpression: `new Foo()` becomes `Foo()`.
fn (c &Checker) un_switch_new_to_call(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	new_token := un_first_token(t, tokens, node, 0) or { return [] }
	mut fixes := [fix_remove_range(new_token.start, new_token.end),
		c.un_remove_spaces_after(new_token.end)]
	if !c.un_new_with_parentheses(t, tokens, node) {
		fixes << fix_insert_at(t.nodes[node].end, '()')
	}
	callee := t.node(node, .callee) or { return fixes }
	// Without `new`, a callee on the next line after `return` would not be returned.
	if !un_same_line(t, new_token.start, t.nodes[callee].start)
		&& !c.un_is_parenthesized(t, tokens, node) {
		fixes << c.un_add_parens_to_return_or_throw(t, tokens, t.nodes[node].parent)
	}
	return fixes
}

// UnCallTokens are the tokens of getCallExpressionTokens: the `(` and `)` of the arguments, and a
// trailing comma before the `)`.
struct UnCallTokens {
	opening  SourceToken
	closing  SourceToken
	trailing ?SourceToken
}

// un_call_tokens ports getCallOrNewExpressionTokens.
fn (c &Checker) un_call_tokens(t &estree.EsTree, tokens &SourceTokens, node int) ?UnCallTokens {
	start := t.node(node, .type_arguments) or { t.node(node, .callee)? }
	opening := c.un_token_after_punctuator(tokens, t.nodes[start].end, '(')?
	inside := tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
	if inside.len < 2 {
		return none
	}
	penultimate := inside[inside.len - 2]
	return UnCallTokens{
		opening:  opening
		closing:  inside.last()
		trailing: if c.token_is(penultimate, ',') { penultimate } else { none }
	}
}

// un_node_matches_name_or_path ports isNodeMatchesNameOrPath: `a.b.c` matches that member chain
// (and `this`, `super` and `new.target` as its first name).
fn un_node_matches_name_or_path(t &estree.EsTree, from int, name_or_path string) bool {
	parts := name_or_path.trim_space().split('.')
	mut node := from
	for index := parts.len - 1; index >= 0; index-- {
		name := parts[index]
		if name == '' {
			return false
		}
		if index == 0 {
			return (t.typ(node) == .identifier && (t.string_of(node, .name) or { '' }) == name)
				|| (name == 'this' && t.typ(node) == .this_expression)
				|| (name == 'super' && t.typ(node) == .super)
		}
		if index == 1 && t.typ(node) == .meta_property {
			property := t.node(node, .property) or { return false }
			if t.typ(property) == .identifier && (t.string_of(property, .name) or { '' }) == name {
				node = t.node(node, .meta) or { return false }
				continue
			}
		}
		if t.typ(node) == .member_expression && !(t.flag(node, .optional) or { false })
			&& !(t.flag(node, .computed) or { false }) {
			property := t.node(node, .property) or { return false }
			if t.typ(property) == .identifier && (t.string_of(property, .name) or { '' }) == name {
				node = t.node(node, .object) or { return false }
				continue
			}
		}
		return false
	}
	return false
}

// un_is_string_literal ports isStringLiteral.
fn un_is_string_literal(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .literal && t.get(node, .value) is string
}

// un_is_regex_literal ports isRegexLiteral.
fn un_is_regex_literal(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .literal && t.get(node, .regex) is estree.RegexInfo
}

// un_raw is the `raw` of a Literal.
fn un_raw(t &estree.EsTree, node int) string {
	return t.string_of(node, .raw) or { '' }
}

// un_template_raw is `value.raw` of a TemplateElement.
fn un_template_raw(t &estree.EsTree, node int) string {
	value := t.get(node, .value)
	return if value is estree.TemplateValue { value.raw } else { '' }
}

// un_is_tagged_template ports isTaggedTemplateLiteral(node, tags): the quasi of a tagged template
// whose tag matches one of `tags` (any tag when there are none).
fn un_is_tagged_template(t &estree.EsTree, node int, tags []string) bool {
	if node < 0 || t.typ(node) != .template_literal {
		return false
	}
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .tagged_template_expression
		|| t.node(parent, .quasi) or { -1 } != node {
		return false
	}
	if tags.len == 0 {
		return true
	}
	tag := t.node(parent, .tag) or { return false }
	return tags.any(un_node_matches_name_or_path(t, tag, it))
}

// un_replace_template_element ports replaceTemplateElement: the text of the element between its
// delimiters (`` ` `` or `}` and `` ` `` or `${`) becomes `replacement`.
fn un_replace_template_element(t &estree.EsTree, node int, replacement string) Fix {
	tail := t.flag(node, .tail) or { false }
	return fix_replace_range(t.nodes[node].start + 1, t.nodes[node].end - (if tail { 1 } else { 2 }),
		replacement)
}

// un_is_escaped_at: the character at `i` follows an odd number of backslashes, the lookbehind
// `(?<=(?:^|[^\\])(?:\\\\)*\\)` of unicorn's escape rules.
fn un_is_escaped_at(text string, i int) bool {
	mut count := 0
	for j := i - 1; j >= 0 && text[j] == `\\`; j-- {
		count++
	}
	return count % 2 == 1
}

// un_reference_node is the ESTree Identifier of a reference the scope tree or the ReferenceTracker
// gives: in a shorthand property the value, not the key, which has the same range.
fn (mut c Checker) un_reference_node(t &estree.EsTree, ts C.TSNode) ?int {
	node := c.es_index_of(t, ts)?
	parent := t.nodes[node].parent
	if parent >= 0 && t.typ(parent) == .property && (t.flag(parent, .shorthand) or { false })
		&& t.node(parent, .key) or { -1 } == node {
		return t.node(parent, .value) or { node }
	}
	// `export { a }`: `local` and `exported` have the same range; the reference is `local`.
	if parent >= 0 && t.typ(parent) == .export_specifier
		&& t.node(parent, .exported) or { -1 } == node {
		return t.node(parent, .local) or { node }
	}
	return node
}

// un_is_left_hand_side ports isLeftHandSide: the node is written (assigned, updated, destructured
// into or deleted).
fn un_is_left_hand_side(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	return match t.typ(parent) {
		.assignment_expression, .assignment_pattern { t.node(parent, .left) or { -1 } == node }
		.update_expression { t.node(parent, .argument) or { -1 } == node }
		.array_pattern { node in (t.list(parent, .elements) or { []int{} }) }
		.property {
			t.node(parent, .value) or { -1 } == node && t.nodes[parent].parent >= 0
				&& t.typ(t.nodes[parent].parent) == .object_pattern
				&& parent in (t.list(t.nodes[parent].parent, .properties) or { []int{} })
		}
		.unary_expression {
			(t.string_of(parent, .operator) or { '' }) == 'delete'
				&& t.node(parent, .argument) or { -1 } == node
		}
		else { false }
	}
}

fn un_is_shorthand_property_value(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	return parent >= 0 && t.typ(parent) == .property && (t.flag(parent, .shorthand) or { false })
		&& t.node(parent, .value) or { -1 } == node
}

fn un_same_range(t &estree.EsTree, a int, b int) bool {
	return a >= 0 && b >= 0 && t.nodes[a].start == t.nodes[b].start
		&& t.nodes[a].end == t.nodes[b].end
}

// un_replace_reference_identifier ports replaceReferenceIdentifier: the identifier becomes
// `replacement`, keeping a shorthand property, import or export working.
fn (c &Checker) un_replace_reference_identifier(t &estree.EsTree, node int, replacement string) Fix {
	name := t.string_of(node, .name) or { '' }
	parent := t.nodes[node].parent
	start := t.nodes[node].start
	end := t.nodes[node].end
	if un_is_shorthand_property_value(t, node) || (parent >= 0
		&& t.typ(parent) == .assignment_pattern && t.node(parent, .left) or { -1 } == node
		&& un_is_shorthand_property_value(t, parent)) {
		return fix_replace_range(start, end, '${name}: ${replacement}')
	}
	if parent >= 0 && t.typ(parent) == .import_specifier && t.node(parent, .local) or { -1 } == node
		&& un_same_range(t, node, t.node(parent, .imported) or { -1 }) {
		return fix_replace_range(start, end, '${name} as ${replacement}')
	}
	if parent >= 0 && t.typ(parent) == .export_specifier && t.node(parent, .local) or { -1 } == node
		&& un_same_range(t, node, t.node(parent, .exported) or { -1 }) {
		return fix_replace_range(start, end, '${replacement} as ${name}')
	}
	if annotation := t.node(node, .type_annotation) {
		optional := t.flag(node, .optional) or { false }
		return fix_replace_range(start, t.nodes[annotation].start, replacement +
			if optional { '?' } else { '' })
	}
	return fix_replace_range(start, end, replacement)
}

// un_string_if_constant ports getStringIfConstant(node) of eslint-utils without a scope: the
// string of a regular expression or BigInt literal, else String() of getStaticValue.
fn (mut c Checker) un_string_if_constant(t &estree.EsTree, node int) ?string {
	if t.typ(node) == .literal {
		regex := t.get(node, .regex)
		if regex is estree.RegexInfo {
			return '/${regex.pattern}/${regex.flags}'
		}
		if bigint := t.string_of(node, .bigint) {
			return bigint
		}
	}
	result := c.get_static_value_unscoped(t.ts_node(node)?)
	if !result.found {
		return none
	}
	return js_any_string_value(result.value)
}

// un_property_name ports getPropertyName of eslint-utils for a Property, MethodDefinition or
// PropertyDefinition.
fn (mut c Checker) un_property_name(t &estree.EsTree, node int) ?string {
	key := t.node(node, .key)?
	if t.flag(node, .computed) or { false } {
		return c.un_string_if_constant(t, key)
	}
	if t.typ(key) == .literal {
		value := t.get(key, .value)
		return match value {
			string { value }
			f64 { js_number_to_string(value) }
			else { c.un_string_if_constant(t, key) }
		}
	}
	if t.typ(key) == .private_identifier {
		return none
	}
	return t.string_of(key, .name)
}

// un_function_name_with_kind ports getFunctionNameWithKind of eslint-utils (which, unlike
// ESLint's, also names a function after the variable, assignment or default export it is).
fn (mut c Checker) un_function_name_with_kind(t &estree.EsTree, node int) string {
	parent := t.nodes[node].parent
	if parent < 0 {
		return ''
	}
	mut tokens := []string{}
	ptyp := t.typ(parent)
	is_value := t.node(parent, .value) or { -1 } == node
	object_method := ptyp == .property && is_value
	class_method := ptyp == .method_definition && is_value
	field_method := ptyp == .property_definition && is_value
	key := t.node(parent, .key) or { -1 }
	if class_method || field_method {
		if t.flag(parent, .static_) or { false } {
			tokens << 'static'
		}
		if key >= 0 && t.typ(key) == .private_identifier {
			tokens << 'private'
		}
	}
	if t.flag(node, .async) or { false } {
		tokens << 'async'
	}
	if t.flag(node, .generator) or { false } {
		tokens << 'generator'
	}
	if object_method || class_method {
		kind := t.string_of(parent, .kind) or { '' }
		if kind == 'constructor' {
			return 'constructor'
		}
		tokens << match kind {
			'get' { 'getter' }
			'set' { 'setter' }
			else { 'method' }
		}
	} else if field_method {
		tokens << 'method'
	} else {
		if t.typ(node) == .arrow_function_expression {
			tokens << 'arrow'
		}
		tokens << 'function'
	}
	if object_method || class_method || field_method {
		if key >= 0 && t.typ(key) == .private_identifier {
			tokens << '#${t.string_of(key, .name) or { '' }}'
		} else if name := c.un_property_name(t, parent) {
			if name != '' {
				tokens << "'${name}'"
			}
		} else if key >= 0 {
			text := c.un_text(t, key)
			if !text.contains('\n') {
				tokens << '[${text}]'
			}
		}
	} else if id := t.node(node, .id) {
		tokens << "'${t.string_of(id, .name) or { '' }}'"
	} else if ptyp == .variable_declarator {
		id := t.node(parent, .id) or { -1 }
		if id >= 0 && t.typ(id) == .identifier {
			tokens << "'${t.string_of(id, .name) or { '' }}'"
		}
	} else if ptyp in [.assignment_expression, .assignment_pattern] {
		left := t.node(parent, .left) or { -1 }
		if left >= 0 && t.typ(left) == .identifier {
			tokens << "'${t.string_of(left, .name) or { '' }}'"
		}
	} else if ptyp == .export_default_declaration && t.node(parent, .declaration) or { -1 } == node {
		tokens << "'default'"
	}
	return tokens.join(' ')
}
