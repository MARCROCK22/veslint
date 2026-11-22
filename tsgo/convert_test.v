module tsgo

import os
import time

// The converter through its C entry point (tsgo/convert.v): its rows against tree-sitter's for a
// few files, and its other results. tests/tsconv/ is the differential test on the corpus.

#flag -I @VMODROOT/vendor/tree-sitter/lib/include
#flag @VMODROOT/build/libtree-sitter-typescript.a
#flag @VMODROOT/treesitter/out/libtree-sitter.a
#include "@VMODROOT/tsgo/inproc/veslint_tsgo_languages.h"

@[typedef]
struct C.TSLanguage {}

@[typedef]
struct C.TSParser {}

@[typedef]
struct C.TSTree {}

@[typedef]
struct C.TSNode {}

@[typedef]
struct C.TSTreeCursor {}

@[typedef]
struct C.TSPoint {
	row    u32
	column u32
}

fn C.veslint_tsgo_convert_languages()
fn C.tree_sitter_typescript() &C.TSLanguage
fn C.tree_sitter_tsx() &C.TSLanguage
fn C.ts_parser_new() &C.TSParser
fn C.ts_parser_delete(&C.TSParser)
fn C.ts_parser_set_language(&C.TSParser, &C.TSLanguage) bool
fn C.ts_parser_parse_string(&C.TSParser, &C.TSTree, &char, u32) &C.TSTree
fn C.ts_tree_delete(&C.TSTree)
fn C.ts_tree_root_node(&C.TSTree) C.TSNode
fn C.ts_tree_cursor_new(C.TSNode) C.TSTreeCursor
fn C.ts_tree_cursor_delete(&C.TSTreeCursor)
fn C.ts_tree_cursor_current_node(&C.TSTreeCursor) C.TSNode
fn C.ts_tree_cursor_current_field_id(&C.TSTreeCursor) u16
fn C.ts_tree_cursor_goto_first_child(&C.TSTreeCursor) bool
fn C.ts_tree_cursor_goto_next_sibling(&C.TSTreeCursor) bool
fn C.ts_tree_cursor_goto_parent(&C.TSTreeCursor) bool
fn C.ts_node_symbol(C.TSNode) u16
fn C.ts_node_start_byte(C.TSNode) u32
fn C.ts_node_end_byte(C.TSNode) u32
fn C.ts_node_start_point(C.TSNode) C.TSPoint
fn C.ts_node_end_point(C.TSNode) C.TSPoint
fn C.ts_node_is_named(C.TSNode) bool
fn C.ts_node_is_extra(C.TSNode) bool
fn C.ts_language_symbol_for_name(&C.TSLanguage, &char, u32, bool) u16

// tree_sitter_rows is tree-sitter's tree of `text` as the converter's rows describe it: per node,
// in preorder, "symbol field flags start-end (row,column)-(row,column) parent".
fn tree_sitter_rows(text string, tsx bool) []string {
	parser := C.ts_parser_new()
	defer {
		C.ts_parser_delete(parser)
	}
	lang := if tsx { C.tree_sitter_tsx() } else { C.tree_sitter_typescript() }
	assert C.ts_parser_set_language(parser, lang)
	tree := C.ts_parser_parse_string(parser, unsafe { nil }, &char(text.str), u32(text.len))
	defer {
		C.ts_tree_delete(tree)
	}
	mut cursor := C.ts_tree_cursor_new(C.ts_tree_root_node(tree))
	defer {
		C.ts_tree_cursor_delete(&cursor)
	}
	mut out := []string{}
	mut open := []int{}
	for {
		node := C.ts_tree_cursor_current_node(&cursor)
		field := if open.len == 0 { u16(0) } else { C.ts_tree_cursor_current_field_id(&cursor) }
		mut flags := 0
		if C.ts_node_is_named(node) {
			flags |= 1
		}
		if C.ts_node_is_extra(node) {
			flags |= 2
		}
		s := C.ts_node_start_point(node)
		e := C.ts_node_end_point(node)
		parent := if open.len == 0 { -1 } else { open.last() }
		out << '${C.ts_node_symbol(node)} ${field} ${flags} ${C.ts_node_start_byte(node)}-${C.ts_node_end_byte(node)} (${s.row},${s.column})-(${e.row},${e.column}) ${parent}'
		if C.ts_tree_cursor_goto_first_child(&cursor) {
			open << out.len - 1
			continue
		}
		for !C.ts_tree_cursor_goto_next_sibling(&cursor) {
			if open.len == 0 || !C.ts_tree_cursor_goto_parent(&cursor) {
				return out
			}
			open.pop()
		}
	}
	return out
}

fn converted_rows(c &Converted) []string {
	mut out := []string{}
	for i in 0 .. c.count {
		r := c.row(i)
		parent := if r.parent == row_none { -1 } else { int(r.parent) }
		out << '${r.symbol} ${r.field} ${r.flags & 3} ${r.start_byte}-${r.end_byte} (${r.start_row},${r.start_column})-(${r.end_row},${r.end_column}) ${parent}'
	}
	return out
}

