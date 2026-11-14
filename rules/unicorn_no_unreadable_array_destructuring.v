module rules

import json2
import time

// Port of the `unicorn/no-unreadable-array-destructuring` rule of eslint-plugin-unicorn 79.0.0,
// with its fix.

const unuad_messages = {
	'ignored-elements':    'Array destructuring may not contain consecutive ignored values.'
	'property-assignment': 'Do not assign destructured values to object properties.'
}

fn unuad_options(options []json2.Any) !int {
	o := option_object(unicorn_no_unreadable_array_destructuring, options, ['maximumIgnoredElements'])!
	value := o.values['maximumIgnoredElements'] or { return 1 }
	return value.int()
}

fn (mut c Checker) lint_unicorn_no_unreadable_array_destructuring(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	maximum := unuad_options(c.rule_options(unicorn_no_unreadable_array_destructuring))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := &UnbTypeContext{
		root:     root
		abs_path: abs_path
		stats:    unsafe { &stats }
	}
	for node in 0 .. t.nodes.len {
		if t.typ(node) == .member_expression {
			stats.checked++
			pattern := unb_parent_pattern(t, node)
			if pattern >= 0 && t.typ(pattern) == .array_pattern {
				findings << Finding{
					stmt:       c.es_tree_position(t, node)
					message_id: 'property-assignment'
				}
			}
			continue
		}
		if t.typ(node) != .array_pattern {
			continue
		}
		stats.checked++
		elements := t.list(node, .elements) or { continue }
		// getMaximumConsecutiveIgnoredElements
		mut most := 0
		mut run := 0
		for element in elements {
			if element < 0 {
				run++
				if run > most {
					most = run
				}
			} else {
				run = 0
			}
		}
		if most <= maximum {
			continue
		}
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'ignored-elements'
		}
		parent := t.nodes[node].parent
		non_null := elements.filter(it >= 0)
		init := t.node(parent, .init) or { -1 }
		if t.typ(parent) == .variable_declarator && t.node(parent, .id) or { -1 } == node && init >= 0
			&& non_null.len == 1 {
			element := non_null[0]
			index := elements.index(element)
			is_slice := t.typ(element) == .rest_element
			variable := if is_slice { t.node(element, .argument) or { continue } } else { element }
			// The pattern becomes the variable alone: comments outside it and the annotation of the
			// pattern would be lost. Destructuring reads through the iterator protocol while `[…]`
			// and `.slice(…)` read by index, so the source must be indexable; `.slice()` of a typed
			// array is no array.
			if t.typ(element) == .assignment_pattern || t.node(node, .type_annotation) != none
				|| c.unb_is_known_non_target(t, init, unb_indexed_collection_options(), mut ctx)
				|| (is_slice && c.unb_is_known_non_target(t, init, unb_array_options(), mut ctx))
				|| c.unb_would_remove_comments(tokens, unb_node_range(t, node), [
				unb_node_range(t, variable),
			], false) {
				findings << finding
				continue
			}
			mut fixes := [
				fix_replace_range(t.nodes[node].start, t.nodes[node].end, c.un_text(t, variable)),
			]
			code := if is_slice { '.slice(${index})' } else { '[${index}]' }
			if !c.un_is_parenthesized(t, tokens, init)
				&& c.unb_member_object_needs_parens(t, tokens, init, -1) {
				fixes << fix_insert_at(t.nodes[init].start, '(')
				fixes << fix_insert_at(t.nodes[parent].end, ')${code}')
			} else {
				fixes << fix_insert_at(t.nodes[parent].end, code)
			}
			fixes << c.unb_fix_space_around_keyword(t, tokens, node)
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
