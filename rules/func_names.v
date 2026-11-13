module rules

import json2
import time
import treesitter { node_field, node_kind, node_parent }

// Port of the `func-names` rule of ESLint 10.6.0, with its options.

const fn_messages = {
	'unnamed': 'Unexpected unnamed {{name}}.'
	'named':   'Unexpected named {{name}}.'
}

struct FnOptions {
	value      string
	generators string // '' when not set
}

// fn_options reads "always", "as-needed" or "never", and `generators`.
fn fn_options(options []json2.Any) !FnOptions {
	values := ['always', 'as-needed', 'never']
	value := if options.len > 0 { options[0] } else { json2.Any('always') }
	if value !is string || value.str() !in values {
		return error('the first option of `${func_names}` must be "always", "as-needed" or "never"')
	}
	o := option_object(func_names, if options.len > 1 { options[1..] } else { []json2.Any{} },
		['generators'])!
	generators := o.values['generators'] or { json2.Any('') }
	if generators !is string || (generators.str() != '' && generators.str() !in values) {
		return error('the option `generators` of `${func_names}` must be "always", "as-needed" or "never"')
	}
	return FnOptions{
		value:      value.str()
		generators: generators.str()
	}
}

fn (mut c Checker) lint_func_names(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := fn_options(c.rule_options(func_names))!
	mut findings := []Finding{}
	kinds := ['function_expression', 'generator_function', 'method_definition', 'function_declaration',
		'generator_function_declaration']
	for node in c.nodes_of_kinds(root, kinds, []) {
		kind := node_kind(node)
		// A FunctionDeclaration only as `export default`: the anonymous one is a function
		// expression for tree-sitter.
		parent := node_parent(node) or { continue }
		is_declaration := node_kind(parent) == 'export_statement'
			&& kind in ['function_expression', 'generator_function', 'function_declaration',
				'generator_function_declaration']
		if kind in ['function_declaration', 'generator_function_declaration'] && !is_declaration {
			continue
		}
		if kind == 'method_definition' && node_field(node, 'body') == none {
			continue
		}
		stats.checked++
		id := es_function_id(node)
		// A name the function refers to itself by is needed.
		if name := id {
			tree := c.scope_tree(root)
			v := tree.declared_variable(name)
			if v >= 0 && tree.variables[v].defs.len > 0 && tree.variables[v].defs[0].kind == .function_name
				&& tree.variables[v].references.len > 0 {
				continue
			}
		}
		has_name := id != none
		config := if es_is_generator_function(node) && o.generators != '' {
			o.generators
		} else {
			o.value
		}
		is_method := kind == 'method_definition'
		mut message_id := ''
		if config == 'never' {
			if has_name && !is_declaration {
				message_id = 'named'
			}
		} else if config == 'as-needed' {
			if !has_name && !c.fn_has_inferred_name(node) {
				message_id = 'unnamed'
			}
		} else if !has_name && !is_method {
			message_id = 'unnamed'
		}
		if message_id != '' {
			findings << Finding{
				stmt:       function_head(node)
				message_id: message_id
				data:       {
					'name': c.es_function_name_with_kind(node)
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// fn_has_inferred_name ports hasInferredName: a method, or a function that gets the name of the
// variable, property or assignment target it is the value of.
fn (c &Checker) fn_has_inferred_name(f C.TSNode) bool {
	if node_kind(f) == 'method_definition' {
		return true
	}
	parent := cti_estree_parent(f) or { return false }
	is_value := fn (field string, parent C.TSNode, f C.TSNode) bool {
		value := node_field(parent, field) or { return false }
		return node_key(unwrap_parens(value)) == node_key(f)
	}
	match node_kind(parent) {
		'variable_declarator' {
			name := node_field(parent, 'name') or { return false }
			return node_kind(name) == 'identifier' && is_value('value', parent, f)
		}
		'pair', 'public_field_definition' {
			return is_value('value', parent, f)
		}
		'assignment_expression', 'augmented_assignment_expression', 'assignment_pattern',
		'object_assignment_pattern' {
			left := unwrap_parens(node_field(parent, 'left') or { return false })
			return node_kind(left) in ['identifier', 'undefined',
				'shorthand_property_identifier_pattern']
				&& is_value('right', parent, f)
		}
		'required_parameter', 'optional_parameter' {
			pattern := node_field(parent, 'pattern') or { return false }
			return node_kind(pattern) == 'identifier' && is_value('value', parent, f)
		}
		else {
			return false
		}
	}
}
