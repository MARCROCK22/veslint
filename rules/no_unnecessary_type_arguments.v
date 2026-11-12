module rules

import time
import tsgo { AstTree, SymbolResponse, TypeResponse, handle_index, handle_kind, handle_path }
import treesitter { named_children, node_end, node_field, node_kind, node_parent, nodes_of_kind, position_of }

// Port of the `no-unnecessary-type-arguments` rule of typescript-eslint 8.62.0 (it has no
// options), with its fix.

const nutarg_messages = {
	'unnecessaryTypeParameter': 'This is the default value for this type parameter, so it can be omitted.'
}

// SyntaxKind and SymbolFlags of TypeScript 7.1.0-beta the rule looks at.
const nutarg_syntax_kind_qualified_name = u32(168)
const nutarg_syntax_kind_variable_declaration = u32(262)
const nutarg_symbol_flag_alias = u32(2097152)

// TypeFlags of type-utils' ObjectFlagsType: Any | Nullable | Never | Object | Union | Intersection.
const nutarg_object_flags_type = u32(1 | 4 | 8 | 262144 | 1048576 | 134217728 | 268435456)

// NutargOwner is where a TSTypeParameterInstantiation belongs, by its TypeScript node.
enum NutargOwner {
	type_reference // TypeReference: the type parameters of its typeName
	// ExpressionWithTypeArguments: those of its expression. In TypeScript 7.1 only the `extends` of a
	// class is one; `implements` and an interface's `extends` are TypeReferences.
	heritage
	call // CallExpression, NewExpression: those of the resolved signature's declaration
}

// NutargCheck is a TSTypeParameterInstantiation the rule checks.
struct NutargCheck {
	owner        NutargOwner
	last         C.TSNode // its last type argument, without parentheses
	count        int      // how many type arguments it has
	name         Span     // the type name, the heritage expression or the `new` callee
	call         C.TSNode // the CallExpression or NewExpression
	is_new       bool
	type_context bool // isInTypeContext: TSInterfaceHeritage, TSTypeReference or TSClassImplements
	fix          Fix  // what removes the last type argument
}

