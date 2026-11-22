module rules

import json2
import os
import treesitter { Parser, children, first_named_child, named_children, node_end, node_field, node_kind, node_start, nodes_of_kind, nodes_of_kinds, position_of, root_node, token_ends }
import math
import strconv
import jsregexp
import crypto.sha1
import tsgo { CompilerOptions }

// ---- directives_test.v ----

// The cases come from tools/gen_inline_config_cases.mjs: what ESLint's parser of configuration
// comments makes of the text of a `/* eslint … */` comment (the rules in order, each with its
// value; an object is written as {"$keys": [[key, value, own]…]}), or the message of its error.

// inline_value_form writes a value read from a comment as the cases do.
fn inline_value_form(value json2.Any) json2.Any {
	if value is []json2.Any {
		return json2.Any(value.map(inline_value_form(it)))
	}
	if value is map[string]json2.Any {
		mut keys := []json2.Any{}
		for key in js_object_keys(value) {
			keys << json2.Any([json2.Any(key), inline_value_form(value[key] or {
				json2.Any(json2.null)
			}), json2.Any(true)])
		}
		return json2.Any({
			'\$keys': json2.Any(keys)
		})
	}
	if json_is_number(value) {
		number := json_number(value)
		if number != number || number - number != 0 {
			return json2.Any({
				'\$js': json2.Any(if number != number {
					'NaN'
				} else if number > 0 {
					'Infinity'
				} else {
					'-Infinity'
				})
			})
		}
	}
	return value
}

// levn_stand_in turns the values of a case that JSON does not have into what veslint has in their
// place (see levn.v): a regular expression is an object without properties, and undefined is null
// in a list and no property in an object.
fn levn_stand_in(value json2.Any) json2.Any {
	if value is []json2.Any {
		return json2.Any(value.map(levn_stand_in(it)))
	}
	if value is map[string]json2.Any {
		if special := value['\$js'] {
			text := special.str()
			if text == 'undefined' {
				return json2.Any(json2.null)
			}
			if text.starts_with('/') {
				return json2.Any({
					'\$keys': json2.Any([]json2.Any{})
				})
			}
			return value
		}
		mut keys := []json2.Any{}
		for item in value['\$keys'] or { json2.Any([]json2.Any{}) }.as_array() {
			entry := item.as_array()
			if js_json_stringify(entry[1]) == '{"\$js":"undefined"}' {
				continue
			}
			keys << json2.Any([entry[0], levn_stand_in(entry[1]), entry[2]])
		}
		return json2.Any({
			'\$keys': json2.Any(keys)
		})
	}
	return value
}

fn test_inline_rules_are_read_like_eslint() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'inline_config_cases.json')) or {
		panic(err)
	}
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	mut checked := 0
	mut dates := 0
	mut wrong := []string{}
	for item in data['cases'] or { panic('no cases') }.as_array() {
		entry := item.as_map()
		text := entry['text'] or { panic('no text') }.str()
		expected := if message := entry['error'] {
			'error: ${message.str()}'
		} else {
			// The rules are a list of [id, value, own]: a list for levn_stand_in too.
			js_json_stringify(levn_stand_in(entry['rules'] or { panic('no rules') }))
		}
		// A `#…#` that V8 reads as a date: veslint does not read dates.
		if expected.contains('"date ') {
			dates++
			continue
		}
		mut got := ''
		if ids, values := parse_inline_rules(text) {
			mut read := []json2.Any{}
			for i, id in ids {
				read << json2.Any([json2.Any(id), inline_value_form(values[i]), json2.Any(true)])
			}
			got = js_json_stringify(json2.Any(read))
		} else {
			got = 'error: ${err.msg()}'
		}
		if got != expected {
			wrong << '${json2.encode(text)}\n  got    ${got}\n  ESLint ${expected}'
		}
		checked++
	}
	if wrong.len > 0 {
		assert false, '${wrong.len} differences:\n' + wrong.join('\n')
	}
	assert checked >= 100
	assert dates == 1
}

// ---- fix_precedence_test.v ----

// Expected values computed with typescript-eslint 8.62.0's own functions on the argument of each
// call to `t`: getOperatorPrecedenceForNode(node), and for its TypeScript node
// getOperatorPrecedence(kind, SyntaxKind.Unknown), getOperatorPrecedence(kind, the node's own
// operator if it is a BinaryExpression), getOperatorPrecedence(kind, Unknown, true) and
// isHigherPrecedenceThanAwait(node).
struct PrecedenceCase {
	code              string
	estree            int
	ts_unknown        int
	ts_own_operator   int
	ts_with_arguments int
	higher_than_await bool
}

const precedence_cases = [
	PrecedenceCase{'t(a);', 20, 20, 20, 20, true},
	PrecedenceCase{'t(undefined);', 20, 20, 20, 20, true},
	PrecedenceCase{'t(this);', 20, 20, 20, 20, true},
	PrecedenceCase{'t(1);', 20, 20, 20, 20, true},
	PrecedenceCase{'t(1n);', 20, 20, 20, 20, true},
	PrecedenceCase{"t('s');", 20, 20, 20, 20, true},
	PrecedenceCase{'t(`t`);', 20, 20, 20, 20, true},
	PrecedenceCase{'t(`t\${a}`);', 20, 20, 20, 20, true},
	PrecedenceCase{'t(/re/g);', 20, 20, 20, 20, true},
	PrecedenceCase{'t(true);', 20, 20, 20, 20, true},
	PrecedenceCase{'t(null);', 20, 20, 20, 20, true},
	PrecedenceCase{'t([a]);', 20, 20, 20, 20, true},
	PrecedenceCase{'t({ a });', 20, 20, 20, 20, true},
	PrecedenceCase{'t(function () {});', 20, 20, 20, 20, true},
	PrecedenceCase{'t(function* () {});', 20, 20, 20, 20, true},
	PrecedenceCase{'t(class {});', 20, 20, 20, 20, true},
	PrecedenceCase{'t(x => x);', 2, 20, 20, 20, true},
	PrecedenceCase{'t((a));', 20, 20, 20, 20, true},
	PrecedenceCase{'t((a, b));', 0, -1, 0, -1, false},
	PrecedenceCase{'t((a = b));', -1, -1, 3, -1, false},
	PrecedenceCase{'t((a += b));', 3, -1, 3, -1, false},
	PrecedenceCase{'t((a ??= b));', 3, -1, 3, -1, false},
	PrecedenceCase{'t((a **= b));', 3, -1, 3, -1, false},
	PrecedenceCase{'t((a >>>= b));', 3, -1, 3, -1, false},
	PrecedenceCase{'t(a + b);', 13, -1, 13, -1, false},
	PrecedenceCase{'t(a - b);', 13, -1, 13, -1, false},
	PrecedenceCase{'t(a * b);', 14, -1, 14, -1, false},
	PrecedenceCase{'t(a / b);', 14, -1, 14, -1, false},
	PrecedenceCase{'t(a % b);', 14, -1, 14, -1, false},
	PrecedenceCase{'t(a ** b);', 15, -1, 15, -1, false},
	PrecedenceCase{'t(a == b);', 3, -1, 10, -1, false},
	PrecedenceCase{'t(a != b);', 10, -1, 10, -1, false},
	PrecedenceCase{'t(a === b);', 10, -1, 10, -1, false},
	PrecedenceCase{'t(a !== b);', 10, -1, 10, -1, false},
	PrecedenceCase{'t(a < b);', 11, -1, 11, -1, false},
	PrecedenceCase{'t(a <= b);', 11, -1, 11, -1, false},
	PrecedenceCase{'t(a > b);', 11, -1, 11, -1, false},
	PrecedenceCase{'t(a >= b);', 11, -1, 11, -1, false},
	PrecedenceCase{'t(a in b);', 11, -1, 11, -1, false},
	PrecedenceCase{'t(a instanceof b);', 11, -1, 11, -1, false},
	PrecedenceCase{'t(a << b);', 12, -1, 12, -1, false},
	PrecedenceCase{'t(a >> b);', 12, -1, 12, -1, false},
	PrecedenceCase{'t(a >>> b);', 12, -1, 12, -1, false},
	PrecedenceCase{'t(a & b);', 9, -1, 9, -1, false},
	PrecedenceCase{'t(a | b);', 7, -1, 7, -1, false},
	PrecedenceCase{'t(a ^ b);', 8, -1, 8, -1, false},
	PrecedenceCase{'t(a && b);', 6, -1, 6, -1, false},
	PrecedenceCase{'t(a || b);', 5, -1, 5, -1, false},
	PrecedenceCase{'t(a ?? b);', 4, -1, 4, -1, false},
	PrecedenceCase{'t(a ? b : c);', 4, 4, 4, 4, false},
	PrecedenceCase{'t(-a);', 16, 16, 16, 16, false},
	PrecedenceCase{'t(+a);', 16, 16, 16, 16, false},
	PrecedenceCase{'t(!a);', 16, 16, 16, 16, false},
	PrecedenceCase{'t(~a);', 16, 16, 16, 16, false},
	PrecedenceCase{'t(typeof a);', 16, 16, 16, 16, false},
	PrecedenceCase{'t(void a);', 16, 16, 16, 16, false},
	PrecedenceCase{'t(delete a.b);', 16, 16, 16, 16, false},
	PrecedenceCase{'t(++a);', 16, 16, 16, 16, false},
	PrecedenceCase{'t(--a);', 16, 16, 16, 16, false},
	PrecedenceCase{'t(a++);', 17, 17, 17, 17, true},
	PrecedenceCase{'t(a--);', 17, 17, 17, 17, true},
	PrecedenceCase{'t(a.b);', 19, 19, 19, 19, true},
	PrecedenceCase{'t(a[b]);', 19, 19, 19, 19, true},
	PrecedenceCase{'t(a?.b);', 19, 19, 19, 19, true},
	PrecedenceCase{'t(a?.[b]);', 19, 19, 19, 19, true},
	PrecedenceCase{'t(a?.b.c);', 19, 19, 19, 19, true},
	PrecedenceCase{'t(a.b());', 18, 18, 18, 18, true},
	PrecedenceCase{'t(a());', 18, 18, 18, 18, true},
	PrecedenceCase{'t(a?.());', 18, 18, 18, 18, true},
	PrecedenceCase{'t(a?.b());', 18, 18, 18, 18, true},
	PrecedenceCase{'t(new A);', 18, 18, 18, 19, true},
	PrecedenceCase{'t(new A());', 18, 18, 18, 19, true},
	PrecedenceCase{'t(new A(1));', 19, 18, 18, 19, true},
	PrecedenceCase{'t(new A.B(1, 2));', 19, 18, 18, 19, true},
	PrecedenceCase{'t(tag`t`);', 19, 19, 19, 19, true},
	PrecedenceCase{'t(import.meta);', 19, 19, 19, 19, true},
	PrecedenceCase{"t(import('x'));", -1, 18, 18, 18, true},
	PrecedenceCase{'t(super.x);', 19, 19, 19, 19, true},
	PrecedenceCase{'t(a!);', 16, 16, 16, 16, false},
	PrecedenceCase{'t(a!.b);', 19, 19, 19, 19, true},
	PrecedenceCase{'t(<T>a);', 16, 16, 16, 16, false},
	PrecedenceCase{'t(a as T);', 11, 11, 11, 11, false},
	PrecedenceCase{'t(a satisfies T);', -1, 11, 11, 11, false},
	PrecedenceCase{'t(a as const);', 11, 11, 11, 11, false},
	PrecedenceCase{'t(f<string>);', -1, -1, -1, -1, false},
	PrecedenceCase{'t(...a);', 1, 1, 1, 1, false},
	PrecedenceCase{'function* g() { t(yield a); }', 2, 2, 2, 2, false},
	PrecedenceCase{'function* g() { t(yield* a); }', 2, 2, 2, 2, false},
	PrecedenceCase{'async function f() { t(await a); }', 16, 16, 16, 16, false},
]

// precedence_test_argument is the first argument of the call to `t`, as ESTree has it (without
// parentheses).
fn precedence_test_argument(root C.vt_node, src string) C.vt_node {
	for call in nodes_of_kind(root, c'call_expression') {
		function := node_field(call, 'function') or { continue }
		if node_kind(function) == 'identifier' && src[treesitter.node_start(function)..treesitter.node_end(function)] == 't' {
			arguments := call_arguments(call) or { continue }
			return unwrap_parens(arguments[0])
		}
	}
	panic('no call to t in ${src}')
}

fn test_operator_precedence() {
	parser := treesitter.new_parser() or { panic(err) }
	for t in precedence_cases {
		tree := parser.parse(t.code) or { panic(err) }
		argument := precedence_test_argument(root_node(tree), t.code)
		assert estree_operator_precedence(argument) == t.estree, t.code
		assert ts_operator_precedence(argument, '', false) == t.ts_unknown, t.code
		assert ts_operator_precedence(argument, ts_binary_operator(argument), false) == t.ts_own_operator, t.code
		assert ts_operator_precedence(argument, '', true) == t.ts_with_arguments, t.code
		assert is_higher_precedence_than_await(argument) == t.higher_than_await, t.code
	}
}

// A parenthesized_expression is TypeScript's ParenthesizedExpression: Primary.
fn test_parenthesized_expression_precedence() {
	parser := treesitter.new_parser() or { panic(err) }
	src := 't((a + b));'
	tree := parser.parse(src) or { panic(err) }
	for call in nodes_of_kind(root_node(tree), c'call_expression') {
		arguments := call_arguments(call) or { continue }
		assert ts_operator_precedence(arguments[0], '', false) == precedence_primary
		assert is_higher_precedence_than_await(arguments[0])
	}
}

// ---- fix_tokens_test.v ----

// FixTokenCase is an ESTree node of one of the programs of tests/fix_tokens_cases.json (its byte
// range and type) with what the original functions return for it inside ESLint. The file comes
// from tools/gen_fix_tokens_cases.mjs: eslint-utils' isParenthesized, and typescript-eslint's
// getTextWithParentheses, isStartOfExpressionStatement, needsPrecedingSemicolon,
// isStrongPrecedenceNode, isWeakPrecedenceParent, getMovedNodeCode (the node moved to its own
// place) and getWrappingFixer (without `wrap`, and wrapping the node in `[…]` and in `!…`).
struct FixTokenCase {
	program            int
	start              int
	end                int
	estree             string
	parenthesized      bool
	with_parentheses   string
	start_of_statement bool
	needs_semicolon    bool
	strong             bool
	weak               bool
	inner              string
	moved              string
	bracket            string
	bang               string
}

// The tree-sitter kinds of each ESTree type in the cases.
const fix_token_kinds = {
	'Identifier':                ['identifier', 'undefined', 'property_identifier',
		'shorthand_property_identifier', 'shorthand_property_identifier_pattern', 'type_identifier',
		'statement_identifier']
	'Literal':                   ['string', 'number', 'true', 'false', 'null', 'regex']
	'MemberExpression':          ['member_expression', 'subscript_expression']
	'CallExpression':            ['call_expression']
	'ImportExpression':          ['call_expression']
	'TaggedTemplateExpression':  ['call_expression']
	'ChainExpression':           ['member_expression', 'subscript_expression', 'call_expression',
		'non_null_expression']
	'NewExpression':             ['new_expression']
	'BinaryExpression':          ['binary_expression']
	'LogicalExpression':         ['binary_expression']
	'UnaryExpression':           ['unary_expression']
	'UpdateExpression':          ['update_expression']
	'ConditionalExpression':     ['ternary_expression']
	'AwaitExpression':           ['await_expression']
	'YieldExpression':           ['yield_expression']
	'ArrayExpression':           ['array']
	'ObjectExpression':          ['object']
	'ArrowFunctionExpression':   ['arrow_function']
	'FunctionExpression':        ['function_expression', 'generator_function']
	'ClassExpression':           ['class']
	'TemplateLiteral':           ['template_string']
	'TSAsExpression':            ['as_expression']
	'TSSatisfiesExpression':     ['satisfies_expression']
	'TSNonNullExpression':       ['non_null_expression']
	'TSTypeAssertion':           ['type_assertion']
	'AssignmentExpression':      ['assignment_expression', 'augmented_assignment_expression']
	'SequenceExpression':        ['sequence_expression']
	'ThisExpression':            ['this']
	'SpreadElement':             ['spread_element']
	'TSInstantiationExpression': ['instantiation_expression']
	'TSTypeReference':           ['type_identifier', 'generic_type', 'nested_type_identifier']
	'TSTypeOperator':            ['index_type_query', 'readonly_type']
	'TSStringKeyword':           ['predefined_type']
	'TSArrayType':               ['array_type']
	'TSUnionType':               ['union_type']
}

fn fix_token_field(entry map[string]json2.Any, name string) json2.Any {
	return entry[name] or { panic('no ${name}') }
}

// fix_token_cases reads the programs and the cases.
fn fix_token_cases() ([]string, []FixTokenCase) {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'fix_tokens_cases.json')) or { panic(err) }
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	programs := fix_token_field(data, 'programs').as_array().map(it.str())
	mut cases := []FixTokenCase{}
	for item in fix_token_field(data, 'cases').as_array() {
		entry := item.as_map()
		cases << FixTokenCase{
			program:            fix_token_field(entry, 'program').int()
			start:              fix_token_field(entry, 'start').int()
			end:                fix_token_field(entry, 'end').int()
			estree:             fix_token_field(entry, 'type').str()
			parenthesized:      fix_token_field(entry, 'parenthesized').bool()
			with_parentheses:   fix_token_field(entry, 'withParentheses').str()
			start_of_statement: fix_token_field(entry, 'startOfStatement').bool()
			needs_semicolon:    fix_token_field(entry, 'needsSemicolon').bool()
			strong:             fix_token_field(entry, 'strong').bool()
			weak:               fix_token_field(entry, 'weak').bool()
			inner:              fix_token_field(entry, 'inner').str()
			moved:              fix_token_field(entry, 'moved').str()
			bracket:            fix_token_field(entry, 'bracket').str()
			bang:               fix_token_field(entry, 'bang').str()
		}
	}
	return programs, cases
}

// fix_token_node finds the named node with that range and one of those kinds.
fn fix_token_node(n C.vt_node, start int, end int, kinds []string) ?C.vt_node {
	if node_start(n) > start || node_end(n) < end {
		return none
	}
	if node_start(n) == start && node_end(n) == end && C.vt_node_is_named(n) && node_kind(n) in kinds {
		return n
	}
	for child in children(n) {
		if found := fix_token_node(child, start, end, kinds) {
			return found
		}
	}
	return none
}

fn test_fix_token_utilities() {
	parser := treesitter.new_parser() or { panic(err) }
	programs, cases := fix_token_cases()
	assert cases.len >= 700
	mut failures := []string{}
	for i, program in programs {
		tree := parser.parse(program) or { panic(err) }
		mut c := &Checker{
			src: program
		}
		for t in cases {
			if t.program != i {
				continue
			}
			label := '${t.estree} `${program[t.start..t.end]}` at ${t.start} of program ${i}'
			node := fix_token_node(root_node(tree), t.start, t.end, fix_token_kinds[t.estree]) or {
				failures << 'no node: ${label}'
				continue
			}
			e := EsNode{
				node:  node
				chain: t.estree == 'ChainExpression'
			}
			inner := c.wrapping_inner_code(e, e)
			got := FixTokenCase{
				...t
				parenthesized:      c.is_parenthesized(e)
				with_parentheses:   c.text_with_parentheses(e)
				start_of_statement: is_start_of_expression_statement(node)
				needs_semicolon:    c.needs_preceding_semicolon(node)
				strong:             is_strong_precedence_node(e)
				weak:               is_weak_precedence_parent(e)
				inner:              inner
				moved:              c.moved_node_code(e, e)
				bracket:            c.wrapping_fix(e, '[${inner}]').text
				bang:               c.wrapping_fix(e, '!${inner}').text
			}
			if got != t {
				failures << '${label}:\n  expected ${t}\n  got      ${got}'
			}
		}
		treesitter.rows_free(tree)
	}
	assert failures.len == 0, failures.join('\n')
}

// es_child gives the ESTree node of a child: parentheses unwrapped, and the ChainExpression of an
// optional chain.
fn test_es_child() {
	parser := treesitter.new_parser() or { panic(err) }
	src := 'f((a?.b), (c.d), e?.g.h);'
	tree := parser.parse(src) or { panic(err) }
	for call in treesitter.nodes_of_kind(root_node(tree), c'call_expression') {
		args := call_arguments(call) or { continue }
		if args.len != 3 {
			continue
		}
		first := es_child(args[0])
		assert first.chain && src[node_start(first.node)..node_end(first.node)] == 'a?.b'
		assert !es_inner(args[0]).chain
		second := es_child(args[1])
		assert !second.chain && src[node_start(second.node)..node_end(second.node)] == 'c.d'
		third := es_child(args[2])
		assert third.chain && src[node_start(third.node)..node_end(third.node)] == 'e?.g.h'
		// The parent of the expression in a chain is its ChainExpression; the parent of that one,
		// and of an argument that is not a chain, is the call.
		inner_parent := es_inner(args[0]).parent() or { panic('no parent') }
		assert inner_parent == first
		assert (first.parent() or { panic('no parent') }) == es_inner(call)
		assert (second.parent() or { panic('no parent') }) == es_inner(call)
	}
	treesitter.rows_free(tree)
}

