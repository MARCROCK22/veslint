module svelte_compiler

// The analysis walk (2-analyze/index.js `visitors`): the universal visitor (svelte-ignore
// comments, the scope of a node) around each node's visitor, and the visitors of JavaScript
// nodes (2-analyze/visitors/*.js). Template visitors are in visit_template.v.

fn (mut z Analyzer) walk_all() ! {
	for k, ast in [z.module_ast, z.instance_ast, z.c.fragment] {
		scope := [z.module_scope, z.instance_scope, z.template_scope][k]
		ast_type := ['module', 'instance', 'template'][k]
		z.props_boxes << false
		z.slot_sets << map[string]bool{}
		z.state_field_maps << map[string]StateField{}
		st := State{
			scope:           scope
			ast_type:        ast_type
			fragment:        if k == 2 { ast } else { -1 }
			props_box:       z.props_boxes.len - 1
			component_slots: z.slot_sets.len - 1
			state_fields:    z.state_field_maps.len - 1
			function_depth:  z.s.scopes[scope].function_depth
		}
		z.path = []
		z.visit(ast, st)!
	}
}

// visit is zimmerframe's visit with the universal visitor `_`.
fn (mut z Analyzer) visit(node int, st State) ! {
	if node < 0 {
		return
	}
	parent := if z.path.len > 0 { z.path.last() } else { -1 }
	typ := z.t.typ(node)
	mut ignores := []string{}
	if z.t.typ(parent) == 'Fragment' && typ != 'Comment' && typ != 'Text' {
		nodes := z.t.list(parent, .nodes)
		idx := nodes.index(node)
		for i := idx - 1; i >= 0; i-- {
			prev := nodes[i]
			if z.t.typ(prev) == 'Comment' {
				ignores << z.extract_svelte_ignore(z.t.nodes[prev].start + 4, z.t.text(prev,
					.data), z.runes)
			} else if z.t.typ(prev) != 'Text' {
				break
			}
		}
	} else {
		for cm in z.t.nodes[node].leading {
			c := z.t.comments[cm]
			ignores << z.extract_svelte_ignore(if c.start == no_pos { no_pos } else { c.start + 2 },
				c.value, z.runes)
		}
	}
	if ignores.len > 0 {
		z.push_ignore(ignores)
	}
	z.ignore_map[node] = if z.ignore_stack.len > 0 { z.ignore_stack.last() } else { []string{} }
	mut s := st
	if scope := z.s.of[node] {
		if scope != st.scope {
			s = z.copy_state(st)
			s.scope = scope
		}
	}
	z.visit_node(node, s)!
	if ignores.len > 0 {
		z.pop_ignore()
	}
}

// next visits the children of `node` (context.next).
fn (mut z Analyzer) next(node int, st State) ! {
	z.path << node
	for ch in z.t.children(node) {
		z.visit(ch, st)!
	}
	z.path.pop()
}

// child visits `child` from the visitor of `node` (context.visit).
fn (mut z Analyzer) child(node int, child int, st State) ! {
	if child < 0 {
		return
	}
	z.path << node
	z.visit(child, st)!
	z.path.pop()
}

fn (z &Analyzer) path_at(i int) int {
	k := z.path.len + i
	return if k >= 0 && k < z.path.len { z.path[k] } else { -1 }
}

fn (mut z Analyzer) visit_node(node int, st State) ! {
	match z.t.typ(node) {
		'ArrowFunctionExpression', 'FunctionExpression' { z.visit_function(node, st)! }
		'FunctionDeclaration' { z.v_function_declaration(node, st)! }
		'AssignmentExpression' { z.v_assignment(node, st)! }
		'UpdateExpression' { z.v_update(node, st)! }
		'AwaitExpression' { z.v_await(node, st)! }
		'CallExpression' { z.v_call(node, st)! }
		'ClassBody' { z.v_class_body(node, st)! }
		'ClassDeclaration' { z.v_class_declaration(node, st)! }
		'ExportDefaultDeclaration' { z.v_export_default(node, st)! }
		'ExportNamedDeclaration' { z.v_export_named(node, st)! }
		'ExportSpecifier' { z.v_export_specifier(node, st)! }
		'ExpressionStatement' { z.v_expression_statement(node, st)! }
		'Identifier' { z.v_identifier(node, st)! }
		'ImportDeclaration' { z.v_import(node, st)! }
		'LabeledStatement' { z.v_labeled(node, st)! }
		'Literal' { z.v_literal(node) }
		'MemberExpression' { z.v_member(node, st)! }
		'NewExpression' { z.v_new(node, st)! }
		'PropertyDefinition' { z.v_property_definition(node, st)! }
		'TemplateElement' { z.v_template_element(node) }
		'VariableDeclarator' { z.v_variable_declarator(node, st)! }
		// template
		'AnimateDirective', 'AttachTag', 'TransitionDirective', 'UseDirective' {
			z.v_directive(node,
				st)!
		}
		'Attribute' { z.v_attribute(node, st)! }
		'AwaitBlock' { z.v_await_block(node, st)! }
		'BindDirective' { z.v_bind(node, st)! }
		'ClassDirective', 'SpreadAttribute' { z.v_expression_holder(node, st)! }
		'Component' { z.v_component(node, st)! }
		'ConstTag' { z.v_const_tag(node, st)! }
		'DeclarationTag' { z.v_declaration_tag(node, st)! }
		'DebugTag' { z.v_debug_tag(node, st)! }
		'EachBlock' { z.v_each(node, st)! }
		'ExpressionTag' { z.v_expression_tag(node, st)! }
		'Fragment' { z.v_fragment(node, st)! }
		'HtmlTag' { z.v_html_tag(node, st)! }
		'IfBlock' { z.v_if(node, st)! }
		'KeyBlock' { z.v_key(node, st)! }
		'LetDirective' { z.v_let(node)! }
		'OnDirective' { z.v_on(node, st)! }
		'RegularElement' { z.v_regular_element(node, st)! }
		'RenderTag' { z.v_render(node, st)! }
		'SlotElement' { z.v_slot(node, st)! }
		'SnippetBlock' { z.v_snippet(node, st)! }
		'StyleDirective' { z.v_style_directive(node, st)! }
		'SvelteBody' { z.v_svelte_meta(node, st, 'svelte:body')! }
		'SvelteComponent' { z.v_svelte_component(node, st)! }
		'SvelteDocument' { z.v_svelte_meta(node, st, 'svelte:document')! }
		'SvelteElement' { z.v_svelte_element(node, st)! }
		'SvelteFragment' { z.v_svelte_fragment(node, st)! }
		'SvelteHead' { z.v_svelte_head(node, st)! }
		'SvelteSelf' { z.v_svelte_self(node, st)! }
		'SvelteWindow' { z.v_svelte_meta(node, st, 'svelte:window')! }
		'SvelteBoundary' { z.v_svelte_boundary(node, st)! }
		'Text' { z.v_text(node, st)! }
		'TitleElement' { z.v_title(node, st)! }
		else { z.next(node, st)! }
	}
}

