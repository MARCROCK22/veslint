module rules

import time
import treesitter { node_field, node_kind, node_start, position_of }

// Port of the `prefer-numeric-literals` rule of ESLint 10.6.0, with its fix (it has no options).

const pnl_messages = {
	'useLiteral': 'Use {{system}} literals instead of {{functionName}}().'
}

fn (mut c Checker) lint_prefer_numeric_literals(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	tokens := c.source_tokens(root)
	for node in c.nodes_of_kinds(root, ['call_expression'], []) {
		args := (call_arguments(node) or { continue }).filter(node_kind(it) != 'comment')
		if args.len != 2 {
			continue
		}
		stats.checked++
		string_node := unwrap_parens(args[0])
		radix_node := unwrap_parens(args[1])
		if node_kind(string_node) !in ['string', 'template_string'] || node_kind(radix_node) != 'number'
			|| c.text(radix_node).ends_with('n') {
			continue
		}
		str := c.es_static_string_value(string_node) or { continue }
		radix := number_literal_value(c.text(radix_node)) or { continue }
		system, prefix := match radix {
			2 { 'binary', '0b' }
			8 { 'octal', '0o' }
			16 { 'hexadecimal', '0x' }
			else { continue }
		}
		callee := node_field(node, 'function') or { continue }
		if !c.es_is_specific_id(callee, 'parseInt')
			&& !c.es_is_specific_member_access(callee, 'Number', 'parseInt') {
			continue
		}
		start := node_start(node)
		end := c.es_end(node)
		// The fix keeps the value: only the digits of the radix.
		digits := match int(radix) {
			2 { '01' }
			8 { '01234567' }
			else { '0123456789abcdefABCDEF' }
		}
		mut has_fix := str.len > 0 && str.bytes().all(digits.contains(it.ascii_str()))
			&& tokens.comments_inside(start, end).len == 0
		replacement := '${prefix}${str}'
		mut text := replacement
		if has_fix {
			if before := tokens.before(start, false) {
				if before.end == start
					&& !es_can_adjacent(before.kind, c.src[before.start..before.end], .numeric, replacement) {
					text = ' ' + text
				}
			}
			if after := tokens.after(end, false) {
				if end == after.start
					&& !es_can_adjacent(.numeric, replacement, after.kind, c.src[after.start..after.end]) {
					text += ' '
				}
			}
		}
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'useLiteral'
			data:       {
				'system':       system
				'functionName': c.es_text(unwrap_parens(callee))
			}
			has_fix:    has_fix
			fix:        fix_replace_range(start, end, text)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
