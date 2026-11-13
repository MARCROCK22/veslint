module rules

import estree
import treesitter { Ident }

// The parts of ESLint's ast-utils the rules ported on the estree module use, on its nodes
// (indexes of an EsTree). Positions are byte offsets of the source.

// es_tree_static_string_value ports getStaticStringValue.
fn es_tree_static_string_value(t &estree.EsTree, node int) ?string {
	match t.typ(node) {
		.literal {
			v := t.get(node, .value)
			match v {
				estree.Null {
					if (t.string_of(node, .raw) or { '' }) == 'null' {
						return 'null'
					}
					if regex := t.prop(node, .regex) {
						return '/${regex.str}/${regex.str2}'
					}
					if t.prop(node, .bigint) != none {
						return t.string_of(node, .bigint)
					}
					return none
				}
				string {
					return v
				}
				bool {
					return v.str()
				}
				f64 {
					return js_number_to_string(v)
				}
				estree.BigIntValue {
					return t.string_of(node, .bigint)
				}
				estree.RegExpValue {
					regex := t.prop(node, .regex)?
					return '/${regex.str}/${regex.str2}'
				}
				else {
					return none
				}
			}
		}
		.template_literal {
			expressions := t.list(node, .expressions) or { []int{} }
			quasis := t.list(node, .quasis) or { []int{} }
			if expressions.len == 0 && quasis.len == 1 {
				v := t.get(quasis[0], .value)
				if v is estree.TemplateValue && v.has_cooked {
					return v.cooked
				}
			}
		}
		else {}
	}
	return none
}

// es_tree_static_property_name ports getStaticPropertyName.
fn es_tree_static_property_name(t &estree.EsTree, node int) ?string {
	if node < 0 {
		return none
	}
	prop := match t.typ(node) {
		.chain_expression {
			return es_tree_static_property_name(t, t.node(node, .expression) or { -1 })
		}
		.property, .property_definition, .method_definition, .ts_property_signature,
		.ts_method_signature {
			t.node(node, .key)?
		}
		.member_expression {
			t.node(node, .property)?
		}
		else {
			return none
		}
	}
	if t.typ(prop) == .identifier && !(t.flag(node, .computed) or { false }) {
		return t.string_of(prop, .name)
	}
	return es_tree_static_string_value(t, prop)
}

// es_tree_skip_chain ports skipChainExpression.
fn es_tree_skip_chain(t &estree.EsTree, node int) int {
	if node >= 0 && t.typ(node) == .chain_expression {
		return t.node(node, .expression) or { node }
	}
	return node
}

// es_tree_is_specific_id ports isSpecificId with a name.
fn es_tree_is_specific_id(t &estree.EsTree, node int, name string) bool {
	return node >= 0 && t.typ(node) == .identifier && (t.string_of(node, .name) or { '' }) == name
}

// es_tree_is_specific_member_access ports isSpecificMemberAccess with names ('' for any).
fn es_tree_is_specific_member_access(t &estree.EsTree, node int, object_name string, property_name string) bool {
	if node < 0 {
		return false
	}
	check := es_tree_skip_chain(t, node)
	if check < 0 || t.typ(check) != .member_expression {
		return false
	}
	if object_name != '' && !es_tree_is_specific_id(t, t.node(check, .object) or { -1 }, object_name) {
		return false
	}
	if property_name != '' {
		return (es_tree_static_property_name(t, check) or { return false }) == property_name
	}
	return true
}

