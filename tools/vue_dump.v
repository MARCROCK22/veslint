module main

// The V side of tools/vue_parse_diff.mjs: prints, for each .vue file of a list, one JSON line
// `{"path": …, "value": …}` with what vue.Document.to_json gives (or `{"fatal": …}`).
//
//   vue_dump json <list>          the files named one per line in <list>
//   vue_dump time <file> [runs]   the time to parse a file
//   vue_dump bench <list> [runs]  the time to parse every file of the list (read beforehand)
import os
import time
import offsets
import vue

fn read_source(path string) string {
	raw := os.read_file(path) or { return '' }
	text, _ := offsets.decode_utf8(raw)
	src, _ := offsets.strip_bom(text)
	return src
}

fn main() {
	if os.args.len < 3 {
		eprintln('usage: vue_dump json <list> | vue_dump time <file> [runs]')
		exit(2)
	}
	match os.args[1] {
		'json' {
			files := os.read_lines(os.args[2]) or { panic(err) }
			parsers := vue.new_parsers() or { panic(err) }
			mut out := os.stdout()
			for path in files {
				if path == '' {
					continue
				}
				src := read_source(path)
				mut doc := vue.parse_sfc_with(src, vue.Options{}, parsers) or {
					out.writeln('{"path":${vue.json_string(path)},"value":{"fatal":{"message":${vue.json_string(err.msg())},"index":null}}}') or {}
					continue
				}
				out.writeln('{"path":${vue.json_string(path)},"value":${doc.to_json()}}') or {}
				doc.free()
			}
		}
		'bench' {
			files := os.read_lines(os.args[2]) or { panic(err) }
			runs := if os.args.len > 3 { os.args[3].int() } else { 1 }
			mut sources := []string{}
			mut bytes := 0
			for path in files {
				if path != '' {
					sources << read_source(path)
					bytes += sources.last().len
				}
			}
			parsers := vue.new_parsers() or { panic(err) }
			sw := time.new_stopwatch()
			for _ in 0 .. runs {
				for src in sources {
					mut doc := vue.parse_sfc_with(src, vue.Options{}, parsers) or { continue }
					doc.free()
				}
			}
			ms := f64(sw.elapsed().microseconds()) / 1000 / runs
			println('${sources.len} files, ${bytes} bytes: ${ms:.1f} ms per run')
		}
		'time' {
			src := read_source(os.args[2])
			runs := if os.args.len > 3 { os.args[3].int() } else { 100 }
			parsers := vue.new_parsers() or { panic(err) }
			sw := time.new_stopwatch()
			for _ in 0 .. runs {
				mut doc := vue.parse_sfc_with(src, vue.Options{}, parsers) or { panic(err) }
				doc.free()
			}
			println('${f64(sw.elapsed().microseconds()) / runs} us per parse')
		}
		else {
			eprintln('unknown mode')
			exit(2)
		}
	}
}
