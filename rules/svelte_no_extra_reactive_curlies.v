module rules

// Port of the `svelte/no-extra-reactive-curlies` rule of eslint-plugin-svelte 3.24.1: a `$:`
// statement whose body is a block of one statement (`SvelteReactiveStatement >
// BlockStatement[body.length=1]`) is reported, with a suggestion that removes the braces. Its
// conditions leave runes mode out.

const svnerc_messages = {
	'extraCurlies':       'Do not wrap reactive statements in curly braces unless necessary.'
	'removeExtraCurlies': 'Remove the unnecessary curly braces.'
}

fn (mut c Checker) lint_svelte_no_extra_reactive_curlies(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.svsc_runes_off(abs_path) {
		return []
	}
	es := &c.svelte.doc.es
	mut findings := []Finding{}
	for statement in c.svsc_reactive_statements() {
		block := es.node(statement, .body) or { continue }
		if es.typ(block) != .block_statement || (es.list(block, .body) or { []int{} }).len != 1 {
			continue
		}
		n := es.nodes[block]
		tokens := c.sv_tokens_in(n.start, n.end, true)
		if tokens.len < 2 {
			continue
		}
		has, fix := c.merge_fixes([
			fix_replace_range(tokens[0].start, tokens[1].start, ''),
			fix_replace_range(tokens[tokens.len - 2].end, tokens[tokens.len - 1].end, ''),
		]) or { false, Fix{} }
		findings << Finding{
			...c.sv_report_es(block, 'extraCurlies', {})
			suggestions: if has {
				[Suggestion{
					message_id: 'removeExtraCurlies'
					fix:        fix
				}]
			} else {
				[]Suggestion{}
			}
		}
	}
	return findings
}
