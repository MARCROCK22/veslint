module main

// Dev-time: the postcss/ port's trees as JSON, one line per input line of the file given
// (`{"mode": "css" | "scss" | "template" | "selector", "css": …}`), for tools/postcss_diff.mjs.
import json2
import os
import postcss

fn pos_json(p postcss.Position) map[string]json2.Any {
	return {
		'offset': json2.Any(p.offset)
		'line':   json2.Any(p.line)
		'column': json2.Any(p.column)
	}
}

fn node_json(r &postcss.Root, i int) json2.Any {
	n := r.nodes[i]
	mut m := map[string]json2.Any{}
	m['type'] = n.typ.str()
	m['start'] = pos_json(n.start)
	if n.has_end {
		m['end'] = pos_json(n.end)
	}
	match n.typ {
		.decl {
			m['prop'] = n.prop
			m['value'] = n.value
			m['important'] = n.important
			m['between'] = n.between
		}
		.rule {
			m['selector'] = n.selector
		}
		.atrule {
			m['name'] = n.name
			m['params'] = n.params
		}
		else {}
	}
	if n.has_nodes {
		mut kids := []json2.Any{}
		for k in n.nodes {
			kids << node_json(r, k)
		}
		m['nodes'] = kids
	}
	return m
}

fn sel_json(r &postcss.SelectorRoot, i int) json2.Any {
	n := r.nodes[i]
	mut m := map[string]json2.Any{}
	m['type'] = n.typ.str()
	if n.typ !in [.root, .selector, .attribute] {
		m['value'] = n.value
	}
	if n.has_start {
		m['start'] = '${n.start_line}:${n.start_column}'
	}
	if n.has_end {
		m['end'] = '${n.end_line}:${n.end_column}'
	}
	if n.typ in [.root, .selector, .pseudo] {
		mut kids := []json2.Any{}
		for k in n.nodes {
			kids << sel_json(r, k)
		}
		m['nodes'] = kids
	}
	return m
}

fn main() {
	for line in os.read_lines(os.args[1])! {
		if line == '' {
			continue
		}
		obj := json2.decode[json2.Any](line)!.as_map()
		mode := obj['mode']!.str()
		css := obj['css']!.str()
		if mode == 'selector' {
			r := postcss.parse_selector(css) or {
				println(json2.encode(json2.Any({
					'error': json2.Any(true)
				})))
				continue
			}
			println(json2.encode(sel_json(&r, 0)))
			continue
		}
		opts := match mode {
			'scss' { postcss.ParseOptions{ syntax: .scss, from: 'F' } }
			'template' { postcss.ParseOptions{ safe: true, template: true } }
			else { postcss.ParseOptions{ from: 'F' } }
		}
		r := postcss.parse(postcss.units(css), opts) or {
			println(json2.encode(json2.Any({
				'error': json2.Any(err.msg())
			})))
			continue
		}
		println(json2.encode(node_json(&r, 0)))
	}
}
