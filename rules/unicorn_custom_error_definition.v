module rules

import estree
import time

// Port of the `unicorn/custom-error-definition` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fixes. Most of its reports have a message of their own and no messageId.

const ucedf_messages = {
	'invalidExport': 'Exported error name should match error class'
}

// ucedf_class_name ports getClassName: the name in upper first, ending in `Error`.
fn ucedf_class_name(name string) string {
	if name == '' {
		return 'Error'
	}
	upper := name[..1].to_upper() + name[1..]
	if upper.to_lower().ends_with('error') {
		return upper[..upper.len - 5] + 'Error'
	}
	return upper + 'Error'
}

// ucedf_valid_super_class ports hasValidSuperClass.
fn ucedf_valid_super_class(t &estree.EsTree, node int) bool {
	super_class := t.node(node, .super_class) or { return false }
	name := match t.typ(super_class) {
		.identifier {
			t.string_of(super_class, .name) or { '' }
		}
		.member_expression {
			property := t.node(super_class, .property) or { return false }
			if (t.flag(super_class, .computed) or { false }) || t.typ(property) != .identifier {
				return false
			}
			t.string_of(property, .name) or { '' }
		}
		else {
			return false
		}
	}
	return name != '' && utne_is_error_name(name)
}

// ucedf_statement_call ports isSuperExpression.
fn ucedf_is_super(t &estree.EsTree, node int) bool {
	if t.typ(node) != .expression_statement {
		return false
	}
	expression := t.node(node, .expression) or { return false }
	return t.typ(expression) == .call_expression
		&& un_node_matches_name_or_path(t, t.node(expression, .callee) or { return false }, 'super')
}

// ucedf_is_assignment ports isAssignmentExpression: `this.<name> = …`.
fn ucedf_is_assignment(t &estree.EsTree, node int, name string) bool {
	if t.typ(node) != .expression_statement {
		return false
	}
	expression := t.node(node, .expression) or { return false }
	return t.typ(expression) == .assignment_expression
		&& un_node_matches_name_or_path(t, t.node(expression, .left) or { return false }, 'this.${name}')
}

// ucedf_is_name_property ports isPropertyDefinition(node, 'name'): an instance field `name`.
fn ucedf_is_name_property(t &estree.EsTree, node int) bool {
	if t.typ(node) != .property_definition || (t.flag(node, .static_) or { false })
		|| (t.flag(node, .computed) or { false }) {
		return false
	}
	key := t.node(node, .key) or { return false }
	return t.typ(key) == .identifier && (t.string_of(key, .name) or { '' }) == 'name'
}

// ucedf_valid_name_property ports isValidNameProperty: `name = '<class name>'`.
fn ucedf_valid_name_property(t &estree.EsTree, property int, class_name string) bool {
	if property < 0 {
		return false
	}
	value := t.node(property, .value) or { return false }
	v := t.get(value, .value)
	return v is string && v == class_name
}

fn ucedf_name_error(c &Checker, t &estree.EsTree, node int, name string) Finding {
	return Finding{
		stmt: c.es_tree_position(t, node)
		text: 'The `name` property should be set to `${name}`.'
	}
}

