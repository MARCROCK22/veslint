module rules

import json2
import time
import tsgo { TypeResponse, handle_index, handle_kind, handle_path }
import treesitter { named_children, node_end, node_field, node_kind, node_parent, node_start, nodes_of_kinds, position_of }

// Port of the `no-base-to-string` rule of typescript-eslint 8.62.0, with its options.

const nbts_messages = {
	'baseArrayJoin': "Using `join()` for {{name}} {{certainty}} use Object's default stringification format ('[object Object]') when stringified."
	'baseToString':  "'{{name}}' {{certainty}} use Object's default stringification format ('[object Object]') when stringified."
}

// NbtsUsefulness ports Usefulness.
enum NbtsUsefulness {
	always
	never
	sometimes
}

// nbts_certainty is the text of a Usefulness in the messages.
fn nbts_certainty(u NbtsUsefulness) string {
	return match u {
		.always { 'always' }
		.never { 'will' }
		.sometimes { 'may' }
	}
}

struct NbtsOptions {
	check_unknown      bool
	ignored_type_names []string
}

fn nbts_options(options []json2.Any) !NbtsOptions {
	o := option_object(no_base_to_string, options, ['checkUnknown', 'ignoredTypeNames'])!
	mut ignored := []string{}
	if value := o.values['ignoredTypeNames'] {
		if value !is []json2.Any {
			return error('option `ignoredTypeNames` of `${no_base_to_string}` must be a list of names')
		}
		for item in value.as_array() {
			if item !is string {
				return error('option `ignoredTypeNames` of `${no_base_to_string}` must be a list of names')
			}
			ignored << item as string
		}
	}
	return NbtsOptions{
		check_unknown:      o.bool_value('checkUnknown')!
		ignored_type_names: ignored
	}
}

// NbtsCheck is an expression the rule checks: its node (ESTree, without parentheses) and whether
// its type is given (the `+` operands) or constrained (`join`).
enum NbtsCheckKind {
	to_string // checkExpression with the type at the node
	join      // checkExpressionForArrayJoin with the constrained type
}

struct NbtsCheck {
	node C.TSNode
	kind NbtsCheckKind
}

// NbtsAddition is a `+` or `+=` whose operands are checked against each other.
struct NbtsAddition {
	left  C.TSNode
	right C.TSNode
}

