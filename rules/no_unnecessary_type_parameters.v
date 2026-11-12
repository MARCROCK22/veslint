module rules

import time
import tsgo { SignatureResponse, TypeResponse }
import treesitter { named_children, node_end, node_field, node_kind, node_parent, node_start, nodes_of_kinds, position_of }

// Port of the `no-unnecessary-type-parameters` rule of typescript-eslint 8.62.0 (it has no
// options), with its suggestion.
//
// The original walks the types with TypeScript's own objects. veslint takes some of their parts
// from the declarations instead:
// - the constraint and the default of a type parameter: the types of those nodes of its
//   declaration, as in the original;
// - the type parameter and the template of a mapped type: the types of those nodes of its
//   declaration. For a mapped type that is an instance of a generic one (the inferred return type
//   of a call, without an alias) the original looks at the keys of the instance (its
//   `constraintType`: TypeScript 6 has not computed its `templateType` unless it compared the
//   instance with another mapped type), which tsgo gives since TypeScript 7.1
//   (getConstraintTypeOfMappedType). Up to 7.0.2 veslint read them in the text of the type.

const nutp_messages = {
	'replaceUsagesWithConstraint': 'Replace all usages of type parameter with its constraint.'
	'sole':                        'Type parameter {{name}} is {{uses}} in the {{descriptor}} signature.'
}

// ArrowFunctionExpression, FunctionDeclaration, FunctionExpression, TSCallSignatureDeclaration,
// TSConstructorType, TSDeclareFunction, TSEmptyBodyFunctionExpression, TSFunctionType and
// TSMethodSignature (not TSConstructSignatureDeclaration).
const nutp_function_kinds = ['arrow_function', 'function_declaration', 'generator_function_declaration',
	'function_expression', 'generator_function', 'method_definition', 'call_signature',
	'constructor_type', 'function_signature', 'method_signature', 'abstract_method_signature',
	'function_type']

const nutp_class_kinds = ['class_declaration', 'class', 'abstract_class_declaration']

// TypeFlags.Index (`keyof T`), StringMapping (`Uppercase<T>`), IndexedAccess; ObjectFlags.Tuple,
// Mapped and Instantiated; the kinds of a TypeParameter and of a MappedType.
const nutp_type_flag_index = u32(2097152)
const nutp_type_flag_string_mapping = u32(8388608)
const nutp_type_flag_indexed_access = u32(33554432)
const nutp_object_flag_tuple = u32(8)
const nutp_object_flag_mapped = u32(32)
const nutp_object_flag_instantiated = u32(64)
const nutp_kind_mapped_type = u32(202)

// NutpParameter is a type parameter that is not repeated in the signature as written.
struct NutpParameter {
	node        C.TSNode
	name_node   C.TSNode
	name        string
	variable    int
	declaration string // the handle of its TypeScript declaration, once known
}

struct NutpCheck {
	node       C.TSNode
	list       C.TSNode   // its `<…>`
	all        []C.TSNode // every type parameter of the list
	descriptor string
mut:
	parameters []NutpParameter
}

// NutpWalk is the state of one collectTypeParameterUsageCounts.
struct NutpWalk {
	from_class bool
mut:
	type_usages          map[int]int
	visited_symbol_lists map[int]bool
	visited_constraints  map[string]bool
	visited_default      bool
	function_like        bool
}

