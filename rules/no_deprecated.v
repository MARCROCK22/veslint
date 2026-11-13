module rules

import json2
import strings
import time
import tsgo { AstTree, SymbolResponse, TypeResponse, handle_index, handle_kind, handle_path }
import treesitter { Ident, children, named_children, node_end, node_field, node_kind, node_parent, node_start, nodes_of_kind, nodes_of_kinds, position_of }

// Port of the `no-deprecated` rule of typescript-eslint 8.62.0, with its `allow` option (bare names
// and `from: "lib"` specifiers, like the other rules). veslint reads no JSX, so the JSX parts of the
// rule do not apply.
//
// The rule reads the @deprecated tags with TypeScript 6's symbol.getJsDocTags and
// Signature.getJsDocTags. veslint ports them on the declaration ASTs (declaration_ast) instead of
// asking tsgo's getJsDocTags, which differs from TypeScript 6 (TypeScript 7.0.2):
// - it leaves out the JSDoc of the initializer of a variable-like declaration, which TypeScript 6
//   lists first: `const f = /** @deprecated x */ () => {}` has no tags;
// - it leaves out the @param and @template tags of parameters and type parameters;
// - it does not inherit the tags of the member a declaration overrides (findBaseOfDeclaration):
//   `class C extends B { m() {} }` has none where TypeScript 6 gives those of `B.m`;
// - it renders links as their source, `{@link X | Text}`, where TypeScript 6 (buildLinkParts) joins
//   the name and the text: `{@link XText}`.
// Its AST has no JSDocMemberName either: `{@link A#b}` is a QualifiedName that tsgo resolves, while
// TypeScript 6 renders it unresolved (getSymbolAtLocation does not take a JSDocMemberName); veslint
// tells it by the `#` of its source text.
//
// TypeScript 6's binder adds the object of a top-level expando assignment, `f` in `f.x = …`, to the
// declarations of the function `f` (bindPotentiallyMissingNamespaces), so the JSDoc of a defaulted
// one, `/** @deprecated */ f.x = a || b;`, deprecates `f` too. tsgo's symbol of `f` has no such
// declaration: ndep_expando_declarations adds them.

const ndep_messages = {
	'deprecated':           '`{{name}}` is deprecated.'
	'deprecatedWithReason': '`{{name}}` is deprecated. {{reason}}'
}

// SymbolFlags.Alias of TypeScript 7.1.0-beta.
const ndep_symbol_flag_alias = u32(2097152)

// Value of jsdoc_deprecation_cache for a symbol without @deprecated tag (a JSDoc text has no NUL).
const ndep_not_deprecated = '\x00'

// SyntaxKind of TypeScript 7.1.0-beta (dist/enums/syntaxKind.enum.js).
const ndep_kind_numeric_literal = u32(8)
const ndep_kind_string_literal = u32(10)
const ndep_kind_no_substitution_template = u32(14)
const ndep_kind_bar_bar_token = u32(56)
const ndep_kind_question_question_token = u32(60)
const ndep_kind_equals_token = u32(63)
const ndep_kind_last_assignment = u32(78)
const ndep_kind_extends_keyword = u32(95)
const ndep_kind_this_keyword = u32(109)
const ndep_kind_implements_keyword = u32(118)
const ndep_kind_constructor = u32(178)
const ndep_kind_get_accessor = u32(179)
const ndep_kind_set_accessor = u32(180)
const ndep_kind_new_expression = u32(216)
const ndep_kind_parenthesized_expression = u32(219)
const ndep_kind_void_expression = u32(224)
const ndep_kind_prefix_unary_expression = u32(226)
const ndep_kind_arrow_function = u32(221)
const ndep_kind_binary_expression = u32(228)
const ndep_kind_meta_property = u32(238)
const ndep_kind_variable_statement = u32(245)
const ndep_kind_expression_statement = u32(246)
const ndep_kind_return_statement = u32(255)
const ndep_kind_variable_declaration = u32(262)
const ndep_kind_module_declaration = u32(269)
const ndep_kind_export_assignment = u32(279)
const ndep_kind_jsx_self_closing_element = u32(287)
const ndep_kind_jsx_opening_element = u32(288)
const ndep_kind_shorthand_property_assignment = u32(305)
const ndep_kind_source_file = u32(308)
const ndep_kind_jsdoc_text = u32(317)
const ndep_kind_jsdoc_link = u32(320)
const ndep_kind_jsdoc_link_code = u32(321)
const ndep_kind_jsdoc_link_plain = u32(322)
const ndep_kind_jsdoc_callback_tag = u32(332)
const ndep_kind_jsdoc_overload_tag = u32(333)
const ndep_kind_jsdoc_parameter_tag = u32(334)
const ndep_kind_jsdoc_return_tag = u32(335)
const ndep_kind_jsdoc_type_tag = u32(337)
const ndep_kind_jsdoc_template_tag = u32(338)
const ndep_kind_jsdoc_typedef_tag = u32(339)
const ndep_kind_jsdoc_satisfies_tag = u32(343)

// canHaveJSDoc.
const ndep_can_have_jsdoc = [u32(79), 170, 171, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182,
	183, 186, 187, 204, 212, 213, 214, 219, 220, 221, 228, 233, 242, 243, 244, 245, 246, 247, 248,
	249, 250, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 264, 265, 266, 267, 268,
	269, 272, 273, 274, 279, 280, 283, 298, 304, 305, 306, 307, 319]

// isLeftHandSideExpressionKind.
const ndep_left_hand_side_kinds = [u32(8), 9, 10, 13, 14, 79, 80, 96, 101, 105, 107, 109, 111,
	211, 212, 213, 214, 215, 216, 217, 219, 220, 230, 233, 235, 237, 238, 284, 286, 287, 290]

// isVariableLike: BindingElement, EnumMember, Parameter, PropertyAssignment, PropertyDeclaration,
// PropertySignature, ShorthandPropertyAssignment, VariableDeclaration.
const ndep_variable_like_kinds = [u32(210), 307, 171, 304, 174, 173, 305, 262]

// isFunctionLike: the declarations a signature comes from.
const ndep_function_like_kinds = [u32(175), 181, 319, 182, 183, 186, 187, 264, 176, 178, 179, 180,
	220, 221]

// The tree-sitter nodes the rule looks at: those of the ESTree Identifiers (with the `target` of
// `new.target`, a meta_property), PrivateIdentifiers and Supers, and the MemberExpressions with a
// computed property.
const ndep_node_kinds = ['identifier', 'jsx_identifier', 'property_identifier',
	'private_property_identifier', 'type_identifier', 'shorthand_property_identifier',
	'shorthand_property_identifier_pattern', 'super', 'this', 'undefined', 'meta_property',
	'subscript_expression']

struct NdepOptions {
	allow []TypeSpecifier
}

fn ndep_options(options []json2.Any) !NdepOptions {
	o := option_object(no_deprecated, options, ['allow'])!
	return NdepOptions{
		allow: o.specifiers('allow')!
	}
}

// NdepTags is what the rule uses of a list of JSDoc tags (JSDocTagInfo[]): whether it has any tag,
// and the text of its first @deprecated tag.
struct NdepTags {
	any        bool
	deprecated bool
	reason     string
}

// NdepReason is the result of getJsDocDeprecation: `found` is false where it is undefined.
struct NdepReason {
	found bool
	text  string
}

// NdepRole is how the ESTree parent of an identifier makes the rule check it.
enum NdepRole {
	skip           // a declaration (isDeclaration), inside an import, or not visited
	normal         // getSymbolAtLocation and its aliases
	exported       // the exported name of an ExportSpecifier
	property_key   // the key of a Property of an ObjectPattern
	property_value // the value of a Property of an ObjectExpression
	jsx_attribute  // the name of a JSXAttribute: a property of the element's props
}

// NdepCheck is an Identifier, PrivateIdentifier or Super the rule checks.
struct NdepCheck {
	node   C.TSNode
	role   NdepRole
	object C.TSNode // property roles: the ObjectExpression or ObjectPattern (node.parent.parent)
	// Call-like (getCallLikeNode): the call, `new` or tagged template whose callee ends at the node,
	// and whether the callee's symbol is the node's (the callee is the node or a member whose
	// property it is) rather than undefined (a computed member).
	call      ?C.TSNode
	from_node bool
	meta_name bool // the `target` of `new.target` (`node` is the meta_property)
}

