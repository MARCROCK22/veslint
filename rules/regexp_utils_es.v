module rules

import estree
import regexpp
import treesitter { node_kind }

// The parts of eslint-plugin-regexp 3.3.3's lib/utils that read the ESTree (the `regexp/*` rules,
// regexp_utils.v): ast-utils/utils.ts (getStaticValue and getStringIfConstant, which also follow
// `regexp.source` and constant variables, getPropertyName, findVariable, findFunction,
// isKnownMethodCall, dereferenceOwnedVariable, dereferenceVariable, parseReplacements,
// getStringValueRange), string-literal-parser/ (the tokens of a string literal),
// replacements-utils.ts, ast-utils/extract-expression-references.ts, get-usage-of-pattern.ts and
// getRegExpNodeFromExpression of regexp-ast/ast.ts. Nodes are indexes of the file's EsTree; the
// scopes and getStaticValue of eslint-utils are veslint's (scope.v, static_value.v), on the
// tree-sitter nodes the ESTree nodes come from.

// rx_es_of is the ESTree node of a tree-sitter node of the file, -1 if none.
fn (mut c Checker) rx_es_of(t &estree.EsTree, n ?C.TSNode) int {
	node := n or { return -1 }
	return c.es_index_of(t, node) or { -1 }
}

// rx_parent ports getParent.
fn rx_parent(t &estree.EsTree, node int) int {
	return if node < 0 { -1 } else { t.nodes[node].parent }
}

// rx_find_variable ports findVariable(context, node) of an Identifier: its variable in the scope
// tree, -1 if none.
fn (mut c Checker) rx_find_variable(root C.TSNode, t &estree.EsTree, node int) int {
	if node < 0 || t.typ(node) != .identifier {
		return -1
	}
	ts := t.ts_node(node) or { return -1 }
	tree := c.scope_tree(root)
	return tree.find_variable(tree.get_scope(ts), t.string_of(node, .name) or { return -1 },
		t.nodes[node].start)
}

// rx_find_simple_variable ports findSimpleVariable: a variable of `{var,let,const} identifier
// ( = <init> )?`, with that one definition; -1 if none.
fn (mut c Checker) rx_find_simple_variable(root C.TSNode, t &estree.EsTree, identifier int) int {
	v := c.rx_find_variable(root, t, identifier)
	if v < 0 {
		return -1
	}
	tree := c.scope_tree(root)
	if tree.variables[v].defs.len != 1 {
		return -1
	}
	def := tree.variables[v].defs[0]
	if def.kind != .variable {
		return -1
	}
	decl_id := def.decl_id or { return -1 }
	if node_kind(decl_id) != 'identifier' {
		return -1
	}
	return v
}

// rx_dereference_owned_variable ports dereferenceOwnedVariable: the value of a variable that only
// this expression reads (read-only, not exported, its initialization and this reference its only
// references), followed; the expression itself otherwise.
fn (mut c Checker) rx_dereference_owned_variable(root C.TSNode, t &estree.EsTree, expression int) int {
	if expression < 0 || t.typ(expression) != .identifier {
		return expression
	}
	v := c.rx_find_simple_variable(root, t, expression)
	if v < 0 {
		return expression
	}
	tree := c.scope_tree(root)
	variable := tree.variables[v]
	def := variable.defs[0]
	declarator := c.rx_es_of(t, def.node)
	// def.parent is the declaration; exported variables are not owned.
	grand_parent := rx_parent(t, rx_parent(t, declarator))
	if grand_parent >= 0 && t.typ(grand_parent) == .export_named_declaration {
		return expression
	}
	if variable.references.len != 2 {
		return expression
	}
	init_ref := tree.references[variable.references[0]]
	this_ref := tree.references[variable.references[1]]
	init := def.init or { return expression }
	if !init_ref.init || def.node_kind_is_for_head()
		|| c.rx_es_of(t, this_ref.identifier) != expression {
		return expression
	}
	init_node := c.rx_es_of(t, init)
	if init_node < 0 {
		return expression
	}
	return c.rx_dereference_owned_variable(root, t, init_node)
}

// node_kind_is_for_head tells whether the definition is the binding of the head of a for-in/of
// loop (its `init` reference writes the right side, not def.node.init).
fn (d ScopeDefinition) node_kind_is_for_head() bool {
	return node_kind(d.node) != 'variable_declarator'
}

