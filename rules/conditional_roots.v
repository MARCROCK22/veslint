module rules

import tsgo { TypeResponse }

// The declaration of a conditional type: the conditional type nodes that may be its root, from
// its alias or from where it comes from (type_sources.v), for isTypeReadonly (type_readonly.v).

// conditional_root_nodes are the conditional type nodes that may be the root of a conditional
// type (see type_sources.v): those its alias or its origin give, without the ones whose parts
// cannot become those of the type. None when its declaration cannot be known.
fn (mut c Checker) conditional_root_nodes(t TypeResponse, origin int, mut state SourceState) ![]string {
	mut candidates := []TypeSource{}
	if t.alias_symbol != 0 {
		// The type is the body of its alias with the type arguments of the alias.
		declaration := alias_declaration(c.alias_symbol_of(t)!)
		if declaration != '' {
			body := c.alias_body_source(declaration, c.alias_bindings(t)!, mut state)!
			if body.node != '' {
				candidates = c.alias_conditional_roots(t, declaration, body, mut state)!
			}
		}
	}
	if candidates.len == 0 {
		mut search := SourceSearch{
			goal:    .roots
			subject: t
		}
		for source in c.origin_sources(mut state, origin)! {
			if !c.search_source(source, mut search, mut state, 0)! {
				return []string{}
			}
		}
		candidates = search.found.clone()
	}
	if candidates.len == 0 {
		return []string{}
	}
	// The check and extends types come with the type; its branches are only asked for when those
	// two leave more than one node.
	mut parts := [t.check_type, t.extends_type, 0, 0]
	mut nodes := c.conditional_possible_roots(candidates, parts, mut state)!
	if nodes.len > 1 {
		parts[2] = c.client.true_type_of_conditional(c.snapshot, c.project, t.id)!.id
		parts[3] = c.client.false_type_of_conditional(c.snapshot, c.project, t.id)!.id
		nodes = c.conditional_possible_roots(candidates, parts, mut state)!
	}
	return nodes
}

// alias_conditional_roots are the conditional type nodes a conditional type with an alias may have
// as root, `body` being the body of the alias with its type arguments.
//
// A conditional type gets an alias in getConditionalType: the one of its root, which is the alias
// whose body the root node is, or the one of the type reference it was asked through (the body of
// another alias, or an import), kept while TypeScript goes from a decided condition to the
// conditional type directly in its false branch. So the root of a type with an alias is the root
// of the type that alias declares or a node down its false branches, whatever the other branches
// are (alias_declared_roots). When that cannot be told, the body is followed like any other
// source.
fn (mut c Checker) alias_conditional_roots(t TypeResponse, declaration string, body TypeSource, mut state SourceState) ![]TypeSource {
	found := c.alias_declared_roots(declaration, body, mut state, 0)!
	if found.len > 0 {
		return found
	}
	mut search := SourceSearch{
		goal:     .roots
		subject:  t
		expanded: [declaration]
	}
	if c.search_source(body, mut search, mut state, 0)! {
		return search.found.clone()
	}
	return []TypeSource{}
}