fn (mut c Checker) lint_no_base_to_string(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := nbts_options(c.rule_options(no_base_to_string))!
	mut additions := []NbtsAddition{}
	mut checks := []NbtsCheck{}
	mut string_calls := []C.TSNode{} // `String(x)` calls and their argument
	mut string_args := []C.TSNode{}
	for node in c.nodes_of_kinds(root, ['binary_expression', 'augmented_assignment_expression',
		'call_expression', 'template_string'], []string{}) {
		match node_kind(node) {
			'binary_expression', 'augmented_assignment_expression' {
				wanted := if node_kind(node) == 'binary_expression' { '+' } else { '+=' }
				if operator_of(node) != wanted {
					continue
				}
				left := node_field(node, 'left') or { continue }
				right := node_field(node, 'right') or { continue }
				additions << NbtsAddition{
					left:  unwrap_parens(left)
					right: unwrap_parens(right)
				}
			}
			'call_expression' {
				args := call_arguments(node) or { continue }
				callee := unwrap_parens(node_field(node, 'function') or { continue })
				if estree_type(callee) == 'Identifier' && c.identifier_name(callee) == 'String'
					&& args.len > 0 && node_kind(args[0]) != 'spread_element' {
					string_calls << node
					string_args << unwrap_parens(args[0])
				}
				// `CallExpression > MemberExpression.callee > Identifier.property`: `x.join()`,
				// `x.toString()`, `x.toLocaleString()` (also `x[join]()` with a variable `join`).
				if estree_type(callee) != 'MemberExpression' {
					continue
				}
				property := member_property(callee) or { continue }
				if node_kind(property) !in ['property_identifier', 'identifier'] {
					continue
				}
				object := unwrap_parens(node_field(callee, 'object') or { continue })
				name := c.identifier_name(property)
				if name == 'join' {
					checks << NbtsCheck{
						node: object
						kind: .join
					}
				} else if name in ['toString', 'toLocaleString'] {
					checks << NbtsCheck{
						node: object
						kind: .to_string
					}
				}
			}
			'template_string' {
				// Tagged templates are not checked.
				if parent := node_parent(node) {
					if node_kind(parent) == 'call_expression' {
						if args := node_field(parent, 'arguments') {
							if node_key(args) == node_key(node) {
								continue
							}
						}
					}
				}
				for sub in named_children(node) {
					if node_kind(sub) == 'template_substitution' {
						if expression := first_named(sub) {
							checks << NbtsCheck{
								node: unwrap_parens(expression)
								kind: .to_string
							}
						}
					}
				}
			}
			else {}
		}
	}
	mut spans := []Span{}
	for a in additions {
		spans << node_span(a.left)
		spans << node_span(a.right)
	}
	spans << string_args.map(node_span(it))
	spans << checks.map(node_span(it.node))
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	// Findings come out in the order of the visitors; veslint sorts them by position.
	for a in additions {
		left_type := c.node_type(a.left) or { continue }
		right_type := c.node_type(a.right) or { continue }
		if c.type_name(left_type, 0)! == 'string' {
			c.nbts_check_expression(a.right, right_type, o, mut findings)!
		} else if c.type_name(right_type, 0)! == 'string' {
			c.nbts_check_expression(a.left, left_type, o, mut findings)!
		}
	}
	if string_calls.len > 0 {
		scopes := c.scope_tree(root)
		for i, call in string_calls {
			// isBuiltInStringCall: no declaration of `String` in the scope of the call itself.
			v := scopes.own_variable(scopes.get_scope(call), 'String')
			if v >= 0 && scopes.variables[v].defs.len > 0 {
				continue
			}
			t := c.node_type(string_args[i]) or { continue }
			c.nbts_check_expression(string_args[i], t, o, mut findings)!
		}
	}
	for check in checks {
		t := c.node_type(check.node) or { continue }
		if check.kind == .join {
			certainty := c.nbts_join_certainty(c.constrained(t)!, o, []int{}, 0)!
			if certainty != .always {
				findings << Finding{
					stmt:       position_of(check.node)
					message_id: 'baseArrayJoin'
					data:       {
						'name':      c.nbts_text(check.node)
						'certainty': nbts_certainty(certainty)
					}
				}
			}
		} else {
			c.nbts_check_expression(check.node, t, o, mut findings)!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += additions.len + string_calls.len + checks.len
	return findings
}

// nbts_text is sourceCode.getText of an ESTree node (its tokens, without a trailing comment).
fn (c &Checker) nbts_text(n C.TSNode) string {
	return c.src[node_start(n)..c.tokens.last_end(node_end(n))]
}

// nbts_check_expression ports checkExpression.
fn (mut c Checker) nbts_check_expression(n C.TSNode, t TypeResponse, o NbtsOptions, mut findings []Finding) ! {
	if estree_type(n) == 'Literal' {
		return
	}
	certainty := c.nbts_to_string_certainty(t, o, []int{}, 0)!
	if certainty == .always {
		return
	}
	findings << Finding{
		stmt:       position_of(n)
		message_id: 'baseToString'
		data:       {
			'name':      c.nbts_text(n)
			'certainty': nbts_certainty(certainty)
		}
	}
}

// nbts_union_certainty ports collectUnionTypeCertainty.
fn nbts_union_certainty(certainties []NbtsUsefulness) NbtsUsefulness {
	if certainties.all(it == .never) {
		return .never
	}
	if certainties.all(it == .always) {
		return .always
	}
	return .sometimes
}

// nbts_tuple_certainty ports collectTupleCertainty.
fn (mut c Checker) nbts_tuple_certainty(t TypeResponse, o NbtsOptions, visited []int, depth int) !NbtsUsefulness {
	mut certainties := []NbtsUsefulness{}
	for arg in c.type_args(t)! {
		certainties << c.nbts_to_string_certainty(arg, o, visited, depth + 1)!
	}
	if certainties.any(it == .never) {
		return .never
	}
	if certainties.any(it == .sometimes) {
		return .sometimes
	}
	return .always
}

// nbts_join_certainty ports collectJoinCertainty.
fn (mut c Checker) nbts_join_certainty(t TypeResponse, o NbtsOptions, visited []int, depth int) !NbtsUsefulness {
	if depth > max_rte_depth {
		return .always
	}
	if t.flags & type_flag_union != 0 {
		mut certainties := []NbtsUsefulness{}
		for part in c.members_of(t)! {
			certainties << c.nbts_join_certainty(part, o, visited, depth + 1)!
		}
		return nbts_union_certainty(certainties)
	}
	if t.flags & type_flag_intersection != 0 {
		for part in c.members_of(t)! {
			if c.nbts_join_certainty(part, o, visited, depth + 1)! == .always {
				return .always
			}
		}
		return .never
	}
	if c.is_tuple(t)! {
		return c.nbts_tuple_certainty(t, o, visited, depth)!
	}
	if c.is_array(t)! {
		return c.nbts_to_string_certainty(c.number_index_type(t)!, o, visited, depth + 1)!
	}
	return .always
}

// nbts_to_string_certainty ports collectToStringCertainty.
fn (mut c Checker) nbts_to_string_certainty(t TypeResponse, o NbtsOptions, visited []int, depth int) !NbtsUsefulness {
	if t.id in visited || depth > max_rte_depth {
		// A self-referencing array or tuple type.
		return .always
	}
	if t.flags & type_flag_type_parameter != 0 {
		constraint := c.constraint_of(t)!
		if !constraint.is_null() {
			return c.nbts_to_string_certainty(constraint, o, visited, depth + 1)!
		}
		// An unconstrained generic means `unknown`.
		return if o.check_unknown { NbtsUsefulness.sometimes } else { NbtsUsefulness.always }
	}
	// The Boolean type definition misses toString() (tsutils.isTypeFlagSet: own flags).
	if t.flags & (u32(256) | type_flag_boolean_literal) != 0 {
		return .always
	}
	if c.nbts_ignored_generic_declaration(t, o)! {
		return .always
	}
	mut seen := map[int]bool{}
	if c.nbts_matches_type_or_base_type(t, o, mut seen)! {
		return .always
	}
	if t.flags & type_flag_intersection != 0 {
		for part in c.members_of(t)! {
			if c.nbts_to_string_certainty(part, o, visited, depth + 1)! == .always {
				return .always
			}
		}
		return .never
	}
	if t.flags & type_flag_union != 0 {
		mut certainties := []NbtsUsefulness{}
		for part in c.members_of(t)! {
			certainties << c.nbts_to_string_certainty(part, o, visited, depth + 1)!
		}
		return nbts_union_certainty(certainties)
	}
	if c.is_tuple(t)! {
		mut inner := visited.clone()
		inner << t.id
		return c.nbts_tuple_certainty(t, o, inner, depth)!
	}
	if c.is_array(t)! {
		mut inner := visited.clone()
		inner << t.id
		return c.nbts_to_string_certainty(c.number_index_type(t)!, o, inner, depth + 1)!
	}
	match c.nbts_is_to_string_like_from_object(t)! {
		.unknown {
			if o.check_unknown && t.flags == type_flag_unknown {
				return .sometimes
			}
			return .always
		}
		.from_object {
			return .never
		}
		.user_defined {
			return .always
		}
	}
}

// nbts_ignored_generic_declaration: the first declaration of the alias symbol (or the symbol) of
// the type is a type alias, an interface or a class with type parameters, and its name is ignored.
fn (mut c Checker) nbts_ignored_generic_declaration(t TypeResponse, o NbtsOptions) !bool {
	symbol := if t.alias_symbol != 0 {
		c.alias_symbol_of(t)!
	} else if t.symbol != 0 {
		c.symbol_of(t)!
	} else {
		return false
	}
	if symbol.is_null() || symbol.declarations.len == 0
		|| unescape_name(symbol.name) !in o.ignored_type_names {
		return false
	}
	declaration := symbol.declarations[0]
	kind := handle_kind(declaration)
	if kind !in [syntax_kind_type_alias_declaration, syntax_kind_interface_declaration,
		syntax_kind_class_declaration] {
		return false
	}
	tree := c.declaration_ast(handle_path(declaration))!
	return tree.node_child(handle_index(declaration), 'typeParameters') != 0
}

// nbts_matches_type_or_base_type ports matchesTypeOrBaseType with the matcher of the rule: the
// getTypeName of the type or of a base type is ignored.
fn (mut c Checker) nbts_matches_type_or_base_type(t TypeResponse, o NbtsOptions, mut seen map[int]bool) !bool {
	if t.id in seen {
		return false
	}
	seen[t.id] = true
	if c.type_name(t, 0)! in o.ignored_type_names {
		return true
	}
	for base in c.base_types_for_type(t)! {
		if c.nbts_matches_type_or_base_type(base, o, mut seen)! {
			return true
		}
	}
	return false
}

// NbtsObjectStringification is the result of isToStringLikeFromObject (undefined, true, false).
enum NbtsObjectStringification {
	unknown      // no toLocaleString, toString or valueOf with declarations
	from_object  // only the ones of the Object interface
	user_defined // a [Symbol.toPrimitive] method or another declaration
}

// nbts_is_to_string_like_from_object ports isToStringLikeFromObject.
fn (mut c Checker) nbts_is_to_string_like_from_object(t TypeResponse) !NbtsObjectStringification {
	// An explicit [Symbol.toPrimitive] method declaration is always user-defined.
	for property in c.properties(t)! {
		if property.name.starts_with('__@toPrimitive') && property.value_declaration != ''
			&& c.nbts_is_symbol_to_primitive_method(property.value_declaration)! {
			return .user_defined
		}
	}
	mut found_on_object := false
	for name in ['toLocaleString', 'toString', 'valueOf'] {
		candidate := c.property(t, name)!
		if candidate.is_null() || candidate.declarations.len == 0 {
			continue
		}
		for declaration in candidate.declarations {
			tree := c.declaration_ast(handle_path(declaration))!
			parent := tree.node_parent(handle_index(declaration))
			if tree.node_kind(parent) != syntax_kind_interface_declaration
				|| tree.node_text(tree.node_child(parent, 'name')) != 'Object' {
				return .user_defined
			}
		}
		found_on_object = true
	}
	return if found_on_object { NbtsObjectStringification.from_object } else { .unknown }
}

// nbts_is_symbol_to_primitive_method ports isSymbolToPrimitiveMethod: a method signature named
// `[Symbol.toPrimitive]` whose `Symbol` is the one of the standard library.
fn (mut c Checker) nbts_is_symbol_to_primitive_method(declaration string) !bool {
	if handle_kind(declaration) != syntax_kind_method_signature {
		return false
	}
	tree := c.declaration_ast(handle_path(declaration))!
	name := tree.node_child(handle_index(declaration), 'name')
	if tree.node_kind(name) != syntax_kind_computed_property_name {
		return false
	}
	access := tree.node_child(name, 'expression')
	if tree.node_kind(access) != syntax_kind_property_access_expression {
		return false
	}
	object := tree.node_child(access, 'expression')
	property := tree.node_child(access, 'name')
	if tree.node_kind(object) != syntax_kind_identifier || tree.node_text(object) != 'Symbol'
		|| tree.node_kind(property) != syntax_kind_identifier
		|| tree.node_text(property) != 'toPrimitive' {
		return false
	}
	symbols := c.client.symbols_at_locations(c.snapshot, c.project, [tree.node_handle(object)])!
	if symbols.len == 0 || symbols[0].is_null() {
		return false
	}
	for d in symbols[0].declarations {
		if c.is_default_library(handle_path(d))! {
			return true
		}
	}
	return false
}
