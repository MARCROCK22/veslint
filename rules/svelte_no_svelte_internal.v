module rules

// Port of the `svelte/no-svelte-internal` rule of eslint-plugin-svelte 3.24.1: an import, a dynamic
// import or a re-export of `svelte/internal` (or of a path under it) is reported. It has no
// conditions: it lints every file.

const svnsi_messages = {
	'unexpected': 'Using svelte/internal is prohibited. This will be removed in Svelte 6.'
}

fn svnsi_is_svelte_internal(value string) bool {
	return value == 'svelte/internal' || value.starts_with('svelte/internal/')
}

fn (mut c Checker) lint_svelte_no_svelte_internal(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() && !c.src.contains('svelte/internal') {
		return []
	}
	e := c.svsc_es(root, abs_path) or { return [] }
	t := e.t
	mut findings := []Finding{}
	for i in e.entered() {
		match t.typ(i) {
			.import_declaration, .import_expression, .export_named_declaration,
			.export_all_declaration {
				source := t.node(i, .source) or { continue }
				value := svsc_string_literal(t, source) or { continue }
				if svnsi_is_svelte_internal(value) {
					findings << c.svsc_report(&e, i, 'unexpected', {})
				}
			}
			else {}
		}
	}
	return findings
}
