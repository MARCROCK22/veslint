module svelte

import estree

// The default export typing the component (src/parser/typescript/analyze/component.ts
// appendComponentDefaultExport), appended last to the virtual code when the script has none.

fn (mut x Virt) component_default_export(c &Conv) {
	if x.has_default_export() {
		return
	}
	mut range_start := -1
	mut range_end := -1
	if c.ca.instance >= 0 {
		inst := c.ca.nodes[c.ca.instance]
		range_start = x.doc.utf16(inst.content_start)
		range_end = x.doc.utf16(inst.content_end)
	}
	mut statements := []int{}
	if range_start >= 0 {
		for st in x.list(x.es.root, .body) {
			if range_start <= x.s(st) && x.e(st) <= range_end {
				statements << st
			}
		}
	}
	mut names := []string{}
	mut code := '\n'
	mut props_type := ''
	explicit, members, probe, open, found := x.recover_runes_props(range_start, range_end)
	if found && explicit != '' {
		props_type = explicit
	} else if found {
		mut parts := []string{}
		if probe != '' {
			probe_name := x.v.unique_id('propsProbe')
			names << probe_name
			code += 'const ${probe_name} = ${probe};'
			parts << '{ [K in keyof typeof ${probe_name}]?: (typeof ${probe_name})[K] }'
		}
		if members != '' {
			parts << members
		}
		if open {
			parts << '{ [key: string]: any }'
		}
		props_type = if parts.len > 0 { parts.join(' & ') } else { '{ [key: string]: never }' }
	} else if x.runes != .on && x.has_named_type(statements, '\$\$Props') {
		props_type = '\$\$Props'
	} else {
		probe_name := x.v.unique_id('legacyPropsProbe')
		mut inferred := []string{}
		export_let := x.legacy_export_let_type(statements, probe_name, mut inferred)
		if inferred.len > 0 {
			names << probe_name
			code += 'const ${probe_name} = () => ({ ${inferred.join(', ')} });'
		}
		if export_let != '' && (x.through_has('\$\$props') || x.through_has('\$\$restProps')) {
			props_type = '${export_let} & { [key: string]: any }'
		} else {
			props_type = if export_let != '' { export_let } else { '{ [key: string]: any }' }
		}
	}
	events := if x.has_named_type(statements, '\$\$Events') {
		'\$\$Events'
	} else {
		'{ [key: string]: any }'
	}
	slots := if x.has_named_type(statements, '\$\$Slots') {
		'\$\$Slots'
	} else {
		'{ [key: string]: any }'
	}
	name := x.v.unique_id('svelteComponent')
	exports := x.instance_exports_type(statements)
	value_type := if exports == '' {
		"import('svelte').Component<${props_type}>"
	} else {
		"import('svelte').Component<${props_type}, ${exports}>"
	}
	mut type_type := "import('svelte').SvelteComponent<${props_type}, ${events}, ${slots}>"
	if exports != '' {
		type_type += ' & ${exports}'
	}
	code += 'declare const ${name}: ${value_type};type ${name} = ${type_type};export { ${name} as default };'
	x.v.append_virtual(code)
}

fn (x &Virt) export_name(n int) string {
	if x.typ(n) == .identifier {
		return x.name(n)
	}
	v := x.es.get(n, .value)
	if v is string {
		return v
	}
	return ''
}

fn (x &Virt) kind_of(n int, key estree.Key) string {
	return x.es.string_of(n, key) or { '' }
}

fn (x &Virt) has_default_export() bool {
	for st in x.list(x.es.root, .body) {
		match x.typ(st) {
			.export_default_declaration {
				return true
			}
			.export_named_declaration {
				if x.kind_of(st, .export_kind) != 'type' {
					for sp in x.list(st, .specifiers) {
						if x.kind_of(sp, .export_kind) != 'type'
							&& x.export_name(x.node(sp, .exported)) == 'default' {
							return true
						}
					}
				}
			}
			.export_all_declaration {
				exported := x.node(st, .exported)
				if x.kind_of(st, .export_kind) != 'type' && exported >= 0
					&& x.export_name(exported) == 'default' {
					return true
				}
			}
			else {}
		}
	}
	return false
}

fn (x &Virt) has_named_type(statements []int, name string) bool {
	for st in statements {
		n := if x.typ(st) == .export_named_declaration { x.node(st, .declaration) } else { st }
		if n >= 0 && x.typ(n) in [.ts_interface_declaration, .ts_type_alias_declaration]
			&& x.name(x.node(n, .id)) == name {
			return true
		}
	}
	return false
}

fn (x &Virt) text(n int) string {
	return x.slice16(x.s(n), x.e(n))
}

fn (x &Virt) slice16(a int, b int) string {
	return x.v.original[x.v.oindex.to_byte(a)..x.v.oindex.to_byte(b)]
}

