module rules

import json2
import time
import tsgo { TypeResponse }
import treesitter { children, has_child_kind, named_children, node_end, node_field, node_kind, node_parent, node_start, nodes_of_kinds }

// Port of the `prefer-readonly` rule of typescript-eslint 8.62.0, with its `onlyInlineLambdas`
// option and its fixer.
//
// The original works on TypeScript's own tree: an access is a modification by the shape of its
// parents there (BinaryExpression, DeleteExpression, the array and object literals of a
// destructuring assignment…), which prd_is_modification follows on the tree-sitter nodes with the
// same shape.

const prd_messages = {
	'preferReadonly': "Member '{{name}}' is never reassigned; mark it as `readonly`."
}

const prd_class_kinds = ['class_declaration', 'class', 'abstract_class_declaration']

// TypeScript's BinaryExpression: assignments, the defaults of a destructuring, the other binary
// operators and the comma.
const prd_binary_kinds = ['assignment_expression', 'augmented_assignment_expression',
	'binary_expression', 'sequence_expression', 'assignment_pattern']

// ObjectFlags.Anonymous and ObjectFlags.ClassOrInterface; TypeFlags.Literal and EnumLiteral.
const prd_object_flag_anonymous = u32(16)
const prd_object_flags_class_or_interface = u32(3)
const prd_type_flags_literal = u32(15360)
const prd_type_flag_enum_literal = u32(32768)

struct PrdOptions {
	only_inline_lambdas bool
}

fn prd_options(options []json2.Any) !PrdOptions {
	o := option_object(prefer_readonly, options, ['onlyInlineLambdas'])!
	return PrdOptions{
		only_inline_lambdas: o.bool_value('onlyInlineLambdas')!
	}
}

// PrdMember is a private member that is not readonly: a class property or a parameter property.
struct PrdMember {
	node         C.TSNode
	name_node    C.TSNode
	name         string // getMemberName
	is_static    bool
	is_parameter bool
}

// PrdAccess is a modification of a member by name: what it is a member of and whether it is
// directly in the constructor.
struct PrdAccess {
	object         C.TSNode
	name           string
	in_constructor bool
}

struct PrdClass {
	node C.TSNode
	span Span
mut:
	members  []PrdMember
	accesses []PrdAccess
}

enum PrdRelation {
	class_and_instance
	class
	instance
	none
}

// PrdReport is a member to report, with what its type annotation needs.
struct PrdReport {
	member      PrdMember
	scope_node  C.TSNode
	violating   TypeResponse
	initializer TypeResponse
	// The type annotation is asked for: the member is a property without one, with a value, an
	// identifier for a name and modifications in the constructor.
	wants_annotation bool
mut:
	enum_node ?C.TSNode // the declaration the name of the type resolves to, if it is an enum
}

