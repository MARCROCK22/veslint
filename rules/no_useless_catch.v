module rules

import time
import treesitter { named_children, node_field, node_kind, node_parent, position_of }

// Port of the `no-useless-catch` rule of ESLint 10.6.0 (it has no options).

const nuca_messages = {
	'unnecessaryCatchClause': 'Unnecessary catch clause.'
	'unnecessaryCatch':       'Unnecessary try/catch wrapper.'
}

fn (mut c Checker) lint_no_useless_catch(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['catch_clause'], []) {
		stats.checked++
		param := node_field(node, 'parameter') or { continue }
		if node_kind(param) != 'identifier' {
			continue
		}
		body := node_field(node, 'body') or { continue }
		statements := named_children(body).filter(node_kind(it) != 'comment')
		if statements.len == 0 || node_kind(statements[0]) != 'throw_statement' {
			continue
		}
		argument := unwrap_parens(first_named(statements[0]) or { continue })
		if node_kind(argument) !in ['identifier', 'undefined']
			|| c.identifier_name(argument) != c.identifier_name(param) {
			continue
		}
		try := node_parent(node) or { continue }
		if _ := node_field(try, 'finalizer') {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unnecessaryCatchClause'
			}
		} else {
			findings << Finding{
				stmt:       position_of(try)
				message_id: 'unnecessaryCatch'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
