module estree

// Declarations: functions, interfaces, type aliases, enums, modules, `declare`, imports and
// exports.

fn (mut c Converter) decl(s C.TSNode, ctx Ctx) int {
	kind := kind_of(s)
	match kind {
		'lexical_declaration', 'variable_declaration' {
			return c.var_decl(s, ctx)
		}
		'function_declaration', 'generator_function_declaration', 'function_signature' {
			return c.function_decl(s, ctx)
		}
		'function_expression', 'generator_function' {
			if ctx.exported {
				return c.function_decl(s, ctx)
			}
			return c.expr(s)
		}
		'class_declaration', 'abstract_class_declaration' {
			return c.class(s, true, ctx)
		}
		'class' {
			return c.class(s, ctx.exported, ctx)
		}
		'interface_declaration' {
			return c.interface_decl(s, ctx)
		}
		'type_alias_declaration' {
			return c.type_alias(s, ctx)
		}
		'enum_declaration' {
			return c.enum_decl(s, ctx)
		}
		'module', 'internal_module' {
			return c.module_decl(s, ctx)
		}
		'ambient_declaration' {
			return c.ambient(s, ctx)
		}
		'import_statement' {
			return c.import_decl(s, ctx)
		}
		'import_alias' {
			return c.import_alias(s, ctx)
		}
		'export_statement' {
			mut out := []int{}
			c.export_stmt(s, mut out)
			return if out.len > 0 { out[0] } else { -1 }
		}
		'expression_statement' {
			mut out := []int{}
			c.statement(s, mut out)
			return if out.len > 0 { out[0] } else { -1 }
		}
		else {
			return c.stmt_fallback(s)
		}
	}
}

fn (mut c Converter) stmt_fallback(s C.TSNode) int {
	// Unknown statement kinds are converted as expressions when they are some.
	return c.expr(s)
}

fn (mut c Converter) function_decl(s C.TSNode, ctx Ctx) int {
	kids := c.kids(s)
	body := field_of(kids, 'body')
	typ := if body == none { NodeType.ts_declare_function } else { NodeType.function_declaration }
	i := c.mk(typ, s, ctx.start_or(c.start(s)), c.end(s))
	c.pbool(i, .async, has_tok(kids, 'async'))
	saved := c.await_ctx
	c.await_ctx = has_tok(kids, 'async')
	defer {
		c.await_ctx = saved
	}
	if b := body {
		c.pnode(i, .body, c.block(b.n, true))
	}
	c.pbool(i, .declare_, ctx.declare)
	c.pbool(i, .expression, false)
	c.pbool(i, .generator, has_tok(kids, '*'))
	if name := field_of(kids, 'name') {
		c.pnode(i, .id, c.ident(name.n))
	} else {
		c.pnull(i, .id)
	}
	c.function_signature(i, kids, true)
	return i
}

// function_signature sets params, returnType and typeParameters from the fields of a function.
fn (mut c Converter) function_signature(i int, kids []Kid, param_decorators bool) {
	if params := field_of(kids, 'parameters') {
		c.plist(i, .params, c.params(params.n, param_decorators))
	} else if param := field_of(kids, 'parameter') {
		c.plist(i, .params, [c.ident(param.n)])
	} else {
		c.plist(i, .params, [])
	}
	if rt := field_of(kids, 'return_type') {
		c.pnode(i, .return_type, c.return_type(rt.n, kids))
	} else if rt := field_of(kids, 'type') {
		// construct_signature and constructor_type name it `type`.
		if rt.kind == 'type_annotation' {
			c.pnode(i, .return_type, c.type_annotation(rt.n))
		} else {
			c.pnode(i, .return_type, c.return_type(rt.n, kids))
		}
	}
	if tp := field_of(kids, 'type_parameters') {
		c.pnode(i, .type_parameters, c.type_parameters(tp.n))
	}
}