fn test_convert_gives_tree_sitters_rows() {
	C.veslint_tsgo_convert_languages()
	cases := [
		['a.ts',
			'// lead\nimport x, { y as z } from "m";\nexport const a: number = 1, b = `t\${x}u`; // c\nclass C<T> extends B implements I { @d m(): void {} p?: string = "s\\n" }\nif (a) { b() } // after\nelse c()\ntype U = A | B & { k: typeof import("x") };\n'],
		['b.tsx', 'const e = <div className="a &amp; b" {...p}>\n  text &lt; {x}\n  <A.B<T> />\n</div>;\n'],
		['c.ts', ''],
		['d.ts', '#!/usr/bin/env node\n\n  /* only a comment */\n'],
	]
	for c in cases {
		tsx := c[0].ends_with('.tsx')
		mut got := convert(c[1], tsx, false)
		defer {
			got.free()
		}
		assert got.status == .rows, c[0]
		assert converted_rows(got) == tree_sitter_rows(c[1], tsx), c[0]
		// The links of the rows: the first child of the root follows it, and prev mirrors next.
		for i in 0 .. got.count {
			r := got.row(i)
			if r.next != row_none {
				assert got.row(int(r.next)).prev == u32(i)
			}
			assert int(r.last) >= i
		}
		lang := if tsx { C.tree_sitter_tsx() } else { C.tree_sitter_typescript() }
		program := C.ts_language_symbol_for_name(lang, c'program', 7, true)
		assert got.row(0).symbol == program
	}
}

fn test_convert_reports_parse_diagnostics() {
	C.veslint_tsgo_convert_languages()
	mut got := convert('const = ;\n', false, false)
	assert got.status == .diagnostics
	assert got.count == 0
	assert got.diagnostics.len > 0
	assert got.diagnostics[0].code == 1134
	assert got.diagnostics[0].text == 'Variable declaration expected.'
	assert got.diagnostics[0].pos == 6
	got.free()
	// Positions are in UTF-16 units: the two units of 😀 before the error, not its four bytes.
	got = convert('"😀"; const = ;\n', false, false)
	assert got.status == .diagnostics
	assert got.diagnostics[0].pos == 12
	// TypeScript 7.1 alone rejects `as` before `**` (microsoft/TypeScript#63527); parser.patch
	// gives TypeScript 6's reading, `((x < 0) as any) ** 2`, without diagnostics.
	got = convert('x < 0 as any ** 2;\n', false, false)
	assert got.status == .rows
	got.free()
}

fn test_convert_reads_top_level_await_by_source_type() {
	C.veslint_tsgo_convert_languages()
	// In a module (ESLint's default sourceType) `await (1)` is an await expression; in a script
	// a call of a function named await.
	mut module_rows := convert('await (1);\n', false, false)
	mut script_rows := convert('await (1);\n', false, true)
	defer {
		module_rows.free()
		script_rows.free()
	}
	assert module_rows.status == .rows
	assert script_rows.status == .rows
	lang := C.tree_sitter_typescript()
	await_expression := C.ts_language_symbol_for_name(lang, c'await_expression', 16, true)
	call_expression := C.ts_language_symbol_for_name(lang, c'call_expression', 15, true)
	assert module_rows.row(2).symbol == await_expression
	assert script_rows.row(2).symbol == call_expression
}

// convert_in converts the program's AST of a file when it is the one a parse of the text gives, and
// parses the text otherwise: the rows are convert's in every case. a.ts is a module; b.ts has no
// import or export, so the program reads it as a script while ESLint's default sourceType makes it
// a module (`await (1)` an await expression); c.tsx is TSX; and a text that is not the program's
// (an unsaved edit) is parsed.
fn test_convert_in_gives_the_rows_of_convert() {
	bin := os.join_path(@VMODROOT, rel_path)
	if !os.is_file(bin) {
		eprintln('skipped: ${bin} is missing')
		return
	}
	C.veslint_tsgo_convert_languages()
	dir := os.join_path(os.temp_dir(), 'veslint-convert-in-test-${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	tsconfig := os.join_path(dir, 'tsconfig.json')
	os.write_file(tsconfig, '{"compilerOptions":{"strict":true,"noEmit":true,"jsx":"preserve"},"include":["*.ts","*.tsx"]}') or {
		panic(err)
	}
	files := {
		'a.ts':  'import { x } from "./b";\nexport const a = await (x as number);\n'
		'b.ts':  'const x = 1;\nawait (1);\n'
		'c.tsx': 'export const e = <div className="a">{1}</div>;\n'
	}
	for name, text in files {
		os.write_file(os.join_path(dir, name), text) or { panic(err) }
	}
	mut c := start(bin, dir, 20 * time.second) or { panic(err) }
	defer {
		c.shutdown()
	}
	c.initialize() or { panic(err) }
	snap := c.create_snapshot([tsconfig]) or { panic(err) }
	mut cases := [][]string{}
	for name, text in files {
		cases << [name, text]
	}
	cases << ['a.ts', 'export const a = 2;\n']
	for case in cases {
		tsx := case[0].ends_with('.tsx')
		program := ProgramFile{
			client:   c
			snapshot: snap.snapshot
			project:  snap.projects[0].id
			path:     os.join_path(dir, case[0])
		}
		for script in [false, true] {
			mut got := convert_in(program, case[1], tsx, script)
			mut want := convert(case[1], tsx, script)
			assert got.status == .rows, '${case[0]} ${script}'
			assert converted_rows(got) == converted_rows(want), '${case[0]} ${script}'
			got.free()
			want.free()
		}
	}
	// Without a snapshot (a lint without types), the text is parsed.
	mut got := convert_in(ProgramFile{
		client: c
		path:   os.join_path(dir, 'a.ts')
	}, files['a.ts'], false, false)
	assert got.status == .rows
	got.free()
}
