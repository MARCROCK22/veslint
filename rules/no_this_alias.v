module rules

import json2
import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-this-alias` rule of typescript-eslint 8.62.0, with its options
// `allowDestructuring` and `allowedNames`.

const nta_messages = {
	'thisAssignment':  "Unexpected aliasing of 'this' to local variable."
	'thisDestructure': "Unexpected aliasing of members of 'this' to local variables."
}

struct NtaOptions {
	allow_destructuring bool
	allowed_names       []string
}

fn nta_options(options []json2.Any) !NtaOptions {
	o := option_object(no_this_alias, options, ['allowDestructuring', 'allowedNames'])!
	return NtaOptions{
		allow_destructuring: o.bool_value('allowDestructuring')!
		allowed_names:       o.string_list('allowedNames')!
	}
}

fn (mut c Checker) lint_no_this_alias(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nta_options(c.rule_options(no_this_alias))!
	mut findings := []Finding{}
	mut checked := 0
	// `VariableDeclarator[init.type='ThisExpression']` and
	// `AssignmentExpression[right.type='ThisExpression']`, whatever the operator (`x ||= this`).
	for node in c.nodes_of_kinds(root, ['variable_declarator', 'assignment_expression',
		'augmented_assignment_expression'], []) {
		is_declarator := node_kind(node) == 'variable_declarator'
		value := node_field(node, if is_declarator { 'value' } else { 'right' }) or { continue }
		if node_kind(unwrap_parens(value)) != 'this' {
			continue
		}
		target := node_field(node, if is_declarator { 'name' } else { 'left' }) or { continue }
		// The id of the declarator, or the left side of the assignment (a pattern, a member…).
		id := unwrap_parens(target)
		checked++
		is_identifier := estree_type(id) == 'Identifier'
		if o.allow_destructuring && !is_identifier {
			continue
		}
		if is_identifier && c.identifier_name(id) in o.allowed_names {
			continue
		}
		findings << Finding{
			stmt:       position_of(id)
			message_id: if is_identifier { 'thisAssignment' } else { 'thisDestructure' }
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}
