module rules

import offsets
import os
import sync
import treesitter
import tsgo

// Which parser builds the rows a lint reads. TypeScript's (the converter of tsgo/inproc/convert.go:
// TypeScript 7.1's parser, whose AST is written as the rows tree-sitter's parse would give) or
// tree-sitter's. VESLINT_PARSER=typescript or tree-sitter chooses; without it, default_parser_source.
// The rows of a .vue or .svelte file's script and template snippets, and those `--server` parses
// from the tree of the file's last text (treesitter.TreeCache), are tree-sitter's whatever it says.

// ParserSource is the parser of a lint's rows.
pub enum ParserSource {
	tree_sitter
	typescript
}

const default_parser_source = ParserSource.tree_sitter

const parser_source = parser_source_of(os.getenv('VESLINT_PARSER'))

// VESLINT_PARSER_DEBUG=1 writes a line on stderr for each file TypeScript's parser was asked for and
// tree-sitter parsed instead (the converter failed).
const parser_debug = os.getenv('VESLINT_PARSER_DEBUG') == '1'

fn parser_source_of(name string) ParserSource {
	return match name {
		'typescript' {
			.typescript
		}
		'tree-sitter' {
			.tree_sitter
		}
		'' {
			default_parser_source
		}
		else {
			eprintln('warning: VESLINT_PARSER=${name} is neither typescript nor tree-sitter: ${default_parser_source} parses')
			default_parser_source
		}
	}
}

// the_parser_source is the parser of the rows of a plain TypeScript file.
pub fn the_parser_source() ParserSource {
	return parser_source
}

// The converter needs the tables of both languages of the grammar once per process, before its
// first file (tsgo.convert_language).
const converter_languages_once = sync.new_once()

fn give_converter_languages() {
	mut once := converter_languages_once
	once.do(fn () {
		for tsx in [false, true] {
			tables := treesitter.converter_tables(tsx)
			tsgo.convert_language(tsx, tables.language, tables.symbol, tables.field)
		}
	})
}

// TypeScriptParse is what TypeScript's parser gave for a file: its rows, or its parse diagnostics
// (ESLint's "Parsing error"), or neither when the converter failed.
struct TypeScriptParse {
	rows        &C.vt_rows = unsafe { nil }
	diagnostics []tsgo.Diagnostic
}

// typescript_parse parses `src` with TypeScript's parser in the dialect of `parser` (TSX for a
// .tsx file) and as ESLint's sourceType says: ESLint gives the parser the sourceType of its parser
// options or of its language options, and typescript-estree makes a "module" a module whatever it
// contains (top-level `await` is then an await expression).
fn typescript_parse(parser treesitter.Parser, src string, language LanguageOptions, path string) TypeScriptParse {
	give_converter_languages()
	source_type := if language.parser_source_type != '' {
		language.parser_source_type
	} else {
		language.source_type
	}
	mut converted := tsgo.convert(src, parser.is_tsx(), source_type != 'module')
	match converted.status {
		.rows {
			rows := parser.adopt_rows(converted.rows, converted.count) or {
				if parser_debug {
					eprintln('debug: ${path}: ${err.msg()}; tree-sitter parses it')
				}
				return TypeScriptParse{}
			}
			// The rows own the buffer now.
			converted.rows = unsafe { nil }
			return TypeScriptParse{
				rows: rows
			}
		}
		.diagnostics {
			return TypeScriptParse{
				diagnostics: converted.diagnostics
			}
		}
		else {
			if parser_debug {
				eprintln("debug: ${path}: TypeScript's converter gave ${converted.status}; tree-sitter parses it")
			}
			return TypeScriptParse{}
		}
	}
}

// typescript_parsing_error is ESLint's fatal problem for a file TypeScript's parser rejects: the
// first of its parse diagnostics in the order typescript-estree throws them (first_parse_diagnostic),
// at its line and 0-based column. `diagnostics` are positioned in the file's text (the one parsed).
fn (c &Checker) typescript_parsing_error(diagnostics []tsgo.Diagnostic) []Finding {
	first := first_parse_diagnostic(diagnostics, offsets.utf16_offsets(c.src, [c.src.len])[0])
	return [
		Finding{
			stmt:             c.position_at(offsets.byte_offset(c.src, first.pos))
			rule:             problem_rule
			message_id:       'fatal'
			text:             'Parsing error: ${first.text}'
			column_from_zero: true
		},
	]
}