fn (mut c Checker) lint_no_unnecessary_type_parameters(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	tree := c.scope_tree(root)
	mut checks := []NutpCheck{}
	mut spans := []Span{}
	mut kinds := nutp_function_kinds.clone()
	kinds << nutp_class_kinds
	for node in c.nodes_of_kinds(root, kinds, []string{}) {
		list := node_field(node, 'type_parameters') or { continue }
		all := named_children(list).filter(node_kind(it) == 'type_parameter')
		// node.body?.range[0] ?? node.returnType?.range[1]
		mut start_of_body := max_int
		if body := node_field(node, 'body') {
			start_of_body = node_start(body)
		} else if return_type := node_field(node, 'return_type') {
			start_of_body = node_end(return_type)
		}
		mut check := NutpCheck{
			node:       node
			list:       list
			all:        all
			descriptor: if node_kind(node) in nutp_class_kinds { 'class' } else { 'function' }
		}
		for parameter in all {
			name_node := node_field(parameter, 'name') or { continue }
			variable := tree.declared_variable(name_node)
			if variable < 0 {
				continue
			}
			// The quick path: a type parameter used several times in the signature as written.
			if c.nutp_repeated_in_ast(parameter, tree, variable, start_of_body) {
				continue
			}
			check.parameters << NutpParameter{
				node:      parameter
				name_node: name_node
				name:      c.identifier_name(name_node)
				variable:  variable
			}
			spans << node_span(name_node)
		}
		if check.parameters.len == 0 {
			continue
		}
		checks << check
		spans << c.nutp_spans(node)
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for check in checks {
		// The TypeScript declaration of each type parameter of the node.
		mut all_declarations := map[u64]string{}
		for parameter in check.all {
			name_node := node_field(parameter, 'name') or { continue }
			handle := c.nutp_declaration(name_node)
			if handle != '' {
				all_declarations[node_key(parameter)] = handle
			}
		}
		counts := c.nutp_count_usage(check, all_declarations)!
		for parameter in check.parameters {
			declaration := all_declarations[node_key(parameter.node)] or { continue }
			count := counts[declaration]
			if count == 0 || count > 2 {
				continue
			}
			_, suggestion := c.suggestion('replaceUsagesWithConstraint', map[string]string{},
				c.nutp_fixes(check, parameter, tree))!
			findings << Finding{
				stmt:        position_of(parameter.node)
				message_id:  'sole'
				data:        {
					'name':       parameter.name
					'descriptor': check.descriptor
					'uses':       if count == 1 { 'never used' } else { 'used only once' }
				}
				suggestions: [suggestion]
			}
		}
	}
	findings.sort_with_compare(compare_findings)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checks.len
	return findings
}

// nutp_repeated_in_ast ports isTypeParameterRepeatedInAST: the type parameter has two references
// in the signature, or one as a type argument of something that is not an array.
fn (c &Checker) nutp_repeated_in_ast(parameter C.TSNode, tree &ScopeTree, variable int, start_of_body int) bool {
	mut total := 0
	for index in tree.variables[variable].references {
		reference := tree.references[index]
		identifier := reference.identifier
		// References inside the definition of the type parameter do not count…
		if node_start(identifier) < node_end(parameter) && node_end(identifier) > node_start(parameter) {
			continue
		}
		// …nor the ones outside the signature.
		if node_start(identifier) > start_of_body {
			continue
		}
		if !reference.type_ref {
			continue
		}
		// As a type argument, the type parameter is being reused; `Array` and `ReadonlyArray` are
		// left for the types to say.
		if direct := type_parent(identifier) {
			if node_kind(direct) == 'type_arguments' {
				mut is_array := false
				if owner := node_parent(direct) {
					if node_kind(owner) == 'generic_type' {
						if name := node_field(owner, 'name') {
							is_array = node_kind(name) == 'type_identifier'
								&& c.text(name) in ['Array', 'ReadonlyArray']
						}
					}
				}
				if !is_array {
					return true
				}
			}
		}
		total++
		if total >= 2 {
			return true
		}
	}
	return false
}

// nutp_node_span is the TypeScript node of a function-like node or of a class member.
fn (c &Checker) nutp_node_span(node C.TSNode) Span {
	return match node_kind(node) {
		'function_type', 'constructor_type' { c.type_node_span(node) }
		'function_signature' { prd_declaration_span(node) }
		'call_signature', 'method_signature', 'abstract_method_signature', 'public_field_definition',
		'index_signature' {
			member_span(node)
		}
		else { function_span(node) }
	}
}

// nutp_spans are the nodes whose types the count of a node needs: the node, or the members of a
// class.
fn (c &Checker) nutp_spans(node C.TSNode) []Span {
	if node_kind(node) !in nutp_class_kinds {
		return [c.nutp_node_span(node)]
	}
	mut spans := []Span{}
	if body := node_field(node, 'body') {
		for member in named_children(body) {
			if node_kind(member) in ['method_definition', 'method_signature',
				'abstract_method_signature', 'public_field_definition', 'index_signature'] {
				spans << c.nutp_node_span(member)
			}
		}
	}
	return spans
}

// nutp_declaration is the handle of the TypeParameter declaration whose name the node is.
fn (c &Checker) nutp_declaration(name_node C.TSNode) string {
	handle := c.node_handles[node_key(name_node)] or { return '' }
	if tsgo.handle_kind(handle) == syntax_kind_type_parameter {
		return handle
	}
	parent := c.ast.tree.node_parent(tsgo.handle_index(handle))
	if parent == 0 || c.ast.tree.node_kind(parent) != syntax_kind_type_parameter {
		return ''
	}
	return c.ast.tree.node_handle(parent)
}

// nutp_type_at is the type at a node of any file (getTypeAtLocation).
fn (mut c Checker) nutp_type_at(handle string) !TypeResponse {
	types := c.client.types_at_locations(c.snapshot, c.project, [handle])!
	return if types.len == 1 { types[0] } else { TypeResponse{} }
}

// nutp_count_usage ports countTypeParameterUsage: how many times each type parameter is used in
// the types of the node (of its type parameters and its members, for a class), by declaration.
fn (mut c Checker) nutp_count_usage(check NutpCheck, declarations map[u64]string) !map[string]int {
	mut counts := map[string]int{}
	if check.descriptor != 'class' {
		c.nutp_collect(check.node, false, mut counts)!
		return counts
	}
	for parameter in check.all {
		declaration := declarations[node_key(parameter)] or { continue }
		mut walk := NutpWalk{
			from_class: true
		}
		c.nutp_visit_type(c.nutp_type_at(declaration)!, false, false, mut walk, mut counts)!
	}
	if body := node_field(check.node, 'body') {
		for member in named_children(body) {
			if node_kind(member) in ['method_definition', 'method_signature',
				'abstract_method_signature', 'public_field_definition', 'index_signature'] {
				c.nutp_collect(member, true, mut counts)!
			}
		}
	}
	return counts
}

// nutp_collect ports collectTypeParameterUsageCounts for a node: the signature of a call
// signature or of a constructor, or the type of any other node.
fn (mut c Checker) nutp_collect(node C.TSNode, from_class bool, mut counts map[string]int) ! {
	span := c.nutp_node_span(node)
	mut walk := NutpWalk{
		from_class: from_class
	}
	kind := node_kind(node)
	is_constructor := kind in ['method_definition', 'method_signature'] && c.pfa_is_constructor(node)
	if kind == 'call_signature' || is_constructor {
		walk.function_like = true
		if handle := c.node_handles[span.key] {
			signature := c.client.signature_from_declaration(c.snapshot, c.project, handle)!
			c.nutp_visit_signature(signature, mut walk, mut counts)!
		}
		return
	}
	node_type := c.node_types[span.key] or { return }
	c.nutp_visit_type(node_type, false, false, mut walk, mut counts)!
}

// nutp_visit_signature ports visitSignature.
fn (mut c Checker) nutp_visit_signature(signature SignatureResponse, mut walk NutpWalk, mut counts map[string]int) ! {
	if signature.id == 0 {
		return
	}
	if signature.this_parameter != 0 {
		this_parameter := c.client.this_parameter_of_signature(c.snapshot, c.project,
			signature.id)!
		if !this_parameter.is_null() {
			c.nutp_visit_type(c.symbol_type(this_parameter.id)!, false, false, mut walk, mut
				counts)!
		}
	}
	for parameter in c.signature_parameters(signature)! {
		c.nutp_visit_type(c.symbol_type(parameter.id)!, false, false, mut walk, mut counts)!
	}
	if signature.type_parameters.len > 0 {
		for type_parameter in c.client.type_parameters_of_signature(c.snapshot, c.project,
			signature.id)! {
			c.nutp_visit_type(type_parameter, false, false, mut walk, mut counts)!
		}
	}
	predicate := c.type_predicate(signature.id)!
	returned := if predicate.found && !predicate.typ.is_null() {
		predicate.typ
	} else {
		c.return_type(signature.id)!
	}
	c.nutp_visit_type(returned, false, true, mut walk, mut counts)!
}

// nutp_visit_type ports visitType: counts the type parameters a type uses.
fn (mut c Checker) nutp_visit_type(t TypeResponse, assume_multiple bool, is_return_type bool, mut walk NutpWalk, mut counts map[string]int) ! {
	if t.is_null() {
		return
	}
	// A type seen this many times is recursive, or already counted enough.
	walk.type_usages[t.id]++
	if walk.type_usages[t.id] > 9 {
		return
	}
	if t.flags & type_flag_type_parameter != 0 {
		if t.symbol == 0 {
			return
		}
		symbol := c.symbol_of(t)!
		if symbol.declarations.len == 0 {
			return
		}
		c.nutp_visit_type_parameter(symbol.declarations[0], assume_multiple, mut walk, mut
			counts)!
		return
	}
	// A generic type alias like `Exclude<T, null>`: its definition is not looked into, so its
	// type arguments are taken as used several times.
	if t.alias_type_arguments.len > 0 {
		for argument in c.client.alias_type_arguments_of_type(c.snapshot, c.project, t.id)! {
			c.nutp_visit_type(argument, true, false, mut walk, mut counts)!
		}
		return
	}
	if t.flags & (type_flag_union | type_flag_intersection) != 0 {
		for part in c.members_of(t)! {
			c.nutp_visit_type(part, assume_multiple, false, mut walk, mut counts)!
		}
		return
	}
	// `T[K]`
	if t.flags & nutp_type_flag_indexed_access != 0 {
		for method in ['getObjectTypeOfType', 'getIndexTypeOfType'] {
			part := c.client.part_of_type(method, c.snapshot, c.project, t.id)!
			c.nutp_visit_type(part, assume_multiple, false, mut walk, mut counts)!
		}
		return
	}
	// Tuples and generic type references like `Map<K, V>`.
	if is_type_reference(t) {
		target := c.target_of(t)!
		for argument in c.type_args(t)! {
			// In a class, everything is used several times. A readonly array or tuple uses its
			// type argument once; a mutable one, several times only when it is returned; any
			// other reference, several times.
			mut multiple := walk.from_class || assume_multiple
			if !multiple {
				multiple = if target.object_flags & nutp_object_flag_tuple != 0 {
					is_return_type && !target.readonly
				} else if !target.is_null() && c.client.is_array_type(c.snapshot, c.project,
					target.id)!
				{
					is_return_type && t.symbol != 0 && c.symbol_of(t)!.name == 'Array'
				} else {
					true
				}
			}
			c.nutp_visit_type(argument, multiple, is_return_type, mut walk, mut counts)!
		}
		return
	}
	// `a${T}b`
	if t.flags & type_flag_template_literal != 0 {
		for part in c.members_of(t)! {
			c.nutp_visit_type(part, assume_multiple, false, mut walk, mut counts)!
		}
		return
	}
	// `T extends string ? T : never`
	if t.flags & type_flag_conditional != 0 {
		for method in ['getCheckTypeOfType', 'getExtendsTypeOfType'] {
			part := c.client.part_of_type(method, c.snapshot, c.project, t.id)!
			c.nutp_visit_type(part, assume_multiple, false, mut walk, mut counts)!
		}
		return
	}
	// Inferred object types like `{ k: V }`, after the references so as not to go into every
	// property of a generic interface.
	if t.flags & type_flag_object != 0 {
		properties := c.properties(t)!
		if !walk.visited_symbol_lists[t.id] {
			walk.visited_symbol_lists[t.id] = true
			for property in properties {
				c.nutp_visit_type(c.symbol_type(property.id)!, false, false, mut walk, mut
					counts)!
			}
		}
		if t.object_flags & nutp_object_flag_mapped != 0 {
			c.nutp_visit_mapped(t, properties.len == 0, mut walk, mut counts)!
		}
		infos := c.index_infos(t.id)!
		for key_flag in [type_flag_number, type_flag_string] {
			for info in infos {
				if info.key_type.flags == key_flag {
					c.nutp_visit_type(info.value_type, true, false, mut walk, mut counts)!
					break
				}
			}
		}
		for kind in [signature_kind_call, signature_kind_construct] {
			for signature in c.signatures_of(t, kind)! {
				walk.function_like = true
				c.nutp_visit_signature(signature, mut walk, mut counts)!
			}
		}
		return
	}
	// Operator types like `keyof T`.
	if t.flags & (nutp_type_flag_index | nutp_type_flag_string_mapping) != 0 {
		c.nutp_visit_type(c.target_of(t)!, assume_multiple, false, mut walk, mut counts)!
	}
}

// nutp_visit_type_parameter is the type parameter part of visitType, for the declaration of the
// type parameter (that of its class, for a `this` type): it counts one use, and visits its
// constraint and its default once each.
fn (mut c Checker) nutp_visit_type_parameter(declaration string, assume_multiple bool, mut walk NutpWalk, mut counts map[string]int) ! {
	counts[declaration] += if assume_multiple { 2 } else { 1 }
	if tsgo.handle_kind(declaration) != syntax_kind_type_parameter {
		return
	}
	ast := c.declaration_ast(tsgo.handle_path(declaration))!
	index := tsgo.handle_index(declaration)
	constraint := ast.node_child(index, 'constraint')
	if constraint != 0 {
		handle := ast.node_handle(constraint)
		if !walk.visited_constraints[handle] {
			walk.visited_constraints[handle] = true
			c.nutp_visit_type(c.nutp_type_at(handle)!, false, false, mut walk, mut counts)!
		}
	}
	default_type := ast.node_child(index, 'defaultType')
	if default_type != 0 && !walk.visited_default {
		walk.visited_default = true
		c.nutp_visit_type(c.nutp_type_at(ast.node_handle(default_type))!, false, false, mut
			walk, mut counts)!
	}
}

// nutp_visit_mapped is the mapped type part of visitType: its type parameter and, when it has no
// properties, its template (or its constraint, without one).
fn (mut c Checker) nutp_visit_mapped(t TypeResponse, without_properties bool, mut walk NutpWalk, mut counts map[string]int) ! {
	if t.symbol == 0 {
		return
	}
	symbol := c.symbol_of(t)!
	if symbol.declarations.len == 0
		|| tsgo.handle_kind(symbol.declarations[0]) != nutp_kind_mapped_type {
		return
	}
	declaration := symbol.declarations[0]
	ast := c.declaration_ast(tsgo.handle_path(declaration))!
	index := tsgo.handle_index(declaration)
	type_parameter := ast.node_child(index, 'typeParameter')
	if type_parameter == 0 {
		return
	}
	// tsgo gives no type for the type parameter of a mapped type: its declaration is visited
	// directly. That of an instance is a copy with the same declaration.
	c.nutp_visit_type_parameter(ast.node_handle(type_parameter), false, mut walk, mut counts)!
	if !without_properties {
		return
	}
	if t.object_flags & nutp_object_flag_instantiated != 0 {
		// The keys of the instance (its constraintType), which tsgo gives since TypeScript 7.1.
		keys := c.client.part_of_type('getConstraintTypeOfMappedType', c.snapshot, c.project,
			t.id)!
		c.nutp_visit_type(keys, false, false, mut walk, mut counts)!
		return
	}
	mut template := ast.node_child(index, 'type')
	if template == 0 {
		template = ast.node_child(type_parameter, 'constraint')
	}
	if template != 0 {
		c.nutp_visit_type(c.nutp_type_at(ast.node_handle(template))!, false, false, mut
			walk, mut counts)!
	}
}

// nutp_fixes ports the fixer of the suggestion: every usage of the type parameter becomes its
// constraint (`unknown` without one, or with `any`), and the type parameter goes away.
fn (mut c Checker) nutp_fixes(check NutpCheck, parameter NutpParameter, tree &ScopeTree) []Fix {
	mut fixes := []Fix{}
	mut constraint_text := 'unknown'
	mut is_complex := false
	if constraint_node := node_field(parameter.node, 'constraint') {
		if raw := first_named(constraint_node) {
			constraint := unwrap_type_parens(raw)
			if !(node_kind(constraint) == 'predefined_type' && c.text(constraint) == 'any') {
				constraint_text = c.text(constraint)
			}
			is_complex = node_kind(constraint) in ['union_type', 'intersection_type', 'conditional_type']
		}
	}
	for index in tree.variables[parameter.variable].references {
		reference := tree.references[index]
		if !reference.type_ref {
			continue
		}
		mut in_matching_type := false
		if parent := type_parent(reference.identifier) {
			in_matching_type = node_kind(parent) in ['array_type', 'lookup_type', 'intersection_type',
				'union_type']
		}
		// A union, an intersection or a conditional type needs parentheses there.
		fixes << if is_complex && in_matching_type {
			fix_replace(reference.identifier, '(${constraint_text})')
		} else {
			fix_replace(reference.identifier, constraint_text)
		}
	}
	// The type parameter itself: the whole `<T>` if it is the only one, or with its comma.
	if check.all.len == 1 {
		fixes << fix_remove(check.list)
		return fixes
	}
	tokens := c.source_tokens(parameter.node)
	if node_key(check.all[0]) == node_key(parameter.node) {
		mut end := node_end(parameter.node)
		mut offset := node_end(parameter.node)
		for {
			token := tokens.after(offset, false) or { break }
			if c.token_is(token, ',') {
				if after := tokens.after(token.end, true) {
					end = after.start
				}
				break
			}
			offset = token.end
		}
		fixes << fix_remove_range(node_start(parameter.node), end)
	} else {
		mut start := node_start(parameter.node)
		mut offset := node_start(parameter.node)
		for {
			token := tokens.before(offset, false) or { break }
			if c.token_is(token, ',') {
				start = token.start
				break
			}
			offset = token.start
		}
		fixes << fix_remove_range(start, node_end(parameter.node))
	}
	return fixes
}