// The token queries of SourceCode.
fn test_source_tokens() {
	parser := treesitter.new_parser() or { panic(err) }
	src := "// lead\nconst a = /* one */ /* two */ f(`x\${b}y`, 's') // tail\n/* last */"
	tree := parser.parse(src) or { panic(err) }
	tokens := build_source_tokens(root_node(tree), src)
	texts := tokens.tokens.map(src[it.start..it.end])
	assert texts == ['const', 'a', '=', 'f', '(', '`x\${', 'b', '}y`', ',', "'s'", ')']
	assert tokens.tokens.map(it.kind) == [SourceTokenKind.keyword, .identifier, .punctuator,
		.identifier, .punctuator, .template, .identifier, .template, .punctuator, .string_,
		.punctuator]
	assert tokens.comments.map(src[it.start..it.end]) == ['// lead', '/* one */', '/* two */',
		'// tail', '/* last */']
	f := src.index('f(') or { panic('no f') }
	before := tokens.before(f, false) or { panic('no token') }
	assert src[before.start..before.end] == '='
	before_comment := tokens.before(f, true) or { panic('no token') }
	assert src[before_comment.start..before_comment.end] == '/* two */'
	after := tokens.after(f + 1, false) or { panic('no token') }
	assert src[after.start..after.end] == '('
	assert tokens.before(0, true) == none
	assert tokens.after(src.len, true) == none
	assert tokens.comments_before(f).map(src[it.start..it.end]) == ['/* one */', '/* two */']
	assert tokens.comments_before(before.start).len == 0
	end := src.index(') //') or { panic('no end') } + 1
	assert tokens.comments_after(end).map(src[it.start..it.end]) == ['// tail', '/* last */']
	assert tokens.comments_inside(0, f).len == 3
	assert tokens.comments_exist_between(before.end, f)
	assert !tokens.comments_exist_between(f, end)
	assert tokens.inside(f, end, false).len == 8
	assert tokens.inside(before.end, f, true).len == 2
	treesitter.rows_free(tree)
}

// ---- gitignore_test.v ----

// tests/gitignore_cases.json (tools/gen_gitignore_cases.mjs) has what the `ignore` package answers
// for lists of gitignore patterns and a set of paths; gitignore.v must answer the same.
fn test_gitignore_matches_the_ignore_package() {
	text := os.read_file(os.join_path(@VMODROOT, 'tests/gitignore_cases.json')) or { panic(err) }
	data := (json2.decode[json2.Any](text) or { panic(err) }).as_map()
	paths := data['paths'] or { panic('no paths') }.as_array().map(it.str())
	mut failures := []string{}
	cases := data['cases'] or { panic('no cases') }.as_array()
	for entry in cases {
		item := entry.as_map()
		patterns := item['patterns'] or { panic('no patterns') }.as_array().map(it.str())
		ignore_case := (item['ignorecase'] or { json2.Any(false) }).bool()
		want := item['ignored'] or { panic('no ignored') }.as_array().map(it.str())
		mut matcher := new_gitignore(patterns, ignore_case)
		got := paths.filter(matcher.ignores(it))
		if got != want {
			failures << '${patterns} (ignorecase ${ignore_case}): ${got}, ignore has ${want}'
		}
	}
	assert failures.len == 0, '${failures.len} of ${cases.len} cases differ:\n${failures[..if failures.len > 10 {
		10
	} else {
		failures.len
	}].join('\n')}'
}

// ---- html_attribute_test.v ----

// The cases come from tools/gen_html_entities.mjs: inputs with what decodeHTMLAttribute of the
// `entities` package gives for them (tests/html_attribute_cases.json).

fn test_html_decode_attribute_matches_entities() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'html_attribute_cases.json')) or {
		panic(err)
	}
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	mut failures := []string{}
	cases := (data['cases'] or { panic('no cases') }).as_array()
	for item in cases {
		values := item.as_array()
		got := html_decode_attribute(values[0].str())
		if got != values[1].str() {
			failures << '${json2.encode(values[0].str())}: ${json2.encode(got)}, entities ${json2.encode(values[1].str())}'
		}
	}
	assert failures == []
	assert cases.len > 20000
}

// ---- js_math_test.v ----

// The cases come from tools/gen_math_cases.mjs: the bits of what V8's Math functions give for
// chosen arguments, and digests of what they give for arguments built from a seed, built here the
// same way.

const math_unary_names = ['acos', 'acosh', 'asin', 'asinh', 'atan', 'atanh', 'cbrt', 'cos', 'cosh',
	'exp', 'expm1', 'log', 'log1p', 'log2', 'log10', 'sin', 'sinh', 'tan', 'tanh']

fn math_cases() map[string]json2.Any {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'math_cases.json')) or { panic(err) }
	return (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
}

fn math_from_hex(text string) f64 {
	return math.f64_from_bits(strconv.parse_uint(text, 16, 64) or { panic(err) })
}

// math_hex writes the bits of a double, with one NaN for all of them, as the generator does.
fn math_hex(x f64) string {
	return if math.is_nan(x) { '7ff8000000000000' } else { '${math.f64_bits(x):016x}' }
}

fn math_unary(name string, x f64) f64 {
	return js_math_function('Math.${name}', x) or { panic('no Math.${name}') }
}

fn test_chosen_arguments_match_v8() {
	data := math_cases()
	cases := (data['cases'] or { panic('no cases') }).as_map()
	mut checked := 0
	for name in math_unary_names {
		for item in (cases[name] or { panic('no ${name}') }).as_array() {
			pair := item.as_array()
			x := math_from_hex(pair[0].str())
			assert math_hex(math_unary(name, x)) == pair[1].str(), 'Math.${name}(${x}) (${pair[0].str()})'
			checked++
		}
	}
	for item in (cases['atan2'] or { panic('no atan2') }).as_array() {
		triple := item.as_array()
		y := math_from_hex(triple[0].str())
		x := math_from_hex(triple[1].str())
		assert math_hex(js_math_atan2(y, x)) == triple[2].str(), 'Math.atan2(${y}, ${x})'
		checked++
	}
	for item in (cases['hypot'] or { panic('no hypot') }).as_array() {
		pair := item.as_array()
		args := pair[0].as_array().map(math_from_hex(it.str()))
		assert math_hex(js_math_hypot(args)) == pair[1].str(), 'Math.hypot(${args})'
		checked++
	}
	assert checked > 1000
}

// MathGenerator is the generator's linear congruential generator.
struct MathGenerator {
mut:
	state u32
}

fn (mut g MathGenerator) next() u32 {
	g.state = g.state * 1103515245 + 12345
	return g.state
}

fn (mut g MathGenerator) unit() f64 {
	return f64(g.next()) / 4294967296.0
}

// math_argument builds an argument of a kind as the generator does, with its numbers in the same
// order.
fn math_argument(mode string, mut g MathGenerator) f64 {
	match mode {
		'bits' {
			high := g.next()
			return js_math_words(high, g.next())
		}
		'unit' {
			return g.unit() * 2 - 1
		}
		'small' {
			return g.unit() * 32 - 16
		}
		'exp' {
			return g.unit() * 1500 - 750
		}
		'wide', 'huge' {
			sign := g.next() & 0x80000000
			exponent := if mode == 'wide' {
				u32(1023 - 60) + g.next() % 121
			} else {
				u32(1023) +
					g.next() % 1024
			}
			significand := g.next() & 0xfffff
			return js_math_words(sign | (exponent << 20) | significand, g.next())
		}
		'pio2' {
			k := f64(i64(g.next() % 200001) - 100000)
			return k * 1.5707963267948966 + (g.unit() - 0.5) * 9.313225746154785e-10
		}
		'near1' {
			return 1 + (g.unit() - 0.5) * 9.5367431640625e-7
		}
		else {
			panic('unknown kind of argument ${mode}')
		}
	}
}

fn math_arguments(mode string, count int, start u32) []f64 {
	mut g := MathGenerator{
		state: start
	}
	mut out := []f64{cap: count}
	for _ in 0 .. count {
		out << math_argument(mode, mut g)
	}
	return out
}

// math_digests are the generator's FNV-1a digests of the bits of the results, a chunk at a time.
fn math_digests(results []f64, chunk_size int) []string {
	mut out := []string{}
	for start := 0; start < results.len; start += chunk_size {
		mut h := u32(0x811c9dc5)
		for x in results[start..math.min(start + chunk_size, results.len)] {
			bits := if math.is_nan(x) { u64(0x7ff8000000000000) } else { math.f64_bits(x) }
			h = (h ^ u32(bits & 0xffffffff)) * 0x01000193
			h = (h ^ u32(bits >> 32)) * 0x01000193
		}
		out << '${h:08x}'
	}
	return out
}

fn math_expected(data map[string]json2.Any, name string, mode string) []string {
	digests := (data['digests'] or { panic('no digests') }).as_map()
	return ((digests[name] or { panic('no ${name}') }).as_map()[mode] or { panic('no ${mode}') }).as_array().map(it.str())
}

fn test_arguments_from_the_seed_match_v8() {
	data := math_cases()
	seed := u32((data['seed'] or { panic('no seed') }).i64())
	count := (data['perMode'] or { panic('no perMode') }).int()
	chunk_size := (data['chunkSize'] or { panic('no chunkSize') }).int()
	modes := (data['modes'] or { panic('no modes') }).as_array().map(it.str())
	for i, mode in modes {
		arguments := math_arguments(mode, count, seed + u32(i))
		for name in math_unary_names {
			results := arguments.map(math_unary(name, it))
			assert math_digests(results, chunk_size) == math_expected(data, name, mode), 'Math.${name} of the ${mode} arguments'
		}
		ys := math_arguments(mode, count, seed + 100 + u32(i))
		xs := math_arguments(mode, count, seed + 200 + u32(i))
		mut results := []f64{cap: count}
		for j, y in ys {
			results << js_math_atan2(y, xs[j])
		}
		assert math_digests(results, chunk_size) == math_expected(data, 'atan2', mode), 'Math.atan2 of the ${mode} arguments'
	}
	// hypot of 0 to 6 arguments: a special one one time in eight, else a `wide` one.
	specials := (data['specials'] or { panic('no specials') }).as_array().map(math_from_hex(it.str()))
	mut g := MathGenerator{
		state: seed + 300
	}
	mut results := []f64{cap: count}
	for _ in 0 .. count {
		mut args := []f64{}
		for _ in 0 .. g.next() % 7 {
			args << if g.next() % 8 == 0 {
				specials[g.next() % u32(specials.len)]
			} else {
				math_argument('wide', mut g)
			}
		}
		results << js_math_hypot(args)
	}
	assert math_digests(results, chunk_size) == math_expected(data, 'hypot', 'mixed'), 'Math.hypot'
}

// ---- json_errors_test.v ----

// The cases come from tools/gen_json_error_cases.mjs: the message of the error V8 throws from
// `JSON.parse(text)`, or '' for valid JSON.
fn test_v8_json_error_matches_v8() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'json_error_cases.json')) or { panic(err) }
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	mut checked := 0
	mut wrong := []string{}
	for item in data['cases'] or { panic('no cases') }.as_array() {
		entry := item.as_map()
		text := entry['text'] or { panic('no text') }.str()
		expected := entry['message'] or { panic('no message') }.str()
		got := v8_json_error(text)
		if got != expected {
			wrong << 'JSON.parse(${json2.encode(text)}): got `${got}`, V8 gives `${expected}`'
		}
		checked++
	}
	assert wrong == []string{}
	assert checked >= 75
}

// ---- json_schema_test.v ----

// The cases come from tools/gen_rule_option_cases.mjs: what ESLint itself says of many option
// values of each ported rule, as the options of the rule in a configuration (`config`: the message
// of the error it throws, or null when it takes them) and in the comment
// `/* eslint rule: [severity, ...options] */` (the message it reports); and the same for schemas
// made for the keywords the rules do not exercise. The message of the comment is in `inline` only
// when it is not `config` as ESLint's linter cuts it (the generator checks that for every case).

fn option_cases() map[string]json2.Any {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'rule_option_cases.json')) or {
		panic(err)
	}
	return (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
}

// OptionCase is a case of the file for the rule with that id.
struct OptionCase {
	options  []json2.Any
	severity json2.Any // as the comment has it
	comment  string    // the text of the comment after `eslint`
	config   string    // ESLint's messages; '' when it takes the options
	inline   string
}

fn option_case(id string, item json2.Any) OptionCase {
	entry := item.as_map()
	options := entry['options'] or { panic('no options') }.as_array()
	severity := entry['severity'] or { json2.Any(2) }
	mut value := [severity]
	for option in options {
		value << option
	}
	config := entry['config'] or { panic('no config') }
	expected_config := if config is string { config } else { '' }
	prefix := 'Key "rules": Key "${id}":'
	assert expected_config == '' || expected_config.starts_with(prefix)
	mut expected_inline := if expected_config == '' {
		''
	} else {
		'Inline configuration for rule "${id}" is invalid:\n\t${js_trim(expected_config[prefix.len..])}\n'
	}
	if inline := entry['inline'] {
		expected_inline = if inline is string { inline } else { '' }
	}
	return OptionCase{
		options:  options
		severity: severity
		comment:  '${id}: ${js_json_stringify(json2.Any(value))}'
		config:   expected_config
		inline:   expected_inline
	}
}

// first_differences keeps a failure readable: the first few, and how many there are.
fn first_differences(wrong []string) string {
	if wrong.len == 0 {
		return ''
	}
	return '${wrong.len} differences; the first ones:\n' + wrong#[..5].join('\n')
}

// rule_schemas.v has the schemas ESLint has for the ported rules and the default options of its
// rules and typescript-eslint's, with the properties in the same order.
fn test_rule_schemas_are_those_of_eslint() {
	data := option_cases()
	schemas := data['schemas'] or { panic('no schemas') }.as_map()
	assert schemas.len == names.len
	assert rule_option_schemas.len == names.len
	for name in names {
		table := json2.decode[json2.Any](rule_option_schemas[name] or { panic('no schema of ${name}') }) or {
			panic(err)
		}
		// The cases name the typescript-eslint rules without their prefix.
		// The rules of ESLint core are `core/<id>` (dot-notation is also a typescript-eslint name).
		// (A wrapper of another plugin, like svelte/@typescript-eslint/…, keeps its whole name.)
		key := if name.starts_with(typescript_eslint_prefix) {
			name.all_after(typescript_eslint_prefix)
		} else if name.contains('/') {
			name
		} else {
			'core/' + name
		}
		assert js_json_stringify(table) == js_json_stringify(schemas[key] or {
			panic('ESLint has no schema of ${name}')
		}), name
	}
	defaults := data['ruleDefaults'] or { panic('no ruleDefaults') }.as_map()
	assert eslint_rule_default_options.len == defaults.len
	assert defaults.len > 100
	for id, value in defaults {
		assert js_json_stringify(json2.Any(eslint_default_options(id))) == js_json_stringify(value), id
	}
}

// The options of every case, for a rule that is on, give the text of ESLint's error for a
// configuration; and the comment of every case, read and applied as the comments of a file are,
// the message ESLint reports for it.
fn test_rule_options_are_validated_like_eslint() {
	data := option_cases()
	mut checked := 0
	mut rejected := 0
	mut wrong := []string{}
	for group in data['rules'] or { panic('no rules') }.as_array() {
		name := group.as_map()['rule'] or { panic('no rule') }.str()
		// The cases name the typescript-eslint rules without their prefix (the others by their id,
		// which for a rule of ESLint core, marked `core`, has none); veslint, by their id.
		core := (group.as_map()['core'] or { json2.Any(false) }).bool()
		id := if name.contains('/') || core { name } else { typescript_eslint_prefix + name }
		for item in group.as_map()['cases'] or { panic('no cases') }.as_array() {
			case := option_case(id, item)
			// ESLint does not validate the options of a rule a configuration turns off.
			problems := if rule_severity_of(case.severity) == 0 {
				''
			} else {
				rule_options_problems(id, case.options)
			}
			config := if problems == '' { '' } else { 'Key "rules": Key "${id}":\n${problems}' }
			if config != case.config {
				wrong << '${case.comment} in a configuration:\n  got ${json2.encode(config)}\n  ESLint gives ${json2.encode(case.config)}'
			}
			label, value, _ := parse_directive(' eslint ${case.comment} ') or {
				panic(case.comment)
			}
			assert label == 'eslint'
			mut checker := Checker{}
			mut result := InlineConfig{
				comments: [DirectiveComment{
					label: label
					value: value
				}]
			}
			checker.apply_inline_rules(mut result, LintConfig{})
			inline := if result.problems.len == 0 { '' } else { result.problems[0].text }
			if inline != case.inline || result.problems.len > 1 {
				wrong << '/* eslint ${case.comment} */:\n  got ${json2.encode(inline)}\n  ESLint gives ${json2.encode(case.inline)}'
			}
			checked++
			if case.inline != '' {
				rejected++
			}
		}
	}
	assert first_differences(wrong) == ''
	assert checked >= 4000
	assert rejected >= 2500
}

// The validator itself, on schemas with the keywords and the combinations the rules do not have.
fn test_schemas_are_validated_like_ajv() {
	data := option_cases()
	mut checked := 0
	mut rejected := 0
	mut wrong := []string{}
	for group in data['synthetic'] or { panic('no synthetic') }.as_array() {
		name := group.as_map()['name'] or { panic('no name') }.str()
		id := 'synthetic/${name}'
		schema := group.as_map()['schema'] or { panic('no schema') }
		for item in group.as_map()['cases'] or { panic('no cases') }.as_array() {
			case := option_case(id, item)
			severity := rule_severity_of(case.severity)
			problems := schema_problem_lines(schema, json2.Any(case.options))
			config := if problems == '' || severity == 0 {
				''
			} else {
				'Key "rules": Key "${id}":\n${problems}'
			}
			if config != case.config {
				wrong << '${case.comment} in a configuration:\n  got ${json2.encode(config)}\n  ESLint gives ${json2.encode(case.config)}'
			}
			// In a comment the options are the ones ESLint's parser reads from it, and only the
			// number 0 goes without validation.
			_, values := parse_inline_rules(case.comment) or { panic(case.comment) }
			read := values[0].as_array()
			inline_problems := schema_problem_lines(schema, json2.Any(read[1..]))
			inline := if inline_problems == '' || (json_is_number(read[0]) && severity == 0) {
				''
			} else {
				'Inline configuration for rule "${id}" is invalid:\n\t${js_trim(inline_problems)}\n'
			}
			if inline != case.inline {
				wrong << '/* eslint ${case.comment} */:\n  got ${json2.encode(inline)}\n  ESLint gives ${json2.encode(case.inline)}'
			}
			checked++
			if case.inline != '' {
				rejected++
			}
		}
	}
	assert first_differences(wrong) == ''
	assert checked >= 2000
	assert rejected >= 1000
}

// A pattern that is not a regular expression fits the schema (a string): in ESLint the rule
// throws when it starts; veslint says so in the place of the comment.
fn test_inline_options_veslint_cannot_take() {
	mut checker := Checker{}
	mut result := InlineConfig{
		comments: [
			DirectiveComment{
				label: 'eslint'
				value: '@typescript-eslint/dot-notation: [2, {"allowPattern": "("}]'
			},
		]
	}
	checker.apply_inline_rules(mut result, LintConfig{})
	assert result.problems.len == 1
	assert result.problems[0].text.starts_with('Inline configuration for rule "@typescript-eslint/dot-notation" is invalid:\n\t`@typescript-eslint/dot-notation`: option `allowPattern`')
	// Turned off, the rule never starts.
	mut off := InlineConfig{
		comments: [
			DirectiveComment{
				label: 'eslint'
				value: '@typescript-eslint/dot-notation: ["off", {"allowPattern": "("}]'
			},
		]
	}
	checker.apply_inline_rules(mut off, LintConfig{})
	assert off.problems.len == 0
}

fn test_json_for_error() {
	value := json2.decode[json2.Any]('{"a": [1, {"b": null}, []], "c": {}, "10": "x\\ny"}') or {
		panic(err)
	}
	assert json_for_error(value, true, 4) == '{\n        "10": "x\\ny",\n        "a": [\n            1,\n            {\n                "b": null\n            },\n            []\n        ],\n        "c": {}\n    }'
	assert json_for_error(json2.Any(''), true, 4) == ''
	assert json_for_error(json2.Any(f64(0)), true, 4) == '0'
	assert json_for_error(json2.Any(false), true, 4) == 'false'
	assert json_for_error(json2.Any(json2.null), true, 8) == 'null'
	assert json_for_error(json2.Any(json2.null), false, 4) == 'undefined'
	assert json_for_error(json2.Any('x'), true, 4) == '"x"'
}

// ---- literals_test.v ----

// Expected values computed with Node (String(eval(literal)) and eval of each string).

fn test_js_number_string() {
	cases := {
		'16':                              '16'
		'0x10':                            '16'
		'0X1F':                            '31'
		'0o17':                            '15'
		'0b101':                           '5'
		'017':                             '15'
		'019':                             '19'
		'1.50':                            '1.5'
		'.5':                              '0.5'
		'1.':                              '1'
		'1e3':                             '1000'
		'1e21':                            '1e+21'
		'1e+21':                           '1e+21'
		'1e-7':                            '1e-7'
		'1.5e-7':                          '1.5e-7'
		'0.000001':                        '0.000001'
		'123456789012345680000':           '123456789012345680000'
		'9007199254740993':                '9007199254740992'
		'1_000_000':                       '1000000'
		'0x1_0':                           '16'
		'1e400':                           'Infinity'
		'5e-324':                          '5e-324'
		'0':                               '0'
		'0.0':                             '0'
		'100':                             '100'
		'1n':                              '1'
		'0x10n':                           '16'
		'123456789012345678901234567890n': '123456789012345678901234567890'
	}
	for text, want in cases {
		got := js_number_string(text) or { '<none>' }
		assert got == want, '${text}: ${got} != ${want}'
	}
}

