module treesitter

// What the patched grammar reads as TypeScript does (internals.md, "Grammar"), by the shape of the
// tree: the kind of each node with its named children, comments apart, in parentheses.

fn shape(n C.TSNode) string {
	parts := named_children(n).map(shape(it))
	return if parts.len == 0 { node_kind(n) } else { '${node_kind(n)}(${parts.join(',')})' }
}

// shapes_of parses `src` (as TSX if `tsx`) and gives the shape of every node of `kind`; a tree
// with syntax errors gives `ERROR` instead.
fn shapes_of(src string, kind string, tsx bool) []string {
	p := if tsx { new_tsx_parser() or { panic(err) } } else { new_parser() or { panic(err) } }
	defer {
		p.close()
	}
	tree := p.parse(src) or { panic(err) }
	defer {
		tree_delete(tree)
	}
	if tree_has_error(tree) {
		return ['ERROR']
	}
	return nodes_of_kind(root_node(tree), &char(kind.str)).map(shape(it))
}

fn shapes(src string, kind string) []string {
	return shapes_of(src, kind, false)
}

// statements_of gives the kinds of the statements of `src`.
fn statements_of(src string) string {
	return shapes(src, 'program')[0]
}

const type_args = 'type_arguments(type_identifier)'

// A union that starts with `|` is one union with that `|`, as TypeScript's UnionType: it was a
// union of one member nested in another.
fn test_union_with_a_leading_bar() {
	assert shapes('const a = x as\n  | A\n  | B;', 'union_type') == [
		'union_type(type_identifier,type_identifier)',
	]
	assert shapes('type T =\n  | A\n  | B\n  | C;', 'type_alias_declaration') == [
		'type_alias_declaration(type_identifier,union_type(union_type(type_identifier,type_identifier),type_identifier))',
	]
	assert shapes('type T = | A;', 'union_type') == ['union_type(type_identifier)']
	assert shapes('type T = & A & B;', 'intersection_type') == [
		'intersection_type(type_identifier,type_identifier)',
	]
	assert shapes('type T = | A & B | C;', 'union_type') == [
		'union_type(intersection_type(type_identifier,type_identifier),type_identifier)',
	]
	// It still loses to two comparisons.
	assert shapes('const r = a < (b) || c > (d);', 'call_expression') == []
	assert shapes('const r = a < b && c > (d);', 'call_expression') == []
}

// Type arguments without a call belong to the member expression before them, not to the unary
// or `await` expression around it.
fn test_instantiation_after_a_unary_operator() {
	inst := 'instantiation_expression(identifier,${type_args})'
	for operator in ['!', '-', '+', '~', 'typeof ', 'void ', 'delete '] {
		assert shapes('const a = ${operator}f<T>;', 'unary_expression') == [
			'unary_expression(${inst})',
		], operator
	}
	assert shapes('async function w() { return await f<T>; }', 'await_expression') == [
		'await_expression(${inst})',
	]
	assert shapes('const a = b + f<T>;', 'binary_expression') == [
		'binary_expression(identifier,${inst})',
	]
	assert shapes('const a = !b.c<T>;', 'unary_expression') == [
		'unary_expression(instantiation_expression(member_expression(identifier,property_identifier),${type_args}))',
	]
	// With a call, they are the type arguments of the call.
	assert shapes('const a = !f<T>(x);', 'unary_expression') == [
		'unary_expression(call_expression(identifier,${type_args},arguments(identifier)))',
	]
	// The empty token the scanner gives after the type arguments is not a node.
	p := new_parser() or { panic(err) }
	defer {
		p.close()
	}
	tree := p.parse('const a = !f<T>;') or { panic(err) }
	defer {
		tree_delete(tree)
	}
	instantiation := nodes_of_kind(root_node(tree), c'instantiation_expression')[0]
	assert children(instantiation).map(node_kind(it)) == ['identifier', 'type_arguments']
	assert token_ends(root_node(tree)).ends == [5, 7, 9, 11, 12, 13, 14, 15, 16]
}

