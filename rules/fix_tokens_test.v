module rules

import json2
import os
import treesitter { children, node_end, node_kind, node_start, root_node }

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
fn fix_token_node(n C.TSNode, start int, end int, kinds []string) ?C.TSNode {
	if node_start(n) > start || node_end(n) < end {
		return none
	}
	if node_start(n) == start && node_end(n) == end && C.ts_node_is_named(n) && node_kind(n) in kinds {
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
		treesitter.tree_delete(tree)
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
	treesitter.tree_delete(tree)
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
	treesitter.tree_delete(tree)
}
