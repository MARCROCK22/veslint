module rules

import estree

// Port of the `svelte/no-reactive-functions` rule of eslint-plugin-svelte 3.24.1: a `$:` statement
// that assigns a function is reported, with a suggestion that turns `$:` into `const`. Its
// conditions leave runes mode out.

const svnrf_messages = {
	'noReactiveFns':  'Do not create functions inside reactive statements unless absolutely necessary.'
	'fixReactiveFns': 'Move the function out of the reactive statement'
}

fn (mut c Checker) lint_svelte_no_reactive_functions(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.svsc_runes_off(abs_path) {
		return []
	}
	es := &c.svelte.doc.es
	mut findings := []Finding{}
	for statement in c.svsc_reactive_statements() {
		body := es.node(statement, .body) or { continue }
		if es.typ(body) != .expression_statement {
			continue
		}
		assignment := es.node(body, .expression) or { continue }
		if es.typ(assignment) != .assignment_expression {
			continue
		}
		// `AssignmentExpression > :function`: one report per function child.
		for side in [estree.Key.left, .right] {
			child := es.node(assignment, side) or { continue }
			if !svsc_is_function(es, child) {
				continue
			}
			n := es.nodes[statement]
			tokens := c.sv_tokens_in(n.start, n.end, false)
			mut suggestions := []Suggestion{}
			if tokens.len >= 3 {
				// isSpaceBetween: any gap from the `:` to the next token (comments are not space).
				mut end := tokens[1].end
				mut space := false
				for token in c.sv_tokens_between(tokens[1].end, tokens[2].start, true) {
					if token.start != end {
						space = true
					}
					end = token.end
				}
				if end != tokens[2].start {
					space = true
				}
				suggestions << Suggestion{
					message_id: 'fixReactiveFns'
					fix:        fix_replace_range(tokens[0].start, tokens[1].end, if space {
						'const'
					} else {
						'const '
					})
				}
			}
			findings << Finding{
				...c.sv_report_es(statement, 'noReactiveFns', {})
				suggestions: suggestions
			}
		}
	}
	return findings
}
