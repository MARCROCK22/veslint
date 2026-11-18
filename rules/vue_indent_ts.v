module rules

// The TypeScript listeners of eslint-plugin-vue 10.12.1's indent-ts.ts (see vue_indent.v).

// vind_type_node_types are TYPE_NODE_TYPES of ts-utils/ts-ast.ts (isTypeNode).
const vind_type_node_types = ['TSAbstractKeyword', 'TSAnyKeyword', 'TSAsyncKeyword', 'TSArrayType',
	'TSBigIntKeyword', 'TSBooleanKeyword', 'TSConditionalType', 'TSConstructorType', 'TSDeclareKeyword',
	'TSExportKeyword', 'TSFunctionType', 'TSImportType', 'TSIndexedAccessType', 'TSInferType',
	'TSIntersectionType', 'TSIntrinsicKeyword', 'TSLiteralType', 'TSMappedType', 'TSNamedTupleMember',
	'TSNeverKeyword', 'TSNullKeyword', 'TSNumberKeyword', 'TSObjectKeyword', 'TSOptionalType',
	'TSQualifiedName', 'TSPrivateKeyword', 'TSProtectedKeyword', 'TSPublicKeyword', 'TSReadonlyKeyword',
	'TSRestType', 'TSStaticKeyword', 'TSStringKeyword', 'TSSymbolKeyword', 'TSTemplateLiteralType',
	'TSThisType', 'TSTupleType', 'TSTypeLiteral', 'TSTypeOperator', 'TSTypePredicate', 'TSTypeQuery',
	'TSTypeReference', 'TSUndefinedKeyword', 'TSUnionType', 'TSUnknownKeyword', 'TSVoidKeyword']

// visit_ts runs the listener of a TypeScript (or non-standard) node's own type.
fn (mut x VindCtx) visit_ts(n VindNode, typ string) {
	match typ {
		'TSTypeAnnotation' { x.ts_type_annotation(n) }
		'TSAsExpression', 'TSSatisfiesExpression' { x.ts_as(n) }
		'TSTypeReference', 'TSInstantiationExpression', 'TSClassImplements', 'TSInterfaceHeritage' {
			x.ts_type_arguments(n)
		}
		'TSTypeParameterInstantiation', 'TSTypeParameterDeclaration' {
			x.node_list(x.items(x.list(n, .params)), x.titem(x.ftn(n)), x.titem(x.ltn(n)), 1, true)
		}
		'TSTypeAliasDeclaration' { x.ts_type_alias(n) }
		'TSConstructorType', 'TSFunctionType' { x.ts_function_type(n, typ) }
		'TSTypeLiteral' {
			x.node_list(x.items(x.list(n, .members)), x.titem(x.ftn(n)), x.titem(x.ltn(n)), 1, true)
		}
		'TSPropertySignature' { x.ts_property_signature(n) }
		'TSIndexSignature' { x.ts_index_signature(n) }
		'TSArrayType' {
			x.sets(x.st.cursor(false, x.item(n).s, x.item(n).e, false, .none_, 0, 2).reverse(), 0, x.ftn(n))
		}
		'TSTupleType' {
			x.node_list(x.items(x.list(n, .element_types)), x.titem(x.ftn(n)), x.titem(x.ltn(n)), 1, true)
		}
		'TSQualifiedName' { x.ts_qualified_name(n) }
		'TSIndexedAccessType' { x.ts_indexed_access(n) }
		'TSUnionType', 'TSIntersectionType' { x.ts_union(n) }
		'TSMappedType' { x.ts_mapped(n) }
		'TSTypeParameter' { x.ts_type_parameter(n) }
		'TSConditionalType' { x.ts_conditional(n) }
		'TSInterfaceDeclaration' { x.ts_interface(n) }
		'TSInterfaceBody', 'TSModuleBlock' {
			x.node_list(x.items(x.list(n, .body)), x.titem(x.ftn(n)), x.titem(x.ltn(n)), 1, true)
		}
		'TSEnumDeclaration' { x.ts_enum(n) }
		'TSEnumBody' {
			x.node_list(x.items(x.list(n, .members)), x.titem(x.ftn(n)), x.titem(x.ltn(n)), 1, true)
		}
		'TSModuleDeclaration' { x.ts_module(n) }
		'TSMethodSignature' { x.ts_method_signature(n) }
		'TSCallSignatureDeclaration', 'TSConstructSignatureDeclaration' {
			x.ts_call_signature(n, typ)
		}
		'TSDeclareFunction', 'TSEmptyBodyFunctionExpression' { x.ts_declare_function(n) }
		'TSTypeOperator', 'TSTypeQuery', 'TSInferType', 'TSRestType' {
			x.set(x.ta(x.titem(x.ftn(n))), 1, x.ftn(n))
		}
		'TSTypePredicate' { x.ts_type_predicate(n) }
		'TSOptionalType', 'TSNonNullExpression', 'TSJSDocNonNullableType' {
			x.set(x.ltn(n), 1, x.ftn(n))
		}
		'TSTypeAssertion' { x.ts_type_assertion(n) }
		'TSImportType' { x.ts_import_type(n) }
		'TSParameterProperty' { x.ts_head_and(n, x.ftn(x.child(n, .parameter))) }
		'TSImportEqualsDeclaration' { x.ts_import_equals(n) }
		'TSExternalModuleReference' { x.ts_external_module_reference(n) }
		'TSExportAssignment' { x.ts_export_assignment(n) }
		'TSNamedTupleMember' { x.ts_named_tuple_member(n) }
		'TSNamespaceExportDeclaration' { x.ts_head_and(n, x.ftn(x.child(n, .id))) }
		'Decorator' { x.ts_decorator(n) }
		'AccessorProperty' { x.ts_accessor_property(n) }
		'ImportAttribute' { x.ts_import_attribute(n) }
		'TSParenthesizedType' {
			x.node_list([x.item(x.child(n, .type_annotation))], x.titem(x.ftn(n)), x.titem(x.ltn(n)), 1, true)
		}
		else {}
	}
}

