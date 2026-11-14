module rules

import estree
import time

// Port of the `unicorn/prefer-string-raw` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its fix.

const upsr_messages = {
	'prefer-string-raw': '`String.raw` should be used to avoid escaping `\\`.'
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

// upsr_restricted ports isStringRawRestricted: where a tagged template cannot take the place of
// the string (a directive, a key, a module source, a literal type…).
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
		.ts_abstract_accessor_property, .ts_property_signature {
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
	return un_is_call(t, object, names: ['expect'], arguments_length: 1)
}

fn (mut c Checker) lint_unicorn_prefer_string_raw(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
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
				mut fixes := c.un_fix_space_around_keyword(t, tokens, node)
				fixes << fix_replace_range(t.nodes[node].start, t.nodes[node].end, 'String.raw`${unescaped}`')
				has_fix, fix := c.merge_fixes(fixes)!
				findings << Finding{
					stmt:       c.es_tree_position(t, node)
					message_id: 'prefer-string-raw'
					has_fix:    has_fix
					fix:        fix
				}
			}
			.template_literal {
				stats.checked++
				if un_is_tagged_template(t, node, []) || upsr_jest_inline_snapshot(t, node) {
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
				mut fixes := c.un_fix_space_around_keyword(t, tokens, node)
				fixes << fix_insert_at(t.nodes[node].start, 'String.raw')
				for i, quasi in quasis {
					v := values[i] as estree.TemplateValue
					if v.cooked != v.raw {
						fixes << un_replace_template_element(t, quasi, v.cooked)
					}
				}
				has_fix, fix := c.merge_fixes(fixes)!
				findings << Finding{
					stmt:       c.es_tree_position(t, node)
					message_id: 'prefer-string-raw'
					has_fix:    has_fix
					fix:        fix
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
