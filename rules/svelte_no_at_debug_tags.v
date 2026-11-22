module rules

// Port of the `svelte/no-at-debug-tags` rule of eslint-plugin-svelte 3.24.1: every `{@debug …}`
// tag is reported, with the suggestion that removes it.

const svnadt_messages = {
	'unexpected':    'Unexpected `{@debug}`.'
	'suggestRemove': 'Remove `{@debug}` from the source'
}

fn (mut c Checker) lint_svelte_no_at_debug_tags(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.debug_tag) {
		n := c.svelte.doc.nodes[i]
		findings << Finding{
			...c.sv_report_snode(i, 'unexpected', {})
			suggestions: [
				Suggestion{
					message_id: 'suggestRemove'
					fix:        Fix{
						start: n.start
						end:   n.end
					}
				},
			]
		}
	}
	return findings
}