fn (mut c Converter) interface_decl(s C.TSNode, ctx Ctx) int {
	kids := c.kids(s)
	i := c.mk(.ts_interface_declaration, s, ctx.start_or(c.start(s)), c.end(s))
	if b := field_of(kids, 'body') {
		body := c.mk(.ts_interface_body, b.n, c.start(b.n), c.end(s))
		c.plist(body, .body, c.type_members(b.n))
		c.pnode(i, .body, body)
	}
	c.pbool(i, .declare_, ctx.declare)
	mut heritage := []int{}
	for k in kids {
		if k.kind == 'extends_type_clause' {
			for t in c.kids(k.n) {
				if t.field == 'type' {
					heritage << c.heritage(t.n, .ts_interface_heritage)
				}
			}
		}
	}
	c.plist(i, .extends_, heritage)
	c.pnode(i, .id, c.ident(field_of(kids, 'name') or { return i }.n))
	if tp := field_of(kids, 'type_parameters') {
		c.pnode(i, .type_parameters, c.type_parameters(tp.n))
	}
	return i
}

fn (mut c Converter) type_alias(s C.TSNode, ctx Ctx) int {
	kids := c.kids(s)
	i := c.mk(.ts_type_alias_declaration, s, ctx.start_or(c.start(s)), c.end(s))
	c.pbool(i, .declare_, ctx.declare)
	c.pnode(i, .id, c.ident(field_of(kids, 'name') or { return i }.n))
	value := field_of(kids, 'value') or { return i }
	if value.kind == 'type_identifier' && c.text(value.n) == 'intrinsic' {
		c.pnode(i, .type_annotation, c.mkn(.ts_intrinsic_keyword, value.n))
	} else {
		c.pnode(i, .type_annotation, c.typ(value.n))
	}
	if tp := field_of(kids, 'type_parameters') {
		c.pnode(i, .type_parameters, c.type_parameters(tp.n))
	}
	return i
}

fn (mut c Converter) enum_decl(s C.TSNode, ctx Ctx) int {
	kids := c.kids(s)
	i := c.mk(.ts_enum_declaration, s, ctx.start_or(c.start(s)), c.end(s))
	if b := field_of(kids, 'body') {
		body := c.mk(.ts_enum_body, b.n, c.start(b.n), c.end(s))
		mut members := []int{}
		for k in c.kids(b.n) {
			if k.kind == 'enum_assignment' {
				mk := c.kids(k.n)
				m := c.mkn(.ts_enum_member, k.n)
				c.pnode(m, .id, c.property_key(field_of(mk, 'name') or { continue }.n))
				if v := field_of(mk, 'value') {
					c.pnode(m, .initializer, c.expr(v.n))
				}
				members << m
			} else if k.field == 'name' {
				m := c.mkn(.ts_enum_member, k.n)
				c.pnode(m, .id, c.property_key(k.n))
				members << m
			}
		}
		c.plist(body, .members, members)
		c.pnode(i, .body, body)
	}
	c.pbool(i, .const_, has_tok(kids, 'const'))
	c.pbool(i, .declare_, ctx.declare)
	c.pnode(i, .id, c.ident(field_of(kids, 'name') or { return i }.n))
	return i
}

// module_decl converts `module`, `namespace` and `declare global`.
fn (mut c Converter) module_decl(s C.TSNode, ctx Ctx) int {
	kids := c.kids(s)
	i := c.mk(.ts_module_declaration, s, ctx.start_or(c.start(s)), c.end(s))
	name := field_of(kids, 'name') or { return i }
	body := field_of(kids, 'body')
	if b := body {
		mb := c.mkn(.ts_module_block, b.n)
		c.plist(mb, .body, c.body(c.named(b.n).map(it.n), true))
		c.pnode(i, .body, mb)
	}
	c.pbool(i, .declare_, ctx.declare)
	c.pbool(i, .global_, false)
	if name.kind == 'string' {
		c.pnode(i, .id, c.literal(name.n))
		c.pstr(i, .kind, 'module')
	} else {
		c.pnode(i, .id, c.entity_name(name.n))
		c.pstr(i, .kind, if has_tok(kids, 'namespace') { 'namespace' } else { 'module' })
	}
	return i
}

