module rules

import json2
import jsregexp
import time
import treesitter { Ident, node_end, node_field, node_kind, node_parent, node_start, nodes_of_kinds, position_of }
import offsets { utf16_offsets }
import tsgo { SymbolResponse, TypeResponse, handle_index, handle_path }

// Port of the `dot-notation` rule of typescript-eslint 8.62.0, which extends the ESLint 10.6.0
// core rule of the same name, with its options and its fixes.

const dotn_messages = {
	'useDot':      '[{{key}}] is better written in dot notation.'
	'useBrackets': '.{{key}} is a syntax error.'
}

// ES3 keywords of the core rule (eslint/lib/rules/utils/keywords.js).
const dotn_keywords = ['abstract', 'boolean', 'break', 'byte', 'case', 'catch', 'char', 'class',
	'const', 'continue', 'debugger', 'default', 'delete', 'do', 'double', 'else', 'enum', 'export',
	'extends', 'false', 'final', 'finally', 'float', 'for', 'function', 'goto', 'if', 'implements',
	'import', 'in', 'instanceof', 'int', 'interface', 'long', 'native', 'new', 'null', 'package',
	'private', 'protected', 'public', 'return', 'short', 'static', 'super', 'switch', 'synchronized',
	'this', 'throw', 'throws', 'transient', 'true', 'try', 'typeof', 'var', 'void', 'volatile',
	'while', 'with']

struct DotnOptions {
	allow_keywords                        bool
	allow_index_signature_property_access bool
	allow_private_class_property_access   bool
	allow_protected_class_property_access bool
	has_pattern                           bool
	pattern                               jsregexp.RegexpProgram // allowPattern
}

// dotn_options reads the options of typescript-eslint's rule, or of the core rule (`core`), which
// has only allowKeywords and allowPattern.
fn dotn_options(options []json2.Any, core bool) !DotnOptions {
	rule := if core { core_dot_notation } else { dot_notation }
	keys := if core {
		['allowKeywords', 'allowPattern']
	} else {
		['allowIndexSignaturePropertyAccess', 'allowKeywords', 'allowPattern',
			'allowPrivateClassPropertyAccess', 'allowProtectedClassPropertyAccess']
	}
	o := option_object(rule, options, keys)!
	// `new RegExp(allowPattern, 'u')`, when the option is not empty.
	mut has_pattern := false
	mut allow_pattern := jsregexp.RegexpProgram{}
	if pattern := o.values['allowPattern'] {
		if pattern !is string {
			return error('option `allowPattern` of `${rule}` must be a string')
		}
		if (pattern as string) != '' {
			allow_pattern = jsregexp.regexp_compile(pattern as string) or {
				return error('option `allowPattern` of `${rule}`: ${err.msg()}')
			}
			has_pattern = true
		}
	}
	return DotnOptions{
		has_pattern:                           has_pattern
		pattern:                               allow_pattern
		allow_keywords:                        o.bool_value('allowKeywords')!
		allow_index_signature_property_access: !core
			&& o.bool_value('allowIndexSignaturePropertyAccess')!
		allow_private_class_property_access:   !core && o.bool_value('allowPrivateClassPropertyAccess')!
		allow_protected_class_property_access: !core
			&& o.bool_value('allowProtectedClassPropertyAccess')!
	}
}

// DotnComputed is a `x['name']` the core rule reports, pending the type checks of the options.
struct DotnComputed {
	member   C.TSNode
	property C.TSNode // ESTree property: the literal or template, without parentheses
	value    string   // its value as a string (`true`, `null` for those literals)
	string   bool     // a string Literal (not a template, boolean or null)
	report   Ident
	key      string
}

fn (mut c Checker) lint_dot_notation(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	o := dotn_options(c.rule_options(dot_notation), false)!
	return c.dotn_lint(root, abs_path, o, true, mut stats)!
}

// lint_core_dot_notation is the `dot-notation` rule of ESLint 10.6.0: typescript-eslint's without
// the options and the checks that need types.
fn (mut c Checker) lint_core_dot_notation(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	o := dotn_options(c.rule_options(core_dot_notation), true)!
	return c.dotn_lint(root, abs_path, o, false, mut stats)!
}