// Whether `<…>` are type arguments depends on what follows them, as in TypeScript's
// canFollowTypeArgumentsInExpression.
fn test_type_arguments_or_comparisons() {
	inst := 'instantiation_expression(identifier,${type_args})'
	// Type arguments: before what cannot start an expression, before a binary operator and
	// before a line break.
	for after in [';', ' ?? g;', ' as G;', ' instanceof G;', ' == g;', ' * 2;', '\nfoo()',
		'\nconst b = 1'] {
		assert shapes('const a = f<T>${after}', 'instantiation_expression') == [inst], after
	}
	assert statements_of('const a = f<T>\nfoo()') == 'program(lexical_declaration(variable_declarator(identifier,${inst})),expression_statement(call_expression(identifier,arguments)))'
	// Comparisons: before what starts an expression on the same line, and always before `+`,
	// `-`, `<` and `>`.
	for after in [' c;', ' -c;', ' +c;', ' !c;', ' [c];', ' 1;', '\n-1', '\n+c'] {
		assert shapes('const a = f < T >${after}', 'instantiation_expression') == [], after
		assert shapes('const a = f < T >${after}', 'binary_expression').len == 2, after
	}
	assert shapes('foo(a < b, c > -1);', 'arguments') == [
		'arguments(binary_expression(identifier,identifier),binary_expression(identifier,unary_expression(number)))',
	]
	// A call wins over the comparisons its type arguments could be read as.
	assert shapes('f<A<B> | null>(null);', 'binary_expression') == []
	assert shapes('f<() => { a: { b: number } }>(x);', 'binary_expression') == []
	assert shapes('class X extends make<A<B> & C<D>, E<F>, G<H>>(x) {}', 'binary_expression') == []
	// The type arguments of an `extends` clause and of a `new` are theirs.
	assert shapes('class X extends B<T> implements I<U> {}', 'extends_clause') == [
		'extends_clause(identifier,${type_args})',
	]
	assert shapes('class X extends B<T>\n{}', 'extends_clause') == [
		'extends_clause(identifier,${type_args})',
	]
	assert shapes('const a = new X<T>;', 'new_expression') == ['new_expression(identifier,${type_args})']
	assert shapes('const a = new X<T>();', 'new_expression') == [
		'new_expression(identifier,${type_args},arguments)',
	]
}

// `typeof import('./x').y` is a type query of an import type, and an import type has its node
// also when it takes type arguments.
fn test_import_types() {
	call := 'call_expression(import,arguments(string(string_fragment)))'
	member := 'member_expression(${call},property_identifier)'
	assert shapes("type A = typeof import('./x');", 'type_query') == ['type_query(import_type(${call}))']
	assert shapes("type A = typeof import('./x').y;", 'type_query') == [
		'type_query(import_type(${member}))',
	]
	assert shapes("type A = typeof import('./x').y<T>;", 'type_query') == [
		'type_query(instantiation_expression(import_type(${member}),${type_args}))',
	]
	assert shapes("function f(a: (typeof import('./x').y)[]) {}", 'array_type') == [
		'array_type(parenthesized_type(type_query(import_type(${member}))))',
	]
	assert shapes("type A = import('./x').Y<T>;", 'generic_type') == [
		'generic_type(import_type(${member}),${type_args})',
	]
	assert shapes('type A = typeof a.b;', 'type_query') == [
		'type_query(member_expression(identifier,property_identifier))',
	]
}

// A target of a destructuring assignment may be a reference in parentheses or with a type
// assertion: the pattern has it as the expression node it is elsewhere.
fn test_destructuring_targets() {
	paren := 'parenthesized_expression(identifier)'
	as_t := 'as_expression(identifier,type_identifier)'
	assert shapes('[x as T, (y), <T>z, w satisfies T, v!] = a;', 'array_pattern') == [
		'array_pattern(${as_t},${paren},type_assertion(${type_args},identifier),satisfies_expression(identifier,type_identifier),non_null_expression(identifier))',
	]
	assert shapes('[(x as T)] = [1];', 'assignment_expression') == [
		'assignment_expression(array_pattern(parenthesized_expression(${as_t})),array(number))',
	]
	assert shapes('({ k: (x), j: y as T } = o);', 'object_pattern') == [
		'object_pattern(pair_pattern(property_identifier,${paren}),pair_pattern(property_identifier,${as_t}))',
	]
	assert shapes('[(x) = 1, ...(y as T), ...z as T] = a;', 'array_pattern') == [
		'array_pattern(assignment_pattern(${paren},number),rest_pattern(parenthesized_expression(${as_t})),rest_pattern(${as_t}))',
	]
	assert shapes('for ([(x as T), { y = (x as T) }] of xs) {}', 'for_in_statement') == [
		'for_in_statement(array_pattern(parenthesized_expression(${as_t}),object_pattern(object_assignment_pattern(shorthand_property_identifier_pattern,parenthesized_expression(${as_t})))),identifier,statement_block)',
	]
	assert shapes('for (x as T of xs) {}', 'for_in_statement') == [
		'for_in_statement(${as_t},identifier,statement_block)',
	]
	assert shapes('[(a.b), (c)[0] as T] = d;', 'array_pattern') == [
		'array_pattern(parenthesized_expression(member_expression(identifier,property_identifier)),as_expression(subscript_expression(parenthesized_expression(identifier),number),type_identifier))',
	]
	// What is not a reference is not a target, nor is a default value after a type assertion.
	for src in ['[(a + b)] = c;', '[f() as T] = c;', '[x as T = 1] = a;', '[([x])] = a;'] {
		assert shapes(src, 'array_pattern') in [['ERROR'], []], src
	}
	// The same elements in an array or an object that is not a target are expressions.
	assert shapes('const a = [(x), y as T];', 'array') == ['array(${paren},${as_t})']
	assert shapes('const a = [(x), y as T];', 'array_pattern') == []
	assert shapes('const o = { k: (x), j: y as T };', 'object') == [
		'object(pair(property_identifier,${paren}),pair(property_identifier,${as_t}))',
	]
}

