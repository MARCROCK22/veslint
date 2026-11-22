module rules

import estree
import time

// Port of the `unicorn/prefer-string-raw` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fixes and suggestion. veslint lints TypeScript files only (isTypeScriptFile).

const upsr_messages = {
	'prefer-string-raw':            '`String.raw` should be used to avoid escaping `\\`.'
	'prefer-string-raw/suggestion': 'Use `String.raw`. This may widen the string literal type to `string`.'
	'unnecessary-string-raw':       'Using `String.raw` is unnecessary as the string does not contain any `\\`.'
}

// upsr_unescape ports unescapeBackslash: `\\` and an escaped quote become the character.
fn upsr_unescape(text string, quote string) string {
	mut out := []u8{cap: text.len}
	mut i := 0
	for i < text.len {
		if text[i] == `\\` && i + 1 < text.len
			&& (text[i + 1] == `\\` || (quote != '' && text[i + 1] == quote[0])) {
			out << text[i + 1]
			i += 2
			continue
		}
		out << text[i]
		i++
	}
	return out.bytestr()
}

// upsr_restricted ports isStringLiteralRequired (utils/is-string-literal-required.js): where
// another expression cannot take the place of the string (a directive, a key, a module source, a
// literal type…).
fn upsr_restricted(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	at := fn [t, parent, node] (key estree.Key) bool {
		return t.node(parent, key) or { -1 } == node
	}
	return match t.typ(parent) {
		.expression_statement {
			t.string_of(parent, .directive) != none
		}
		.property, .property_definition, .method_definition, .accessor_property {
			!(t.flag(parent, .computed) or { false }) && at(.key)
		}
		.ts_abstract_property_definition, .ts_abstract_method_definition,
		.ts_abstract_accessor_property, .ts_property_signature, .ts_method_signature {
			at(.key)
		}
		.import_declaration, .export_named_declaration {
			at(.source)
		}
		.export_all_declaration {
			at(.source) || at(.exported)
		}
		.import_attribute {
			at(.key) || at(.value)
		}
		.import_specifier {
			at(.imported)
		}
		.export_specifier {
			at(.local) || at(.exported)
		}
		.jsx_attribute {
			at(.value)
		}
		.ts_enum_member {
			at(.initializer) || at(.id)
		}
		.ts_module_declaration {
			at(.id)
		}
		.ts_external_module_reference {
			at(.expression)
		}
		.ts_literal_type {
			at(.literal)
		}
		.ts_import_type {
			at(.source)
		}
		else {
			false
		}
	}
}

// upsr_jest_inline_snapshot ports isJestInlineSnapshot: the argument of
// `expect(…).toMatchInlineSnapshot(…)`.
fn upsr_jest_inline_snapshot(t &estree.EsTree, node int) bool {
	call := t.nodes[node].parent
	if !un_is_method_call(t, call,
		methods:          ['toMatchInlineSnapshot']
		arguments_length: 1
		optional_call:    false
		optional_member:  false
	) || (t.list(call, .arguments) or { []int{} })[0] != node {
		return false
	}
	object := t.node(t.node(call, .callee) or { return false }, .object) or { return false }
	return un_is_call(t, object, names: ['expect'], arguments_length: 1, optional: false)
}