// entity_name converts a name of identifiers separated by dots to an Identifier or nested
// TSQualifiedName.
fn (mut c Converter) entity_name(n C.TSNode) int {
	match kind_of(n) {
		'nested_identifier', 'member_expression' {
			kids := c.kids(n)
			obj := field_of(kids, 'object') or { return -1 }
			prop := field_of(kids, 'property') or { return -1 }
			i := c.mkn(.ts_qualified_name, n)
			c.pnode(i, .left, c.entity_name(obj.n))
			c.pnode(i, .right, c.ident(prop.n))
			return i
		}
		'nested_type_identifier' {
			kids := c.kids(n)
			obj := field_of(kids, 'module') or { return -1 }
			prop := field_of(kids, 'name') or { return -1 }
			i := c.mkn(.ts_qualified_name, n)
			c.pnode(i, .left, c.entity_name(obj.n))
			c.pnode(i, .right, c.ident(prop.n))
			return i
		}
		'this' {
			return c.mkn(.this_expression, n)
		}
		else {
			return c.ident(n)
		}
	}
}

fn (mut c Converter) ambient(s C.TSNode, ctx Ctx) int {
	kids := c.kids(s)
	start := ctx.start_or(c.start(s))
	if has_tok(kids, 'global') {
		// declare global { … }
		i := c.mk(.ts_module_declaration, s, start, c.end(s))
		global := tok_of(kids, 'global') or { return i }
		if b := first_named(kids) {
			mb := c.mkn(.ts_module_block, b.n)
			c.plist(mb, .body, c.body(c.named(b.n).map(it.n), true))
			c.pnode(i, .body, mb)
		}
		c.pbool(i, .declare_, has_tok(kids, 'declare'))
		c.pbool(i, .global_, true)
		c.pnode(i, .id, c.ident_at(global.n, c.start(global.n), c.end(global.n), 'global'))
		c.pstr(i, .kind, 'global')
		return i
	}
	inner := first_named(kids) or { return -1 }
	i := c.decl(inner.n, Ctx{
		declare: true
		start:   start
	})
	if i >= 0 && c.t.nodes[i].end < c.end(s) {
		c.t.nodes[i].end = c.end(s)
	}
	return i
}

// --- Imports ---

fn (mut c Converter) import_decl(s C.TSNode, ctx Ctx) int {
	kids := c.kids(s)
	for req in kids {
		if req.kind == 'import_require_clause' {
			return c.import_require(s, kids, req, ctx)
		}
	}
	i := c.mk(.import_declaration, s, ctx.start_or(c.start(s)), c.end(s))
	c.plist(i, .attributes, c.import_attributes(kids))
	// `import type X`: a `type` token between `import` and the clause.
	c.pstr(i, .import_kind, if has_tok(kids, 'type') { 'type' } else { 'value' })
	if src := field_of(kids, 'source') {
		c.pnode(i, .source, c.literal(src.n))
	}
	mut specifiers := []int{}
	for k in kids {
		if k.kind != 'import_clause' {
			continue
		}
		for part in c.kids(k.n) {
			match part.kind {
				'identifier' {
					local := c.ident(part.n)
					sp := c.mkn(.import_default_specifier, part.n)
					c.pnode(sp, .local, local)
					specifiers << sp
				}
				'namespace_import' {
					sp := c.mkn(.import_namespace_specifier, part.n)
					if id := first_named(c.kids(part.n)) {
						c.pnode(sp, .local, c.ident(id.n))
					}
					specifiers << sp
				}
				'named_imports' {
					for spec in c.kids(part.n) {
						if spec.kind != 'import_specifier' {
							continue
						}
						sk := c.kids(spec.n)
						sp := c.mkn(.import_specifier, spec.n)
						name := field_of(sk, 'name') or { continue }
						alias := field_of(sk, 'alias')
						c.pnode(sp, .imported, c.module_name(name.n))
						c.pstr(sp, .import_kind, if has_tok(sk, 'type') { 'type' } else { 'value' })
						if a := alias {
							c.pnode(sp, .local, c.module_name(a.n))
						} else {
							c.pnode(sp, .local, c.module_name(name.n))
						}
						specifiers << sp
					}
				}
				else {}
			}
		}
	}
	c.plist(i, .specifiers, specifiers)
	return i
}