// Number::toString of values no literal token has: negatives, NaN and the infinities.
fn test_js_number_to_string() {
	cases := {
		'-1':                     js_number_to_string(-1)
		'-2.5':                   js_number_to_string(-2.5)
		'-1e+21':                 js_number_to_string(-1e21)
		'-1e-7':                  js_number_to_string(-1e-7)
		'-0.5':                   js_number_to_string(-0.5)
		'-123456789012345680000': js_number_to_string(-123456789012345680000.0)
		'-5e-324':                js_number_to_string(-5e-324)
		'0':                      js_number_to_string(-0.0)
		'NaN':                    js_number_to_string(math.nan())
		'Infinity':               js_number_to_string(math.inf(1))
		'-Infinity':              js_number_to_string(math.inf(-1))
	}
	for want, got in cases {
		assert got == want, '${got} != ${want}'
	}
}

fn test_cooked_string() {
	assert cooked_string('a\\tb', false) or { '' } == 'a\tb'
	assert cooked_string('\\x41\\u0042\\u{43}', false) or { '' } == 'ABC'
	assert cooked_string('\\uD83D\\uDE00', false) or { '' } == '😀'
	assert cooked_string("\\'", false) or { '' } == "'"
	assert cooked_string('l\\\n', false) or { '' } == 'l'
	assert cooked_string('\\a', false) or { '' } == 'a'
	assert cooked_string('\\0', false) or { '' } == [u8(0)].bytestr()
	assert cooked_string('c\r\nd', true) or { '' } == 'c\nd'
	assert cooked_string('plain', false) or { '' } == 'plain'
	assert cooked_string('é\\é', false) or { '' } == 'éé'
}

fn test_cooked_string_invalid() {
	for raw in ['\\1', '\\01', '\\uD83D', '\\uDE00', '\\u{110000}', '\\x4', '\\u{}', 'fin\\'] {
		if got := cooked_string(raw, false) {
			assert false, '${raw}: expected none, got ${got}'
		}
	}
}

// ---- locale_compare_test.v ----