fn (mut c Checker) dotn_lint(root C.TSNode, abs_path string, o DotnOptions, typed bool, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	index_access := typed && (o.allow_index_signature_property_access
		|| c.no_property_access_from_index_signature)
	mut findings := []Finding{}
	mut computed := []DotnComputed{}
	for member in c.nodes_of_kinds(root, member_kinds, type_name_kinds) {
		if node_kind(member) == 'member_expression' {
			if o.allow_keywords || dotn_in_type_query(member) {
				continue
			}
			property := node_field(member, 'property') or { continue }
			if node_kind(property) != 'property_identifier' {
				continue
			}
			name := c.identifier_name(property)
			if name in dotn_keywords {
				findings << c.with_fixes(Finding{
					stmt:       position_of(property)
					message_id: 'useBrackets'
					data:       {
						'key': name
					}
				}, c.dotn_use_brackets_fixes(member, property, name))!
			}
			continue
		}
		property := member_property(member) or { continue }
		mut value := ''
		mut key := ''
		mut is_string := false
		match node_kind(property) {
			'string' {
				value = c.literal_string_value(property) or { continue }
				key = '"${value}"'
				is_string = true
			}
			'true', 'false', 'null' {
				value = node_kind(property)
				key = value
			}
			'template_string' {
				value = c.literal_name(property) or { continue }
				key = '`${value}`'
			}
			else {
				continue
			}
		}
		if !dotn_valid_identifier(value) || (!o.allow_keywords && value in dotn_keywords) {
			continue
		}
		if o.has_pattern {
			allowed := jsregexp.regexp_test(o.pattern, value) or {
				return error('option `allowPattern` of `${dot_notation}`: ${err.msg()}')
			}
			if allowed {
				continue
			}
		}
		computed << DotnComputed{
			member:   member
			property: property
			value:    value
			string:   is_string
			report:   position_of(property)
			key:      key
		}
	}
	mut allowed := map[int]bool{}
	if (index_access || o.allow_private_class_property_access
		|| o.allow_protected_class_property_access) && computed.len > 0 {
		allowed = c.dotn_type_exemptions(computed, o, index_access, abs_path, mut stats)!
	}
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	for i, access in computed {
		if i in allowed {
			continue
		}
		findings << c.with_fixes(Finding{
			stmt:       access.report
			message_id: 'useDot'
			data:       {
				'key': access.key
			}
		}, c.dotn_use_dot_fixes(access))!
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += computed.len
	return findings
}

// dotn_type_exemptions gives the indexes of the accesses the type part of the typescript-eslint
// rule exempts. The property symbol is getSymbolAtLocation of the key or else the property of the
// non-nullable type of the object named like a string key: with allowPrivateClassPropertyAccess
// or allowProtectedClassPropertyAccess, the first modifier of its first declaration decides; with
// allowIndexSignaturePropertyAccess (or the compiler option noPropertyAccessFromIndexSignature),
// an access without a property symbol is exempt if the type has a string index signature.
fn (mut c Checker) dotn_type_exemptions(computed []DotnComputed, o DotnOptions, index_access bool, abs_path string, mut stats Stats) !map[int]bool {
	mut spans := []Span{}
	for access in computed {
		object := node_field(access.member, 'object') or { continue }
		spans << node_span(unwrap_parens(object))
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	symbols := c.client.symbols_at(c.snapshot, c.project, abs_path, utf16_offsets(c.src,
		computed.map(node_start(it.property))))!
	if symbols.len != computed.len {
		return error('protocol: tsgo returned ${symbols.len} symbols for ${computed.len} positions')
	}
	mut allowed := map[int]bool{}
	for i, access in computed {
		mut symbol := symbols[i]
		mut object_type := TypeResponse{}
		if symbol.is_null() {
			object := node_field(access.member, 'object') or { continue }
			t := c.node_type(unwrap_parens(object)) or { continue }
			object_type = c.client.non_nullable_type(c.snapshot, c.project, t.id)!
			if !object_type.is_null() && access.string {
				for prop in c.properties(object_type)! {
					if prop.name == access.value {
						symbol = prop
						break
					}
				}
			}
		}
		if o.allow_private_class_property_access || o.allow_protected_class_property_access {
			modifier := c.dotn_first_modifier(symbol)!
			if (o.allow_private_class_property_access && modifier == syntax_kind_private_keyword)
				|| (o.allow_protected_class_property_access
					&& modifier == syntax_kind_protected_keyword) {
				allowed[i] = true
				continue
			}
		}
		if !symbol.is_null() || !index_access || object_type.is_null() {
			continue
		}
		for info in c.index_infos(object_type.id)! {
			if info.key_type.flags & type_flag_string_like != 0 {
				allowed[i] = true
				break
			}
		}
	}
	return allowed
}

// dotn_first_modifier ports `getModifiers(symbol.getDeclarations()[0])?.[0].kind`: the SyntaxKind
// of the first modifier (decorators are not modifiers) of the first declaration, or 0.
fn (mut c Checker) dotn_first_modifier(symbol SymbolResponse) !u32 {
	if symbol.declarations.len == 0 {
		return 0
	}
	declaration := symbol.declarations[0]
	tree := c.declaration_ast(handle_path(declaration))!
	modifiers := tree.node_child(handle_index(declaration), 'modifiers')
	if modifiers == 0 {
		return 0
	}
	for modifier in tree.node_children(modifiers) {
		kind := tree.node_kind(modifier)
		if kind != syntax_kind_decorator {
			return kind
		}
	}
	return 0
}

// dotn_valid_identifier is the core rule's /^[a-zA-Z_$][\w$]*$/u.
fn dotn_valid_identifier(value string) bool {
	if value == '' {
		return false
	}
	for i, ch in value {
		ok := (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || ch == `_` || ch == `$`
			|| (i > 0 && ch >= `0` && ch <= `9`)
		if !ok {
			return false
		}
	}
	return true
}

// dotn_in_type_query: a `typeof a.b` name, which ESTree has as a TSQualifiedName (or the qualifier
// of a TSImportType), not a MemberExpression.
fn dotn_in_type_query(member C.TSNode) bool {
	mut node := member
	for depth := 0; depth < max_expression_depth; depth++ {
		parent := node_parent(node) or { return false }
		match node_kind(parent) {
			'type_query' { return true }
			'member_expression' { node = parent }
			else { return false }
		}
	}
	return false
}

// dotn_use_dot_fixes ports the fixer of `useDot`: a `.` before the `[` (not after `?.`; ` .` after
// a decimal integer), the brackets and their content replaced by the name, and a space after it
// when the next token would join it. No fix with a comment inside the brackets.
fn (mut c Checker) dotn_use_dot_fixes(access DotnComputed) []Fix {
	member := access.member
	object := unwrap_parens(node_field(member, 'object') or { return []Fix{} })
	left_bracket := c.source_token_after(object, '[') or { return []Fix{} }
	right_bracket := c.last_token(member) or { return []Fix{} }
	tokens := c.source_tokens(member)
	if tokens.comments_exist_between(left_bracket.end, right_bracket.start) {
		return []Fix{}
	}
	mut fixes := []Fix{}
	if !is_optional_element(member) {
		fixes << fix_insert_at(left_bracket.start, if c.dotn_is_decimal_integer(object) {
			' .'
		} else {
			'.'
		})
	}
	fixes << fix_replace_range(left_bracket.start, right_bracket.end, access.value)
	if next := tokens.after(node_end(member), false) {
		if next.start == right_bracket.end && !c.dotn_can_follow_name(next) {
			fixes << fix_insert_at(right_bracket.end, ' ')
		}
	}
	return fixes
}

// dotn_is_decimal_integer ports astUtils.isDecimalInteger: a number literal (not a BigInt)
// written like /^(?:0|0[0-7]*[89]\d*|[1-9](?:_?\d)*)$/u, after which a `.` would be a decimal
// point.
fn (c &Checker) dotn_is_decimal_integer(n C.TSNode) bool {
	if node_kind(n) != 'number' {
		return false
	}
	t := c.text(n)
	if t == '0' {
		return true
	}
	if t == '' || !t[0].is_digit() {
		return false
	}
	mut i := 1
	if t[0] == `0` {
		for i < t.len && t[i] >= `0` && t[i] <= `7` {
			i++
		}
		if i >= t.len || t[i] !in [u8(`8`), `9`] {
			return false
		}
		return t[i..].bytes().all(it.is_digit())
	}
	for i < t.len {
		if t[i] == `_` {
			i++
		}
		if i >= t.len || !t[i].is_digit() {
			return false
		}
		i++
	}
	return true
}

// dotn_can_follow_name ports astUtils.canTokensBeAdjacent(name, token) for a name on the left: a
// punctuator, a string, a template, a number that starts with `.` or a private name can follow it
// without a space; another word, a number or a regular expression cannot.
fn (c &Checker) dotn_can_follow_name(next SourceToken) bool {
	return match next.kind {
		.punctuator, .string_, .template, .private_identifier { true }
		.numeric { c.token_text(next).starts_with('.') }
		else { false }
	}
}

// dotn_use_brackets_fixes ports the fixer of `useBrackets`: the `.` goes (a `?.` stays) and the
// name becomes `["name"]`. No fix for `let.name` (a statement that starts with `let[` is a
// declaration) nor with a comment between the dot and the name.
fn (mut c Checker) dotn_use_brackets_fixes(member C.TSNode, property C.TSNode, name string) []Fix {
	object := unwrap_parens(node_field(member, 'object') or { return []Fix{} })
	optional := is_optional_element(member)
	if node_kind(object) == 'identifier' && c.identifier_name(object) == 'let' && !optional {
		return []Fix{}
	}
	dot := c.token_before(property) or { return []Fix{} }
	if c.source_tokens(member).comments_exist_between(dot.end, node_start(property)) {
		return []Fix{}
	}
	mut fixes := []Fix{}
	if !optional {
		fixes << fix_remove_range(dot.start, dot.end)
	}
	fixes << fix_replace(property, '["${name}"]')
	return fixes
}

// dotn_core_options reads the options of the core rule.
fn dotn_core_options(options []json2.Any) !DotnOptions {
	return dotn_options(options, true)
}