// ---------------------------------------------------------------------------------------------
// shared/function.js

fn (mut z Analyzer) visit_function(node int, st State) ! {
	mut s := z.copy_state(st)
	s.function_depth = st.function_depth + 1
	s.expression = false
	z.next(node, s)!
}

fn (mut z Analyzer) v_function_declaration(node int, st State) ! {
	id := z.t.get(node, .id)
	if z.runes && id >= 0 {
		z.validate_identifier_name(z.s.get(st.scope, z.t.name(id)), -1)!
	}
	z.visit_function(node, st)!
}

// ---------------------------------------------------------------------------------------------
// shared/utils.js

// validate_identifier_name: `$` and `$`-prefixed declarations are invalid (function_depth -1:
// not given).
fn (mut z Analyzer) validate_identifier_name(binding int, function_depth int) ! {
	if binding < 0 {
		return
	}
	b := z.s.bindings[binding]
	if b.declaration_kind in ['synthetic', 'param', 'rest_param'] {
		return
	}
	if function_depth > 1 {
		return
	}
	name := z.t.name(b.node)
	if name == '$' {
		return z.error_at(b.node, e_dollar_binding_invalid())
	}
	if name.starts_with('$') && !(z.t.typ(b.initial) == 'ImportDeclaration'
		&& z.t.text(b.initial, .import_kind) == 'type') {
		return z.error_at(b.node, e_dollar_prefix_invalid())
	}
}

fn (mut z Analyzer) validate_assignment(node int, argument int, st State) ! {
	z.validate_no_const_assignment(node, argument, st.scope, z.t.typ(node) == 'BindDirective')!
	t := z.t
	if t.typ(argument) == 'Identifier' {
		binding := z.s.get(st.scope, t.name(argument))
		if z.runes {
			if z.props_id >= 0 && binding >= 0 && z.s.bindings[binding].node == z.props_id {
				return z.error_at(node, e_constant_assignment('\$props.id()'))
			}
			if binding >= 0 && z.s.bindings[binding].kind == 'each' {
				return z.error_at(node, e_each_item_invalid_assignment())
			}
		}
		if binding >= 0 && z.s.bindings[binding].kind == 'snippet' {
			return z.error_at(node, e_snippet_parameter_assignment())
		}
	}
	if t.typ(argument) == 'MemberExpression' && t.typ(t.get(argument, .object)) == 'ThisExpression' {
		prop := t.get(argument, .property)
		name := if t.flag(argument, .computed) && t.typ(prop) != 'Literal' {
			none
		} else {
			t.get_name(prop)
		}
		if n := name {
			if field := z.state_field_maps[st.state_fields][n] {
				if t.typ(field.node) == 'AssignmentExpression' && node != field.node {
					mut i := z.path.len
					for i > 0 {
						i--
						parent := z.path[i]
						if t.typ(parent) in ['FunctionDeclaration', 'FunctionExpression',
							'ArrowFunctionExpression'] {
							grandparent := if i - 1 >= 0 { z.path[i - 1] } else { -1 }
							if t.typ(grandparent) == 'MethodDefinition'
								&& t.text(grandparent, .kind) == 'constructor'
								&& t.nodes[node].start < t.nodes[field.node].start {
								return z.error_at(node, e_state_field_invalid_assignment())
							}
							break
						}
					}
				}
			}
		}
	}
}

