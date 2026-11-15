module rules

import time

// Port of the `marcrock/uppercase-first-class-letter` rule of @marcrock22/eslintcf 0.0.1
// (src/rules/uppercaseFirstClassLetterRule.ts; it has no options): the name of a class declaration
// that starts with a lower-case ASCII letter.

const mufc_messages = {
	'uppercaseFirstClassLeter': 'Start this name with an upper-case letter.'
}

fn (mut c Checker) lint_marcrock_uppercase_first_class_letter(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .class_declaration {
			continue
		}
		stats.checked++
		id := t.node(node, .id) or { continue }
		name := t.string_of(id, .name) or { continue }
		// /^[a-z]/.test(node.id.name)
		if name == '' || name[0] < `a` || name[0] > `z` {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, id)
			message_id: 'uppercaseFirstClassLeter'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
