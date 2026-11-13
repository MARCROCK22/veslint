module rules

import time
import tsgo { TypeResponse }
import treesitter { Ident, children, first_named_child, has_child_kind, named_children, node_end, node_field, node_kind, node_parent, node_start, nodes_of_kind, position_of, prev_sibling }

// Port of the `require-await` rule of typescript-eslint 8.62.0 (it has no options), with its
// `removeAsync` suggestion. Limits of the port: internals.md, "Rules" section.

const ra_messages = {
	'missingAwait': "{{name}} has no 'await' expression."
	'removeAsync':  "Remove 'async'."
}

// tree-sitter nodes that are a function in ESTree: ArrowFunctionExpression, FunctionDeclaration
// or FunctionExpression (also the value of a method).
const function_kinds = ['function_declaration', 'function_expression', 'generator_function',
	'generator_function_declaration', 'arrow_function', 'method_definition']

// ESTree literals (`Literal`): a `yield` of a literal does not count.
const literal_kinds = ['string', 'number', 'true', 'false', 'null', 'regex']

// AsyncCandidate is a non-empty async function without `await` or `for await`: whether it is
// reported depends on the types of these nodes.
struct AsyncCandidate {
	node C.TSNode
mut:
	thenables []C.TSNode // if any is thenable, it counts as an await (parameters and body of
	// an arrow, and `return` expressions)
	yields    []C.TSNode // arguments of `yield`
	delegates []C.TSNode // arguments of `yield*`
}