// ts_member is the listener of `TSAbstractMethodDefinition, TSAbstractPropertyDefinition,
// TSAbstractAccessorProperty, TSEnumMember, ClassProperty, TSAbstractClassProperty`.
fn (mut x VindCtx) ts_member(n VindNode, typ string) {
	if typ == 'TSEnumMember' {
		x.property_like(n, x.child(n, .id), x.child(n, .initializer), x.flag(n, .computed))
	} else {
		x.property_like(n, x.child(n, .key), x.child(n, .value), x.flag(n, .computed))
	}
}

// ts_class is the `ClassDeclaration[implements], …` listener.
fn (mut x VindCtx) ts_class(n VindNode) {
	type_params := x.child(n, .type_parameters)
	if type_params.ok() {
		id := x.child(n, .id)
		x.set(x.ftn(type_params), 1, x.ftn(if id.ok() { id } else { n }))
	}
	super_args := x.child(n, .super_type_arguments)
	super_class := x.child(n, .super_class)
	if super_args.ok() && super_class.ok() {
		x.set(x.ftn(super_args), 1, x.ftn(super_class))
	}
	implements := x.list(n, .implements_)
	if implements.len == 0 {
		return
	}
	class_token := x.ftn(n)
	implements_token := x.tb(x.item(implements[0]))
	x.set(implements_token, 1, class_token)
	x.node_list(x.items(implements), x.titem(implements_token), VindItem{}, 1, true)
}

// ts_type_parens is the `*[type=/^TS/]` listener: the parentheses around a type.
fn (mut x VindCtx) ts_type_parens(n VindNode, ptype string) {
	if x.typ(n) !in vind_type_node_types || ptype == 'TSParenthesizedType' {
		return
	}
	x.on_expression(n)
}

fn (mut x VindCtx) ts_type_annotation(n VindNode) {
	it := x.item(n)
	firsts := x.st.cursor(true, it.s, it.e, false, .none_, 0, 2)
	colon := if firsts.len > 0 { firsts[0] } else { -1 }
	second := if firsts.len > 1 { firsts[1] } else { -1 }
	base := x.ftn(x.parent(n))
	x.sets([colon, second], 1, base)
	before := x.tb(x.titem(colon))
	if x.value(before) == '?' {
		x.set(before, 1, base)
	}
}

fn (mut x VindCtx) ts_as(n VindNode) {
	expr_first, expr_last := x.first_last(x.item(x.child(n, .expression)), 0)
	as_token := x.ta(x.titem(expr_last))
	x.sets([as_token, x.first_of(x.item(x.child(n, .type_annotation)))], 1, expr_first)
}

fn (mut x VindCtx) ts_type_arguments(n VindNode) {
	type_args := x.child(n, .type_arguments)
	if !type_args.ok() {
		return
	}
	x.set(x.ftn(type_args), 1, x.ftn(n))
}