fn (mut z Analyzer) validate_no_const_assignment(node int, argument int, scope int, is_binding bool) ! {
	t := z.t
	match t.typ(argument) {
		'ArrayPattern' {
			for el in t.list(argument, .elements) {
				if el >= 0 {
					z.validate_no_const_assignment(node, el, scope, is_binding)!
				}
			}
		}
		'ObjectPattern' {
			for p in t.list(argument, .properties) {
				if t.typ(p) == 'Property' {
					z.validate_no_const_assignment(node, t.get(p, .value), scope, is_binding)!
				}
			}
		}
		'Identifier' {
			binding := z.s.get(scope, t.name(argument))
			if binding >= 0 {
				b := z.s.bindings[binding]
				if b.declaration_kind == 'import' || (b.declaration_kind == 'const' && b.kind != 'each') {
					thing := if b.declaration_kind == 'import' { 'import' } else { 'constant' }
					if is_binding {
						return z.error_at(node, e_constant_binding(thing))
					}
					return z.error_at(node, e_constant_assignment(thing))
				}
			}
		}
		else {}
	}
}

// validate_opening_tag: a block opens with `{` and the expected character.
fn (mut z Analyzer) validate_opening_tag(node int, expected string) ! {
	start := z.t.nodes[node].start
	src := z.c.src
	if start + 1 >= src.len || src[start + 1..start + 2] != expected {
		return z.error_range(start, start + 5, e_block_unexpected_character(expected))
	}
}

fn (mut z Analyzer) validate_block_not_empty(node int) {
	if node < 0 {
		return
	}
	nodes := z.t.list(node, .nodes)
	if nodes.len == 1 && z.t.typ(nodes[0]) == 'Text' && z.t.text(nodes[0], .raw).trim_space() == '' {
		z.warn(nodes[0], w_block_empty())
	}
}

fn (mut z Analyzer) ensure_no_module_import_conflict(node int, st State) ! {
	id := z.t.get(node, .id)
	for i in z.t.extract_identifiers(id) {
		if st.ast_type == 'instance' && st.scope == z.instance_scope {
			b := z.s.get(z.module_scope, z.t.name(i))
			if b >= 0 && z.s.bindings[b].declaration_kind == 'import' {
				return z.error_at(id, e_declaration_duplicate_module_import())
			}
		}
	}
}

fn (mut z Analyzer) validate_export(node int, scope int, name string) ! {
	binding := z.s.get(scope, name)
	if binding < 0 {
		return
	}
	b := z.s.bindings[binding]
	if b.kind == 'derived' {
		return z.error_at(node, e_derived_invalid_export())
	}
	if (b.kind == 'state' || b.kind == 'raw_state') && b.reassigned {
		return z.error_at(node, e_state_invalid_export())
	}
}

// ---------------------------------------------------------------------------------------------
// scope.js get_rune / get_global_keypath

fn (z &Analyzer) get_rune(node int, scope int) string {
	if node < 0 || z.t.typ(node) != 'CallExpression' {
		return ''
	}
	keypath := z.get_global_keypath(z.t.get(node, .callee), scope)
	if keypath == '' || !is_rune(keypath) {
		return ''
	}
	return keypath
}

fn (z &Analyzer) get_global_keypath(node int, scope int) string {
	t := z.t
	mut n := node
	mut joined := ''
	for t.typ(n) == 'MemberExpression' {
		if t.flag(n, .computed) {
			return ''
		}
		prop := t.get(n, .property)
		if t.typ(prop) != 'Identifier' {
			return ''
		}
		joined = '.' + t.name(prop) + joined
		n = t.get(n, .object)
	}
	if t.typ(n) == 'CallExpression' && t.typ(t.get(n, .callee)) == 'Identifier' {
		joined = '()' + joined
		n = t.get(n, .callee)
	}
	if t.typ(n) != 'Identifier' {
		return ''
	}
	if z.s.get(scope, t.name(n)) >= 0 {
		return ''
	}
	return t.name(n) + joined
}

// ---------------------------------------------------------------------------------------------
// JavaScript visitors.

fn (mut z Analyzer) reactive_assign(st State, binding int) {
	if binding < 0 || st.reactive_statement < 0 {
		return
	}
	if binding !in z.reactive_statements[st.reactive_statement].assignments {
		z.reactive_statements[st.reactive_statement].assignments << binding
	}
}

fn (mut z Analyzer) v_assignment(node int, st State) ! {
	left := z.t.get(node, .left)
	z.validate_assignment(node, left, st)!
	if st.reactive_statement >= 0 {
		id := if z.t.typ(left) == 'MemberExpression' { z.t.object(left) } else { left }
		if id >= 0 {
			for i in z.t.extract_identifiers(left) {
				z.reactive_assign(st, z.s.get(st.scope, z.t.name(i)))
			}
		}
	}
	z.next(node, st)!
}

fn (mut z Analyzer) v_update(node int, st State) ! {
	arg := z.t.get(node, .argument)
	z.validate_assignment(node, arg, st)!
	if st.reactive_statement >= 0 {
		id := if z.t.typ(arg) == 'MemberExpression' { z.t.object(arg) } else { arg }
		if z.t.typ(id) == 'Identifier' {
			z.reactive_assign(st, z.s.get(st.scope, z.t.name(id)))
		}
	}
	z.next(node, st)!
}

fn (mut z Analyzer) v_await(node int, st State) ! {
	tla := st.ast_type == 'instance' && st.function_depth == 1
	mut suspend := tla
	if st.expression {
		suspend = true
	}
	if suspend {
		// experimental.async is off.
		return z.error_at(node, e_experimental_async())
	}
	z.next(node, st)!
}