// Pairs compared by Node (ICU, en-US) with String.prototype.localeCompare.
fn test_js_locale_compare_like_node() {
	cases := [
		LocaleCase{"Odd.x·y", "Odd.ªb", 1},
		LocaleCase{"Odd.x·y", "Odd.é", 1},
		LocaleCase{"Odd.x·y", "Odd.e", 1},
		LocaleCase{"Odd.x·y", "Odd.E", 1},
		LocaleCase{"Odd.x·y", "Odd.ea", 1},
		LocaleCase{"Odd.x·y", "Odd.éa", 1},
		LocaleCase{"Odd.x·y", "Odd.eb", 1},
		LocaleCase{"Odd.x·y", "Odd.日本", -1},
		LocaleCase{"Odd.x·y", "Odd.ab", 1},
		LocaleCase{"Odd.x·y", "Odd.яa", -1},
		LocaleCase{"Odd.x·y", "Odd.αa", -1},
		LocaleCase{"Odd.x·y", "x-", -1},
		LocaleCase{"Odd.x·y", "x.", -1},
		LocaleCase{"Odd.x·y", "x0", -1},
		LocaleCase{"Odd.x·y", "xé", -1},
		LocaleCase{"Odd.x·y", "xÉ", -1},
		LocaleCase{"Odd.x·y", "\"1\"", 1},
		LocaleCase{"Odd.x·y", "1", 1},
		LocaleCase{"Odd.x·y", "10", 1},
		LocaleCase{"Odd.x·y", "2", 1},
		LocaleCase{"Odd.x·y", "-2n", 1},
		LocaleCase{"Odd.x·y", "10n", 1},
		LocaleCase{"Odd.x·y", "1n", 1},
		LocaleCase{"Odd.x·y", "null", 1},
		LocaleCase{"Odd.x·y", "undefined", -1},
		LocaleCase{"Odd.x·y", "true", -1},
		LocaleCase{"Odd.x·y", "Enum.a", 1},
		LocaleCase{"Odd.x·y", "Enum.B", 1},
		LocaleCase{"Odd.x·y", "Enum.b", 1},
		LocaleCase{"Odd.x·y", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"Odd.x·y", "\"a\"", 1},
		LocaleCase{"Odd.x·y", "\"B\"", 1},
		LocaleCase{"Odd.x·y", "\"c\"", 1},
		LocaleCase{"Odd.x·y", "Apple.aLast", 1},
		LocaleCase{"Odd.x·y", "Apple.same", 1},
		LocaleCase{"Odd.x·y", "Zebra.same", -1},
		LocaleCase{"Odd.x·y", "Zebra.zLast", -1},
		LocaleCase{"Odd.x·y", "a b", 1},
		LocaleCase{"Odd.x·y", "a_b", 1},
		LocaleCase{"Odd.x·y", "a-b", 1},
		LocaleCase{"Odd.x·y", "ab", 1},
		LocaleCase{"Odd.x·y", "aB", 1},
		LocaleCase{"Odd.x·y", "Ab", 1},
		LocaleCase{"Odd.x·y", "\$x", 1},
		LocaleCase{"Odd.x·y", "_x", 1},
		LocaleCase{"Odd.x·y", "x", -1},
		LocaleCase{"Odd.ªb", "Odd.é", -1},
		LocaleCase{"Odd.ªb", "Odd.e", -1},
		LocaleCase{"Odd.ªb", "Odd.E", -1},
		LocaleCase{"Odd.ªb", "Odd.ea", -1},
		LocaleCase{"Odd.ªb", "Odd.éa", -1},
		LocaleCase{"Odd.ªb", "Odd.eb", -1},
		LocaleCase{"Odd.ªb", "Odd.日本", -1},
		LocaleCase{"Odd.ªb", "Odd.ab", 1},
		LocaleCase{"Odd.ªb", "Odd.яa", -1},
		LocaleCase{"Odd.ªb", "Odd.αa", -1},
		LocaleCase{"Odd.ªb", "x-", -1},
		LocaleCase{"Odd.ªb", "x.", -1},
		LocaleCase{"Odd.ªb", "x0", -1},
		LocaleCase{"Odd.ªb", "xé", -1},
		LocaleCase{"Odd.ªb", "xÉ", -1},
		LocaleCase{"Odd.ªb", "\"1\"", 1},
		LocaleCase{"Odd.ªb", "1", 1},
		LocaleCase{"Odd.ªb", "10", 1},
		LocaleCase{"Odd.ªb", "2", 1},
		LocaleCase{"Odd.ªb", "-2n", 1},
		LocaleCase{"Odd.ªb", "10n", 1},
		LocaleCase{"Odd.ªb", "1n", 1},
		LocaleCase{"Odd.ªb", "null", 1},
		LocaleCase{"Odd.ªb", "undefined", -1},
		LocaleCase{"Odd.ªb", "true", -1},
		LocaleCase{"Odd.ªb", "Enum.a", 1},
		LocaleCase{"Odd.ªb", "Enum.B", 1},
		LocaleCase{"Odd.ªb", "Enum.b", 1},
		LocaleCase{"Odd.ªb", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"Odd.ªb", "\"a\"", 1},
		LocaleCase{"Odd.ªb", "\"B\"", 1},
		LocaleCase{"Odd.ªb", "\"c\"", 1},
		LocaleCase{"Odd.ªb", "Apple.aLast", 1},
		LocaleCase{"Odd.ªb", "Apple.same", 1},
		LocaleCase{"Odd.ªb", "Zebra.same", -1},
		LocaleCase{"Odd.ªb", "Zebra.zLast", -1},
		LocaleCase{"Odd.ªb", "a b", 1},
		LocaleCase{"Odd.ªb", "a_b", 1},
		LocaleCase{"Odd.ªb", "a-b", 1},
		LocaleCase{"Odd.ªb", "ab", 1},
		LocaleCase{"Odd.ªb", "aB", 1},
		LocaleCase{"Odd.ªb", "Ab", 1},
		LocaleCase{"Odd.ªb", "\$x", 1},
		LocaleCase{"Odd.ªb", "_x", 1},
		LocaleCase{"Odd.ªb", "x", -1},
		LocaleCase{"Odd.é", "Odd.e", 1},
		LocaleCase{"Odd.é", "Odd.E", 1},
		LocaleCase{"Odd.é", "Odd.ea", -1},
		LocaleCase{"Odd.é", "Odd.éa", -1},
		LocaleCase{"Odd.é", "Odd.eb", -1},
		LocaleCase{"Odd.é", "Odd.日本", -1},
		LocaleCase{"Odd.é", "Odd.ab", 1},
		LocaleCase{"Odd.é", "Odd.яa", -1},
		LocaleCase{"Odd.é", "Odd.αa", -1},
		LocaleCase{"Odd.é", "x-", -1},
		LocaleCase{"Odd.é", "x.", -1},
		LocaleCase{"Odd.é", "x0", -1},
		LocaleCase{"Odd.é", "xé", -1},
		LocaleCase{"Odd.é", "xÉ", -1},
		LocaleCase{"Odd.é", "\"1\"", 1},
		LocaleCase{"Odd.é", "1", 1},
		LocaleCase{"Odd.é", "10", 1},
		LocaleCase{"Odd.é", "2", 1},
		LocaleCase{"Odd.é", "-2n", 1},
		LocaleCase{"Odd.é", "10n", 1},
		LocaleCase{"Odd.é", "1n", 1},
		LocaleCase{"Odd.é", "null", 1},
		LocaleCase{"Odd.é", "undefined", -1},
		LocaleCase{"Odd.é", "true", -1},
		LocaleCase{"Odd.é", "Enum.a", 1},
		LocaleCase{"Odd.é", "Enum.B", 1},
		LocaleCase{"Odd.é", "Enum.b", 1},
		LocaleCase{"Odd.é", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"Odd.é", "\"a\"", 1},
		LocaleCase{"Odd.é", "\"B\"", 1},
		LocaleCase{"Odd.é", "\"c\"", 1},
		LocaleCase{"Odd.é", "Apple.aLast", 1},
		LocaleCase{"Odd.é", "Apple.same", 1},
		LocaleCase{"Odd.é", "Zebra.same", -1},
		LocaleCase{"Odd.é", "Zebra.zLast", -1},
		LocaleCase{"Odd.é", "a b", 1},
		LocaleCase{"Odd.é", "a_b", 1},
		LocaleCase{"Odd.é", "a-b", 1},
		LocaleCase{"Odd.é", "ab", 1},
		LocaleCase{"Odd.é", "aB", 1},
		LocaleCase{"Odd.é", "Ab", 1},
		LocaleCase{"Odd.é", "\$x", 1},
		LocaleCase{"Odd.é", "_x", 1},
		LocaleCase{"Odd.é", "x", -1},
		LocaleCase{"Odd.e", "Odd.E", -1},
		LocaleCase{"Odd.e", "Odd.ea", -1},
		LocaleCase{"Odd.e", "Odd.éa", -1},
		LocaleCase{"Odd.e", "Odd.eb", -1},
		LocaleCase{"Odd.e", "Odd.日本", -1},
		LocaleCase{"Odd.e", "Odd.ab", 1},
		LocaleCase{"Odd.e", "Odd.яa", -1},
		LocaleCase{"Odd.e", "Odd.αa", -1},
		LocaleCase{"Odd.e", "x-", -1},
		LocaleCase{"Odd.e", "x.", -1},
		LocaleCase{"Odd.e", "x0", -1},
		LocaleCase{"Odd.e", "xé", -1},
		LocaleCase{"Odd.e", "xÉ", -1},
		LocaleCase{"Odd.e", "\"1\"", 1},
		LocaleCase{"Odd.e", "1", 1},
		LocaleCase{"Odd.e", "10", 1},
		LocaleCase{"Odd.e", "2", 1},
		LocaleCase{"Odd.e", "-2n", 1},
		LocaleCase{"Odd.e", "10n", 1},
		LocaleCase{"Odd.e", "1n", 1},
		LocaleCase{"Odd.e", "null", 1},
		LocaleCase{"Odd.e", "undefined", -1},
		LocaleCase{"Odd.e", "true", -1},
		LocaleCase{"Odd.e", "Enum.a", 1},
		LocaleCase{"Odd.e", "Enum.B", 1},
		LocaleCase{"Odd.e", "Enum.b", 1},
		LocaleCase{"Odd.e", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"Odd.e", "\"a\"", 1},
		LocaleCase{"Odd.e", "\"B\"", 1},
		LocaleCase{"Odd.e", "\"c\"", 1},
		LocaleCase{"Odd.e", "Apple.aLast", 1},
		LocaleCase{"Odd.e", "Apple.same", 1},
		LocaleCase{"Odd.e", "Zebra.same", -1},
		LocaleCase{"Odd.e", "Zebra.zLast", -1},
		LocaleCase{"Odd.e", "a b", 1},
		LocaleCase{"Odd.e", "a_b", 1},
		LocaleCase{"Odd.e", "a-b", 1},
		LocaleCase{"Odd.e", "ab", 1},
		LocaleCase{"Odd.e", "aB", 1},
		LocaleCase{"Odd.e", "Ab", 1},
		LocaleCase{"Odd.e", "\$x", 1},
		LocaleCase{"Odd.e", "_x", 1},
		LocaleCase{"Odd.e", "x", -1},
		LocaleCase{"Odd.E", "Odd.ea", -1},
		LocaleCase{"Odd.E", "Odd.éa", -1},
		LocaleCase{"Odd.E", "Odd.eb", -1},
		LocaleCase{"Odd.E", "Odd.日本", -1},
		LocaleCase{"Odd.E", "Odd.ab", 1},
		LocaleCase{"Odd.E", "Odd.яa", -1},
		LocaleCase{"Odd.E", "Odd.αa", -1},
		LocaleCase{"Odd.E", "x-", -1},
		LocaleCase{"Odd.E", "x.", -1},
		LocaleCase{"Odd.E", "x0", -1},
		LocaleCase{"Odd.E", "xé", -1},
		LocaleCase{"Odd.E", "xÉ", -1},
		LocaleCase{"Odd.E", "\"1\"", 1},
		LocaleCase{"Odd.E", "1", 1},
		LocaleCase{"Odd.E", "10", 1},
		LocaleCase{"Odd.E", "2", 1},
		LocaleCase{"Odd.E", "-2n", 1},
		LocaleCase{"Odd.E", "10n", 1},
		LocaleCase{"Odd.E", "1n", 1},
		LocaleCase{"Odd.E", "null", 1},
		LocaleCase{"Odd.E", "undefined", -1},
		LocaleCase{"Odd.E", "true", -1},
		LocaleCase{"Odd.E", "Enum.a", 1},
		LocaleCase{"Odd.E", "Enum.B", 1},
		LocaleCase{"Odd.E", "Enum.b", 1},
		LocaleCase{"Odd.E", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"Odd.E", "\"a\"", 1},
		LocaleCase{"Odd.E", "\"B\"", 1},
		LocaleCase{"Odd.E", "\"c\"", 1},
		LocaleCase{"Odd.E", "Apple.aLast", 1},
		LocaleCase{"Odd.E", "Apple.same", 1},
		LocaleCase{"Odd.E", "Zebra.same", -1},
		LocaleCase{"Odd.E", "Zebra.zLast", -1},
		LocaleCase{"Odd.E", "a b", 1},
		LocaleCase{"Odd.E", "a_b", 1},
		LocaleCase{"Odd.E", "a-b", 1},
		LocaleCase{"Odd.E", "ab", 1},
		LocaleCase{"Odd.E", "aB", 1},
		LocaleCase{"Odd.E", "Ab", 1},
		LocaleCase{"Odd.E", "\$x", 1},
		LocaleCase{"Odd.E", "_x", 1},
		LocaleCase{"Odd.E", "x", -1},
		LocaleCase{"Odd.ea", "Odd.éa", -1},
		LocaleCase{"Odd.ea", "Odd.eb", -1},
		LocaleCase{"Odd.ea", "Odd.日本", -1},
		LocaleCase{"Odd.ea", "Odd.ab", 1},
		LocaleCase{"Odd.ea", "Odd.яa", -1},
		LocaleCase{"Odd.ea", "Odd.αa", -1},
		LocaleCase{"Odd.ea", "x-", -1},
		LocaleCase{"Odd.ea", "x.", -1},
		LocaleCase{"Odd.ea", "x0", -1},
		LocaleCase{"Odd.ea", "xé", -1},
		LocaleCase{"Odd.ea", "xÉ", -1},
		LocaleCase{"Odd.ea", "\"1\"", 1},
		LocaleCase{"Odd.ea", "1", 1},
		LocaleCase{"Odd.ea", "10", 1},
		LocaleCase{"Odd.ea", "2", 1},
		LocaleCase{"Odd.ea", "-2n", 1},
		LocaleCase{"Odd.ea", "10n", 1},
		LocaleCase{"Odd.ea", "1n", 1},
		LocaleCase{"Odd.ea", "null", 1},
		LocaleCase{"Odd.ea", "undefined", -1},
		LocaleCase{"Odd.ea", "true", -1},
		LocaleCase{"Odd.ea", "Enum.a", 1},
		LocaleCase{"Odd.ea", "Enum.B", 1},
		LocaleCase{"Odd.ea", "Enum.b", 1},
		LocaleCase{"Odd.ea", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"Odd.ea", "\"a\"", 1},
		LocaleCase{"Odd.ea", "\"B\"", 1},
		LocaleCase{"Odd.ea", "\"c\"", 1},
		LocaleCase{"Odd.ea", "Apple.aLast", 1},
		LocaleCase{"Odd.ea", "Apple.same", 1},
		LocaleCase{"Odd.ea", "Zebra.same", -1},
		LocaleCase{"Odd.ea", "Zebra.zLast", -1},
		LocaleCase{"Odd.ea", "a b", 1},
		LocaleCase{"Odd.ea", "a_b", 1},
		LocaleCase{"Odd.ea", "a-b", 1},
		LocaleCase{"Odd.ea", "ab", 1},
		LocaleCase{"Odd.ea", "aB", 1},
		LocaleCase{"Odd.ea", "Ab", 1},
		LocaleCase{"Odd.ea", "\$x", 1},
		LocaleCase{"Odd.ea", "_x", 1},
		LocaleCase{"Odd.ea", "x", -1},
		LocaleCase{"Odd.éa", "Odd.eb", -1},
		LocaleCase{"Odd.éa", "Odd.日本", -1},
		LocaleCase{"Odd.éa", "Odd.ab", 1},
		LocaleCase{"Odd.éa", "Odd.яa", -1},
		LocaleCase{"Odd.éa", "Odd.αa", -1},
		LocaleCase{"Odd.éa", "x-", -1},
		LocaleCase{"Odd.éa", "x.", -1},
		LocaleCase{"Odd.éa", "x0", -1},
		LocaleCase{"Odd.éa", "xé", -1},
		LocaleCase{"Odd.éa", "xÉ", -1},
		LocaleCase{"Odd.éa", "\"1\"", 1},
		LocaleCase{"Odd.éa", "1", 1},
		LocaleCase{"Odd.éa", "10", 1},
		LocaleCase{"Odd.éa", "2", 1},
		LocaleCase{"Odd.éa", "-2n", 1},
		LocaleCase{"Odd.éa", "10n", 1},
		LocaleCase{"Odd.éa", "1n", 1},
		LocaleCase{"Odd.éa", "null", 1},
		LocaleCase{"Odd.éa", "undefined", -1},
		LocaleCase{"Odd.éa", "true", -1},
		LocaleCase{"Odd.éa", "Enum.a", 1},
		LocaleCase{"Odd.éa", "Enum.B", 1},
		LocaleCase{"Odd.éa", "Enum.b", 1},
		LocaleCase{"Odd.éa", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"Odd.éa", "\"a\"", 1},
		LocaleCase{"Odd.éa", "\"B\"", 1},
		LocaleCase{"Odd.éa", "\"c\"", 1},
		LocaleCase{"Odd.éa", "Apple.aLast", 1},
		LocaleCase{"Odd.éa", "Apple.same", 1},
		LocaleCase{"Odd.éa", "Zebra.same", -1},
		LocaleCase{"Odd.éa", "Zebra.zLast", -1},
		LocaleCase{"Odd.éa", "a b", 1},
		LocaleCase{"Odd.éa", "a_b", 1},
		LocaleCase{"Odd.éa", "a-b", 1},
		LocaleCase{"Odd.éa", "ab", 1},
		LocaleCase{"Odd.éa", "aB", 1},
		LocaleCase{"Odd.éa", "Ab", 1},
		LocaleCase{"Odd.éa", "\$x", 1},
		LocaleCase{"Odd.éa", "_x", 1},
		LocaleCase{"Odd.éa", "x", -1},
		LocaleCase{"Odd.eb", "Odd.日本", -1},
		LocaleCase{"Odd.eb", "Odd.ab", 1},
		LocaleCase{"Odd.eb", "Odd.яa", -1},
		LocaleCase{"Odd.eb", "Odd.αa", -1},
		LocaleCase{"Odd.eb", "x-", -1},
		LocaleCase{"Odd.eb", "x.", -1},
		LocaleCase{"Odd.eb", "x0", -1},
		LocaleCase{"Odd.eb", "xé", -1},
		LocaleCase{"Odd.eb", "xÉ", -1},
		LocaleCase{"Odd.eb", "\"1\"", 1},
		LocaleCase{"Odd.eb", "1", 1},
		LocaleCase{"Odd.eb", "10", 1},
		LocaleCase{"Odd.eb", "2", 1},
		LocaleCase{"Odd.eb", "-2n", 1},
		LocaleCase{"Odd.eb", "10n", 1},
		LocaleCase{"Odd.eb", "1n", 1},
		LocaleCase{"Odd.eb", "null", 1},
		LocaleCase{"Odd.eb", "undefined", -1},
		LocaleCase{"Odd.eb", "true", -1},
		LocaleCase{"Odd.eb", "Enum.a", 1},
		LocaleCase{"Odd.eb", "Enum.B", 1},
		LocaleCase{"Odd.eb", "Enum.b", 1},
		LocaleCase{"Odd.eb", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"Odd.eb", "\"a\"", 1},
		LocaleCase{"Odd.eb", "\"B\"", 1},
		LocaleCase{"Odd.eb", "\"c\"", 1},
		LocaleCase{"Odd.eb", "Apple.aLast", 1},
		LocaleCase{"Odd.eb", "Apple.same", 1},
		LocaleCase{"Odd.eb", "Zebra.same", -1},
		LocaleCase{"Odd.eb", "Zebra.zLast", -1},
		LocaleCase{"Odd.eb", "a b", 1},
		LocaleCase{"Odd.eb", "a_b", 1},
		LocaleCase{"Odd.eb", "a-b", 1},
		LocaleCase{"Odd.eb", "ab", 1},
		LocaleCase{"Odd.eb", "aB", 1},
		LocaleCase{"Odd.eb", "Ab", 1},
		LocaleCase{"Odd.eb", "\$x", 1},
		LocaleCase{"Odd.eb", "_x", 1},
		LocaleCase{"Odd.eb", "x", -1},
		LocaleCase{"Odd.日本", "Odd.ab", 1},
		LocaleCase{"Odd.日本", "Odd.яa", 1},
		LocaleCase{"Odd.日本", "Odd.αa", 1},
		LocaleCase{"Odd.日本", "x-", -1},
		LocaleCase{"Odd.日本", "x.", -1},
		LocaleCase{"Odd.日本", "x0", -1},
		LocaleCase{"Odd.日本", "xé", -1},
		LocaleCase{"Odd.日本", "xÉ", -1},
		LocaleCase{"Odd.日本", "\"1\"", 1},
		LocaleCase{"Odd.日本", "1", 1},
		LocaleCase{"Odd.日本", "10", 1},
		LocaleCase{"Odd.日本", "2", 1},
		LocaleCase{"Odd.日本", "-2n", 1},
		LocaleCase{"Odd.日本", "10n", 1},
		LocaleCase{"Odd.日本", "1n", 1},
		LocaleCase{"Odd.日本", "null", 1},
		LocaleCase{"Odd.日本", "undefined", -1},
		LocaleCase{"Odd.日本", "true", -1},
		LocaleCase{"Odd.日本", "Enum.a", 1},
		LocaleCase{"Odd.日本", "Enum.B", 1},
		LocaleCase{"Odd.日本", "Enum.b", 1},
		LocaleCase{"Odd.日本", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"Odd.日本", "\"a\"", 1},
		LocaleCase{"Odd.日本", "\"B\"", 1},
		LocaleCase{"Odd.日本", "\"c\"", 1},
		LocaleCase{"Odd.日本", "Apple.aLast", 1},
		LocaleCase{"Odd.日本", "Apple.same", 1},
		LocaleCase{"Odd.日本", "Zebra.same", -1},
		LocaleCase{"Odd.日本", "Zebra.zLast", -1},
		LocaleCase{"Odd.日本", "a b", 1},
		LocaleCase{"Odd.日本", "a_b", 1},
		LocaleCase{"Odd.日本", "a-b", 1},
		LocaleCase{"Odd.日本", "ab", 1},
		LocaleCase{"Odd.日本", "aB", 1},
		LocaleCase{"Odd.日本", "Ab", 1},
		LocaleCase{"Odd.日本", "\$x", 1},
		LocaleCase{"Odd.日本", "_x", 1},
		LocaleCase{"Odd.日本", "x", -1},
		LocaleCase{"Odd.ab", "Odd.яa", -1},
		LocaleCase{"Odd.ab", "Odd.αa", -1},
		LocaleCase{"Odd.ab", "x-", -1},
		LocaleCase{"Odd.ab", "x.", -1},
		LocaleCase{"Odd.ab", "x0", -1},
		LocaleCase{"Odd.ab", "xé", -1},
		LocaleCase{"Odd.ab", "xÉ", -1},
		LocaleCase{"Odd.ab", "\"1\"", 1},
		LocaleCase{"Odd.ab", "1", 1},
		LocaleCase{"Odd.ab", "10", 1},
		LocaleCase{"Odd.ab", "2", 1},
		LocaleCase{"Odd.ab", "-2n", 1},
		LocaleCase{"Odd.ab", "10n", 1},
		LocaleCase{"Odd.ab", "1n", 1},
		LocaleCase{"Odd.ab", "null", 1},
		LocaleCase{"Odd.ab", "undefined", -1},
		LocaleCase{"Odd.ab", "true", -1},
		LocaleCase{"Odd.ab", "Enum.a", 1},
		LocaleCase{"Odd.ab", "Enum.B", 1},
		LocaleCase{"Odd.ab", "Enum.b", 1},
		LocaleCase{"Odd.ab", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"Odd.ab", "\"a\"", 1},
		LocaleCase{"Odd.ab", "\"B\"", 1},
		LocaleCase{"Odd.ab", "\"c\"", 1},
		LocaleCase{"Odd.ab", "Apple.aLast", 1},
		LocaleCase{"Odd.ab", "Apple.same", 1},
		LocaleCase{"Odd.ab", "Zebra.same", -1},
		LocaleCase{"Odd.ab", "Zebra.zLast", -1},
		LocaleCase{"Odd.ab", "a b", 1},
		LocaleCase{"Odd.ab", "a_b", 1},
		LocaleCase{"Odd.ab", "a-b", 1},
		LocaleCase{"Odd.ab", "ab", 1},
		LocaleCase{"Odd.ab", "aB", 1},
		LocaleCase{"Odd.ab", "Ab", 1},
		LocaleCase{"Odd.ab", "\$x", 1},
		LocaleCase{"Odd.ab", "_x", 1},
		LocaleCase{"Odd.ab", "x", -1},
		LocaleCase{"Odd.яa", "Odd.αa", 1},
		LocaleCase{"Odd.яa", "x-", -1},
		LocaleCase{"Odd.яa", "x.", -1},
		LocaleCase{"Odd.яa", "x0", -1},
		LocaleCase{"Odd.яa", "xé", -1},
		LocaleCase{"Odd.яa", "xÉ", -1},
		LocaleCase{"Odd.яa", "\"1\"", 1},
		LocaleCase{"Odd.яa", "1", 1},
		LocaleCase{"Odd.яa", "10", 1},
		LocaleCase{"Odd.яa", "2", 1},
		LocaleCase{"Odd.яa", "-2n", 1},
		LocaleCase{"Odd.яa", "10n", 1},
		LocaleCase{"Odd.яa", "1n", 1},
		LocaleCase{"Odd.яa", "null", 1},
		LocaleCase{"Odd.яa", "undefined", -1},
		LocaleCase{"Odd.яa", "true", -1},
		LocaleCase{"Odd.яa", "Enum.a", 1},
		LocaleCase{"Odd.яa", "Enum.B", 1},
		LocaleCase{"Odd.яa", "Enum.b", 1},
		LocaleCase{"Odd.яa", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"Odd.яa", "\"a\"", 1},
		LocaleCase{"Odd.яa", "\"B\"", 1},
		LocaleCase{"Odd.яa", "\"c\"", 1},
		LocaleCase{"Odd.яa", "Apple.aLast", 1},
		LocaleCase{"Odd.яa", "Apple.same", 1},
		LocaleCase{"Odd.яa", "Zebra.same", -1},
		LocaleCase{"Odd.яa", "Zebra.zLast", -1},
		LocaleCase{"Odd.яa", "a b", 1},
		LocaleCase{"Odd.яa", "a_b", 1},
		LocaleCase{"Odd.яa", "a-b", 1},
		LocaleCase{"Odd.яa", "ab", 1},
		LocaleCase{"Odd.яa", "aB", 1},
		LocaleCase{"Odd.яa", "Ab", 1},
		LocaleCase{"Odd.яa", "\$x", 1},
		LocaleCase{"Odd.яa", "_x", 1},
		LocaleCase{"Odd.яa", "x", -1},
		LocaleCase{"Odd.αa", "x-", -1},
		LocaleCase{"Odd.αa", "x.", -1},
		LocaleCase{"Odd.αa", "x0", -1},
		LocaleCase{"Odd.αa", "xé", -1},
		LocaleCase{"Odd.αa", "xÉ", -1},
		LocaleCase{"Odd.αa", "\"1\"", 1},
		LocaleCase{"Odd.αa", "1", 1},
		LocaleCase{"Odd.αa", "10", 1},
		LocaleCase{"Odd.αa", "2", 1},
		LocaleCase{"Odd.αa", "-2n", 1},
		LocaleCase{"Odd.αa", "10n", 1},
		LocaleCase{"Odd.αa", "1n", 1},
		LocaleCase{"Odd.αa", "null", 1},
		LocaleCase{"Odd.αa", "undefined", -1},
		LocaleCase{"Odd.αa", "true", -1},
		LocaleCase{"Odd.αa", "Enum.a", 1},
		LocaleCase{"Odd.αa", "Enum.B", 1},
		LocaleCase{"Odd.αa", "Enum.b", 1},
		LocaleCase{"Odd.αa", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"Odd.αa", "\"a\"", 1},
		LocaleCase{"Odd.αa", "\"B\"", 1},
		LocaleCase{"Odd.αa", "\"c\"", 1},
		LocaleCase{"Odd.αa", "Apple.aLast", 1},
		LocaleCase{"Odd.αa", "Apple.same", 1},
		LocaleCase{"Odd.αa", "Zebra.same", -1},
		LocaleCase{"Odd.αa", "Zebra.zLast", -1},
		LocaleCase{"Odd.αa", "a b", 1},
		LocaleCase{"Odd.αa", "a_b", 1},
		LocaleCase{"Odd.αa", "a-b", 1},
		LocaleCase{"Odd.αa", "ab", 1},
		LocaleCase{"Odd.αa", "aB", 1},
		LocaleCase{"Odd.αa", "Ab", 1},
		LocaleCase{"Odd.αa", "\$x", 1},
		LocaleCase{"Odd.αa", "_x", 1},
		LocaleCase{"Odd.αa", "x", -1},
		LocaleCase{"x-", "x.", -1},
		LocaleCase{"x-", "x0", -1},
		LocaleCase{"x-", "xé", -1},
		LocaleCase{"x-", "xÉ", -1},
		LocaleCase{"x-", "\"1\"", 1},
		LocaleCase{"x-", "1", 1},
		LocaleCase{"x-", "10", 1},
		LocaleCase{"x-", "2", 1},
		LocaleCase{"x-", "-2n", 1},
		LocaleCase{"x-", "10n", 1},
		LocaleCase{"x-", "1n", 1},
		LocaleCase{"x-", "null", 1},
		LocaleCase{"x-", "undefined", 1},
		LocaleCase{"x-", "true", 1},
		LocaleCase{"x-", "Enum.a", 1},
		LocaleCase{"x-", "Enum.B", 1},
		LocaleCase{"x-", "Enum.b", 1},
		LocaleCase{"x-", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"x-", "\"a\"", 1},
		LocaleCase{"x-", "\"B\"", 1},
		LocaleCase{"x-", "\"c\"", 1},
		LocaleCase{"x-", "Apple.aLast", 1},
		LocaleCase{"x-", "Apple.same", 1},
		LocaleCase{"x-", "Zebra.same", -1},
		LocaleCase{"x-", "Zebra.zLast", -1},
		LocaleCase{"x-", "a b", 1},
		LocaleCase{"x-", "a_b", 1},
		LocaleCase{"x-", "a-b", 1},
		LocaleCase{"x-", "ab", 1},
		LocaleCase{"x-", "aB", 1},
		LocaleCase{"x-", "Ab", 1},
		LocaleCase{"x-", "\$x", 1},
		LocaleCase{"x-", "_x", 1},
		LocaleCase{"x-", "x", 1},
		LocaleCase{"x.", "x0", -1},
		LocaleCase{"x.", "xé", -1},
		LocaleCase{"x.", "xÉ", -1},
		LocaleCase{"x.", "\"1\"", 1},
		LocaleCase{"x.", "1", 1},
		LocaleCase{"x.", "10", 1},
		LocaleCase{"x.", "2", 1},
		LocaleCase{"x.", "-2n", 1},
		LocaleCase{"x.", "10n", 1},
		LocaleCase{"x.", "1n", 1},
		LocaleCase{"x.", "null", 1},
		LocaleCase{"x.", "undefined", 1},
		LocaleCase{"x.", "true", 1},
		LocaleCase{"x.", "Enum.a", 1},
		LocaleCase{"x.", "Enum.B", 1},
		LocaleCase{"x.", "Enum.b", 1},
		LocaleCase{"x.", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"x.", "\"a\"", 1},
		LocaleCase{"x.", "\"B\"", 1},
		LocaleCase{"x.", "\"c\"", 1},
		LocaleCase{"x.", "Apple.aLast", 1},
		LocaleCase{"x.", "Apple.same", 1},
		LocaleCase{"x.", "Zebra.same", -1},
		LocaleCase{"x.", "Zebra.zLast", -1},
		LocaleCase{"x.", "a b", 1},
		LocaleCase{"x.", "a_b", 1},
		LocaleCase{"x.", "a-b", 1},
		LocaleCase{"x.", "ab", 1},
		LocaleCase{"x.", "aB", 1},
		LocaleCase{"x.", "Ab", 1},
		LocaleCase{"x.", "\$x", 1},
		LocaleCase{"x.", "_x", 1},
		LocaleCase{"x.", "x", 1},
		LocaleCase{"x0", "xé", -1},
		LocaleCase{"x0", "xÉ", -1},
		LocaleCase{"x0", "\"1\"", 1},
		LocaleCase{"x0", "1", 1},
		LocaleCase{"x0", "10", 1},
		LocaleCase{"x0", "2", 1},
		LocaleCase{"x0", "-2n", 1},
		LocaleCase{"x0", "10n", 1},
		LocaleCase{"x0", "1n", 1},
		LocaleCase{"x0", "null", 1},
		LocaleCase{"x0", "undefined", 1},
		LocaleCase{"x0", "true", 1},
		LocaleCase{"x0", "Enum.a", 1},
		LocaleCase{"x0", "Enum.B", 1},
		LocaleCase{"x0", "Enum.b", 1},
		LocaleCase{"x0", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"x0", "\"a\"", 1},
		LocaleCase{"x0", "\"B\"", 1},
		LocaleCase{"x0", "\"c\"", 1},
		LocaleCase{"x0", "Apple.aLast", 1},
		LocaleCase{"x0", "Apple.same", 1},
		LocaleCase{"x0", "Zebra.same", -1},
		LocaleCase{"x0", "Zebra.zLast", -1},
		LocaleCase{"x0", "a b", 1},
		LocaleCase{"x0", "a_b", 1},
		LocaleCase{"x0", "a-b", 1},
		LocaleCase{"x0", "ab", 1},
		LocaleCase{"x0", "aB", 1},
		LocaleCase{"x0", "Ab", 1},
		LocaleCase{"x0", "\$x", 1},
		LocaleCase{"x0", "_x", 1},
		LocaleCase{"x0", "x", 1},
		LocaleCase{"xé", "xÉ", -1},
		LocaleCase{"xé", "\"1\"", 1},
		LocaleCase{"xé", "1", 1},
		LocaleCase{"xé", "10", 1},
		LocaleCase{"xé", "2", 1},
		LocaleCase{"xé", "-2n", 1},
		LocaleCase{"xé", "10n", 1},
		LocaleCase{"xé", "1n", 1},
		LocaleCase{"xé", "null", 1},
		LocaleCase{"xé", "undefined", 1},
		LocaleCase{"xé", "true", 1},
		LocaleCase{"xé", "Enum.a", 1},
		LocaleCase{"xé", "Enum.B", 1},
		LocaleCase{"xé", "Enum.b", 1},
		LocaleCase{"xé", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"xé", "\"a\"", 1},
		LocaleCase{"xé", "\"B\"", 1},
		LocaleCase{"xé", "\"c\"", 1},
		LocaleCase{"xé", "Apple.aLast", 1},
		LocaleCase{"xé", "Apple.same", 1},
		LocaleCase{"xé", "Zebra.same", -1},
		LocaleCase{"xé", "Zebra.zLast", -1},
		LocaleCase{"xé", "a b", 1},
		LocaleCase{"xé", "a_b", 1},
		LocaleCase{"xé", "a-b", 1},
		LocaleCase{"xé", "ab", 1},
		LocaleCase{"xé", "aB", 1},
		LocaleCase{"xé", "Ab", 1},
		LocaleCase{"xé", "\$x", 1},
		LocaleCase{"xé", "_x", 1},
		LocaleCase{"xé", "x", 1},
		LocaleCase{"xÉ", "\"1\"", 1},
		LocaleCase{"xÉ", "1", 1},
		LocaleCase{"xÉ", "10", 1},
		LocaleCase{"xÉ", "2", 1},
		LocaleCase{"xÉ", "-2n", 1},
		LocaleCase{"xÉ", "10n", 1},
		LocaleCase{"xÉ", "1n", 1},
		LocaleCase{"xÉ", "null", 1},
		LocaleCase{"xÉ", "undefined", 1},
		LocaleCase{"xÉ", "true", 1},
		LocaleCase{"xÉ", "Enum.a", 1},
		LocaleCase{"xÉ", "Enum.B", 1},
		LocaleCase{"xÉ", "Enum.b", 1},
		LocaleCase{"xÉ", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"xÉ", "\"a\"", 1},
		LocaleCase{"xÉ", "\"B\"", 1},
		LocaleCase{"xÉ", "\"c\"", 1},
		LocaleCase{"xÉ", "Apple.aLast", 1},
		LocaleCase{"xÉ", "Apple.same", 1},
		LocaleCase{"xÉ", "Zebra.same", -1},
		LocaleCase{"xÉ", "Zebra.zLast", -1},
		LocaleCase{"xÉ", "a b", 1},
		LocaleCase{"xÉ", "a_b", 1},
		LocaleCase{"xÉ", "a-b", 1},
		LocaleCase{"xÉ", "ab", 1},
		LocaleCase{"xÉ", "aB", 1},
		LocaleCase{"xÉ", "Ab", 1},
		LocaleCase{"xÉ", "\$x", 1},
		LocaleCase{"xÉ", "_x", 1},
		LocaleCase{"xÉ", "x", 1},
		LocaleCase{"\"1\"", "1", -1},
		LocaleCase{"\"1\"", "10", -1},
		LocaleCase{"\"1\"", "2", -1},
		LocaleCase{"\"1\"", "-2n", 1},
		LocaleCase{"\"1\"", "10n", -1},
		LocaleCase{"\"1\"", "1n", -1},
		LocaleCase{"\"1\"", "null", -1},
		LocaleCase{"\"1\"", "undefined", -1},
		LocaleCase{"\"1\"", "true", -1},
		LocaleCase{"\"1\"", "Enum.a", -1},
		LocaleCase{"\"1\"", "Enum.B", -1},
		LocaleCase{"\"1\"", "Enum.b", -1},
		LocaleCase{"\"1\"", "(typeof Enum)[\"a\"]", -1},
		LocaleCase{"\"1\"", "\"a\"", -1},
		LocaleCase{"\"1\"", "\"B\"", -1},
		LocaleCase{"\"1\"", "\"c\"", -1},
		LocaleCase{"\"1\"", "Apple.aLast", -1},
		LocaleCase{"\"1\"", "Apple.same", -1},
		LocaleCase{"\"1\"", "Zebra.same", -1},
		LocaleCase{"\"1\"", "Zebra.zLast", -1},
		LocaleCase{"\"1\"", "a b", -1},
		LocaleCase{"\"1\"", "a_b", -1},
		LocaleCase{"\"1\"", "a-b", -1},
		LocaleCase{"\"1\"", "ab", -1},
		LocaleCase{"\"1\"", "aB", -1},
		LocaleCase{"\"1\"", "Ab", -1},
		LocaleCase{"\"1\"", "\$x", -1},
		LocaleCase{"\"1\"", "_x", 1},
		LocaleCase{"\"1\"", "x", -1},
		LocaleCase{"1", "10", -1},
		LocaleCase{"1", "2", -1},
		LocaleCase{"1", "-2n", 1},
		LocaleCase{"1", "10n", -1},
		LocaleCase{"1", "1n", -1},
		LocaleCase{"1", "null", -1},
		LocaleCase{"1", "undefined", -1},
		LocaleCase{"1", "true", -1},
		LocaleCase{"1", "Enum.a", -1},
		LocaleCase{"1", "Enum.B", -1},
		LocaleCase{"1", "Enum.b", -1},
		LocaleCase{"1", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"1", "\"a\"", 1},
		LocaleCase{"1", "\"B\"", 1},
		LocaleCase{"1", "\"c\"", 1},
		LocaleCase{"1", "Apple.aLast", -1},
		LocaleCase{"1", "Apple.same", -1},
		LocaleCase{"1", "Zebra.same", -1},
		LocaleCase{"1", "Zebra.zLast", -1},
		LocaleCase{"1", "a b", -1},
		LocaleCase{"1", "a_b", -1},
		LocaleCase{"1", "a-b", -1},
		LocaleCase{"1", "ab", -1},
		LocaleCase{"1", "aB", -1},
		LocaleCase{"1", "Ab", -1},
		LocaleCase{"1", "\$x", 1},
		LocaleCase{"1", "_x", 1},
		LocaleCase{"1", "x", -1},
		LocaleCase{"10", "2", -1},
		LocaleCase{"10", "-2n", 1},
		LocaleCase{"10", "10n", -1},
		LocaleCase{"10", "1n", -1},
		LocaleCase{"10", "null", -1},
		LocaleCase{"10", "undefined", -1},
		LocaleCase{"10", "true", -1},
		LocaleCase{"10", "Enum.a", -1},
		LocaleCase{"10", "Enum.B", -1},
		LocaleCase{"10", "Enum.b", -1},
		LocaleCase{"10", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"10", "\"a\"", 1},
		LocaleCase{"10", "\"B\"", 1},
		LocaleCase{"10", "\"c\"", 1},
		LocaleCase{"10", "Apple.aLast", -1},
		LocaleCase{"10", "Apple.same", -1},
		LocaleCase{"10", "Zebra.same", -1},
		LocaleCase{"10", "Zebra.zLast", -1},
		LocaleCase{"10", "a b", -1},
		LocaleCase{"10", "a_b", -1},
		LocaleCase{"10", "a-b", -1},
		LocaleCase{"10", "ab", -1},
		LocaleCase{"10", "aB", -1},
		LocaleCase{"10", "Ab", -1},
		LocaleCase{"10", "\$x", 1},
		LocaleCase{"10", "_x", 1},
		LocaleCase{"10", "x", -1},
		LocaleCase{"2", "-2n", 1},
		LocaleCase{"2", "10n", 1},
		LocaleCase{"2", "1n", 1},
		LocaleCase{"2", "null", -1},
		LocaleCase{"2", "undefined", -1},
		LocaleCase{"2", "true", -1},
		LocaleCase{"2", "Enum.a", -1},
		LocaleCase{"2", "Enum.B", -1},
		LocaleCase{"2", "Enum.b", -1},
		LocaleCase{"2", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"2", "\"a\"", 1},
		LocaleCase{"2", "\"B\"", 1},
		LocaleCase{"2", "\"c\"", 1},
		LocaleCase{"2", "Apple.aLast", -1},
		LocaleCase{"2", "Apple.same", -1},
		LocaleCase{"2", "Zebra.same", -1},
		LocaleCase{"2", "Zebra.zLast", -1},
		LocaleCase{"2", "a b", -1},
		LocaleCase{"2", "a_b", -1},
		LocaleCase{"2", "a-b", -1},
		LocaleCase{"2", "ab", -1},
		LocaleCase{"2", "aB", -1},
		LocaleCase{"2", "Ab", -1},
		LocaleCase{"2", "\$x", 1},
		LocaleCase{"2", "_x", 1},
		LocaleCase{"2", "x", -1},
		LocaleCase{"-2n", "10n", -1},
		LocaleCase{"-2n", "1n", -1},
		LocaleCase{"-2n", "null", -1},
		LocaleCase{"-2n", "undefined", -1},
		LocaleCase{"-2n", "true", -1},
		LocaleCase{"-2n", "Enum.a", -1},
		LocaleCase{"-2n", "Enum.B", -1},
		LocaleCase{"-2n", "Enum.b", -1},
		LocaleCase{"-2n", "(typeof Enum)[\"a\"]", -1},
		LocaleCase{"-2n", "\"a\"", -1},
		LocaleCase{"-2n", "\"B\"", -1},
		LocaleCase{"-2n", "\"c\"", -1},
		LocaleCase{"-2n", "Apple.aLast", -1},
		LocaleCase{"-2n", "Apple.same", -1},
		LocaleCase{"-2n", "Zebra.same", -1},
		LocaleCase{"-2n", "Zebra.zLast", -1},
		LocaleCase{"-2n", "a b", -1},
		LocaleCase{"-2n", "a_b", -1},
		LocaleCase{"-2n", "a-b", -1},
		LocaleCase{"-2n", "ab", -1},
		LocaleCase{"-2n", "aB", -1},
		LocaleCase{"-2n", "Ab", -1},
		LocaleCase{"-2n", "\$x", -1},
		LocaleCase{"-2n", "_x", 1},
		LocaleCase{"-2n", "x", -1},
		LocaleCase{"10n", "1n", -1},
		LocaleCase{"10n", "null", -1},
		LocaleCase{"10n", "undefined", -1},
		LocaleCase{"10n", "true", -1},
		LocaleCase{"10n", "Enum.a", -1},
		LocaleCase{"10n", "Enum.B", -1},
		LocaleCase{"10n", "Enum.b", -1},
		LocaleCase{"10n", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"10n", "\"a\"", 1},
		LocaleCase{"10n", "\"B\"", 1},
		LocaleCase{"10n", "\"c\"", 1},
		LocaleCase{"10n", "Apple.aLast", -1},
		LocaleCase{"10n", "Apple.same", -1},
		LocaleCase{"10n", "Zebra.same", -1},
		LocaleCase{"10n", "Zebra.zLast", -1},
		LocaleCase{"10n", "a b", -1},
		LocaleCase{"10n", "a_b", -1},
		LocaleCase{"10n", "a-b", -1},
		LocaleCase{"10n", "ab", -1},
		LocaleCase{"10n", "aB", -1},
		LocaleCase{"10n", "Ab", -1},
		LocaleCase{"10n", "\$x", 1},
		LocaleCase{"10n", "_x", 1},
		LocaleCase{"10n", "x", -1},
		LocaleCase{"1n", "null", -1},
		LocaleCase{"1n", "undefined", -1},
		LocaleCase{"1n", "true", -1},
		LocaleCase{"1n", "Enum.a", -1},
		LocaleCase{"1n", "Enum.B", -1},
		LocaleCase{"1n", "Enum.b", -1},
		LocaleCase{"1n", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"1n", "\"a\"", 1},
		LocaleCase{"1n", "\"B\"", 1},
		LocaleCase{"1n", "\"c\"", 1},
		LocaleCase{"1n", "Apple.aLast", -1},
		LocaleCase{"1n", "Apple.same", -1},
		LocaleCase{"1n", "Zebra.same", -1},
		LocaleCase{"1n", "Zebra.zLast", -1},
		LocaleCase{"1n", "a b", -1},
		LocaleCase{"1n", "a_b", -1},
		LocaleCase{"1n", "a-b", -1},
		LocaleCase{"1n", "ab", -1},
		LocaleCase{"1n", "aB", -1},
		LocaleCase{"1n", "Ab", -1},
		LocaleCase{"1n", "\$x", 1},
		LocaleCase{"1n", "_x", 1},
		LocaleCase{"1n", "x", -1},
		LocaleCase{"null", "undefined", -1},
		LocaleCase{"null", "true", -1},
		LocaleCase{"null", "Enum.a", 1},
		LocaleCase{"null", "Enum.B", 1},
		LocaleCase{"null", "Enum.b", 1},
		LocaleCase{"null", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"null", "\"a\"", 1},
		LocaleCase{"null", "\"B\"", 1},
		LocaleCase{"null", "\"c\"", 1},
		LocaleCase{"null", "Apple.aLast", 1},
		LocaleCase{"null", "Apple.same", 1},
		LocaleCase{"null", "Zebra.same", -1},
		LocaleCase{"null", "Zebra.zLast", -1},
		LocaleCase{"null", "a b", 1},
		LocaleCase{"null", "a_b", 1},
		LocaleCase{"null", "a-b", 1},
		LocaleCase{"null", "ab", 1},
		LocaleCase{"null", "aB", 1},
		LocaleCase{"null", "Ab", 1},
		LocaleCase{"null", "\$x", 1},
		LocaleCase{"null", "_x", 1},
		LocaleCase{"null", "x", -1},
		LocaleCase{"undefined", "true", 1},
		LocaleCase{"undefined", "Enum.a", 1},
		LocaleCase{"undefined", "Enum.B", 1},
		LocaleCase{"undefined", "Enum.b", 1},
		LocaleCase{"undefined", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"undefined", "\"a\"", 1},
		LocaleCase{"undefined", "\"B\"", 1},
		LocaleCase{"undefined", "\"c\"", 1},
		LocaleCase{"undefined", "Apple.aLast", 1},
		LocaleCase{"undefined", "Apple.same", 1},
		LocaleCase{"undefined", "Zebra.same", -1},
		LocaleCase{"undefined", "Zebra.zLast", -1},
		LocaleCase{"undefined", "a b", 1},
		LocaleCase{"undefined", "a_b", 1},
		LocaleCase{"undefined", "a-b", 1},
		LocaleCase{"undefined", "ab", 1},
		LocaleCase{"undefined", "aB", 1},
		LocaleCase{"undefined", "Ab", 1},
		LocaleCase{"undefined", "\$x", 1},
		LocaleCase{"undefined", "_x", 1},
		LocaleCase{"undefined", "x", -1},
		LocaleCase{"true", "Enum.a", 1},
		LocaleCase{"true", "Enum.B", 1},
		LocaleCase{"true", "Enum.b", 1},
		LocaleCase{"true", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"true", "\"a\"", 1},
		LocaleCase{"true", "\"B\"", 1},
		LocaleCase{"true", "\"c\"", 1},
		LocaleCase{"true", "Apple.aLast", 1},
		LocaleCase{"true", "Apple.same", 1},
		LocaleCase{"true", "Zebra.same", -1},
		LocaleCase{"true", "Zebra.zLast", -1},
		LocaleCase{"true", "a b", 1},
		LocaleCase{"true", "a_b", 1},
		LocaleCase{"true", "a-b", 1},
		LocaleCase{"true", "ab", 1},
		LocaleCase{"true", "aB", 1},
		LocaleCase{"true", "Ab", 1},
		LocaleCase{"true", "\$x", 1},
		LocaleCase{"true", "_x", 1},
		LocaleCase{"true", "x", -1},
		LocaleCase{"Enum.a", "Enum.B", -1},
		LocaleCase{"Enum.a", "Enum.b", -1},
		LocaleCase{"Enum.a", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"Enum.a", "\"a\"", 1},
		LocaleCase{"Enum.a", "\"B\"", 1},
		LocaleCase{"Enum.a", "\"c\"", 1},
		LocaleCase{"Enum.a", "Apple.aLast", 1},
		LocaleCase{"Enum.a", "Apple.same", 1},
		LocaleCase{"Enum.a", "Zebra.same", -1},
		LocaleCase{"Enum.a", "Zebra.zLast", -1},
		LocaleCase{"Enum.a", "a b", 1},
		LocaleCase{"Enum.a", "a_b", 1},
		LocaleCase{"Enum.a", "a-b", 1},
		LocaleCase{"Enum.a", "ab", 1},
		LocaleCase{"Enum.a", "aB", 1},
		LocaleCase{"Enum.a", "Ab", 1},
		LocaleCase{"Enum.a", "\$x", 1},
		LocaleCase{"Enum.a", "_x", 1},
		LocaleCase{"Enum.a", "x", -1},
		LocaleCase{"Enum.B", "Enum.b", 1},
		LocaleCase{"Enum.B", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"Enum.B", "\"a\"", 1},
		LocaleCase{"Enum.B", "\"B\"", 1},
		LocaleCase{"Enum.B", "\"c\"", 1},
		LocaleCase{"Enum.B", "Apple.aLast", 1},
		LocaleCase{"Enum.B", "Apple.same", 1},
		LocaleCase{"Enum.B", "Zebra.same", -1},
		LocaleCase{"Enum.B", "Zebra.zLast", -1},
		LocaleCase{"Enum.B", "a b", 1},
		LocaleCase{"Enum.B", "a_b", 1},
		LocaleCase{"Enum.B", "a-b", 1},
		LocaleCase{"Enum.B", "ab", 1},
		LocaleCase{"Enum.B", "aB", 1},
		LocaleCase{"Enum.B", "Ab", 1},
		LocaleCase{"Enum.B", "\$x", 1},
		LocaleCase{"Enum.B", "_x", 1},
		LocaleCase{"Enum.B", "x", -1},
		LocaleCase{"Enum.b", "(typeof Enum)[\"a\"]", 1},
		LocaleCase{"Enum.b", "\"a\"", 1},
		LocaleCase{"Enum.b", "\"B\"", 1},
		LocaleCase{"Enum.b", "\"c\"", 1},
		LocaleCase{"Enum.b", "Apple.aLast", 1},
		LocaleCase{"Enum.b", "Apple.same", 1},
		LocaleCase{"Enum.b", "Zebra.same", -1},
		LocaleCase{"Enum.b", "Zebra.zLast", -1},
		LocaleCase{"Enum.b", "a b", 1},
		LocaleCase{"Enum.b", "a_b", 1},
		LocaleCase{"Enum.b", "a-b", 1},
		LocaleCase{"Enum.b", "ab", 1},
		LocaleCase{"Enum.b", "aB", 1},
		LocaleCase{"Enum.b", "Ab", 1},
		LocaleCase{"Enum.b", "\$x", 1},
		LocaleCase{"Enum.b", "_x", 1},
		LocaleCase{"Enum.b", "x", -1},
		LocaleCase{"(typeof Enum)[\"a\"]", "\"a\"", 1},
		LocaleCase{"(typeof Enum)[\"a\"]", "\"B\"", 1},
		LocaleCase{"(typeof Enum)[\"a\"]", "\"c\"", 1},
		LocaleCase{"(typeof Enum)[\"a\"]", "Apple.aLast", -1},
		LocaleCase{"(typeof Enum)[\"a\"]", "Apple.same", -1},
		LocaleCase{"(typeof Enum)[\"a\"]", "Zebra.same", -1},
		LocaleCase{"(typeof Enum)[\"a\"]", "Zebra.zLast", -1},
		LocaleCase{"(typeof Enum)[\"a\"]", "a b", -1},
		LocaleCase{"(typeof Enum)[\"a\"]", "a_b", -1},
		LocaleCase{"(typeof Enum)[\"a\"]", "a-b", -1},
		LocaleCase{"(typeof Enum)[\"a\"]", "ab", -1},
		LocaleCase{"(typeof Enum)[\"a\"]", "aB", -1},
		LocaleCase{"(typeof Enum)[\"a\"]", "Ab", -1},
		LocaleCase{"(typeof Enum)[\"a\"]", "\$x", -1},
		LocaleCase{"(typeof Enum)[\"a\"]", "_x", 1},
		LocaleCase{"(typeof Enum)[\"a\"]", "x", -1},
		LocaleCase{"\"a\"", "\"B\"", -1},
		LocaleCase{"\"a\"", "\"c\"", -1},
		LocaleCase{"\"a\"", "Apple.aLast", -1},
		LocaleCase{"\"a\"", "Apple.same", -1},
		LocaleCase{"\"a\"", "Zebra.same", -1},
		LocaleCase{"\"a\"", "Zebra.zLast", -1},
		LocaleCase{"\"a\"", "a b", -1},
		LocaleCase{"\"a\"", "a_b", -1},
		LocaleCase{"\"a\"", "a-b", -1},
		LocaleCase{"\"a\"", "ab", -1},
		LocaleCase{"\"a\"", "aB", -1},
		LocaleCase{"\"a\"", "Ab", -1},
		LocaleCase{"\"a\"", "\$x", -1},
		LocaleCase{"\"a\"", "_x", 1},
		LocaleCase{"\"a\"", "x", -1},
		LocaleCase{"\"B\"", "\"c\"", -1},
		LocaleCase{"\"B\"", "Apple.aLast", -1},
		LocaleCase{"\"B\"", "Apple.same", -1},
		LocaleCase{"\"B\"", "Zebra.same", -1},
		LocaleCase{"\"B\"", "Zebra.zLast", -1},
		LocaleCase{"\"B\"", "a b", -1},
		LocaleCase{"\"B\"", "a_b", -1},
		LocaleCase{"\"B\"", "a-b", -1},
		LocaleCase{"\"B\"", "ab", -1},
		LocaleCase{"\"B\"", "aB", -1},
		LocaleCase{"\"B\"", "Ab", -1},
		LocaleCase{"\"B\"", "\$x", -1},
		LocaleCase{"\"B\"", "_x", 1},
		LocaleCase{"\"B\"", "x", -1},
		LocaleCase{"\"c\"", "Apple.aLast", -1},
		LocaleCase{"\"c\"", "Apple.same", -1},
		LocaleCase{"\"c\"", "Zebra.same", -1},
		LocaleCase{"\"c\"", "Zebra.zLast", -1},
		LocaleCase{"\"c\"", "a b", -1},
		LocaleCase{"\"c\"", "a_b", -1},
		LocaleCase{"\"c\"", "a-b", -1},
		LocaleCase{"\"c\"", "ab", -1},
		LocaleCase{"\"c\"", "aB", -1},
		LocaleCase{"\"c\"", "Ab", -1},
		LocaleCase{"\"c\"", "\$x", -1},
		LocaleCase{"\"c\"", "_x", 1},
		LocaleCase{"\"c\"", "x", -1},
		LocaleCase{"Apple.aLast", "Apple.same", -1},
		LocaleCase{"Apple.aLast", "Zebra.same", -1},
		LocaleCase{"Apple.aLast", "Zebra.zLast", -1},
		LocaleCase{"Apple.aLast", "a b", 1},
		LocaleCase{"Apple.aLast", "a_b", 1},
		LocaleCase{"Apple.aLast", "a-b", 1},
		LocaleCase{"Apple.aLast", "ab", 1},
		LocaleCase{"Apple.aLast", "aB", 1},
		LocaleCase{"Apple.aLast", "Ab", 1},
		LocaleCase{"Apple.aLast", "\$x", 1},
		LocaleCase{"Apple.aLast", "_x", 1},
		LocaleCase{"Apple.aLast", "x", -1},
		LocaleCase{"Apple.same", "Zebra.same", -1},
		LocaleCase{"Apple.same", "Zebra.zLast", -1},
		LocaleCase{"Apple.same", "a b", 1},
		LocaleCase{"Apple.same", "a_b", 1},
		LocaleCase{"Apple.same", "a-b", 1},
		LocaleCase{"Apple.same", "ab", 1},
		LocaleCase{"Apple.same", "aB", 1},
		LocaleCase{"Apple.same", "Ab", 1},
		LocaleCase{"Apple.same", "\$x", 1},
		LocaleCase{"Apple.same", "_x", 1},
		LocaleCase{"Apple.same", "x", -1},
		LocaleCase{"Zebra.same", "Zebra.zLast", -1},
		LocaleCase{"Zebra.same", "a b", 1},
		LocaleCase{"Zebra.same", "a_b", 1},
		LocaleCase{"Zebra.same", "a-b", 1},
		LocaleCase{"Zebra.same", "ab", 1},
		LocaleCase{"Zebra.same", "aB", 1},
		LocaleCase{"Zebra.same", "Ab", 1},
		LocaleCase{"Zebra.same", "\$x", 1},
		LocaleCase{"Zebra.same", "_x", 1},
		LocaleCase{"Zebra.same", "x", 1},
		LocaleCase{"Zebra.zLast", "a b", 1},
		LocaleCase{"Zebra.zLast", "a_b", 1},
		LocaleCase{"Zebra.zLast", "a-b", 1},
		LocaleCase{"Zebra.zLast", "ab", 1},
		LocaleCase{"Zebra.zLast", "aB", 1},
		LocaleCase{"Zebra.zLast", "Ab", 1},
		LocaleCase{"Zebra.zLast", "\$x", 1},
		LocaleCase{"Zebra.zLast", "_x", 1},
		LocaleCase{"Zebra.zLast", "x", 1},
		LocaleCase{"a b", "a_b", -1},
		LocaleCase{"a b", "a-b", -1},
		LocaleCase{"a b", "ab", -1},
		LocaleCase{"a b", "aB", -1},
		LocaleCase{"a b", "Ab", -1},
		LocaleCase{"a b", "\$x", 1},
		LocaleCase{"a b", "_x", 1},
		LocaleCase{"a b", "x", -1},
		LocaleCase{"a_b", "a-b", -1},
		LocaleCase{"a_b", "ab", -1},
		LocaleCase{"a_b", "aB", -1},
		LocaleCase{"a_b", "Ab", -1},
		LocaleCase{"a_b", "\$x", 1},
		LocaleCase{"a_b", "_x", 1},
		LocaleCase{"a_b", "x", -1},
		LocaleCase{"a-b", "ab", -1},
		LocaleCase{"a-b", "aB", -1},
		LocaleCase{"a-b", "Ab", -1},
		LocaleCase{"a-b", "\$x", 1},
		LocaleCase{"a-b", "_x", 1},
		LocaleCase{"a-b", "x", -1},
		LocaleCase{"ab", "aB", -1},
		LocaleCase{"ab", "Ab", -1},
		LocaleCase{"ab", "\$x", 1},
		LocaleCase{"ab", "_x", 1},
		LocaleCase{"ab", "x", -1},
		LocaleCase{"aB", "Ab", -1},
		LocaleCase{"aB", "\$x", 1},
		LocaleCase{"aB", "_x", 1},
		LocaleCase{"aB", "x", -1},
		LocaleCase{"Ab", "\$x", 1},
		LocaleCase{"Ab", "_x", 1},
		LocaleCase{"Ab", "x", -1},
		LocaleCase{"\$x", "_x", 1},
		LocaleCase{"\$x", "x", -1},
		LocaleCase{"_x", "x", -1},
	]
	for k in cases {
		assert js_locale_compare(k.a, k.b) == k.want, '${k.a} vs ${k.b}'
	}
}

