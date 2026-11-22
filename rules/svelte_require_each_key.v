module rules

// Port of the `svelte/require-each-key` rule of eslint-plugin-svelte 3.24.1: an `{#each}` block
// with an item (`as x`) needs a key; the report goes from the block's start to the `}` after the
// item (or the index).

const svrek_messages = {
	'expectedKey': 'Each block should have a key'
}

fn (mut c Checker) lint_svelte_require_each_key(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.each_block) {
		n := doc.nodes[i]
		if n.context.idx < 0 || n.key_expr.idx >= 0 {
			continue
		}
		_, last_end := c.sv_ref_range(if n.index_ref.idx >= 0 { n.index_ref } else { n.context })
		brace := c.sv_token_after(last_end, false) or { continue }
		findings << c.sv_report(n.start, if brace.loc_end >= 0 { brace.loc_end } else { brace.end },
			'expectedKey', {})
	}
	return findings
}