fn (mut z Analyzer) v_call(node int, st State) ! {
	t := z.t
	parent := z.path_at(-1)
	rname := z.get_rune(node, st.scope)
	args := t.list(node, .arguments)
	if rname != '' && rname != '\$inspect' {
		for arg in args {
			if t.typ(arg) == 'SpreadElement' {
				return z.error_at(node, e_rune_invalid_spread(rname))
			}
		}
	}
	match rname {
		'\$bindable' {
			if args.len > 1 {
				return z.error_at(node, e_rune_invalid_arguments_length('\$bindable', 'zero or one arguments'))
			}
			p4 := z.path_at(-4)
			if t.typ(parent) != 'AssignmentPattern' || t.typ(z.path_at(-3)) != 'ObjectPattern'
				|| t.typ(p4) != 'VariableDeclarator'
				|| z.get_rune(t.get(p4, .init), st.scope) != '\$props' {
				return z.error_at(node, e_bindable_invalid_location())
			}
		}
		'\$host' {
			if args.len > 0 {
				return z.error_at(node, e_rune_invalid_arguments('\$host'))
			} else if st.ast_type == 'module' || !z.custom_element {
				return z.error_at(node, e_host_invalid_placement())
			}
		}
		'\$props' {
			if z.props_boxes[st.props_box] {
				return z.error_at(node, e_props_duplicate(rname))
			}
			z.props_boxes[st.props_box] = true
			if t.typ(parent) != 'VariableDeclarator' || st.ast_type != 'instance'
				|| st.scope != z.instance_scope {
				return z.error_at(node, e_props_invalid_placement())
			}
			if args.len > 0 {
				return z.error_at(node, e_rune_invalid_arguments(rname))
			}
		}
		'\$props.id' {
			grand_parent := z.path_at(-2)
			if z.props_id >= 0 {
				return z.error_at(node, e_props_duplicate(rname))
			}
			if t.typ(parent) != 'VariableDeclarator' || t.typ(t.get(parent, .id)) != 'Identifier'
				|| st.ast_type != 'instance' || st.scope != z.instance_scope
				|| t.typ(grand_parent) != 'VariableDeclaration' {
				return z.error_at(node, e_props_id_invalid_placement())
			}
			if args.len > 0 {
				return z.error_at(node, e_rune_invalid_arguments(rname))
			}
			z.props_id = t.get(parent, .id)
		}
		'\$state', '\$state.raw', '\$derived', '\$derived.by' {
			valid := (t.typ(parent) == 'VariableDeclarator'
				&& t.typ(z.path_at(-3)) != 'ConstTag')
				|| (t.typ(parent) == 'PropertyDefinition' && !t.flag(parent, .static_)
					&& !t.flag(parent, .computed)) || z.is_class_property_assignment_at_constructor_root(parent)
			if !valid {
				return z.error_at(node, e_state_invalid_placement(rname))
			}
			if (rname == '\$derived' || rname == '\$derived.by') && args.len != 1 {
				return z.error_at(node, e_rune_invalid_arguments_length(rname, 'exactly one argument'))
			} else if args.len > 1 {
				return z.error_at(node, e_rune_invalid_arguments_length(rname, 'zero or one arguments'))
			}
		}
		'\$effect', '\$effect.pre' {
			if t.typ(parent) != 'ExpressionStatement' {
				return z.error_at(node, e_effect_invalid_placement())
			}
			if args.len != 1 {
				return z.error_at(node, e_rune_invalid_arguments_length(rname, 'exactly one argument'))
			}
		}
		'\$effect.tracking' {
			if args.len != 0 {
				return z.error_at(node, e_rune_invalid_arguments(rname))
			}
		}
		'\$effect.root', '\$inspect().with', '\$state.eager', '\$state.snapshot' {
			if args.len != 1 {
				return z.error_at(node, e_rune_invalid_arguments_length(rname, 'exactly one argument'))
			}
		}
		'\$inspect' {
			if args.len < 1 {
				return z.error_at(node, e_rune_invalid_arguments_length(rname, 'one or more arguments'))
			}
		}
		'\$inspect.trace' {
			if args.len > 1 {
				return z.error_at(node, e_rune_invalid_arguments_length(rname, 'zero or one arguments'))
			}
			grand_parent := z.path_at(-2)
			f := z.path_at(-3)
			if t.typ(parent) != 'ExpressionStatement' || t.typ(grand_parent) != 'BlockStatement'
				|| t.typ(f) !in ['FunctionDeclaration', 'FunctionExpression', 'ArrowFunctionExpression']
				|| t.list(grand_parent, .body)[0] != parent {
				return z.error_at(node, e_inspect_trace_invalid_placement())
			}
			if t.flag(f, .generator) {
				return z.error_at(node, e_inspect_trace_generator())
			}
		}
		else {}
	}
	if rname == '\$derived' {
		mut s := z.copy_state(st)
		s.function_depth = st.function_depth + 1
		s.derived_function_depth = st.function_depth + 1
		s.expression = true
		z.next(node, s)!
	} else if rname == '\$inspect' {
		mut s := z.copy_state(st)
		s.function_depth = st.function_depth + 1
		z.next(node, s)!
	} else {
		z.next(node, st)!
	}
}