// rx_dereference_variable ports dereferenceVariable: the initializer of a const, or of a var or
// let only read after its initialization, followed.
fn (mut c Checker) rx_dereference_variable(root C.TSNode, t &estree.EsTree, expression int) int {
	if expression < 0 || t.typ(expression) != .identifier {
		return expression
	}
	v := c.rx_find_simple_variable(root, t, expression)
	if v < 0 {
		return expression
	}
	tree := c.scope_tree(root)
	variable := tree.variables[v]
	def := variable.defs[0]
	init := def.init or { return expression }
	init_node := c.rx_es_of(t, init)
	if init_node < 0 {
		return expression
	}
	if def.parent_kind == 'const' {
		return c.rx_dereference_variable(root, t, init_node)
	}
	mut inits := 0
	mut reads := 0
	for r in variable.references {
		ref := tree.references[r]
		if ref.init {
			inits++
		}
		if ref.is_read_only() {
			reads++
		}
	}
	if inits == 1 && reads + inits == variable.references.len {
		return c.rx_dereference_variable(root, t, init_node)
	}
	return expression
}

// rx_static_value ports getStaticValue of ast-utils/utils.ts: `+` of two static values,
// `.source` of a static RegExp, a template literal of static values and a constant variable are
// followed; anything else is eslint-utils' getStaticValue.
fn (mut c Checker) rx_static_value(root C.TSNode, t &estree.EsTree, node int) StaticValue {
	if node < 0 {
		return StaticValue{}
	}
	match t.typ(node) {
		.binary_expression {
			if (t.string_of(node, .operator) or { '' }) == '+' {
				left := c.rx_static_value(root, t, t.node(node, .left) or { -1 })
				if !left.found {
					return StaticValue{}
				}
				right := c.rx_static_value(root, t, t.node(node, .right) or { -1 })
				if !right.found {
					return StaticValue{}
				}
				value := stv_binary_operation('+', left.value, right.value) or {
					return StaticValue{}
				}
				return stv_found(value)
			}
		}
		.member_expression {
			if (c.rx_property_name(root, t, node) or { '' }) == 'source' {
				object := c.rx_static_value(root, t, t.node(node, .object) or { -1 })
				if object.found && object.value.kind == .regexp_ {
					return stv_found(js_any_string(object.value.regexp.source))
				}
			}
		}
		.template_literal {
			mut values := []JsAny{}
			for expr in t.list(node, .expressions) or { []int{} } {
				value := c.rx_static_value(root, t, expr)
				if !value.found {
					return StaticValue{}
				}
				values << value.value
			}
			quasis := t.list(node, .quasis) or { return StaticValue{} }
			mut out := rx_cooked(t, quasis[0])
			for i, value in values {
				out << regexpp.to_utf16(js_any_string_value(value) or { return StaticValue{} })
				out << rx_cooked(t, quasis[i + 1])
			}
			return stv_found(js_any_string(out))
		}
		.identifier {
			de_ref := c.rx_dereference_variable(root, t, node)
			if de_ref != node {
				return c.rx_static_value(root, t, de_ref)
			}
		}
		else {}
	}
	ts := t.ts_node(node) or { return StaticValue{} }
	return c.get_static_value(ts)
}

// rx_cooked is the cooked value of a template element (`String(null)` when it has none).
fn rx_cooked(t &estree.EsTree, quasi int) []u16 {
	v := t.get(quasi, .value)
	if v is estree.TemplateValue {
		return if v.has_cooked { regexpp.to_utf16(v.cooked) } else { regexpp.to_utf16('undefined') }
	}
	return []
}

// rx_string_if_constant ports getStringIfConstant of ast-utils/utils.ts: String() of the static
// value of a binary or member expression, an identifier or a template literal (which follow
// `regexp.source`), eslint-utils' getStringIfConstant otherwise.
fn (mut c Checker) rx_string_if_constant(root C.TSNode, t &estree.EsTree, node int) ?string {
	if node < 0 {
		return none
	}
	if t.typ(node) in [.binary_expression, .member_expression, .identifier, .template_literal] {
		evaluated := c.rx_static_value(root, t, node)
		if !evaluated.found {
			return none
		}
		return js_any_string_value(evaluated.value)
	}
	ts := t.ts_node(node) or { return none }
	return c.string_if_constant(ts)
}

