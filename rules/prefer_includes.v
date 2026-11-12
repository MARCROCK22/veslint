module rules

import time
import tsgo { handle_index, handle_kind, handle_path }
import treesitter { node_end, node_field, node_kind, node_start, nodes_of_kind, position_of }
import offsets { utf16_offsets }

// Port of the `prefer-includes` rule of typescript-eslint 8.62.0, with its fixes.
//
// For a regular expression with a surrogate that has no pair (`/\ud800/.test(text)`), the text
// of the fix has U+FFFD in its place: that is how Node writes such a string in UTF-8, so it is
// what `eslint --fix` leaves in the file.

const pinc_messages = {
	'preferIncludes':       "Use 'includes()' method instead."
	'preferStringIncludes': 'Use `String#includes()` method with a string instead.'
}

// SyntaxKinds of ts.isFunctionLike (TypeScript 7.1.0-beta): MethodSignature, MethodDeclaration,
// Constructor, GetAccessor, SetAccessor, CallSignature, ConstructSignature, IndexSignature,
// FunctionType, ConstructorType, FunctionExpression, ArrowFunction and FunctionDeclaration.
const pinc_function_like_kinds = [u32(175), 176, 178, 179, 180, 181, 182, 183, 186, 187, 220, 221,
	264]

// PincIndexOf is a `x.indexOf(y)` compared like `includes`, pending the declarations of `indexOf`.
struct PincIndexOf {
	compare  C.TSNode
	call     C.TSNode
	property C.TSNode
	negative bool // isNegativeCheck: the comparison means "not included"
	fixable  bool // allowFixing: the call is not an optional chain
}

// PincTest is a `/re/.test(x)` call whose regular expression is a plain string.
struct PincTest {
	call     C.TSNode
	argument C.TSNode // without parentheses
	text     string   // the string the regular expression matches
	optional bool     // `/re/?.test(x)`
}