fn (z &Analyzer) is_class_property_assignment_at_constructor_root(node int) bool {
	t := z.t
	if t.typ(node) == 'AssignmentExpression' && t.text(node, .operator) == '=' {
		left := t.get(node, .left)
		if t.typ(left) == 'MemberExpression' && t.typ(t.get(left, .object)) == 'ThisExpression' {
			prop := t.get(left, .property)
			if (t.typ(prop) == 'Identifier' && !t.flag(left, .computed))
				|| t.typ(prop) == 'PrivateIdentifier' || t.typ(prop) == 'Literal' {
				p := z.path_at(-5)
				return t.typ(p) == 'MethodDefinition' && t.text(p, .kind) == 'constructor'
			}
		}
	}
	return false
}

fn (mut z Analyzer) v_class_body(node int, st State) ! {
	if !z.runes {
		z.next(node, st)!
		return
	}
	t := z.t
	mut state_fields := map[string]StateField{}
	mut fields := map[string][]string{}
	mut constructor := -1
	body := t.list(node, .body)
	for child in body {
		typ := t.typ(child)
		if typ == 'PropertyDefinition' && !t.flag(child, .computed) && !t.flag(child, .static_) {
			z.class_handle(child, t.get(child, .key), t.get(child, .value), st, mut state_fields,
				fields)!
			key := t.get_name(t.get(child, .key)) or { '' }
			if key !in fields {
				fields[key] = [if t.get(child, .value) >= 0 { 'assigned_prop' } else { 'prop' }]
				continue
			}
			return z.error_at(child, e_duplicate_class_field(key))
		}
		if typ == 'MethodDefinition' {
			kind := t.text(child, .kind)
			if kind == 'constructor' {
				constructor = child
			} else if !t.flag(child, .computed) {
				key := (if t.flag(child, .static_) { '@' } else { '' }) +
					(t.get_name(t.get(child, .key)) or { 'null' })
				if key !in fields {
					fields[key] = [kind]
					continue
				}
				mut field := fields[key]
				if kind in field || 'prop' in field || 'assigned_prop' in field {
					return z.error_at(child, e_duplicate_class_field(key))
				}
				if kind == 'get' {
					if field.len == 1 && field[0] == 'set' {
						field << 'get'
						fields[key] = field
						continue
					}
				} else if kind == 'set' {
					if field.len == 1 && field[0] == 'get' {
						field << 'set'
						fields[key] = field
						continue
					}
				} else {
					field << kind
					fields[key] = field
					continue
				}
				return z.error_at(child, e_duplicate_class_field(key))
			}
		}
	}
	if constructor >= 0 {
		fbody := t.get(t.get(constructor, .value), .body)
		for statement in t.list(fbody, .body) {
			if t.typ(statement) != 'ExpressionStatement' {
				continue
			}
			expr := t.get(statement, .expression)
			if t.typ(expr) != 'AssignmentExpression' {
				continue
			}
			left := t.get(expr, .left)
			if t.typ(left) != 'MemberExpression' || t.typ(t.get(left, .object)) != 'ThisExpression' {
				continue
			}
			if t.flag(left, .computed) && t.typ(t.get(left, .property)) != 'Literal' {
				continue
			}
			z.class_handle(expr, t.get(left, .property), t.get(expr, .right), st, mut state_fields,
				fields)!
		}
	}
	z.state_field_maps << state_fields
	mut s := z.copy_state(st)
	s.state_fields = z.state_field_maps.len - 1
	z.next(node, s)!
}

fn (mut z Analyzer) class_handle(node int, key int, value int, st State, mut state_fields map[string]StateField, fields map[string][]string) ! {
	name := z.t.get_name(key) or { return }
	rname := z.get_rune(value, st.scope)
	if rname != '' && is_state_creation_rune(rname) {
		if name in state_fields {
			return z.error_at(node, e_state_field_duplicate(name))
		}
		k := (if z.t.typ(node) == 'AssignmentExpression' || !z.t.flag(node, .static_) {
			''
		} else {
			'@'
		}) + name
		if field := fields[k] {
			if !(field.len == 1 && field[0] == 'prop') {
				return z.error_at(node, e_duplicate_class_field(k))
			}
		}
		state_fields[name] = StateField{
			node:  node
			typ:   rname
			value: value
		}
	}
}

fn (mut z Analyzer) v_class_declaration(node int, st State) ! {
	id := z.t.get(node, .id)
	if z.runes && id >= 0 {
		z.validate_identifier_name(z.s.get(st.scope, z.t.name(id)), -1)!
	}
	allowed := if st.ast_type == 'module' { 0 } else { 1 }
	if z.s.scopes[st.scope].function_depth > allowed {
		z.warn(node, w_perf_avoid_nested_class())
	}
	z.next(node, st)!
}

fn (mut z Analyzer) v_export_default(node int, st State) ! {
	// st.ast_type is always set in a component.
	return z.error_at(node, e_module_illegal_default_export())
}

