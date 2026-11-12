module offsets

import os
import treesitter { Ident }

struct AppExpected {
	name     string
	byte_off int
	utf16    int
	line     int
	col      int
}

// Table and output of PROMPT.md §5, verified with tsgo 7.0.2 and 7.1.0-beta on app.ts.
const app_expected = [
	AppExpected{
		name:     'saludo'
		byte_off: 32
		utf16:    30
		line:     2
		col:      7
	},
	AppExpected{
		name:     'mensaje'
		byte_off: 59
		utf16:    57
		line:     3
		col:      5
	},
	AppExpected{
		name:     'año'
		byte_off: 89
		utf16:    87
		line:     4
		col:      7
	},
	AppExpected{
		name:     'fiesta'
		byte_off: 108
		utf16:    105
		line:     4
		col:      25
	},
	AppExpected{
		name:     'x'
		byte_off: 131
		utf16:    126
		line:     4
		col:      46
	},
	AppExpected{
		name:     'nada'
		byte_off: 144
		utf16:    139
		line:     5
		col:      7
	},
	AppExpected{
		name:     'suma'
		byte_off: 166
		utf16:    161
		line:     6
		col:      10
	},
	AppExpected{
		name:     'a'
		byte_off: 171
		utf16:    166
		line:     6
		col:      15
	},
	AppExpected{
		name:     'b'
		byte_off: 182
		utf16:    177
		line:     6
		col:      26
	},
	AppExpected{
		name:     'resultado'
		byte_off: 227
		utf16:    222
		line:     9
		col:      7
	},
]

fn read_app() string {
	raw := os.read_file(os.join_path(@VMODROOT, 'app.ts')) or { panic(err) }
	src, _ := strip_bom(raw)
	return src
}

fn declared(src string) []Ident {
	p := treesitter.new_parser() or { panic(err) }
	defer {
		p.close()
	}
	tree := p.parse(src) or { panic(err) }
	defer {
		treesitter.tree_delete(tree)
	}
	return p.identifiers(tree, src, false)
}

fn test_app_table_bytes_to_utf16() {
	src := read_app()
	assert utf16_offsets(src, app_expected.map(it.byte_off)) == app_expected.map(it.utf16)
}

fn test_app_declarations_found_by_tree_sitter() {
	idents := declared(read_app())
	assert idents.map(it.text) == app_expected.map(it.name)
	assert idents.map(it.start_byte) == app_expected.map(it.byte_off)
}

fn test_app_display_positions() {
	src := read_app()
	offsets, display := utf16_positions(src, declared(src))
	assert offsets == app_expected.map(it.utf16)
	assert display.map(it.line) == app_expected.map(it.line)
	assert display.map(it.col) == app_expected.map(it.col)
}

fn test_unsorted_offsets() {
	// é takes 2 bytes and 1 unit; 🎉 takes 4 bytes and 2 units.
	assert utf16_offsets('é🎉x', [6, 0, 2]) == [3, 0, 1]
}

fn test_emoji() {
	src := 'const s = "🎉🎉🎉"; const x = 1;\n'
	idents := declared(src)
	assert idents.map(it.text) == ['s', 'x']
	assert idents[1].start_byte == 32
	assert utf16_offsets(src, [32]) == [26]
}

fn test_bom_is_stripped() {
	src, had_bom := strip_bom('\xEF\xBB\xBFlet bb = 1;\n')
	assert had_bom
	assert src == 'let bb = 1;\n'
	idents := declared(src)
	assert idents[0].text == 'bb'
	assert utf16_offsets(src, [idents[0].start_byte]) == [4]
	_, again := strip_bom(src)
	assert !again
}

fn test_crlf() {
	src := 'const a = 1;\r\nconst bb = 2;\r\n'
	idents := declared(src)
	assert idents.map(it.text) == ['a', 'bb']
	assert idents[1].start_byte == 20
	assert idents[1].row == 1
	assert idents[1].col_bytes == 6
	_, display := utf16_positions(src, idents)
	assert display[1] == DisplayPos{
		line: 2
		col:  7
	}
}

