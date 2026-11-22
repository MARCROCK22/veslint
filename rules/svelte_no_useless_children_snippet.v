module rules

// Port of the `svelte/no-useless-children-snippet` rule of eslint-plugin-svelte 3.24.1 (Svelte 5):
// a `{#snippet children()}` without parameters directly in an element is its content already.

const snucs_messages = {
	'uselessSnippet': 'Found an unnecessary children snippet.'
}

fn (mut c Checker) lint_svelte_no_useless_children_snippet(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.snippet_block) {
		n := doc.nodes[i]
		if n.parent >= 0 && doc.nodes[n.parent].typ == .element && c.sv_ref_name(n.id) == 'children'
			&& n.params.len == 0 {
			findings << c.sv_report_snode(i, 'uselessSnippet', {})
		}
	}
	return findings
}
