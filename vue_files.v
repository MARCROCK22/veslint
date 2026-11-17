module main

import offsets
import rules
import treesitter
import vue

// Vue single-file components. veslint lints the TypeScript script of a .vue file as ESLint does
// with vue-eslint-parser and typescript-eslint's parser: the rules run on the script (rules/
// vue_file.v), with the types tsgo gives for the code typescript-eslint type-checks, which tsgo has
// in a virtual TypeScript twin of the file (rules.vue_twin_path), served by the client and never
// written. A .vue whose script is JavaScript is not linted (veslint lints only TypeScript): it is
// skipped with a warning. One without a script is linted (its Program is empty).

// VueParsers parses the .vue files of a run, created on first use.
struct VueParsers {
mut:
	parsers &vue.Parsers = unsafe { nil }
}

fn (mut p VueParsers) parse(src string) !&vue.Document {
	if p.parsers == unsafe { nil } {
		p.parsers = vue.new_parsers()!
	}
	return vue.parse_sfc_with(src, vue.Options{}, p.parsers)
}

fn (mut p VueParsers) close() {
	if p.parsers != unsafe { nil } {
		p.parsers.close()
		p.parsers = unsafe { nil }
	}
}

// vue_javascript_warning is the warning for a .vue file that is not linted because its script is
// JavaScript.
fn vue_javascript_warning(path string) string {
	return 'warning: ${path}: not linted: its <script> is JavaScript, and veslint lints only TypeScript (lang="ts" or "tsx")'
}

// twin_code is the code tsgo is given for a .vue file (its twin's text) and whether the file is
// linted: not when its script is JavaScript.
fn (mut p VueParsers) twin_code(src string) !(string, bool) {
	mut doc := p.parse(src)!
	defer {
		doc.free()
	}
	return doc.script.code, doc.script.lang != .js
}

// uses_tsx_grammar: the script of the document is read with the grammar's tsx dialect.
fn uses_tsx_grammar(doc &vue.Document) bool {
	return doc.script.lang == .tsx
}

// vue_report_positions are the line and column ESLint prints for the start (and, with `ends`, the
// end) of each finding of a .vue file: those of vue-eslint-parser's locations, whose lines end
// only at a line feed, for a report on a node or a token; ESLint's own (offsets.utf16_positions)
// for one whose rule computes its location from the text (Finding.text_loc).
fn vue_report_positions(doc &vue.Document, findings []rules.Finding, ends bool) ([]offsets.DisplayPos, []offsets.DisplayPos) {
	mut starts := []offsets.DisplayPos{cap: findings.len}
	mut end_positions := []offsets.DisplayPos{}
	text_located := findings.filter(it.text_loc)
	mut text_starts := []offsets.DisplayPos{}
	mut text_ends := []offsets.DisplayPos{}
	if text_located.len > 0 {
		_, text_starts = offsets.utf16_positions(doc.src, text_located.map(it.stmt))
		_, text_ends = offsets.utf16_positions(doc.src, text_located.map(treesitter.Ident{
			start_byte: if it.stmt.end_byte >= 0 { it.stmt.end_byte } else { it.stmt.start_byte }
			row:        it.stmt.row
		}))
	}
	mut next := 0
	for f in findings {
		if f.text_loc {
			starts << text_starts[next]
			if ends {
				end_positions << text_ends[next]
			}
			next++
			continue
		}
		loc := doc.loc(f.stmt.start_byte)
		starts << offsets.DisplayPos{
			// A report without a place in the file: ESLint's line 0.
			line: if f.stmt.row < 0 { 0 } else { loc.line }
			col:  loc.column + 1
		}
		if ends {
			end := doc.loc(if f.stmt.end_byte >= 0 { f.stmt.end_byte } else { f.stmt.start_byte })
			end_positions << offsets.DisplayPos{
				line: end.line
				col:  end.column + 1
			}
		}
	}
	return starts, end_positions
}

// vue_identifiers are the identifiers of the script of a .vue file for the type mode: where they
// are in the file, and their UTF-16 offsets in the twin's text (what tsgo is asked).
fn vue_identifiers(parser treesitter.Parser, doc &vue.Document, all bool) ([]treesitter.Ident, []int, []offsets.DisplayPos) {
	script := &doc.script
	if script.tree == unsafe { nil } {
		return []treesitter.Ident{}, []int{}, []offsets.DisplayPos{}
	}
	idents := parser.identifiers(script.tree, doc.src, all).filter(script.file_to_synthetic(it.start_byte,
		false) >= 0)
	code_bytes := idents.map(script.file_to_synthetic(it.start_byte, false))
	units := offsets.utf16_offsets(script.code, code_bytes)
	mut display := []offsets.DisplayPos{cap: idents.len}
	for id in idents {
		loc := doc.loc(id.start_byte)
		display << offsets.DisplayPos{
			line: loc.line
			col:  loc.column + 1
		}
	}
	return idents, units, display
}
