module rules

import estree
import time

// Port of the `unicorn/prefer-set-size` rule of eslint-plugin-unicorn 64.0.0 (it has no options),
// with its fix.

const upss_messages = {
	'prefer-set-size': 'Prefer using `Set#size` instead of `Array#length`.'
}

// upss_is_set ports isSet. A variable is a Set when its only definition is a `const` whose kind
// is `const` (definition.kind), which typescript-eslint's definitions do not have: linted as
// TypeScript, only `new Set(…)` itself is one.
fn upss_is_set(t &estree.EsTree, node int) bool {
	return un_is_new(t, node, names: ['Set'])
}

// upss_set_node ports getSetNode: `[...set].length` and `Array.from(set).length`.
fn upss_set_node(t &estree.EsTree, object int) ?int {
	elements := t.list(object, .elements) or { []int{} }
	if t.typ(object) == .array_expression && elements.len == 1 && elements[0] >= 0
		&& t.typ(elements[0]) == .spread_element {
		return t.node(elements[0], .argument)
	}
	if un_is_method_call(t, object,
		objects:          ['Array']
		methods:          ['from']
		arguments_length: 1
		optional_call:    false
		optional_member:  false
	) {
		return (t.list(object, .arguments) or { return none })[0]
	}
	return none
}

fn (mut c Checker) lint_unicorn_prefer_set_size(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .member_expression {
			continue
		}
		stats.checked++
		if !un_is_member(t, node, properties: ['length'], optional: false) {
			continue
		}
		array := t.node(node, .object) or { continue }
		set := upss_set_node(t, array) or { continue }
		if !upss_is_set(t, set) {
			continue
		}
		property := t.node(node, .property) or { continue }
		mut finding := Finding{
			stmt:       c.es_tree_position(t, property)
			message_id: 'prefer-set-size'
		}
		if tokens.comments_inside(t.nodes[array].start, t.nodes[array].end).len <= tokens.comments_inside(t.nodes[set].start,
			t.nodes[set].end).len {
			mut fixes := [
				fix_replace_range(t.nodes[property].start, t.nodes[property].end, 'size'),
				fix_replace_range(t.nodes[array].start, t.nodes[array].end, c.un_text(t, set)),
			]
			if t.typ(array) == .array_expression {
				fixes << c.un_fix_space_around_keyword(t, tokens, node)
			}
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