fn (mut x VindCtx) ts_type_alias(n VindNode) {
	type_token := x.ftn(n)
	id := x.child(n, .id)
	id_token := x.ftn(id)
	x.set(id_token, 1, type_token)
	type_params := x.child(n, .type_parameters)
	mut eq := -1
	if type_params.ok() {
		x.set(x.ftn(type_params), 1, id_token)
		eq = x.ta(x.item(type_params))
	} else {
		eq = x.ta(x.item(id))
	}
	init := x.ta(x.titem(eq))
	x.sets([eq, init], 1, id_token)
}

// ts_params_head sets the offsets of `new` and of the type parameters of a function type or a
// call or construct signature, and gives its `(`.
fn (mut x VindCtx) ts_params_head(n VindNode, first int, with_new bool) int {
	mut current := first
	if with_new {
		current = x.ta(x.titem(current))
		x.set(current, 1, first)
	}
	type_params := x.child(n, .type_parameters)
	if type_params.ok() {
		current = x.ta(x.item(type_params))
		x.set(current, 1, first)
	}
	return current
}

fn (mut x VindCtx) ts_function_type(n VindNode, typ string) {
	first := x.ftn(n)
	left_paren := x.ts_params_head(n, first, typ == 'TSConstructorType')
	params := x.list(n, .params)
	right_paren := x.taf(x.last_or(params, x.titem(left_paren)), .close_paren)
	x.node_list(x.items(params), x.titem(left_paren), x.titem(right_paren), 1, true)
	arrow := x.ta(x.titem(right_paren))
	x.set(arrow, 1, left_paren)
}

// ts_key_last processes a computed key of a signature (`[key]`) and gives the last token of the
// key (its `]` when computed).
fn (mut x VindCtx) ts_key_last(n VindNode, first int) int {
	key := x.child(n, .key)
	_, key_last := x.first_last(x.item(key), 0)
	if x.flag(n, .computed) {
		close_bracket := x.ta(x.titem(key_last))
		x.node_list([x.item(key)], x.titem(first), x.titem(close_bracket), 1, true)
		return close_bracket
	}
	return key_last
}

// sets_through sets the tokens between `from` and `to`, and `to`, at `offset` from `base`.
fn (mut x VindCtx) sets_through(from int, to int, offset int, base int) {
	mut tokens := x.between(x.titem(from), x.titem(to))
	tokens << to
	x.sets(tokens, offset, base)
}

fn (mut x VindCtx) ts_property_signature(n VindNode) {
	first := x.ftn(n)
	key_last := x.ts_key_last(n, first)
	type_annotation := x.child(n, .type_annotation)
	if type_annotation.ok() {
		x.sets_through(key_last, x.ftn(type_annotation), 1, first)
	} else if x.flag(n, .optional) {
		x.set(x.ltn(n), 1, first)
	}
}

fn (mut x VindCtx) ts_index_signature(n VindNode) {
	left_bracket := x.ftn(n)
	params := x.list(n, .parameters)
	right_bracket := x.taf(x.last_or(params, x.titem(left_bracket)), .close_bracket)
	x.node_list(x.items(params), x.titem(left_bracket), x.titem(right_bracket), 1, true)
	type_annotation := x.child(n, .type_annotation)
	if !type_annotation.ok() {
		return
	}
	x.sets_through(right_bracket, x.ftn(type_annotation), 1, left_bracket)
}

fn (mut x VindCtx) ts_qualified_name(n VindNode) {
	object := x.ftn(n)
	dot := x.tb(x.item(x.child(n, .right)))
	property := x.ta(x.titem(dot))
	x.sets([dot, property], 1, object)
}

fn (mut x VindCtx) ts_indexed_access(n VindNode) {
	object := x.ftn(n)
	index_type := x.item(x.child(n, .index_type))
	left_bracket := x.tbf(index_type, .open_bracket)
	right_bracket := x.taf(index_type, .close_bracket)
	x.set(left_bracket, 1, object)
	x.node_list([index_type], x.titem(left_bracket), x.titem(right_bracket), 1, true)
}

// ts_beginning_of_element is isBeginningOfElement of indent-ts.ts.
fn (x &VindCtx) ts_beginning_of_element(token int, belonging VindNode) bool {
	tus := x.st.all[token].us
	mut node := belonging
	for node.ok() {
		parent := x.parent(node)
		if !parent.ok() {
			break
		}
		ptype := x.typ(parent)
		if ptype == 'TSTypeParameterInstantiation' {
			params := x.list(parent, .params)
			return params.len >= 2 && params.any(x.starts_at(x.first_of(x.item(it)), tus))
		}
		if ptype == 'TSTupleType' {
			return x.list(parent, .element_types).any(it.ok()
				&& x.starts_at(x.first_of(x.item(it)), tus))
		}
		node = parent
	}
	return false
}

