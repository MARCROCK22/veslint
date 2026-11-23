module tsparse

import treesitter

fn ts_parser(tsx bool) &C.TSParser {
	return (if tsx { treesitter.new_tsx_parser() } else { treesitter.new_parser() } or {
		panic(err)
	}).ts_parser()
}

fn test_typescript_rows_of_code_it_parses() {
	if source() != .typescript {
		return
	}
	parsed := parse(ts_parser(false), 'const a = <T>(x: T) => x;\n', 'a snippet')!
	defer {
		treesitter.rows_free(parsed.rows)
	}
	assert parsed.typescript
	assert !parsed.rejected
	assert parsed.diagnostics.len == 0
	assert !treesitter.tree_has_error(parsed.rows)
	root := treesitter.root_node(parsed.rows)
	assert treesitter.node_kind(root) == 'program'
}

fn test_code_only_tree_sitter_rejects_parses() {
	if source() != .typescript {
		return
	}
	// tree-sitter's grammar does not read `new new Foo()`; TypeScript does.
	parsed := parse(ts_parser(false), 'new new Foo();\n', 'a snippet')!
	defer {
		treesitter.rows_free(parsed.rows)
	}
	assert parsed.typescript
	assert !parsed.rejected
}

fn test_rejected_code_keeps_tree_sitter_rows_and_diagnostics() {
	if source() != .typescript {
		return
	}
	code := 'let x = ;\n'
	parsed := parse(ts_parser(false), code, 'a snippet')!
	defer {
		treesitter.rows_free(parsed.rows)
	}
	assert !parsed.typescript
	assert parsed.rejected
	assert parsed.diagnostics.len > 0
	// tree-sitter's rows, with its error, where its first error is.
	assert treesitter.tree_has_error(parsed.rows)
	assert parsed.error_offset(code) == treesitter.first_error_offset(treesitter.root_node(parsed.rows))
}

fn test_error_offset_of_code_only_typescript_rejects() {
	if source() != .typescript {
		return
	}
	// A legacy octal literal: tree-sitter's grammar reads it, TypeScript's parser reports it.
	code := 'const é = 010;\n'
	parsed := parse(ts_parser(false), code, 'a snippet')!
	defer {
		treesitter.rows_free(parsed.rows)
	}
	assert parsed.rejected
	assert !treesitter.tree_has_error(parsed.rows)
	// The diagnostic's UTF-16 position in bytes: `é` is two bytes and one unit.
	assert parsed.error_offset(code) == code.index('010') or { -1 }
}

fn test_the_dialect_of_the_parser() {
	if source() != .typescript {
		return
	}
	jsx := '<div>{a}</div>;\n'
	tsx := parse(ts_parser(true), jsx, 'a snippet')!
	defer {
		treesitter.rows_free(tsx.rows)
	}
	assert tsx.typescript && !tsx.rejected
	ts := parse(ts_parser(false), jsx, 'a snippet')!
	defer {
		treesitter.rows_free(ts.rows)
	}
	assert ts.rejected
}
