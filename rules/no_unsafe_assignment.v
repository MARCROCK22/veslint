module rules

import jsregexp
import time
import tsgo { SymbolResponse, TypeResponse }
import treesitter { Ident, children, first_named_child, has_child_kind, named_children, node_end, node_field, node_kind, node_parent, node_start, nodes_of_kinds, position_of }

// Port of the `no-unsafe-assignment` rule of typescript-eslint 8.62.0 (it has no options). Limits
// of the port: README, "Rules" section.

const nua_messages = {
	'anyAssignment':               'Unsafe assignment of an {{sender}} value.'
	'anyAssignmentThis':           'Unsafe assignment of an {{sender}} value. `this` is typed as `any`.\nYou can try to fix this by turning on the `noImplicitThis` compiler option, or adding a `this` parameter to the function.'
	'unsafeArrayPattern':          'Unsafe array destructuring of an {{sender}} array value.'
	'unsafeArrayPatternFromTuple': 'Unsafe array destructuring of a tuple element with an {{sender}} value.'
	'unsafeArraySpread':           'Unsafe spread of an {{sender}} value in an array.'
	'unsafeAssignment':            'Unsafe assignment of type {{sender}} to a variable of type {{receiver}}.'
	'unsafeObjectPattern':         'Unsafe object destructuring of a property with an {{sender}} value.'
}

// Comparison ports ComparisonType: the type the assigned value is compared with.
enum Comparison {
	none       // no annotation: the type of the variable is that of the value
	basic      // the type of the receiver
	contextual // the contextual type of the key (getContextualType from type-utils)
}

// Assignment is a receiver and the value it gets, checked with checkAssignment. If it does not
// report and `destructure` is set, the destructurings of the receiver are checked too.
struct Assignment {
	receiver    C.TSNode
	sender      C.TSNode
	reporting   C.TSNode
	report_end  int = -1 // where the reported ESTree node ends, when not where `reporting` does
	comparison  Comparison
	destructure bool
}

const assignment_kinds = ['variable_declarator', 'assignment_expression', 'required_parameter',
	'optional_parameter', 'assignment_pattern', 'object_assignment_pattern', 'public_field_definition',
	'object', 'array', 'jsx_attribute']

fn (mut c Checker) lint_no_unsafe_assignment(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	assignments, spreads := c.collect_assignments(root)
	mut spans := []Span{}
	for a in assignments {
		spans << node_span(a.receiver)
		spans << node_span(a.sender)
	}
	for spread in spreads {
		if arg := first_named_child(spread) {
			spans << node_span(unwrap_parens(arg))
		}
	}
	spans << c.this_spans(assignments.map(it.sender))
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for a in assignments {
		mut reported := c.check_assignment(a, mut findings)!
		if a.destructure && !reported {
			reported = c.check_array_destructure_helper(a.receiver, a.sender, mut findings)!
		}
		if a.destructure && !reported {
			c.check_object_destructure_helper(a.receiver, a.sender, mut findings)!
		}
	}
	// `ArrayExpression > SpreadElement`
	for spread in spreads {
		arg := unwrap_parens(first_named_child(spread) or { continue })
		t := c.node_type(arg) or { continue }
		if c.is_any(t)! || c.is_any_array(t)! {
			findings << Finding{
				stmt:       position_of(spread)
				message_id: 'unsafeArraySpread'
				data:       {
					'sender': any_text(t)
				}
			}
		}
	}
	findings.sort_with_compare(compare_findings)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += assignments.len + spreads.len
	return findings
}

