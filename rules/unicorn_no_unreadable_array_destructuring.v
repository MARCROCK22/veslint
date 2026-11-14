module rules

import time

// Port of the `unicorn/no-unreadable-array-destructuring` rule of eslint-plugin-unicorn 64.0.0 (it
// has no options), with its fix.

const unuad_messages = {
	'no-unreadable-array-destructuring': 'Array destructuring may not contain consecutive ignored values.'
}

fn (mut c Checker) lint_unicorn_no_unreadable_array_destructuring(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .array_pattern {
			continue
		}
		stats.checked++
		elements := t.list(node, .elements) or { continue }
		mut consecutive := false
		for i in 0 .. elements.len - 1 {
			if elements[i] < 0 && elements[i + 1] < 0 {
				consecutive = true
				break
			}
		}
		if elements.len < 3 || !consecutive {
			continue
		}
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'no-unreadable-array-destructuring'
		}
		parent := t.nodes[node].parent
		non_null := elements.filter(it >= 0)
		init := t.node(parent, .init) or { -1 }
		if t.typ(parent) == .variable_declarator && t.node(parent, .id) or { -1 } == node && init >= 0
			&& non_null.len == 1 && t.typ(non_null[0]) != .assignment_pattern {
			element := non_null[0]
			index := elements.index(element)
			is_slice := t.typ(element) == .rest_element
			variable := if is_slice { t.node(element, .argument) or { continue } } else { element }
			mut fixes := [
				fix_replace_range(t.nodes[node].start, t.nodes[node].end, c.un_text(t, variable)),
			]
			code := if is_slice { '.slice(${index})' } else { '[${index}]' }
			if !c.un_is_parenthesized(t, tokens, init) && c.un_member_object_needs_parens(t, tokens, init) {
				fixes << fix_insert_at(t.nodes[init].start, '(')
				fixes << fix_insert_at(t.nodes[parent].end, ')${code}')
			} else {
				fixes << fix_insert_at(t.nodes[parent].end, code)
			}
			fixes << c.un_fix_space_around_keyword(t, tokens, node)
			has_fix, fix := c.merge_fixes(fixes)!
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
