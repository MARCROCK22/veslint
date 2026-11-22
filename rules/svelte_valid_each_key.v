module rules

import svelte

// Port of the `svelte/valid-each-key` rule of eslint-plugin-svelte 3.24.1: the key of an
// `{#each}` block must use a variable the block defines (its item, its index, or one of its
// expression), read through the scope of the key (svelte-eslint-parser's scope manager).

const svvek_messages = {
	'keyUseEachVars': 'Expected key to use the variables which are defined by the `{#each}` block.'
}

fn (mut c Checker) lint_svelte_valid_each_key(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	info := &doc.scope
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.each_block) {
		n := doc.nodes[i]
		if n.key_expr.idx < 0 {
			continue
		}
		key_start, key_end := c.sv_ref_range(n.key_expr)
		mut ranges := [][2]int{}
		for r in [n.context, n.index_ref, n.expression] {
			if r.idx >= 0 {
				s, e := c.sv_ref_range(r)
				ranges << [s, e]!
			}
		}
		scope := c.sv_scope_of(n.key_expr)
		mut uses := false
		for v in info.scopes[scope].variables {
			variable := info.variables[v]
			iteration := variable.defs.any(fn [ranges, doc] (d svelte.SDef) bool {
				name := doc.es.nodes[d.name]
				return ranges.any(it[0] <= name.start && name.end <= it[1])
			})
			if !iteration {
				continue
			}
			for ref in variable.references {
				id := doc.es.nodes[info.references[ref].identifier]
				if key_start <= id.start && id.end <= key_end {
					uses = true
					break
				}
			}
			if uses {
				break
			}
		}
		if !uses {
			findings << c.sv_report_ref(n.key_expr, 'keyUseEachVars', {})
		}
	}
	return findings
}
