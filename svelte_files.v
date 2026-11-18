module main

import offsets
import os
import rules
import svelte
import time
import treesitter

// Svelte components. veslint lints a .svelte file as ESLint does with svelte-eslint-parser and
// typescript-eslint's parser: the rules run on its script and its template's expressions
// (rules/svelte_file.v), with the types tsgo gives for the virtual code svelte-eslint-parser
// hands typescript-eslint, which tsgo has in a virtual TypeScript twin of the file
// (rules.svelte_twin_path), served by the client and never written. A .svelte whose script is
// JavaScript is not linted (veslint lints only TypeScript): it is skipped with a warning. One
// without a script is linted (its template's expressions).

// SvelteParsers parses the .svelte files of a run, created on first use.
struct SvelteParsers {
mut:
	parsers &svelte.Parsers = unsafe { nil }
}

fn (mut p SvelteParsers) parse(src string) !&svelte.Document {
	if p.parsers == unsafe { nil } {
		p.parsers = svelte.new_parsers()!
	}
	return svelte.parse_svelte_with(src, p.parsers)
}

fn (mut p SvelteParsers) close() {
	if p.parsers != unsafe { nil } {
		p.parsers.close()
		p.parsers = unsafe { nil }
	}
}

// module_virtual is the virtual code of a `.svelte.ts` module (svelte/module.v).
fn (mut p SvelteParsers) module_virtual(src string) !svelte.ModuleVirtual {
	if p.parsers == unsafe { nil } {
		p.parsers = svelte.new_parsers()!
	}
	return p.parsers.module_virtual(src)
}

// svelte_javascript_warning is the warning for a .svelte file that is not linted because its
// script is JavaScript.
fn svelte_javascript_warning(path string) string {
	return 'warning: ${path}: not linted: its <script> is JavaScript, and veslint lints only TypeScript (lang="ts")'
}

// svelte_is_typescript: the document's scripts are TypeScript (the `lang` svelte-eslint-parser
// merges over them is ts or typescript), or it has none.
fn svelte_is_typescript(doc &svelte.Document) bool {
	if doc.lang in ['ts', 'typescript'] {
		return true
	}
	if doc.nodes.len == 0 {
		// A document the compiler rejected: decided by the text.
		return !svelte_has_script_tag(doc.src)
	}
	for child in doc.nodes[0].children {
		if doc.nodes[child].typ == .script_element {
			return false
		}
	}
	return true
}

// svelte_has_script_tag: the text has a `<script` start tag.
fn svelte_has_script_tag(src string) bool {
	lower := src.to_lower()
	mut from := 0
	for {
		i := lower.index_after('<script', from) or { return false }
		next := if i + 7 < lower.len { lower[i + 7] } else { `>` }
		if next in [`>`, ` `, `\t`, `\n`, `\r`, `/`] {
			return true
		}
		from = i + 7
	}
	return false
}

// twin_code is the code tsgo is given for a .svelte file (its twin's text) and whether the file
// is linted: not when its script is JavaScript.
fn (mut p SvelteParsers) twin_code(src string) !(string, bool) {
	mut doc := p.parse(src)!
	defer {
		doc.free()
	}
	return doc.virtual_code, svelte_is_typescript(doc)
}

