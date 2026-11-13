module main

// The V side of the differential test of the code path analysis: converts files with the estree
// module, runs codepath.analyze and writes the events like tests/codepath/oracle.mjs.
//
//   codepath_dump hash <list> [<shard>/<shards>]   prints `path\tstatus\tsha1` per input
//   codepath_dump dump <file>                       prints the events of one file
//   codepath_dump time <file> [<runs>]              times parse, conversion and analysis
//
// status: `ok`, or `tserror` when tree-sitter has ERROR or MISSING nodes.
import os
import time
import crypto.sha1
import strings
import estree
import jsregexp
import codepath
import offsets
import treesitter

fn read_source(path string) string {
	raw := os.read_file(path) or { return '' }
	text, _ := offsets.decode_utf8(raw)
	src, _ := offsets.strip_bom(text)
	return src
}

// options are those ESLint gives typescript-eslint's parser: sourceType `module`.
fn options() estree.Options {
	return estree.Options{
		module:       true
		regexp_valid: fn (pattern string, flags string) bool {
			return jsregexp.regexp_new(estree.utf16_units(pattern), flags) != none
		}
	}
}

fn convert_file(path string, ts_parser &treesitter.Parser, tsx_parser &treesitter.Parser) ?(estree.EsTree, &C.TSTree) {
	src := read_source(path)
	p := if path.ends_with('.tsx') { tsx_parser } else { ts_parser }
	tree := p.parse(src) or { return none }
	t := estree.convert_with(treesitter.root_node(tree), src, path.ends_with('.tsx'), options()) or {
		treesitter.tree_delete(tree)
		return none
	}
	return t, tree
}

fn main() {
	ts_parser := treesitter.new_parser() or { panic(err) }
	tsx_parser := treesitter.new_tsx_parser() or { panic(err) }
	if os.args.len < 3 {
		eprintln('usage: codepath_dump hash|dump|time …')
		exit(2)
	}
	match os.args[1] {
		'dump' {
			t, tree := convert_file(os.args[2], &ts_parser, &tsx_parser) or {
				eprintln('tree-sitter error')
				exit(1)
			}
			print(serialize(t, codepath.analyze(t)))
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
				println('${file}\tok\t${sha1.hexhash(serialize(t, codepath.analyze(t)))}')
				treesitter.tree_delete(tree)
			}
		}
		'time' {
			runs := if os.args.len > 3 { os.args[3].int() } else { 5 }
			time_file(os.args[2], runs, &ts_parser, &tsx_parser)
		}
		else {
			eprintln('usage: codepath_dump hash|dump|time …')
			exit(2)
		}
	}
}

fn node_text(t &estree.EsTree, i int) string {
	n := t.nodes[i]
	return '${n.typ.type_name()} ${n.start}-${n.end}'
}

fn ids(an &codepath.Analysis, segs []int) string {
	return '[' + segs.map(an.segment_id(it)).join(',') + ']'
}

fn segment_text(an &codepath.Analysis, seg int) string {
	s := an.segments[seg]
	return 'r=${int(s.reachable)} used=${int(s.used)} prev=${ids(an, s.prev_segments)} next=${ids(an, s.next_segments)} allPrev=${ids(an, s.all_prev_segments)} allNext=${ids(an, s.all_next_segments)} looped=${ids(an, s.looped_prev_segments)}'
}

// walk runs traverseSegments: `skip_every` > 0 calls skip() on every visited segment whose
// position (from 0) modulo skip_every is 1, `break_at` > 0 calls break() on the segment at that
// position.
fn walk(an &codepath.Analysis, cp int, opts codepath.TraverseOptions, skip_every int, break_at int) []int {
	mut out := []int{}
	mut w := an.walk_segments(cp, opts)
	for {
		seg := w.next() or { break }
		k := out.len
		out << seg
		if skip_every > 0 && k % skip_every == 1 {
			w.skip()
		}
		if break_at > 0 && k == break_at {
			w.stop()
		}
	}
	return out
}

fn code_path_text(an &codepath.Analysis, cp int) string {
	c := an.code_paths[cp]
	plain := walk(an, cp, codepath.TraverseOptions{}, 0, 0)
	skipped := walk(an, cp, codepath.TraverseOptions{}, 3, 0)
	broken := walk(an, cp, codepath.TraverseOptions{}, 0, 3)
	first := if plain.len > 1 {
		ids(an, walk(an, cp, codepath.TraverseOptions{ first: plain[1] }, 0, 0))
	} else {
		'-'
	}
	last := if c.final_segments.len > 0 {
		ids(an, walk(an, cp, codepath.TraverseOptions{ last: c.final_segments[0] }, 0, 0))
	} else {
		'-'
	}
	children := '[' + c.child_code_paths.map(an.code_path_id(it)).join(',') + ']'
	return 'initial=${an.segment_id(c.initial_segment)} final=${ids(an, c.final_segments)} returned=${ids(an, c.returned_segments)} thrown=${ids(an, c.thrown_segments)} children=${children} traverse=${ids(an, plain)} skip=${ids(an, skipped)} break=${ids(an, broken)} first=${first} last=${last}'
}

// serialize writes one line per event, in the format of tests/codepath/oracle.mjs.
fn serialize(t &estree.EsTree, an &codepath.Analysis) string {
	mut b := strings.new_builder(an.events.len * 60)
	for ev in an.events {
		match ev.kind {
			.enter_node {
				b.write_string('+${node_text(t, ev.node)}\n')
			}
			.leave_node {
				b.write_string('-${node_text(t, ev.node)}\n')
			}
			.code_path_start {
				c := an.code_paths[ev.code_path]
				upper := if c.upper >= 0 { an.code_path_id(c.upper) } else { '-' }
				b.write_string('${ev.kind.listener_name()} ${an.code_path_id(ev.code_path)} origin=${c.origin} upper=${upper} @${node_text(t, ev.node)}\n')
			}
			.code_path_end {
				b.write_string('${ev.kind.listener_name()} ${an.code_path_id(ev.code_path)} @${node_text(t, ev.node)} ${code_path_text(an, ev.code_path)}\n')
			}
			.segment_loop {
				b.write_string('${ev.kind.listener_name()} ${an.segment_id(ev.segment)} ${an.segment_id(ev.to_segment)} @${node_text(t, ev.node)}\n')
			}
			else {
				b.write_string('${ev.kind.listener_name()} ${an.segment_id(ev.segment)} @${node_text(t, ev.node)} ${segment_text(an, ev.segment)}\n')
			}
		}
	}
	return b.str()
}

fn time_file(path string, runs int, ts_parser &treesitter.Parser, tsx_parser &treesitter.Parser) {
	src := read_source(path)
	p := if path.ends_with('.tsx') { tsx_parser } else { ts_parser }
	for _ in 0 .. runs {
		mut sw := time.new_stopwatch()
		tree := p.parse(src) or { panic(err) }
		parse_ms := sw.elapsed().microseconds() / 1000.0
		sw.restart()
		t := estree.convert_with(treesitter.root_node(tree), src, path.ends_with('.tsx'),
			options()) or { panic(err) }
		conv_ms := sw.elapsed().microseconds() / 1000.0
		sw.restart()
		an := codepath.analyze(t)
		cpa_ms := sw.elapsed().microseconds() / 1000.0
		println('parse ${parse_ms:.1f} ms, convert ${conv_ms:.1f} ms, code paths ${cpa_ms:.1f} ms: ${t.nodes.len} nodes, ${an.events.len} events, ${an.segments.len} segments, ${an.code_paths.len} code paths, ${src.len} bytes')
		treesitter.tree_delete(tree)
	}
}