fn test_line_separator_u2028() {
	src := '// a b\nconst z = 1;\n'
	idents := declared(src)
	assert idents.map(it.text) == ['z']
	assert idents[0].start_byte == 15
	assert idents[0].row == 1
	assert utf16_offsets(src, [15]) == [13]
	// tree-sitter's row is 1, and the line tsc and ESLint show is the third: U+2028 ends the first.
	_, display := utf16_positions(src, idents)
	assert display[0] == DisplayPos{
		line: 3
		col:  7
	}
}

// The line breaks of TypeScript's computeLineStarts and of ESLint's /\r\n|[\r\n\u2028\u2029]/.
fn test_line_starts() {
	src := 'a\r\nb\rc\nd\u2028e\u2029f\n\rg\r\r'
	lines := line_starts(src)
	// a CRLF b CR c LF d U+2028 e U+2029 f LF CR g CR CR
	assert lines.starts == [0, 3, 5, 7, 11, 15, 17, 18, 20, 21]
	assert lines.line_index(0) == 0
	// The `\n` of a CRLF is still in the line it ends.
	assert lines.line_index(2) == 0
	assert lines.line_index(3) == 1
	assert lines.line_index(4) == 1
	assert lines.line_index(7) == 3
	// The bytes of U+2028 are in the line it ends.
	assert lines.line_index(10) == 3
	assert lines.line_index(11) == 4
	assert lines.line_index(16) == 5
	assert lines.line_index(17) == 6
	assert lines.line_index(19) == 7
	assert lines.line_index(src.len) == 9
	for offset in 0 .. src.len + 1 {
		// Nothing starts between the `\r` and the `\n` of a CRLF.
		if offset == 2 {
			continue
		}
		assert lines.line_start(offset) == line_start_before(src, offset), 'offset ${offset}'
	}
	assert line_starts('').starts == [0]
	assert line_starts('x').line_start(1) == 0
	assert LineStarts{}.line_index(5) == 0
	assert LineStarts{}.line_start(5) == 0
	// E2 80 A7 and E2 81 A8 are not line breaks.
	assert line_starts('a\u2027b\u2068c').starts == [0]
	assert line_start_before('a\u2027b\u2068c', 8) == 0
}

fn test_display_positions_with_every_line_break() {
	src := '// a\u2028const a = 1;\u2029const b = "🎉\u2028"; const c = 2;\rconst d = `\r\n`; const e = 3;\r\nconst f = 4;\n'
	idents := declared(src)
	assert idents.map(it.text) == ['a', 'b', 'c', 'd', 'e', 'f']
	// tree-sitter sees three rows; tsc and ESLint, seven lines.
	assert idents.map(it.row) == [0, 0, 0, 0, 1, 2]
	_, display := utf16_positions(src, idents)
	assert display.map(it.line) == [2, 3, 4, 5, 6, 7]
	assert display.map(it.col) == [7, 7, 10, 7, 10, 7]
}

// A report without a place in the file has a negative row: ESLint's line 0 and column 0, which
// it prints as `0:1`.
fn test_display_position_without_a_place() {
	_, display := utf16_positions('a\nb\n', [Ident{
		row: -1
	}])
	assert display == [DisplayPos{
		line: 0
		col:  1
	}]
}

fn test_all_identifiers_includes_usages() {
	src := 'const a = 1;\nconst b = a + a;\n'
	p := treesitter.new_parser() or { panic(err) }
	defer {
		p.close()
	}
	tree := p.parse(src) or { panic(err) }
	defer {
		treesitter.tree_delete(tree)
	}
	idents := p.identifiers(tree, src, true)
	assert idents.map(it.text) == ['a', 'b', 'a', 'a']
	assert idents.map(it.start_byte) == [6, 19, 23, 27]
}
