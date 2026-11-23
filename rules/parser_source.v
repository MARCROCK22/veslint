module rules

import offsets
import treesitter
import tsgo
import tsparse

// Which parser builds the rows a lint reads: tsparse.source (VESLINT_PARSER), TypeScript's by
// default (the converter of tsgo/inproc/convert.go: TypeScript 7.1's parser, whose AST is written
// as the rows tree-sitter's parse would give), for a plain TypeScript file, the script and
// template snippets of a .vue or .svelte file (vue/, svelte/) and Svelte's lint code.

const parser_source = tsparse.source()

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
	source_type := if language.parser_source_type != '' {
		language.parser_source_type
	} else {
		language.source_type
	}
	converted := tsparse.convert(parser.ts_parser(), src, source_type != 'module')
	if converted.failed != '' && tsparse.debugging() {
		eprintln('debug: ${path}: ${converted.failed}; tree-sitter parses it')
	}
	return TypeScriptParse{
		rows:        converted.rows
		diagnostics: converted.diagnostics
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