fn (mut c Checker) lint_prefer_readonly(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	options := prd_options(c.rule_options(prefer_readonly))!
	mut sw := time.new_stopwatch()
	mut classes := []PrdClass{}
	mut index := map[u64]int{}
	mut spans := []Span{}
	for node in c.nodes_of_kinds(root, prd_class_kinds, []string{}) {
		mut class := PrdClass{
			node: node
			span: prtt_class_span(node)
		}
		spans << class.span
		if body := node_field(node, 'body') {
			for member in named_children(body) {
				match node_kind(member) {
					'public_field_definition' {
						if declared := c.prd_declared(member, false, options) {
							class.members << declared
							// The types the annotation may need.
							if value := node_field(member, 'value') {
								spans << member_span(member)
								spans << node_span(unwrap_parens(value))
							}
						}
					}
					'method_definition', 'method_signature' {
						// enterConstructor: the parameter properties.
						if !c.pfa_is_constructor(member) {
							continue
						}
						parameters := node_field(member, 'parameters') or { continue }
						for parameter in named_children(parameters) {
							if node_kind(parameter) !in ['required_parameter', 'optional_parameter'] {
								continue
							}
							if declared := c.prd_declared(parameter, true, options) {
								class.members << declared
							}
						}
					}
					else {}
				}
			}
		}
		index[node_key(node)] = classes.len
		classes << class
	}
	if classes.len > 0 {
		for access in c.nodes_of_kinds(root, member_kinds, type_name_kinds) {
			name := c.prd_modified_name(access) or { continue }
			// The class the access is in, and whether it is directly in its constructor.
			mut owner := -1
			mut first_function := ?C.TSNode(none)
			mut node := access
			for {
				node = node_parent(node) or { break }
				kind := node_kind(node)
				if kind in function_kinds && first_function == none {
					first_function = node
				}
				if kind in prd_class_kinds {
					owner = index[node_key(node)] or { -1 }
					break
				}
			}
			if owner < 0 {
				continue
			}
			mut in_constructor := false
			if function := first_function {
				if node_kind(function) == 'method_definition' && c.pfa_is_constructor(function) {
					if body := node_parent(function) {
						if class_node := node_parent(body) {
							in_constructor = node_key(class_node) == node_key(classes[owner].node)
						}
					}
				}
			}
			object := unwrap_parens(node_field(access, 'object') or { continue })
			classes[owner].accesses << PrdAccess{
				object:         object
				name:           name
				in_constructor: in_constructor
			}
			spans << node_span(object)
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut reports := []PrdReport{}
	mut enum_spans := []Span{}
	for class in classes {
		if class.members.len == 0 {
			continue
		}
		mut class_name := ''
		if found := c.node_types[class.span.key] {
			mut class_type := found
			if class_type.flags & type_flag_intersection != 0 {
				parts := c.members_of(class_type)!
				if parts.len > 0 {
					class_type = parts[0]
				}
			}
			if class_type.symbol != 0 {
				class_name = c.symbol_of(class_type)!.name
			}
		}
		mut member_modifications := map[string]bool{}
		mut static_modifications := map[string]bool{}
		mut constructor_modifications := map[string]bool{}
		for access in class.accesses {
			modifier_type := c.node_type(access.object) or { continue }
			relation := c.prd_relation(modifier_type, class_name, 0)!
			if relation == .instance && access.in_constructor {
				constructor_modifications[access.name] = true
				continue
			}
			if relation in [.instance, .class_and_instance] {
				member_modifications[access.name] = true
			}
			if relation in [.class, .class_and_instance] {
				static_modifications[access.name] = true
			}
		}
		// A later member with the same name replaces an earlier one.
		mut by_name := map[string]PrdMember{}
		mut order := []string{}
		for member in class.members {
			key := '${if member.is_static { 's' } else { 'i' }}:${member.name}'
			if key !in by_name {
				order << key
			}
			by_name[key] = member
		}
		for key in order {
			member := by_name[key]
			modified := if member.is_static {
				static_modifications[member.name]
			} else {
				member_modifications[member.name]
			}
			if modified {
				continue
			}
			mut report := PrdReport{
				member:     member
				scope_node: member.node
			}
			if !member.is_parameter && node_kind(member.name_node) == 'property_identifier'
				&& constructor_modifications[member.name] {
				if _ := node_field(member.node, 'type') {
				} else if value := node_field(member.node, 'value') {
					violating := c.node_types[member_span(member.node).key] or { TypeResponse{} }
					initializer := c.node_type(unwrap_parens(value)) or { TypeResponse{} }
					report = PrdReport{
						...report
						violating:        violating
						initializer:      initializer
						wants_annotation: !violating.is_null() && !initializer.is_null()
					}
				}
			}
			// The annotation of an enum must be a name in scope that is that enum.
			if report.wants_annotation && report.initializer.flags & prd_type_flag_enum_literal != 0 {
				if enum_node := c.prd_enum_in_scope(member.node, c.type_string(report.violating)!) {
					report.enum_node = enum_node
					enum_spans << prd_declaration_span(enum_node)
				}
			}
			reports << report
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	sw.restart()
	c.resolve_spans(enum_spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for report in reports {
		member := report.member
		mut fixes := [fix_insert_at(c.prd_readonly_position(member), 'readonly ')]
		annotation := c.prd_type_annotation(report)!
		if annotation != '' {
			fixes << fix_insert_at(node_end(member.name_node), ': ${annotation}')
		}
		findings << c.with_fixes(Finding{
			stmt:       member_start(member.node)
			message_id: 'preferReadonly'
			data:       {
				'name': c.prd_name_text(member)
			}
		}, fixes)!
	}
	findings.sort_with_compare(compare_findings)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += classes.len
	return findings
}

// prd_declared ports addDeclaredVariable for a class property or a parameter of a constructor:
// it is private (or its name is a `#name`), neither readonly nor an accessor, and has a name
// getMemberName knows. A parameter must have the `private` modifier.
fn (c &Checker) prd_declared(node C.TSNode, is_parameter bool, options PrdOptions) ?PrdMember {
	name_node := node_field(node, if is_parameter { 'pattern' } else { 'name' })?
	mut is_private := false
	for child in children(node) {
		if node_kind(child) == 'accessibility_modifier' && c.text(child) == 'private' {
			is_private = true
		}
	}
	if is_parameter && !is_private {
		return none
	}
	if !is_private && node_kind(name_node) != 'private_property_identifier' {
		return none
	}
	if has_child_kind(node, 'readonly') || has_child_kind(node, 'accessor') {
		return none
	}
	if options.only_inline_lambdas {
		if value := node_field(node, 'value') {
			if node_kind(unwrap_parens(value)) != 'arrow_function' {
				return none
			}
		}
	}
	name := c.prd_member_name(name_node)?
	return PrdMember{
		node:         node
		name_node:    name_node
		name:         name
		is_static:    !is_parameter && has_child_kind(node, 'static')
		is_parameter: is_parameter
	}
}

// prd_member_name ports getMemberName: the text of an identifier, of a `#name`, of a string or of
// a number; for a computed name, that of a number or the source of `Symbol.something`.
fn (c &Checker) prd_member_name(name C.TSNode) ?string {
	match node_kind(name) {
		'property_identifier', 'identifier' {
			return c.identifier_name(name)
		}
		'private_property_identifier' {
			return c.text(name)
		}
		'string' {
			return c.literal_string_value(name)
		}
		'number' {
			return js_number_string(c.text(name))
		}
		'computed_property_name' {
			expression := first_named(name)?
			if node_kind(expression) == 'number' {
				return js_number_string(c.text(expression))
			}
			if node_kind(expression) == 'member_expression' {
				object := node_field(expression, 'object')?
				if node_kind(object) == 'identifier' && c.text(object) == 'Symbol' {
					return c.text(expression)
				}
			}
			return none
		}
		else {
			return none
		}
	}
}

// prd_modified_name is the name of the member an access modifies, if it does (the MemberExpression
// handler): for `a.b`, by the shape of its parents; for `a['b']`, only as the target of an
// assignment, with its static name.
fn (mut c Checker) prd_modified_name(access C.TSNode) ?string {
	parent := node_parent(access)?
	parent_kind := node_kind(parent)
	if node_kind(access) == 'subscript_expression' {
		if parent_kind !in ['assignment_expression', 'augmented_assignment_expression',
			'assignment_pattern'] {
			return none
		}
		left := node_field(parent, 'left')?
		if node_key(left) != node_key(access) || node_kind(left) != 'subscript_expression' {
			return none
		}
		return c.static_member_string(access)
	}
	property := node_field(access, 'property')?
	name := if node_kind(property) == 'private_property_identifier' {
		c.text(property)
	} else {
		c.identifier_name(property)
	}
	// handleParentBinaryExpression
	if parent_kind in prd_binary_kinds {
		if parent_kind in ['binary_expression', 'sequence_expression'] {
			return none
		}
		left := node_field(parent, 'left')?
		if node_key(left) == node_key(access) && node_kind(left) == 'member_expression' {
			return name
		}
		return none
	}
	if (parent_kind == 'unary_expression' && operator_of(parent) == 'delete')
		|| prd_is_destructuring_assignment(access) {
		return name
	}
	// `++` and `--`.
	if parent_kind == 'update_expression' {
		return name
	}
	return none
}

// prd_is_destructuring_assignment ports isDestructuringAssignment: from the parent of the access,
// up through array and object literals and their spreads, to a `=` whose left side that is.
fn prd_is_destructuring_assignment(access C.TSNode) bool {
	mut current := node_parent(access) or { return false }
	for {
		parent := node_parent(current) or { break }
		kind := node_kind(parent)
		if kind in ['object', 'object_pattern', 'array', 'array_pattern'] {
			current = parent
		} else if kind in ['spread_element', 'rest_pattern'] {
			// A SpreadAssignment, or a SpreadElement of an array literal.
			grandparent := node_parent(parent) or { break }
			if node_kind(grandparent) !in ['object', 'object_pattern', 'array', 'array_pattern'] {
				break
			}
			current = parent
		} else if kind in prd_binary_kinds && node_kind(current) != 'member_expression' {
			if kind !in ['assignment_expression', 'assignment_pattern'] {
				return false
			}
			left := node_field(parent, 'left') or { return false }
			return node_key(left) == node_key(current) && node_kind(left) == node_kind(current)
		} else {
			break
		}
	}
	return false
}

// prd_relation ports getTypeToClassRelation: the type is the class (its static side), an
// instance of it, both or neither. typeIsOrHasBaseType compares the names of the symbols.
fn (mut c Checker) prd_relation(t TypeResponse, class_name string, depth int) !PrdRelation {
	if depth >= max_type_depth {
		return .none
	}
	if t.flags & type_flag_intersection != 0 {
		mut result := PrdRelation.none
		for part in c.members_of(t)! {
			match c.prd_relation(part, class_name, depth + 1)! {
				.class {
					if result == .instance {
						return .class_and_instance
					}
					result = .class
				}
				.instance {
					if result == .class {
						return .class_and_instance
					}
					result = .instance
				}
				else {}
			}
		}
		return result
	}
	if t.flags & type_flag_union != 0 {
		// A union with something else has no access to private members.
		parts := c.members_of(t)!
		if parts.len == 0 {
			return .none
		}
		return c.prd_relation(parts[0], class_name, depth + 1)!
	}
	if t.symbol == 0 || class_name == '' {
		return .none
	}
	mut related := c.symbol_of(t)!.name == class_name
	if !related && t.flags & type_flag_object != 0
		&& t.object_flags & prd_object_flags_class_or_interface != 0 {
		for base in c.client.base_types(c.snapshot, c.project, t.id)! {
			if base.symbol != 0 && c.symbol_of(base)!.name == class_name {
				related = true
				break
			}
		}
	}
	if !related {
		return .none
	}
	if t.flags & type_flag_object != 0 && t.object_flags & prd_object_flag_anonymous != 0 {
		return .class
	}
	return .instance
}

// prd_name_text is the source of the name of the member (of what is inside the brackets, for a
// computed name).
fn (c &Checker) prd_name_text(member PrdMember) string {
	if node_kind(member.name_node) == 'computed_property_name' {
		if expression := first_named(member.name_node) {
			return c.text(unwrap_parens(expression))
		}
	}
	if member.is_parameter {
		// The Identifier of a parameter spans its `?` and its type annotation.
		mut end := node_end(member.name_node)
		for child in children(member.node) {
			if node_kind(child) in ['?', 'type_annotation'] && node_start(child) >= end {
				end = node_end(child)
			}
		}
		return c.src[node_start(member.name_node)..end]
	}
	return c.text(member.name_node)
}

// prd_readonly_position is where `readonly ` goes: before the name or, for a computed name,
// before the token that comes before what is inside the brackets.
fn (mut c Checker) prd_readonly_position(member PrdMember) int {
	if node_kind(member.name_node) == 'computed_property_name' {
		if expression := first_named(member.name_node) {
			if token := c.token_before(unwrap_parens(expression)) {
				return token.start
			}
		}
	}
	return node_start(member.name_node)
}

// prd_enum_in_scope: the declaration of the first type definition of the variable called `name`
// in the scope of the member, when it is an enum.
fn (mut c Checker) prd_enum_in_scope(member C.TSNode, name string) ?C.TSNode {
	mut root := member
	for {
		root = node_parent(root) or { break }
	}
	tree := c.scope_tree(root)
	variable := tree.find_variable(tree.get_scope(member), name, -1)
	if variable < 0 {
		return none
	}
	for definition in tree.variables[variable].defs {
		if definition.kind.is_type_definition() {
			if node_kind(definition.node) == 'enum_declaration' {
				return definition.node
			}
			return none
		}
	}
	return none
}

// prd_declaration_span is the TypeScript node of a declaration: `export` and `declare` are its
// modifiers.
fn prd_declaration_span(declaration C.TSNode) Span {
	mut first := declaration
	for {
		parent := node_parent(first) or { break }
		if node_kind(parent) !in ['export_statement', 'ambient_declaration'] {
			break
		}
		first = parent
	}
	return Span{
		key:   node_key(declaration)
		first: first
		end:   node_end(declaration)
	}
}

// prd_type_annotation ports the type annotation of the fix (getTypeAnnotationForViolatingNode):
// with `readonly`, a property initialized with a literal would have the type of that literal,
// and the assignments of the constructor would not fit. '' when the widened type is the same or
// cannot be named.
fn (mut c Checker) prd_type_annotation(report PrdReport) !string {
	if !report.wants_annotation || report.initializer.id == report.violating.id {
		return ''
	}
	if report.initializer.flags & prd_type_flags_literal == 0 {
		return ''
	}
	annotation := c.type_string(report.violating)!
	if report.initializer.flags & prd_type_flag_enum_literal != 0 {
		enum_node := report.enum_node or { return '' }
		definition_type := c.node_type(enum_node) or { return '' }
		if definition_type.id != report.violating.id {
			return ''
		}
	}
	return annotation
}
