module rules

import json2

// Port of the `svelte/spaced-html-comment` rule of eslint-plugin-svelte 3.24.1: with "always" (the
// default) an HTML comment that is not blank needs white space after `<!--` and before `-->`;
// with "never" a space or tab there (not a line break) is reported. Both fix.

const sshc_messages = {
	'expectedSpaceBefore':   "Expected space or tab before '-->' in comment."
	'expectedSpaceAfter':    "Expected space or tab after '<!--' in comment."
	'unexpectedSpaceBefore': "Unexpected space or tab before '-->' in comment."
	'unexpectedSpaceAfter':  "Unexpected space or tab after '<!--' in comment."
}

fn sshc_options(options []json2.Any) !bool {
	if options.len == 0 {
		return true
	}
	value := options[0]
	if value is string && value in ['always', 'never'] {
		return value != 'never'
	}
	return error('the option of `${svelte_spaced_html_comment}` must be "always" or "never"')
}

fn (mut c Checker) lint_svelte_spaced_html_comment(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	require_space := sshc_options(c.rule_options(svelte_spaced_html_comment))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.html_comment) {
		n := doc.nodes[i]
		runes := n.value.runes()
		if runes.all(is_js_space(it)) {
			continue
		}
		first := runes[0]
		last := runes.last()
		if require_space {
			if !is_js_space(first) {
				findings << Finding{
					...c.sv_report_snode(i, 'expectedSpaceAfter', {})
					has_fix: true
					fix:     Fix{
						start: n.start + 4
						end:   n.start + 4
						text:  ' '
					}
				}
			}
			if !is_js_space(last) {
				findings << Finding{
					...c.sv_report_snode(i, 'expectedSpaceBefore', {})
					has_fix: true
					fix:     Fix{
						start: n.end - 3
						end:   n.end - 3
						text:  ' '
					}
				}
			}
			continue
		}
		// /^[^\S\n\r]/: a white space that is not a line break.
		if is_js_space(first) && first !in [`\n`, `\r`] {
			findings << Finding{
				...c.sv_report_snode(i, 'unexpectedSpaceAfter', {})
				has_fix: true
				fix:     Fix{
					start: n.start + 4
					end:   n.start + 4 + utf8_char_len(n.value[0])
				}
			}
		}
		// /(?<=\S)[^\S\n\r]$/
		if runes.len >= 2 && is_js_space(last) && last !in [`\n`, `\r`]
			&& !is_js_space(runes[runes.len - 2]) {
			width := last.str().len
			findings << Finding{
				...c.sv_report_snode(i, 'unexpectedSpaceBefore', {})
				has_fix: true
				fix:     Fix{
					start: n.end - 3 - width
					end:   n.end - 3
				}
			}
		}
	}
	return findings
}