// collect_assignments collects in one pass what typescript-eslint checks with checkAssignment,
// and the `...x` of array literals.
fn (c &Checker) collect_assignments(root C.TSNode) ([]Assignment, []C.TSNode) {
	mut out := []Assignment{}
	mut spreads := []C.TSNode{}
	for node in c.nodes_of_kinds(root, assignment_kinds, []) {
		match node_kind(node) {
			'variable_declarator' {
				// VariableDeclarator[init != null]
				name := node_field(node, 'name') or { continue }
				value := node_field(node, 'value') or { continue }
				out << Assignment{
					receiver:    name
					sender:      unwrap_parens(value)
					reporting:   node
					comparison:  annotated(node)
					destructure: true
				}
			}
			'assignment_expression' {
				// AssignmentExpression[operator = "="]: `+=` and the rest are another kind of node.
				left := node_field(node, 'left') or { continue }
				right := node_field(node, 'right') or { continue }
				out << Assignment{
					receiver:    unwrap_parens(left)
					sender:      unwrap_parens(right)
					reporting:   node
					comparison:  .basic
					destructure: true
				}
			}
			'required_parameter', 'optional_parameter' {
				// The AssignmentPattern of a parameter with a default value starts at the name, without
				// decorators or modifiers.
				pattern := node_field(node, 'pattern') or { continue }
				value := node_field(node, 'value') or { continue }
				out << Assignment{
					receiver:    pattern
					sender:      unwrap_parens(value)
					reporting:   pattern
					report_end:  node_end(node)
					comparison:  .basic
					destructure: true
				}
			}
			'assignment_pattern', 'object_assignment_pattern' {
				// Default values in a destructuring (`[a = 1]`, `{ a = 1 }`).
				left := node_field(node, 'left') or { continue }
				right := node_field(node, 'right') or { continue }
				out << Assignment{
					receiver:    left
					sender:      unwrap_parens(right)
					reporting:   node
					comparison:  .basic
					destructure: true
				}
			}
			'public_field_definition' {
				// PropertyDefinition and AccessorProperty with a value. Decorators are part of the field in
				// tree-sitter, as in ESTree.
				name := node_field(node, 'name') or { continue }
				value := node_field(node, 'value') or { continue }
				out << Assignment{
					receiver:   property_key(name) or { continue }
					sender:     unwrap_parens(value)
					reporting:  node
					comparison: annotated(node)
				}
			}
			'object' {
				// The `{ type: 'json' }` of an import attribute is a list of ImportAttribute nodes
				// in ESTree, not an ObjectExpression.
				if parent := node_parent(node) {
					if node_kind(parent) == 'import_attribute' {
						continue
					}
				}
				out << object_assignments(node)
			}
			'jsx_attribute' {
				// `JSXAttribute[value != null]` whose value is a JSXExpressionContainer with an
				// expression. The receiver is the attribute's name: type-utils' getContextualType gives
				// it no contextual type, so its own type counts.
				mut name := ?C.TSNode(none)
				mut value := ?C.TSNode(none)
				for child in named_children(node) {
					if node_kind(child) == 'jsx_expression' {
						value = jsx_expression_value(child)
					} else if name == none {
						name = child
					}
				}
				out << Assignment{
					receiver:   name or { continue }
					sender:     value or { continue }
					reporting:  value or { continue }
					comparison: .basic
				}
			}
			'array' {
				for child in named_children(node) {
					if node_kind(child) == 'spread_element' {
						spreads << child
					}
				}
			}
			else {}
		}
	}
	return out, spreads
}

// object_assignments ports `:not(ObjectPattern) > Property` in an object literal.
fn object_assignments(object C.TSNode) []Assignment {
	mut out := []Assignment{}
	for prop in named_children(object) {
		match node_kind(prop) {
			'pair' {
				key := property_key(node_field(prop, 'key') or { continue }) or { continue }
				value := node_field(prop, 'value') or { continue }
				out << Assignment{
					receiver:   key
					sender:     unwrap_parens(value)
					reporting:  prop
					comparison: .contextual
				}
			}
			'shorthand_property_identifier' {
				// In ESTree, the key and the value are the same identifier.
				out << Assignment{
					receiver:   prop
					sender:     prop
					reporting:  prop
					comparison: .contextual
				}
			}
			'method_definition' {
				// The type of a method is a function and is never reported; that of a get or a set is the
				// property's. getContextualType gives no type to the key of an accessor, so the receiver is the
				// type of the key.
				if has_child_kind(prop, 'get') || has_child_kind(prop, 'set') {
					key := property_key(node_field(prop, 'name') or { continue }) or { continue }
					out << Assignment{
						receiver:   key
						sender:     prop
						reporting:  prop
						comparison: .basic
					}
				}
			}
			else {}
		}
	}
	return out
}

// annotated ports getComparisonType: with a type annotation the value is compared with the receiver.
fn annotated(node C.TSNode) Comparison {
	if _ := node_field(node, 'type') {
		return .basic
	}
	return .none
}

// property_key is the key in ESTree: in `[k]`, the expression inside.
fn property_key(name C.TSNode) ?C.TSNode {
	if node_kind(name) == 'computed_property_name' {
		return unwrap_parens(first_named_child(name)?)
	}
	return name
}