// rx_property_name ports getPropertyName(node, context): the name of a non-computed property, the
// constant string of a computed one; none for a private name.
fn (mut c Checker) rx_property_name(root C.TSNode, t &estree.EsTree, member int) ?string {
	prop := t.node(member, .property)?
	if t.typ(prop) == .private_identifier {
		return none
	}
	if !(t.flag(member, .computed) or { false }) {
		return t.string_of(prop, .name)
	}
	return c.rx_string_if_constant(root, t, prop)
}

// rx_property_name_unscoped ports getPropertyName(node) without a context: a computed property is
// named only by a string literal.
fn rx_property_name_unscoped(t &estree.EsTree, member int) ?string {
	prop := t.node(member, .property)?
	if t.typ(prop) == .private_identifier {
		return none
	}
	if !(t.flag(member, .computed) or { false }) {
		return t.string_of(prop, .name)
	}
	if rx_is_string_literal(t, prop) {
		v := t.get(prop, .value)
		if v is string {
			return v
		}
	}
	return none
}

// rx_find_function ports findFunction: the function a name stands for, through `const` aliases;
// -1 if none.
fn (mut c Checker) rx_find_function(root C.TSNode, t &estree.EsTree, id int) int {
	mut target := id
	mut seen := map[int]bool{}
	for {
		if target in seen {
			return -1
		}
		seen[target] = true
		v := c.rx_find_variable(root, t, target)
		if v < 0 {
			return -1
		}
		tree := c.scope_tree(root)
		if tree.variables[v].defs.len != 1 {
			return -1
		}
		def := tree.variables[v].defs[0]
		def_node := c.rx_es_of(t, def.node)
		if def_node >= 0 && t.typ(def_node) == .function_declaration {
			return def_node
		}
		if def.kind == .variable && def.parent_kind == 'const' && !def.node_kind_is_for_head() {
			init := c.rx_es_of(t, def.init)
			if init >= 0 {
				if t.typ(init) in [.function_expression, .arrow_function_expression] {
					return init
				}
				if t.typ(init) == .identifier {
					target = init
					continue
				}
			}
		}
		return -1
	}
	return -1
}

// rx_is_known_method_call ports isKnownMethodCall: `object.method(…)` with a non-computed name
// the map has, that many arguments and no spread, on an object that is not `super`.
fn rx_is_known_method_call(t &estree.EsTree, node int, methods map[string]int) bool {
	mem := t.node(node, .callee) or { return false }
	if t.typ(mem) != .member_expression || (t.flag(mem, .computed) or { false }) {
		return false
	}
	prop := t.node(mem, .property) or { return false }
	if t.typ(prop) != .identifier {
		return false
	}
	arg_length := methods[t.string_of(prop, .name) or { '' }] or { return false }
	args := t.list(node, .arguments) or { []int{} }
	if args.len != arg_length || args.any(t.typ(it) == .spread_element) {
		return false
	}
	object := t.node(mem, .object) or { return false }
	return t.typ(object) != .super
}

// rx_method_name is the name of the method of a known method call.
fn rx_method_name(t &estree.EsTree, call int) string {
	mem := t.node(call, .callee) or { return '' }
	prop := t.node(mem, .property) or { return '' }
	return t.string_of(prop, .name) or { '' }
}

// RxStrToken is a token of string-literal-parser: its value and its range, in UTF-16 units of the
// text it was read from.
struct RxStrToken {
	value  []u16
	start  int
	end    int
	escape bool
}

// rx_code_point_at ports String#codePointAt.
fn rx_code_point_at(s []u16, i int) ?u32 {
	if i < 0 || i >= s.len {
		return none
	}
	u := u32(s[i])
	if u >= 0xd800 && u <= 0xdbff && i + 1 < s.len && s[i + 1] >= 0xdc00 && s[i + 1] <= 0xdfff {
		return 0x10000 + ((u - 0xd800) << 10) + (u32(s[i + 1]) - 0xdc00)
	}
	return u
}

fn rx_from_code_point(cp u32) []u16 {
	mut out := []u16{}
	if cp >= 0x10000 {
		v := cp - 0x10000
		out << u16(0xd800 + (v >> 10))
		out << u16(0xdc00 + (v & 0x3ff))
	} else {
		out << u16(cp)
	}
	return out
}

// RxStrTokenizer ports the Tokenizer of string-literal-parser (ecmaVersion Infinity).
struct RxStrTokenizer {
	source []u16
	end    int
mut:
	pos int
}

