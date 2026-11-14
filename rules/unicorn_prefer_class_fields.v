module rules

import estree
import time

// Port of the `unicorn/prefer-class-fields` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fix and suggestion.

const upcfl_messages = {
	'prefer-class-fields/error':      'Prefer class field declaration over `this` assignment in constructor for static values.'
	'prefer-class-fields/suggestion': 'Encountered same-named class field declaration and `this` assignment in constructor. Replace the class field declaration with the value from `this` assignment.'
}

// `TSAbstractPropertyDefinition` is a declaration only field, it can not get an initializer.
const upcfl_field_types = [estree.NodeType.accessor_property, .property_definition,
	.ts_abstract_property_definition]

fn (mut c Checker) lint_unicorn_prefer_class_fields(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for class_body in 0 .. t.nodes.len {
		if t.typ(class_body) != .class_body {
			continue
		}
		stats.checked++
		members := t.list(class_body, .body) or { continue }
		mut constructor := -1
		for member in members {
			if t.string_of(member, .kind) or { '' } == 'constructor'
				&& !(t.flag(member, .computed) or { false })
				&& !(t.flag(member, .static_) or { false }) && t.typ(member) == .method_definition {
				value := t.node(member, .value) or { continue }
				if t.typ(value) == .function_expression {
					constructor = member
					break
				}
			}
		}
		if constructor < 0 {
			continue
		}
		function := t.node(constructor, .value) or { continue }
		function_body := t.node(function, .body) or { continue }
		mut node := -1
		for statement in t.list(function_body, .body) or { []int{} } {
			if t.typ(statement) != .empty_statement {
				node = statement
				break
			}
		}
		if node < 0 || t.typ(node) != .expression_statement {
			continue
		}
		expression := t.node(node, .expression) or { continue }
		if t.typ(expression) != .assignment_expression
			|| t.string_of(expression, .operator) or { '' } != '=' {
			continue
		}
		left := t.node(expression, .left) or { continue }
		right := t.node(expression, .right) or { continue }
		if t.typ(left) != .member_expression || t.flag(left, .computed) or { false } {
			continue
		}
		object := t.node(left, .object) or { continue }
		property := t.node(left, .property) or { continue }
		if t.typ(object) != .this_expression
			|| t.typ(property) !in [.identifier, .private_identifier] {
			continue
		}
		if t.typ(right) != .literal && un_static_string_value(t, right) == none {
			continue
		}
		property_name := t.string_of(property, .name) or { continue }
		property_value := c.un_text(t, right)
		property_type := t.typ(property)
		// TypeScript emits the assignment of a parameter property at the top of the constructor,
		// after the class field initializers, so `constructor(private x) { this.x = 0; }` must not
		// become a field, and a field named like a parameter property would be a duplicate.
		mut has_parameter_property := false
		for parameter in t.list(function, .params) or { []int{} } {
			if t.typ(parameter) != .ts_parameter_property {
				continue
			}
			inner := t.node(parameter, .parameter) or { continue }
			// `private x = 1` is an `AssignmentPattern`.
			name := t.node(inner, .left) or { inner }
			if upcfl_is_same_key(t, name, property_type, property_name) {
				has_parameter_property = true
				break
			}
		}
		if has_parameter_property {
			continue
		}
		// A `get`/`set` accessor or a method defines the property on the prototype, a data field
		// would shadow it. A private name is unique in the whole class, a `static` member with that
		// name is already the declaration.
		has_conflicting_member := members.any((t.typ(it) == .method_definition
			|| t.typ(it) in upcfl_field_types) && !(t.flag(it, .computed) or { false })
			&& upcfl_is_same_key(t, t.node(it, .key) or { -1 }, property_type, property_name)
			&& ((property_type == .private_identifier && (t.flag(it, .static_) or { false }))
				|| (t.typ(it) == .method_definition && !(t.flag(it, .static_) or { false }))))
		existing_properties := members.filter(t.typ(it) in upcfl_field_types
			&& !(t.flag(it, .computed) or { false }) && !(t.flag(it, .static_) or { false })
			&& upcfl_is_same_key(t, t.node(it, .key) or { -1 }, property_type, property_name))
		existing := if existing_properties.len > 0 { existing_properties[0] } else { -1 }
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'prefer-class-fields/error'
		}
		// An `abstract` or `declare` field has no initializer, and a definite assignment assertion
		// can not have one either. With duplicate fields, the later ones would still reset the
		// value to `undefined`.
		if existing_properties.len > 1 || (existing >= 0 && upcfl_has_no_initializer(t, existing)) {
			findings << finding
			continue
		}
		// The assignment is rebuilt as a field, a comment inside it would be lost.
		if has_conflicting_member
			|| tokens.comments_inside(t.nodes[node].start, t.nodes[node].end).len > 0 {
			findings << finding
			continue
		}
		mut fixes := [c.upcfl_remove_field_assignment(t, node)]
		existing_value := if existing >= 0 { t.node(existing, .value) or { -1 } } else { -1 }
		if existing >= 0 {
			if existing_value >= 0 {
				fixes << fix_replace_range(t.nodes[existing_value].start, t.nodes[existing_value].end,
					property_value)
			} else {
				text := ' = ${property_value}'
				last_token := un_last_token(t, tokens, existing) or { continue }
				fixes << if c.token_is(last_token, ';') {
					fix_insert_at(last_token.start, text)
				} else {
					fix_insert_at(t.nodes[existing].end, '${text};')
				}
			}
		} else {
			closing_brace := un_last_token(t, tokens, class_body) or { continue }
			indent := c.un_indent_string(t, constructor)
			linebreak := c.unb_linebreak()
			mut text := '${indent}${property_name} = ${property_value};${linebreak}'
			if closing_brace.start == 0 || c.src[closing_brace.start - 1] != `\n` {
				text = '${linebreak}${text}'
			}
			last_property := members.last()
			if t.typ(last_property) == .property_definition {
				last_token := un_last_token(t, tokens, last_property) or { continue }
				if c.token_text(last_token) != ';' {
					text = ';${text}'
				}
			}
			fixes << fix_insert_at(closing_brace.start, text)
		}
		_, fix := c.merge_fixes(fixes)!
		if existing_value >= 0 {
			finding = Finding{
				...finding
				suggestions: [
					Suggestion{
						message_id: 'prefer-class-fields/suggestion'
						fix:        fix
					},
				]
			}
		} else {
			finding = Finding{
				...finding
				has_fix: true
				fix:     fix
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// upcfl_is_same_key ports isSameKey: `get 'bar'()` is the same accessor as `get bar()`.
fn upcfl_is_same_key(t &estree.EsTree, key int, property_type estree.NodeType, property_name string) bool {
	if key < 0 {
		return false
	}
	if t.typ(key) == property_type && t.string_of(key, .name) or { return false } == property_name {
		return true
	}
	if property_type == .identifier && t.typ(key) == .literal {
		value := t.get(key, .value)
		return value is string && value == property_name
	}
	return false
}

// upcfl_has_no_initializer ports hasNoInitializer.
fn upcfl_has_no_initializer(t &estree.EsTree, property int) bool {
	return (t.flag(property, .declare_) or { false }) || (t.flag(property, .definite) or { false })
		|| t.typ(property) == .ts_abstract_property_definition
}

// upcfl_remove_field_assignment ports removeFieldAssignment: the statement, with its whole line
// when it is alone on it.
fn (c &Checker) upcfl_remove_field_assignment(t &estree.EsTree, node int) Fix {
	start := t.nodes[node].start
	line, _ := t.line_column(start)
	line_start := t.line_starts[line - 1]
	mut line_end := c.src.len
	if line < t.line_starts.len {
		line_end = t.line_starts[line]
		// The line ends before its line break.
		for line_end > line_start && c.src[line_end - 1] in [`\n`, `\r`] {
			line_end--
		}
		if line_end >= line_start + 3 && c.src[line_end - 3] == 0xe2 && c.src[line_end - 2] == 0x80
			&& c.src[line_end - 1] in [u8(0xa8), 0xa9] {
			line_end -= 3
		}
	}
	if js_trim(c.src[line_start..line_end]) == c.un_text(t, node) {
		next_start := if line < t.line_starts.len { t.line_starts[line] } else { c.src.len }
		return fix_remove_range(line_start, next_start)
	}
	return fix_remove_range(start, t.nodes[node].end)
}
