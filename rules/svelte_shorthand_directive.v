module rules

import json2

// Port of the `svelte/shorthand-directive` rule of eslint-plugin-svelte 3.24.1: with prefer
// "always" (the default) `bind:x={x}`, `class:x={x}` and `style:x={x}` should be `bind:x`,
// `class:x` and `style:x`; with "never" the other way round. Both fix.

const svshd_messages = {
	'expectedShorthand': 'Expected shorthand directive.'
	'expectedRegular':   'Expected regular directive syntax.'
}

fn svshd_options(options []json2.Any) !bool {
	o := option_object(svelte_shorthand_directive, options, ['prefer'])!
	return o.string_value('prefer', ['always', 'never'])! != 'never'
}

// svshd_always is reportForAlways: the fix removes the `=` and the value with its quotes.
fn (c &Checker) svshd_always(i int) !Finding {
	mut finding := c.sv_report_snode(i, 'expectedShorthand', {})
	q := c.sv_attribute_value_quote_and_range(i) or { return finding }
	eq := c.sv_token_before(q.first.start, false) or { return finding }
	has_fix, fix := c.merge_fixes([Fix{
		start: eq.start
		end:   eq.end
	}, Fix{
		start: q.start
		end:   q.end
	}])!
	return Finding{
		...finding
		has_fix: has_fix
		fix:     fix
	}
}

// svshd_never is reportForNever: the fix writes `={name}` after the key's name.
fn (c &Checker) svshd_never(i int) Finding {
	doc := c.svelte.doc
	key := doc.nodes[doc.nodes[i].key.idx]
	_, name_end := c.sv_ref_range(key.key)
	return Finding{
		...c.sv_report_snode(i, 'expectedRegular', {})
		has_fix: true
		fix:     Fix{
			start: name_end
			end:   name_end
			text:  '={${c.sv_ref_name(key.key)}}'
		}
	}
}

fn (mut c Checker) lint_svelte_shorthand_directive(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	always := svshd_options(c.rule_options(svelte_shorthand_directive))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes() {
		n := doc.nodes[i]
		if n.typ == .directive {
			if n.kind !in ['Binding', 'Class'] || n.expression.idx < 0 || !n.expression.es
				|| doc.es.nodes[n.expression.idx].typ != .identifier
				|| c.sv_directive_key_name(i) != c.sv_ref_name(n.expression) {
				continue
			}
		} else if n.typ == .style_directive {
			if always {
				if n.shorthand || n.values.len != 1 {
					continue
				}
				value := doc.nodes[n.values[0]]
				if value.typ != .mustache_tag || value.expression.idx < 0 || !value.expression.es
					|| doc.es.nodes[value.expression.idx].typ != .identifier
					|| c.sv_ref_name(value.expression) != c.sv_directive_key_name(i) {
					continue
				}
			}
		} else {
			continue
		}
		if always {
			if !n.shorthand {
				findings << c.svshd_always(i)!
			}
		} else if n.shorthand {
			findings << c.svshd_never(i)
		}
	}
	return findings
}