// rx_parse_string_tokens ports parseTokens: the tokens of a string's body (quote 0) or of a
// literal after its opening quote (`quote` ends it); an error where the tokenizer throws.
fn (mut tk RxStrTokenizer) parse_tokens(quote u32) ![]RxStrToken {
	in_template := quote == `\``
	mut out := []RxStrToken{}
	for tk.pos < tk.end {
		start := tk.pos
		cp := rx_code_point_at(tk.source, start) or { return error('Unterminated string constant') }
		tk.pos = start + if cp >= 0x10000 { 2 } else { 1 }
		if quote != 0 && cp == quote {
			break
		}
		if cp == `\\` {
			value := tk.read_escape(in_template)!
			out << RxStrToken{
				value:  value
				start:  start
				end:    tk.pos
				escape: true
			}
		} else if cp == `\r` || cp == `\n` {
			if in_template {
				if cp == `\r` && (rx_code_point_at(tk.source, tk.pos) or { 0 }) == `\n` {
					tk.pos++
				}
				out << RxStrToken{
					value: [u16(`\n`)]
					start: start
					end:   tk.pos
				}
			} else {
				return error('Unterminated string constant')
			}
		} else {
			if (cp == 0x2028 || cp == 0x2029) && !in_template {
				return error('Unterminated string constant')
			}
			out << RxStrToken{
				value: rx_from_code_point(cp)
				start: start
				end:   tk.pos
			}
		}
	}
	return out
}

fn (mut tk RxStrTokenizer) read_escape(in_template bool) ![]u16 {
	cp := rx_code_point_at(tk.source, tk.pos) or { return error('Invalid or unexpected token') }
	tk.pos += if cp >= 0x10000 { 2 } else { 1 }
	match cp {
		`n` {
			return [u16(`\n`)]
		}
		`r` {
			return [u16(`\r`)]
		}
		`t` {
			return [u16(`\t`)]
		}
		`b` {
			return [u16(8)]
		}
		`v` {
			return [u16(11)]
		}
		`f` {
			return [u16(12)]
		}
		`\r`, `\n` {
			if cp == `\r` && (rx_code_point_at(tk.source, tk.pos) or { 0 }) == `\n` {
				tk.pos++
			}
			return []u16{}
		}
		`x` {
			return rx_from_code_point(tk.read_hex(2)!)
		}
		`u` {
			return rx_from_code_point(tk.read_unicode()!)
		}
		else {
			if cp >= `0` && cp <= `7` {
				// /^[0-7]+/ on the three units from the first digit.
				mut digits := []u8{}
				for k in tk.pos - 1 .. tk.pos + 2 {
					if k < tk.source.len && tk.source[k] >= `0` && tk.source[k] <= `7` {
						digits << u8(tk.source[k])
					} else {
						break
					}
				}
				mut octal := rx_parse_octal(digits)
				if octal > 255 {
					digits = digits[..digits.len - 1].clone()
					octal = rx_parse_octal(digits)
				}
				tk.pos += digits.len - 1
				next := rx_code_point_at(tk.source, tk.pos) or { 0 }
				if (digits.bytestr() != '0' || next == `8` || next == `9`) && in_template {
					return error('Octal literal in template string')
				}
				return rx_from_code_point(u32(octal))
			}
			return rx_from_code_point(cp)
		}
	}
}

fn rx_parse_octal(digits []u8) int {
	mut v := 0
	for d in digits {
		v = v * 8 + int(d - `0`)
	}
	return v
}

fn (mut tk RxStrTokenizer) read_unicode() !u32 {
	cp := rx_code_point_at(tk.source, tk.pos) or { 0 }
	if cp == `{` {
		tk.pos++
		mut end_index := -1
		for k in tk.pos .. tk.source.len {
			if tk.source[k] == `}` {
				end_index = k
				break
			}
		}
		if end_index < 0 {
			return error('Invalid Unicode escape sequence')
		}
		code := tk.read_hex(end_index - tk.pos)!
		tk.pos++
		if code > 0x10ffff {
			return error('Code point out of bounds')
		}
		return code
	}
	return tk.read_hex(4)
}