// alias_declared_roots are the root of the conditional type an alias declares and the conditional
// type nodes down its false branches; `body` is the body of the alias with its type arguments.
// None when the alias does not declare a conditional type whose root can be told:
// - the body is a conditional type node whose condition is not decided where it is declared (the
//   type of the body has the check and extends types of the node): that node;
// - the body names another alias, and the type of the body has the alias of this one (it is the
//   type the other declares, asked through this body): the roots of the other, with the type
//   arguments the body gives it. `type A<T> = B<T>`, as far as it goes.
fn (mut c Checker) alias_declared_roots(declaration string, body TypeSource, mut state SourceState, depth int) ![]TypeSource {
	mut found := []TypeSource{}
	if depth > max_type_depth {
		return found
	}
	tree := c.declaration_ast(tsgo.handle_path(body.node))!
	root := skip_type_parentheses(tree, tsgo.handle_index(body.node))
	if root == 0 {
		return found
	}
	kind := tree.node_kind(root)
	if kind != syntax_kind_conditional_type && kind != syntax_kind_type_reference {
		return found
	}
	declared := c.declared_type_node(tree.node_handle(root))!
	if declared.flags & type_flag_conditional == 0 {
		return found
	}
	if kind == syntax_kind_type_reference {
		if declared.alias_symbol == 0
			|| alias_declaration(c.alias_symbol_of(declared)!) != declaration {
			return found
		}
		named := c.type_name_symbol(tree, root)!
		if named.is_null() || named.flags & source_symbol_flag_type_alias == 0 {
			return found
		}
		named_declaration := alias_declaration(named)
		if named_declaration == '' {
			return found
		}
		mut bindings := []TypeBinding{}
		for argument in tree.node_children(tree.node_child(root, 'typeArguments')) {
			bindings << TypeBinding{
				node: tree.node_handle(argument)
				env:  body.env
			}
		}
		named_body := c.alias_body_source(named_declaration, bindings, mut state)!
		if named_body.node == '' {
			return found
		}
		return c.alias_declared_roots(named_declaration, named_body, mut state, depth + 1)!
	}
	handles := [tree.node_handle(tree.node_child(root, 'checkType')),
		tree.node_handle(tree.node_child(root, 'extendsType'))]
	c.request_type_nodes(handles)!
	check := c.declared_type_node(handles[0])!
	extends := c.declared_type_node(handles[1])!
	if check.is_null() || extends.is_null() || declared.check_type != check.id
		|| declared.extends_type != extends.id {
		return found
	}
	mut node := root
	for node != 0 && tree.node_kind(node) == syntax_kind_conditional_type
		&& found.len < max_source_depth {
		found << TypeSource{tree.node_handle(node), body.env}
		node = tree.node_child(node, 'falseType')
	}
	return found
}

fn (mut c Checker) conditional_possible_roots(candidates []TypeSource, parts []int, mut state SourceState) ![]string {
	mut nodes := []string{}
	for candidate in candidates {
		if candidate.node !in nodes && c.conditional_may_be_root(candidate, parts, mut state)! {
			nodes << candidate.node
		}
	}
	return nodes
}

// conditional_may_be_root: the check type, the extends type and the two branches of a conditional
// type node, with type arguments applied, may be those of a conditional type (`parts`, their ids;
// 0 for one that is not compared). A part no type argument changes must be the same type; a part
// that is a type parameter must be what the environment has for it, and the same wherever it is.
fn (mut c Checker) conditional_may_be_root(candidate TypeSource, parts []int, mut state SourceState) !bool {
	tree := c.declaration_ast(tsgo.handle_path(candidate.node))!
	node := tsgo.handle_index(candidate.node)
	properties := ['checkType', 'extendsType', 'trueType', 'falseType']
	handles := properties.map(tree.node_handle(tree.node_child(node, it)))
	c.request_type_nodes(handles)!
	mut bound := map[int]int{}
	for i, handle in handles {
		actual := parts[i]
		if actual == 0 || tree.node_child(node, properties[i]) == 0 {
			continue
		}
		declared := c.declared_type_node(handle)!
		if declared.is_null() {
			continue
		}
		if type_is_fixed(declared) {
			if declared.id != actual {
				return false
			}
			continue
		}
		if declared.flags & type_flag_type_parameter == 0 || declared.symbol == 0 {
			continue
		}
		if declared.symbol in bound {
			if bound[declared.symbol] != actual {
				return false
			}
			continue
		}
		env := state.envs[candidate.env]
		mut expected := TypeResponse{}
		if binding := env.bindings[declared.symbol] {
			expected = c.binding_type(binding, mut state, 0)!
		} else if env.open {
			expected = declared
		}
		if !expected.is_null() && expected.id != actual {
			// A conditional type is distributed over the members of the union its check type
			// parameter stands for: in each, the type parameter is that member.
			if i != 0 || expected.flags & type_flag_union == 0
				|| !c.members_of(expected)!.any(it.id == actual) {
				return false
			}
		}
		bound[declared.symbol] = actual
	}
	return true
}