fn (mut z Analyzer) v_export_named(node int, st State) ! {
	z.next(node, st)!
	t := z.t
	for spec in t.list(node, .specifiers) {
		exported := t.get(spec, .exported)
		name := if t.typ(exported) == 'Identifier' {
			t.name(exported)
		} else {
			t.text(exported, .value)
		}
		if name == 'default' {
			return z.error_at(node, e_module_illegal_default_export())
		}
	}
	decl := t.get(node, .declaration)
	if t.typ(decl) == 'VariableDeclaration' {
		if z.runes && st.ast_type == 'instance' && t.text(decl, .kind) == 'let' {
			return z.error_at(node, e_legacy_export_invalid())
		}
		for d in t.list(decl, .declarations) {
			for id in t.extract_identifiers(t.get(d, .id)) {
				b := z.s.get(st.scope, t.name(id))
				if b < 0 {
					continue
				}
				binding := z.s.bindings[b]
				if binding.kind == 'derived' {
					return z.error_at(node, e_derived_invalid_export())
				}
				if (binding.kind == 'state' || binding.kind == 'raw_state') && binding.reassigned {
					return z.error_at(node, e_state_invalid_export())
				}
			}
		}
	}
}

fn (mut z Analyzer) v_export_specifier(node int, st State) ! {
	t := z.t
	local := t.get(node, .local)
	local_name := if t.typ(local) == 'Identifier' { t.name(local) } else { t.text(local, .value) }
	if st.ast_type == 'instance' {
		if z.runes {
			b := z.s.get(st.scope, local_name)
			if b >= 0 {
				z.s.bindings[b].reassigned = true
			}
		}
	} else {
		z.validate_export(node, st.scope, local_name)!
	}
}

fn (mut z Analyzer) v_expression_statement(node int, st State) ! {
	t := z.t
	expr := t.get(node, .expression)
	if t.typ(expr) == 'NewExpression' && t.typ(t.get(expr, .callee)) == 'Identifier' {
		args := t.list(expr, .arguments)
		if args.len == 1 && t.typ(args[0]) == 'ObjectExpression' {
			mut has_target := false
			for p in t.list(args[0], .properties) {
				key := t.get(p, .key)
				if t.typ(p) == 'Property' && t.typ(key) == 'Identifier' && t.name(key) == 'target' {
					has_target = true
					break
				}
			}
			if has_target {
				b := z.s.get(st.scope, t.name(t.get(expr, .callee)))
				if b >= 0 && z.s.bindings[b].kind == 'normal'
					&& z.s.bindings[b].declaration_kind == 'import' {
					decl := z.s.bindings[b].initial
					if z.lit_value_str(t.get(decl, .source)).ends_with('.svelte') {
						for spec in t.list(decl, .specifiers) {
							if t.name(t.get(spec, .local)) == t.name(z.s.bindings[b].node)
								&& t.typ(spec) == 'ImportDefaultSpecifier' {
								z.warn(expr, w_legacy_component_creation())
								break
							}
						}
					}
				}
			}
		}
	}
	z.next(node, st)!
}

fn (mut z Analyzer) v_identifier(node int, st State) ! {
	t := z.t
	mut i := z.path.len
	i--
	mut parent := if i >= 0 { z.path[i] } else { -1 }
	if !t.is_reference(node, parent) {
		return
	}
	name := t.name(node)
	if name == 'arguments' {
		mut in_fn := false
		for p in z.path {
			if t.typ(p) in ['FunctionDeclaration', 'FunctionExpression'] {
				in_fn = true
				break
			}
		}
		if !in_fn {
			return z.error_at(node, e_invalid_arguments_usage())
		}
	}
	if name == '\$\$slots' {
		z.uses_slots = true
	}
	if z.runes {
		if is_rune(name) && z.s.get(st.scope, name) < 0 {
			sb := z.s.get(st.scope, name[1..])
			if sb < 0 || z.s.bindings[sb].kind != 'store_sub' {
				mut current := node
				mut full := name
				for t.typ(parent) == 'MemberExpression' {
					if t.flag(parent, .computed) {
						return z.error_at(parent, e_rune_invalid_computed_property())
					}
					full += '.' + t.name(t.get(parent, .property))
					current = parent
					i--
					parent = if i >= 0 { z.path[i] } else { -1 }
					if !is_rune(full) {
						if full == '\$effect.active' {
							return z.error_at(parent, e_rune_renamed('\$effect.active', '\$effect.tracking'))
						}
						if full == '\$state.frozen' {
							return z.error_at(parent, e_rune_renamed('\$state.frozen', '\$state.raw'))
						}
						if full == '\$state.is' {
							return z.error_at(parent, e_rune_removed('\$state.is'))
						}
						return z.error_at(parent, e_rune_invalid_name(full))
					}
				}
				if t.typ(parent) != 'CallExpression' {
					return z.error_at(current, e_rune_missing_parentheses())
				}
			}
		}
	}
	binding := z.s.get(st.scope, name)
	if binding < 0 {
		return
	}
	b := z.s.bindings[binding]
	if z.runes && node != b.node && st.function_depth == z.s.scopes[b.scope].function_depth
		&& ((b.kind == 'state' && (b.reassigned || (t.typ(b.initial) == 'CallExpression'
			&& t.list(b.initial, .arguments).len == 1
			&& t.typ(t.list(b.initial, .arguments)[0]) != 'SpreadElement'
			&& !z.should_proxy(t.list(b.initial, .arguments)[0], st.scope))))
			|| b.kind in ['raw_state', 'derived', 'prop', 'rest_prop'])
		&& (t.typ(parent) != 'AssignmentExpression' || t.get(parent, .left) != node)
		&& t.typ(parent) != 'UpdateExpression' {
		mut typ := 'closure'
		mut k := z.path.len
		for k > 0 {
			k--
			p := z.path[k]
			if t.typ(p) in ['ArrowFunctionExpression', 'FunctionDeclaration', 'FunctionExpression'] {
				break
			}
			if t.typ(p) == 'CallExpression' && k + 1 < z.path.len
				&& z.path[k + 1] in t.list(p, .arguments) {
				r := z.get_rune(p, st.scope)
				if r == '\$state' || r == '\$state.raw' {
					typ = 'derived'
					break
				}
			}
		}
		z.warn(node, w_state_referenced_locally(name, typ))
	}
	if st.reactive_statement >= 0 && b.scope == z.module_scope && b.reassigned {
		z.warn(node, w_reactive_declaration_module_script_dependency())
	}
}