fn (mut tk RxStrTokenizer) read_hex(length int) !u32 {
	mut total := u64(0)
	for _ in 0 .. length {
		cp := rx_code_point_at(tk.source, tk.pos) or {
			return error('Invalid hexadecimal escape sequence')
		}
		val := if cp >= `a` {
			cp - `a` + 10
		} else if cp >= `A` {
			cp - `A` + 10
		} else if cp >= `0` && cp <= `9` {
			cp - `0`
		} else {
			return error('Invalid hexadecimal escape sequence')
		}
		if val >= 16 {
			return error('Invalid hexadecimal escape sequence')
		}
		total = total * 16 + val
		tk.pos++
	}
	return u32(if total > 0xffffffff { u64(0xffffffff) } else { total })
}

// rx_string_value_range ports getStringValueRange: the source range (bytes) of [start, end) of the
// value of a string literal, through its tokens; none when the value is shorter or the literal
// does not tokenize.
fn (c &Checker) rx_string_value_range(t &estree.EsTree, node int, start_offset int, end_offset int) ?(int, int) {
	if rx_string_value(t, node).len < end_offset {
		return none
	}
	node_start := t.nodes[node].start + 1
	raw := regexpp.to_utf16(c.src[node_start..t.nodes[node].end - 1])
	mut tk := RxStrTokenizer{
		source: raw
		end:    raw.len
	}
	tokens := tk.parse_tokens(0) or { return none }
	mut value_index := 0
	mut start := -1
	for token in tokens {
		end_index := value_index + token.value.len
		if start < 0 && value_index <= start_offset && start_offset < end_index {
			start = token.start
		}
		if start >= 0 && value_index < end_offset && end_offset <= end_index {
			return rx_bytes_after_units(c.src, node_start, start), rx_bytes_after_units(c.src,
				node_start, token.end)
		}
		value_index = end_index
	}
	return none
}

// RxReplacementKind is the `type` of a replacement element.
enum RxReplacementKind {
	character
	dollar
	reference
}

// RxReplacement is a ReplacementElement of parseReplacements: a character, `$$` `$&` `` $` `` `$'`
// (`kind`), or a reference `$1` `$<name>` (`ref_num` or `ref_name`, `ref_text`); [start, end) in
// bytes of the source.
struct RxReplacement {
	kind       RxReplacementKind
	value      []u16
	dollar     string
	ref_num    int
	ref_name   string
	ref_is_num bool
	ref_text   string
	start      int
	end        int
}

// rx_base_parse_replacements ports baseParseReplacements on tokens (their value and range).
fn rx_base_parse_replacements(chars []RxStrToken) []RxReplacement {
	mut elements := []RxReplacement{}
	mut index := 0
	for index < chars.len {
		token := chars[index]
		index++
		if regexpp.utf16_to_wtf8(token.value) == '$' && index < chars.len {
			next := chars[index]
			index++
			nv := regexpp.utf16_to_wtf8(next.value)
			if nv in ['$', '&', '`', "'"] {
				elements << RxReplacement{
					kind:   .dollar
					dollar: nv
					start:  token.start
					end:    next.end
				}
				continue
			}
			// parseNumberRef
			if nv.len == 1 && nv[0].is_digit() {
				if nv == '0' {
					if index < chars.len {
						after := chars[index]
						index++
						av := regexpp.utf16_to_wtf8(after.value)
						if av.len == 1 && av[0] >= `1` && av[0] <= `9` {
							elements << RxReplacement{
								kind:       .reference
								ref_num:    av.int()
								ref_is_num: true
								ref_text:   nv + av
								start:      token.start
								end:        after.end
							}
							continue
						}
						index--
					}
				} else {
					elements << RxReplacement{
						kind:       .reference
						ref_num:    nv.int()
						ref_is_num: true
						ref_text:   nv
						start:      token.start
						end:        next.end
					}
					continue
				}
			}
			// parseNamedRef
			if nv == '<' {
				start_index := index
				mut found := false
				for index < chars.len {
					tok := chars[index]
					index++
					if regexpp.utf16_to_wtf8(tok.value) == '>' {
						mut name := []u16{}
						for k in start_index .. index - 1 {
							name << chars[k].value
						}
						ref := regexpp.utf16_to_wtf8(name)
						elements << RxReplacement{
							kind:     .reference
							ref_name: ref
							ref_text: ref
							start:    token.start
							end:      tok.end
						}
						found = true
						break
					}
				}
				if found {
					continue
				}
				index = start_index
			}
			index--
		}
		elements << RxReplacement{
			kind:  .character
			value: token.value
			start: token.start
			end:   token.end
		}
	}
	return elements
}