struct LocaleCase {
	a    string
	b    string
	want int
}

// ---- package_pattern_test.v ----

// The cases come from tools/gen_package_pattern_cases.mjs: for the `package` of a type specifier,
// the pattern typescript-eslint 8.62.0 made of it (8.72 compares the names by path components
// instead, path_is_in_package; the cases stay as a test of the Annex B regular expressions), and what `new RegExp(pattern).test(text)` gives in V8
// for each text (`1` or `0`, or `?` where V8 answers two ways), or that V8 rejects the pattern.
fn test_package_patterns_match_like_v8() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'package_pattern_cases.json')) or {
		panic(err)
	}
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	texts := data['texts'] or { panic('no texts') }.as_array().map(it.str())
	mut checked := 0
	mut rejected := 0
	mut wrong := []string{}
	mut unsupported := []string{}
	for item in data['cases'] or { panic('no cases') }.as_array() {
		entry := item.as_map()
		package_name := entry['package'] or { panic('no package') }.str()
		pattern := entry['pattern'] or { panic('no pattern') }.str()
		assert v8_package_pattern(package_name) == pattern
		if 'error' in entry {
			rejected++
			if _ := jsregexp.regexp_compile_annex_b(utf16_units(pattern)) {
				wrong << '/${pattern}/ should be invalid'
			}
			continue
		}
		matches := entry['matches'] or { panic('no matches') }.str()
		assert matches.len == texts.len
		prog := jsregexp.regexp_compile_annex_b(utf16_units(pattern)) or {
			if err.msg().contains('a backreference that ignores case') {
				unsupported << pattern
			} else {
				wrong << '/${pattern}/ does not compile: ${err.msg()}'
			}
			continue
		}
		for i, text in texts {
			if matches[i] == `?` {
				continue
			}
			got := jsregexp.regexp_test_annex_b(prog, utf16_units(text)) or {
				wrong << '/${pattern}/ on ${json2.encode(text)}: ${err.msg()}'
				continue
			}
			if got != (matches[i] == `1`) {
				wrong << '/${pattern}/ on ${json2.encode(text)}: got ${got}'
			}
			checked++
		}
	}
	if wrong.len > 0 {
		assert false, '${wrong.len} differences; the first ones:\n' + wrong#[..12].join('\n')
	}
	assert checked >= 40000
	assert rejected >= 100
	// The one thing of these patterns veslint does not match: a backreference inside a group with
	// the `i` flag (the matcher compares it as the `u` mode does). It says so.
	assert unsupported == ['(?i:(a)\\1)|(?i:(a)\\1)']
}