fn (z &Analyzer) should_proxy(node int, scope int) bool {
	t := z.t
	if node < 0 {
		return false
	}
	typ := t.typ(node)
	if typ in ['Literal', 'TemplateLiteral', 'ArrowFunctionExpression', 'FunctionExpression',
		'UnaryExpression', 'BinaryExpression'] || (typ == 'Identifier' && t.name(node) == 'undefined') {
		return false
	}
	if typ == 'Identifier' && scope >= 0 {
		binding := z.s.get(scope, t.name(node))
		if binding >= 0 {
			b := z.s.bindings[binding]
			if !b.reassigned && b.initial >= 0 && t.typ(b.initial) !in [
				'FunctionDeclaration',
				'ClassDeclaration',
				'ImportDeclaration',
				'EachBlock',
				'SnippetBlock',
			] {
				return z.should_proxy(b.initial, -1)
			}
		}
	}
	return true
}

fn (mut z Analyzer) v_import(node int, st State) ! {
	if !z.runes {
		return
	}
	t := z.t
	source := z.lit_value_str(t.get(node, .source))
	if source.starts_with('svelte/internal') {
		return z.error_at(node, e_import_svelte_internal_forbidden())
	}
	if source == 'svelte' {
		for spec in t.list(node, .specifiers) {
			if t.typ(spec) == 'ImportSpecifier' {
				imported := t.get(spec, .imported)
				if t.typ(imported) == 'Identifier'
					&& t.name(imported) in ['beforeUpdate', 'afterUpdate'] {
					return z.error_at(spec, e_runes_mode_invalid_import(t.name(imported)))
				}
			}
		}
	}
}

fn (mut z Analyzer) v_labeled(node int, st State) ! {
	t := z.t
	if t.name(t.get(node, .label)) == '$' {
		parent := z.path_at(-1)
		if st.ast_type == 'instance' && t.typ(parent) == 'Program' {
			if z.runes {
				return z.error_at(node, e_legacy_reactive_statement_invalid())
			}
			z.reactive_statements << ReactiveStatement{}
			rs := z.reactive_statements.len - 1
			mut s := z.copy_state(st)
			s.reactive_statement = rs
			s.function_depth = z.s.scopes[st.scope].function_depth + 1
			z.next(node, s)!
			// Every referenced binding becomes a dependency, unless it is on the left of `=`.
			for name, nodes in z.s.scopes[st.scope].references {
				binding := z.s.get(st.scope, name)
				if binding < 0 {
					continue
				}
				for r in nodes {
					mut left := r.node
					mut i := r.path.len - 1
					mut p := r.path[i]
					for t.typ(p) == 'MemberExpression' {
						left = p
						i--
						p = if i >= 0 { r.path[i] } else { -1 }
					}
					if t.typ(p) == 'AssignmentExpression' && t.text(p, .operator) == '='
						&& t.get(p, .left) == left {
						continue
					}
					z.reactive_statements[rs].dependencies << binding
					break
				}
			}
			z.reactive_nodes << node
			body := t.get(node, .body)
			if t.typ(body) == 'ExpressionStatement'
				&& t.typ(t.get(body, .expression)) == 'AssignmentExpression' {
				left := t.get(t.get(body, .expression), .left)
				mut ids := t.extract_identifiers(left)
				if t.typ(left) == 'MemberExpression' {
					id := t.object(left)
					if id >= 0 {
						ids = [id]
					}
				}
				for id in ids {
					b := z.s.get(st.scope, t.name(id))
					if b >= 0 && z.s.bindings[b].kind == 'legacy_reactive' {
						z.s.bindings[b].legacy_dependencies = z.reactive_statements[rs].dependencies.clone()
					}
				}
			}
			z.next(node, st)!
			return
		} else if !z.runes {
			z.warn(node, w_reactive_declaration_invalid_placement())
		}
	}
	z.next(node, st)!
}

fn has_bidi(s string) bool {
	for r in s.runes() {
		if r in [rune(0x202a), 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067, 0x2068, 0x2069] {
			return true
		}
	}
	return false
}

fn (mut z Analyzer) v_literal(node int) {
	if z.t.lit_kind(node) == .string && has_bidi(z.t.text(node, .value)) {
		z.warn(node, w_bidirectional_control_characters())
	}
}

fn (mut z Analyzer) v_template_element(node int) {
	if has_bidi(z.t.text(node, .cooked)) {
		z.warn(node, w_bidirectional_control_characters())
	}
}