// check_assignment ports checkAssignment and returns whether it reported.
fn (mut c Checker) check_assignment(a Assignment, mut findings []Finding) !bool {
	sender_type := c.node_type(a.sender) or { return false }
	sender_is_any := c.is_any(sender_type)!
	// Only `any`, or a generic reference with `any` among its type arguments, is reported: for
	// any other value the type of the receiver is not asked.
	if !sender_is_any && (a.comparison == .none || !is_type_reference(sender_type)) {
		return false
	}
	receiver_type := if a.comparison == .contextual {
		c.key_contextual_type(a.receiver)!
	} else {
		c.node_type(a.receiver) or { TypeResponse{} }
	}
	if receiver_type.is_null() {
		return false
	}
	if sender_is_any {
		// Assigning `any` to `unknown` is allowed.
		if c.is_unknown(receiver_type)! {
			return false
		}
		findings << Finding{
			stmt:       c.nua_place(a)
			message_id: if c.this_is_any(a.sender)! { 'anyAssignmentThis' } else { 'anyAssignment' }
			data:       {
				'sender': any_text(sender_type)
			}
		}
		return true
	}
	if a.comparison == .none {
		return false
	}
	pair := c.unsafe_assignment(sender_type, receiver_type, a.sender)!
	if !pair.found {
		return false
	}
	findings << Finding{
		stmt:       c.nua_place(a)
		message_id: 'unsafeAssignment'
		data:       {
			'sender':   '`${c.client.type_to_string(c.snapshot, c.project, pair.sender.id)!}`'
			'receiver': '`${c.client.type_to_string(c.snapshot, c.project, pair.receiver.id)!}`'
		}
	}
	return true
}

// key_contextual_type is the receiver of a property of an object literal: getContextualType from
// type-utils only gives the contextual type to keys that are identifiers; without it, the type of
// the key.
fn (mut c Checker) key_contextual_type(key C.TSNode) !TypeResponse {
	if node_kind(key) in ['property_identifier', 'shorthand_property_identifier'] {
		contextual := c.contextual_type(key)!
		if !contextual.is_null() {
			return contextual
		}
	}
	return c.node_type(key) or { TypeResponse{} }
}

// any_text is the {{sender}} of createData without a receiver.
fn any_text(t TypeResponse) string {
	return if is_error_type(t) { 'error typed' } else { '`any`' }
}

fn (mut c Checker) check_array_destructure_helper(receiver C.TSNode, sender C.TSNode, mut findings []Finding) !bool {
	if node_kind(receiver) != 'array_pattern' {
		return false
	}
	t := c.node_type(sender) or { return false }
	location := c.node_handles[node_key(sender)] or { return false }
	return c.check_array_destructure(receiver, t, location, 0, mut findings)!
}

// check_array_destructure ports checkArrayDestructure: an array of `any`, or each `any` element of
// a tuple, also in nested patterns.
fn (mut c Checker) check_array_destructure(pattern C.TSNode, sender_type TypeResponse, sender string, depth int, mut findings []Finding) !bool {
	if depth > max_expression_depth {
		c.too_deep++
		return false
	}
	if c.is_any_array(sender_type)! {
		findings << Finding{
			stmt:       position_of(pattern)
			message_id: 'unsafeArrayPattern'
			data:       {
				'sender': any_text(sender_type)
			}
		}
		return false
	}
	if !c.is_tuple(sender_type)! {
		return true
	}
	elements := c.type_args(sender_type)!
	mut did_report := false
	for i, element in array_pattern_elements(pattern) {
		el := element or { continue }
		if node_kind(el) == 'rest_pattern' || i >= elements.len {
			continue
		}
		t := elements[i]
		if c.is_any(t)! {
			findings << Finding{
				stmt:       position_of(el)
				message_id: 'unsafeArrayPatternFromTuple'
				data:       {
					'sender': any_text(t)
				}
			}
			did_report = true
		} else if node_kind(el) == 'array_pattern' {
			did_report = c.check_array_destructure(el, t, sender, depth + 1, mut findings)!
		} else if node_kind(el) == 'object_pattern' {
			did_report = c.check_object_destructure(el, t, sender, depth + 1, mut findings)!
		}
	}
	return did_report
}

// array_pattern_elements are the elements of an array pattern as in ESTree, with holes (`[, a]`)
// as none.
fn array_pattern_elements(pattern C.TSNode) []?C.TSNode {
	mut out := []?C.TSNode{}
	mut pending := ?C.TSNode(none)
	for child in children(pattern) {
		match node_kind(child) {
			'[', 'comment' {}
			',' {
				out << pending
				pending = none
			}
			']' {
				if el := pending {
					out << el
				}
			}
			else {
				pending = child
			}
		}
	}
	return out
}

fn (mut c Checker) check_object_destructure_helper(receiver C.TSNode, sender C.TSNode, mut findings []Finding) !bool {
	if node_kind(receiver) != 'object_pattern' {
		return false
	}
	t := c.node_type(sender) or { return false }
	location := c.node_handles[node_key(sender)] or { return false }
	return c.check_object_destructure(receiver, t, location, 0, mut findings)!
}