// v8_package_pattern is the pattern typescript-eslint 8.62.0 made of a package name: the name, or
// the one of its @types package.
fn v8_package_pattern(pkg string) string {
	return '${pkg}|${types_package_name(pkg)}'
}

// A name of a package is a pattern without anchors, as typescript-eslint has it; with a scope, the
// name of its @types package counts too.
fn test_v8_package_pattern_of_a_name() {
	assert v8_package_pattern('fake-pkg') == 'fake-pkg|fake-pkg'
	assert v8_package_pattern('@scope/name') == '@scope/name|scope__name'
	assert v8_package_pattern('@/name') == '@/name|@/name'
	prog := jsregexp.regexp_compile_annex_b(utf16_units(v8_package_pattern('@scope/name'))) or { panic(err) }
	assert jsregexp.regexp_test_annex_b(prog, utf16_units('@types/scope__name/index.d.ts')) or { panic(err) }
	assert jsregexp.regexp_test_annex_b(prog, utf16_units('@scope/name/lib/a.d.ts')) or { panic(err) }
	assert !(jsregexp.regexp_test_annex_b(prog, utf16_units('@scope/other/lib/a.d.ts')) or { panic(err) })
}

// ---- requires_quoting_test.v ----

// Expected values computed with requiresQuoting of @typescript-eslint/type-utils 8.62.0 on
// TypeScript 6.0.3 (the result is the same with the ES2022 target and with the default one).
struct RequiresQuotingCase {
	name     string
	expected bool
}

const requires_quoting_cases = [
	RequiresQuotingCase{'', true},
	RequiresQuotingCase{'a', false},
	RequiresQuotingCase{'A1', false},
	RequiresQuotingCase{'_', false},
	RequiresQuotingCase{'$', false},
	RequiresQuotingCase{'__proto__', false},
	RequiresQuotingCase{'1x', true},
	RequiresQuotingCase{'a-b', true},
	RequiresQuotingCase{'a b', true},
	RequiresQuotingCase{"it's", true},
	RequiresQuotingCase{'é', false},
	RequiresQuotingCase{'日本', false},
	RequiresQuotingCase{'ªb', false},
	// U+00B7 continues an identifier but does not start one.
	RequiresQuotingCase{'·x', true},
	RequiresQuotingCase{'x·y', false},
	// So does the zero-width joiner.
	RequiresQuotingCase{'a‍b', false},
	RequiresQuotingCase{'‍a', true},
	// Outside the BMP: two surrogates for charCodeAt, never identifier characters, even when the
	// code point is a letter.
	RequiresQuotingCase{'🎉', true},
	RequiresQuotingCase{'a🎉', true},
	RequiresQuotingCase{'𝒜', true},
	// A combining mark.
	RequiresQuotingCase{'à', false},
	RequiresQuotingCase{'̀a', true},
	RequiresQuotingCase{'ǅ', false},
	RequiresQuotingCase{'ⅳ', false},
	RequiresQuotingCase{'x‿', false},
	RequiresQuotingCase{'℘', false},
	RequiresQuotingCase{'a b', true},
	RequiresQuotingCase{'π', false},
	RequiresQuotingCase{'new\nline', true},
	RequiresQuotingCase{'x￿', true},
	RequiresQuotingCase{'Ａ', false},
	RequiresQuotingCase{'a.b', true},
	RequiresQuotingCase{'a1_$', false},
	RequiresQuotingCase{'$1', false},
	RequiresQuotingCase{'9', true},
	RequiresQuotingCase{'ℂ', false},
	RequiresQuotingCase{'ᢅ', false},
]

fn test_requires_quoting() {
	for case in requires_quoting_cases {
		assert requires_quoting(case.name) == case.expected, 'requires_quoting(${case.name.bytes().hex()})'
	}
}

// The code units above ASCII that TypeScript 6.0.3's isIdentifierStart and isIdentifierPart accept
// with the ESNext target: 48983 and 50691.
fn test_identifier_tables() {
	mut starts := 0
	mut parts := 0
	for code in u32(128) .. u32(0x10000) {
		if ts_is_identifier_start(code) {
			starts++
		}
		if ts_is_identifier_part(code) {
			parts++
		}
	}
	assert starts == 48983
	assert parts == 50691
	// ASCII: letters, `$` and `_` start an identifier; digits only continue it.
	for code in u32(0) .. u32(128) {
		letter := (code >= `a` && code <= `z`) || (code >= `A` && code <= `Z`) || code == `$`
			|| code == `_`
		assert ts_is_identifier_start(code) == letter
		assert ts_is_identifier_part(code) == (letter || (code >= `0` && code <= `9`))
	}
}

// ---- scope_oracle_test.v ----

// The scope tree of each program of tests/scope/ must be what ESLint's scope manager holds for
// it: tests/scope_cases.json comes from tools/gen_scope_cases.mjs, which runs the real
// @typescript-eslint/parser and scope-manager inside ESLint's Linter with the languageOptions,
// linterOptions and compilerOptions of the case, and writes every scope, variable and reference.
// The test gives the same options to the code a lint run uses (inline_config, file_scope_setup
// and scope_tree) and compares everything: the scopes (type, range, upper and variable scope,
// isStrict and the references left to the upper scope), their variables in order (definitions,
// identifiers and references in resolution order), their references in order (identifier,
// read/write/init flags, type/value kind, variable resolved to; of an identifier, its name and
// where it starts: ESTree's range includes a type annotation), the unresolved references, the
// implicit global variables and, through a digest, every variable of the global scope with what
// ESLint sets on it.

const scope_oracle_types = {
	ScopeKind.global:                   'global'
	ScopeKind.esmodule:                 'module'
	ScopeKind.function:                 'function'
	ScopeKind.function_expression_name: 'function-expression-name'
	ScopeKind.block:                    'block'
	ScopeKind.catch_clause:             'catch'
	ScopeKind.for_statement:            'for'
	ScopeKind.switch_statement:         'switch'
	ScopeKind.with_statement:           'with'
	ScopeKind.class_scope:              'class'
	ScopeKind.class_field_initializer:  'class-field-initializer'
	ScopeKind.class_static_block:       'class-static-block'
	ScopeKind.ts_enum:                  'tsEnum'
	ScopeKind.ts_module:                'tsModule'
	ScopeKind.type_scope:               'type'
	ScopeKind.function_type:            'functionType'
	ScopeKind.conditional_type:         'conditionalType'
	ScopeKind.mapped_type:              'mappedType'
}

const scope_oracle_definitions = {
	DefKind.catch_clause:    'CatchClause'
	DefKind.class_name:      'ClassName'
	DefKind.function_name:   'FunctionName'
	DefKind.import_binding:  'ImportBinding'
	DefKind.parameter:       'Parameter'
	DefKind.ts_enum_member:  'TSEnumMemberName'
	DefKind.ts_enum_name:    'TSEnumName'
	DefKind.ts_module_name:  'TSModuleName'
	DefKind.type_definition: 'Type'
	DefKind.variable:        'Variable'
}

fn scope_oracle_field(entry map[string]json2.Any, name string) json2.Any {
	return entry[name] or { panic('no ${name}') }
}

fn scope_oracle_int(entry map[string]json2.Any, name string) int {
	return scope_oracle_field(entry, name).int()
}

// scope_oracle_tree builds the scope tree of a case the way a lint run does.
fn scope_oracle_tree(item map[string]json2.Any) (&ScopeTree, string) {
	file := scope_oracle_field(item, 'file').str()
	src := scope_oracle_field(item, 'source').str()
	parser := if file.ends_with('.tsx') {
		treesitter.new_tsx_parser() or { panic(err) }
	} else {
		treesitter.new_parser() or { panic(err) }
	}
	tree := parser.parse(src) or { panic(err) }
	root := root_node(tree)
	// The compiler options as TypeScript holds them (what tsgo answers): null without a program,
	// where typescript-eslint's parser has no lib of its own and analyze() takes `esnext`.
	compiler := scope_oracle_field(item, 'compilerOptions')
	project := if compiler is map[string]json2.Any {
		new_scope_project(json2.decode[CompilerOptions](compiler.json_str()) or { panic(err) })
	} else {
		ScopeProject{
			libs: ['esnext']
		}
	}
	linter := scope_oracle_field(item, 'linterOptions').as_map()
	config := LintConfig{
		language:         parse_language_options(scope_oracle_field(item, 'languageOptions'))
		no_inline_config: (linter['noInlineConfig'] or { json2.Any(false) }).bool()
	}
	mut c := &Checker{
		src:           src
		tokens:        token_ends(root)
		node_index:    treesitter.new_node_index(root)
		scope_project: project
	}
	inline := c.inline_config(root, config)
	c.scope_setup = c.file_scope_setup(config, inline)
	return c.scope_tree(root), src
}

// scope_oracle_compare lists the differences between the scope tree of a case and ESLint's.
fn scope_oracle_compare(item map[string]json2.Any) []string {
	t, src := scope_oracle_tree(item)
	mut out := []string{}
	expected := scope_oracle_field(item, 'scopes').as_array()
	if expected.len != t.scopes.len {
		got_types := t.scopes.map(scope_oracle_types[it.kind])
		want_types := expected.map(scope_oracle_field(it.as_map(), 'type').str())
		out << 'scopes: ${got_types}, ESLint has ${want_types}'
		return out
	}
	// The id of a reference is its place in the references of the scopes, in order.
	mut ids := map[int]int{}
	mut positions := map[int]int{} // the place of a variable in its scope
	for scope in t.scopes {
		for r in scope.references {
			ids[r] = ids.len
		}
		for i, v in scope.variables {
			positions[v] = i
		}
	}
	line := fn [src] (offset int) int {
		return src[..offset].count('\n') + 1
	}
	for s, scope in t.scopes {
		want := expected[s].as_map()
		want_type := scope_oracle_field(want, 'type').str()
		want_start := scope_oracle_int(want, 'start')
		label := 'scope ${s} (${want_type} ${scope_oracle_field(want, 'block').str()} at line ${line(want_start)})'
		got_head := '${scope_oracle_types[scope.kind]} [${scope.start},${scope.end}) upper ${scope.upper} variableScope ${scope.variable_scope} strict ${t.is_strict(s)} through ${scope.through.map(ids[it])}'
		want_through := scope_oracle_field(want, 'through').as_array().map(it.int())
		want_head := '${want_type} [${want_start},${scope_oracle_int(want, 'end')}) upper ${scope_oracle_int(want, 'upper')} variableScope ${scope_oracle_int(want, 'variableScope')} strict ${scope_oracle_field(want, 'isStrict').bool()} through ${want_through}'
		if got_head != want_head {
			out << '${label}: ${got_head}, ESLint has ${want_head}'
		}
		// Variables: of the global scope, only the ones ESLint declared or something references.
		mut got_variables := []string{}
		for i, v in scope.variables {
			variable := t.variables[v]
			if s == 0 && variable.lib && variable.references.len == 0 {
				continue
			}
			mut defs := []string{}
			for def in variable.defs {
				defs << '${scope_oracle_definitions[def.kind]}@${node_start(def.name)}'
			}
			identifiers := variable.identifiers.map(node_start(it))
			resolved := variable.references.map(ids[it])
			got_variables << '${variable.name}#${i} defs[${defs.join(' ')}] identifiers${identifiers} references${resolved}'
		}
		mut want_variables := []string{}
		for entry in scope_oracle_field(want, 'variables').as_array() {
			variable := entry.as_map()
			mut defs := []string{}
			for def in scope_oracle_field(variable, 'defs').as_array() {
				d := def.as_map()
				kind := scope_oracle_field(d, 'type').str()
				defs << '${kind}@${scope_oracle_int(d, 'start')}'
			}
			name := scope_oracle_field(variable, 'name').str()
			identifiers := scope_oracle_field(variable, 'identifiers').as_array().map(it.int())
			resolved := scope_oracle_field(variable, 'references').as_array().map(it.int())
			want_variables << '${name}#${scope_oracle_int(variable, 'index')} defs[${defs.join(' ')}] identifiers${identifiers} references${resolved}'
		}
		scope_oracle_diff(mut out, '${label} variables', got_variables, want_variables)
		mut got_references := []string{}
		for r in scope.references {
			ref := t.references[r]
			flags := (if ref.read { 'R' } else { '' }) + (if ref.write { 'W' } else { '' }) +
				(if ref.init { 'i' } else { '' })
			kind := (if ref.type_ref { 'T' } else { '' }) + (if ref.value_ref { 'V' } else { '' })
			resolved := if ref.resolved >= 0 {
				'${t.variables[ref.resolved].scope}.${positions[ref.resolved]}'
			} else {
				'-'
			}
			start := node_start(ref.identifier)
			got_references << '#${ids[r]} ${ref.name}@${start} line ${line(start)} ${flags} ${kind} -> ${resolved}'
		}
		mut want_references := []string{}
		for entry in scope_oracle_field(want, 'references').as_array() {
			ref := entry.as_map()
			target := scope_oracle_field(ref, 'resolved').as_array().map(it.int().str())
			resolved := if target.len == 0 { '-' } else { target.join('.') }
			name := scope_oracle_field(ref, 'name').str()
			start := scope_oracle_int(ref, 'start')
			flags := scope_oracle_field(ref, 'flags').str()
			kind := scope_oracle_field(ref, 'kind').str()
			want_references << '#${scope_oracle_int(ref, 'id')} ${name}@${start} line ${line(start)} ${flags} ${kind} -> ${resolved}'
		}
		scope_oracle_diff(mut out, '${label} references', got_references, want_references)
	}
	global := scope_oracle_field(item, 'global').as_map()
	through := t.through.map(ids[it])
	want_through := scope_oracle_field(global, 'through').as_array().map(it.int())
	if through != want_through {
		out << 'through: ${through}, ESLint has ${want_through}'
	}
	implicit := t.implicit.map('${it.name}${it.defs.map('[${node_start(it.name)}, ${node_start(it.node)}]')}')
	want_implicit := scope_oracle_field(global, 'implicit').as_array().map(fn (entry json2.Any) string {
		variable := entry.as_map()
		defs := scope_oracle_field(variable, 'defs').as_array().map(fn (def json2.Any) string {
			pair := def.as_array()
			return '[${pair[0].int()}, ${pair[1].int()}]'
		})
		return '${scope_oracle_field(variable, 'name').str()}${defs}'
	})
	if implicit != want_implicit {
		out << 'implicit: ${implicit}, ESLint has ${want_implicit}'
	}
	lines := scope_oracle_global_lines(t)
	digest := sha1.hexhash(lines.join('\n'))
	if digest != scope_oracle_field(global, 'digest').str() {
		count := scope_oracle_int(global, 'count')
		out << 'the ${lines.len} variables of the global scope differ from the ${count} of ESLint (compare `node tools/gen_scope_cases.mjs --globals <case>` with the output of VESLINT_SCOPE_GLOBALS=<case>)'
	}
	return out
}

// scope_oracle_global_lines are the lines of the digest: one per variable of the global scope.
fn scope_oracle_global_lines(t &ScopeTree) []string {
	mut lines := []string{}
	for v in t.scopes[0].variables {
		variable := t.variables[v]
		lines << [
			variable.name,
			if variable.lib { 'lib' } else { 'variable' },
			(if variable.is_type_variable() { 'T' } else { '' }) +
				(if variable.is_value_variable() { 'V' } else { '' }),
			if variable.writeable { 'writable' } else { '' },
			if variable.eslint_explicit_global { 'explicit' } else { '' },
			variable.eslint_implicit_global_setting,
			if variable.eslint_used { 'used' } else { '' },
			variable.references.len.str(),
		].join('\t')
	}
	return lines
}

// scope_oracle_diff reports the first entries two lists differ in.
fn scope_oracle_diff(mut out []string, label string, got []string, want []string) {
	if got == want {
		return
	}
	mut shown := 0
	for i in 0 .. if got.len > want.len { got.len } else { want.len } {
		g := got[i] or { '(nothing)' }
		w := want[i] or { '(nothing)' }
		if g != w {
			out << '${label}[${i}]: ${g}, ESLint has ${w}'
			shown++
			if shown == 4 {
				out << '${label}: … (${got.len} entries, ESLint has ${want.len})'
				break
			}
		}
	}
}

fn test_scopes_match_eslint() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'scope_cases.json')) or { panic(err) }
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	cases := scope_oracle_field(data, 'cases').as_array()
	assert cases.len >= 45
	only := os.getenv('VESLINT_SCOPE_CASE')
	listed := os.getenv('VESLINT_SCOPE_GLOBALS')
	mut failures := []string{}
	mut references := 0
	for entry in cases {
		item := entry.as_map()
		name := scope_oracle_field(item, 'name').str()
		if only != '' && name != only {
			continue
		}
		if listed == name {
			t, _ := scope_oracle_tree(item)
			println(scope_oracle_global_lines(t).join('\n'))
		}
		for scope in scope_oracle_field(item, 'scopes').as_array() {
			references += scope_oracle_field(scope.as_map(), 'references').as_array().len
		}
		for difference in scope_oracle_compare(item) {
			failures << '${name}: ${difference}'
		}
	}
	if failures.len > 0 {
		eprintln(failures.join('\n'))
	}
	assert failures.len == 0, '${failures.len} differences with ESLint'
	assert only != '' || references >= 1500
}

// ---- scope_test.v ----

fn scope_test_tree(src string) (&ScopeTree, C.vt_node) {
	parser := treesitter.new_parser() or { panic(err) }
	tree := parser.parse(src) or { panic(err) }
	root := root_node(tree)
	return build_scope_tree(root, src, token_ends(root)), root
}

// scope_test_node is the identifier-like node of `src` that starts at the i-th occurrence of
// `name` (0-based).
fn scope_test_node(root C.vt_node, src string, name string, occurrence int) C.vt_node {
	mut seen := 0
	for n in nodes_of_kinds(root, ['identifier', 'type_identifier', 'property_identifier',
		'shorthand_property_identifier', 'shorthand_property_identifier_pattern', 'undefined',
		'private_property_identifier'], []string{}) {
		if src[node_start(n)..treesitter.node_end(n)] == name {
			if seen == occurrence {
				return n
			}
			seen++
		}
	}
	panic('no ${name} #${occurrence}')
}

fn scope_test_refs(t &ScopeTree, name string) []ScopeReference {
	return t.references.filter(it.name == name)
}

// getScope: the program is the global scope, any other top-level node the module scope; functions,
// blocks, classes and their parts follow ESLint (a method's name is outside its function).
fn test_get_scope() {
	src := 'const a = 1;\nfunction f(p = a) { { let b = p; } }\nclass C { m(q) { return q; } [a] = () => a; }\n@dec export class D {}\n'
	t, root := scope_test_tree(src)
	assert t.get_scope(root) == 0
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'a', 0))].kind == .esmodule
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'f', 0))].kind == .function
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'p', 0))].kind == .function
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'b', 0))].kind == .block
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'm', 0))].kind == .class_scope
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'q', 0))].kind == .function
	// `[a]` is a computed key (class scope); the arrow of its value is a function.
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'a', 2))].kind == .class_scope
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'a', 3))].kind == .function
	// The decorator before `export` belongs to the class.
	assert t.scopes[t.get_scope(scope_test_node(root, src, 'dec', 0))].kind == .class_scope
}

// find_variable from the global scope with a location reaches the same scope as getScope.
fn test_find_variable_and_own_variable() {
	src := 'const x = 1;\nfunction f() { const x = 2; return [x, String, undefined, Nope]; }\n'
	t, root := scope_test_tree(src)
	inner := scope_test_node(root, src, 'x', 2)
	v := t.find_variable(0, 'x', node_start(inner))
	assert v >= 0 && t.scopes[t.variables[v].scope].kind == .function
	outer := t.find_variable(0, 'x', -1)
	assert outer < 0 // no descent: the global scope does not declare x
	assert t.variables[t.find_variable(1, 'x', -1)].scope == 1
	// ECMAScript globals are variables without definitions; undeclared names have none.
	s := t.find_variable(0, 'String', node_start(scope_test_node(root, src, 'String', 0)))
	assert s >= 0 && t.variables[s].scope == 0 && t.variables[s].defs.len == 0
	assert t.find_variable(0, 'undefined', -1) >= 0
	assert t.find_variable(0, 'Nope', -1) == -1
	f := t.get_scope(inner)
	assert t.own_variable(f, 'x') >= 0
	assert t.own_variable(f, 'f') == -1
	assert t.own_variable(1, 'f') >= 0
}