fn (mut z Analyzer) v_member(node int, st State) ! {
	t := z.t
	obj := t.get(node, .object)
	prop := t.get(node, .property)
	if t.typ(obj) == 'Identifier' && t.typ(prop) == 'Identifier' {
		b := z.s.get(st.scope, t.name(obj))
		if b >= 0 && z.s.bindings[b].kind == 'rest_prop' && t.name(prop).starts_with('\$\$') {
			return z.error_at(prop, e_props_illegal_name())
		}
	}
	z.next(node, st)!
}

fn (mut z Analyzer) v_new(node int, st State) ! {
	if z.t.typ(z.t.get(node, .callee)) == 'ClassExpression'
		&& z.s.scopes[st.scope].function_depth > 0 {
		z.warn(node, w_perf_avoid_inline_class())
	}
	z.next(node, st)!
}

fn (mut z Analyzer) v_property_definition(node int, st State) ! {
	name := z.t.get_name(z.t.get(node, .key)) or { '' }
	if name != '' {
		if field := z.state_field_maps[st.state_fields][name] {
			if node != field.node && z.t.get(node, .value) >= 0
				&& z.t.nodes[node].start < z.t.nodes[field.node].start {
				return z.error_at(node, e_state_field_invalid_assignment())
			}
		}
	}
	z.next(node, st)!
}

fn (mut z Analyzer) v_variable_declarator(node int, st State) ! {
	t := z.t
	z.ensure_no_module_import_conflict(node, st)!
	id := t.get(node, .id)
	init := t.get(node, .init)
	if z.runes {
		rname := z.get_rune(init, st.scope)
		mut ids := []int{}
		mut rest := []bool{}
		t.extract_paths(id, mut ids, mut rest)
		for p in ids {
			z.validate_identifier_name(z.s.get(st.scope, t.name(p)), -1)!
		}
		if rname in ['\$state', '\$state.raw', '\$derived', '\$derived.by', '\$props'] {
			for k, p in ids {
				b := z.s.get(st.scope, t.name(p))
				z.s.bindings[b].kind = match rname {
					'\$state' { 'state' }
					'\$state.raw' { 'raw_state' }
					'\$derived', '\$derived.by' { 'derived' }
					else {
						if rest[k] { 'rest_prop' } else { 'prop' }
					}
				}
			}
		}
		if rname == '\$props' {
			if t.typ(id) != 'ObjectPattern' && t.typ(id) != 'Identifier' {
				return z.error_at(node, e_props_invalid_identifier())
			}
			if z.custom_element && !z.custom_element_props {
				if t.typ(id) == 'Identifier' {
					z.warn(id, w_custom_element_props_identifier())
				} else {
					for p in t.list(id, .properties) {
						if t.typ(p) == 'RestElement' {
							z.warn(p, w_custom_element_props_identifier())
							break
						}
					}
				}
			}
			if t.typ(id) == 'Identifier' {
				b := z.s.get(st.scope, t.name(id))
				z.s.bindings[b].initial = -1
				z.s.bindings[b].kind = 'rest_prop'
			} else {
				for property in t.list(id, .properties) {
					if t.typ(property) != 'Property' {
						continue
					}
					if t.flag(property, .computed) {
						return z.error_at(property, e_props_invalid_pattern())
					}
					key := t.get(property, .key)
					if t.typ(key) == 'Identifier' && t.name(key).starts_with('\$\$') {
						return z.error_at(property, e_props_illegal_name())
					}
					pv := t.get(property, .value)
					value := if t.typ(pv) == 'AssignmentPattern' { t.get(pv, .left) } else { pv }
					if t.typ(value) != 'Identifier' {
						return z.error_at(property, e_props_invalid_pattern())
					}
					alias := if t.typ(key) == 'Identifier' {
						t.name(key)
					} else {
						t.lit_string(key)
					}
					initial := if t.typ(pv) == 'AssignmentPattern' { t.get(pv, .right) } else { -1 }
					b := z.s.get(st.scope, t.name(value))
					z.s.bindings[b].prop_alias = alias
					z.s.bindings[b].has_prop_alias = true
					callee := t.get(initial, .callee)
					if t.typ(initial) == 'CallExpression' && t.typ(callee) == 'Identifier'
						&& t.name(callee) == '\$bindable' {
						a := t.list(initial, .arguments)
						z.s.bindings[b].initial = if a.len > 0 { a[0] } else { -1 }
						z.s.bindings[b].kind = 'bindable_prop'
					} else {
						z.s.bindings[b].initial = initial
					}
				}
			}
		}
	} else if t.typ(init) == 'CallExpression' {
		callee := t.get(init, .callee)
		if t.typ(callee) == 'Identifier' && t.name(callee) in ['\$state', '\$derived', '\$props'] {
			sb := z.s.get(st.scope, t.name(callee))
			if sb < 0 || z.s.bindings[sb].kind != 'store_sub' {
				return z.error_at(init, e_rune_invalid_usage(t.name(callee)))
			}
		}
	}
	if init >= 0 && z.get_rune(init, st.scope) == '\$props' {
		mut s := z.copy_state(st)
		s.function_depth = st.function_depth + 1
		z.child(node, id, s)!
		z.child(node, init, st)!
	} else {
		z.next(node, st)!
	}
}