fn (mut c Checker) lint_prefer_includes(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut index_ofs := []PincIndexOf{}
	mut tests := []PincTest{}
	mut spans := []Span{}
	for call in c.nodes_of_kind(root, c'call_expression') {
		args := call_arguments(call) or { continue }
		callee := unwrap_parens(node_field(call, 'function') or { continue })
		// 'BinaryExpression > CallExpression.left > MemberExpression' and the same with a
		// ChainExpression around the call: the member is the callee or an argument.
		if compare := pinc_compare_of(call) {
			mut members := [callee]
			members << args.map(unwrap_parens(it))
			for member in members {
				if is_member(member) && !is_estree_chain_root(member) {
					if found := c.pinc_index_of(call, member, compare) {
						index_ofs << found
					}
				}
			}
		}
		// 'CallExpression[arguments.length=1] > MemberExpression.callee[property.name="test"]
		// [computed=false]'
		if args.len == 1 && node_kind(callee) == 'member_expression' && !is_estree_chain_root(callee) {
			property := node_field(callee, 'property') or { continue }
			if node_kind(property) != 'property_identifier' || c.identifier_name(property) != 'test' {
				continue
			}
			text := c.pinc_regexp_text(node_field(callee, 'object') or { continue }) or { continue }
			tests << PincTest{
				call:     call
				argument: unwrap_parens(args[0])
				text:     text
				optional: is_optional_element(callee)
			}
			spans << node_span(unwrap_parens(args[0]))
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	if index_ofs.len > 0 {
		symbols := c.client.symbols_at(c.snapshot, c.project, abs_path, utf16_offsets(c.src,
			index_ofs.map(node_start(it.property))))!
		if symbols.len != index_ofs.len {
			return error('protocol: tsgo returned ${symbols.len} symbols for ${index_ofs.len} positions')
		}
		for i, found in index_ofs {
			if c.pinc_has_includes(symbols[i].declarations)! {
				finding := Finding{
					stmt:       position_of(found.compare)
					message_id: 'preferIncludes'
				}
				findings << if found.fixable {
					c.with_fixes(finding, pinc_index_of_fixes(found))!
				} else {
					finding
				}
			}
		}
	}
	for test in tests {
		t := c.node_type(test.argument) or { continue }
		includes := c.property(c.constrained(t)!, 'includes')!
		if !includes.is_null() {
			findings << c.with_fixes(Finding{
				stmt:       position_of(test.call)
				message_id: 'preferStringIncludes'
			}, pinc_test_fixes(test))!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += index_ofs.len + tests.len
	return findings
}

// pinc_compare_of is the BinaryExpression whose `left` is the call (directly or through the
// ChainExpression of an optional chain).
fn pinc_compare_of(call C.TSNode) ?C.TSNode {
	compare := estree_parent(call)?
	if estree_binary_kind(compare) != 'BinaryExpression' {
		return none
	}
	left := unwrap_parens(node_field(compare, 'left')?)
	if node_key(left) != node_key(call) || node_kind(left) != node_kind(call) {
		return none
	}
	return compare
}

// pinc_index_of ports checkArrayIndexOf up to the symbol lookup: a static `indexOf` member and a
// comparison equivalent to `includes()`.
fn (mut c Checker) pinc_index_of(call C.TSNode, member C.TSNode, compare C.TSNode) ?PincIndexOf {
	if !c.is_static_member_access_of_value(member, ['indexOf']) {
		return none
	}
	right := node_field(compare, 'right')?
	operator := operator_of(compare)
	expected := match operator {
		'!==', '!=', '>', '===', '==', '<=' { -1.0 }
		'>=', '<' { 0.0 }
		else { return none }
	}
	value := c.get_static_value(right)
	if !value.found || value.value.kind != .number_ || value.value.number != expected {
		return none
	}
	return PincIndexOf{
		compare:  compare
		call:     call
		property: member_property(member)?
		negative: operator in ['===', '==', '<=', '<']
		fixable:  !(is_chain_element(call) && is_estree_chain_root(call))
	}
}

// pinc_index_of_fixes ports the fixer of checkArrayIndexOf: `!` before the call if the check is
// negative, the property becomes `includes` and the comparison after the call goes.
fn pinc_index_of_fixes(found PincIndexOf) []Fix {
	mut fixes := []Fix{}
	if found.negative {
		fixes << fix_insert_before(found.call, '!')
	}
	fixes << fix_replace(found.property, 'includes')
	fixes << fix_remove_range(node_end(found.call), node_end(found.compare))
	return fixes
}

// pinc_test_fixes ports the fixer of `/re/.test(x)`: only the argument stays, in parentheses
// unless it is a Literal, a TemplateLiteral, an Identifier, a MemberExpression or a
// CallExpression, followed by `.includes('text')`.
fn pinc_test_fixes(test PincTest) []Fix {
	includes := "${if test.optional { '?.' } else { '.' }}includes('${pinc_escape_string(test.text)}')"
	needs_paren := pinc_needs_paren(test.argument)
	mut fixes := [
		fix_remove_range(node_start(test.call), node_start(test.argument)),
		fix_remove_range(node_end(test.argument), node_end(test.call)),
	]
	if needs_paren {
		fixes << fix_insert_before(test.argument, '(')
	}
	// One insertion after the argument: the `)` and then the call, in the order the original
	// yields them.
	fixes << fix_insert_after(test.argument, if needs_paren { ')' + includes } else { includes })
	return fixes
}

// pinc_needs_paren: the ESTree type of the argument is not one of the five that need no
// parentheses (an optional chain is a ChainExpression, a tagged template and `import()` are not
// CallExpressions).
fn pinc_needs_paren(argument C.TSNode) bool {
	e := es_child(argument)
	if e.chain {
		return true
	}
	return match node_kind(e.node) {
		'string', 'number', 'true', 'false', 'null', 'regex', 'template_string', 'identifier',
		'undefined', 'member_expression', 'subscript_expression' {
			false
		}
		'call_expression' {
			precedence_is_tagged_template(e.node) || precedence_is_import_call(e.node)
		}
		else {
			true
		}
	}
}

// pinc_escape_string ports escapeString: the text inside a single-quoted string.
fn pinc_escape_string(text string) string {
	mut out := []u8{cap: text.len}
	for b in text.bytes() {
		match b {
			0 { out << '\\0'.bytes() }
			`\t` { out << '\\t'.bytes() }
			`\n` { out << '\\n'.bytes() }
			`\v` { out << '\\v'.bytes() }
			`\f` { out << '\\f'.bytes() }
			`\r` { out << '\\r'.bytes() }
			`'` { out << "\\'".bytes() }
			`\\` { out << '\\\\'.bytes() }
			else { out << b }
		}
	}
	return out.bytestr()
}

// pinc_has_includes ports the declaration check of checkArrayIndexOf: every declaration of
// `indexOf` belongs to a type with an `includes` method with the same parameters.
fn (mut c Checker) pinc_has_includes(declarations []string) !bool {
	if declarations.len == 0 {
		return false
	}
	mut handles := []string{}
	for declaration in declarations {
		tree := c.declaration_ast(handle_path(declaration))!
		handles << tree.node_handle(tree.node_parent(handle_index(declaration)))
	}
	types := c.client.types_at_locations(c.snapshot, c.project, handles)!
	if types.len != handles.len {
		return error('protocol: tsgo returned ${types.len} types for ${handles.len} nodes')
	}
	for i, declaration in declarations {
		if types[i].is_null() {
			return false
		}
		includes := c.property(types[i], 'includes')!
		mut same := false
		for candidate in includes.declarations {
			if c.pinc_same_parameters(candidate, declaration)! {
				same = true
				break
			}
		}
		if !same {
			return false
		}
	}
	return true
}

// pinc_same_parameters ports hasSameParameters: two function-like declarations whose parameters
// have the same text.
fn (mut c Checker) pinc_same_parameters(a string, b string) !bool {
	if handle_kind(a) !in pinc_function_like_kinds || handle_kind(b) !in pinc_function_like_kinds {
		return false
	}
	params_a := c.pinc_parameter_texts(a)!
	params_b := c.pinc_parameter_texts(b)!
	return params_a == params_b
}

fn (mut c Checker) pinc_parameter_texts(declaration string) ![]string {
	tree := c.declaration_ast(handle_path(declaration))!
	list := tree.node_child(handle_index(declaration), 'parameters')
	if list == 0 {
		return []string{}
	}
	return tree.node_children(list).map(tree.node_source_text(it))
}

// pinc_regexp_text ports parseRegExp: the string a static RegExp without `i` nor `g` matches,
// when its single alternative is made of characters only.
fn (mut c Checker) pinc_regexp_text(n C.TSNode) ?string {
	value := c.get_static_value(n)
	if !value.found || value.value.kind != .regexp_ {
		return none
	}
	re := value.value.regexp
	if re.flags.contains('i') || re.flags.contains('g') {
		return none
	}
	pattern := regexp_parse(re.source, regexp_mode(re.flags))
	if !pattern.valid || pattern.alternatives.len != 1 {
		return none
	}
	// String.fromCodePoint of the characters: UTF-16 units outside the `u` and `v` modes, where a
	// surrogate pair makes one character.
	mut units := []u16{}
	for element in pattern.alternatives[0] {
		if element.kind != .character {
			return none
		}
		if element.value > 0xffff {
			v := element.value - 0x10000
			units << u16(0xd800 + (v >> 10))
			units << u16(0xdc00 + (v & 0x3ff))
		} else {
			units << u16(element.value)
		}
	}
	return stv_units_string(units)
}
