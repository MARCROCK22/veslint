module main

// The V side of the differential test: converts files with the estree module and serializes the
// trees like tests/estree/oracle.mjs.
//
//   estree_dump hash <list> [<shard>/<shards>]   prints `path\tstatus\tsha1` per input
//   estree_dump dump <file>                       prints the serialization of one file
//   estree_dump time <file> [<runs>]              times parse and conversion
//
// status: `ok`, or `tserror` when tree-sitter has ERROR or MISSING nodes.
import os
import time
import crypto.sha1
import strings
import estree
import jsregexp
import offsets
import treesitter

// read_source reads a file as veslint (and ESLint) does: decoded as UTF-8 with U+FFFD for
// invalid bytes, without BOM.
fn read_source(path string) string {
	raw := os.read_file(path) or { return '' }
	text, _ := offsets.decode_utf8(raw)
	src, _ := offsets.strip_bom(text)
	return src
}

fn convert_file(path string, ts_parser &treesitter.Parser, tsx_parser &treesitter.Parser) ?(estree.EsTree, &C.TSTree) {
	src := read_source(path)
	p := if path.ends_with('.tsx') { tsx_parser } else { ts_parser }
	tree := p.parse(src) or { return none }
	t := estree.convert_with(treesitter.root_node(tree), src, path.ends_with('.tsx'), options(path)) or {
		treesitter.tree_delete(tree)
		return none
	}
	return t, tree
}

fn main() {
	ts_parser := treesitter.new_parser() or { panic(err) }
	tsx_parser := treesitter.new_tsx_parser() or { panic(err) }
	mode := os.args[1]
	match mode {
		'dump' {
			t, tree := convert_file(os.args[2], &ts_parser, &tsx_parser) or {
				eprintln('tree-sitter error')
				exit(1)
			}
			print(t.serialize())
			treesitter.tree_delete(tree)
		}
		'traverse' {
			t, tree := convert_file(os.args[2], &ts_parser, &tsx_parser) or {
				eprintln('tree-sitter error')
				exit(1)
			}
			print(traversal(t))
			treesitter.tree_delete(tree)
		}
		'hash' {
			files := os.read_lines(os.args[2]) or { panic(err) }
			mut shard, mut shards := 0, 1
			if os.args.len > 3 {
				parts := os.args[3].split('/')
				shard, shards = parts[0].int(), parts[1].int()
			}
			for k, file in files {
				if file == '' || k % shards != shard {
					continue
				}
				t, tree := convert_file(file, &ts_parser, &tsx_parser) or {
					println('${file}\ttserror\t-')
					continue
				}
				println('${file}\tok\t${sha1.hexhash(t.serialize())}:${sha1.hexhash(traversal(t))}')
				treesitter.tree_delete(tree)
			}
		}
		'time' {
			runs := if os.args.len > 3 { os.args[3].int() } else { 5 }
			time_file(os.args[2], runs, &ts_parser, &tsx_parser)
		}
		else {
			eprintln('usage: estree_dump hash|dump|time …')
			exit(2)
		}
	}
}

// traversal lists the enter and leave events of the traversal, like the oracle's.
fn traversal(t estree.EsTree) string {
	mut b := strings.new_builder(t.nodes.len * 40)
	for step in t.steps() {
		n := t.nodes[step.node]
		b.write_string('${if step.leave { '-' } else { '+' }}${n.typ.type_name()} ${n.start}-${n.end}\n')
	}
	return b.str()
}

// time_file times the parse and the conversion of a file `runs` times.
fn time_file(path string, runs int, ts_parser &treesitter.Parser, tsx_parser &treesitter.Parser) {
	src := read_source(path)
	p := if path.ends_with('.tsx') { tsx_parser } else { ts_parser }
	for _ in 0 .. runs {
		mut sw := time.new_stopwatch()
		tree := p.parse(src) or { panic(err) }
		parse_ms := sw.elapsed().microseconds() / 1000.0
		sw.restart()
		t := estree.convert_with(treesitter.root_node(tree), src, path.ends_with('.tsx'), options(path)) or {
			panic(err)
		}
		conv_ms := sw.elapsed().microseconds() / 1000.0
		println('parse ${parse_ms:.1f} ms, convert ${conv_ms:.1f} ms, ${t.nodes.len} nodes, ${src.len} bytes')
		treesitter.tree_delete(tree)
	}
}

// options are those of typescript-estree's parse for the file: without sourceType, a .mts is a
// module.
fn options(path string) estree.Options {
	return estree.Options{
		module:       path.to_lower().ends_with('.mts') || os.getenv('ORACLE_MODULE') != ''
		// ESTREE_FORCE: convert also a tree with errors (to check that the conversion survives).
		allow_errors: os.getenv('ESTREE_FORCE') != ''
		regexp_valid: fn (pattern string, flags string) bool {
			return jsregexp.regexp_new(estree.utf16_units(pattern), flags) != none
		}
	}
}