fn (mut c Checker) lint_no_unnecessary_type_arguments(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut checks := []NutargCheck{}
	mut spans := []Span{}
	for node in c.nodes_of_kind(root, c'type_arguments') {
		check := c.nutarg_check_of(node) or { continue }
		spans << c.type_node_span(check.last)
		spans << check.name
		if check.owner == .call {
			spans << node_span(check.call)
		}
		checks << check
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for check in checks {
		if c.nutarg_is_default(check)! {
			findings << Finding{
				stmt:       position_of(check.last)
				message_id: 'unnecessaryTypeParameter'
				has_fix:    true
				fix:        check.fix
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checks.len
	return findings
}

// nutarg_check_of maps a type_arguments node to the TypeScript node that owns it, like
// esTreeNodeToTSNodeMap; none for the owners getTypeParametersFromNode ignores (instantiation
// expressions, type queries, import types, type assertions).
fn (c &Checker) nutarg_check_of(node C.TSNode) ?NutargCheck {
	args := named_children(node)
	if args.len == 0 {
		return none
	}
	last := unwrap_type_parens(args.last())
	// The fixer removes the whole `<…>` of a single type argument; otherwise, from the end of the
	// previous one (parentheses are not part of a type) to the end of the last one.
	fix := if args.len == 1 {
		fix_remove(node)
	} else {
		fix_remove_range(node_end(unwrap_type_parens(args[args.len - 2])), node_end(last))
	}
	parent := node_parent(node)?
	match node_kind(parent) {
		'generic_type' {
			name := node_field(parent, 'name')?
			if node_kind(name) == 'import_type' {
				// `import('./x').Y<T>` is an ImportType.
				return none
			}
			grand := node_parent(parent)?
			heritage := node_kind(grand) in ['implements_clause', 'extends_type_clause']
			// tsgo 7.1 names `A.B` with a QualifiedName in a heritage clause too.
			kind := if node_kind(name) == 'nested_type_identifier' {
				nutarg_syntax_kind_qualified_name
			} else {
				syntax_kind_identifier
			}
			return NutargCheck{
				owner:        if heritage {
					NutargOwner.heritage
				} else {
					NutargOwner.type_reference
				}
				last:         last
				count:        args.len
				name:         Span{
					key:   node_key(name)
					first: name
					end:   node_end(name)
					kind:  kind
				}
				type_context: true
				fix:          fix
			}
		}
		'extends_clause' {
			// `class C extends Base<T>`: the superTypeArguments of the class.
			value := node_field(parent, 'value')?
			return NutargCheck{
				owner: .heritage
				last:  last
				count: args.len
				name:  node_span(value)
				fix:   fix
			}
		}
		'call_expression', 'new_expression' {
			is_new := node_kind(parent) == 'new_expression'
			callee := node_field(parent, if is_new { 'constructor' } else { 'function' })?
			return NutargCheck{
				owner:  .call
				last:   last
				count:  args.len
				name:   node_span(callee)
				call:   parent
				is_new: is_new
				fix:    fix
			}
		}
		'jsx_opening_element', 'jsx_self_closing_element' {
			// `<Button<string> />`: getTypeParametersFromCall, through the signature the element
			// resolves to.
			tag := node_field(parent, 'name')?
			return NutargCheck{
				owner: .call
				last:  last
				count: args.len
				name:  node_span(tag)
				call:  parent
				fix:   fix
			}
		}
		else {
			return none
		}
	}
}

// nutarg_is_default ports checkTSArgsAndParameters: the last type argument is the default of its
// type parameter.
fn (mut c Checker) nutarg_is_default(check NutargCheck) !bool {
	parameters, tree := c.nutarg_type_parameters(check)!
	i := check.count - 1
	if i >= parameters.len {
		return false
	}
	default_node := tree.node_child(parameters[i], 'defaultType')
	if default_node == 0 {
		return false
	}
	arg_type := c.node_type(check.last) or { return false }
	types := c.client.types_at_locations(c.snapshot, c.project, [tree.node_handle(default_node)])!
	if types.len != 1 || types[0].is_null() {
		return false
	}
	default_type := types[0]
	if default_type.id == arg_type.id {
		return true
	}
	// getTypeForComparison: a type reference compares by its target and type arguments.
	default_target, default_args := c.nutarg_comparison(default_type)!
	arg_target, arg_args := c.nutarg_comparison(arg_type)!
	return default_target == arg_target && default_args.len == arg_args.len
		&& default_args.map(it.id) == arg_args.map(it.id)
}

// nutarg_comparison ports getTypeForComparison: the target id and the type arguments of a type
// reference (isTypeReferenceType), else the type itself.
fn (mut c Checker) nutarg_comparison(t TypeResponse) !(int, []TypeResponse) {
	if t.flags & nutarg_object_flags_type != 0 && t.object_flags & object_flag_reference != 0 {
		return t.target, c.type_args(t)!
	}
	return t.id, []TypeResponse{}
}

// nutarg_type_parameters ports getTypeParametersFromNode: the TypeParameter nodes of the
// declaration, and the tree of its file (empty when there are none).
fn (mut c Checker) nutarg_type_parameters(check NutargCheck) !([]int, AstTree) {
	if check.owner == .call {
		if node_key(check.call) !in c.node_handles {
			return []int{}, AstTree{}
		}
		signature := c.resolved_signature(check.call)!
		if signature.id == 0 || signature.declaration == '' {
			if check.is_new {
				return c.nutarg_from_type(check)!
			}
			return []int{}, AstTree{}
		}
		tree := c.declaration_ast(handle_path(signature.declaration))!
		return nutarg_parameter_list(tree, handle_index(signature.declaration)), tree
	}
	return c.nutarg_from_type(check)!
}

// nutarg_from_type ports getTypeParametersFromType on the name: the type parameters of the first
// declaration of its (aliased) symbol that has them.
fn (mut c Checker) nutarg_from_type(check NutargCheck) !([]int, AstTree) {
	handle := c.node_handles[check.name.key] or { return []int{}, AstTree{} }
	symbols := c.client.symbols_at_locations(c.snapshot, c.project, [handle])!
	if symbols.len != 1 || symbols[0].is_null() {
		return []int{}, AstTree{}
	}
	at_location := symbols[0]
	symbol := if at_location.flags & nutarg_symbol_flag_alias != 0 {
		c.aliased_symbol(at_location.id)!
	} else {
		at_location
	}
	// sortDeclarationsByTypeValueContext: type aliases and interfaces first (a stable sort),
	// reversed outside a type context.
	mut sorted := symbol.declarations.filter(nutarg_is_type_declaration(it))
	sorted << symbol.declarations.filter(!nutarg_is_type_declaration(it))
	if !check.type_context {
		sorted = sorted.reverse()
	}
	for declaration in sorted {
		kind := handle_kind(declaration)
		if nutarg_is_type_declaration(declaration)
			|| kind in [syntax_kind_class_declaration, syntax_kind_class_expression] {
			tree := c.declaration_ast(handle_path(declaration))!
			index := handle_index(declaration)
			if tree.node_child(index, 'typeParameters') != 0 {
				return nutarg_parameter_list(tree, index), tree
			}
			continue
		}
		if kind == nutarg_syntax_kind_variable_declaration {
			// getConstructSignatureDeclaration of the symbol at the location (not the aliased one).
			found, parameters, tree := c.nutarg_construct_parameters(at_location)!
			if found {
				return parameters, tree
			}
		}
	}
	return []int{}, AstTree{}
}

// nutarg_construct_parameters gives the typeParameters of the declaration of the first construct
// signature of the type of the symbol; found is false when they are undefined.
fn (mut c Checker) nutarg_construct_parameters(symbol SymbolResponse) !(bool, []int, AstTree) {
	t := c.symbol_type(symbol.id)!
	if t.is_null() {
		return false, []int{}, AstTree{}
	}
	signatures := c.signatures_of(t, signature_kind_construct)!
	if signatures.len == 0 || signatures[0].declaration == '' {
		return false, []int{}, AstTree{}
	}
	declaration := signatures[0].declaration
	tree := c.declaration_ast(handle_path(declaration))!
	index := handle_index(declaration)
	if tree.node_child(index, 'typeParameters') == 0 {
		return false, []int{}, AstTree{}
	}
	return true, nutarg_parameter_list(tree, index), tree
}

fn nutarg_is_type_declaration(handle string) bool {
	kind := handle_kind(handle)
	return kind == syntax_kind_type_alias_declaration || kind == syntax_kind_interface_declaration
}

// nutarg_parameter_list are the TypeParameter nodes of a declaration's typeParameters.
fn nutarg_parameter_list(tree AstTree, declaration int) []int {
	list := tree.node_child(declaration, 'typeParameters')
	if list == 0 {
		return []int{}
	}
	return tree.node_children(list)
}