// rx_parse_replacements ports parseReplacements of a string literal: its tokens (the empty ones
// left out) read as a replacement string, each element with its range in the source.
fn (c &Checker) rx_parse_replacements(t &estree.EsTree, node int) []RxReplacement {
	start := t.nodes[node].start
	end := t.nodes[node].end
	text := regexpp.to_utf16(c.src[start..end])
	quote := rx_code_point_at(text, 0) or { return [] }
	mut tk := RxStrTokenizer{
		source: text
		end:    text.len
		pos:    1
	}
	tokens := tk.parse_tokens(quote) or { return [] }
	mut chars := []RxStrToken{}
	for token in tokens {
		if token.value.len > 0 {
			chars << RxStrToken{
				...token
				start: rx_bytes_after_units(c.src, start, token.start)
				end:   rx_bytes_after_units(c.src, start, token.end)
			}
		}
	}
	return rx_base_parse_replacements(chars)
}

// rx_regexp_node_from_expression ports getRegExpNodeFromExpression: the pattern of a regular
// expression literal, or of a static RegExp value; none when it does not parse.
fn (mut c Checker) rx_regexp_node_from_expression(root C.TSNode, t &estree.EsTree, node int) ?regexpp.Ast {
	if t.typ(node) == .literal {
		regex := t.prop(node, .regex)?
		pattern := regexpp.to_utf16(regex.str)
		return regexpp.parse_pattern(pattern, 0, pattern.len, regexpp.PatternFlags{
			unicode:      regex.str2.contains('u')
			unicode_sets: regex.str2.contains('v')
		}, regexpp.Options{}) or { return none }
	}
	evaluated := c.rx_static_value(root, t, node)
	if !evaluated.found || evaluated.value.kind != .regexp_ {
		return none
	}
	// parseRegExpLiteral(regexp): the literal `/source/flags`.
	mut literal := [u16(`/`)]
	literal << evaluated.value.regexp.source
	literal << u16(`/`)
	literal << regexpp.to_utf16(evaluated.value.regexp.flags)
	ast := regexpp.parse_literal(literal, 0, literal.len, regexpp.Options{}) or { return none }
	return ast
}

// RxRefKind is the `type` of an ExpressionReference.
enum RxRefKind {
	unused
	unknown
	exported
	member
	destructuring
	argument
	call
	iteration
}

// RxExpressionRef is an ExpressionReference: `node` the expression, `other` its member expression,
// destructuring pattern, call or for-of statement.
struct RxExpressionRef {
	kind  RxRefKind
	node  int
	other int = -1
}

struct RxAlreadyChecked {
mut:
	variables map[int]bool
	functions map[int][]int
}

// rx_expression_references ports extractExpressionReferences, all of them in order.
fn (mut c Checker) rx_expression_references(root C.TSNode, t &estree.EsTree, node int) []RxExpressionRef {
	mut checked := RxAlreadyChecked{}
	mut out := []RxExpressionRef{}
	c.rx_references_for_expression(root, t, node, mut checked, mut out)
	return out
}

// rx_expression_references_for_variable ports extractExpressionReferencesForVariable.
fn (mut c Checker) rx_expression_references_for_variable(root C.TSNode, t &estree.EsTree, node int) []RxExpressionRef {
	mut checked := RxAlreadyChecked{}
	mut out := []RxExpressionRef{}
	c.rx_references_for_variable(root, t, node, mut checked, mut out)
	return out
}