fn (mut x VindCtx) ts_union(n VindNode) {
	first := x.ftn(n)
	prev := x.tb(x.titem(first))
	indent := prev < 0 || x.st.all[prev].end_line == x.st.all[first].line
		|| x.ts_beginning_of_element(first, n)
	offset := if indent { 1 } else { 0 }
	types := x.list(n, .types)
	if types.len == 0 {
		return
	}
	mut firsts := []int{}
	mut lasts := []int{}
	for i, t in types {
		// `types.map(getFirstAndLastTokens)`: the index is the border offset.
		f, l := x.first_last(x.item(t), i)
		firsts << f
		lasts << l
	}
	mut start := 0
	mut last := first
	if firsts[0] == first {
		last = lasts[0]
		start = 1
	}
	for k in start .. firsts.len {
		x.sets(x.between(x.titem(last), x.titem(firsts[k])), offset, first)
		x.set(firsts[k], offset, first)
	}
}

fn (mut x VindCtx) ts_mapped(n VindNode) {
	left_brace := x.ftn(n)
	key := x.child(n, .key)
	type_param := x.child(n, .type_parameter)
	key_or_param := if key.ok() { key } else { type_param }
	left_bracket := x.tb(x.item(key_or_param))
	name_type := x.child(n, .name_type)
	constraint := x.child(n, .constraint)
	right_bracket := x.ta(x.item(if name_type.ok() {
		name_type
	} else if constraint.ok() {
		constraint
	} else {
		type_param
	}))
	x.sets_through(left_brace, left_bracket, 1, left_brace)
	x.node_list([x.item(key_or_param), x.item(name_type)], x.titem(left_bracket), x.titem(right_bracket),
		1, true)
	if constraint.ok() {
		mut tokens := x.between(x.item(key), x.item(constraint))
		tokens << x.ftn(constraint)
		x.sets(tokens, 1, x.ftn(key))
	}
	right_brace := x.ltn(n)
	type_annotation := x.child(n, .type_annotation)
	if type_annotation.ok() {
		x.sets_through(right_bracket, x.ftn(type_annotation), 1, left_brace)
	} else {
		x.sets(x.between(x.titem(right_bracket), x.titem(right_brace)), 1, left_brace)
	}
	x.set(right_brace, 0, left_brace)
}

fn (mut x VindCtx) ts_type_parameter(n VindNode) {
	all := x.toks(x.item(n))
	if all.len == 0 {
		return
	}
	first := all[0]
	mut after := all[1..].clone()
	for child in [x.child(n, .constraint), x.child(n, .default_)] {
		if !child.ok() {
			continue
		}
		remove := x.toks(x.item(child))
		for k := 1; k < remove.len; k++ {
			i := after.index(remove[k])
			if i != -1 {
				after.delete(i)
			}
		}
	}
	if after.len == 0 {
		return
	}
	second := after[0]
	after.delete(0)
	x.set(second, 1, first)
	if x.value(second) == 'extends' {
		mut prev := -1
		mut k := 0
		for k < after.len {
			if x.value(after[k]) == '=' {
				break
			}
			x.set(after[k], 1, second)
			prev = after[k]
			k++
		}
		for k < after.len {
			x.set(after[k], 1, if prev >= 0 { prev } else { second })
			k++
		}
	} else {
		x.sets(after, 1, first)
	}
}

fn (mut x VindCtx) ts_conditional(n VindNode) {
	check := x.ftn(n)
	extends := x.ta(x.item(x.child(n, .check_type)))
	extends_type := x.child(n, .extends_type)
	x.set(extends, 1, check)
	x.set(x.ftn(extends_type), 1, extends)
	question := x.taf(x.item(extends_type), .not_close_paren)
	consequent := x.ta(x.titem(question))
	colon := x.taf(x.item(x.child(n, .true_type)), .not_close_paren)
	alternate := x.ta(x.titem(colon))
	mut base := n
	mut parent := x.parent(base)
	for parent.ok() && x.typ(parent) == 'TSConditionalType' && x.child(parent, .false_type) == base {
		base = parent
		parent = x.parent(base)
	}
	base_token := x.ftn(base)
	x.sets([question, colon], 1, base_token)
	x.set(consequent, 1, question)
	x.set(alternate, 1, colon)
}