// Definitions: kind, parent kind, declarator id and init (none for `let x;`, `declare` and for-of
// heads, which still are variable definitions).
fn test_definitions() {
	src := 'let a;\ndeclare const b: number;\nconst { c } = obj;\nfor (const d of []) {}\nfunction g(...e: number[]) {}\nimport f from "m";\ntry {} catch (h) {}\n'
	t, root := scope_test_tree(src)
	def := fn [t, root, src] (name string) ScopeDefinition {
		v := t.declared_variable(scope_test_node(root, src, name, 0))
		assert v >= 0
		return t.variables[v].defs[0]
	}
	a := def('a')
	assert a.kind == .variable && a.parent_kind == 'let' && a.init == none
	b := def('b')
	assert b.kind == .variable && b.parent_kind == 'const' && b.init == none
	c := def('c')
	assert c.parent_kind == 'const' && c.init != none
	if id := c.decl_id {
		assert treesitter.node_kind(id) == 'object_pattern'
	} else {
		assert false
	}
	d := def('d')
	assert d.kind == .variable && d.parent_kind == 'const' && d.init == none
	e := def('e')
	assert e.kind == .parameter && e.rest
	assert def('f').kind == .import_binding
	assert def('h').kind == .catch_clause
}

// Read and write flags as typescript-eslint's Referencer sets them (checked against its scope
// manager): one `as`/`<T>`/`!` around an assignment or update target is unwrapped.
fn test_reference_flags() {
	src := 'let x = 1;\nx!++;\n(x as any) = 2;\n(x satisfies number);\nx += 1;\n[x] = [1];\nfor (x of []) {}\nx++;\n({ a: x } = {});\nx! = 4;\ntypeof x;\nexport { x };\n'
	t, _ := scope_test_tree(src)
	flags := scope_test_refs(t, 'x').map('${if it.read { 'R' } else { '' }}${if it.write {
		'W'
	} else {
		''
	}}${if it.init { 'i' } else { '' }}')
	assert flags == ['Wi', 'RW', 'W', 'R', 'RW', 'W', 'W', 'RW', 'W', 'W', 'R', 'R']
	refs := scope_test_refs(t, 'x')
	assert refs.last().type_ref && refs.last().value_ref // export { x } is a type and value reference
	assert refs.all(it.resolved >= 0)
	assert refs.filter(it.is_read_only()).len == 3
}

// A reference in the parameters does not see a variable declared only in the body; a type
// reference does not resolve to a value-only variable.
fn test_resolution() {
	src := 'const v = 1;\nfunction f(p = v) { const v = 2; }\ntype T = typeof v;\nlet w: w;\n'
	t, _ := scope_test_tree(src)
	v_refs := scope_test_refs(t, 'v').filter(!it.write)
	assert v_refs.len == 2
	for r in v_refs {
		assert t.variables[r.resolved].scope == 1
	}
	w_type := scope_test_refs(t, 'w').filter(it.type_ref)
	assert w_type.len == 1 && w_type[0].resolved == -1
}

// Scopes created for classes, fields, static blocks, enums, namespaces and types.
fn test_scope_kinds() {
	src := 'class K<T> { f = 1; static { } }\nenum E { A }\nnamespace N {}\ntype M<U> = { [P in keyof U]: U[P] };\ntype C<V> = V extends Array<infer I> ? I : never;\nswitch (1) {}\nfor (let i = 0; ; ) {}\n'
	t, _ := scope_test_tree(src)
	kinds := t.scopes.map(it.kind)
	assert kinds == [.global, .esmodule, .class_scope, .class_field_initializer, .class_static_block,
		.ts_enum, .ts_module, .type_scope, .mapped_type, .type_scope, .conditional_type,
		.switch_statement, .for_statement, .block]
}

// The implicit variables of the libs: the libs and the ones they include in typescript-eslint's
// order, where the first one that has a name decides whether it is a type, a value or both.
fn test_scope_libs() {
	assert scope_lib_order(['ES2015', 'dom', 'es2015', 'no-such-lib'])[..5] == [
		'es2015',
		'dom',
		'es5',
		'es2015.core',
		'es2015.collection',
	]
	es5 := new_scope_libs(['es5'])
	symbol := es5.variables[es5.set['Symbol']]
	assert symbol.lib && symbol.lib_type && !symbol.lib_value
	number := es5.variables[es5.set['Number']]
	assert number.lib && number.lib_type && number.lib_value
	assert 'Map' !in es5.set && 'parseInt' !in es5.set && 'Partial' in es5.set
	assert es5.variables.last().name == 'const' && !es5.variables.last().lib_value
	full := new_scope_libs(['ES2022.Full'])
	assert 'NodeListOf' in full.set && 'BigInt' in full.set && 'Float16Array' !in full.set
	assert 'Float16Array' in new_scope_libs(['esnext.full']).set
	assert new_scope_libs([]string{}).variables.map(it.name) == ['const']
	assert new_scope_libs(['no-such-lib']).variables.len == 1
	// Every lib typescript-eslint's getLib takes from a target exists, and so does every lib
	// another one includes.
	for name in ['es6', 'es2016.full', 'es2025.full', 'esnext.full', 'lib'] {
		assert name in scope_lib_variables, name
	}
	for name, included in scope_lib_references {
		assert name in scope_lib_variables, name
		for lib in included {
			assert lib in scope_lib_variables, lib
		}
	}
}

// The globals ESLint declares: those of the ecmaVersion, of CommonJS and of the configuration,
// with the values of the comments, in the order of the keys of ESLint's object.
fn test_declared_globals() {
	language := parse_language_options(json2.decode[json2.Any]('{"ecmaVersion": 5, "sourceType": "commonjs", "globals": {"b": true, "a": "off", "7": "readonly", "JSON": "off", "exports": false}}') or {
		panic(err)
	})
	assert language.ecma_version == 5 && language.source_type == 'commonjs'
	assert language.globals.keys() == ['b', 'a', '7', 'JSON', 'exports']
	globals := declared_globals(language, {
		'a':   'writable'
		'NaN': 'off'
		'c':   'readonly'
		'3':   'readonly'
	})
	declared_names := globals.map(it.name)
	// Integer names first; then the globals of ES5 in ESLint's order (without NaN, off in a
	// comment, and JSON, off in the configuration), those of CommonJS and the others as added.
	assert declared_names[..3] == ['3', '7', 'Array']
	assert 'NaN' !in declared_names && 'JSON' !in declared_names && 'Map' !in declared_names
	assert declared_names[declared_names.len - 7..] == ['exports', 'global', 'module', 'require',
		'b', 'a', 'c']
	by_name := fn [globals] (name string) ScopeGlobal {
		return globals.filter(it.name == name)[0]
	}
	assert by_name('exports') == ScopeGlobal{'exports', false, 'readonly', false}
	assert by_name('b') == ScopeGlobal{'b', true, 'writable', false}
	assert by_name('a') == ScopeGlobal{'a', true, 'off', true}
	assert by_name('c') == ScopeGlobal{'c', false, '', true}
	assert by_name('3') == ScopeGlobal{'3', false, '', true}
	// Without options: the globals of the latest version.
	assert declared_globals(LanguageOptions{}, map[string]string{}).map(it.name) == scope_es_globals
}

// The options of typescript-eslint's parser, and how it chooses the names a JSX element references.
fn test_parser_options() {
	options := fn (text string) LanguageOptions {
		return parse_language_options(json2.decode[json2.Any](text) or { panic(err) })
	}
	project := ScopeProject{
		libs:                 ['es2022', 'dom']
		jsx_factory:          ' preact .h'
		jsx_fragment_factory: 'Fragment'
	}
	pragma, fragment := scope_jsx_names(project, options('{}'))
	assert pragma == 'preact' && fragment == 'Fragment'
	default_pragma, no_fragment := scope_jsx_names(ScopeProject{}, options('{}'))
	assert default_pragma == 'React' && no_fragment == ''
	null_pragma, own_fragment := scope_jsx_names(project, options('{"parserOptions": {"jsxPragma": null, "jsxFragmentName": "Frag"}}'))
	assert null_pragma == '' && own_fragment == 'Frag'
	own_pragma, null_fragment := scope_jsx_names(project, options('{"parserOptions": {"jsxPragma": "h", "jsxFragmentName": null}}'))
	assert own_pragma == 'h' && null_fragment == ''
	assert scope_libs_of(project, options('{}')) == ['es2022', 'dom']
	assert scope_libs_of(project, options('{"parserOptions": {"lib": ["ES5"]}}')) == ['ES5']
	assert scope_libs_of(project, options('{"parserOptions": {"lib": []}}')).len == 0
	assert scope_libs_of(project, options('{"parserOptions": {"lib": null}}')) == [
		'es2022',
		'dom',
	]
	libs := new_scope_libs([]string{})
	setup := fn [project, libs, options] (text string) ScopeSetup {
		return new_scope_setup(project, options(text), map[string]string{}, []string{},
			libs)
	}
	assert !setup('{}').script && !setup('{}').global_return
	assert setup('{"sourceType": "script"}').script && setup('{"sourceType": "commonjs"}').script
	assert !setup('{"sourceType": "commonjs", "parserOptions": {"sourceType": "module"}}').script
	assert setup('{"parserOptions": {"sourceType": "script", "ecmaFeatures": {"globalReturn": true}}}').global_return
	assert parse_language_options(json2.Any('not an object')) == LanguageOptions{}
}

// The names of an `/* exported */` comment (parseListConfig).
fn test_exported_names() {
	assert exported_names(' a, \'b\' ,"c", \'d, e\' , ,__proto__, a, \'f"') == ['a', 'b', 'c',
		"'d", "e'", '__proto__', '\'f"']
	assert exported_names('').len == 0
}

// A script has no module scope, and with globalReturn the program is the body of a function; the
// globals ESLint declares take the references nothing resolved, and an `/* exported */` comment
// marks a variable of the global scope.
fn test_scope_setup() {
	src := 'var top = Partial; function f() { return [top, declared, missing]; }'
	parser := treesitter.new_parser() or { panic(err) }
	tree := parser.parse(src) or { panic(err) }
	root := root_node(tree)
	setup := ScopeSetup{
		libs:          new_scope_libs(['es5'])
		declared:      [ScopeGlobal{'declared', true, 'writable', false},
			ScopeGlobal{'Partial', false, '', true}]
		exported:      ['top', 'declared', 'nothing']
		script:        true
		global_return: true
	}
	t := build_scope_tree_with(root, src, token_ends(root), setup)
	assert t.scopes.map(it.kind) == [.global, .function, .function]
	assert t.own_variable(1, 'arguments') >= 0 && t.own_variable(1, 'top') >= 0
	declared := t.variables[t.own_variable(0, 'declared')]
	assert !declared.lib && declared.writeable && declared.eslint_used
		&& declared.eslint_implicit_global_setting == 'writable' && declared.references.len == 1
	// `Partial` is a type of the lib: its value reference only resolves once ESLint declares it.
	partial := t.variables[t.own_variable(0, 'Partial')]
	assert partial.lib && partial.eslint_explicit_global && partial.references.len == 1
		&& partial.eslint_implicit_global_setting == ''
	assert t.through.map(t.references[it].name) == ['missing']
	script := build_scope_tree_with(root, src, token_ends(root), ScopeSetup{
		...setup
		global_return: false
	})
	assert script.scopes.map(it.kind) == [.global, .function]
	assert script.variables[script.own_variable(0, 'top')].eslint_used
	assert !script.variables[script.own_variable(0, 'f')].eslint_used
}

fn test_ecma_version_globals() {
	assert normalize_ecma_version(json2.Any('latest')) == scope_latest_ecma_version
	assert normalize_ecma_version(json2.Any(i64(3))) == 3
	assert normalize_ecma_version(json2.Any(i64(5))) == 5
	assert normalize_ecma_version(json2.Any(i64(6))) == 2015
	assert normalize_ecma_version(json2.Any(f64(2019))) == 2019
	assert normalize_ecma_version(json2.Any(f64(2019.5))) == -1
	assert ecma_version_has_global(3, 'parseInt') && ecma_version_has_global(5, 'NaN')
	assert !ecma_version_has_global(5, 'Proxy') && ecma_version_has_global(2015, 'Proxy')
	assert !ecma_version_has_global(2019, 'BigInt') && ecma_version_has_global(2020, 'BigInt')
	assert ecma_version_has_global(scope_latest_ecma_version, 'BigInt')
	// ESLint has no globals for a version it does not know.
	assert !ecma_version_has_global(2014, 'parseInt') && !ecma_version_has_global(2099, 'parseInt')
	assert !ecma_version_has_global(-1, 'parseInt')
	for name in scope_es_globals {
		assert name in scope_es_global_versions, name
	}
}

fn test_normalize_global_value() {
	assert normalize_global_value(json2.Any('off')) or { '' } == 'off'
	assert normalize_global_value(json2.Any(true)) or { '' } == 'writable'
	assert normalize_global_value(json2.Any('writeable')) or { '' } == 'writable'
	assert normalize_global_value(json2.Any(false)) or { '' } == 'readonly'
	assert normalize_global_value(json2.Any(json2.Null{})) or { '' } == 'readonly'
	assert normalize_global_value(json2.Any('readable')) or { '' } == 'readonly'
	assert normalize_global_value(json2.Any('on')) or { '' } == ''
}

fn test_global_entries() {
	entries := global_entries(' b : off , a b:writable,2:x 1 __proto__:off c: ,, a:readonly:z ')
	assert entries.map(it.name) == ['1', '2', 'b', 'a', '__proto__', 'c']
	assert entries.map(it.value) == ['', 'x', 'writable', 'readonly', 'off', '']
	assert entries.map(it.has_value) == [false, true, true, true, true, true]
	assert global_entries('').len == 0
}

// ---- static_value_math_test.v ----

// Values of Math that getStaticValue gives, as the bits of the doubles of Node 26.8.2 (V8 14.6).

fn math_test_abs(x f64) u64 {
	math_object := stv_builtin_global('Math') or { panic('no Math') }
	mut ctx := StvContext{}
	result := stv_call_function(js_any_function('Math.abs'), math_object, true, [
		js_any_number(x),
	], mut ctx) or { panic('Math.abs is not static') }
	assert result.kind == .number_
	return math.f64_bits(result.number)
}

// Math.abs clears the sign of a zero too: `Object.is(Math.abs(-0), 0)`.
fn test_math_abs_of_negative_zero() {
	assert math_test_abs(-0.0) == u64(0)
	assert math_test_abs(0.0) == u64(0)
	assert math_test_abs(-1.5) == u64(0x3ff8000000000000)
	assert math_test_abs(1.5) == u64(0x3ff8000000000000)
	assert math_test_abs(-5e-324) == u64(1)
	assert math_test_abs(math.inf(-1)) == u64(0x7ff0000000000000)
	assert math.is_nan(math.f64_from_bits(math_test_abs(math.nan())))
}

// The value properties of Math: V8 computes LOG10E as log10(E), which is not 1 / LN10.
fn test_math_constants() {
	math_object := stv_builtin_global('Math') or { panic('no Math') }
	expected := {
		'E':       u64(0x4005bf0a8b145769)
		'LN10':    0x40026bb1bbb55516
		'LN2':     0x3fe62e42fefa39ef
		'LOG10E':  0x3fdbcb7b1526e50e
		'LOG2E':   0x3ff71547652b82fe
		'PI':      0x400921fb54442d18
		'SQRT1_2': 0x3fe6a09e667f3bcd
		'SQRT2':   0x3ff6a09e667f3bcd
	}
	for name, bits in expected {
		value := stv_get(math_object, js_any_text(name)) or { panic('Math.${name} is not static') }
		assert value.kind == .number_
		assert math.f64_bits(value.number) == bits, 'Math.${name}'
	}
}

fn math_test_pow(x f64, y f64) u64 {
	math_object := stv_builtin_global('Math') or { panic('no Math') }
	mut ctx := StvContext{}
	result := stv_call_function(js_any_function('Math.pow'), math_object, true, [
		js_any_number(x),
		js_any_number(y),
	], mut ctx) or { panic('Math.pow is not static') }
	assert result.kind == .number_
	// `**` is the same function in V8.
	assert math.f64_bits(stv_power(x, y)) == math.f64_bits(result.number)
	return math.f64_bits(result.number)
}

// An exponent of 2 is `x * x` and one of 0.5 is `sqrt(x + 0)` in V8: for these bases the C
// library's pow gives the neighbouring double.
fn test_power_of_two_and_of_a_half() {
	squares := {
		u64(0x4010e09bfe4571a6): u64(0x4031cd89124b5a04)
		0x4012647c9ccf8d5e:      0x4035248f7a45a50c
		0x40174b5c4375a7fa:      0x4040f5061a7f5d6e
		0x401fb40a81c14c4e:      0x404f68c9519db599
		0x4014c50f646f33bd:      0x403af621862e027a
		0x401d93b60d62f4a8:      0x404b5663ccea10e4
	}
	for base, result in squares {
		assert math_test_pow(math.f64_from_bits(base), 2) == result, '${base:x} ** 2'
	}
	roots := {
		u64(0x3ff841c666906e7c): u64(0x3ff3b35606b42b6a)
		0x401f7741ceb04b06:      0x40067011c22dd87d
		0x4021eb9f6e392f54:      0x4007f2666f0c4dc5
		0x401a20a6ab51a8c6:      0x4004722fe678d015
		0x4022466e17070e74:      0x40082ec67a65699b
		0x4020eb3944fba522:      0x400744a011c7eae0
	}
	for base, result in roots {
		assert math_test_pow(math.f64_from_bits(base), 0.5) == result, '${base:x} ** 0.5'
	}
}

// The cases ECMAScript sets apart, and plain calls of pow.
fn test_power_special_cases() {
	infinity := u64(0x7ff0000000000000)
	assert math_test_pow(-0.0, 0.5) == u64(0)
	assert math_test_pow(0.0, 0.5) == u64(0)
	assert math_test_pow(math.inf(-1), 0.5) == infinity
	assert math_test_pow(math.inf(1), 0.5) == infinity
	assert math.is_nan(math.f64_from_bits(math_test_pow(-4, 0.5)))
	assert math_test_pow(-0.0, 2) == u64(0)
	assert math_test_pow(math.inf(-1), 2) == infinity
	assert math_test_pow(-4, 2) == u64(0x4030000000000000)
	assert math_test_pow(-0.0, -0.5) == infinity
	assert math_test_pow(math.inf(-1), -0.5) == u64(0)
	assert math.is_nan(math.f64_from_bits(math_test_pow(1, math.inf(1))))
	assert math.is_nan(math.f64_from_bits(math_test_pow(-1, math.inf(-1))))
	assert math.is_nan(math.f64_from_bits(math_test_pow(2, math.nan())))
	assert math.is_nan(math.f64_from_bits(math_test_pow(math.nan(), 2)))
	assert math_test_pow(math.nan(), 0) == u64(0x3ff0000000000000)
	assert math_test_pow(2, 8) == u64(0x4070000000000000)
	assert math_test_pow(1.1, 3) == u64(0x3ff54bc6a7ef9db4)
	assert math_test_pow(9.9, 2.5) == u64(0x40734619a9fc9124)
}

// ---- static_value_test.v ----

// The expected values come from tools/gen_static_value_cases.mjs: what getStaticValue of
// @eslint-community/eslint-utils gives, in ESLint, for each expression statement of a source
// (tests/static_value_cases.json). The names below were computed with ESLint 10.6.0:
// getStaticMemberAccessValue / getPropertyName of member expression statements.

const stv_test_names_source = "const key = 'reduce';\nconst index = 0;\nlet counter = 1;\ncounter++;\ndeclare const o: Record<string, number>;\no.reduce;\no['reduce'];\no[`reduce`];\no['re' + 'duce'];\no[key];\no[index];\no[counter];\no[0];\no[1.50];\no[0x10];\no[1n];\no[null];\no[true];\no[undefined];\no[[1, 2]];\no[{}];\no[/a/g];\no[Symbol.iterator];\no[`a\${key}`];\no[unknown];\no.#private;\no?.reduce;\no?.['reduce'];\n"

// Line of the member expression statement, getStaticMemberAccessValue and getPropertyName.
const stv_test_names_expected = [
	'6	"reduce"	"reduce"',
	'7	"reduce"	"reduce"',
	'8	"reduce"	"reduce"',
	'9	"reduce"	"reduce"',
	'10	"reduce"	"reduce"',
	'11	"0"	"0"',
	'12	undefined	null',
	'13	"0"	"0"',
	'14	"1.5"	"1.5"',
	'15	"16"	"16"',
	'16	"1"	"1"',
	'17	"null"	"null"',
	'18	"true"	"true"',
	'19	"undefined"	"undefined"',
	'20	"1,2"	"1,2"',
	'21	"[object Object]"	"[object Object]"',
	'22	"/a/g"	"/a/g"',
	'23	symbol	"Symbol(Symbol.iterator)"',
	'24	"areduce"	"areduce"',
	'25	undefined	null',
	'26	"private"	null',
]

fn stv_test_hex(units []u16) string {
	return units.map(u32(it).hex()).join(',')
}

fn stv_test_number(x f64) string {
	return if x == 0 && math.signbit(x) {
		'-0'
	} else if math.is_inf(x, -1) {
		'-Infinity'
	} else {
		js_number_to_string(x)
	}
}

