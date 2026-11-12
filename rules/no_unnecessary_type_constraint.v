module rules

import os
import time
import treesitter { next_sibling, node_end, node_field, node_kind, node_parent, position_of }

// Port of the `no-unnecessary-type-constraint` rule of typescript-eslint 8.62.0 (it has no
// options), with its suggestion.

const nutcon_messages = {
	'removeUnnecessaryConstraint': 'Remove the unnecessary `{{constraint}}` constraint.'
	'unnecessaryConstraint':       'Constraining the generic type `{{name}}` to `{{constraint}}` does nothing and is unnecessary.'
}

fn (mut c Checker) lint_no_unnecessary_type_constraint(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	// `<T extends X>` in a function, a class, an interface, an alias or a signature with a type
	// parameter list (TSTypeParameterDeclaration): not a mapped type's key nor an `infer`.
	disambiguation := os.file_ext(abs_path).to_lower() in ['.cts', '.mts', '.tsx']
	for node in c.nodes_of_kind(root, c'type_parameter') {
		list := node_parent(node) or { continue }
		if node_kind(list) != 'type_parameters' {
			continue
		}
		constraint_clause := node_field(node, 'constraint') or { continue }
		checked++
		constraint_type := unwrap_type_parens(first_named(constraint_clause) or { continue })
		constraint := c.text(constraint_type)
		if node_kind(constraint_type) != 'predefined_type' || constraint !in ['any', 'unknown'] {
			continue
		}
		name := node_field(node, 'name') or { continue }
		// In an arrow function of a file where `<T>` could be JSX, a lone parameter keeps a comma.
		in_arrow := node_kind(node_parent(list) or { list }) == 'arrow_function'
		has_default := if _ := node_field(node, 'value') { true } else { false }
		trailing_comma := in_arrow && disambiguation && nutcon_parameter_count(list) == 1
			&& !nutcon_followed_by_comma(node) && !has_default
		_, suggestion := c.suggestion('removeUnnecessaryConstraint', {
			'constraint': constraint
		}, [fix_replace_range(node_end(name), node_end(constraint_type), if trailing_comma {
			','
		} else {
			''
		})])!
		findings << Finding{
			stmt:        position_of(node)
			message_id:  'unnecessaryConstraint'
			data:        {
				'name':       c.text(name)
				'constraint': constraint
			}
			suggestions: [suggestion]
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

fn nutcon_parameter_count(list C.TSNode) int {
	return children_of_kind(list, 'type_parameter').len
}

// nutcon_followed_by_comma: the token after the type parameter is a `,`.
fn nutcon_followed_by_comma(n C.TSNode) bool {
	next := next_sibling(n) or { return false }
	return node_kind(next) == ','
}
