module rules

import json2
import time
import treesitter { node_field, node_kind, node_parent, position_of }

// Port of the `no-restricted-globals` rule of ESLint 10.6.0.

const nrg_messages = {
	'defaultMessage': "Unexpected use of '{{name}}'."
	'customMessage':  "Unexpected use of '{{name}}'. {{customMessage}}"
}

const nrg_global_objects = ['globalThis', 'self', 'window']

struct NrgOptions {
	messages            map[string]string // restricted name -> custom message ('' for none)
	check_global_object bool
	global_objects      []string
}

fn nrg_options(options []json2.Any) !NrgOptions {
	mut list := options.clone()
	mut check := false
	mut objects := nrg_global_objects.clone()
	if options.len > 0 && options[0] is map[string]json2.Any {
		first := options[0].as_map()
		if globals := first['globals'] {
			list = if globals is []json2.Any { globals.clone() } else { []json2.Any{} }
			if value := first['checkGlobalObject'] {
				check = value is bool && value as bool
			}
			if value := first['globalObjects'] {
				if value is []json2.Any {
					for item in value {
						if item is string && item !in objects {
							objects << item
						}
					}
				}
			}
		}
	}
	mut messages := map[string]string{}
	for item in list {
		if item is string {
			messages[item] = ''
		} else if item is map[string]json2.Any {
			m := item.as_map()
			name := m['name'] or { continue }
			message := m['message'] or { json2.Any('') }
			messages[name.str()] = if message is string { message } else { '' }
		} else {
			return error('the options of `${no_restricted_globals}` must be names or objects with a name')
		}
	}
	return NrgOptions{
		messages:            messages
		check_global_object: check
		global_objects:      objects
	}
}

fn (mut c Checker) lint_no_restricted_globals(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nrg_options(c.rule_options(no_restricted_globals))!
	mut findings := []Finding{}
	if o.messages.len == 0 {
		return findings
	}
	tree := c.scope_tree(root)
	global := tree.scopes[0]
	for v in global.variables {
		stats.checked++
		variable := tree.variables[v]
		if variable.defs.len > 0 || variable.name !in o.messages {
			continue
		}
		for r in variable.references {
			id := tree.references[r].identifier
			if !nrg_in_type_context(id) {
				findings << nrg_report(id, variable.name, o)
			}
		}
	}
	for r in global.through {
		reference := tree.references[r]
		if reference.name in o.messages && !nrg_in_type_context(reference.identifier) {
			findings << nrg_report(reference.identifier, reference.name, o)
		}
	}
	if o.check_global_object {
		for object in o.global_objects {
			v := tree.find_variable(0, object, -1)
			if v < 0 {
				continue
			}
			for r in tree.variables[v].references {
				// The member access around `window.window…`.
				mut parent := nrg_parent(tree.references[r].identifier) or { continue }
				for c.es_is_specific_member_access(parent, '', object) {
					parent = nrg_parent(parent) or { break }
				}
				name := c.es_static_property_name(parent) or { continue }
				if name !in o.messages {
					continue
				}
				property := node_field(parent, if node_kind(parent) == 'subscript_expression' {
					'index'
				} else {
					'property'
				}) or { continue }
				findings << nrg_report(unwrap_parens(property), name, o)
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nrg_parent is the ESTree parent: parentheses are not nodes.
fn nrg_parent(n C.TSNode) ?C.TSNode {
	mut parent := node_parent(n)?
	for node_kind(parent) == 'parenthesized_expression' {
		parent = node_parent(parent)?
	}
	return parent
}

fn nrg_report(id C.TSNode, name string, o NrgOptions) Finding {
	message := o.messages[name] or { '' }
	return Finding{
		stmt:       position_of(id)
		message_id: if message != '' { 'customMessage' } else { 'defaultMessage' }
		data:       {
			'name':          name
			'customMessage': message
		}
	}
}

// nrg_in_type_context ports isInTypeContext: the parent of the identifier is a TSTypeReference,
// TSInterfaceHeritage, TSClassImplements, TSTypeQuery or TSQualifiedName.
fn nrg_in_type_context(id C.TSNode) bool {
	if node_kind(id) == 'type_identifier' {
		return true
	}
	parent := node_parent(id) or { return false }
	match node_kind(parent) {
		'nested_type_identifier', 'type_query', 'extends_type_clause', 'implements_clause',
		'generic_type', 'nested_identifier' {
			return true
		}
		'member_expression' {
			// `typeof a.b` in a type is a TSQualifiedName.
			mut node := parent
			for node_kind(node) == 'member_expression' {
				node = node_parent(node) or { return false }
			}
			return node_kind(node) == 'type_query'
		}
		else {
			return false
		}
	}
}
