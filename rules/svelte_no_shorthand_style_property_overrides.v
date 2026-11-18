module rules

// Port of the `svelte/no-shorthand-style-property-overrides` rule of eslint-plugin-svelte 3.24.1:
// a shorthand property (SHORTHAND_PROPERTIES, with the same vendor prefix) set on an element after
// one of its longhand properties, by its `style` attributes and `style:` directives.

const snspo_messages = {
	'unexpected': "Unexpected shorthand '{{shorthand}}' after '{{original}}'."
}

fn (mut c Checker) lint_svelte_no_shorthand_style_property_overrides(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	mut findings := []Finding{}
	for tag in c.sv_snodes_of(.start_tag) {
		mut before := map[string]bool{}
		for set in c.svst_decl_sets_of_tag(tag) {
			for decl in set {
				prefix := svst_vendor_prefix(decl.prop)
				normalized := decl.prop[prefix.len..]
				longhands := svst_shorthand_properties[normalized] or { continue }
				for longhand in longhands {
					with_prefix := prefix + longhand
					if with_prefix !in before {
						continue
					}
					findings << c.svst_report_decl(decl, 'unexpected', {
						'shorthand': decl.prop
						'original':  with_prefix
					})
				}
			}
			for decl in set {
				before[decl.prop] = true
			}
		}
	}
	return findings
}
