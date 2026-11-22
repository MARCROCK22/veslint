module rules

import estree
import time

// Port of the `unicorn/no-useless-collection-argument` rule of eslint-plugin-unicorn 79.0.0 (it
// has no options), with its fix and suggestion.

const unuca_messages = {
	'no-useless-collection-argument/error':      'The {{description}} is useless.'
	'no-useless-collection-argument/suggestion': 'Remove the {{description}}'
}

fn (mut c Checker) lint_unicorn_no_useless_collection_argument(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for new_expression in 0 .. t.nodes.len {
		if !un_is_new(t, new_expression,
			names:            ['Set', 'Map', 'WeakSet', 'WeakMap']
			arguments_length: 1
		) {
			continue
		}
		stats.checked++
		iterable := (t.list(new_expression, .arguments) or { continue })[0]
		is_checking_fallback := t.typ(iterable) == .logical_expression
			&& (t.string_of(iterable, .operator) or { '' }) == '??'
		node := if is_checking_fallback { t.node(iterable, .right) or { continue } } else { iterable }
		description := c.unuca_description(t, node)
		if description == '' {
			continue
		}
		fixes := if is_checking_fallback {
			c.unuca_remove_fallback(t, tokens, node) or { []Fix{} }
		} else {
			if f := c.un_remove_argument(t, tokens, node) { [f] } else { []Fix{} }
		}
		// A fix could drop or move a comment inside the argument, so only suggest it.
		removal := c.un_argument_removal_range(t, tokens, iterable) or { continue }
		should_use_suggestion := un_has_comment_in_range(tokens, removal.start, removal.end)
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'no-useless-collection-argument/error'
			data:       {
				'description': description
			}
		}
		if fixes.len > 0 {
			has_fix, fix := c.merge_fixes(fixes)!
			if has_fix {
				if should_use_suggestion {
					finding = Finding{
						...finding
						suggestions: [
							Suggestion{
								message_id: 'no-useless-collection-argument/suggestion'
								data:       {
									'description': description
								}
								fix:        fix
							},
						]
					}
				} else {
					finding = Finding{
						...finding
						has_fix: true
						fix:     fix
					}
				}
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unuca_description ports getDescription ('' for a value that is not useless).
fn (c &Checker) unuca_description(t &estree.EsTree, node int) string {
	if un_is_empty_array(t, node) {
		return 'empty array'
	}
	if (un_static_string_value(t, node) or { 'x' }) == '' {
		return 'empty string'
	}
	if c.unb_is_null_literal(t, node) {
		return '`null`'
	}
	if un_is_undefined(t, node) {
		return '`undefined`'
	}
	return ''
}

// unuca_remove_fallback ports removeFallback (the fix of no-useless-fallback-in-spread, without its
// check of comments).
fn (c &Checker) unuca_remove_fallback(t &estree.EsTree, tokens &SourceTokens, node int) ?[]Fix {
	logical := t.nodes[node].parent
	left := t.node(logical, .left)?
	left_parenthesized := c.un_is_parenthesized(t, tokens, left)
	_, start := c.un_parenthesized_range(t, tokens, left)
	end := t.nodes[logical].end
	mut fixes := [fix_remove_range(start, end)]
	if left_parenthesized || t.typ(left) != .sequence_expression {
		fixes << c.un_remove_parentheses(t, tokens, logical)
	}
	return fixes
}
