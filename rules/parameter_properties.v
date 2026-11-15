module rules

import estree
import json2
import time

// Port of the `@typescript-eslint/parameter-properties` rule of typescript-eslint 8.72.2, with its
// options `allow` and `prefer`.

const ppr_messages = {
	'preferClassProperty':     'Property {{parameter}} should be declared as a class property.'
	'preferParameterProperty': 'Property {{parameter}} should be declared as a parameter property.'
}

const ppr_modifiers = ['readonly', 'private', 'protected', 'public', 'private readonly',
	'protected readonly', 'public readonly']

struct PprOptions {
	allow                   []string
	prefer_class_properties bool
}

fn ppr_options(options []json2.Any) !PprOptions {
	o := option_object(parameter_properties, options, ['allow', 'prefer'])!
	allow := o.string_list('allow')!
	for modifier in allow {
		if modifier !in ppr_modifiers {
			return error('option `allow` of `${parameter_properties}` must list: ${ppr_modifiers.join(', ')}')
		}
	}
	prefer := o.string_value('prefer', ['class-property', 'parameter-property'])!
	return PprOptions{
		allow:                   allow
		prefer_class_properties: prefer != 'parameter-property'
	}
}

// PprNodes are PropertyNodes: the nodes of one name in a class (-1 for none).
struct PprNodes {
mut:
	class_property         int = -1
	constructor_assignment int = -1
	constructor_parameter  int = -1
}

// PprClass is the map of a class from names to their nodes, in insertion order.
struct PprClass {
mut:
	names []string
	nodes map[string]PprNodes
}

fn (mut p PprClass) get(name string) PprNodes {
	if name !in p.nodes {
		p.names << name
		p.nodes[name] = PprNodes{}
	}
	return p.nodes[name]
}

fn (mut c Checker) lint_parameter_properties(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := ppr_options(c.rule_options(parameter_properties))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	if o.prefer_class_properties {
		for node in 0 .. t.nodes.len {
			if t.typ(node) != .ts_parameter_property {
				continue
			}
			stats.checked++
			if ppr_modifiers_of(t, node) !in o.allow {
				findings << Finding{
					stmt:       c.es_tree_position(t, node)
					message_id: 'preferClassProperty'
					data:       {
						'parameter': ppr_parameter_name(t, node)
					}
				}
			}
		}
		stats.eval_ms += ms(sw.elapsed())
		return findings
	}
	mut stack := []PprClass{}
	for step in t.steps() {
		node := step.node
		typ := t.typ(node)
		if step.leave {
			if typ in [.class_declaration, .class_expression] {
				class := stack.pop()
				for name in class.names {
					nodes := class.nodes[name] or { continue }
					if nodes.class_property >= 0 && nodes.constructor_assignment >= 0
						&& nodes.constructor_parameter >= 0
						&& c.ppr_type_annotations_match(t, nodes.class_property, nodes.constructor_parameter) {
						findings << Finding{
							stmt:       c.es_tree_position(t, nodes.class_property)
							message_id: 'preferParameterProperty'
							data:       {
								'parameter': name
							}
						}
					}
				}
			}
			continue
		}
		match typ {
			.class_declaration, .class_expression {
				stats.checked++
				stack << PprClass{}
			}
			.class_body {
				if stack.len == 0 {
					continue
				}
				for element in t.list(node, .body) or { []int{} } {
					key := t.node(element, .key) or { continue }
					if t.typ(element) == .property_definition && t.typ(key) == .identifier
						&& t.node(element, .value) == none
						&& ppr_modifiers_of(t, element) !in o.allow {
						name := t.string_of(key, .name) or { '' }
						mut nodes := stack[stack.len - 1].get(name)
						nodes.class_property = element
						stack[stack.len - 1].nodes[name] = nodes
					}
				}
			}
			.method_definition {
				if stack.len == 0 || (t.string_of(node, .kind) or { '' }) != 'constructor' {
					continue
				}
				value := t.node(node, .value) or { continue }
				for parameter in t.list(value, .params) or { []int{} } {
					if t.typ(parameter) == .identifier {
						name := t.string_of(parameter, .name) or { '' }
						mut nodes := stack[stack.len - 1].get(name)
						nodes.constructor_parameter = parameter
						stack[stack.len - 1].nodes[name] = nodes
					}
				}
				body := t.node(value, .body) or { continue }
				for statement in t.list(body, .body) or { []int{} } {
					assignment := ppr_this_assignment(t, statement) or { break }
					right := t.node(assignment, .right) or { break }
					name := t.string_of(right, .name) or { '' }
					mut nodes := stack[stack.len - 1].get(name)
					nodes.constructor_assignment = assignment
					stack[stack.len - 1].nodes[name] = nodes
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ppr_this_assignment is the expression of a statement `this.a = b;` (`a` and `b` identifiers).
fn ppr_this_assignment(t &estree.EsTree, statement int) ?int {
	if t.typ(statement) != .expression_statement {
		return none
	}
	expression := t.node(statement, .expression)?
	if t.typ(expression) != .assignment_expression {
		return none
	}
	left := t.node(expression, .left)?
	if t.typ(left) != .member_expression {
		return none
	}
	if t.typ(t.node(left, .object)?) != .this_expression
		|| t.typ(t.node(left, .property)?) != .identifier
		|| t.typ(t.node(expression, .right)?) != .identifier {
		return none
	}
	return expression
}

// ppr_modifiers_of ports getModifiers: the accessibility and `readonly` of the node.
fn ppr_modifiers_of(t &estree.EsTree, node int) string {
	mut modifiers := []string{}
	accessibility := t.string_of(node, .accessibility) or { '' }
	if accessibility != '' {
		modifiers << accessibility
	}
	if t.flag(node, .readonly) or { false } {
		modifiers << 'readonly'
	}
	return modifiers.join(' ')
}

// ppr_parameter_name is the name of the parameter of a parameter property.
fn ppr_parameter_name(t &estree.EsTree, node int) string {
	parameter := t.node(node, .parameter) or { return '' }
	if t.typ(parameter) == .identifier {
		return t.string_of(parameter, .name) or { '' }
	}
	left := t.node(parameter, .left) or { return 'undefined' }
	return t.string_of(left, .name) or { 'undefined' }
}

// ppr_type_annotations_match ports typeAnnotationsMatch.
fn (c &Checker) ppr_type_annotations_match(t &estree.EsTree, class_property int, constructor_parameter int) bool {
	a := t.node(class_property, .type_annotation) or { -1 }
	b := t.node(constructor_parameter, .type_annotation) or { -1 }
	if a < 0 || b < 0 {
		return a == b
	}
	return c.src[t.nodes[a].start..t.nodes[a].end] == c.src[t.nodes[b].start..t.nodes[b].end]
}
