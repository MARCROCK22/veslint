module tsgo

// The converter from TypeScript's AST to the rows of tree-sitter's tree (tsgo/inproc/convert.go,
// linked in libveslint_tsgo.a): one call parses a file with TypeScript's parser and gives the rows
// tree-sitter's parse of it would give (veslint_tsgo.h, veslint_tsgo_row). Nothing lints with it
// yet; treesitter's rows will take them.

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

// ConvertStatus is what a conversion gave.
pub enum ConvertStatus {
	rows        // the rows of the file
	diagnostics // TypeScript reports parse diagnostics (ESLint's "Parsing error"): no rows
	failed      // the converter failed: no rows, the file is parsed with tree-sitter
	no_language // convert_language was not called for the file's language
}

// Converted is the rows of a file, in C memory until free is called.
pub struct Converted {
pub:
	status ConvertStatus
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
	status := match call.result {
		0 { ConvertStatus.rows }
		1 { ConvertStatus.diagnostics }
		3 { ConvertStatus.no_language }
		else { ConvertStatus.failed }
	}
	return Converted{
		status: status
		rows:   unsafe { &C.veslint_tsgo_row(call.out) }
		count:  int(call.out_len)
	}
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
