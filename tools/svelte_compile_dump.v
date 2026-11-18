module main

// The V side of tools/svelte_compile_diff.mjs: prints, for each .svelte file of a list, one JSON
// line `{"path": …, "warnings": […], "error": …|null}` with what svelte_compiler gives for the
// file as Svelte 5.56.0's compile(code, {generate: false}) would (positions as
// {line, column}: 1-based lines, 0-based UTF-16 columns).
//
//   svelte_compile_dump json <list>          the files named one per line in <list>
//   svelte_compile_dump bench <list> [runs]  the time to parse and analyze every file
import os
import time
import offsets
import svelte
import svelte_compiler

fn read_source(path string) string {
	raw := os.read_file(path) or { return '' }
	text, _ := offsets.decode_utf8(raw)
	src, _ := offsets.strip_bom(text)
	return src
}

fn loc_json(src string, offset int) string {
	if offset == svelte_compiler.no_pos {
		return 'null'
	}
	mut line := 1
	mut col := 0
	mut i := 0
	for i < offset && i < src.len {
		c := src[i]
		if c == `\n` {
			line++
			col = 0
			i++
			continue
		}
		if c < 0x80 {
			col++
			i++
			continue
		}
		n := utf8_char_len(c)
		col += if n == 4 { 2 } else { 1 }
		i += n
	}
	return '{"line":${line},"column":${col}}'
}

fn custom_element(doc &svelte.Document) bool {
	ca := doc.cast
	if ca.options < 0 {
		return false
	}
	for a in ca.nodes[ca.options].attributes {
		n := ca.nodes[a]
		if n.typ == .attribute && n.name in ['tag', 'customElement'] {
			return true
		}
	}
	return false
}

fn main() {
	if os.args.len < 3 {
		eprintln('usage: svelte_compile_dump json <list> | bench <list> [runs]')
		exit(2)
	}
	files := os.read_lines(os.args[2]) or { panic(err) }
	parsers := svelte.new_parsers() or { panic(err) }
	if os.args[1] == 'bench' {
		runs := if os.args.len > 3 { os.args[3].int() } else { 1 }
		mut sources := []string{}
		for path in files {
			if path != '' {
				sources << read_source(path)
			}
		}
		sw := time.new_stopwatch()
		for _ in 0 .. runs {
			for src in sources {
				mut doc := svelte.parse_svelte_with(src, parsers) or { continue }
				if doc.error == none {
					c := svelte_compiler.build_component(doc, false) or {
						doc.free()
						continue
					}
					svelte_compiler.analyze(c, svelte_compiler.Options{
						custom_element: custom_element(doc)
					})
				}
				doc.free()
			}
		}
		println('${sources.len} files x ${runs}: ${sw.elapsed().milliseconds()} ms')
		return
	}
	mut out := os.stdout()
	for path in files {
		if path == '' {
			continue
		}
		src := read_source(path)
		mut doc := svelte.parse_svelte_with(src, parsers) or {
			out.writeln('{"path":${svelte.json_string(path)},"fatal":${svelte.json_string(err.msg())}}') or {}
			continue
		}
		if e := doc.error {
			out.writeln('{"path":${svelte.json_string(path)},"parse_error":${svelte.json_string(e.message)}}') or {}
			doc.free()
			continue
		}
		mut result := svelte_compiler.Result{}
		mut misses := 0
		if c := svelte_compiler.build_component(doc, false) {
			misses = c.misses
			result = svelte_compiler.analyze(c, svelte_compiler.Options{
				custom_element: custom_element(doc)
			})
		} else {
			if err is svelte_compiler.CompileError {
				result = svelte_compiler.Result{
					error: err
				}
			} else {
				out.writeln('{"path":${svelte.json_string(path)},"fatal":${svelte.json_string(err.msg())}}') or {}
				doc.free()
				continue
			}
		}
		mut ws := []string{}
		for w in result.warnings {
			ws << '{"code":${svelte.json_string(w.code)},"message":${svelte.json_string(w.message)},"start":${loc_json(src, w.start)},"end":${loc_json(src, w.end)}}'
		}
		mut err_json := 'null'
		if e := result.error {
			err_json = '{"code":${svelte.json_string(e.diag.code)},"message":${svelte.json_string(e.diag.message)},"start":${loc_json(src, e.start)},"end":${loc_json(src, e.end)}}'
		}
		out.writeln('{"path":${svelte.json_string(path)},"warnings":[${ws.join(',')}],"error":${err_json},"runes":${result.runes},"misses":${misses}}') or {}
		doc.free()
	}
}