// A comment with a line break counts as a line break for the automatic semicolon.
fn test_comment_with_a_line_break_ends_a_statement() {
	assert shapes('function f() { return /* a\n b */ 1; }', 'statement_block') == [
		'statement_block(return_statement,expression_statement(number))',
	]
	assert shapes('function f() { return /* a */ 1; }', 'statement_block') == [
		'statement_block(return_statement(number))',
	]
	assert shapes('function* f() { yield /* a\n */ 1; }', 'statement_block') == [
		'statement_block(expression_statement(yield_expression),expression_statement(number))',
	]
	assert statements_of('a /*\n*/ ++b') == 'program(expression_statement(identifier),expression_statement(update_expression(identifier)))'
	assert statements_of('a = b /*\n*/ c = d') == 'program(expression_statement(assignment_expression(identifier,identifier)),expression_statement(assignment_expression(identifier,identifier)))'
	// Where a line break does not end the statement, the comment does not either.
	assert statements_of('a = b /*\n*/ + c') == 'program(expression_statement(assignment_expression(identifier,binary_expression(identifier,identifier))))'
	assert statements_of('a = b /*\n*/ (c)') == 'program(expression_statement(assignment_expression(identifier,call_expression(identifier,arguments(identifier)))))'
	// A comment right before the `?` of a conditional is still a node, also on the next line.
	assert shapes('x = a /* c */? b : c', 'comment').len == 1
	assert shapes('x = a\n/* c */ ? b : c', 'comment').len == 1
	assert shapes('x = a\n/* c */ ? b : c', 'ternary_expression').len == 1
	assert shapes('x = a /* c\nd */? b : c', 'comment').len == 1
	assert shapes('x = a /* c\nd */? b : c', 'ternary_expression').len == 1
}

// A statement ends at any line terminator of ECMAScript: a line feed, a carriage return (alone
// or before a line feed), U+2028 and U+2029.
fn test_every_line_terminator_ends_a_statement() {
	call := 'expression_statement(call_expression(identifier,arguments))'
	for terminator in ['\n', '\r\n', '\r', ' ', ' '] {
		name := terminator.bytes().hex()
		assert statements_of('a()${terminator}b()${terminator}') == 'program(${call},${call})', name
		assert statements_of('a() // c${terminator}b()') == 'program(${call},${call})', name
		assert shapes('function f() { return${terminator}1 }', 'statement_block') == [
			'statement_block(return_statement,expression_statement(number))',
		], name
		assert statements_of('a${terminator}++b') == 'program(expression_statement(identifier),expression_statement(update_expression(identifier)))', name
		// The statement goes on where it does after a line feed.
		assert statements_of('a = b${terminator}(c)') == 'program(expression_statement(assignment_expression(identifier,call_expression(identifier,arguments(identifier)))))', name
		assert shapes('interface I { a: string${terminator}b: number }', 'interface_body') == [
			'interface_body(property_signature(property_identifier,type_annotation(predefined_type)),property_signature(property_identifier,type_annotation(predefined_type)))',
		], name
		assert statements_of('#!/usr/bin/env node${terminator}a()') == 'program(hash_bang_line,${call})', name
		assert shapes('let a = b${terminator}in${terminator}c', 'binary_expression') == [
			'binary_expression(identifier,identifier)',
		], name
		// White space with a line terminator between two JSX elements is not text.
		assert shapes_of('const e = <a>${terminator}  <b/>${terminator}</a>', 'jsx_text',
			true) == [], name
	}
	// A name that starts with `in` or `instanceof` is not those operators.
	for word in ['in_range', 'in2', 'in\$x', 'instanceof_', 'index', 'instanceofx'] {
		assert statements_of('let a = 1\n${word}(a)') == 'program(lexical_declaration(variable_declarator(identifier,number)),expression_statement(call_expression(identifier,arguments(identifier))))', word
	}
	assert shapes('let a = b\nin c', 'binary_expression') == ['binary_expression(identifier,identifier)']
	assert shapes('let a = b\ninstanceof c', 'binary_expression') == [
		'binary_expression(identifier,identifier)',
	]
	// White space the C locale does not know (here a no-break space) is white space.
	assert statements_of('a()\u00a0\nb()') == 'program(${call},${call})'
	assert shapes('let a = b\n\u00a0+ c', 'binary_expression') == ['binary_expression(identifier,identifier)']
	assert shapes('let a = b\nin\u00a0c', 'binary_expression') == ['binary_expression(identifier,identifier)']
}
