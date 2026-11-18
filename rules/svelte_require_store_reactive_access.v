module rules

import estree

// Port of the `svelte/require-store-reactive-access` rule of eslint-plugin-svelte 3.24.1: a store
// used as a value where its value is meant (in the template, `{store}`, attributes of HTML
// elements, directives, blocks; in expressions, conditions, operators, templates, calls…) is
// reported, with a fix that adds the `$` prefix to an identifier of a store declared in the
// instance script. A store is an expression whose type has a `subscribe` taking two functions
// (with types), else a variable initialized with `writable`/`readable`/`derived` of
// `svelte/store`. Only components are checked.

const svrsra_messages = {
	'usingRawStoreInText': 'Use the \$ prefix or the get function to access reactive values instead of accessing the raw store.'
}

struct SvrsraContext {
	e        SvscEs
	b        SvscBridge
	typed    bool
	abs_path string
	root     C.TSNode
mut:
	store_variables map[int]bool // ES checker: lint variable -> declared with `const`
	creator_calls   map[int]bool // view nodes of the calls of writable/readable/derived
	module_scripts  [][]int
	findings        []Finding
}

// svrsra_is_store is the rule's isStore.
fn (mut c Checker) svrsra_is_store(mut ctx SvrsraContext, node int, consistent bool, mut stats Stats) bool {
	if ctx.typed {
		ts := c.svsc_lint_ts(&ctx.b, node, ctx.abs_path, mut stats) or { return false }
		return c.svsc_is_store_ts(ts, consistent)
	}
	t := ctx.e.t
	if t.typ(node) != .identifier {
		return false
	}
	name := t.string_of(node, .name) or { return false }
	if name.starts_with('\$') {
		return false
	}
	lint := ctx.b.lint_of(node) or { return false }
	ts := ctx.b.lint.ts_node(lint) or { return false }
	tree := c.scope_tree(ctx.root)
	v := tree.find_variable(tree.get_scope(ts), name, ctx.b.lint.nodes[lint].start)
	if v < 0 {
		return false
	}
	is_const := ctx.store_variables[v] or { return false }
	return if consistent { is_const } else { true }
}

// svrsra_verify is verifyExpression.
fn (mut c Checker) svrsra_verify(mut ctx SvrsraContext, node int, disable_fix bool, consistent bool, allow_callable bool, mut stats Stats) {
	if node < 0 {
		return
	}
	if !c.svrsra_is_store(mut ctx, node, consistent, mut stats) {
		return
	}
	if allow_callable && ctx.typed {
		if ts := c.svsc_lint_ts(&ctx.b, node, ctx.abs_path, mut stats) {
			if c.svsc_is_callable_ts(ts) {
				return
			}
		}
	}
	t := ctx.e.t
	mut finding := c.svsc_report(&ctx.e, node, 'usingRawStoreInText', {})
	if t.typ(node) == .identifier && !disable_fix && c.svrsra_can_use_prefix(ctx, node) {
		finding = Finding{
			...finding
			has_fix: true
			fix:     fix_insert_at(t.nodes[node].start, '\$')
		}
	}
	ctx.findings << finding
}

// svrsra_can_use_prefix is canUseStorePrefix: a variable of the instance script's top level, used
// outside the module script.
fn (c &Checker) svrsra_can_use_prefix(ctx SvrsraContext, node int) bool {
	v := c.sv_find_variable(node)
	info := &c.svelte.doc.scope
	if v < 0 || info.scopes[info.variables[v].scope].typ != 'module' {
		return false
	}
	n := ctx.e.t.nodes[node]
	return !svntlbg_contains(ctx.module_scripts, n.start, n.end)
}

// svrsra_unwrap_type is unwrapTypeExpression.
fn svrsra_unwrap_type(t &estree.EsTree, node int) int {
	mut expr := node
	for t.typ(expr) in [.ts_as_expression, .ts_satisfies_expression, .ts_non_null_expression,
		.ts_type_assertion] {
		expr = t.node(expr, .expression) or { break }
	}
	return expr
}