fn (mut c Checker) rx_references_for_expression(root C.TSNode, t &estree.EsTree, expression int, mut checked RxAlreadyChecked, mut out []RxExpressionRef) {
	mut node := expression
	mut parent := rx_parent(t, node)
	for parent >= 0 && t.typ(parent) in [.chain_expression, .ts_non_null_expression, .ts_as_expression] {
		node = parent
		parent = rx_parent(t, node)
	}
	if parent < 0 || t.typ(parent) == .expression_statement {
		out << RxExpressionRef{
			kind: .unused
			node: node
		}
		return
	}
	match t.typ(parent) {
		.member_expression {
			if (t.node(parent, .object) or { -1 }) == node {
				out << RxExpressionRef{
					kind:  .member
					node:  node
					other: parent
				}
			} else {
				out << RxExpressionRef{
					kind: .unknown
					node: node
				}
			}
		}
		.assignment_expression {
			if (t.node(parent, .right) or { -1 }) == node
				&& (t.string_of(parent, .operator) or { '' }) == '=' {
				c.rx_references_for_pattern(root, t, node, t.node(parent, .left) or { -1 }, mut
					checked, mut out)
			} else {
				out << RxExpressionRef{
					kind: .unknown
					node: node
				}
			}
		}
		.variable_declarator {
			if (t.node(parent, .init) or { -1 }) == node {
				pp := rx_parent(t, rx_parent(t, parent))
				if pp >= 0 && t.typ(pp) == .export_named_declaration {
					out << RxExpressionRef{
						kind: .exported
						node: node
					}
				}
				c.rx_references_for_pattern(root, t, node, t.node(parent, .id) or { -1 }, mut
					checked, mut out)
			} else {
				out << RxExpressionRef{
					kind: .unknown
					node: node
				}
			}
		}
		.call_expression {
			args := t.list(parent, .arguments) or { []int{} }
			arg_index := args.index(node)
			if arg_index > -1 {
				callee := t.node(parent, .callee) or { -1 }
				if callee >= 0 && t.typ(callee) == .identifier {
					f := c.rx_find_function(root, t, callee)
					if f >= 0 {
						c.rx_references_for_function_argument(root, t, node, f, arg_index, mut
							checked, mut out)
						return
					}
				}
				out << RxExpressionRef{
					kind:  .argument
					node:  node
					other: parent
				}
			} else {
				out << RxExpressionRef{
					kind: .call
					node: node
				}
			}
		}
		.export_specifier, .export_default_declaration {
			out << RxExpressionRef{
				kind: .exported
				node: node
			}
		}
		.for_of_statement {
			if (t.node(parent, .right) or { -1 }) == node {
				out << RxExpressionRef{
					kind:  .iteration
					node:  node
					other: parent
				}
			} else {
				out << RxExpressionRef{
					kind: .unknown
					node: node
				}
			}
		}
		.if_statement, .conditional_expression, .logical_expression, .unary_expression {
			if !rx_is_used_in_test(t, parent, node) {
				out << RxExpressionRef{
					kind: .unknown
					node: node
				}
			}
		}
		else {
			out << RxExpressionRef{
				kind: .unknown
				node: node
			}
		}
	}
}

// rx_is_used_in_test ports isUsedInTest.
fn rx_is_used_in_test(t &estree.EsTree, parent int, node int) bool {
	return match t.typ(parent) {
		.if_statement, .conditional_expression {
			(t.node(parent, .test) or { -1 }) == node
		}
		.logical_expression {
			(t.string_of(parent, .operator) or { '' }) == '&&'
				&& (t.node(parent, .left) or { -1 }) == node
		}
		.unary_expression {
			(t.string_of(parent, .operator) or { '' }) == '!'
				&& (t.node(parent, .argument) or { -1 }) == node
		}
		else {
			false
		}
	}
}

fn (mut c Checker) rx_references_for_pattern(root C.TSNode, t &estree.EsTree, expression int, pattern int, mut checked RxAlreadyChecked, mut out []RxExpressionRef) {
	mut target := pattern
	for target >= 0 && t.typ(target) == .assignment_pattern {
		target = t.node(target, .left) or { -1 }
	}
	if target >= 0 && t.typ(target) == .identifier {
		c.rx_references_for_variable(root, t, target, mut checked, mut out)
	} else if target >= 0 && t.typ(target) in [.object_pattern, .array_pattern] {
		out << RxExpressionRef{
			kind:  .destructuring
			node:  expression
			other: target
		}
	} else {
		out << RxExpressionRef{
			kind: .unknown
			node: expression
		}
	}
}

fn (mut c Checker) rx_references_for_variable(root C.TSNode, t &estree.EsTree, identifier int, mut checked RxAlreadyChecked, mut out []RxExpressionRef) {
	v := c.rx_find_variable(root, t, identifier)
	if v < 0 {
		out << RxExpressionRef{
			kind: .unknown
			node: identifier
		}
		return
	}
	if v in checked.variables {
		return
	}
	checked.variables[v] = true
	tree := c.scope_tree(root)
	if tree.variables[v].eslint_used {
		out << RxExpressionRef{
			kind: .exported
			node: identifier
		}
	}
	read_references := tree.variables[v].references.filter(tree.references[it].read)
	if read_references.len == 0 {
		out << RxExpressionRef{
			kind: .unused
			node: identifier
		}
		return
	}
	for r in read_references {
		ident := c.rx_es_of(t, tree.references[r].identifier)
		if ident < 0 || t.typ(ident) == .jsx_identifier {
			continue
		}
		c.rx_references_for_expression(root, t, ident, mut checked, mut out)
	}
}