fn (mut c Checker) lint_unicorn_custom_error_definition(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.class_declaration {
				stats.checked++
				findings << c.ucedf_definition(t, tokens, node)!
			}
			.assignment_expression {
				stats.checked++
				right := t.node(node, .right) or { continue }
				if t.typ(right) == .class_expression {
					findings << c.ucedf_definition(t, tokens, right)!
				}
				left := t.node(node, .left) or { continue }
				if t.typ(left) == .member_expression {
					object := t.node(left, .object) or { continue }
					if t.typ(object) == .identifier
						&& (t.string_of(object, .name) or { '' }) == 'exports' {
						if finding := c.ucedf_export(t, node) {
							findings << finding
						}
					}
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ucedf_definition ports customErrorDefinition.
fn (mut c Checker) ucedf_definition(t &estree.EsTree, tokens &SourceTokens, node int) ![]Finding {
	mut out := []Finding{}
	if !ucedf_valid_super_class(t, node) {
		return out
	}
	id := t.node(node, .id) or { return out }
	name := t.string_of(id, .name) or { return out }
	class_name := ucedf_class_name(name)
	if name != class_name {
		out << Finding{
			stmt: c.es_tree_position(t, id)
			text: 'Invalid class name, use `${class_name}`.'
		}
	}
	class_body := t.node(node, .body) or { return out }
	body := t.list(class_body, .body) or { []int{} }
	constructor := body.filter((t.string_of(it, .kind) or { '' }) == 'constructor')
	properties := body.filter(ucedf_is_name_property(t, it))
	name_property := if properties.len > 0 { properties[0] } else { -1 }
	if constructor.len == 0 {
		if ucedf_valid_name_property(t, name_property, name) {
			return out
		}
		value := if name_property >= 0 { t.node(name_property, .value) or { -1 } } else { -1 }
		at := if value >= 0 { value } else { node }
		fix := if value >= 0 {
			fix_replace_range(t.nodes[value].start, t.nodes[value].end, "'${name}'")
		} else if name_property >= 0 {
			fix_replace_range(t.nodes[name_property].start, t.nodes[name_property].end,
				"name = '${name}';")
		} else {
			fix_insert_at(t.nodes[class_body].start + 1, "\n\tname = '${name}';\n")
		}
		out << Finding{
			...ucedf_name_error(c, t, at, name)
			has_fix: true
			fix:     fix
		}
		return out
	}
	out << c.ucedf_constructor_body(t, tokens, constructor[0], name, name_property)!
	return out
}

// ucedf_constructor_body ports checkConstructorBody.
fn (mut c Checker) ucedf_constructor_body(t &estree.EsTree, tokens &SourceTokens, constructor int, name string, name_property int) ![]Finding {
	mut out := []Finding{}
	value := t.node(constructor, .value) or { return out }
	// A constructor without a body (TypeScript).
	block := t.node(value, .body) or { return out }
	statements := t.list(block, .body) or { []int{} }
	supers := statements.filter(ucedf_is_super(t, it))
	mut message_index := -1
	for i, statement in statements {
		if ucedf_is_assignment(t, statement, 'message') {
			message_index = i
			break
		}
	}
	if supers.len == 0 {
		out << Finding{
			stmt: c.es_tree_position(t, block)
			text: 'Missing call to `super()` in constructor.'
		}
	} else if message_index >= 0 {
		super_statement := supers[0]
		expression := statements[message_index]
		mut fixes := []Fix{}
		call := t.node(super_statement, .expression) or { return out }
		if (t.list(call, .arguments) or { []int{} }).len == 0 {
			right := t.node(t.node(expression, .expression) or { return out }, .right) or {
				return out
			}
			fixes << fix_insert_at(t.nodes[super_statement].start + 6, c.un_parenthesized_text(t,
				tokens, right))
		}
		start := if message_index == 0 {
			t.nodes[block].start
		} else {
			t.nodes[statements[message_index - 1]].end
		}
		fixes << fix_remove_range(start, t.nodes[expression].end)
		has_fix, fix := c.merge_fixes(fixes)!
		out << Finding{
			stmt:    c.es_tree_position(t, super_statement)
			text:    'Pass the error message to `super()` instead of setting `this.message`.'
			has_fix: has_fix
			fix:     fix
		}
	}
	name_assignments := statements.filter(ucedf_is_assignment(t, it, 'name'))
	if name_assignments.len == 0 {
		if !ucedf_valid_name_property(t, name_property, name) {
			value_node := if name_property >= 0 {
				t.node(name_property, .value) or { block }
			} else {
				block
			}
			out << ucedf_name_error(c, t, value_node, name)
		}
		return out
	}
	right := t.node(t.node(name_assignments[0], .expression) or { return out }, .right) or { return out }
	v := t.get(right, .value)
	if t.typ(right) != .literal || !(v is string && v == name) {
		out << ucedf_name_error(c, t, right, name)
	}
	return out
}

// ucedf_export ports customErrorExport: `exports.Name = class Name extends Error {}`.
fn (c &Checker) ucedf_export(t &estree.EsTree, node int) ?Finding {
	left := t.node(node, .left)?
	property := t.node(left, .property)?
	right := t.node(node, .right)?
	if t.typ(right) != .class_expression || !ucedf_valid_super_class(t, right) {
		return none
	}
	id := t.node(right, .id)?
	error_name := t.string_of(id, .name)?
	if (t.string_of(property, .name) or { '' }) == error_name && t.typ(property) == .identifier {
		return none
	}
	return Finding{
		stmt:       c.es_tree_position(t, property)
		message_id: 'invalidExport'
		has_fix:    true
		fix:        fix_replace_range(t.nodes[property].start, t.nodes[property].end, error_name)
	}
}
