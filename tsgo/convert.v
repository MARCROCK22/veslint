module tsgo

// The converter from TypeScript's AST to the rows of tree-sitter's tree (tsgo/inproc/convert.go,
// linked in libveslint_tsgo.a): one call parses a file with TypeScript's parser and gives the rows
// tree-sitter's parse of it would give (veslint_tsgo.h, veslint_tsgo_row), which a lint reads as
// its tree (rules.lint_file, treesitter.rows_adopt), or the parse diagnostics.

// A row: a visible node of the tree, in preorder (see veslint_tsgo.h).
pub struct C.veslint_tsgo_row {
pub:
	start_byte   u32
	end_byte     u32
	start_row    u32
	start_column u32
	end_row      u32
	end_column   u32
	parent       u32
	next         u32
	prev         u32
	last         u32
	symbol       u16
	field        u16
	flags        u8
}

pub const row_none = max_u32
pub const row_named = u8(1)
pub const row_extra = u8(2)
pub const row_missing = u8(4)
pub const row_error = u8(8)
pub const row_has_error = u8(16)

const op_convert_language = 6
const op_convert = 7
const op_convert_file = 8

// ConvertStatus is what a conversion gave.
pub enum ConvertStatus {
	rows        // the rows of the file
	diagnostics // TypeScript reports parse diagnostics (ESLint's "Parsing error"): no rows
	failed      // the converter failed: no rows, the file is parsed with tree-sitter
	no_language // convert_language was not called for the file's language
}

// Converted is the rows of a file, in C memory until free is called, or its parse diagnostics.
pub struct Converted {
pub:
	status ConvertStatus
	// The parse diagnostics (status .diagnostics) in the order of transpile_diagnostics' (by
	// position), with `pos` in UTF-16 units of the text and `end` unknown (= pos).
	diagnostics []Diagnostic
pub mut:
	rows  &C.veslint_tsgo_row = unsafe { nil }
	count int
}

// convert_language gives the converter the tables of one of the grammar's languages, once, before
// the first convert of a file of it: `language` is the `const TSLanguage *`, `symbol` and `field`
// its ts_language_symbol_for_name and ts_language_field_id_for_name (Go calls them through a
// pointer that takes the language as `const void *`).
pub fn convert_language(tsx bool, language voidptr, symbol voidptr, field voidptr) {
	mut call := C.veslint_tsgo_call{
		op:   op_convert_language
		flag: if tsx { 1 } else { 0 }
		a:    unsafe { &char(language) }
		b:    unsafe { &char(symbol) }
		c:    unsafe { &char(field) }
	}
	C.veslint_tsgo_invoke(&call)
}

// convert parses `text` (without its BOM) with TypeScript's parser and converts its AST to the
// rows of tree-sitter's tree of it. `script` is ESLint's sourceType "script" (TypeScript then
// reads a top-level `await` as a name).
pub fn convert(text string, tsx bool, script bool) Converted {
	mut flags := if tsx { 1 } else { 0 }
	if script {
		flags |= 2
	}
	mut call := C.veslint_tsgo_call{
		op:    op_convert
		flag:  flags
		a:     &char(text.str)
		a_len: uint(text.len)
	}
	C.veslint_tsgo_invoke(&call)
	return converted_of(call)
}

// ProgramFile names a file of a program of TypeScript in this process: the client of the session,
// the snapshot, the project and the file's path, as a request for the file gives them.
pub struct ProgramFile {
pub:
	client   &Client = unsafe { nil }
	snapshot int     = -1
	project  string
	path     string
}

// convert_in is convert for `program`, a file of a program of TypeScript in this process (none
// when its client is not in this process or has no snapshot): the converter converts the
// program's AST of the file when it is the one a parse of `text` gives, so that the file is not
// parsed again, and parses `text` otherwise. The rows are the same.
pub fn convert_in(program ProgramFile, text string, tsx bool, script bool) Converted {
	if program.client == unsafe { nil } || program.client.inproc == 0 || program.snapshot < 0
		|| program.path == '' {
		return convert(text, tsx, script)
	}
	mut flags := if tsx { 1 } else { 0 }
	if script {
		flags |= 2
	}
	// As the parameters of veslint/nodesAtRanges, without values.
	params := binary_params(program.snapshot, program.project, program.path, [])
	mut call := C.veslint_tsgo_call{
		op:     op_convert_file
		handle: program.client.inproc
		flag:   flags
		a:      &char(text.str)
		a_len:  uint(text.len)
		b:      &char(params.str)
		b_len:  uint(params.len)
	}
	C.veslint_tsgo_invoke(&call)
	return converted_of(call)
}

// converted_of is what a call of op_convert or op_convert_file gave.
fn converted_of(call C.veslint_tsgo_call) Converted {
	status := match call.result {
		0 { ConvertStatus.rows }
		1 { ConvertStatus.diagnostics }
		3 { ConvertStatus.no_language }
		else { ConvertStatus.failed }
	}
	if status == .diagnostics {
		report := unsafe { tos(&u8(call.out), int(call.out_len)) }.clone()
		unsafe { C.free(call.out) }
		diagnostics := parse_diagnostics_text(report) or {
			return Converted{
				status: .failed
			}
		}
		return Converted{
			status:      status
			diagnostics: diagnostics
		}
	}
	return Converted{
		status: status
		rows:   unsafe { &C.veslint_tsgo_row(call.out) }
		count:  int(call.out_len)
	}
}

// parse_diagnostics_text reads the converter's diagnostics: per diagnostic `code pos length` on a
// line, then its message of `length` bytes (tsgo/inproc/main.go, diagnosticsText).
fn parse_diagnostics_text(report string) ![]Diagnostic {
	mut out := []Diagnostic{}
	mut at := 0
	for at < report.len {
		eol := report.index_after_('\n', at)
		if eol < 0 {
			return error('the converter gave a diagnostic without its message')
		}
		head := report[at..eol].split(' ')
		if head.len != 3 {
			return error('the converter gave a diagnostic header `${report[at..eol]}`')
		}
		length := head[2].int()
		if length < 0 || eol + 1 + length > report.len {
			return error('the converter gave a diagnostic message beyond its text')
		}
		pos := head[1].int()
		out << Diagnostic{
			pos:  pos
			end:  pos
			code: head[0].int()
			text: report[eol + 1..eol + 1 + length]
		}
		at = eol + 1 + length
	}
	return out
}

// row is the i-th row.
pub fn (c &Converted) row(i int) C.veslint_tsgo_row {
	return unsafe { c.rows[i] }
}

// free frees the rows.
pub fn (mut c Converted) free() {
	if !isnil(c.rows) {
		unsafe { C.free(c.rows) }
		c.rows = unsafe { nil }
		c.count = 0
	}
}