// svrsra_unwrap_nullish is unwrapNullishFallback.
fn svrsra_unwrap_nullish(t &estree.EsTree, node int) int {
	mut expr := svrsra_unwrap_type(t, node)
	for t.typ(expr) == .logical_expression && (t.string_of(expr, .operator) or { '' }) == '??' {
		expr = svrsra_unwrap_type(t, t.node(expr, .right) or { break })
	}
	return expr
}

// svrsra_initializer is getInitializer: a `const x = init` or a parameter default.
fn (c &Checker) svrsra_initializer(node int) int {
	v := c.sv_find_variable(node)
	if v < 0 {
		return -1
	}
	info := &c.svelte.doc.scope
	es := &c.svelte.doc.es
	defs := info.variables[v].defs
	if defs.len != 1 {
		return -1
	}
	kind, declarator := c.svsc_def(defs[0])
	if kind == .variable {
		id := es.node(declarator, .id) or { return -1 }
		return if es.typ(id) == .identifier { es.node(declarator, .init) or { -1 } } else { -1 }
	}
	if kind == .other {
		parent := es.nodes[defs[0].name].parent
		if parent >= 0 && es.typ(parent) == .assignment_pattern
			&& (es.node(parent, .left) or { -1 }) == defs[0].name {
			return es.node(parent, .right) or { -1 }
		}
	}
	return -1
}

// svrsra_is_maybe_missing_call is isMaybeMissingStoreCall.
fn svrsra_is_maybe_missing_call(t &estree.EsTree, node int, ctx SvrsraContext) bool {
	mut expr := svrsra_unwrap_nullish(t, node)
	if t.typ(expr) == .await_expression {
		expr = svrsra_unwrap_type(t, t.node(expr, .argument) or { return false })
	}
	if t.typ(expr) == .chain_expression {
		expr = t.node(expr, .expression) or { return false }
	}
	return t.typ(expr) == .call_expression && !ctx.creator_calls[expr]
}

// svrsra_is_existence_check is isStoreExistenceCheck.
fn (mut c Checker) svrsra_is_existence_check(mut ctx SvrsraContext, left int, right int, mut stats Stats) bool {
	if !ctx.typed {
		return false
	}
	t := ctx.e.t
	expr := svrsra_unwrap_nullish(t, left)
	mut maybe_missing := false
	if t.typ(expr) == .identifier {
		init := c.svrsra_initializer(expr)
		maybe_missing = init >= 0 && svrsra_is_maybe_missing_call(t, init, ctx)
	} else {
		maybe_missing = svrsra_is_maybe_missing_call(t, expr, ctx)
	}
	return maybe_missing && c.svrsra_is_store(mut ctx, left, false, mut stats)
		&& c.svrsra_is_store(mut ctx, right, false, mut stats)
}

// svrsra_can_accept_element is canAcceptStoreAttributeElement: a component's props (not an
// HTML element nor `<svelte:element>`).
fn (c &Checker) svrsra_can_accept_element(element int) bool {
	if element < 0 {
		return false
	}
	n := c.svelte.doc.nodes[element]
	if n.typ != .element {
		return false
	}
	return !(n.kind == 'html' || (n.kind == 'special' && c.sv_element_name(element) == 'svelte:element'))
}

// svrsra_element_of is `attr.parent.parent` (the element of an attribute's start tag).
fn (c &Checker) svrsra_element_of(attr int) int {
	start_tag := c.svelte.doc.nodes[attr].parent
	return if start_tag >= 0 { c.svelte.doc.nodes[start_tag].parent } else { -1 }
}

