module rules

import estree
import time

// Port of the `unicorn/no-new-buffer` rule of eslint-plugin-unicorn 64.0.0 (it has no options),
// with its fix and its suggestions.

const unnb_messages = {
	'error':         '`new Buffer()` is deprecated, use `Buffer.{{method}}()` instead.'
	'error-unknown': '`new Buffer()` is deprecated, use `Buffer.alloc()` or `Buffer.from()` instead.'
	'suggestion':    'Switch to `Buffer.{{replacement}}()`.'
}

// unnb_infer_method ports inferMethod: `alloc` for a size, `from` for data; none if unknown.
fn (mut c Checker) unnb_infer_method(t &estree.EsTree, args []int) ?string {
	if args.len != 1 {
		return 'from'
	}
	first := args[0]
	if t.typ(first) == .spread_element {
		return none
	}
	if t.typ(first) in [.array_expression, .template_literal] {
		return 'from'
	}
	if c.un_is_number(t, first) {
		return 'alloc'
	}
	result := c.un_static_value(t, first)
	if result.found && result.value.kind in [.string_, .array_] {
		return 'from'
	}
	return none
}

fn (mut c Checker) lint_unicorn_no_new_buffer(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .new_expression {
			continue
		}
		stats.checked++
		if !un_is_new(t, node, names: ['Buffer']) {
			continue
		}
		args := t.list(node, .arguments) or { []int{} }
		if method := c.unnb_infer_method(t, args) {
			has_fix, fix := c.merge_fixes(c.unnb_fix(t, tokens, node, method))!
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'error'
				data:       {
					'method': method
				}
				has_fix:    has_fix
				fix:        fix
			}
			continue
		}
		mut suggestions := []Suggestion{}
		for replacement in ['from', 'alloc'] {
			_, fix := c.merge_fixes(c.unnb_fix(t, tokens, node, replacement))!
			suggestions << Suggestion{
				message_id: 'suggestion'
				data:       {
					'replacement': replacement
				}
				fix:        fix
			}
		}
		findings << Finding{
			stmt:        c.es_tree_position(t, node)
			message_id:  'error-unknown'
			suggestions: suggestions
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) unnb_fix(t &estree.EsTree, tokens &SourceTokens, node int, method string) []Fix {
	callee := t.node(node, .callee) or { return [] }
	mut fixes := [fix_insert_at(t.nodes[callee].end, '.${method}')]
	fixes << c.un_switch_new_to_call(t, tokens, node)
	return fixes
}