// svelte_report_positions are the line and column ESLint prints for the start (and, with `ends`,
// the end) of each finding of a .svelte file: those of svelte-eslint-parser's locations for a
// report on a node or a token; ESLint's own (offsets.utf16_positions) for one whose rule computes
// its location from the text (Finding.text_loc).
fn svelte_report_positions(doc &svelte.Document, findings []rules.Finding, ends bool) ([]offsets.DisplayPos, []offsets.DisplayPos) {
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
	// A report whose `loc` takes only its start (or only its end) from the text: that side is
	// ESLint's, the other svelte-eslint-parser's (svelte/html-self-closing).
	half_located := findings.filter(it.text_loc_start || it.text_loc_end)
	mut half_starts := []offsets.DisplayPos{}
	mut half_ends := []offsets.DisplayPos{}
	if half_located.len > 0 {
		_, half_starts = offsets.utf16_positions(doc.src, half_located.map(it.stmt))
		_, half_ends = offsets.utf16_positions(doc.src, half_located.map(treesitter.Ident{
			start_byte: if it.stmt.end_byte >= 0 { it.stmt.end_byte } else { it.stmt.start_byte }
			row:        it.stmt.row
		}))
	}
	mut next := 0
	mut next_half := 0
	for f in findings {
		if f.text_loc_start || f.text_loc_end {
			start := doc.loc(f.stmt.start_byte)
			end := doc.loc(if f.stmt.end_byte >= 0 { f.stmt.end_byte } else { f.stmt.start_byte })
			starts << if f.text_loc_start {
				half_starts[next_half]
			} else {
				offsets.DisplayPos{
					line: start.line
					col:  start.column + 1
				}
			}
			if ends {
				end_positions << if f.text_loc_end {
					half_ends[next_half]
				} else {
					offsets.DisplayPos{
						line: end.line
						col:  end.column + 1
					}
				}
			}
			next_half++
			continue
		}
		if f.text_loc {
			starts << text_starts[next]
			if ends {
				end_positions << text_ends[next]
			}
			next++
			continue
		}
		if f.fixed_line != 0 {
			starts << offsets.DisplayPos{
				line: f.fixed_line
				col:  f.fixed_column
			}
			if ends {
				end_positions << offsets.DisplayPos{}
			}
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

// svelte_identifiers are the identifiers of a .svelte file for the type mode (its script and its
// template's expressions): where they are in the file, and their UTF-16 offsets in the twin's
// text (what tsgo is asked).
fn svelte_identifiers(parser treesitter.Parser, doc &svelte.Document, all bool) ([]treesitter.Ident, []int, []offsets.DisplayPos) {
	tree := parser.parse(doc.lint_code) or {
		return []treesitter.Ident{}, []int{}, []offsets.DisplayPos{}
	}
	defer {
		treesitter.tree_delete(tree)
	}
	text := doc.lint_text()
	mut idents := []treesitter.Ident{}
	mut units := []int{}
	mut display := []offsets.DisplayPos{}
	for id in parser.identifiers(tree, text, all) {
		file := doc.lint_to_file(id.start_byte, false)
		if file < 0 {
			continue
		}
		unit := doc.file_to_virtual(file)
		if unit < 0 {
			continue
		}
		idents << treesitter.Ident{
			...id
			start_byte: file
		}
		units << unit
		loc := doc.loc(file)
		display << offsets.DisplayPos{
			line: loc.line
			col:  loc.column + 1
		}
	}
	// In the order of the file.
	mut order := []int{len: idents.len, init: index}
	order.sort_with_compare(fn [idents] (a &int, b &int) int {
		return idents[*a].start_byte - idents[*b].start_byte
	})
	return order.map(idents[it]), order.map(units[it]), order.map(display[it])
}

// prepare_svelte_file is prepare_file for a .svelte file: the identifiers of its script and of
// its template, asked in its twin. A file whose script is JavaScript is skipped with a warning
// (its FileWork is not `svelte`).
fn prepare_svelte_file(mut svelte_parsers SvelteParsers, parser treesitter.Parser, path string, project_override string, all bool, mut bench BenchReport) !FileWork {
	mut sw := time.new_stopwatch()
	src, _, _ := read_source(path)!
	mut doc := svelte_parsers.parse(src) or { return error('${path}: ${err.msg()}') }
	defer {
		doc.free()
	}
	if !svelte_is_typescript(doc) {
		eprintln(svelte_javascript_warning(path))
		return FileWork{}
	}
	if doc.error != none {
		eprintln('warning: ${path}: svelte-eslint-parser rejects it; no types')
		return FileWork{}
	}
	bench.read_parse_ms += ms(sw.elapsed())
	sw.restart()
	idents, utf16, display := svelte_identifiers(parser, doc, all)
	bench.query_ms += ms(sw.elapsed())
	abs_path := os.abs_path(path)
	tsconfig := if project_override != '' { project_override } else { find_tsconfig(abs_path)! }
	bench.files++
	bench.identifiers += idents.len
	return FileWork{
		path:      path
		abs_path:  abs_path
		ts_path:   rules.svelte_twin_path(abs_path)
		tsconfig:  tsconfig
		idents:    idents
		offsets:   utf16
		display:   display
		svelte:    true
		twin_code: doc.virtual_code
	}
}