// module_name is an imported or exported name: an Identifier or a string Literal.
fn (mut c Converter) module_name(n C.TSNode) int {
	if kind_of(n) == 'string' {
		return c.literal(n)
	}
	return c.ident(n)
}

fn (mut c Converter) import_attributes(kids []Kid) []int {
	mut out := []int{}
	for k in kids {
		if k.kind != 'import_attribute' {
			continue
		}
		obj := first_named(c.kids(k.n)) or { continue }
		for pair in c.kids(obj.n) {
			if pair.kind != 'pair' {
				continue
			}
			pk := c.kids(pair.n)
			a := c.mkn(.import_attribute, pair.n)
			c.pnode(a, .key, c.property_key(field_of(pk, 'key') or { continue }.n))
			c.pnode(a, .value, c.expr(field_of(pk, 'value') or { continue }.n))
			out << a
		}
	}
	return out
}

// import_require converts `import x = require('y')`.
fn (mut c Converter) import_require(s C.TSNode, kids []Kid, req Kid, ctx Ctx) int {
	i := c.mk(.ts_import_equals_declaration, s, ctx.start_or(c.start(s)), c.end(s))
	rk := c.kids(req.n)
	if id := first_named(rk) {
		c.pnode(i, .id, c.ident(id.n))
	}
	c.pstr(i, .import_kind, if has_tok(kids, 'type') { 'type' } else { 'value' })
	if require := tok_of(rk, 'require') {
		src := field_of(rk, 'source') or { return i }
		ext := c.mk(.ts_external_module_reference, require.n, c.start(require.n), c.end(req.n))
		c.pnode(ext, .expression, c.literal(src.n))
		c.pnode(i, .module_reference, ext)
	}
	return i
}

// import_alias converts `import x = A.B`.
fn (mut c Converter) import_alias(s C.TSNode, ctx Ctx) int {
	kids := c.kids(s)
	i := c.mk(.ts_import_equals_declaration, s, ctx.start_or(c.start(s)), c.end(s))
	named := kids.filter(it.named)
	if named.len < 2 {
		return i
	}
	c.pnode(i, .id, c.ident(named[0].n))
	c.pstr(i, .import_kind, if has_tok(kids, 'type') { 'type' } else { 'value' })
	c.pnode(i, .module_reference, c.entity_name(named[1].n))
	return i
}

// --- Exports ---

