module rules

// Port of the `svelte/no-dupe-style-properties` rule of eslint-plugin-svelte 3.24.1: a property
// set twice on an element, by its `style` attributes (their declarations, and those of the string
// and template literals of their interpolations) and its `style:` directives, is reported at each
// place (once each).

const sndsp_messages = {
	'unexpected': "Duplicate property '{{name}}'."
}

fn (mut c Checker) lint_svelte_no_dupe_style_properties(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	mut findings := []Finding{}
	for tag in c.sv_snodes_of(.start_tag) {
		sets := c.svst_decl_sets_of_tag(tag)
		// Each declaration by its place in `sets` (the objects upstream keeps in a Set).
		mut reported := map[string]bool{}
		mut before := map[string]string{}
		mut decls := map[string]SvstDecl{}
		for k, set in sets {
			for j, decl in set {
				id := '${k}:${j}'
				decls[id] = decl
				if already := before[decl.prop] {
					for r in [already, id] {
						if r !in reported {
							d := decls[r]
							findings << c.svst_report_decl(d, 'unexpected', {
								'name': d.prop
							})
							reported[r] = true
						}
					}
				}
			}
			for j, decl in set {
				before[decl.prop] = '${k}:${j}'
			}
		}
	}
	return findings
}
