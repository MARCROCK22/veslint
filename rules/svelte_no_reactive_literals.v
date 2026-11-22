module rules

// Port of the `svelte/no-reactive-literals` rule of eslint-plugin-svelte 3.24.1: a `$:` statement
// that assigns a literal, `[]` or `{}` is reported, with a suggestion that makes it a `let`
// declaration. Its conditions leave runes mode out.

const svnrl_messages = {
	'noReactiveLiterals': 'Do not assign literal values inside reactive statements unless absolutely necessary.'
	'fixReactiveLiteral': 'Move the literal out of the reactive statement into an assignment'
}

fn (mut c Checker) lint_svelte_no_reactive_literals(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
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
		right := es.node(assignment, .right) or { continue }
		literal := match es.typ(right) {
			.literal { true }
			.array_expression { (es.list(right, .elements) or { [0] }).len == 0 }
			.object_expression { (es.list(right, .properties) or { [0] }).len == 0 }
			else { false }
		}
		if !literal {
			continue
		}
		n := es.nodes[statement]
		has, fix := c.merge_fixes([
			fix_insert_at(n.start, 'let ${c.sv_es_text(assignment)}'),
			fix_replace_range(n.start, n.end, ''),
		]) or { false, Fix{} }
		findings << Finding{
			...c.sv_report_es(statement, 'noReactiveLiterals', {})
			suggestions: if has {
				[Suggestion{
					message_id: 'fixReactiveLiteral'
					fix:        fix
				}]
			} else {
				[]Suggestion{}
			}
		}
	}
	return findings
}