// es_tree_function_name ports getFunctionNameWithKind.
fn (c &Checker) es_tree_function_name(t &estree.EsTree, node int) string {
	parent := t.nodes[node].parent
	ptyp := if parent >= 0 { t.typ(parent) } else { estree.NodeType.program }
	ntyp := t.typ(node)
	mut tokens := []string{}
	key := if parent >= 0 { t.node(parent, .key) or { -1 } } else { -1 }
	computed := parent >= 0 && (t.flag(parent, .computed) or { false })
	if ptyp in [.method_definition, .property_definition]
		|| ntyp in [.ts_property_signature, .ts_method_signature] {
		if t.flag(parent, .static_) or { false } {
			tokens << 'static'
		}
		if !computed && key >= 0 && t.typ(key) == .private_identifier {
			tokens << 'private'
		}
	}
	if t.flag(node, .async) or { false } {
		tokens << 'async'
	}
	if t.flag(node, .generator) or { false } {
		tokens << 'generator'
	}
	if ptyp in [.property, .method_definition] {
		kind := t.string_of(parent, .kind) or { '' }
		if kind == 'constructor' {
			return 'constructor'
		}
		tokens << match kind {
			'get' { 'getter' }
			'set' { 'setter' }
			else { 'method' }
		}
	} else if ntyp == .ts_method_signature {
		tokens << match t.string_of(node, .kind) or { '' } {
			'get' { 'getter' }
			'set' { 'setter' }
			else { 'method' }
		}
	} else if ptyp == .property_definition {
		tokens << 'method'
	} else {
		if ntyp == .arrow_function_expression {
			tokens << 'arrow'
		}
		tokens << 'function'
	}
	id := t.node(node, .id) or { -1 }
	if ptyp in [.property, .method_definition, .property_definition] {
		if !computed && key >= 0 && t.typ(key) == .private_identifier {
			tokens << '#${t.string_of(key, .name) or { '' }}'
		} else if name := es_tree_static_property_name(t, parent) {
			tokens << "'${name}'"
		} else if id >= 0 {
			tokens << "'${t.string_of(id, .name) or { '' }}'"
		}
	} else if ntyp == .ts_method_signature {
		tokens << "'${es_tree_static_property_name(t, node) or { 'null' }}'"
	} else if id >= 0 {
		tokens << "'${t.string_of(id, .name) or { '' }}'"
	}
	return tokens.join(' ')
}

// es_tree_position is the place of a report on an ESTree node: its range.
fn (c &Checker) es_tree_position(t &estree.EsTree, node int) Ident {
	return c.position_range(t.nodes[node].start, t.nodes[node].end)
}

// es_tree_function_head ports getFunctionHeadLoc: from the Property, MethodDefinition,
// PropertyDefinition, TSPropertySignature or TSMethodSignature the function is the value of (or
// the function) to the opening paren of its parameters, or the `=>` of an arrow function.
fn (mut c Checker) es_tree_function_head(t &estree.EsTree, node int) Ident {
	parent := t.nodes[node].parent
	if parent >= 0 && t.typ(parent) in [.property, .method_definition, .property_definition,
		.ts_property_signature, .ts_method_signature] {
		return c.position_range(t.nodes[parent].start, c.es_tree_params_paren(t, node))
	}
	if t.typ(node) == .arrow_function_expression {
		if body := t.node(node, .body) {
			tokens := c.source_tokens(t.nodes[t.root].ts)
			mut at := t.nodes[body].start
			for {
				token := tokens.before(at, false) or { break }
				if c.src[token.start..token.end] == '=>' {
					return c.position_range(token.start, token.end)
				}
				at = token.start
			}
		}
	}
	return c.position_range(t.nodes[node].start, c.es_tree_params_paren(t, node))
}

// es_tree_params_paren ports the start of getOpeningParenOfParams: the `(` of the parameters (the
// first one after the id, or in the function), or, for an arrow function with a single parameter
// without parentheses, the parameter.
fn (mut c Checker) es_tree_params_paren(t &estree.EsTree, node int) int {
	tokens := c.source_tokens(t.nodes[t.root].ts)
	params := t.list(node, .params) or { []int{} }
	if t.typ(node) == .arrow_function_expression && params.len == 1 {
		arg := t.nodes[params[0]].start
		if before := tokens.before(arg, false) {
			if c.src[before.start..before.end] == '(' {
				return before.start
			}
		}
		return arg
	}
	mut at := if id := t.node(node, .id) { t.nodes[id].end } else { t.nodes[node].start }
	for {
		token := tokens.after(at, false) or { break }
		if token.start >= t.nodes[node].end {
			break
		}
		if c.src[token.start..token.end] == '(' {
			return token.start
		}
		at = token.end
	}
	return t.nodes[node].start
}