fn (mut x VindCtx) ts_interface(n VindNode) {
	interface_token := x.ftn(n)
	id := x.ftn(x.child(n, .id))
	x.set(id, 1, interface_token)
	type_params := x.child(n, .type_parameters)
	if type_params.ok() {
		x.set(x.ftn(type_params), 1, id)
	}
	extends := x.list(n, .extends_)
	if extends.len > 0 {
		extends_token := x.tb(x.item(extends[0]))
		x.set(extends_token, 1, interface_token)
		x.node_list(x.items(extends), x.titem(extends_token), VindItem{}, 1, true)
	}
	x.set(x.ftn(x.child(n, .body)), 0, interface_token)
}

// ts_named_head sets the offsets of the tokens before the name of an enum or a module (`const`,
// `declare`…) and of the name, and gives the name's last token.
fn (mut x VindCtx) ts_named_head(n VindNode, first int) int {
	id_first, id_last := x.first_last(x.item(x.child(n, .id)), 0)
	x.sets(x.between(x.titem(first), x.titem(id_first)), 0, first)
	x.set(id_first, 1, first)
	return id_last
}

fn (mut x VindCtx) ts_enum(n VindNode) {
	first := x.ftn(n)
	id_last := x.ts_named_head(n, first)
	left_brace := x.ta(x.titem(id_last))
	right_brace := x.ltn(n)
	x.set(left_brace, 0, first)
	if x.child(n, .body).ok() {
		return
	}
	x.node_list(x.items(x.list(n, .members)), x.titem(left_brace), x.titem(right_brace), 1,
		true)
}

fn (mut x VindCtx) ts_module(n VindNode) {
	first := x.ftn(n)
	x.ts_named_head(n, first)
	body := x.child(n, .body)
	if !body.ok() {
		return
	}
	body_first := x.ftn(body)
	x.set(body_first, if x.is_punct(body_first, '{') { 0 } else { 1 }, first)
}

fn (mut x VindCtx) ts_method_signature(n VindNode) {
	first := x.ftn(n)
	key_last := x.ts_key_last(n, first)
	left_paren := x.taf(x.titem(key_last), .open_paren)
	x.sets_through(key_last, left_paren, 1, first)
	params := x.list(n, .params)
	right_paren := x.taf(x.last_or(params, x.titem(left_paren)), .close_paren)
	x.node_list(x.items(params), x.titem(left_paren), x.titem(right_paren), 1, true)
	return_type := x.child(n, .return_type)
	if !return_type.ok() {
		return
	}
	x.sets_through(key_last, x.ftn(return_type), 1, first)
}

fn (mut x VindCtx) ts_call_signature(n VindNode, typ string) {
	first := x.ftn(n)
	left_paren := x.ts_params_head(n, first, typ == 'TSConstructSignatureDeclaration')
	params := x.list(n, .params)
	right_paren := x.taf(x.last_or(params, x.titem(left_paren)), .close_paren)
	x.node_list(x.items(params), x.titem(left_paren), x.titem(right_paren), 1, true)
	return_type := x.child(n, .return_type)
	if !return_type.ok() {
		return
	}
	x.sets_through(right_paren, x.ftn(return_type), 1, first)
}

fn (mut x VindCtx) ts_declare_function(n VindNode) {
	first := x.ftn(n)
	mut left_paren := -1
	mut body_base := -1
	if first >= 0 && x.st.all[first].typ == 'Punctuator' {
		left_paren = first
		body_base = x.ftn(x.parent(n))
	} else {
		left_paren = x.function_head(n, first)
		body_base = first
	}
	type_params := x.child(n, .type_parameters)
	if !x.is_punct(left_paren, '(') && type_params.ok() {
		left_paren = x.ta(x.item(type_params))
	}
	params := x.list(n, .params)
	right_paren := x.taf(x.last_or(params, x.titem(left_paren)), .close_paren)
	x.set(left_paren, 1, body_base)
	x.node_list(x.items(params), x.titem(left_paren), x.titem(right_paren), 1, true)
}

fn (mut x VindCtx) ts_type_predicate(n VindNode) {
	first := x.ftn(n)
	op := x.taf(x.item(x.child(n, .parameter_name)), .not_close_paren)
	type_annotation := x.child(n, .type_annotation)
	right := if type_annotation.ok() { x.first_of(x.item(type_annotation)) } else { -1 }
	x.sets([op, right], 1, x.first_of(x.titem(first)))
}