fn prop_key(name string) string {
	if name.len > 0 && (name[0].is_letter() || name[0] == `_` || name[0] == `$`)
		&& name.bytes().all(it.is_letter() || it.is_digit() || it == `_` || it == `$`) {
		return name
	}
	return json_quote(name)
}

fn (x &Virt) strip_as_const(n int) int {
	if x.typ(n) == .ts_as_expression {
		ta := x.node(n, .type_annotation)
		if ta >= 0 && x.typ(ta) == .ts_type_reference {
			tn := x.node(ta, .type_name)
			if tn >= 0 && x.typ(tn) == .identifier && x.name(tn) == 'const' {
				return x.node(n, .expression)
			}
		}
	}
	return n
}

fn (x &Virt) degenerate_default_type(n int) string {
	match x.typ(n) {
		.array_expression {
			if x.list(n, .elements).len == 0 {
				return 'any[]'
			}
		}
		.literal {
			if (x.es.string_of(n, .raw) or { '' }) == 'null' {
				return 'any'
			}
		}
		.identifier {
			if x.name(n) == 'undefined' {
				return 'any'
			}
		}
		.unary_expression {
			if x.kind_of(n, .operator) == 'void' {
				return 'any'
			}
		}
		else {}
	}
	return ''
}

fn (x &Virt) legacy_export_let_type(statements []int, probe string, mut inferred []string) string {
	if x.runes == .on {
		return ''
	}
	mut members := []string{}
	mut let_decls := map[string]int{}
	for st in statements {
		decl := if x.typ(st) == .export_named_declaration { x.node(st, .declaration) } else { st }
		if decl < 0 || x.typ(decl) != .variable_declaration || x.kind_of(decl, .kind) != 'let' {
			continue
		}
		for d in x.list(decl, .declarations) {
			id := x.node(d, .id)
			if x.typ(id) == .identifier {
				let_decls[x.name(id)] = d
			}
		}
	}
	for st in statements {
		if x.typ(st) != .export_named_declaration || x.kind_of(st, .export_kind) == 'type' {
			continue
		}
		decl := x.node(st, .declaration)
		if decl >= 0 && x.typ(decl) == .variable_declaration && x.kind_of(decl, .kind) == 'let' {
			for d in x.list(decl, .declarations) {
				id := x.node(d, .id)
				if x.typ(id) != .identifier {
					continue
				}
				members << x.push_member(x.name(id), d, probe, mut inferred)
			}
			continue
		}
		if decl < 0 && x.node(st, .source) < 0 {
			for sp in x.list(st, .specifiers) {
				local := x.node(sp, .local)
				if x.typ(local) != .identifier || x.kind_of(sp, .export_kind) == 'type'
					|| x.export_name(x.node(sp, .exported)) == 'default' {
					continue
				}
				d := let_decls[x.name(local)] or { continue }
				members << x.push_member(x.export_name(x.node(sp, .exported)), d, probe, mut
					inferred)
			}
		}
	}
	if members.len == 0 {
		return ''
	}
	return '{ ${members.join('; ')} }'
}

fn (x &Virt) push_member(exported string, d int, probe string, mut inferred []string) string {
	init := x.node(d, .init)
	optional := init >= 0
	id := x.node(d, .id)
	ann := if x.typ(id) == .identifier { x.node(id, .type_annotation) } else { -1 }
	local := if x.typ(id) == .identifier { x.name(id) } else { '' }
	mut typ := ''
	if ann >= 0 {
		typ = x.text(x.node(ann, .type_annotation))
	} else if local != '' {
		if init >= 0 {
			typ = x.degenerate_default_type(x.strip_as_const(init))
		}
		if typ == '' {
			if local !in inferred {
				inferred << local
			}
			typ = '(typeof ${probe} extends () => infer P ? P : never)[${json_quote(local)}]'
		}
	} else {
		typ = 'any'
	}
	return '${prop_key(exported)}${if optional { '?' } else { '' }}: ${typ}'
}

fn (x &Virt) instance_exports_type(statements []int) string {
	legacy := x.runes != .on
	mut let_bindings := []string{}
	for st in statements {
		decl := if x.typ(st) == .export_named_declaration { x.node(st, .declaration) } else { st }
		if decl < 0 || x.typ(decl) != .variable_declaration || x.kind_of(decl, .kind) != 'let' {
			continue
		}
		for d in x.list(decl, .declarations) {
			id := x.node(d, .id)
			if x.typ(id) == .identifier {
				let_bindings << x.name(id)
			}
		}
	}
	mut keys := []string{}
	mut values := map[string]string{}
	for st in statements {
		if x.typ(st) != .export_named_declaration || x.kind_of(st, .export_kind) == 'type' {
			continue
		}
		decl := x.node(st, .declaration)
		if decl >= 0 && x.typ(decl) == .variable_declaration {
			if legacy && x.kind_of(decl, .kind) == 'let' {
				continue
			}
			for d in x.list(decl, .declarations) {
				id := x.node(d, .id)
				if x.typ(id) == .identifier {
					nm := x.name(id)
					if nm !in values {
						keys << nm
					}
					values[nm] = nm
				}
			}
		} else if decl >= 0 && x.typ(decl) in [.function_declaration, .class_declaration] {
			id := x.node(decl, .id)
			if id >= 0 {
				nm := x.name(id)
				if nm !in values {
					keys << nm
				}
				values[nm] = nm
			}
		} else if decl < 0 && x.node(st, .source) < 0 {
			for sp in x.list(st, .specifiers) {
				local := x.node(sp, .local)
				if x.typ(local) != .identifier || x.kind_of(sp, .export_kind) == 'type' {
					continue
				}
				exported := x.export_name(x.node(sp, .exported))
				if exported == 'default' || (legacy && x.name(local) in let_bindings) {
					continue
				}
				if exported !in values {
					keys << exported
				}
				values[exported] = x.name(local)
			}
		}
	}
	if keys.len == 0 {
		return ''
	}
	return '{ ${keys.map('${prop_key(it)}: typeof ${values[it]}').join('; ')} }'
}