fn (mut c Checker) lint_unicorn_prefer_string_raw(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.literal {
				stats.checked++
				if !un_is_string_literal(t, node) || upsr_restricted(t, node)
					|| upsr_jest_inline_snapshot(t, node) {
					continue
				}
				raw := un_raw(t, node)
				if raw.len < 2 || raw[raw.len - 2] == `\\` || !raw.contains('\\\\')
					|| raw.contains('`') || raw.contains('\${')
					|| !un_same_line(t, t.nodes[node].start, t.nodes[node].end) {
					continue
				}
				unescaped := upsr_unescape(raw[1..raw.len - 1], raw[..1])
				value := t.get(node, .value)
				if !(value is string && value == unescaped) {
					continue
				}
				mut fixes := c.unb_fix_space_around_keyword(t, tokens, node)
				fixes << fix_replace_range(t.nodes[node].start, t.nodes[node].end, 'String.raw`${unescaped}`')
				found, finding := c.upsr_problem(t, node, fixes, abs_path, mut stats)!
				if found {
					findings << finding
				}
			}
			.template_literal {
				stats.checked++
				if un_is_tagged_template(t, node, []) || upsr_restricted(t, node)
					|| upsr_jest_inline_snapshot(t, node) {
					continue
				}
				quasis := t.list(node, .quasis) or { continue }
				values := quasis.map(t.get(it, .value))
				mut all_same := true
				mut skip := false
				for value in values {
					if value !is estree.TemplateValue {
						skip = true
						break
					}
					v := value as estree.TemplateValue
					if v.cooked != v.raw {
						all_same = false
					}
					if v.cooked.ends_with('\\') || upsr_unescape(v.raw, '') != v.cooked {
						skip = true
					}
				}
				if all_same || skip {
					continue
				}
				mut fixes := c.unb_fix_space_around_keyword(t, tokens, node)
				fixes << fix_insert_at(t.nodes[node].start, 'String.raw')
				for i, quasi in quasis {
					v := values[i] as estree.TemplateValue
					if v.cooked != v.raw {
						fixes << un_replace_template_element(t, quasi, v.cooked)
					}
				}
				found, finding := c.upsr_problem(t, node, fixes, abs_path, mut stats)!
				if found {
					findings << finding
				}
			}
			.tagged_template_expression {
				stats.checked++
				found, finding := c.upsr_unnecessary(root, t, tokens, node)!
				if found {
					findings << finding
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// upsr_problem ports getStringRawProblem, which keeps the literal types of TypeScript: none for
// `as const`, nor when the types say the replacement could change the type of the string; a
// suggestion when the fix may widen it.
fn (mut c Checker) upsr_problem(t &estree.EsTree, node int, fixes []Fix, abs_path string, mut stats Stats) !(bool, Finding) {
	parent := t.nodes[node].parent
	if t.typ(parent) in [.ts_as_expression, .ts_type_assertion] {
		annotation := t.node(parent, .type_annotation) or { -1 }
		if annotation >= 0 && t.typ(annotation) == .ts_type_reference {
			name := t.node(annotation, .type_name) or { -1 }
			if name >= 0 && (t.string_of(name, .name) or { '' }) == 'const' {
				return false, Finding{}
			}
		}
	}
	mut binding := -1
	if t.typ(parent) == .variable_declarator && t.node(parent, .init) or { -1 } == node {
		id := t.node(parent, .id) or { -1 }
		if id >= 0 && t.typ(id) == .identifier {
			binding = id
		}
	}
	// Assignability alone does not keep narrowing or generic inference.
	mut type_safety := ?bool(none)
	if type_ := c.unb_type_of(t, node, abs_path, mut stats) {
		mut safe := type_.flags == type_flag_string
		if !safe && binding >= 0 {
			if binding_type := c.unb_type_of(t, binding, abs_path, mut stats) {
				non_nullable := c.client.non_nullable_type(c.snapshot, c.project, binding_type.id)!
				safe = non_nullable.flags == type_flag_string
			}
		}
		type_safety = safe
	}
	if safety := type_safety {
		if !safety {
			return false, Finding{}
		}
	}
	can_fix := type_safety or {
		binding >= 0 && c.upsr_binding_is_string(t, parent, binding)
	}
	_, fix := c.merge_fixes(fixes)!
	mut finding := Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: 'prefer-string-raw'
	}
	if can_fix {
		finding = Finding{
			...finding
			has_fix: true
			fix:     fix
		}
	} else {
		finding = Finding{
			...finding
			suggestions: [
				Suggestion{
					message_id: 'prefer-string-raw/suggestion'
					fix:        fix
				},
			]
		}
	}
	return true, finding
}

// upsr_binding_is_string: without the types, the binding is annotated `string`, or is a `let` or
// `var` without an annotation.
fn (c &Checker) upsr_binding_is_string(t &estree.EsTree, declarator int, binding int) bool {
	if annotation := t.node(binding, .type_annotation) {
		inner := t.node(annotation, .type_annotation) or { return false }
		return t.typ(inner) == .ts_string_keyword
	}
	declaration := t.nodes[declarator].parent
	return (t.string_of(declaration, .kind) or { '' }) in ['let', 'var']
}

// upsr_unnecessary reports a `String.raw` of the global whose template has no backslash: the fix
// makes it a string literal.
fn (mut c Checker) upsr_unnecessary(root C.vt_node, t &estree.EsTree, tokens &SourceTokens, node int) !(bool, Finding) {
	quasi := t.node(node, .quasi) or { return false, Finding{} }
	tag := t.node(node, .tag) or { return false, Finding{} }
	if !un_is_member(t, tag, objects: ['String'], properties: ['raw'], optional: false) {
		return false, Finding{}
	}
	object := t.node(tag, .object) or { return false, Finding{} }
	if !c.es_is_global_reference(root, t.ts_node(object) or { return false, Finding{} }) {
		return false, Finding{}
	}
	quasis := t.list(quasi, .quasis) or { return false, Finding{} }
	if quasis.any(un_template_raw(t, it).contains('\\')) {
		return false, Finding{}
	}
	raw_quasi := c.un_text(t, quasi)
	// A line break, a bare `\r` too, is not allowed in a string literal; `\u2028` and `\u2029` are
	// kept in the template literal too.
	suggestion := if (t.list(quasi, .expressions) or { []int{} }).len > 0
		|| raw_quasi.contains_any('\n\r\u2028\u2029') {
		raw_quasi
	} else {
		"'" + raw_quasi[1..raw_quasi.len - 1].replace("'", "\\'") + "'"
	}
	mut finding := Finding{
		stmt:       c.es_tree_position(t, tag)
		message_id: 'unnecessary-string-raw'
	}
	// The tag is removed as a whole: a comment inside it would be dropped.
	if tokens.comments_inside(t.nodes[tag].start, t.nodes[tag].end).len > 0 {
		return true, finding
	}
	mut fixes := []Fix{}
	before := tokens.before(t.nodes[node].start, false)
	keyword_parent := c.unb_unparenthesized_keyword_argument_parent(t, tokens, node)
	if c.unb_needs_semicolon(t, tokens, before, suggestion) {
		fixes << fix_insert_at(t.nodes[node].start, ';')
	}
	same_line := if b := before { un_same_line(t, b.start, t.nodes[quasi].start) } else { true }
	if keyword_parent >= 0 && !same_line {
		if t.typ(keyword_parent) in [.return_statement, .throw_statement] {
			fixes << c.un_add_parens_to_return_or_throw(t, tokens, keyword_parent)
		} else if t.typ(keyword_parent) == .yield_expression {
			fixes << fix_insert_at(t.nodes[node].start, '(')
			fixes << fix_insert_at(t.nodes[node].end, ')')
		}
	}
	fixes << fix_replace_range(t.nodes[quasi].start, t.nodes[quasi].end, suggestion)
	fixes << c.un_remove_parentheses(t, tokens, tag)
	fixes << fix_remove_range(t.nodes[tag].start, t.nodes[tag].end)
	has_fix, fix := c.merge_fixes(fixes)!
	return true, Finding{
		...finding
		has_fix: has_fix
		fix:     fix
	}
}
