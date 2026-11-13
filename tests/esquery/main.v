module main

// The V side of the esquery differential test (tests/esquery/oracle.mjs has the same modes and
// output).
//
//   esq_dump match <selectors> <files> [<shard>/<shards>]
//   esq_dump show <selectors> <index> <files>
//   esq_dump run <groups> <files> [<shard>/<shards>]
//   esq_dump showrun <groups> <index> <files>
//
// Selectors are written one per line as the hexadecimal of their WTF-8 bytes.
import os
import crypto.sha1
import strings
import encoding.hex
import estree
import esquery
import jsregexp
import offsets
import treesitter

struct File {
	path string
	t    estree.EsTree
}

fn load(path string, ts_parser &treesitter.Parser, tsx_parser &treesitter.Parser) File {
	raw := os.read_file(path) or { panic(err) }
	text, _ := offsets.decode_utf8(raw)
	src, _ := offsets.strip_bom(text)
	tsx := path.ends_with('.tsx')
	p := if tsx { tsx_parser } else { ts_parser }
	tree := p.parse(src) or { panic(err) }
	// A regular expression V8 rejects is a Literal whose value is null, as in typescript-estree.
	t := estree.convert_with(treesitter.root_node(tree), src, tsx, estree.Options{
		regexp_valid: fn (pattern string, flags string) bool {
			return jsregexp.regexp_new(estree.utf16_units(pattern), flags) != none
		}
	}) or {
		panic('${path}: ${err}')
	}
	return File{path, t}
}

fn label(t &estree.EsTree, i int) string {
	n := t.nodes[i]
	return '${n.typ.type_name()} ${n.start}-${n.end}'
}

fn match_list(f &File, sel &esquery.Selector) string {
	mut b := strings.new_builder(256)
	b.write_string('F ${f.path}\n')
	nodes := esquery.match_all(&f.t, sel) or {
		// esquery throws at the first node where matching fails: the nodes before it were
		// matched, which the oracle lists too.
		partial := match_until_error(&f.t, sel)
		for i in partial {
			b.write_string(label(&f.t, i) + '\n')
		}
		b.write_string('THROW\n')
		return b.str()
	}
	for i in nodes {
		b.write_string(label(&f.t, i) + '\n')
	}
	return b.str()
}

// match_until_error lists the matches before the node where matching fails.
fn match_until_error(t &estree.EsTree, sel &esquery.Selector) []int {
	mut out := []int{}
	mut ancestry := []int{}
	for step in t.steps() {
		if step.leave {
			ancestry.delete(0)
			continue
		}
		ok := esquery.matches(t, step.node, sel, ancestry) or { return out }
		if ok {
			out << step.node
		}
		ancestry.insert(0, step.node)
	}
	return out
}

fn run_group(f &File, sources []string) string {
	mut parsed := []esquery.EslintSelector{}
	mut indexes := []int{}
	for i, source in sources {
		k := parsed.map(it.source).index(source)
		if k >= 0 {
			indexes[k] = i
			continue
		}
		parsed << esquery.parse_eslint(source) or { return 'PARSEERROR\n' }
		indexes << i
	}
	mut b := strings.new_builder(256)
	b.write_string('F ${f.path}\n')
	calls := esquery.run_parsed(&f.t, parsed, indexes) or {
		// The calls before the failure are made too.
		for c in run_until_error(&f.t, parsed, indexes) {
			b.write_string('${if c.exit { '-' } else { '+' }}${c.selector} ${label(&f.t, c.node)}\n')
		}
		b.write_string('THROW\n')
		return b.str()
	}
	for c in calls {
		b.write_string('${if c.exit { '-' } else { '+' }}${c.selector} ${label(&f.t, c.node)}\n')
	}
	return b.str()
}

// run_until_error is run_parsed up to the failure, one selector at a time.
fn run_until_error(t &estree.EsTree, selectors []esquery.EslintSelector, indexes []int) []esquery.Match {
	mut out := []esquery.Match{}
	mut order := []int{len: selectors.len, init: index}
	order.sort_with_compare(fn [selectors] (a &int, b &int) int {
		return selectors[*a].compare(selectors[*b])
	})
	mut ancestry := []int{}
	for step in t.steps() {
		if step.leave {
			ancestry.delete(0)
		}
		typ := t.typ(step.node).type_name()
		for k in order {
			s := &selectors[k]
			if s.is_exit != step.leave {
				continue
			}
			if types := s.node_types {
				if typ !in types {
					continue
				}
			}
			ok := esquery.matches(t, step.node, s.root, ancestry) or { return out }
			if ok {
				out << esquery.Match{step.node, indexes[k], step.leave}
			}
		}
		if !step.leave {
			ancestry.insert(0, step.node)
		}
	}
	return out
}

fn read_lines(path string) []string {
	return (os.read_lines(path) or { panic(err) }).filter(it != '')
}

fn decode(h string) string {
	return (hex.decode(h) or { panic(err) }).bytestr()
}

fn shard_of(args []string, i int) (int, int) {
	if args.len > i {
		parts := args[i].split('/')
		return parts[0].int(), parts[1].int()
	}
	return 0, 1
}

fn main() {
	ts_parser := treesitter.new_parser() or { panic(err) }
	tsx_parser := treesitter.new_tsx_parser() or { panic(err) }
	args := os.args[1..]
	mode := args[0]
	show := mode in ['show', 'showrun']
	which := if show { args[2].int() } else { -1 }
	files_arg := if show { args[3] } else { args[2] }
	files := read_lines(files_arg).map(load(it, &ts_parser, &tsx_parser))
	shard, shards := if show { 0, 1 } else { shard_of(args, 3) }
	mut out := []string{}
	if mode in ['match', 'show'] {
		for i, line in read_lines(args[1]) {
			if (which >= 0 && i != which) || (which < 0 && i % shards != shard) {
				continue
			}
			sel := esquery.parse(decode(line)) or {
				out << '${i}\tparseerror\t-'
				continue
			}
			text := files.map(match_list(it, &sel)).join('')
			if show {
				print(text)
			} else {
				out << '${i}\tok\t${sha1.hexhash(text)}'
			}
		}
	} else {
		for i, line in read_lines(args[1]) {
			if (which >= 0 && i != which) || (which < 0 && i % shards != shard) {
				continue
			}
			sources := line.split(' ').map(decode(it))
			text := files.map(run_group(it, sources)).join('')
			if show {
				print(text)
			} else {
				out << '${i}\t${sha1.hexhash(text)}'
			}
		}
	}
	if out.len > 0 {
		println(out.join('\n'))
	}
}
