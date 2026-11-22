module treesitter

import os

fn statements(src string) ([]C.vt_node, TokenEnds, &C.vt_rows) {
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
		rows_free(tree)
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
		rows_free(tree)
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
		rows_free(tree)
	}
	assert stmts.len == 2
	assert tokens.ends == [1, 3]
	assert tokens.last_end(0) == 0
	assert tokens.last_end(2) == 1
}

// same_nodes tells whether two lists hold the same nodes in the same order.
fn same_nodes(a []C.vt_node, b []C.vt_node) bool {
	if a.len != b.len {
		return false
	}
	for i, node in a {
		if !C.vt_node_eq(node, b[i]) {
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
		rows_free(tree)
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

// walk_of_kinds is what of_kinds gives, from a recursive walk of the children.
fn walk_of_kinds(root C.vt_node, kinds []string, skip []string) []C.vt_node {
	mut nodes := []C.vt_node{}
	if C.vt_node_is_named(root) && node_kind(root) in kinds {
		nodes << root
	}
	if node_kind(root) !in skip {
		for child in children(root) {
			nodes << walk_of_kinds(child, kinds, skip)
		}
	}
	return nodes
}

fn same_index_and_ends(p Parser, src string) int {
	tree := p.parse(src) or { panic(err) }
	defer {
		rows_free(tree)
	}
	root := root_node(tree)
	expected := token_ends(root)
	index, ends := new_node_index_and_token_ends(root)
	assert ends.ends == expected.ends, src
	alone := new_node_index(root)
	assert index.count == alone.count
	assert index.buckets.len == alone.buckets.len
	for i, bucket in index.buckets {
		assert bucket.seq == alone.buckets[i].seq
	}
	// The nodes of each kind, also without the subtrees of other kinds, are those of a walk of the
	// tree.
	for kind, _ in index.named {
		assert same_nodes(index.of_kind(root, kind), walk_of_kinds(root, [kind], [])), src
	}
	for skip in [['function_declaration'], ['arrow_function', 'class_body'], ['comment']] {
		kinds := ['identifier', 'call_expression', 'comment', 'property_identifier']
		assert same_nodes(index.of_kinds(root, kinds, skip), walk_of_kinds(root, kinds, skip)), src
	}
	assert index.named == alone.named
	assert index.anonymous == alone.anonymous
	return expected.ends.len
}

// The rows answer what tree-sitter's functions answer (rows_build.h, vt_rows_check), for every node
// of the rules' fixtures, of .tsx ones and of trees with errors, but where tree-sitter has quirks
// no reader of veslint sees (vt_rows_check_quirk).
fn test_rows_are_tree_sitters() {
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
	mut checked := u64(0)
	for file in files {
		checked += same_rows(p, os.read_file(file) or { panic(err) })
	}
	for file in tsx_files {
		checked += same_rows(tsx, os.read_file(file) or { panic(err) })
	}
	checked += same_rows(p, 'a\nb /* c */ ) d; { x; /* y */ z }')
	checked += same_rows(p, 'let = ;\nfunction f( { return 1 }\nclass A { a = 1 b = 2 }\nif (x) y\nz')
	assert checked > 900000
}

fn same_rows(p Parser, src string) u64 {
	tree := p.parse_tree(src) or { panic(err) }
	defer {
		tree_delete(tree)
	}
	rows := rows_of(tree) or { panic(err) }
	defer {
		rows_free(rows)
	}
	assert C.vt_rows_check(rows, tree) == 0, src
	// Written and read back as another parser would fill them: the same rows.
	path := os.join_path(os.temp_dir(), 'veslint-rows-test-${os.getpid()}.bin')
	assert C.vt_rows_dump(rows, &char(path.str))
	loaded := C.vt_rows_load(&char(path.str), voidptr(C.vt_rows_language(rows)))
	os.rm(path) or {}
	assert !isnil(loaded)
	defer {
		rows_free(loaded)
	}
	assert loaded.count == rows.count
	for i in 0 .. int(rows.count) {
		a := C.vt_node_row(C.vt_node_at(rows, u32(i)))
		b := C.vt_node_row(C.vt_node_at(loaded, u32(i)))
		assert a.start_byte == b.start_byte && a.end_byte == b.end_byte && a.start_row == b.start_row
			&& a.start_column == b.start_column && a.end_row == b.end_row
			&& a.end_column == b.end_column && a.parent == b.parent && a.next == b.next
			&& a.prev == b.prev && a.last == b.last && a.symbol == b.symbol && a.field == b.field
			&& a.flags == b.flags, src
	}
	return u64(rows.count)
}
