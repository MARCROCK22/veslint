module rules

import json2

// Port of the `svelte/shorthand-attribute` rule of eslint-plugin-svelte 3.24.1: with prefer
// "always" (the default) `name={name}` should be `{name}`; with "never" `{name}` should be
// `name={name}`. Both fix.

const svsha_messages = {
	'expectedShorthand': 'Expected shorthand attribute.'
	'expectedRegular':   'Expected regular attribute syntax.'
}

fn svsha_options(options []json2.Any) !bool {
	o := option_object(svelte_shorthand_attribute, options, ['prefer'])!
	return o.string_value('prefer', ['always', 'never'])! != 'never'
}

fn (mut c Checker) lint_svelte_shorthand_attribute(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	always := svsha_options(c.rule_options(svelte_shorthand_attribute))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	if !always {
		for i in c.sv_snodes_of(.shorthand_attribute) {
			n := doc.nodes[i]
			findings << Finding{
				...c.sv_report_snode(i, 'expectedRegular', {})
				has_fix: true
				fix:     Fix{
					start: n.start
					end:   n.start
					text:  '${c.sv_attribute_name(i)}='
				}
			}
		}
		return findings
	}
	for i in c.sv_snodes_of(.attribute) {
		n := doc.nodes[i]
		if n.values.len != 1 {
			continue
		}
		value := doc.nodes[n.values[0]]
		if value.typ != .mustache_tag || value.expression.idx < 0 || !value.expression.es
			|| doc.es.nodes[value.expression.idx].typ != .identifier {
			continue
		}
		if c.sv_attribute_name(i) != c.sv_ref_name(value.expression) {
			continue
		}
		mut finding := c.sv_report_snode(i, 'expectedShorthand', {})
		if q := c.sv_attribute_value_quote_and_range(i) {
			fixes := if q.quote in ['double', 'single'] {
				[Fix{
					start: n.start
					end:   q.first.end
				}, Fix{
					start: q.last.start
					end:   q.last.end
				}]
			} else {
				[Fix{
					start: n.start
					end:   q.start
				}]
			}
			has_fix, fix := c.merge_fixes(fixes)!
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
		findings << finding
	}
	return findings
}