// stv_test_serialize writes a value like `serialize` of tools/gen_static_value_cases.mjs:
// u(ndefined), null, b(oolean), n(umber), s(tring, as UTF-16 units), i (BigInt), y (a well-known
// symbol), f (a builtin function) or ns (another builtin object) with its name, a[…] (array, h:
// a hole), o{…} (object), r (RegExp), m{…} (Map), e[…] (Set) and t (an iterator, with what is
// left of it).
fn stv_test_serialize(v JsAny, depth int) string {
	if depth > 6 {
		return '…'
	}
	return match v.kind {
		.undefined_ {
			'u'
		}
		.hole_ {
			'h'
		}
		.null_ {
			'null'
		}
		.boolean_ {
			'b:${v.boolean}'
		}
		.number_ {
			'n:' + stv_test_number(v.number)
		}
		.string_ {
			's:' + stv_test_hex(v.units)
		}
		.bigint_ {
			'i:' + v.digits
		}
		.symbol_ {
			if v.registered { 'yr:' + stv_test_hex(v.units) } else { 'y:' + v.name }
		}
		.wrapper_ {
			'w(' + stv_test_serialize(v.elements[0], depth + 1) + ')'
		}
		.function_ {
			'f:' + v.name
		}
		.array_ {
			'a[' + v.elements.map(stv_test_serialize(it, depth + 1)).join(';') + ']'
		}
		.regexp_ {
			'r:' + stv_test_hex(v.regexp.source) + '/' + v.regexp.flags
		}
		.namespace_ {
			'ns:' + v.name
		}
		.object_ {
			mut parts := []string{}
			for i, k in v.keys {
				parts << stv_test_hex(stv_key_units(k)) + '=' + stv_test_serialize(v.values[i], depth + 1)
			}
			prototype := if v.elements.len == 0 {
				''
			} else if v.elements[0].kind == .null_ {
				'^null'
			} else {
				'^' + stv_test_serialize(v.elements[0], depth + 1)
			}
			'o' + prototype + '{' + parts.join(';') + '}'
		}
		.map_ {
			mut parts := []string{}
			for i, k in v.elements {
				parts << stv_test_serialize(k, depth + 1) + '=>' +
					stv_test_serialize(v.values[i], depth + 1)
			}
			'm{' + parts.join(';') + '}'
		}
		.set_ {
			'e[' + v.elements.map(stv_test_serialize(it, depth + 1)).join(';') + ']'
		}
		.iterator_ {
			't:${v.name}[' + v.elements.map(stv_test_serialize(it, depth + 1)).join(';') + ']'
		}
	}
}

fn stv_test_checker(src string) (Checker, C.vt_node) {
	parser := treesitter.new_parser() or { panic(err) }
	tree := parser.parse(src) or { panic(err) }
	root := root_node(tree)
	return Checker{
		src:    src
		tokens: token_ends(root)
	}, root
}

// stv_test_max_steps bounds the sub-expressions one evaluation may visit in these tests. The
// longest one of tests/static_value_cases.json visits a few hundred; constants that refer to each
// other would visit 2^100 if an evaluation went on after the depth limit.
const stv_test_max_steps = 20000

// Every statement of tests/static_value_cases.json has eslint-utils' value, with two exceptions
// that the test pins too: where the value depends on the environment (`ENV`: the time zone, the
// locale or the clock) veslint answers "not static", and it may do so for a statement written
// under one of the limits of static_value.v (the `tags`). A value that differs from eslint-utils',
// or one where eslint-utils has none, is never accepted; a limit without a statement that veslint
// does not evaluate is not one any more. No evaluation may reach stv_test_max_steps: an
// evaluation that does not end fails here instead of hanging. STV_REPORT=<file> writes every
// difference to that file.
fn test_get_static_value() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'static_value_cases.json')) or { panic(err) }
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	source := (data['source'] or { panic('no source') }).str()
	// The statements: the ones of the declarations, then one per line from `firstCase`.
	mut lines := (data['declarationLines'] or { panic('no declarationLines') }).as_array().map(it.int())
	first_case := (data['firstCase'] or { panic('no firstCase') }).int()
	values := (data['values'] or { panic('no values') }).as_array().map(it.str())
	for i in 0 .. values.len - lines.len {
		lines << first_case + i
	}
	// The limit of each statement, written as runs.
	mut tags := []string{cap: values.len}
	for run in (data['tags'] or { panic('no tags') }).as_array() {
		pair := run.as_array()
		for _ in 0 .. pair[0].int() {
			tags << pair[1].str()
		}
	}
	limits := (data['limits'] or { panic('no limits') }).as_map()
	source_lines := source.split('\n')
	mut c, root := stv_test_checker(source)
	statements := nodes_of_kind(root, c'expression_statement')
	assert statements.len == lines.len
	mut wrong := []string{}
	mut not_evaluated := []string{}
	mut limited := map[string][]string{}
	mut evaluated := map[string]int{}
	mut endless := []string{}
	mut most_steps := 0
	for i, stmt in statements {
		line := position_of(stmt).row + 1
		assert line == lines[i]
		expression := first_named_child(stmt) or { panic('no expression') }
		r, exhausted, steps := c.get_static_value_bounded(expression, stv_test_max_steps)
		got := if r.found { stv_test_serialize(r.value, 0) } else { 'NULL' }
		want := values[i]
		text := source_lines[line - 1]
		if exhausted {
			endless << text
		}
		if steps > most_steps {
			most_steps = steps
		}
		if want == 'ENV' {
			if got != 'NULL' {
				wrong << '${text}\t${want}\t${got}'
			}
		} else if got == want {
			if want != 'NULL' {
				evaluated[tags[i]]++
			}
		} else if got != 'NULL' {
			wrong << '${text}\t${want}\t${got}'
		} else if tags[i] == '' {
			not_evaluated << '${text}\t${want}'
		} else {
			limited[tags[i]] << text
		}
	}
	if report := os.getenv_opt('STV_REPORT') {
		mut out := ['ENDLESS ${endless.len} (most steps: ${most_steps})']
		out << endless
		out << 'WRONG ${wrong.len}'
		out << wrong
		out << 'NOT EVALUATED ${not_evaluated.len}'
		out << not_evaluated
		for name, _ in limits {
			out << 'LIMIT ${name}: ${limited[name].len} not evaluated, ${evaluated[name]} evaluated'
			out << limited[name]
		}
		os.write_file(report, out.join('\n') + '\n') or { panic(err) }
		return
	}
	assert endless == []string{}
	assert wrong == []string{}
	assert not_evaluated == []string{}
	for name, _ in limits {
		assert limited[name].len > 0, 'the limit `${name}` has no statement that is not evaluated'
	}
	for name, _ in limited {
		assert name in limits
	}
	assert statements.len >= 10000
}

// The functions veslint takes for callable are the ones of eslint-utils' callAllowed and
// callPassThrough, which the generator builds from eslint-utils' own source.
fn test_call_allowed_is_eslint_utils() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'static_value_cases.json')) or { panic(err) }
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	mut allowed := (data['callAllowed'] or { panic('no callAllowed') }).as_array().map(it.str())
	mut pass_through := (data['callPassThrough'] or { panic('no callPassThrough') }).as_array().map(it.str())
	mut ours := stv_call_allowed.clone()
	mut ours_pass_through := stv_call_pass_through.clone()
	allowed.sort()
	pass_through.sort()
	ours.sort()
	ours_pass_through.sort()
	assert ours == allowed
	assert ours_pass_through == pass_through
}

// Constants that refer to each other end the evaluation at the depth limit, like the stack
// overflow that eslint-utils catches: before, veslint went on with the other operands, which
// never ended for two constants that name each other twice.
fn test_cyclic_constants_end() {
	source := 'const a = [b, b];\nconst b = a + a;\nconst k = [1];\nk[n]();\nconst n = m + m;\nconst m = n + n;\n(a);\n(b);\n([a, 1]);\n(a || 1);\n(1 || a);\n(k);\n'
	mut c, root := stv_test_checker(source)
	mut got := []string{}
	for stmt in nodes_of_kind(root, c'expression_statement') {
		expression := first_named_child(stmt) or { panic('no expression') }
		r, exhausted, steps := c.get_static_value_bounded(expression, stv_test_max_steps)
		assert !exhausted, c.text(stmt)
		assert steps < 1000, c.text(stmt)
		got << if r.found { stv_test_serialize(r.value, 0) } else { 'NULL' }
	}
	// k[n](), then the six statements in parentheses: only `1 || a` does not evaluate `a`.
	assert got == ['NULL', 'NULL', 'NULL', 'NULL', 'NULL', 'n:1', 'NULL']
}

fn test_static_member_name_and_property_name() {
	mut c, root := stv_test_checker(stv_test_names_source)
	mut want := map[int]string{}
	for entry in stv_test_names_expected {
		line, value := entry.split_once('\t') or { panic(entry) }
		want[line.int()] = value
	}
	mut checked := 0
	for stmt in nodes_of_kind(root, c'expression_statement') {
		member := first_named_child(stmt) or { continue }
		if node_kind(member) !in ['member_expression', 'subscript_expression']
			|| is_estree_chain_root(member) {
			continue
		}
		line := position_of(stmt).row + 1
		expected := want[line] or { continue }
		access_text, name_text := expected.split_once('\t') or { panic(expected) }
		access := c.static_member_name(member)
		name := c.property_name(member)
		// A symbol key gives none: it never equals a name.
		got_access := if a := access {
			'"${a}"'
		} else if access_text == 'symbol' {
			'symbol'
		} else {
			'undefined'
		}
		got_name := if n := name { '"${n}"' } else { 'null' }
		assert got_access == access_text, 'line ${line}'
		assert got_name == name_text, 'line ${line}'
		checked++
	}
	assert checked == stv_test_names_expected.len
	assert c.is_static_member_access_of_value(first_named_child(named_children(root)[5]) or {
		panic('no member')
	}, ['filter', 'reduce'])
}

// ---- unicode_normalization_test.v ----

// The cases come from tools/gen_unicode_normalization.mjs: what normalize gives in V8 for chosen
// strings (their four forms as UTF-16 units), and FNV-1a digests of what it gives for every code
// point alone, for the strings made from each composition and for random strings from a pool,
// all of them built here as the generator builds them.

const normalization_forms = ['NFC', 'NFD', 'NFKC', 'NFKD']

fn normalization_cases() map[string]json2.Any {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'unicode_normalization_cases.json')) or {
		panic(err)
	}
	return (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
}

fn normalization_units(value json2.Any) []u16 {
	return value.as_array().map(u16(it.int()))
}

fn test_chosen_strings_match_v8() {
	data := normalization_cases()
	mut checked := 0
	for item in data['cases'] or { panic('no cases') }.as_array() {
		entry := item.as_map()
		units := normalization_units(entry['units'] or { panic('no units') })
		for form in normalization_forms {
			want := normalization_units(entry[form.to_lower()] or { panic('no ${form}') })
			assert js_normalize(units, form) == want, '${form} of ${units}'
		}
		checked++
	}
	assert checked >= 70
}

// normalization_digest is the generator's FNV-1a over the UTF-16 units of the form of each string,
// with a separator after each one.
fn normalization_digest(strings [][]u32, form string) string {
	mut h := u32(0x811c9dc5)
	for points in strings {
		mut units := []u16{}
		for cp in points {
			jsregexp.append_utf16(mut units, cp)
		}
		for unit in js_normalize(units, form) {
			h = (h ^ u32(unit)) * u32(0x01000193)
		}
		h = (h ^ u32(0x10000)) * u32(0x01000193)
	}
	return '${h:08x}'
}

fn normalization_digests(data map[string]json2.Any, form string, kind string) []string {
	forms := (data['digests'] or { panic('no digests') }).as_map()
	return (forms[form] or { panic('no ${form}') }).as_map()[kind] or { panic('no ${kind}') }.as_array().map(it.str())
}

fn normalization_chunks(strings [][]u32, size int) [][][]u32 {
	mut out := [][][]u32{}
	for start := 0; start < strings.len; start += size {
		end := if start + size < strings.len { start + size } else { strings.len }
		out << strings[start..end]
	}
	return out
}

// normalization_block_digest is the digest of the code points of a block alone, normalized or as
// they are.
fn normalization_block_digest(first int, count int, form string) string {
	mut h := u32(0x811c9dc5)
	mut units := []u16{cap: 2}
	for cp in first .. first + count {
		units.clear()
		jsregexp.append_utf16(mut units, u32(cp))
		for unit in if form == '' { units } else { js_normalize(units, form) } {
			h = (h ^ u32(unit)) * u32(0x01000193)
		}
		h = (h ^ u32(0x10000)) * u32(0x01000193)
	}
	return '${h:08x}'
}

// Every code point alone, in blocks: the lone surrogates too. A block that V8 leaves as it is, and
// where no code point has a class or a decomposition or is a Hangul syllable, is one js_normalize
// leaves as it is too, without asking it (most blocks are unassigned); the others are normalized.
fn test_every_code_point_matches_v8() {
	data := normalization_cases()
	block_size := (data['blockSize'] or { panic('no blockSize') }).int()
	mut normalized := 0
	for form in normalization_forms {
		want := normalization_digests(data, form, 'blocks')
		assert want.len * block_size == 0x110000
		for b, digest in want {
			first := u32(b * block_size)
			last := first + u32(block_size) - 1
			in_block := fn [first, last] (cp u32) bool {
				return cp >= first && cp <= last
			}
			mut plain := !(first < hangul_s_base + hangul_s_count && last >= hangul_s_base)
				&& !unicode_nfd_keys.any(in_block(it)) && !unicode_nfkd_keys.any(in_block(it))
			for i := 0; plain && i < unicode_class_ranks.len; i += 2 {
				plain = !in_block(unicode_class_ranks[i])
			}
			if plain && digest == normalization_block_digest(int(first), block_size, '') {
				continue
			}
			assert normalization_block_digest(int(first), block_size, form) == digest, '${form} of U+${first:04X}..U+${last:04X}'
			normalized++
		}
	}
	assert normalized > 0
}

// Each composition with nothing, a mark of the lowest class (U+0334), one of the highest (U+0345)
// and U+0301 between its two code points, and its composite followed by its second code point and
// by U+0334: what blocks a composition and what does not.
fn test_compositions_match_v8() {
	data := normalization_cases()
	chunk_size := (data['chunkSize'] or { panic('no chunkSize') }).int()
	mut strings := [][]u32{}
	for i := 0; i < unicode_compositions.len; i += 3 {
		a, b, c := unicode_compositions[i], unicode_compositions[i + 1], unicode_compositions[i + 2]
		strings << [a, b]
		strings << [a, u32(0x334), b]
		strings << [a, u32(0x345), b]
		strings << [a, u32(0x301), b]
		strings << [c, b]
		strings << [c, u32(0x334)]
	}
	for form in normalization_forms {
		want := normalization_digests(data, form, 'compositions')
		chunks := normalization_chunks(strings, chunk_size)
		assert chunks.len == want.len
		for i, chunk in chunks {
			assert normalization_digest(chunk, form) == want[i], '${form} of the compositions of chunk ${i}'
		}
	}
}

// Random strings from the generator's pool, with its seed and its linear congruential generator.
fn test_random_strings_match_v8() {
	data := normalization_cases()
	chunk_size := (data['chunkSize'] or { panic('no chunkSize') }).int()
	pool := (data['pool'] or { panic('no pool') }).as_array().map(u32(it.int()))
	count := (data['randomCount'] or { panic('no randomCount') }).int()
	max_length := u32((data['maxLength'] or { panic('no maxLength') }).int())
	mut state := u32((data['seed'] or { panic('no seed') }).i64())
	mut strings := [][]u32{cap: count}
	for _ in 0 .. count {
		state = state * 1103515245 + 12345
		length := 1 + (state >> 8) % max_length
		mut points := []u32{cap: int(length)}
		for _ in 0 .. length {
			state = state * 1103515245 + 12345
			points << pool[(state >> 8) % u32(pool.len)]
		}
		strings << points
	}
	for form in normalization_forms {
		want := normalization_digests(data, form, 'random')
		chunks := normalization_chunks(strings, chunk_size)
		assert chunks.len == want.len
		for i, chunk in chunks {
			assert normalization_digest(chunk, form) == want[i], '${form} of the random strings of chunk ${i}'
		}
	}
}

// ---- whatwg_url_test.v ----

// The cases come from tools/gen_whatwg_url_cases.mjs: inputs and bases with the href of Node's
// `new URL(input, base)` (null when it throws), and whether isSafeToAddDotSlashToUrl of
// unicorn/relative-url-style holds (tests/whatwg_url_cases.json).

// wu_resolve is `new URL(input, base).href`.
fn wu_resolve(input string, base string) !string {
	parsed_base := wu_parse(base, false, WuUrl{})!
	return wu_href(wu_parse(input, true, parsed_base)!)
}

fn wu_cases() map[string]json2.Any {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'whatwg_url_cases.json')) or {
		panic(err)
	}
	return (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
}

// wu_test_mentions_domain tells whether a URL may hold a domain that needs UTS #46, which
// rules/whatwg_url.v does not port: a non-ASCII character (maybe percent-encoded) or `xn--`.
fn wu_test_mentions_domain(text string) bool {
	lower := text.to_lower()
	return text.bytes().any(it >= 0x80) || lower.contains('xn--') || lower.contains('%8')
		|| lower.contains('%9') || lower.contains('%a') || lower.contains('%b')
		|| lower.contains('%c') || lower.contains('%d') || lower.contains('%e')
		|| lower.contains('%f')
}

fn test_hrefs_match_node() {
	data := wu_cases()
	mut checked := 0
	mut unsupported := 0
	mut failures := []string{}
	for item in (data['hrefs'] or { panic('no hrefs') }).as_array() {
		values := item.as_array()
		input := values[0].str()
		has_base := values[1] !is json2.Null
		base := if has_base { values[1].str() } else { '' }
		want := if values[2] is json2.Null { '' } else { values[2].str() }
		mut got := ''
		if has_base {
			got = wu_resolve(input, base) or {
				if err.msg() == wu_unsupported {
					assert wu_test_mentions_domain(input) || wu_test_mentions_domain(base), '${input} ${base}'
					unsupported++
					continue
				}
				''
			}
		} else {
			parsed := wu_parse(input, false, WuUrl{}) or {
				if err.msg() == wu_unsupported {
					assert wu_test_mentions_domain(input), input
					unsupported++
					continue
				}
				WuUrl{}
			}
			got = if parsed.scheme == '' { '' } else { wu_href(parsed) }
		}
		checked++
		if got != want {
			failures << '${json2.encode(input)} against ${json2.encode(base)}: ${json2.encode(got)}, Node ${json2.encode(want)}'
		}
	}
	assert failures == []
	assert checked > 15000
	assert unsupported < 500
}

fn test_safety_matches_node() {
	data := wu_cases()
	mut failures := []string{}
	mut unknown := 0
	for item in (data['safe'] or { panic('no safe') }).as_array() {
		values := item.as_array()
		url := values[0].str()
		base := values[1].str()
		want := values[2].bool()
		got := wu_is_safe_to_add_dot_slash(url, base) or {
			// The rule takes such a URL as unsafe.
			assert wu_test_mentions_domain(url) || wu_test_mentions_domain(base), url
			unknown++
			if want {
				failures << '${json2.encode(url)} against ${base}: unknown, Node true'
			}
			continue
		}
		if got != want {
			failures << '${json2.encode(url)} against ${base}: ${got}, Node ${want}'
		}
	}
	assert failures == []
	assert unknown < 50
}

// A lone surrogate (WTF-8 in veslint's strings) is U+FFFD, as for Node's USVString.
fn test_lone_surrogate_is_replaced() {
	// Node: new URL('\ud800/\udfff?\ud83d#\ude00', 'https://example.com/a/b/').href
	assert wu_resolve('\xed\xa0\x80/\xed\xbf\xbf?\xed\xa0\xbd#\xed\xb8\x80', 'https://example.com/a/b/')! == 'https://example.com/a/b/%EF%BF%BD/%EF%BF%BD?%EF%BF%BD#%EF%BF%BD'
	// A pair of surrogates written as two WTF-8 sequences is not produced by veslint (it joins
	// them), but each half alone is replaced.
	assert wu_resolve('a\xed\xa0\xbd', 'file:///a/b.html')! == 'file:///a/a%EF%BF%BD'
}

// order_sensitive_schemas lists the rules whose schema ajv may take for another one's: the same
// stable serialization, another text.
// mentions_order_sensitive_schema finds the names where a search of each finds them: at the start
// and at the end of the text, next to other dashes, and not a name cut short.
fn test_mentions_order_sensitive_schema_is_a_search_of_each_name() {
	mut texts := ['', '-', 'sort-maps', 'xsort-mapsx', '--sort-maps--', 'sort-map', 'sort--maps',
		'/* eslint vue/no-template-shadow: 2 */', 'no-template-shado', 'a - b',
		'restricted-component-names', 'restricted-component-name',
		'perfectionist/sort-heritage-clauses-', 'sort-import-attribute']
	for name in order_sensitive_schemas {
		short := name.all_after_last('/')
		texts << short
		texts << 'x' + short
		texts << short + '-'
		texts << short[..short.len - 1]
		texts << short[1..]
	}
	for text in texts {
		want := order_sensitive_schemas.any(text.contains(it.all_after_last('/')))
		assert mentions_order_sensitive_schema(text) == want, text
	}
}

fn test_order_sensitive_schemas_are_the_colliding_ones() {
	mut names_by_key := map[string][]string{}
	mut texts_by_key := map[string][]string{}
	for name, text in rule_option_schemas {
		value := json2.decode[json2.Any](text) or { panic('${name}: ${err}') }
		key := canonical_json(value)
		names_by_key[key] << name
		if text !in texts_by_key[key] {
			texts_by_key[key] << text
		}
	}
	mut colliding := []string{}
	for key, group in names_by_key {
		if texts_by_key[key].len > 1 {
			colliding << group
		}
	}
	colliding.sort()
	assert colliding == order_sensitive_schemas
}
