module treesitter

fn statements(src string) ([]C.TSNode, TokenEnds, &C.TSTree) {
	p := new_parser() or { panic(err) }
	defer {
		p.close()
	}
	tree := p.parse(src) or { panic(err) }
	root := root_node(tree)
	return nodes_of_kind(root, c'expression_statement'), token_ends(root), tree
}

// Without `;`, tree-sitter puts the trailing comment in the statement; TypeScript does not count
// it. The token index gives the real end of the statement and the `pos` of the next one.
fn test_token_ends_skip_trailing_comments() {
	src := 'f() // a\nf() /* b */\nf()'
	stmts, tokens, tree := statements(src)
	defer {
		tree_delete(tree)
	}
	assert stmts.len == 3
	assert node_end(stmts[0]) > 3 // includes `// a`
	assert tokens.last_end(node_end(stmts[0])) == 3
	assert tokens.last_end(node_start(stmts[1])) == 3
	assert tokens.last_end(node_end(stmts[1])) == 12
	assert tokens.last_end(node_start(stmts[2])) == 12
}

// The leading `#!` is trivia for TypeScript: the first statement starts at pos 0.
fn test_token_ends_skip_hash_bang() {
	src := '#!/usr/bin/env node\nf();\n'
	stmts, tokens, tree := statements(src)
	defer {
		tree_delete(tree)
	}
	assert stmts.len == 1
	assert tokens.last_end(node_start(stmts[0])) == 0
	assert tokens.last_end(node_end(stmts[0])) == node_end(stmts[0])
}

// Automatic `;` are zero-width nodes and do not count as tokens.
fn test_token_ends_skip_zero_width_tokens() {
	src := 'a\nb'
	stmts, tokens, tree := statements(src)
	defer {
		tree_delete(tree)
	}
	assert stmts.len == 2
	assert tokens.ends == [1, 3]
	assert tokens.last_end(0) == 0
	assert tokens.last_end(2) == 1
}

// same_nodes tells whether two lists hold the same nodes in the same order.
fn same_nodes(a []C.TSNode, b []C.TSNode) bool {
	if a.len != b.len {
		return false
	}
	for i, node in a {
		if !C.ts_node_eq(node, b[i]) {
			return false
		}
	}
	return true
}

fn test_node_index_gives_what_the_walks_give() {
	src := [
		'class A<T> { m(a: T[] = []) { return (b: T) => [a, b, () => this]; } }',
		'function f(x: number) { function g() { return x ? [1, [2, [3]]] : g; } return g; }',
		'const o = { a: [f(1), f(2)], b: typeof f, c: `\${f(3)} \${[4]}` };',
		'label: for (const [k, v] of Object.entries(o)) { if (k) continue label; }',
	].join('\n')
	p := new_parser() or { panic(err) }
	defer {
		p.close()
	}
	tree := p.parse(src) or { panic(err) }
	defer {
		tree_delete(tree)
	}
	root := root_node(tree)
	index := new_node_index(root)
	kinds := ['program', 'array', 'arrow_function', 'call_expression', 'class_declaration',
		'function_declaration', 'identifier', 'number', 'statement_block', 'template_substitution',
		'type_identifier', 'no_such_kind', '(', 'return']
	for kind in kinds {
		assert same_nodes(index.of_kind(root, kind), nodes_of_kind(root, &char(kind.str))), kind
	}
	// Every pair of wanted kinds with every skipped kind, a kind twice, a kind both wanted and
	// skipped (the node is taken and not entered) and the root skipped.
	for i, first in kinds {
		for second in kinds[i..] {
			wanted := [first, second]
			assert same_nodes(index.of_kinds(root, wanted, []), nodes_of_kinds(root, wanted,
				[])), '${wanted}'
			for skipped in kinds {
				assert same_nodes(index.of_kinds(root, wanted, [skipped]), nodes_of_kinds(root,
					wanted, [skipped])), '${wanted} without ${skipped}'
			}
			assert same_nodes(index.of_kinds(root, wanted, ['array', 'arrow_function']),
				nodes_of_kinds(root, wanted, ['array', 'arrow_function'])), '${wanted} without two kinds'
		}
	}
	assert index.of_kinds(root, ['array', 'identifier'], ['program']).len == 0
	assert index.of_kinds(root, ['program', 'identifier'], ['program']).len == 1
	// A node that is not the root of the index is walked.
	function := nodes_of_kind(root, c'function_declaration')[0]
	assert same_nodes(index.of_kind(function, 'array'), nodes_of_kind(function, c'array'))
	assert index.of_kind(function, 'array').len == 3
	assert same_nodes(index.of_kinds(function, ['array', 'identifier'], ['statement_block']),
		nodes_of_kinds(function, ['array', 'identifier'], ['statement_block']))
	// An index that was never built walks too.
	assert same_nodes(NodeIndex{}.of_kind(root, 'array'), nodes_of_kind(root, c'array'))
}