// recover_runes_props is recoverRunesProps: (explicit type, members, probe, open, found).
fn (x &Virt) recover_runes_props(start int, end int) (string, string, string, bool, bool) {
	if x.runes == .off || start < 0 {
		return '', '', '', false, false
	}
	for r in x.through {
		id := x.an.refs[r].id
		if x.name(id) != '\$props' || !(start <= x.s(id) && x.e(id) <= end) {
			continue
		}
		call := x.es.nodes[id].parent
		if call < 0 || x.typ(call) != .call_expression || x.node(call, .callee) != id {
			continue
		}
		mut value := call
		mut cast := -1
		for {
			p := x.es.nodes[value].parent
			if p >= 0 && x.typ(p) in [.ts_as_expression, .ts_satisfies_expression] {
				cast = x.node(p, .type_annotation)
				value = p
			} else if p >= 0 && x.typ(p) == .ts_non_null_expression {
				value = p
			} else {
				break
			}
		}
		decl := x.es.nodes[value].parent
		if decl < 0 || x.typ(decl) != .variable_declarator || x.node(decl, .init) != value {
			continue
		}
		declaration := x.es.nodes[decl].parent
		mut stmt := declaration
		if declaration >= 0 && x.es.nodes[declaration].parent >= 0
			&& x.typ(x.es.nodes[declaration].parent) == .export_named_declaration {
			stmt = x.es.nodes[declaration].parent
		}
		if stmt < 0 || x.es.nodes[stmt].parent != x.es.root {
			continue
		}
		decl_id := x.node(decl, .id)
		ann := x.node(decl_id, .type_annotation)
		typ := if ann >= 0 { x.node(ann, .type_annotation) } else { cast }
		if typ >= 0 {
			return x.text(typ), '', '', false, true
		}
		if x.typ(decl_id) == .object_pattern {
			m, p, o := x.infer_props(decl_id)
			return '', m, p, o, true
		}
	}
	return '', '', '', false, false
}

fn (x &Virt) infer_props(pattern int) (string, string, bool) {
	mut members := []string{}
	mut defaulted := []string{}
	mut seen := []string{}
	mut open := false
	for prop in x.list(pattern, .properties) {
		if x.typ(prop) != .property {
			open = true
			continue
		}
		key := x.node(prop, .key)
		computed := x.es.flag(prop, .computed) or { false }
		mut k := ''
		mut normalized := ''
		if !computed && x.typ(key) == .identifier {
			k = x.name(key)
			normalized = k
		} else if x.typ(key) == .literal {
			v := x.es.get(key, .value)
			if v is string {
				normalized = v
			} else if v is f64 {
				normalized = js_number_string(v)
			} else {
				open = true
				continue
			}
			k = x.es.string_of(key, .raw) or { '' }
		} else {
			open = true
			continue
		}
		if normalized in seen {
			continue
		}
		seen << normalized
		value := x.node(prop, .value)
		if x.typ(value) == .assignment_pattern {
			mut def := x.strip_as_const(x.node(value, .right))
			if x.typ(def) == .call_expression {
				callee := x.node(def, .callee)
				if x.typ(callee) == .identifier && x.name(callee) == '\$bindable'
					&& x.node(def, .type_arguments) < 0 {
					args := x.list(def, .arguments)
					if args.len == 0 {
						members << '${k}?: any'
						continue
					}
					if x.typ(args[0]) != .spread_element {
						def = x.strip_as_const(args[0])
					}
				}
			}
			degraded := x.degenerate_default_type(def)
			if degraded != '' {
				members << '${k}?: ${degraded}'
				continue
			}
			defaulted << '${k}: (${x.text(def)})'
		} else {
			members << '${k}: any'
		}
	}
	return if members.len > 0 { '{ ${members.join('; ')} }' } else { '' }, if defaulted.len > 0 {
		'{ ${defaulted.join(', ')} }'
	} else {
		''
	}, open
}