// NdepMember is a MemberExpression with a computed property.
struct NdepMember {
	object   C.TSNode
	property C.TSNode
}

// NdepState holds what the rule computes for a file.
struct NdepState {
mut:
	symbol_tags map[int]NdepTags // symbol.getJsDocTags, by symbol id
	in_progress map[int]bool     // symbols whose tags are being computed
	// symbol.getContextualJsDocTags of the accessors of each kind, by `<symbol id>:<kind>`
	contextual_tags   map[string]NdepTags
	declaration_tags  map[string]NdepTags
	aliased           map[int]SymbolResponse
	immediate         map[int]SymbolResponse
	heritage_types    map[string]TypeResponse
	link_resolved     map[string]bool
	declaration_names map[string]string
}

fn (mut c Checker) lint_no_deprecated(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := ndep_options(c.rule_options(no_deprecated))!
	import_ranges := c.nodes_of_kind(root, c'import_statement').map([node_start(it), node_end(it)])
	mut checks := []NdepCheck{}
	mut members := []NdepMember{}
	for node in c.nodes_of_kinds(root, ndep_node_kinds, []string{}) {
		if node_end(node) == node_start(node) || ndep_in_ranges(node_start(node), import_ranges) {
			continue
		}
		match node_kind(node) {
			'subscript_expression' {
				if ndep_in_type_query(node) {
					continue
				}
				object := node_field(node, 'object') or { continue }
				index := node_field(node, 'index') or { continue }
				members << NdepMember{
					object:   unwrap_parens(object)
					property: unwrap_parens(index)
				}
			}
			'meta_property' {
				// Of `new.target`, `target` has the symbol of the class or function. The other names
				// (`new`, `import`, `meta`) have synthetic symbols, without declarations.
				if c.text(node).starts_with('new') {
					checks << NdepCheck{
						node:      node
						role:      .normal
						meta_name: true
					}
				}
			}
			else {
				role, object := ndep_role(node)
				if role == .skip {
					continue
				}
				mut call := ?C.TSNode(none)
				mut from_node := false
				if role == .normal {
					call, from_node = ndep_call_like(node)
				}
				checks << NdepCheck{
					node:      node
					role:      role
					object:    object
					call:      call
					from_node: from_node
				}
			}
		}
	}
	mut spans := []Span{}
	for chk in checks {
		if chk.meta_name {
			spans << Span{
				key:   node_key(chk.node)
				first: chk.node
				end:   node_end(chk.node)
				kind:  ndep_kind_meta_property
			}
		} else {
			// A type reference that is only its name has the range of that name. The reference is
			// requested first, as the rules that look at types do (type_node_span): the first
			// request of a range wins, and tsgo gives the name no type.
			if node_kind(chk.node) == 'type_identifier' {
				spans << c.type_node_span(chk.node)
			}
			spans << node_span(chk.node)
		}
		if call := chk.call {
			spans << Span{
				key:   node_key(call)
				first: call
				end:   node_end(call)
				kind:  ndep_call_kind(call)
			}
		}
		if chk.role in [.property_key, .property_value, .jsx_attribute] {
			spans << node_span(chk.object)
		}
	}
	for m in members {
		spans << node_span(m.property)
		spans << node_span(m.object)
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	// The symbol of each checked node, in one request.
	mut handles := []string{}
	mut owners := []int{}
	for i, chk in checks {
		mut handle := c.node_handles[node_key(chk.node)] or { continue }
		if chk.meta_name {
			name := c.ast.tree.node_child(handle_index(handle), 'name')
			if name == 0 {
				continue
			}
			handle = c.ast.tree.node_handle(name)
		} else if handle_kind(handle) in [syntax_kind_type_reference,
			syntax_kind_expression_with_type_arguments] {
			// The symbol is that of the name of the reference.
			property := if handle_kind(handle) == syntax_kind_type_reference {
				'typeName'
			} else {
				'expression'
			}
			name := c.ast.tree.node_child(handle_index(handle), property)
			if name == 0 {
				continue
			}
			handle = c.ast.tree.node_handle(name)
		}
		handles << handle
		owners << i
	}
	symbols := if handles.len > 0 {
		c.client.symbols_at_locations(c.snapshot, c.project, handles)!
	} else {
		[]SymbolResponse{}
	}
	if symbols.len != handles.len {
		return error('protocol: tsgo returned ${symbols.len} symbols for ${handles.len} nodes')
	}
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut st := NdepState{}
	mut findings := []Finding{}
	for j, i in owners {
		chk := checks[i]
		reason := c.ndep_check_reason(chk, symbols[j], mut st)!
		if !reason.found {
			continue
		}
		name, static_name, at := c.ndep_reported_name(chk)
		if o.allow.len > 0 {
			t := c.node_type(chk.node) or { TypeResponse{} }
			if (!t.is_null() && c.type_matches_some_specifier(t, o.allow)!)
				|| c.value_matches_some_specifier(static_name, o.allow, t)! {
				continue
			}
		}
		findings << ndep_finding(at, name, reason)
	}
	for m in members {
		// checkMemberExpression: a property of literal type, looked up by its value.
		property_type := c.node_type(m.property) or { continue }
		if property_type.flags & type_flag_literal_value == 0 {
			continue
		}
		object_type := c.node_type(m.object) or { continue }
		name := if property_type.flags & type_flag_bigint_literal != 0 {
			// String() of a PseudoBigInt object.
			'[object Object]'
		} else {
			literal_type_name(property_type)
		}
		property := c.property(object_type, name)!
		reason := c.ndep_symbol_reason(property, mut st)!
		if !reason.found {
			continue
		}
		if o.allow.len > 0 && c.type_matches_some_specifier(object_type, o.allow)! {
			continue
		}
		findings << ndep_finding(position_of(m.property), name, reason)
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checks.len + members.len
	return findings
}

fn ndep_finding(at Ident, name string, reason NdepReason) Finding {
	if reason.text == '' {
		return Finding{
			stmt:       at
			message_id: 'deprecated'
			data:       {
				'name': name
			}
		}
	}
	return Finding{
		stmt:       at
		message_id: 'deprecatedWithReason'
		data:       {
			'name':   name
			'reason': reason.text
		}
	}
}

// ndep_in_ranges: the offset is inside one of the sorted, disjoint [start, end) ranges.
fn ndep_in_ranges(offset int, ranges [][]int) bool {
	mut lo, mut hi := 0, ranges.len
	for lo < hi {
		mid := (lo + hi) / 2
		if ranges[mid][1] <= offset {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo < ranges.len && ranges[lo][0] <= offset
}

// ndep_in_type_query: a member access inside `typeof`, which typescript-estree makes a
// TSQualifiedName or a TSIndexedAccessType, not a MemberExpression.
fn ndep_in_type_query(n C.TSNode) bool {
	mut node := n
	for _ in 0 .. max_expression_depth {
		parent := node_parent(node) or { return false }
		match node_kind(parent) {
			'member_expression', 'subscript_expression', 'parenthesized_expression' {
				node = parent
			}
			'type_query' {
				return true
			}
			else {
				return false
			}
		}
	}
	return false
}

// ndep_call_kind is the SyntaxKind of a call-like node: CallExpression, TaggedTemplateExpression or
// NewExpression.
fn ndep_call_kind(call C.TSNode) u32 {
	match node_kind(call) {
		'new_expression' { return ndep_kind_new_expression }
		'jsx_self_closing_element' { return ndep_kind_jsx_self_closing_element }
		'jsx_opening_element' { return ndep_kind_jsx_opening_element }
		else {}
	}
	args := node_field(call, 'arguments') or { return syntax_kind_call_expression }
	return if node_kind(args) == 'template_string' {
		syntax_kind_tagged_template_expression
	} else {
		syntax_kind_call_expression
	}
}

// ndep_reported_name ports getReportedNodeName, with getStaticName of valueMatchesSpecifier ('' for
// `super`) and the position of the reported node.
fn (c &Checker) ndep_reported_name(chk NdepCheck) (string, string, Ident) {
	if chk.meta_name {
		return 'target', 'target', c.position_range(node_end(chk.node) - 'target'.len, node_end(chk.node))
	}
	match node_kind(chk.node) {
		'super' {
			return 'super', '', position_of(chk.node)
		}
		'private_property_identifier' {
			name := c.identifier_name(chk.node).trim_left('#')
			return '#${name}', name, position_of(chk.node)
		}
		'this' {
			return 'this', 'this', position_of(chk.node)
		}
		else {
			name := c.identifier_name(chk.node)
			// A parameter or a declarator's name has its type annotation in ESTree.
			return name, name, c.es_binding_position(chk.node)
		}
	}
}

// ndep_role tells how the rule checks an identifier from its ESTree parent: isDeclaration,
// the visitors' exceptions (an ExportAllDeclaration's name, the computed property of a member, the
// local name of an ExportSpecifier) and the Property case of getDeprecationReason. Returns the
// ObjectExpression or ObjectPattern for the Property roles.
fn ndep_role(n C.TSNode) (NdepRole, C.TSNode) {
	kind := node_kind(n)
	parent := node_parent(n) or { return NdepRole.skip, n }
	match kind {
		'statement_identifier' {
			// Labels have no symbol.
			return .skip, n
		}
		'shorthand_property_identifier' {
			// `{ a }`: the key is a declaration, the value is checked.
			return .property_value, parent
		}
		'shorthand_property_identifier_pattern' {
			// `{ a } = …`: the key is checked, the value is a declaration.
			if node_kind(parent) == 'object_assignment_pattern' {
				pattern := node_parent(parent) or { return NdepRole.skip, n }
				return .property_key, pattern
			}
			return .property_key, parent
		}
		'property_identifier', 'private_property_identifier' {
			return ndep_member_name_role(n, parent)
		}
		'type_identifier' {
			return ndep_type_identifier_role(n, parent), n
		}
		'this' {
			// A `this` parameter.
			if node_kind(parent) in ['required_parameter', 'optional_parameter'] {
				if pattern := node_field(parent, 'pattern') {
					if node_key(pattern) == node_key(n) {
						return ndep_parameter_role(parent), n
					}
				}
			}
			return .skip, n
		}
		'undefined' {
			// In a type it is TSUndefinedKeyword.
			if node_kind(parent) == 'literal_type' {
				return .skip, n
			}
			return ndep_identifier_role(n)
		}
		'super' {
			return .normal, n
		}
		'jsx_identifier' {
			// JSXIdentifier: every one but the name of a closing element (those of a member name in
			// a closing element are visited, like in the original).
			return if node_kind(parent) == 'jsx_closing_element' {
				NdepRole.skip
			} else {
				NdepRole.normal
			}, n
		}
		else {
			return ndep_identifier_role(n)
		}
	}
}

// ndep_member_name_role: a property_identifier or private_property_identifier, by its parent.
fn ndep_member_name_role(n C.TSNode, parent C.TSNode) (NdepRole, C.TSNode) {
	match node_kind(parent) {
		'pair', 'method_definition', 'method_signature', 'property_signature', 'enum_assignment',
		'enum_body', 'ambient_declaration' {
			// Keys of an ObjectExpression, MethodDefinition, TSMethodSignature, TSPropertySignature,
			// TSEnumMember.
			return .skip, n
		}
		'pair_pattern' {
			pattern := node_parent(parent) or { return NdepRole.skip, n }
			return .property_key, pattern
		}
		'jsx_attribute' {
			// getJSXAttributeDeprecation: `object` is the name of the opening element.
			element := node_parent(parent) or { return NdepRole.skip, n }
			name := node_field(element, 'name') or { return NdepRole.skip, n }
			return .jsx_attribute, name
		}
		'public_field_definition' {
			// The key of a PropertyDefinition or AccessorProperty; an abstract one is a
			// TSAbstractPropertyDefinition or TSAbstractAccessorProperty, which isDeclaration does not
			// list.
			return if ndep_is_abstract_field(parent) { NdepRole.normal } else { NdepRole.skip }, n
		}
		else {
			// MemberExpression (or TSQualifiedName) property, TSAbstractMethodDefinition key, the
			// left of `#x in y`.
			return .normal, n
		}
	}
}

fn ndep_is_abstract_field(field C.TSNode) bool {
	return children_of_kind(field, 'abstract').len > 0
}

// ndep_type_identifier_role: the names of classes, interfaces, type aliases and type parameters are
// declarations; the other type_identifiers are references (TSTypeReference, TSQualifiedName…).
fn ndep_type_identifier_role(n C.TSNode, parent C.TSNode) NdepRole {
	match node_kind(parent) {
		'class', 'class_declaration', 'abstract_class_declaration', 'interface_declaration',
		'type_alias_declaration', 'type_parameter' {
			name := node_field(parent, 'name') or { return .normal }
			return if node_key(name) == node_key(n) { NdepRole.skip } else { NdepRole.normal }
		}
		'infer_type' {
			// `infer U extends C`: U is the name of a TSTypeParameter.
			for child in named_children(parent) {
				if node_kind(child) == 'type_identifier' {
					return if node_key(child) == node_key(n) {
						NdepRole.skip
					} else {
						NdepRole.normal
					}
				}
			}
			return .normal
		}
		else {
			return .normal
		}
	}
}

// ndep_identifier_role: an `identifier` by its ESTree parent (parentheses skipped).
fn ndep_identifier_role(n C.TSNode) (NdepRole, C.TSNode) {
	parent := estree_parent(n) or { return NdepRole.skip, n }
	is_field := fn [n, parent] (field string) bool {
		value := node_field(parent, field) or { return false }
		return node_key(unwrap_parens(value)) == node_key(n)
	}
	match node_kind(parent) {
		'variable_declarator', 'function_declaration', 'function_expression', 'generator_function',
		'generator_function_declaration', 'function_signature', 'enum_declaration',
		'internal_module',
		'module' {
			// The id of a VariableDeclarator, a function or a TSEnumDeclaration or TSModuleDeclaration.
			return if is_field('name') { NdepRole.skip } else { NdepRole.normal }, n
		}
		'required_parameter', 'optional_parameter' {
			if is_field('pattern') || is_field('name') {
				return ndep_parameter_role(parent), n
			}
			return .normal, n
		}
		'arrow_function' {
			// Its parameter and its expression body: ArrowFunctionExpression is a parent isDeclaration
			// lists.
			return .skip, n
		}
		'import_alias' {
			// `import A = B`: A is the id of the TSImportEqualsDeclaration.
			first := children_of_kind(parent, 'identifier')[0] or { return NdepRole.skip, n }
			return if node_key(first) == node_key(n) { NdepRole.skip } else { NdepRole.normal }, n
		}
		'export_specifier' {
			// The local name is not visited; the exported one is (export_specifier.alias, or its name).
			if alias := node_field(parent, 'alias') {
				return if node_key(alias) == node_key(n) {
					NdepRole.exported
				} else {
					NdepRole.skip
				}, n
			}
			return .exported, n
		}
		'namespace_export', 'import_specifier', 'import_clause', 'namespace_import',
		'import_require_clause', 'array_pattern' {
			return .skip, n
		}
		'assignment_pattern' {
			return if is_field('left') { NdepRole.skip } else { NdepRole.normal }, n
		}
		'pair' {
			// The value of a Property of an ObjectExpression.
			object := node_parent(parent) or { return NdepRole.skip, n }
			return .property_value, object
		}
		'pair_pattern' {
			// The value of a Property of an ObjectPattern is a declaration.
			return .skip, n
		}
		'computed_property_name' {
			return ndep_computed_key_role(n, parent)
		}
		'subscript_expression' {
			// The computed property of a MemberExpression is left to checkMemberExpression; in
			// `typeof a[b]` it is a type.
			if is_field('index') && !ndep_in_type_query(parent) {
				return .skip, n
			}
			return .normal, n
		}
		'for_in_statement' {
			// `for (const x of …)`: x is the id of a VariableDeclarator.
			if is_field('left') {
				if _ := node_field(parent, 'kind') {
					return .skip, n
				}
			}
			return .normal, n
		}
		else {
			return .normal, n
		}
	}
}

// ndep_parameter_role: a parameter is a declaration (the parent isDeclaration sees is the function,
// a TSParameterProperty or an AssignmentPattern), except in TSFunctionType, TSConstructorType,
// TSCallSignatureDeclaration and TSConstructSignatureDeclaration.
fn ndep_parameter_role(param C.TSNode) NdepRole {
	if _ := node_field(param, 'value') {
		return .skip
	}
	for child in children(param) {
		if node_kind(child) in ['accessibility_modifier', 'override_modifier', 'readonly'] {
			return .skip
		}
	}
	formal := node_parent(param) or { return .skip }
	owner := node_parent(formal) or { return .skip }
	return if node_kind(owner) in ['function_type', 'constructor_type', 'call_signature',
		'construct_signature'] {
		NdepRole.normal
	} else {
		NdepRole.skip
	}
}

// ndep_computed_key_role: `[k]` as the key of a property or member is a declaration (the key of a
// Property of an ObjectExpression, MethodDefinition, PropertyDefinition, TSPropertySignature,
// TSMethodSignature), except in an ObjectPattern and in abstract members.
fn ndep_computed_key_role(n C.TSNode, key C.TSNode) (NdepRole, C.TSNode) {
	owner := node_parent(key) or { return NdepRole.skip, n }
	match node_kind(owner) {
		'pair_pattern' {
			pattern := node_parent(owner) or { return NdepRole.skip, n }
			return .property_key, pattern
		}
		'pair', 'method_definition', 'method_signature', 'property_signature', 'enum_assignment',
		'enum_body' {
			return .skip, n
		}
		'public_field_definition' {
			return if ndep_is_abstract_field(owner) { NdepRole.normal } else { NdepRole.skip }, n
		}
		else {
			return .normal, n
		}
	}
}

// ndep_call_like ports getCallLikeNode: the call, `new` or tagged template whose callee is the node,
// or a chain of member expressions whose properties lead to it; and whether the callee's symbol is
// the node's (false through a computed member, whose ElementAccessExpression has no symbol).
fn ndep_call_like(n C.TSNode) (?C.TSNode, bool) {
	if node_kind(n) == 'jsx_identifier' {
		// The name of a JSXOpeningElement (a self-closing element has one too in ESTree).
		parent := node_parent(n) or { return none, false }
		if node_kind(parent) in ['jsx_opening_element', 'jsx_self_closing_element'] {
			if name := node_field(parent, 'name') {
				if node_key(name) == node_key(n) {
					return parent, true
				}
			}
		}
		return none, false
	}
	mut callee := n
	mut from_node := true
	for _ in 0 .. max_expression_depth {
		if is_chain_element(callee) && is_estree_chain_root(callee) {
			// Its ESTree parent is a ChainExpression.
			return none, false
		}
		parent := estree_parent(callee) or { return none, false }
		match node_kind(parent) {
			'member_expression' {
				property := node_field(parent, 'property') or { return none, false }
				if node_key(property) != node_key(callee) {
					break
				}
			}
			'subscript_expression' {
				index := node_field(parent, 'index') or { return none, false }
				if node_key(unwrap_parens(index)) != node_key(callee) {
					break
				}
				from_node = false
			}
			else {
				break
			}
		}
		callee = parent
	}
	// isNodeCalleeOfParent
	if is_chain_element(callee) && is_estree_chain_root(callee) {
		return none, false
	}
	parent := estree_parent(callee) or { return none, false }
	kind := node_kind(parent)
	if kind != 'call_expression' && kind != 'new_expression' {
		return none, false
	}
	target := node_field(parent, if kind == 'call_expression' { 'function' } else { 'constructor' }) or {
		return none, false
	}
	if node_key(unwrap_parens(target)) != node_key(callee) {
		return none, false
	}
	return parent, from_node
}

// ndep_check_reason ports getDeprecationReason (and, for an ExportSpecifier, the visitor's check of
// the alias itself).
fn (mut c Checker) ndep_check_reason(chk NdepCheck, symbol SymbolResponse, mut st NdepState) !NdepReason {
	if chk.role == .exported {
		// Only the exported side; a deprecated alias is not reported there.
		if c.ndep_symbol_reason(symbol, mut st)!.found {
			return NdepReason{}
		}
	}
	if call := chk.call {
		return c.ndep_call_like_reason(call, if chk.from_node {
			symbol
		} else {
			SymbolResponse{}
		}, mut st)!
	}
	if chk.role == .jsx_attribute {
		// The property of that name of the contextual type of the element's name (its props).
		contextual := c.contextual_type(chk.object)!
		if contextual.is_null() {
			return NdepReason{}
		}
		return c.ndep_symbol_reason(c.property(contextual, c.text(chk.node))!, mut st)!
	}
	if chk.role in [.property_key, .property_value] {
		name := c.identifier_name(chk.node)
		object_type := c.node_type(chk.object) or { TypeResponse{} }
		property := if object_type.is_null() {
			SymbolResponse{}
		} else {
			c.property(object_type, name)!
		}
		r := c.ndep_alias_chain(symbol, true, mut st)!
		if r.found {
			return r
		}
		of_property := c.ndep_symbol_reason(property, mut st)!
		if of_property.found {
			return of_property
		}
		of_symbol := c.ndep_symbol_reason(symbol, mut st)!
		if of_symbol.found {
			return of_symbol
		}
		// getShorthandAssignmentValueSymbol(propertySymbol.valueDeclaration): only a shorthand
		// property assignment has one.
		if symbol.is_null() || symbol.value_declaration == ''
			|| handle_kind(symbol.value_declaration) != ndep_kind_shorthand_property_assignment {
			return NdepReason{}
		}
		value_symbol := c.client.shorthand_assignment_value_symbol(c.snapshot, c.project,
			symbol.value_declaration)!
		return c.ndep_symbol_reason(value_symbol, mut st)!
	}
	return c.ndep_alias_chain(symbol, true, mut st)!
}

// ndep_call_like_reason ports getCallLikeDeprecation.
fn (mut c Checker) ndep_call_like_reason(call C.TSNode, symbol SymbolResponse, mut st NdepState) !NdepReason {
	aliased := if !symbol.is_null() && symbol.flags & ndep_symbol_flag_alias != 0 {
		c.ndep_aliased(symbol, mut st)!
	} else {
		symbol
	}
	kind := if !aliased.is_null() && aliased.declarations.len > 0 {
		handle_kind(aliased.declarations[0])
	} else {
		u32(0)
	}
	// Properties with function types are deprecated on their symbols, not on their signatures.
	if kind !in [syntax_kind_method_declaration, syntax_kind_function_declaration,
		syntax_kind_method_signature] {
		r := c.ndep_alias_chain(symbol, true, mut st)!
		if r.found {
			return r
		}
		signature := c.ndep_signature_reason(call, mut st)!
		if signature.found {
			return signature
		}
		return c.ndep_symbol_reason(aliased, mut st)!
	}
	// Functions and methods: the overload the call resolves to, not the tags of all of them.
	r := c.ndep_alias_chain(symbol, false, mut st)!
	if r.found {
		return r
	}
	// The resolved signature comes from one of the declarations: when they all give the same
	// reason, getResolvedSignature is not needed.
	if aliased.declarations.all(handle_kind(it) in ndep_function_like_kinds) {
		mut same := true
		first := c.ndep_declaration_reason(aliased.declarations[0], aliased.name, mut st)!
		for declaration in aliased.declarations[1..] {
			if c.ndep_declaration_reason(declaration, aliased.name, mut st)! != first {
				same = false
				break
			}
		}
		if same {
			return first
		}
	}
	return c.ndep_signature_reason(call, mut st)!
}

// ndep_signature_reason ports getJsDocDeprecation(checker.getResolvedSignature(call)).
fn (mut c Checker) ndep_signature_reason(call C.TSNode, mut st NdepState) !NdepReason {
	signature := c.resolved_signature(call)!
	if signature.declaration == '' {
		return NdepReason{}
	}
	return c.ndep_declaration_reason(signature.declaration, '', mut st)!
}

// ndep_declaration_reason is getJsDocDeprecation of the signature of a declaration:
// Signature.getJsDocTags is getJsDocTagsOfDeclarations([declaration]). `name` is the name of the
// declaration's symbol ('' to look it up when inheriting).
fn (mut c Checker) ndep_declaration_reason(declaration string, name string, mut st NdepState) !NdepReason {
	tags := if cached := st.declaration_tags[declaration] {
		cached
	} else {
		computed := c.ndep_tags_of_declarations([declaration], name, mut st)!
		st.declaration_tags[declaration] = computed
		computed
	}
	return NdepReason{
		found: tags.deprecated
		text:  tags.reason
	}
}

// ndep_alias_chain ports searchForDeprecationInAliasesChain: the first deprecated alias of the
// chain from `symbol` to its target and, with `check_aliased`, the target.
fn (mut c Checker) ndep_alias_chain(symbol SymbolResponse, check_aliased bool, mut st NdepState) !NdepReason {
	if symbol.is_null() || symbol.flags & ndep_symbol_flag_alias == 0 {
		return if check_aliased { c.ndep_symbol_reason(symbol, mut st)! } else { NdepReason{} }
	}
	target := c.ndep_aliased(symbol, mut st)!
	mut current := symbol
	for _ in 0 .. max_expression_depth {
		if current.flags & ndep_symbol_flag_alias == 0 {
			break
		}
		r := c.ndep_symbol_reason(current, mut st)!
		if r.found {
			return r
		}
		if current.declarations.len == 0 {
			break
		}
		next := c.ndep_immediate(current, mut st)!
		if next.is_null() {
			break
		}
		current = next
		if check_aliased && current.id == target.id {
			return c.ndep_symbol_reason(current, mut st)!
		}
	}
	return NdepReason{}
}

fn (mut c Checker) ndep_aliased(symbol SymbolResponse, mut st NdepState) !SymbolResponse {
	if symbol.id !in st.aliased {
		st.aliased[symbol.id] = c.aliased_symbol(symbol.id)!
	}
	return st.aliased[symbol.id]
}

fn (mut c Checker) ndep_immediate(symbol SymbolResponse, mut st NdepState) !SymbolResponse {
	if symbol.id !in st.immediate {
		st.immediate[symbol.id] = c.client.immediate_aliased_symbol(c.snapshot, c.project,
			symbol.id)!
	}
	return st.immediate[symbol.id]
}

// ndep_symbol_reason ports getJsDocDeprecation(symbol): the text of the first @deprecated tag of
// symbol.getJsDocTags(checker), kept for the whole run in jsdoc_deprecation_cache.
fn (mut c Checker) ndep_symbol_reason(symbol SymbolResponse, mut st NdepState) !NdepReason {
	if symbol.is_null() {
		return NdepReason{}
	}
	if cached := c.jsdoc_deprecation_cache[symbol.id] {
		return if cached == ndep_not_deprecated {
			NdepReason{}
		} else {
			NdepReason{
				found: true
				text:  cached
			}
		}
	}
	tags := c.ndep_symbol_tags(symbol, mut st)!
	c.jsdoc_deprecation_cache[symbol.id] = if tags.deprecated {
		tags.reason
	} else {
		ndep_not_deprecated
	}
	return NdepReason{
		found: tags.deprecated
		text:  tags.reason
	}
}

// ndep_symbol_tags ports symbol.getJsDocTags(checker). While they are computed, the symbol has no
// tags (TypeScript's guard against inheritance cycles).
fn (mut c Checker) ndep_symbol_tags(symbol SymbolResponse, mut st NdepState) !NdepTags {
	if tags := st.symbol_tags[symbol.id] {
		return tags
	}
	if symbol.id in st.in_progress {
		return NdepTags{}
	}
	st.in_progress[symbol.id] = true
	mut declarations := symbol.declarations.clone()
	declarations << c.ndep_expando_declarations(symbol)!
	tags := c.ndep_tags_of_declarations(declarations, symbol.name, mut st)!
	st.in_progress.delete(symbol.id)
	st.symbol_tags[symbol.id] = tags
	return tags
}

// ndep_expando_declarations are the declarations TypeScript 6's binder adds to a function declared
// at the top level of a file and tsgo's symbols do not have: the `f` of each top-level assignment
// `f.x = …` of that file (bindPotentiallyMissingNamespaces), in source order. They matter because
// getNextJSDocCommentLocation gives that identifier the JSDoc of a defaulted assignment, so
// `/** @deprecated */ f.x = a || b` deprecates `f` too.
fn (mut c Checker) ndep_expando_declarations(symbol SymbolResponse) ![]string {
	if symbol.value_declaration == '' {
		return []string{}
	}
	tree := c.declaration_ast(handle_path(symbol.value_declaration))!
	declaration := handle_index(symbol.value_declaration)
	// isFunctionSymbol: a function declaration, or a variable initialized with a function.
	mut statement := declaration
	is_variable := tree.node_kind(declaration) == ndep_kind_variable_declaration
	if is_variable {
		if tree.node_kind(tree.node_child(declaration, 'initializer')) !in [
			syntax_kind_function_expression,
			ndep_kind_arrow_function,
		] {
			return []string{}
		}
		statement = tree.node_parent(tree.node_parent(declaration))
	} else if tree.node_kind(declaration) != syntax_kind_function_declaration {
		return []string{}
	}
	file := tree.node_parent(statement)
	if tree.node_kind(file) != ndep_kind_source_file {
		return []string{}
	}
	mut found := []string{}
	for child in tree.node_children(tree.node_child(file, 'statements')) {
		// Function declarations are bound first; a variable is only known after its declaration.
		if tree.node_kind(child) != ndep_kind_expression_statement || (is_variable && child < statement) {
			continue
		}
		ndep_collect_expando(tree, tree.node_child(child, 'expression'), symbol.name, mut
			found)
	}
	return found
}

// ndep_collect_expando adds the `f` of the assignments `f.x = …` of an expression statement:
// through chained assignments and commas they are still at the top level
// (isTopLevelNamespaceAssignment).
fn ndep_collect_expando(tree AstTree, expression int, name string, mut found []string) {
	if tree.node_kind(expression) != ndep_kind_binary_expression {
		return
	}
	if ndep_is_property_assignment_declaration(tree, expression) {
		object := tree.node_child(tree.node_child(expression, 'left'), 'expression')
		if tree.node_kind(object) == syntax_kind_identifier && tree.node_text(object) == name {
			found << tree.node_handle(object)
		}
	}
	ndep_collect_expando(tree, tree.node_child(expression, 'left'), name, mut found)
	ndep_collect_expando(tree, tree.node_child(expression, 'right'), name, mut found)
}

// ndep_tags_of_declarations ports getJsDocTagsOfDeclarations: the tags of the declarations
// (getJsDocTagsFromDeclarations) and, when there are none or one asks for @inheritDoc, before them
// those of the members they override.
fn (mut c Checker) ndep_tags_of_declarations(declarations []string, name string, mut st NdepState) !NdepTags {
	mut own := NdepTags{}
	mut inherit_doc := false
	mut unique := map[string]bool{}
	for declaration in declarations {
		if declaration in unique {
			continue
		}
		unique[declaration] = true
		tree := c.declaration_ast(handle_path(declaration))!
		tags := ndep_jsdoc_tags(tree, handle_index(declaration))
		kinds := tags.map(tree.node_kind(it))
		mut tag_names := []string{cap: tags.len}
		for tag in tags {
			tag_name := tree.node_text(tree.node_child(tag, 'tagName'))
			tag_names << tag_name
			if tag_name in ['inheritDoc', 'inheritdoc'] {
				inherit_doc = true
			}
		}
		// Comments with a @typedef or @callback belong to no declaration, unless they document it.
		if kinds.any(it in [ndep_kind_jsdoc_typedef_tag, ndep_kind_jsdoc_callback_tag])
			&& !kinds.any(it in [ndep_kind_jsdoc_parameter_tag, ndep_kind_jsdoc_return_tag]) {
			continue
		}
		for i, tag in tags {
			if !own.deprecated && tag_names[i] == 'deprecated' {
				own = NdepTags{
					any:        true
					deprecated: true
					reason:     c.ndep_comment_text(tree, tag, mut st)!
				}
			} else {
				own = NdepTags{
					...own
					any: true
				}
			}
		}
	}
	if own.any && !inherit_doc {
		return own
	}
	mut result := own
	mut seen := map[int]bool{}
	for declaration in declarations {
		found, inherited := c.ndep_find_base(declaration, name, mut seen, mut st)!
		if found {
			// tags = [...inherited, ...tags]
			result = NdepTags{
				any:        inherited.any || result.any
				deprecated: inherited.deprecated || result.deprecated
				reason:     if inherited.deprecated { inherited.reason } else { result.reason }
			}
		}
	}
	return result
}

// ndep_find_base ports findBaseOfDeclaration with the callback of getJsDocTagsOfDeclarations: the
// tags of the member of the first super type (extends, then implements) that has the declaration's
// name and is not `seen`, if it has a single declaration (an accessor: getContextualJsDocTags).
fn (mut c Checker) ndep_find_base(declaration string, symbol_name string, mut seen map[int]bool, mut st NdepState) !(bool, NdepTags) {
	tree := c.declaration_ast(handle_path(declaration))!
	index := handle_index(declaration)
	mut container := tree.node_parent(index)
	if container != 0 && tree.node_kind(container) == ndep_kind_constructor {
		container = tree.node_parent(container)
	}
	if container == 0 {
		return false, NdepTags{}
	}
	supers := ndep_super_type_nodes(tree, container)
	if supers.len == 0 {
		return false, NdepTags{}
	}
	name := if symbol_name != '' {
		symbol_name
	} else {
		c.ndep_declaration_name(tree, index, mut st)!
	}
	if name == '' {
		return false, NdepTags{}
	}
	is_static := ndep_has_static_modifier(tree, index)
	kind := tree.node_kind(index)
	for super_node in supers {
		base := c.ndep_heritage_type(tree, super_node, mut st)!
		if base.is_null() {
			continue
		}
		mut t := base
		if is_static && base.symbol != 0 {
			base_symbol := c.symbol_of(base)!
			if !base_symbol.is_null() {
				t = c.symbol_type(base_symbol.id)!
			}
		}
		property := c.property(t, name)!
		if property.is_null() || property.id in seen {
			continue
		}
		seen[property.id] = true
		if kind in [ndep_kind_get_accessor, ndep_kind_set_accessor] {
			return true, c.ndep_contextual_tags(property, kind, mut st)!
		}
		if property.declarations.len == 1 {
			return true, c.ndep_symbol_tags(property, mut st)!
		}
	}
	return false, NdepTags{}
}

// ndep_contextual_tags ports symbol.getContextualJsDocTags for an accessor: the tags of the
// accessors of the same kind, if any, or else those of the symbol. Like the symbol's
// contextualGetAccessorTags and contextualSetAccessorTags, they are computed once, and are empty
// while they are being computed: `class Foo implements Foo { get bar() … }` finds `bar` as its own
// base and would recurse forever.
fn (mut c Checker) ndep_contextual_tags(symbol SymbolResponse, accessor_kind u32, mut st NdepState) !NdepTags {
	key := '${symbol.id}:${accessor_kind}'
	mut tags := NdepTags{}
	if known := st.contextual_tags[key] {
		tags = known
	} else {
		st.contextual_tags[key] = NdepTags{}
		accessors := symbol.declarations.filter(handle_kind(it) == accessor_kind)
		tags = c.ndep_tags_of_declarations(accessors, symbol.name, mut st)!
		st.contextual_tags[key] = tags
	}
	if tags.any {
		return tags
	}
	return c.ndep_symbol_tags(symbol, mut st)!
}

// ndep_declaration_name is the name of the symbol of a declaration (declaration.symbol.name), from
// its name; '' without one (a signature or a constructor, which have no inheritable name) or for a
// computed name.
fn (mut c Checker) ndep_declaration_name(tree AstTree, index int, mut st NdepState) !string {
	handle := tree.node_handle(index)
	if handle in st.declaration_names {
		return st.declaration_names[handle]
	}
	mut name := ''
	name_node := tree.node_child(index, 'name')
	if name_node != 0 && tree.node_kind(name_node) != syntax_kind_computed_property_name {
		symbols := c.client.symbols_at_locations(c.snapshot, c.project, [
			tree.node_handle(name_node),
		])!
		if symbols.len == 1 && !symbols[0].is_null() {
			name = symbols[0].name
		}
	}
	st.declaration_names[handle] = name
	return name
}

// ndep_heritage_type is checker.getTypeAtLocation of a super type node.
fn (mut c Checker) ndep_heritage_type(tree AstTree, node int, mut st NdepState) !TypeResponse {
	handle := tree.node_handle(node)
	if handle !in st.heritage_types {
		types := c.client.types_at_locations(c.snapshot, c.project, [handle])!
		st.heritage_types[handle] = if types.len == 1 { types[0] } else { TypeResponse{} }
	}
	return st.heritage_types[handle]
}

// ndep_super_type_nodes ports getAllSuperTypeNodes: the types of the first `extends` clause of an
// interface; of a class, the first type of its first `extends` clause and the types of its first
// `implements` clause.
fn ndep_super_type_nodes(tree AstTree, container int) []int {
	kind := tree.node_kind(container)
	clauses := tree.node_children(tree.node_child(container, 'heritageClauses'))
	if kind == syntax_kind_interface_declaration {
		for clause in clauses {
			if tree.node_token(clause) == ndep_kind_extends_keyword {
				return tree.node_children(tree.node_child(clause, 'types'))
			}
		}
		return []int{}
	}
	if kind !in [syntax_kind_class_declaration, syntax_kind_class_expression] {
		return []int{}
	}
	mut out := []int{}
	for clause in clauses {
		if tree.node_token(clause) == ndep_kind_extends_keyword {
			types := tree.node_children(tree.node_child(clause, 'types'))
			if types.len > 0 {
				out << types[0]
			}
			break
		}
	}
	for clause in clauses {
		if tree.node_token(clause) == ndep_kind_implements_keyword {
			out << tree.node_children(tree.node_child(clause, 'types'))
			break
		}
	}
	return out
}

fn ndep_has_static_modifier(tree AstTree, index int) bool {
	return tree.node_children(tree.node_child(index, 'modifiers')).any(tree.node_kind(it) == syntax_kind_static_keyword)
}

// ndep_jsdoc_tags ports getJSDocTags (getJSDocTagsWorker): the JSDoc tags of a declaration, by
// getJSDocCommentsAndTags.
fn ndep_jsdoc_tags(tree AstTree, host int) []int {
	if tree.node_kind(host) !in ndep_can_have_jsdoc {
		return []int{}
	}
	mut out := []int{}
	// The JSDoc of a variable-like declaration's initializer comes first.
	if tree.node_kind(host) in ndep_variable_like_kinds {
		initializer := tree.node_child(host, 'initializer')
		if initializer != 0 && ndep_has_jsdoc_nodes(tree, initializer) {
			out << ndep_owned_tags(tree, host, tree.node_jsdocs(initializer))
		}
	}
	mut node := host
	for _ in 0 .. max_expression_depth {
		if node == 0 || tree.node_parent(node) == 0 {
			break
		}
		if ndep_has_jsdoc_nodes(tree, node) {
			out << ndep_owned_tags(tree, host, tree.node_jsdocs(node))
		}
		kind := tree.node_kind(node)
		if kind == syntax_kind_parameter {
			out << ndep_parameter_tags(tree, node)
			break
		}
		if kind == syntax_kind_type_parameter {
			out << ndep_type_parameter_tags(tree, node)
			break
		}
		node = ndep_next_jsdoc_location(tree, node)
	}
	return out
}

fn ndep_has_jsdoc_nodes(tree AstTree, node int) bool {
	return tree.node_kind(node) in ndep_can_have_jsdoc && tree.node_jsdocs(node).len > 0
}

// ndep_owned_tags ports filterOwnedJSDocTags: all the tags of the last comment (but a @type or
// @satisfies of a parenthesized expression, which belongs to it), and only the @overload tags of
// the others.
fn ndep_owned_tags(tree AstTree, host int, jsdocs []int) []int {
	mut out := []int{}
	for i, jsdoc in jsdocs {
		tags := tree.node_children(tree.node_child(jsdoc, 'tags'))
		for tag in tags {
			kind := tree.node_kind(tag)
			if i < jsdocs.len - 1 {
				if kind == ndep_kind_jsdoc_overload_tag {
					out << tag
				}
				continue
			}
			if kind in [ndep_kind_jsdoc_type_tag, ndep_kind_jsdoc_satisfies_tag] {
				owner := tree.node_parent(jsdoc)
				if tree.node_kind(owner) == ndep_kind_parenthesized_expression && owner != host {
					continue
				}
			}
			out << tag
		}
	}
	return out
}

// ndep_parameter_tags ports getJSDocParameterTags: the @param tags of the function that name the
// parameter or, for a binding pattern, the one at its position.
fn ndep_parameter_tags(tree AstTree, param int) []int {
	name := tree.node_child(param, 'name')
	if name == 0 {
		return []int{}
	}
	function := tree.node_parent(param)
	tags := ndep_jsdoc_tags(tree, function).filter(tree.node_kind(it) == ndep_kind_jsdoc_parameter_tag)
	if tree.node_kind(name) == syntax_kind_identifier {
		text := tree.node_text(name)
		return tags.filter(fn [tree, text] (tag int) bool {
			tag_name := tree.node_child(tag, 'name')
			return tree.node_kind(tag_name) == syntax_kind_identifier
				&& tree.node_text(tag_name) == text
		})
	}
	i := tree.node_children(tree.node_child(function, 'parameters')).index(param)
	if i >= 0 && i < tags.len {
		return [tags[i]]
	}
	return []int{}
}

// ndep_type_parameter_tags ports getJSDocTypeParameterTags: the @template tags of the declaration
// that name the type parameter.
fn ndep_type_parameter_tags(tree AstTree, type_parameter int) []int {
	text := tree.node_text(tree.node_child(type_parameter, 'name'))
	return ndep_jsdoc_tags(tree, tree.node_parent(type_parameter)).filter(fn [tree, text] (tag int) bool {
		if tree.node_kind(tag) != ndep_kind_jsdoc_template_tag {
			return false
		}
		return tree.node_children(tree.node_child(tag, 'typeParameters')).any(tree.node_text(tree.node_child(it,
			'name')) == text)
	})
}

// ndep_next_jsdoc_location ports getNextJSDocCommentLocation: the node whose JSDoc also documents
// `node` (0 if none).
fn ndep_next_jsdoc_location(tree AstTree, node int) int {
	parent := tree.node_parent(node)
	if parent == 0 {
		return 0
	}
	parent_kind := tree.node_kind(parent)
	if parent_kind in [syntax_kind_property_assignment, ndep_kind_export_assignment,
		syntax_kind_property_declaration] || (parent_kind == ndep_kind_expression_statement
		&& tree.node_kind(node) == syntax_kind_property_access_expression)
		|| parent_kind == ndep_kind_return_statement || ndep_nested_module(tree, parent)
		|| ndep_is_assignment_expression(tree, node) {
		return parent
	}
	grandparent := tree.node_parent(parent)
	if grandparent == 0 {
		return 0
	}
	if ndep_first_variable(tree, grandparent) == node || ndep_is_assignment_expression(tree, parent) {
		return grandparent
	}
	outer := tree.node_parent(grandparent)
	if outer != 0 && (ndep_first_variable(tree, outer) != 0
		|| ndep_single_initializer(tree, outer) == node
		|| ndep_source_of_defaulted_assignment(tree, outer) != 0) {
		return outer
	}
	return 0
}

// ndep_nested_module ports getNestedModuleDeclaration: `namespace A.B {}` (a module whose body is a
// module).
fn ndep_nested_module(tree AstTree, node int) bool {
	if tree.node_kind(node) != ndep_kind_module_declaration {
		return false
	}
	body := tree.node_child(node, 'body')
	return body != 0 && tree.node_kind(body) == ndep_kind_module_declaration
}

// ndep_is_assignment_expression ports isAssignmentExpression: an assignment (compound ones
// included) to a left-hand-side expression.
fn ndep_is_assignment_expression(tree AstTree, node int) bool {
	if tree.node_kind(node) != ndep_kind_binary_expression {
		return false
	}
	operator := tree.node_kind(tree.node_child(node, 'operatorToken'))
	return operator >= ndep_kind_equals_token && operator <= ndep_kind_last_assignment
		&& tree.node_kind(tree.node_child(node, 'left')) in ndep_left_hand_side_kinds
}

// ndep_first_variable ports getSingleVariableOfVariableStatement: the first declaration of a
// variable statement (0 if none).
fn ndep_first_variable(tree AstTree, node int) int {
	if tree.node_kind(node) != ndep_kind_variable_statement {
		return 0
	}
	list := tree.node_child(node, 'declarationList')
	declarations := tree.node_children(tree.node_child(list, 'declarations'))
	return if declarations.len > 0 { declarations[0] } else { 0 }
}

// ndep_single_initializer ports getSingleInitializerOfVariableStatementOrPropertyDeclaration.
fn ndep_single_initializer(tree AstTree, node int) int {
	match tree.node_kind(node) {
		ndep_kind_variable_statement {
			variable := ndep_first_variable(tree, node)
			return if variable != 0 { tree.node_child(variable, 'initializer') } else { 0 }
		}
		syntax_kind_property_declaration, syntax_kind_property_assignment {
			return tree.node_child(node, 'initializer')
		}
		else {
			return 0
		}
	}
}

// ndep_source_of_defaulted_assignment ports getSourceOfDefaultedAssignment: in `a.b = c || d` (a
// property assignment declaration), d.
fn ndep_source_of_defaulted_assignment(tree AstTree, node int) int {
	if tree.node_kind(node) != ndep_kind_expression_statement {
		return 0
	}
	expression := tree.node_child(node, 'expression')
	if tree.node_kind(expression) != ndep_kind_binary_expression
		|| !ndep_is_property_assignment_declaration(tree, expression) {
		return 0
	}
	right := tree.node_child(expression, 'right')
	if tree.node_kind(right) != ndep_kind_binary_expression {
		return 0
	}
	operator := tree.node_kind(tree.node_child(right, 'operatorToken'))
	if operator != ndep_kind_bar_bar_token && operator != ndep_kind_question_question_token {
		return 0
	}
	return tree.node_child(right, 'right')
}

// ndep_is_property_assignment_declaration: getAssignmentDeclarationKind of a binary expression in a
// TypeScript file is not None, which only AssignmentDeclarationKind.Property gives
// (getAssignmentDeclarationKindWorker and getAssignmentDeclarationPropertyAccessKind).
fn ndep_is_property_assignment_declaration(tree AstTree, expression int) bool {
	left := tree.node_child(expression, 'left')
	if tree.node_kind(tree.node_child(expression, 'operatorToken')) != ndep_kind_equals_token
		|| !ndep_is_access(tree, left) || ndep_is_void_zero(tree, ndep_right_most_assigned(tree,
		expression)) {
		return false
	}
	object := tree.node_child(left, 'expression')
	if ndep_is_bindable_static_name(tree, object, true) && ndep_access_name(tree, left) == 'prototype'
		&& tree.node_kind(ndep_binary_initializer(tree, expression)) == syntax_kind_object_literal_expression {
		// AssignmentDeclarationKind.Prototype
		return false
	}
	if tree.node_kind(object) == ndep_kind_this_keyword || ndep_is_module_exports(tree, left)
		|| !ndep_is_bindable_static_name(tree, object, true) {
		return false
	}
	if ndep_is_bindable_static_access(tree, object, false) && ndep_access_name(tree, object) == 'prototype' {
		// AssignmentDeclarationKind.PrototypeProperty
		return false
	}
	mut next_to_last := left
	for _ in 0 .. max_expression_depth {
		inner := tree.node_child(next_to_last, 'expression')
		if inner == 0 || tree.node_kind(inner) == syntax_kind_identifier {
			break
		}
		next_to_last = inner
	}
	id := tree.node_text(tree.node_child(next_to_last, 'expression'))
	if (id == 'exports' || (id == 'module' && ndep_access_name(tree, next_to_last) == 'exports'))
		&& ndep_is_bindable_static_access(tree, left, false) {
		// AssignmentDeclarationKind.ExportsProperty
		return false
	}
	return ndep_is_bindable_static_name(tree, left, true)
		|| (tree.node_kind(left) == syntax_kind_element_access_expression
			&& ndep_is_dynamic_name(tree, left))
}

fn ndep_is_access(tree AstTree, node int) bool {
	return tree.node_kind(node) in [syntax_kind_property_access_expression,
		syntax_kind_element_access_expression]
}

// ndep_is_void_zero ports isVoidZero: `void 0`.
fn ndep_is_void_zero(tree AstTree, node int) bool {
	if tree.node_kind(node) != ndep_kind_void_expression {
		return false
	}
	operand := tree.node_child(node, 'expression')
	return tree.node_kind(operand) == ndep_kind_numeric_literal
		&& tree.node_source_text(operand) == '0'
}

// ndep_right_most_assigned ports getRightMostAssignedExpression.
fn ndep_right_most_assigned(tree AstTree, node int) int {
	mut current := node
	for _ in 0 .. max_expression_depth {
		if tree.node_kind(current) != ndep_kind_binary_expression
			|| tree.node_kind(tree.node_child(current, 'operatorToken')) != ndep_kind_equals_token
			|| tree.node_kind(tree.node_child(current, 'left')) !in ndep_left_hand_side_kinds {
			break
		}
		current = tree.node_child(current, 'right')
	}
	return current
}

// ndep_binary_initializer ports getInitializerOfBinaryExpression.
fn ndep_binary_initializer(tree AstTree, node int) int {
	mut current := node
	for _ in 0 .. max_expression_depth {
		right := tree.node_child(current, 'right')
		if tree.node_kind(right) != ndep_kind_binary_expression {
			return right
		}
		current = right
	}
	return 0
}

// ndep_is_bindable_static_name ports isBindableStaticNameExpression.
fn ndep_is_bindable_static_name(tree AstTree, node int, exclude_this bool) bool {
	return ndep_is_entity_name_expression(tree, node)
		|| ndep_is_bindable_static_access(tree, node, exclude_this)
}

// ndep_is_entity_name_expression ports isEntityNameExpression: an identifier or a chain of
// property accesses of identifiers.
fn ndep_is_entity_name_expression(tree AstTree, node int) bool {
	mut current := node
	for _ in 0 .. max_expression_depth {
		kind := tree.node_kind(current)
		if kind == syntax_kind_identifier {
			return true
		}
		if kind != syntax_kind_property_access_expression
			|| tree.node_kind(tree.node_child(current, 'name')) != syntax_kind_identifier {
			return false
		}
		current = tree.node_child(current, 'expression')
	}
	return false
}

// ndep_is_bindable_static_access ports isBindableStaticAccessExpression (and
// isBindableStaticElementAccessExpression).
fn ndep_is_bindable_static_access(tree AstTree, node int, exclude_this bool) bool {
	kind := tree.node_kind(node)
	object := tree.node_child(node, 'expression')
	this_object := !exclude_this && tree.node_kind(object) == ndep_kind_this_keyword
	if kind == syntax_kind_property_access_expression {
		return this_object || (tree.node_kind(tree.node_child(node, 'name')) == syntax_kind_identifier
			&& ndep_is_bindable_static_name(tree, object, true))
	}
	if kind == syntax_kind_element_access_expression
		&& ndep_is_string_or_numeric_literal_like(tree, tree.node_child(node, 'argumentExpression')) {
		return this_object || ndep_is_entity_name_expression(tree, object)
			|| ndep_is_bindable_static_access(tree, object, true)
	}
	return false
}

fn ndep_is_string_or_numeric_literal_like(tree AstTree, node int) bool {
	return tree.node_kind(node) in [ndep_kind_string_literal, ndep_kind_no_substitution_template,
		ndep_kind_numeric_literal]
}

// ndep_access_name ports getElementOrPropertyAccessName (the text of a string literal from its
// source, without escapes).
fn ndep_access_name(tree AstTree, node int) string {
	if tree.node_kind(node) == syntax_kind_property_access_expression {
		return tree.node_text(tree.node_child(node, 'name'))
	}
	mut argument := tree.node_child(node, 'argumentExpression')
	for tree.node_kind(argument) == ndep_kind_parenthesized_expression {
		argument = tree.node_child(argument, 'expression')
	}
	text := tree.node_source_text(argument)
	return match tree.node_kind(argument) {
		ndep_kind_string_literal, ndep_kind_no_substitution_template {
			if text.len >= 2 { text[1..text.len - 1] } else { '' }
		}
		ndep_kind_numeric_literal {
			text
		}
		else {
			''
		}
	}
}

// ndep_is_module_exports ports isModuleExportsAccessExpression: `module.exports`.
fn ndep_is_module_exports(tree AstTree, node int) bool {
	if !ndep_is_access(tree, node) {
		return false
	}
	if tree.node_kind(node) == syntax_kind_element_access_expression
		&& !ndep_is_string_or_numeric_literal_like(tree, tree.node_child(node, 'argumentExpression')) {
		return false
	}
	object := tree.node_child(node, 'expression')
	return tree.node_kind(object) == syntax_kind_identifier && tree.node_text(object) == 'module'
		&& ndep_access_name(tree, node) == 'exports'
}

// ndep_is_dynamic_name ports isDynamicName for an element access: its argument is not a literal
// (nor a signed number).
fn ndep_is_dynamic_name(tree AstTree, node int) bool {
	mut argument := tree.node_child(node, 'argumentExpression')
	for tree.node_kind(argument) == ndep_kind_parenthesized_expression {
		argument = tree.node_child(argument, 'expression')
	}
	if ndep_is_string_or_numeric_literal_like(tree, argument) {
		return false
	}
	if tree.node_kind(argument) == ndep_kind_prefix_unary_expression
		&& tree.node_kind(tree.node_child(argument, 'operand')) == ndep_kind_numeric_literal {
		text := tree.node_source_text(argument)
		return !(text.starts_with('-') || text.starts_with('+'))
	}
	return true
}

// ndep_comment_text ports displayPartsToString(getCommentDisplayParts(tag)) for a @deprecated tag:
// its texts and links (buildLinkParts).
fn (mut c Checker) ndep_comment_text(tree AstTree, tag int, mut st NdepState) !string {
	comment := tree.node_child(tag, 'comment')
	if comment == 0 {
		return ''
	}
	mut out := strings.new_builder(64)
	for part in tree.node_children(comment) {
		match tree.node_kind(part) {
			ndep_kind_jsdoc_text {
				out.write_string(tree.node_text(part))
			}
			ndep_kind_jsdoc_link, ndep_kind_jsdoc_link_code, ndep_kind_jsdoc_link_plain {
				out.write_string(c.ndep_link_text(tree, part, mut st)!)
			}
			else {}
		}
	}
	return out.str()
}

// ndep_link_text ports buildLinkParts: `{@link name text}`, where a name that resolves to a
// declaration is followed by its text without separator.
fn (mut c Checker) ndep_link_text(tree AstTree, link int, mut st NdepState) !string {
	prefix := match tree.node_kind(link) {
		ndep_kind_jsdoc_link { '{@link ' }
		ndep_kind_jsdoc_link_code { '{@linkcode ' }
		else { '{@linkplain ' }
	}
	text := tree.node_text(link)
	name_node := tree.node_child(link, 'name')
	if name_node == 0 {
		return '${prefix}${text}}'
	}
	suffix := ndep_link_name_end(text)
	name := tree.node_source_text(name_node) + text[..suffix]
	rest := ndep_skip_separator(text[suffix..])
	if c.ndep_link_resolves(tree, name_node, mut st)! {
		return '${prefix}${name}${rest}}'
	}
	separator := if suffix == 0 || (suffix < text.len && text[suffix] == `|` && !name.ends_with(' ')) {
		' '
	} else {
		''
	}
	return '${prefix}${name}${separator}${rest}}'
}

// ndep_link_name_end ports findLinkNameEnd: how much of the text continues the name (a URL up to
// `|`, `()` or `<…>`).
fn ndep_link_name_end(text string) int {
	if text.starts_with('://') {
		mut pos := 0
		for pos < text.len && text[pos] != `|` {
			pos++
		}
		return pos
	}
	if text.starts_with('()') {
		return 2
	}
	if text.len > 0 && text[0] == `<` {
		mut brackets := 0
		mut i := 0
		for i < text.len {
			if text[i] == `<` {
				brackets++
			}
			if text[i] == `>` {
				brackets--
			}
			i++
			if brackets == 0 {
				return i
			}
		}
	}
	return 0
}

// ndep_skip_separator ports skipSeparatorFromLinkText: a leading `|` and the spaces after it.
fn ndep_skip_separator(text string) string {
	if text.len == 0 || text[0] != `|` {
		return text
	}
	mut pos := 1
	for pos < text.len && text[pos] == ` ` {
		pos++
	}
	return text[pos..]
}

// ndep_link_resolves: the symbol of a link's name (getSymbolAtLocation, through aliases: getSymbolTarget)
// has a declaration. TypeScript 6 resolves no JSDocMemberName (`A#b`).
fn (mut c Checker) ndep_link_resolves(tree AstTree, name int, mut st NdepState) !bool {
	if tree.node_source_text(name).contains('#') {
		return false
	}
	handle := tree.node_handle(name)
	if handle in st.link_resolved {
		return st.link_resolved[handle]
	}
	symbols := c.client.symbols_at_locations(c.snapshot, c.project, [handle])!
	mut target := if symbols.len == 1 { symbols[0] } else { SymbolResponse{} }
	if !target.is_null() && target.flags & ndep_symbol_flag_alias != 0 {
		target = c.ndep_aliased(target, mut st)!
	}
	resolved := !target.is_null() && (target.value_declaration != '' || target.declarations.len > 0)
	st.link_resolved[handle] = resolved
	return resolved
}
