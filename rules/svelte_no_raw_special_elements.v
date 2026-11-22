module rules

// Port of the `svelte/no-raw-special-elements` rule of eslint-plugin-svelte 3.24.1: the HTML
// elements head, body, window, document, element and options are Svelte 4's special elements,
// written `svelte:<name>` in Svelte 5; the fix adds the prefix to the start and end tags.

const snrse_messages = {
	'deprecatedElement': 'Special {{name}} element is deprecated in v5, use svelte:{{name}} instead.'
}

const snrse_names = ['head', 'body', 'window', 'document', 'element', 'options']

fn (mut c Checker) lint_svelte_no_raw_special_elements(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.element) {
		n := doc.nodes[i]
		if n.kind != 'html' {
			continue
		}
		name := c.sv_ref_name(n.name_ref)
		if name !in snrse_names {
			continue
		}
		mut fixes := [Fix{
			start: n.start + 1
			end:   n.start + 1
			text:  'svelte:'
		}]
		if n.end_tag >= 0 {
			at := doc.nodes[n.end_tag].start + 2
			fixes << Fix{
				start: at
				end:   at
				text:  'svelte:'
			}
		}
		has_fix, fix := c.merge_fixes(fixes)!
		findings << Finding{
			...c.sv_report_snode(i, 'deprecatedElement', {
				'name': name
			})
			has_fix: has_fix
			fix:     fix
		}
	}
	return findings
}
