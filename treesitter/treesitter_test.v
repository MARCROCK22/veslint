module treesitter

import os

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

// parents_agree walks every node under `root` with a cursor and checks node_parent (the parents the
// index recorded) against tree-sitter's ts_node_parent.
fn parents_agree(root C.TSNode) int {
	mut checked := 0
	mut cursor := C.ts_tree_cursor_new(root)
	defer {
		C.ts_tree_cursor_delete(&cursor)
	}
	for {
		node := C.ts_tree_cursor_current_node(&cursor)
		expected := C.ts_node_parent(node)
		got := node_parent(node) or { C.TSNode{} }
		if C.ts_node_is_null(expected) {
			assert node_parent(node) == none
		} else {
			assert C.ts_node_eq(got, expected)
			assert C.ts_node_start_byte(got) == C.ts_node_start_byte(expected)
			assert C.ts_node_symbol(got) == C.ts_node_symbol(expected)
		}
		checked++
		if C.ts_tree_cursor_goto_first_child(&cursor) {
			continue
		}
		for !C.ts_tree_cursor_goto_next_sibling(&cursor) {
			if !C.ts_tree_cursor_goto_parent(&cursor) {
				return checked
			}
		}
	}
	return checked
}

fn test_node_parent_from_the_index_is_tree_sitters() {
	p := new_parser() or { panic(err) }
	defer {
		p.close()
	}
	// The rules' own fixtures: every construct of the grammar, JSX left to the tsx parser.
	mut files := os.walk_ext(os.join_path(@VMODROOT, 'tests', 'rules'), '.ts')
	files.sort()
	mut checked := 0
	for file in files#[..400] {
		tree := p.parse(os.read_file(file) or { panic(err) }) or { panic(err) }
		root := root_node(tree)
		_ := new_node_index(root)
		checked += parents_agree(root)
		// Forgotten before the tree is freed: tree-sitter's walk from then on.
		parent_cache_clear()
		tree_delete(tree)
	}
	assert checked > 100000
	// A tree with no index (or another tree than the index's) is walked by tree-sitter.
	tree := p.parse('const a = [1, (b) => b];') or { panic(err) }
	defer {
		tree_delete(tree)
	}
	assert parents_agree(root_node(tree)) > 10
}

// One walk gives the node index and the token ends that the two walks give: on the rules' own
// fixtures (comments, `#!`, automatic `;`, ERROR nodes) and on .tsx ones (JSX children).
fn test_node_index_and_token_ends_from_one_walk() {
	p := new_parser() or { panic(err) }
	tsx := new_tsx_parser() or { panic(err) }
	defer {
		p.close()
		tsx.close()
	}
	mut files := os.walk_ext(os.join_path(@VMODROOT, 'tests', 'rules'), '.ts')
	files.sort()
	mut tsx_files := os.walk_ext(os.join_path(@VMODROOT, 'tests', 'rules'), '.tsx')
	tsx_files.sort()
	mut checked := 0
	for file in files#[..300] {
		checked += same_index_and_ends(p, os.read_file(file) or { panic(err) })
	}
	for file in tsx_files#[..100] {
		checked += same_index_and_ends(tsx, os.read_file(file) or { panic(err) })
	}
	checked += same_index_and_ends(tsx, '#!/usr/bin/env node\nconst a = <div a="1" {...b}>\n  x {y} /* c */ <b/>\n</div> // d\n')
	checked += same_index_and_ends(p, 'a\nb /* c */ ) d')
	assert checked > 10000
}

fn same_index_and_ends(p Parser, src string) int {
	tree := p.parse(src) or { panic(err) }
	defer {
		parent_cache_clear()
		tree_delete(tree)
	}
	root := root_node(tree)
	expected := token_ends(root)
	index, ends := new_node_index_and_token_ends(root)
	assert ends.ends == expected.ends, src
	alone := new_node_index(root)
	assert index.count == alone.count
	assert index.buckets.len == alone.buckets.len
	for i, bucket in index.buckets {
		assert same_nodes(bucket.nodes, alone.buckets[i].nodes)
		assert bucket.seq == alone.buckets[i].seq
		assert bucket.last == alone.buckets[i].last
	}
	assert index.named == alone.named
	assert index.anonymous == alone.anonymous
	return expected.ends.len
}
