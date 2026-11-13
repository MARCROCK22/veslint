module rules

import json2
import time
import treesitter { named_children, node_field, node_kind, node_parent, position_of }

// Port of the `no-restricted-properties` rule of ESLint 10.6.0.

const nrp_messages = {
	'restrictedObjectProperty': "'{{objectName}}.{{propertyName}}' is restricted from being used.{{allowedPropertiesMessage}}{{message}}"
	'restrictedProperty':       "'{{propertyName}}' is restricted from being used.{{allowedObjectsMessage}}{{message}}"
}

// NrpRestriction is an option: a list given (`allowObjects`, `allowProperties`) is `allowed`
// with has_allowed.
struct NrpRestriction {
	message     string
	allowed     []string
	has_allowed bool
}

struct NrpOptions {
mut:
	properties map[string]map[string]NrpRestriction // object -> property -> restriction
	objects    map[string]NrpRestriction            // globally restricted objects
	global     map[string]NrpRestriction            // globally restricted properties
}

fn nrp_strings(v json2.Any) ([]string, bool) {
	if v !is []json2.Any {
		return []string{}, false
	}
	mut out := []string{}
	for item in v.as_array() {
		out << item.str()
	}
	return out, true
}

fn nrp_options(options []json2.Any) !NrpOptions {
	mut o := NrpOptions{}
	for option in options {
		if option !is map[string]json2.Any {
			return error('the options of `${no_restricted_properties}` must be objects')
		}
		m := option.as_map()
		message := if value := m['message'] { value.str() } else { '' }
		object := m['object'] or { json2.Null{} }
		property := m['property'] or { json2.Null{} }
		if object !is string {
			allowed, has := nrp_strings(m['allowObjects'] or { json2.Null{} })
			o.global[property.str()] = NrpRestriction{message, allowed, has}
		} else if property !is string {
			allowed, has := nrp_strings(m['allowProperties'] or { json2.Null{} })
			o.objects[object.str()] = NrpRestriction{message, allowed, has}
		} else {
			if object.str() !in o.properties {
				o.properties[object.str()] = map[string]NrpRestriction{}
			}
			o.properties[object.str()][property.str()] = NrpRestriction{
				message: message
			}
		}
	}
	return o
}

fn (mut c Checker) lint_no_restricted_properties(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nrp_options(c.rule_options(no_restricted_properties))!
	mut findings := []Finding{}
	if o.properties.len == 0 && o.objects.len == 0 && o.global.len == 0 {
		return findings
	}
	for node in c.nodes_of_kinds(root, ['member_expression', 'subscript_expression', 'object_pattern'], []) {
		stats.checked++
		if node_kind(node) == 'object_pattern' {
			object_name := c.nrp_pattern_object(node)
			for property in named_children(node) {
				if node_kind(property) in ['comment', 'rest_pattern'] {
					continue
				}
				name := c.es_static_key_name(property) or { continue }
				c.nrp_check(node, object_name, name, o, mut findings)
			}
			continue
		}
		if nrp_in_type_query(node) {
			continue
		}
		name := c.es_static_property_name(node) or { continue }
		object := unwrap_parens(node_field(node, 'object') or { continue })
		object_name := if node_kind(object) in ['identifier', 'undefined'] {
			?string(c.identifier_name(object))
		} else {
			?string(none)
		}
		c.nrp_check(node, object_name, name, o, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nrp_in_type_query: a member expression of `typeof a.b` in a type (a TSQualifiedName).
fn nrp_in_type_query(n C.TSNode) bool {
	mut node := n
	for node_kind(node) == 'member_expression' {
		node = node_parent(node) or { return false }
	}
	return node_kind(node) == 'type_query'
}

// nrp_pattern_object is the name of the identifier an object pattern destructures (the init of
// its declarator, the right of its assignment or default value).
fn (c &Checker) nrp_pattern_object(pattern C.TSNode) ?string {
	parent := node_parent(pattern)?
	mut right := ?C.TSNode(none)
	match node_kind(parent) {
		'variable_declarator' {
			name := node_field(parent, 'name')?
			if node_key(name) == node_key(pattern) {
				right = node_field(parent, 'value')
			}
		}
		'assignment_expression', 'assignment_pattern' {
			right = node_field(parent, 'right')
		}
		'required_parameter', 'optional_parameter' {
			right = node_field(parent, 'value')
		}
		else {}
	}
	value := unwrap_parens(right?)
	if node_kind(value) in ['identifier', 'undefined'] {
		return c.identifier_name(value)
	}
	return none
}

// nrp_check ports checkPropertyAccess.
fn (c &Checker) nrp_check(node C.TSNode, object_name ?string, property_name string, o NrpOptions, mut findings []Finding) {
	mut matched := ?NrpRestriction(none)
	if object := object_name {
		if properties := o.properties[object] {
			matched = properties[property_name] or { none }
		} else {
			matched = o.objects[object] or { none }
		}
	}
	if m := matched {
		if !(m.has_allowed && property_name in m.allowed) {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'restrictedObjectProperty'
				data:       {
					'objectName':               object_name or { '' }
					'propertyName':             property_name
					'message':                  if m.message != '' { ' ${m.message}' } else { '' }
					'allowedPropertiesMessage': if m.has_allowed {
						' Only these properties are allowed: ${m.allowed.join(', ')}.'
					} else {
						''
					}
				}
			}
			return
		}
	}
	g := o.global[property_name] or { return }
	if g.has_allowed {
		if object := object_name {
			if object in g.allowed {
				return
			}
		}
	}
	findings << Finding{
		stmt:       position_of(node)
		message_id: 'restrictedProperty'
		data:       {
			'propertyName':          property_name
			'message':               if g.message != '' { ' ${g.message}' } else { '' }
			'allowedObjectsMessage': if g.has_allowed {
				" Property '${property_name}' is only allowed on these objects: ${g.allowed.join(', ')}."
			} else {
				''
			}
		}
	}
}
