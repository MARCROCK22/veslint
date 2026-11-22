module rules

import jsregexp

// Port of the `svelte/no-bind-value-on-checkable-inputs` rule of eslint-plugin-svelte 3.24.1: a
// `bind:value` on an <input> whose type is checkbox or radio (a literal, or an expression with a
// static string value, in any case) does not work; the suggestions change it to `bind:checked`
// (checkboxes) or `bind:group`.

const snbvci_messages = {
	'checkboxValueBinding': '`bind:value` does not work on checkbox inputs. Did you mean `bind:checked` or `bind:group`?'
	'radioValueBinding':    '`bind:value` does not work on radio inputs. Did you mean `bind:group`?'
	'checkedSuggestion':    'Change `bind:value` to `bind:checked`.'
	'groupSuggestion':      'Change `bind:value` to `bind:group`.'
}

fn (mut c Checker) lint_svelte_no_bind_value_on_checkable_inputs(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for el in c.sv_snodes_of(.element) {
		n := doc.nodes[el]
		if n.name_ref.es || n.name_ref.idx < 0 || doc.nodes[n.name_ref.idx].typ != .name
			|| doc.nodes[n.name_ref.idx].name != 'input' || n.start_tag < 0 {
			continue
		}
		typ := c.snbvci_type(root, abs_path, n.start_tag) or { continue }
		if typ != 'checkbox' && typ != 'radio' {
			continue
		}
		mut bind := -1
		for a in doc.nodes[n.start_tag].attributes {
			an := doc.nodes[a]
			if an.typ == .directive && an.kind == 'Binding' && c.sv_directive_key_name(a) == 'value' {
				bind = a
				break
			}
		}
		if bind < 0 {
			continue
		}
		mut suggestions := []Suggestion{}
		for kind in if typ == 'checkbox' { ['checked', 'group'] } else { ['group'] } {
			b := doc.nodes[bind]
			fix := if b.shorthand {
				Fix{
					start: b.start
					end:   b.end
					text:  'bind:${kind}={value}'
				}
			} else {
				key_start, key_end := c.sv_ref_range(b.key)
				Fix{
					start: key_start
					end:   key_end
					text:  'bind:${kind}'
				}
			}
			suggestions << Suggestion{
				message_id: '${kind}Suggestion'
				fix:        fix
			}
		}
		findings << Finding{
			...c.sv_report_snode(bind, '${typ}ValueBinding', {})
			suggestions: suggestions
		}
	}
	return findings
}

// snbvci_type is getType: the lower-cased value of the `type` attribute (its name in any case)
// when it is one literal or one mustache tag with a static string.
fn (mut c Checker) snbvci_type(root C.vt_node, abs_path string, tag int) ?string {
	doc := c.svelte.doc
	for a in doc.nodes[tag].attributes {
		an := doc.nodes[a]
		if an.typ != .attribute || c.sv_attribute_name(a).to_lower() != 'type' {
			continue
		}
		if an.values.len != 1 {
			return none
		}
		v := doc.nodes[an.values[0]]
		if v.typ == .literal {
			return snbvci_lower(v.value)
		}
		if v.typ == .mustache_tag && v.expression.es && v.expression.idx >= 0 {
			value := c.snbvci_static_string(root, abs_path, v.expression.idx)?
			return snbvci_lower(value)
		}
		return none
	}
	return none
}

// snbvci_static_string is getStaticValue of a template expression as a string: the expression of
// the lint code (where the scope manager has the template's variables) at the same place.
fn (mut c Checker) snbvci_static_string(root C.vt_node, abs_path string, expr int) ?string {
	doc := c.svelte.doc
	e := doc.es.nodes[expr]
	start := c.svelte_file_to_lint(e.start, false)
	end := c.svelte_file_to_lint(e.end, true)
	if start < 0 || end < 0 {
		return none
	}
	t := c.es_tree(root, abs_path)?
	for k, n in t.nodes {
		if n.start == start && n.end == end && n.typ == e.typ {
			value := c.un_static_value(t, k)
			if value.found && value.value.kind == .string_ {
				return stv_units_string(value.value.units)
			}
			return none
		}
	}
	return none
}

// snbvci_lower is String.prototype.toLowerCase.
fn snbvci_lower(s string) string {
	return stv_units_string(jsregexp.js_to_lower(utf16_units(s)))
}