fn (mut c Converter) export_stmt(s C.TSNode, mut out []int) {
	kids := c.kids(s)
	export_tok := tok_of(kids, 'export') or { return }
	export_start := c.start(export_tok.n)
	is_default := has_tok(kids, 'default')
	decorators := fields_of(kids, 'decorator')
	if d := field_of(kids, 'declaration') {
		// The declaration starts at the token after `export` (or `export default`).
		decl := c.decl(d.n, Ctx{
			exported: is_default
		})
		if decl < 0 {
			return
		}
		if decorators.len > 0 {
			c.set_list_prop(decl, .decorators, decorators.map(c.decorator(it.n)))
		}
		end := c.t.nodes[decl].end
		if is_default {
			i := c.mk(.export_default_declaration, s, export_start, end)
			c.pnode(i, .declaration, decl)
			c.pstr(i, .export_kind, 'value')
			out << i
		} else {
			i := c.mk(.export_named_declaration, s, export_start, end)
			c.plist(i, .attributes, [])
			c.pnode(i, .declaration, decl)
			typ := c.t.nodes[decl].typ
			is_type := typ in [.ts_interface_declaration, .ts_type_alias_declaration]
			c.pstr(i, .export_kind, if is_type || c.prop_bool(decl, .declare_) {
				'type'
			} else {
				'value'
			})
			c.pnull(i, .source)
			c.plist(i, .specifiers, [])
			out << i
		}
		// A `;` tree-sitter put in the statement after a declaration is an empty statement.
		if semi := tok_of(kids, ';') {
			if c.start(semi.n) >= end {
				out << c.mkn(.empty_statement, semi.n)
			}
		}
		return
	}
	if v := field_of(kids, 'value') {
		if is_default {
			if v.kind in ['class', 'function_expression', 'generator_function'] {
				decl := c.decl(v.n, Ctx{
					exported: true
				})
				if decorators.len > 0 {
					c.set_list_prop(decl, .decorators, decorators.map(c.decorator(it.n)))
				}
				end := c.t.nodes[decl].end
				i := c.mk(.export_default_declaration, s, export_start, end)
				c.pnode(i, .declaration, decl)
				c.pstr(i, .export_kind, 'value')
				out << i
				if semi := tok_of(kids, ';') {
					out << c.mkn(.empty_statement, semi.n)
				}
				return
			}
			i := c.mk(.export_default_declaration, s, export_start, c.end(s))
			c.pnode(i, .declaration, c.expr(v.n))
			c.pstr(i, .export_kind, 'value')
			out << i
			return
		}
	}
	if has_tok(kids, '=') {
		// export = x;
		i := c.mk(.ts_export_assignment, s, export_start, c.end(s))
		if e := first_named(kids.filter(it.field == '')) {
			c.pnode(i, .expression, c.expr(e.n))
		}
		out << i
		return
	}
	if has_tok(kids, 'namespace') && has_tok(kids, 'as') {
		// export as namespace X;
		i := c.mk(.ts_namespace_export_declaration, s, export_start, c.end(s))
		if id := first_named(kids) {
			c.pnode(i, .id, c.ident(id.n))
		}
		out << i
		return
	}
	export_kind := if has_tok(kids, 'type') { 'type' } else { 'value' }
	if has_tok(kids, '*') || kids.any(it.kind == 'namespace_export') {
		i := c.mk(.export_all_declaration, s, export_start, c.end(s))
		c.plist(i, .attributes, c.import_attributes(kids))
		mut exported := -1
		for k in kids {
			if k.kind == 'namespace_export' {
				if name := first_named(c.kids(k.n)) {
					exported = c.module_name(name.n)
				}
			}
		}
		c.pnode(i, .exported, exported)
		c.pstr(i, .export_kind, export_kind)
		if src := field_of(kids, 'source') {
			c.pnode(i, .source, c.literal(src.n))
		}
		out << i
		return
	}
	i := c.mk(.export_named_declaration, s, export_start, c.end(s))
	c.plist(i, .attributes, c.import_attributes(kids))
	c.pnull(i, .declaration)
	c.pstr(i, .export_kind, export_kind)
	if src := field_of(kids, 'source') {
		c.pnode(i, .source, c.literal(src.n))
	} else {
		c.pnull(i, .source)
	}
	mut specifiers := []int{}
	for k in kids {
		if k.kind != 'export_clause' {
			continue
		}
		for spec in c.kids(k.n) {
			if spec.kind != 'export_specifier' {
				continue
			}
			sk := c.kids(spec.n)
			sp := c.mkn(.export_specifier, spec.n)
			name := field_of(sk, 'name') or { continue }
			if a := field_of(sk, 'alias') {
				c.pnode(sp, .exported, c.module_name(a.n))
			} else {
				c.pnode(sp, .exported, c.module_name(name.n))
			}
			c.pstr(sp, .export_kind, if has_tok(sk, 'type') { 'type' } else { 'value' })
			c.pnode(sp, .local, c.module_name(name.n))
			specifiers << sp
		}
	}
	c.plist(i, .specifiers, specifiers)
	out << i
}
