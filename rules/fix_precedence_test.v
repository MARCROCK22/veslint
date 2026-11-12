module rules

import treesitter { node_field, node_kind, nodes_of_kind, root_node }

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
fn precedence_test_argument(root C.TSNode, src string) C.TSNode {
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