fn (mut c Checker) rx_references_for_function_argument(root C.TSNode, t &estree.EsTree, expression int, f int, arg_index int, mut checked RxAlreadyChecked, mut out []RxExpressionRef) {
	mut already := checked.functions[f] or { []int{} }
	if arg_index in already {
		return
	}
	already << arg_index
	checked.functions[f] = already
	params := t.list(f, .params) or { []int{} }
	head := if params.len > arg_index + 1 { params[..arg_index + 1] } else { params }
	if arg_index >= params.len || head.any(it >= 0 && t.typ(it) == .rest_element) {
		out << RxExpressionRef{
			kind: .unknown
			node: expression
		}
		return
	}
	c.rx_references_for_pattern(root, t, expression, params[arg_index], mut checked, mut
		out)
}

// RxUsage is UsageOfPattern.
enum RxUsage {
	partial
	whole
	mixed
	unknown
}

// rx_usage_of_pattern ports getUsageOfPattern: how the regular expression is used.
fn (mut c Checker) rx_usage_of_pattern(root C.TSNode, t &estree.EsTree, node int) RxUsage {
	mut partial := false
	mut whole := false
	for ref in c.rx_expression_references(root, t, node) {
		match ref.kind {
			.member {
				name := if !(t.flag(ref.other, .computed) or { false }) {
					t.string_of(t.node(ref.other, .property) or { -1 }, .name) or { '' }
				} else {
					c.rx_string_if_constant(root, t, t.node(ref.other, .property) or { -1 }) or {
						'\x00'
					}
				}
				match rx_usage_of_prop_name(name) {
					.partial { partial = true }
					.whole { whole = true }
					.unknown { return .unknown }
					else {}
				}
			}
			.destructuring {
				if t.typ(ref.other) == .object_pattern {
					for prop in t.list(ref.other, .properties) or { []int{} } {
						if t.typ(prop) == .rest_element {
							continue
						}
						key := t.node(prop, .key) or { -1 }
						name := if !(t.flag(prop, .computed) or { false }) {
							if t.typ(key) == .identifier {
								t.string_of(key, .name) or { '' }
							} else {
								es_tree_static_string_value(t, key) or { '' }
							}
						} else {
							c.rx_string_if_constant(root, t, key) or { '\x00' }
						}
						match rx_usage_of_prop_name(name) {
							.partial { partial = true }
							.whole { whole = true }
							else {}
						}
					}
				}
			}
			.unused {}
			.argument {
				call := ref.other
				args := t.list(call, .arguments) or { []int{} }
				callee := t.node(call, .callee) or { -1 }
				if args.len > 0 && args[0] == ref.node && callee >= 0
					&& t.typ(callee) == .member_expression {
					prop_name := if !(t.flag(callee, .computed) or { false }) {
						t.string_of(t.node(callee, .property) or { -1 }, .name) or { '' }
					} else {
						c.rx_string_if_constant(root, t, t.node(callee, .property) or { -1 }) or {
							'\x00'
						}
					}
					if prop_name in ['match', 'matchAll', 'split', 'replace', 'replaceAll', 'search'] {
						whole = true
					} else {
						return .unknown
					}
				} else {
					return .unknown
				}
			}
			else {
				return .unknown
			}
		}
	}
	if partial {
		return if whole { .mixed } else { .partial }
	}
	return if whole { .whole } else { .unknown }
}

// rx_usage_of_prop_name ports iterateUsageOfPatternForPropName: `.source` is partial, the flags
// (and compile) nothing (mixed here), anything else whole.
fn rx_usage_of_prop_name(name string) RxUsage {
	if name == 'source' {
		return .partial
	}
	if name in ['compile', 'dotAll', 'flags', 'global', 'ignoreCase', 'multiline', 'sticky', 'unicode'] {
		return .mixed
	}
	return .whole
}