fn (mut x VindCtx) ts_type_assertion(n VindNode) {
	first := x.ftn(n)
	expression := x.first_of(x.item(x.child(n, .expression)))
	x.node_list([x.item(x.child(n, .type_annotation))], x.titem(first), x.titem(x.tb(x.titem(expression))),
		1, true)
	x.set(expression, 1, first)
}

fn (mut x VindCtx) ts_import_type(n VindNode) {
	first := x.ftn(n)
	left_paren := x.taf(x.titem(first), .open_paren)
	x.set(left_paren, 1, first)
	mut arg := x.child(n, .source)
	if !arg.ok() {
		arg = x.child(n, .argument)
	}
	if !arg.ok() {
		arg = x.child(n, .parameter)
	}
	mut args := [x.item(arg)]
	options := x.child(n, .options)
	if options.ok() {
		args << x.item(options)
	}
	right_paren := x.taf(args.last(), .close_paren)
	x.node_list(args, x.titem(left_paren), x.titem(right_paren), 1, true)
	qualifier := x.child(n, .qualifier)
	if qualifier.ok() {
		dot := x.tb(x.item(qualifier))
		property := x.ta(x.titem(dot))
		x.sets([dot, property], 1, first)
	}
	type_args := x.child(n, .type_arguments)
	if type_args.ok() {
		x.set(x.ftn(type_args), 1, first)
	}
}

// ts_head_and sets the tokens from the node's first token to `to` (included) at 1 from the
// first (TSParameterProperty, TSNamespaceExportDeclaration).
fn (mut x VindCtx) ts_head_and(n VindNode, to int) {
	first := x.ftn(n)
	x.sets_through(first, to, 1, first)
}

fn (mut x VindCtx) ts_import_equals(n VindNode) {
	import_token := x.ftn(n)
	id_first, id_last := x.first_last(x.item(x.child(n, .id)), 0)
	x.set(id_first, 1, import_token)
	op := x.ta(x.titem(id_last))
	x.sets([op, x.ftn(x.child(n, .module_reference))], 1, id_last)
}

fn (mut x VindCtx) ts_external_module_reference(n VindNode) {
	require := x.ftn(n)
	left_paren := x.taf(x.titem(require), .open_paren)
	right_paren := x.ltn(n)
	x.set(left_paren, 1, require)
	x.node_list([x.item(x.child(n, .expression))], x.titem(left_paren), x.titem(right_paren),
		1, true)
}

fn (mut x VindCtx) ts_export_assignment(n VindNode) {
	export := x.ftn(n)
	expr_first := x.first_of(x.item(x.child(n, .expression)))
	op := x.tb(x.titem(expr_first))
	x.sets([op, expr_first], 1, export)
}

fn (mut x VindCtx) ts_named_tuple_member(n VindNode) {
	label := x.ftn(n)
	element := x.first_of(x.item(x.child(n, .element_type)))
	x.sets_through(label, element, 1, label)
}

fn (mut x VindCtx) ts_decorator(n VindNode) {
	it := x.item(n)
	firsts := x.st.cursor(true, it.s, it.e, false, .none_, 0, 2)
	at := if firsts.len > 0 { firsts[0] } else { -1 }
	second := if firsts.len > 1 { firsts[1] } else { -1 }
	x.set(second, 0, at)
	parent := x.parent(n)
	decorators := x.list(parent, .decorators)
	if decorators.len == 0 {
		return
	}
	if decorators[0] == n {
		if x.item(parent).s == it.s {
			x.set(x.ta(x.item(decorators.last())), 0, at)
		} else {
			grand := x.parent(parent)
			target := if grand.ok()
				&& x.typ(grand) in ['ExportDefaultDeclaration', 'ExportNamedDeclaration']
				&& it.s < x.item(grand).s {
				grand
			} else {
				parent
			}
			x.copy_offset(at, x.ftn(target))
		}
	} else {
		x.set(at, 0, x.ftn(decorators[0]))
	}
}

fn (mut x VindCtx) ts_accessor_property(n VindNode) {
	x.property_like(n, x.child(n, .key), x.child(n, .value), x.flag(n, .computed))
	x.semicolons(n)
}

fn (mut x VindCtx) ts_import_attribute(n VindNode) {
	first := x.ftn(n)
	key_first, key_last := x.first_last(x.item(x.child(n, .key)), 0)
	x.sets(x.between(x.titem(first), x.titem(key_first)), 0, first)
	x.set(key_first, 0, first)
	x.sets_through(key_last, x.ftn(x.child(n, .value)), 1, key_last)
}
