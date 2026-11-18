module rules

// Port of the `svelte/no-at-html-tags` rule of eslint-plugin-svelte 3.24.1: every `{@html …}` tag
// (a SvelteMustacheTag of kind raw) is reported.

const svnaht_messages = {
	'unexpected': '`{@html}` can lead to XSS attack.'
}

fn (mut c Checker) lint_svelte_no_at_html_tags(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.mustache_tag) {
		if c.svelte.doc.nodes[i].kind == 'raw' {
			findings << c.sv_report_snode(i, 'unexpected', {})
		}
	}
	return findings
}