fn (mut c Checker) lint_require_await(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut has_await := map[u64]bool{}
	for node in c.nodes_of_kind(root, c'await_expression') {
		if f := enclosing_function(node) {
			has_await[node_key(f)] = true
		}
	}
	for loop in c.nodes_of_kind(root, c'for_in_statement') {
		// `for await (… of …)`, or a header that declares with `await using`.
		if is_for_await_of(loop) || using_kind(loop) == 'await using' {
			if f := enclosing_function(loop) {
				has_await[node_key(f)] = true
			}
		}
	}
	// VariableDeclaration[kind = "await using"]
	for declaration in c.nodes_of_kind(root, c'lexical_declaration') {
		if using_kind(declaration) == 'await using' {
			if f := enclosing_function(declaration) {
				has_await[node_key(f)] = true
			}
		}
	}
	mut functions := []C.TSNode{}
	functions << c.nodes_of_kind(root, c'function_declaration')
	functions << c.nodes_of_kind(root, c'function_expression')
	functions << c.nodes_of_kind(root, c'generator_function')
	functions << c.nodes_of_kind(root, c'generator_function_declaration')
	functions << c.nodes_of_kind(root, c'arrow_function')
	functions << c.nodes_of_kind(root, c'method_definition')
	mut candidates := []AsyncCandidate{}
	mut index := map[u64]int{}
	for f in functions {
		if !has_child_kind(f, 'async') || has_await[node_key(f)] || is_empty_function(f) {
			continue
		}
		mut candidate := AsyncCandidate{
			node: f
		}
		if node_kind(f) == 'arrow_function' {
			candidate.thenables << arrow_children(f)
		}
		index[node_key(f)] = candidates.len
		candidates << candidate
	}
	if candidates.len > 0 {
		for ret in c.nodes_of_kind(root, c'return_statement') {
			expr := first_named_child(ret) or { continue }
			f := enclosing_function(ret) or { continue }
			i := index[node_key(f)] or { continue }
			candidates[i].thenables << expr
		}
		for y in c.nodes_of_kind(root, c'yield_expression') {
			arg := unwrap_parens(first_named_child(y) or { continue })
			f := enclosing_function(y) or { continue }
			i := index[node_key(f)] or { continue }
			if node_kind(arg) in literal_kinds {
				continue
			}
			if has_child_kind(y, '*') {
				candidates[i].delegates << arg
			} else {
				candidates[i].yields << arg
			}
		}
	}
	mut wanted := []C.TSNode{}
	for candidate in candidates {
		wanted << candidate.thenables
		wanted << candidate.yields
		wanted << candidate.delegates
	}
	c.resolve_node_types(wanted, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for candidate in candidates {
		if c.reports_missing_await(candidate)! {
			findings << Finding{
				stmt:        c.function_head(candidate.node)
				message_id:  'missingAwait'
				data:        {
					'name': c.function_name(candidate.node)
				}
				suggestions: c.ra_remove_async(candidate.node)!
			}
		}
	}
	findings.sort(a.stmt.start_byte < b.stmt.start_byte)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += functions.len
	return findings
}

// ra_remove_async ports the `removeAsync` suggestion: it removes the `async` keyword (a `;` takes
// its place if what follows would continue the previous statement) and unwraps a `Promise<T>`
// return type, or makes an `AsyncGenerator` one a `Generator`.
fn (mut c Checker) ra_remove_async(f C.TSNode) ![]Suggestion {
	// nodeWithAsyncKeyword: the function, or the MethodDefinition or Property of a method. In
	// ESTree a class method starts at its first decorator, which tree-sitter leaves before it.
	mut first := f
	mut class_method := false
	if node_kind(f) == 'method_definition' {
		if parent := node_parent(f) {
			class_method = node_kind(parent) == 'class_body'
		}
		if class_method {
			mut current := f
			for {
				previous := prev_sibling(current) or { break }
				kind := node_kind(previous)
				if kind == 'decorator' {
					first = previous
				} else if kind != 'comment' {
					break
				}
				current = previous
			}
		}
	}
	// getFirstToken(nodeWithAsyncKeyword, token => token.value === 'async')
	tokens := c.source_tokens(f)
	mut found := false
	mut async_token := SourceToken{}
	for token in tokens.inside(node_start(first), node_end(f), false) {
		if c.token_text(token) == 'async' {
			async_token = token
			found = true
			break
		}
	}
	if !found {
		return []Suggestion{}
	}
	// Up to the next token or comment.
	after := tokens.after(async_token.end, true) or { return []Suggestion{} }
	next := tokens.after(async_token.end, false) or { return []Suggestion{} }
	// Without `async`, a `[` or a `(` could continue the statement before: a `;` goes in its place.
	add_semicolon := (c.token_is(next, '[') || c.token_is(next, '('))
		&& (class_method || is_start_of_expression_statement(f))
		&& c.needs_preceding_semicolon(first)
	mut fixes := [
		fix_replace_range(async_token.start, after.start, if add_semicolon { ';' } else { '' }),
	]
	fixes << c.ra_return_type_fixes(f)
	ok, suggestion := c.suggestion('removeAsync', map[string]string{}, fixes)!
	return if ok { [suggestion] } else { []Suggestion{} }
}

// ra_return_type_fixes are the changes of `removeAsync` to a return type that is a type reference:
// `AsyncGenerator` becomes `Generator` in a generator, and `Promise<T>` becomes `T` elsewhere.
fn (mut c Checker) ra_return_type_fixes(f C.TSNode) []Fix {
	annotation := node_field(f, 'return_type') or { return []Fix{} }
	if node_kind(annotation) != 'type_annotation' {
		return []Fix{}
	}
	reference := unwrap_type_parens(first_named(annotation) or { return []Fix{} })
	// hasTypeName: the name of the reference is an identifier (not a qualified name).
	name := match node_kind(reference) {
		'generic_type' { node_field(reference, 'name') or { return []Fix{} } }
		'type_identifier' { reference }
		else { return []Fix{} }
	}
	if node_kind(name) != 'type_identifier' {
		return []Fix{}
	}
	if is_generator(f) {
		if c.text(name) == 'AsyncGenerator' {
			return [fix_replace(name, 'Generator')]
		}
		return []Fix{}
	}
	if c.text(name) != 'Promise' || node_kind(reference) != 'generic_type' {
		return []Fix{}
	}
	// The first `<` and the last `>` of the reference: its type arguments.
	mut open := -1
	mut close := SourceToken{}
	for token in c.node_tokens(reference) {
		if open < 0 && c.token_is(token, '<') {
			open = token.end
		}
		if c.token_is(token, '>') {
			close = token
		}
	}
	if open < 0 || close.end == 0 {
		return []Fix{}
	}
	return [fix_remove_range(close.start, close.end), fix_remove_range(node_start(name), open)]
}

// reports_missing_await decides with the types. If some node lacks a type (no tsgo node with its
// range) nothing is reported: it cannot be ruled out that it is thenable.
fn (mut c Checker) reports_missing_await(candidate AsyncCandidate) !bool {
	mut unknown := false
	for n in candidate.thenables {
		t := c.node_type(n) or {
			unknown = true
			continue
		}
		if c.is_thenable(t, c.symbol_location(n))! {
			return false
		}
	}
	if is_generator(candidate.node) {
		for n in candidate.yields {
			t := c.node_type(n) or {
				unknown = true
				continue
			}
			if c.is_thenable(t, c.symbol_location(n))! {
				return false
			}
		}
		for n in candidate.delegates {
			t := c.node_type(n) or {
				unknown = true
				continue
			}
			for part in c.flatten(t, 0)! {
				if c.has_well_known_property(part, 'asyncIterator')! {
					return false
				}
			}
		}
	}
	return !unknown
}

// flatten ports expandUnionOrIntersectionType: the parts of unions and intersections.
fn (mut c Checker) flatten(t TypeResponse, depth int) ![]TypeResponse {
	if depth > max_type_depth || t.flags & (type_flag_union | type_flag_intersection) == 0 {
		return [t]
	}
	mut parts := []TypeResponse{}
	for member in c.members_of(t)! {
		parts << c.flatten(member, depth + 1)!
	}
	return parts
}

// enclosing_function gives the innermost function containing `n`, like the rule's scopeInfo. The
// computed key of a method is evaluated outside of it.
fn enclosing_function(n C.TSNode) ?C.TSNode {
	mut child := n
	mut node := node_parent(n)?
	for {
		kind := node_kind(node)
		if kind in function_kinds {
			is_key := kind == 'method_definition' && same_node(node_field(node, 'name'), child)
			if !is_key {
				return node
			}
		}
		child = node
		node = node_parent(node)?
	}
	return none
}

fn same_node(a ?C.TSNode, b C.TSNode) bool {
	node := a or { return false }
	return node_key(node) == node_key(b)
}

fn is_generator(f C.TSNode) bool {
	kind := node_kind(f)
	return kind in ['generator_function', 'generator_function_declaration']
		|| (kind == 'method_definition' && has_child_kind(f, '*'))
}

// is_empty_function: the body is a block without statements (comments do not count).
fn is_empty_function(f C.TSNode) bool {
	body := node_field(f, 'body') or { return false }
	return node_kind(body) == 'statement_block' && named_children(body).len == 0
}

// arrow_children are the children of an arrow that the selector
// `ArrowFunctionExpression[async = true] > :not(BlockStatement, AwaitExpression)` checks with the
// type: the parameters, and the body if it is an expression. It also selects the return
// annotation and the type parameters, but typescript-estree maps them to no TypeScript node and
// they are never thenable.
fn arrow_children(f C.TSNode) []C.TSNode {
	mut out := []C.TSNode{}
	if param := node_field(f, 'parameter') {
		out << param
	} else if params := node_field(f, 'parameters') {
		for p in named_children(params) {
			out << estree_param(p)
		}
	}
	if body := node_field(f, 'body') {
		inner := unwrap_parens(body)
		if node_kind(body) != 'statement_block' && node_kind(inner) != 'await_expression' {
			out << inner
		}
	}
	return out
}

// estree_param is the TypeScript node typescript-estree maps to a parameter: the whole parameter
// if it is a rest one or has a default value, and otherwise its name or pattern.
fn estree_param(p C.TSNode) C.TSNode {
	pattern := node_field(p, 'pattern') or { return p }
	if node_kind(pattern) == 'rest_pattern' {
		return p
	}
	if _ := node_field(p, 'value') {
		return p
	}
	return pattern
}

// estree_parent is the ESTree parent, where parentheses are not nodes.
fn estree_parent(n C.TSNode) ?C.TSNode {
	mut parent := node_parent(n)?
	for node_kind(parent) == 'parenthesized_expression' {
		parent = node_parent(parent)?
	}
	return parent
}

// is_value_of: `f` is the value of the property or field `member`.
fn is_value_of(member C.TSNode, f C.TSNode) bool {
	value := node_field(member, 'value') or { return false }
	return node_key(unwrap_parens(value)) == node_key(f)
}

// function_head ports typescript-eslint's getFunctionHeadLoc, which is where the rules report:
// from the class member (without its decorators) or the property whose value the function is,
// or from the function, to the opening paren of its parameters; or the `=>` of other arrows.
fn (mut c Checker) function_head(f C.TSNode) Ident {
	kind := node_kind(f)
	if kind == 'method_definition' {
		return c.position_range(node_start(f), c.es_params_paren(f))
	}
	if parent := estree_parent(f) {
		parent_kind := node_kind(parent)
		if parent_kind == 'public_field_definition' && is_value_of(parent, f) {
			return c.position_range(member_start(parent).start_byte, c.es_params_paren(f))
		}
		if parent_kind == 'pair' && is_value_of(parent, f) {
			return c.position_range(node_start(parent), c.es_params_paren(f))
		}
	}
	if kind == 'arrow_function' {
		for child in children(f) {
			if node_kind(child) == '=>' {
				return position_of(child)
			}
		}
	}
	return c.position_range(node_start(f), c.es_params_paren(f))
}

// member_start is the first token of a class member after its decorators.
fn member_start(member C.TSNode) Ident {
	all := children(member)
	mut first := 0
	for i, child in all {
		if node_kind(child) == 'decorator' {
			first = i + 1
		}
	}
	for child in all[first..] {
		if node_kind(child) != 'comment' {
			return position_of(child)
		}
	}
	return position_of(member)
}

// function_name ports getFunctionNameWithKind from eslint-utils, capitalized like
// typescript-eslint's upperCaseFirst: "Static async method 'x'", "Async arrow function 'f'", etc.
// typescript-eslint calls it without `sourceCode`, so a computed key that is not static gets no
// name.
fn (mut c Checker) function_name(f C.TSNode) string {
	kind := node_kind(f)
	is_method := kind == 'method_definition'
	mut parent_kind := ''
	mut member := f
	if parent := estree_parent(f) {
		parent_kind = node_kind(parent)
		if !is_method {
			member = parent
		}
	}
	in_pair := !is_method && parent_kind == 'pair' && is_value_of(member, f)
	in_field := !is_method && parent_kind == 'public_field_definition' && is_value_of(member, f)
	method_like := is_method || in_pair || in_field
	mut words := []string{}
	mut key := ?C.TSNode(none)
	if method_like {
		key = node_field(member, if in_pair { 'key' } else { 'name' })
	}
	if (is_method && parent_kind == 'class_body') || in_field {
		if has_child_kind(member, 'static') {
			words << 'static'
		}
		if k := key {
			if node_kind(k) == 'private_property_identifier' {
				words << 'private'
			}
		}
	}
	words << 'async'
	if is_generator(f) {
		words << 'generator'
	}
	if method_like {
		words << 'method'
	} else {
		if kind == 'arrow_function' {
			words << 'arrow'
		}
		words << 'function'
	}
	if method_like {
		if k := key {
			if node_kind(k) == 'private_property_identifier' {
				words << c.text(k)
			} else if static_name := c.static_key_name(k) {
				// eslint-utils names it only when the name is truthy: `async ''() {}` has none.
				if static_name != '' {
					words << "'${static_name}'"
				}
			}
		}
	} else if id := node_field(f, 'name') {
		words << "'${c.text(id)}'"
	} else if parent := estree_parent(f) {
		name := c.binding_name(parent, f)
		if name != '' {
			words << name
		}
	}
	text := words.join(' ')
	return text[..1].to_upper() + text[1..]
}

// static_key_name ports getPropertyName for the key of a member, without a scope: an identifier
// is its name, a literal its value as a string, and a computed key its static value as a string,
// where no identifier is static.
fn (mut c Checker) static_key_name(key C.TSNode) ?string {
	match node_kind(key) {
		'property_identifier' {
			return c.text(key)
		}
		'string', 'number' {
			return c.string_if_constant_unscoped(key)
		}
		'computed_property_name' {
			return c.string_if_constant_unscoped(first_named_child(key)?)
		}
		else {
			return none
		}
	}
}

// binding_name is the name an anonymous function is assigned to: variable, assignment, default
// value or `export default`.
fn (c &Checker) binding_name(parent C.TSNode, f C.TSNode) string {
	match node_kind(parent) {
		'variable_declarator' {
			name := node_field(parent, 'name') or { return '' }
			if node_kind(name) == 'identifier' {
				return "'${c.text(name)}'"
			}
		}
		'assignment_expression', 'augmented_assignment_expression', 'assignment_pattern',
		'object_assignment_pattern' {
			left := node_field(parent, 'left') or { return '' }
			if node_kind(left) in ['identifier', 'shorthand_property_identifier_pattern'] {
				return "'${c.text(left)}'"
			}
		}
		'required_parameter', 'optional_parameter' {
			pattern := node_field(parent, 'pattern') or { return '' }
			if node_kind(pattern) == 'identifier' && is_value_of(parent, f) {
				return "'${c.text(pattern)}'"
			}
		}
		'export_statement' {
			if is_value_of(parent, f) {
				return "'default'"
			}
		}
		else {}
	}
	return ''
}
