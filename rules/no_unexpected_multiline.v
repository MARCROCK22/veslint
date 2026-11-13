module rules

import time
import treesitter { node_field, node_kind, node_start }

// Port of the `no-unexpected-multiline` rule of ESLint 10.6.0 (it has no options).

const num_messages = {
	'function':       'Unexpected newline between function and ( of function call.'
	'property':       'Unexpected newline between object and [ of property access.'
	'taggedTemplate': 'Unexpected newline between template tag and template literal.'
	'division':       'Unexpected newline between numerator and division operator.'
}

fn (mut c Checker) lint_no_unexpected_multiline(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	tokens := c.source_tokens(root)
	for node in c.nodes_of_kinds(root, ['subscript_expression', 'call_expression', 'binary_expression'], []) {
		stats.checked++
		match node_kind(node) {
			'subscript_expression' {
				if is_optional_element(node) {
					continue
				}
				c.num_check_break_after(root, node_field(node, 'object') or { continue }, 'property', mut
					findings)
			}
			'call_expression' {
				args := node_field(node, 'arguments') or { continue }
				if node_kind(args) == 'template_string' {
					// A TaggedTemplateExpression: the token before the template.
					before := tokens.before(node_start(args), false) or { continue }
					if es_has_line_break(c.src[before.end..node_start(args)]) {
						findings << Finding{
							stmt:       c.position_at(node_start(args))
							message_id: 'taggedTemplate'
						}
					}
					continue
				}
				if is_optional_element(node)
					|| !(call_arguments(node) or { []C.TSNode{} }).any(node_kind(it) != 'comment') {
					continue
				}
				c.num_check_break_after(root, node_field(node, 'function') or { continue }, 'function', mut
					findings)
			}
			else {
				// `a\n/ b / g`: a `/` whose left side is a `/` followed by a name like regexp flags.
				if operator_of(node) != '/' {
					continue
				}
				inner := unwrap_parens(node_field(node, 'left') or { continue })
				if node_kind(inner) != 'binary_expression' || operator_of(inner) != '/' {
					continue
				}
				mut slash := tokens.after(c.es_end(inner), false) or { continue }
				for c.src[slash.start..slash.end] != '/' {
					slash = tokens.after(slash.end, false) or { break }
				}
				after := tokens.after(slash.end, false) or { continue }
				text := c.src[after.start..after.end]
				if after.kind == .identifier && text.len > 0
					&& text.bytes().all(it in [`g`, `i`, `m`, `s`, `u`, `y`]) && slash.end == after.start {
					c.num_check_break_after(root, node_field(inner, 'left') or { continue }, 'division', mut
						findings)
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// num_check_break_after ports checkForBreakAfter: a line break before the token that follows the
// node (its closing parentheses aside).
fn (mut c Checker) num_check_break_after(root C.TSNode, n C.TSNode, message_id string, mut findings []Finding) {
	tokens := c.source_tokens(root)
	mut open := tokens.after(c.es_end(unwrap_parens(n)), false) or { return }
	for c.src[open.start..open.end] == ')' {
		open = tokens.after(open.end, false) or { return }
	}
	end := tokens.before(open.start, false) or { return }
	if es_has_line_break(c.src[end.end..open.start]) {
		findings << Finding{
			stmt:       c.position_at(open.start)
			message_id: message_id
		}
	}
}
