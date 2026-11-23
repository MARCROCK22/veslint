module tsparse

import offsets
import os
import sync
import treesitter
import tsgo

// Which parser gives the rows of a text: TypeScript's (the converter of tsgo/inproc/convert.go,
// TypeScript 7.1's parser, whose AST is written as the rows tree-sitter's parse would give) or
// tree-sitter's. VESLINT_PARSER=typescript or tree-sitter chooses, for every text veslint parses:
// a file, a .vue or .svelte file's script, a template expression, the code `--server` lints.

// Source is the parser of a text's rows.
pub enum Source {
	tree_sitter
	typescript
}

// TypeScript's parser by default: it gives ESLint's tree and parse errors exactly (tree-sitter's
// grammar reads some code otherwise) and it is faster.
const default_source = Source.typescript

const the_source = source_of(os.getenv('VESLINT_PARSER'))

// VESLINT_PARSER_DEBUG=1 writes a line on stderr for each text TypeScript's parser was asked for
// and tree-sitter parsed instead (the converter failed).
const debug = os.getenv('VESLINT_PARSER_DEBUG') == '1'

fn source_of(name string) Source {
	return match name {
		'typescript' {
			.typescript
		}
		'tree-sitter' {
			.tree_sitter
		}
		'' {
			default_source
		}
		else {
			eprintln('warning: VESLINT_PARSER=${name} is neither typescript nor tree-sitter: ${default_source} parses')
			default_source
		}
	}
}

// source is the parser VESLINT_PARSER chose.
pub fn source() Source {
	return the_source
}

// debugging: VESLINT_PARSER_DEBUG=1.
pub fn debugging() bool {
	return debug
}

// The converter needs the tables of both languages of the grammar once per process, before its
// first text (tsgo.convert_language).
const languages_once = sync.new_once()

fn give_languages() {
	mut once := languages_once
	once.do(fn () {
		for tsx in [false, true] {
			tables := treesitter.converter_tables(tsx)
			tsgo.convert_language(tsx, tables.language, tables.symbol, tables.field)
		}
	})
}

// Converted is what TypeScript's parser gave for a text: its rows, or its parse diagnostics
// (ESLint's "Parsing error"), or neither when the converter failed (`failed` says why).
pub struct Converted {
pub:
	rows        &C.vt_rows = unsafe { nil }
	diagnostics []tsgo.Diagnostic
	failed      string
}

// convert parses `code` with TypeScript's parser in the dialect of `parser` (TSX when it reads the
// tsx grammar), as a module or, `script`, as ESLint's sourceType "script" (TypeScript then reads a
// top-level `await` as a name), and gives the rows in the language of `parser`.
pub fn convert(parser &C.TSParser, code string, script bool) Converted {
	give_languages()
	mut converted := tsgo.convert(code, treesitter.parser_is_tsx(parser), script)
	match converted.status {
		.rows {
			rows := treesitter.adopt_rows_of(parser, converted.rows, converted.count) or {
				return Converted{
					failed: err.msg()
				}
			}
			// The rows own the buffer now.
			converted.rows = unsafe { nil }
			return Converted{
				rows: rows
			}
		}
		.diagnostics {
			return Converted{
				diagnostics: converted.diagnostics
			}
		}
		else {
			return Converted{
				failed: "TypeScript's converter gave ${converted.status}"
			}
		}
	}
}

// Parse is the rows of a text (`rows`, to be freed with treesitter.rows_free) and whether its
// parser rejects it (`rejected`: TypeScript's parse diagnostics, or tree-sitter's ERROR and
// MISSING nodes). The rows of a text TypeScript's parser rejects are tree-sitter's, with its
// errors: what reads a tree with errors (where the first one is, the tokens of a script that does
// not parse) reads the same tree as before the converter.
pub struct Parse {
pub:
	rows &C.vt_rows = unsafe { nil }
	// typescript: the rows are TypeScript's (the converter's).
	typescript bool
	rejected   bool
	// diagnostics: TypeScript's parse diagnostics of a text it rejects (UTF-16 positions).
	diagnostics []tsgo.Diagnostic
}

// parse gives the rows of `code` with the parser `source` chose: TypeScript's, in the dialect of
// `parser` and as a module (the scripts and snippets of .vue and .svelte files are: their parsers
// give typescript-eslint sourceType "module"), else, or when the converter fails, tree-sitter's
// with `parser`. `what` names the text in errors.
pub fn parse(parser &C.TSParser, code string, what string) !Parse {
	if the_source == .typescript {
		converted := convert(parser, code, false)
		if converted.rows != unsafe { nil } {
			return Parse{
				rows:       converted.rows
				typescript: true
			}
		}
		if converted.diagnostics.len > 0 {
			return Parse{
				rows:        treesitter.parse_with(parser, code, what)!
				rejected:    true
				diagnostics: converted.diagnostics
			}
		}
		if debug {
			eprintln('debug: ${what}: ${converted.failed}; tree-sitter parses it')
		}
	}
	rows := treesitter.parse_with(parser, code, what)!
	return Parse{
		rows:     rows
		rejected: treesitter.tree_has_error(rows)
	}
}

// error_offset is where the parse of `code` failed (a byte offset): where tree-sitter's first
// ERROR or MISSING node starts when its rows have one, as before the converter, else where
// TypeScript's first diagnostic is (tree-sitter's grammar reads code TypeScript rejects), 0 when
// neither has an error.
pub fn (p &Parse) error_offset(code string) int {
	root := treesitter.root_node(p.rows)
	if C.vt_node_has_error(root) {
		return treesitter.first_error_offset(root)
	}
	if p.diagnostics.len > 0 {
		return offsets.byte_offset(code, p.diagnostics[0].pos)
	}
	return 0
}