fn (mut c Checker) lint_svelte_require_store_reactive_access(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	e := c.svsc_es(root, abs_path) or { return [] }
	b := c.svsc_bridge(root, &e, abs_path) or { return [] }
	doc := c.svelte.doc
	t := e.t
	mut ctx := SvrsraContext{
		e:        e
		b:        b
		typed:    c.scope_setup.type_information
		abs_path: abs_path
		root:     root
	}
	for ch in doc.nodes[0].children {
		if doc.nodes[ch].typ == .script_element && c.sv_is_module_script(ch) {
			ctx.module_scripts << [doc.nodes[ch].start, doc.nodes[ch].end]
		}
	}
	tree := c.scope_tree(root)
	for call in c.svsc_store_calls(root, abs_path, ['writable', 'readable', 'derived']) {
		if view := b.view_of(call.node) {
			ctx.creator_calls[view] = true
		}
		if ctx.typed {
			continue
		}
		declarator := b.lint.nodes[call.node].parent
		if declarator < 0 || b.lint.typ(declarator) != .variable_declarator {
			continue
		}
		id := b.lint.node(declarator, .id) or { continue }
		declaration := b.lint.nodes[declarator].parent
		if b.lint.typ(id) != .identifier || declaration < 0
			|| b.lint.typ(declaration) != .variable_declaration {
			continue
		}
		v := tree.declared_variable(b.lint.ts_node(id) or { continue })
		if v >= 0 {
			ctx.store_variables[v] = (b.lint.string_of(declaration, .kind) or { '' }) == 'const'
		}
	}
	for step in c.sv_steps() {
		if step.leave {
			continue
		}
		if !step.node.es {
			i := step.node.idx
			n := doc.nodes[i]
			match n.typ {
				.mustache_tag {
					parent := n.parent
					mut accepts := false
					mut event := false
					if parent >= 0 && doc.nodes[parent].typ == .attribute {
						attr := doc.nodes[parent]
						name := c.sv_attribute_name(parent)
						accepts = attr.values.len <= 1 && !name.starts_with('--')
							&& c.svrsra_can_accept_element(c.svrsra_element_of(parent))
						event = attr.values.len == 1 && name.starts_with('on')
					}
					if !accepts && n.expression.es {
						c.svrsra_verify(mut ctx, n.expression.idx, false, false, event, mut
							stats)
					}
				}
				.shorthand_attribute {
					if !c.svrsra_can_accept_element(c.svrsra_element_of(i)) && n.value_ref.es {
						c.svrsra_verify(mut ctx, n.value_ref.idx, true, false, c.sv_ref_name(n.key).starts_with('on'), mut
							stats)
					}
				}
				.spread_attribute {
					if n.expression.es {
						c.svrsra_verify(mut ctx, n.expression.idx, false, false, false, mut
							stats)
					}
				}
				.directive {
					key := if !n.key.es && n.key.idx >= 0 {
						doc.nodes[n.key.idx].key
					} else {
						n.key
					}
					match n.kind {
						'Action', 'Animation', 'Transition' {
							if key.es && key.idx >= 0 && t.typ(key.idx) == .identifier {
								c.svrsra_verify(mut ctx, key.idx, false, false, true, mut
									stats)
							}
						}
						'Binding' {
							if c.sv_directive_key_name(i) != 'this'
								&& c.svrsra_can_accept_element(c.svrsra_element_of(i)) {
								continue
							}
							if !n.expression.es || n.expression.idx < 0 {
								continue
							}
							if n.function_bindings {
								for expr in t.list(n.expression.idx, .expressions) or { []int{} } {
									c.svrsra_verify(mut ctx, expr, n.shorthand, false, false, mut
										stats)
								}
							} else {
								c.svrsra_verify(mut ctx, n.expression.idx, n.shorthand,
									false, false, mut stats)
							}
						}
						'Class' {
							if n.expression.es {
								c.svrsra_verify(mut ctx, n.expression.idx, n.shorthand,
									true, false, mut stats)
							}
						}
						'EventHandler' {
							if n.expression.es {
								c.svrsra_verify(mut ctx, n.expression.idx, false, false,
									true, mut stats)
							}
						}
						else {}
					}
				}
				.style_directive {
					key := if !n.key.es && n.key.idx >= 0 {
						doc.nodes[n.key.idx].key
					} else {
						n.key
					}
					if n.shorthand && key.es && key.idx >= 0 && t.typ(key.idx) == .identifier {
						c.svrsra_verify(mut ctx, key.idx, true, false, false, mut stats)
					}
				}
				.special_directive {
					if n.kind == 'this' && n.expression.es {
						c.svrsra_verify(mut ctx, n.expression.idx, false, false, false, mut
							stats)
					}
				}
				.if_block, .await_block {
					if n.expression.es {
						c.svrsra_verify(mut ctx, n.expression.idx, false, true, false, mut
							stats)
					}
				}
				.each_block {
					if n.expression.es {
						c.svrsra_verify(mut ctx, n.expression.idx, false, false, false, mut
							stats)
					}
				}
				else {}
			}
			continue
		}
		i := step.node.idx
		node_of := fn [t, i] (key estree.Key) int {
			return t.node(i, key) or { -1 }
		}
		match t.typ(i) {
			.if_statement, .while_statement, .do_while_statement, .conditional_expression,
			.for_statement {
				c.svrsra_verify(mut ctx, node_of(.test), false, true, false, mut stats)
			}
			.for_in_statement, .for_of_statement {
				c.svrsra_verify(mut ctx, node_of(.right), false, false, false, mut stats)
			}
			.switch_statement {
				c.svrsra_verify(mut ctx, node_of(.discriminant), false, false, false, mut
					stats)
			}
			.call_expression, .new_expression {
				callee := node_of(.callee)
				if callee >= 0 && t.typ(callee) != .super {
					c.svrsra_verify(mut ctx, callee, false, false, t.typ(i) == .call_expression, mut
						stats)
				}
			}
			.unary_expression {
				operator := t.string_of(i, .operator) or { '' }
				c.svrsra_verify(mut ctx, node_of(.argument), false, operator in ['!', 'typeof'],
					false, mut stats)
			}
			.update_expression, .spread_element {
				c.svrsra_verify(mut ctx, node_of(.argument), false, false, false, mut stats)
			}
			.assignment_expression {
				operator := t.string_of(i, .operator) or { '' }
				left := node_of(.left)
				right := node_of(.right)
				if operator in ['??=', '||=', '&&='] {
					if operator == '??=' && c.svrsra_is_existence_check(mut ctx, left, right, mut
						stats)
					{
						continue
					}
					c.svrsra_verify(mut ctx, left, true, ctx.typed, false, mut stats)
					if !c.svrsra_is_store(mut ctx, left, false, mut stats) {
						c.svrsra_verify(mut ctx, right, false, false, false, mut stats)
					}
				} else if operator != '=' {
					if left >= 0 && t.typ(left) !in [.object_pattern, .array_pattern] {
						c.svrsra_verify(mut ctx, left, false, false, false, mut stats)
					}
					c.svrsra_verify(mut ctx, right, false, false, false, mut stats)
				}
			}
			.binary_expression {
				operator := t.string_of(i, .operator) or { '' }
				equality := operator in ['==', '!=', '===', '!==']
				left := node_of(.left)
				if left >= 0 && t.typ(left) != .private_identifier {
					c.svrsra_verify(mut ctx, left, false, equality, false, mut stats)
				}
				c.svrsra_verify(mut ctx, node_of(.right), false, equality, false, mut stats)
			}
			.logical_expression {
				if (t.string_of(i, .operator) or { '' }) == '??'
					&& c.svrsra_is_existence_check(mut ctx, node_of(.left), node_of(.right), mut
						stats)
				{
					continue
				}
				c.svrsra_verify(mut ctx, node_of(.left), false, true, false, mut stats)
			}
			.template_literal {
				for expr in t.list(i, .expressions) or { []int{} } {
					c.svrsra_verify(mut ctx, expr, false, false, false, mut stats)
				}
			}
			.tagged_template_expression {
				c.svrsra_verify(mut ctx, node_of(.tag), false, false, true, mut stats)
			}
			.property, .property_definition, .method_definition {
				key := node_of(.key)
				if key >= 0 && t.typ(key) != .private_identifier && (t.flag(i, .computed) or {
					false
				}) {
					c.svrsra_verify(mut ctx, key, false, false, false, mut stats)
				}
			}
			.import_expression {
				c.svrsra_verify(mut ctx, node_of(.source), false, false, false, mut stats)
			}
			.await_expression {
				c.svrsra_verify(mut ctx, node_of(.argument), false, true, false, mut stats)
			}
			else {}
		}
	}
	return ctx.findings
}
