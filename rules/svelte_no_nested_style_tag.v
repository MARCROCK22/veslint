module rules

// Port of the `svelte/no-nested-style-tag` rule of eslint-plugin-svelte 3.24.1: a `<style>` that is
// an HTML element (not the component's top-level style) is reported.

const snnst_messages = {
	'nestedStyle': 'Nested `<style>` elements are not scoped and may lead to unintended styles being applied.'
}

fn (mut c Checker) lint_svelte_no_nested_style_tag(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.element) {
		n := doc.nodes[i]
		if n.kind != 'html' || n.name_ref.es || n.name_ref.idx < 0
			|| doc.nodes[n.name_ref.idx].typ != .name || doc.nodes[n.name_ref.idx].name != 'style' {
			continue
		}
		findings << c.sv_report_snode(i, 'nestedStyle', {})
	}
	return findings
}
