module rules

import estree
import time

// Port of the `unicorn/no-new-buffer` rule of eslint-plugin-unicorn 79.0.0 (it has no options),
// with its fix and its suggestions.

const unnb_messages = {
	'error':         '`new Buffer()` is deprecated, use `Buffer.{{method}}()` instead.'
	'error-unknown': '`new Buffer()` is deprecated, use `Buffer.alloc()` or `Buffer.from()` instead.'
	'suggestion':    'Switch to `Buffer.{{replacement}}()`.'
}

// unnb_infer_method ports inferMethod: `alloc` for a size, `from` for data; none if unknown.
fn (mut c Checker) unnb_infer_method(mut ctx UnCtx, args []int) ?string {
	t := ctx.t
	if args.len == 0 {
		return 'from'
	}
	first := args[0]
	if t.typ(first) == .spread_element {
		return none
	}
	// A number selects allocation, which `Buffer.from()` would throw on.
	if c.un_is_number(mut ctx, first) {
		return 'alloc'
	}
	if t.typ(first) in [.array_expression, .template_literal] {
		return 'from'
	}
	// A string encoding selects `Buffer.from()` for any input.
	if args.len > 1 {
		if second := c.un_static_value_for_control_flow(mut ctx, args[1]) {
			if second.value.kind == .string_ {
				return 'from'
			}
		}
	}
	if result := c.un_static_value_for_control_flow(mut ctx, first) {
		if result.value.kind in [.string_, .array_] {
			return 'from'
		}
	}
	return none
}

// unnb_can_remove_ignored_arguments ports canRemoveIgnoredArguments: the allocation drops the
// arguments after the size, which must have no comments and no side effects.
fn (c &Checker) unnb_can_remove_ignored_arguments(t &estree.EsTree, tokens &SourceTokens, node int, args []int) bool {
	if args.len < 2 {
		return true
	}
	comma := c.un_token_after_punctuator(tokens, t.nodes[args[0]].end, ',') or { return false }
	return !un_has_comment_in_range(tokens, comma.start, t.nodes[node].end)
		&& args[1..].all(!un_has_side_effect(t, it))
}

fn (mut c Checker) lint_unicorn_no_new_buffer(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .new_expression {
			continue
		}
		stats.checked++
		if !un_is_new(t, node, names: ['Buffer']) {
			continue
		}
		args := t.list(node, .arguments) or { []int{} }
		if method := c.unnb_infer_method(mut ctx, args) {
			mut finding := Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'error'
				data:       {
					'method': method
				}
			}
			if method != 'alloc' || args.len == 1 {
				has_fix, fix := c.merge_fixes(c.unnb_fix(t, tokens, node, method))!
				finding = Finding{
					...finding
					has_fix: has_fix
					fix:     fix
				}
			} else if c.unnb_can_remove_ignored_arguments(t, tokens, node, args) {
				_, fix := c.merge_fixes(c.unnb_fix(t, tokens, node, method))!
				finding = Finding{
					...finding
					suggestions: [
						Suggestion{
							message_id: 'suggestion'
							data:       {
								'replacement': method
							}
							fix:        fix
						},
					]
				}
			}
			findings << finding
			continue
		}
		mut suggestions := []Suggestion{}
		for replacement in ['from', 'alloc'] {
			if replacement == 'alloc' && !c.unnb_can_remove_ignored_arguments(t, tokens, node, args) {
				continue
			}
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
	mut fixes := []Fix{}
	// The allocation takes only the size: extra arguments could add a fill.
	if method == 'alloc' {
		args := t.list(node, .arguments) or { []int{} }
		for i := args.len - 1; i >= 1; i-- {
			fixes << c.un_remove_argument(t, tokens, args[i]) or { continue }
		}
	}
	fixes << fix_insert_at(t.nodes[callee].end, '.${method}')
	fixes << c.un_switch_new_to_call(t, tokens, node)
	return fixes
}
