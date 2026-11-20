module main

import json2
import offsets
import os
import rules
import tsgo
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

// parse parses a .vue file with the vueFeatures of its configuration (vue_parse_options).
fn (mut p VueParsers) parse(src string, options vue.Options) !&vue.Document {
	if p.parsers == unsafe { nil } {
		p.parsers = vue.new_parsers()!
	}
	return vue.parse_sfc_with(src, options, p.parsers)
}

// vue_parse_options are the vueFeatures vue-eslint-parser parses the .vue file at `abs_path`
// with: its configuration's parserOptions.vueFeatures. Without a configuration (the type mode),
// the defaults.
fn (l &LoadedConfig) vue_parse_options(abs_path string) vue.Options {
	index := l.file_config[abs_path] or { 0 }
	if index < l.configs.len {
		return l.configs[index].language.vue_features
	}
	return vue.Options{}
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
fn (mut p VueParsers) twin_code(src string, options vue.Options) !(string, bool) {
	mut doc := p.parse(src, options)!
	defer {
		doc.free()
	}
	return doc.script.code, doc.script.lang != .js
}

// include_twins makes sure that the tsconfig of each .vue file has its twin in its program, as
// typescript-eslint has the .vue file in it with extraFileExtensions ['.vue']: a tsconfig that
// lists its `include` or its `files` may leave the twin out (`src/**/*.vue` does not match
// `App.vue.vls.ts`). tsgo is then given that tsconfig with the missing twins added to its `files`
// (its readFile callback serves it). `twins` are the twins of each tsconfig. Returns the tsconfig
// files it served.
fn include_twins(mut client tsgo.Client, twins map[string][]string) ![]string {
	mut served := []string{}
	for tsconfig, paths in twins {
		parsed := client.parse_config_file(tsconfig)!
		mut keys := map[string]bool{}
		for name in parsed.file_names {
			keys[tsgo.path_key(name)] = true
		}
		missing := paths.filter(tsgo.path_key(it) !in keys)
		if missing.len == 0 {
			continue
		}
		text := os.read_file(tsconfig) or { continue }
		raw := json2.decode[json2.Any](strip_jsonc(text)) or { continue }
		if raw !is map[string]json2.Any {
			continue
		}
		mut config := raw.as_map().clone()
		// Without either, the default `include` (**/*) matches the twin already.
		if 'include' !in config && 'files' !in config {
			continue
		}
		mut listed := []json2.Any{}
		if files := config['files'] {
			if files is []json2.Any {
				listed = files.clone()
			}
		}
		for path in missing {
			listed << json2.Any(path)
		}
		config['files'] = json2.Any(listed)
		client.serve(tsconfig, json2.encode(json2.Any(config)))
		served << tsconfig
	}
	return served
}

// vue_report_positions are the line and column ESLint prints for the start (and, with `ends`, the
// end) of each finding of a .vue file: those of vue-eslint-parser's locations, whose lines end
// only at a line feed, for a report on a node or a token; ESLint's own (offsets.utf16_positions)
// for one whose rule computes its location from the text (Finding.text_loc).
fn vue_report_positions(doc &vue.Document, findings []rules.Finding, ends bool) ([]offsets.DisplayPos, []offsets.DisplayPos) {
	mut starts := []offsets.DisplayPos{cap: findings.len}
	mut end_positions := []offsets.DisplayPos{}
	text_located := findings.filter(it.text_loc || it.text_loc_start || it.text_loc_end)
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
		if f.line_loc {
			starts << offsets.DisplayPos{
				line: f.fixed_line
				col:  f.fixed_column
			}
			if ends {
				end_positions << offsets.DisplayPos{
					line: f.fixed_end_line
					col:  f.fixed_end_column
				}
			}
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
		if f.text_loc_start || f.text_loc_end {
			loc := doc.loc(f.stmt.start_byte)
			starts << if f.text_loc_start {
				text_starts[next]
			} else {
				offsets.DisplayPos{
					line: loc.line
					col:  loc.column + 1
				}
			}
			if ends {
				end := doc.loc(if f.stmt.end_byte >= 0 {
					f.stmt.end_byte
				} else {
					f.stmt.start_byte
				})
				end_positions << if f.text_loc_end {
					text_ends[next]
				} else {
					offsets.DisplayPos{
						line: end.line
						col:  end.column + 1
					}
				}
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

// vue_identifiers are the identifiers of the script of a .vue file for the type mode: where they
// are in the file, and their UTF-16 offsets in the twin's text (what tsgo is asked).
fn vue_identifiers(parser treesitter.Parser, doc &vue.Document, all bool) !([]treesitter.Ident, []int, []offsets.DisplayPos) {
	script := &doc.script
	if script.tree == unsafe { nil } {
		return []treesitter.Ident{}, []int{}, []offsets.DisplayPos{}
	}
	idents := parser.identifiers(script.tree, doc.src, all)!.filter(script.file_to_synthetic(it.start_byte,
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