// check_object_destructure ports checkObjectDestructure: each destructured property whose type in
// the value is `any`, also in nested patterns. The type of each property is requested as seen from
// the value (`sender`, its tsgo node), like getTypeOfSymbolAtLocation in typescript-eslint, and
// only for the properties that appear in the pattern.
fn (mut c Checker) check_object_destructure(pattern C.TSNode, sender_type TypeResponse, sender string, depth int, mut findings []Finding) !bool {
	if depth > max_expression_depth {
		c.too_deep++
		return false
	}
	mut properties := map[string]SymbolResponse{}
	for prop in c.properties(sender_type)! {
		properties[unescape_name(prop.name)] = prop
	}
	mut did_report := false
	for prop in named_children(pattern) {
		key, value := c.pattern_property(prop) or { continue }
		symbol := properties[key] or { continue }
		t := c.client.type_of_symbol_at_location(c.snapshot, c.project, symbol.id, sender)!
		if c.is_any(t)! {
			findings << Finding{
				stmt:       position_of(value)
				message_id: 'unsafeObjectPattern'
				data:       {
					'sender': any_text(t)
				}
			}
			did_report = true
		} else if node_kind(value) == 'array_pattern' {
			did_report = c.check_array_destructure(value, t, sender, depth + 1, mut findings)!
		} else if node_kind(value) == 'object_pattern' {
			did_report = c.check_object_destructure(value, t, sender, depth + 1, mut findings)!
		}
	}
	return did_report
}

// pattern_property gives the name of a property of an object pattern and its ESTree value, or none
// if it has no computable name (or it is a `...rest`).
fn (c &Checker) pattern_property(prop C.TSNode) ?(string, C.TSNode) {
	match node_kind(prop) {
		'shorthand_property_identifier_pattern' {
			return c.identifier_name(prop), prop
		}
		'object_assignment_pattern' {
			// `{ a = 1 }`: the value of the property is the whole AssignmentPattern.
			left := node_field(prop, 'left')?
			if node_kind(left) != 'shorthand_property_identifier_pattern' {
				return none
			}
			return c.identifier_name(left), prop
		}
		'pair_pattern' {
			key := node_field(prop, 'key')?
			value := node_field(prop, 'value')?
			name := match node_kind(key) {
				'property_identifier' { c.identifier_name(key) }
				'computed_property_name' { c.literal_name(unwrap_parens(first_named_child(key)?))? }
				else { c.literal_name(key)? }
			}
			return name, value
		}
		else {
			return none
		}
	}
}

// identifier_name is the name of an identifier with its `\u…` escapes applied, like the ESTree
// `name`.
fn (c &Checker) identifier_name(n C.TSNode) string {
	text := c.text(n)
	if !text.contains('\\') {
		return text
	}
	return cooked_string(text, false) or { text }
}

// literal_name is String(value) of a literal used as a property name: strings and templates
// without substitutions (with their escapes), numbers, BigInt, true/false/null and regular
// expressions.
fn (c &Checker) literal_name(n C.TSNode) ?string {
	text := c.text(n)
	match node_kind(n) {
		'string' {
			return cooked_string(text[1..text.len - 1], false)
		}
		'template_string' {
			if named_children(n).any(node_kind(it) == 'template_substitution') {
				return none
			}
			return cooked_string(text[1..text.len - 1], true)
		}
		'number' {
			return js_number_string(text)
		}
		'true', 'false', 'null' {
			return text
		}
		'regex' {
			// String(new RegExp(pattern, flags)): the pattern as written (a literal has nothing V8
			// escapes in its `source`) and the flags in V8's order; a Literal V8 rejects has no value,
			// and String(null) is its name.
			pattern := node_field(n, 'pattern') or { return 'null' }
			flags := if f := node_field(n, 'flags') { c.text(f) } else { '' }
			re := jsregexp.regexp_new(utf16_units(c.text(pattern)), flags) or { return 'null' }
			return '/${c.text(pattern)}/${re.flags}'
		}
		else {
			return none
		}
	}
}

// unescape_name undoes the escaping of TypeScript symbol names, which tsgo returns as they are
// (`__a` is `___a`).
fn unescape_name(name string) string {
	return if name.starts_with('___') { name[1..] } else { name }
}

// nua_place is where an assignment is reported: its reporting node (a field to its `;`, the
// AssignmentPattern of a parameter to its default value).
fn (mut c Checker) nua_place(a Assignment) Ident {
	if a.report_end >= 0 {
		return c.position_range(node_start(a.reporting), c.tokens.last_end(a.report_end))
	}
	if node_kind(a.reporting) == 'public_field_definition' {
		return c.position_range(node_start(a.reporting), c.es_member_end(a.reporting))
	}
	return position_of(a.reporting)
}
