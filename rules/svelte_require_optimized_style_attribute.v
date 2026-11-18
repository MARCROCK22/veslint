module rules

// Port of the `svelte/require-optimized-style-attribute` rule of eslint-plugin-svelte 3.24.1: a
// `style` attribute Svelte cannot optimize: a shorthand `{style}`, one the parser cannot read
// (too complex), and in one it reads, a declaration with an interpolation outside its property
// and value (too complex) or in its property, a comment, or an interpolation between the
// declarations (too complex).

const sroa_messages = {
	'shorthand':        'It cannot be optimized because style attribute is specified using shorthand.'
	'comment':          'It cannot be optimized because contains comments.'
	'interpolationKey': 'It cannot be optimized because property of style declaration contain interpolation.'
	'complex':          'It cannot be optimized because too complex.'
}

fn (mut c Checker) lint_svelte_require_optimized_style_attribute(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes() {
		n := doc.nodes[i]
		if n.typ == .shorthand_attribute {
			if c.sv_ref_name(n.key) == 'style' {
				findings << c.sv_report_snode(i, 'shorthand', {})
			}
			continue
		}
		if n.typ != .attribute || c.sv_attribute_name(i) != 'style' || n.values.len == 0 {
			continue
		}
		style := c.svst_parse_attribute(i) or {
			findings << c.sv_report_snode(i, 'complex', {})
			continue
		}
		for child in style.nodes {
			match child.kind {
				.decl {
					if child.unknown_interps.len > 0 {
						findings << c.sv_report_text(child.start, child.end, 'complex', {})
					} else if child.prop_interps.len > 0 {
						findings << c.sv_report_text(child.prop_start, child.prop_end,
							'interpolationKey', {})
					}
				}
				.comment {
					findings << c.sv_report_text(child.start, child.end, 'comment', {})
				}
				.inline {
					findings << c.sv_report_text(child.start, child.end, 'complex', {})
				}
			}
		}
	}
	return findings
}
