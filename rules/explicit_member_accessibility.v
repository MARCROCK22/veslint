module rules

import estree
import json2
import time

// Port of the `@typescript-eslint/explicit-member-accessibility` rule of typescript-eslint 8.72.2,
// with all its options, its fix (no-public) and its suggestions (explicit).

const ema_messages = {
	'addExplicitAccessibility':    "Add '{{ type }}' accessibility modifier"
	'missingAccessibility':        'Missing accessibility modifier on {{type}} {{name}}.'
	'unwantedPublicAccessibility': 'Public accessibility modifier on {{type}} {{name}}.'
}

const ema_levels = ['explicit', 'no-public', 'off']

struct EmaOptions {
	ctor_check           string
	accessor_check       string
	method_check         string
	prop_check           string
	param_prop_check     string
	ignored_method_names []string
}

fn ema_options(options []json2.Any) !EmaOptions {
	o := option_object(explicit_member_accessibility, options, ['accessibility',
		'ignoredMethodNames', 'overrides'])!
	mut base := o.string_value('accessibility', ema_levels)!
	if base == '' {
		base = 'explicit'
	}
	mut overrides := map[string]string{}
	if raw := o.values['overrides'] {
		if raw !is map[string]json2.Any {
			return error('${explicit_member_accessibility}: overrides must be an object')
		}
		m := raw as map[string]json2.Any
		for key, value in m {
			if key !in ['accessors', 'constructors', 'methods', 'parameterProperties', 'properties'] {
				return error('${explicit_member_accessibility}: unknown override ${key}')
			}
			if value !is string || (value as string) !in ema_levels {
				return error('${explicit_member_accessibility}: overrides.${key} must be one of ${ema_levels}')
			}
			overrides[key] = value as string
		}
	}
	return EmaOptions{
		ctor_check:           overrides['constructors'] or { base }
		accessor_check:       overrides['accessors'] or { base }
		method_check:         overrides['methods'] or { base }
		prop_check:           overrides['properties'] or { base }
		param_prop_check:     overrides['parameterProperties'] or { base }
		ignored_method_names: o.string_list('ignoredMethodNames') or { []string{} }
	}
}

fn (mut c Checker) lint_explicit_member_accessibility(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := ema_options(c.rule_options(explicit_member_accessibility))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.source_tokens(t.nodes[t.root].ts)
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.method_definition, .ts_abstract_method_definition {
				stats.checked++
				c.ema_check_method(t, tokens, node, o, mut findings)
			}
			.property_definition, .ts_abstract_property_definition, .accessor_property,
			.ts_abstract_accessor_property {
				stats.checked++
				c.ema_check_property(t, tokens, node, o, mut findings)
			}
			.ts_parameter_property {
				stats.checked++
				c.ema_check_parameter_property(t, tokens, node, o, mut findings)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ema_check_method ports checkMethodAccessibilityModifier.
fn (mut c Checker) ema_check_method(t &estree.EsTree, tokens &SourceTokens, node int, o EmaOptions, mut findings []Finding) {
	key := t.node(node, .key) or { return }
	if t.typ(key) == .private_identifier {
		return
	}
	mut node_type := 'method definition'
	kind := t.string_of(node, .kind) or { '' }
	check := match kind {
		'method' {
			o.method_check
		}
		'constructor' {
			o.ctor_check
		}
		'get', 'set' {
			node_type = '${kind} property accessor'
			o.accessor_check
		}
		else {
			'explicit'
		}
	}
	method_name, _ := c.tsm_name_from_member(t, node)
	if check == 'off' || method_name in o.ignored_method_names {
		return
	}
	c.ema_report(t, tokens, node, check, method_name, node_type, mut findings)
}

// ema_check_property ports checkPropertyAccessibilityModifier.
fn (mut c Checker) ema_check_property(t &estree.EsTree, tokens &SourceTokens, node int, o EmaOptions, mut findings []Finding) {
	key := t.node(node, .key) or { return }
	if t.typ(key) == .private_identifier {
		return
	}
	property_name, _ := c.tsm_name_from_member(t, node)
	c.ema_report(t, tokens, node, o.prop_check, property_name, 'class property', mut findings)
}

// ema_report reports a member: its `public` with `no-public`, its missing accessibility with
// `explicit`.
fn (mut c Checker) ema_report(t &estree.EsTree, tokens &SourceTokens, node int, check string, name string, node_type string, mut findings []Finding) {
	accessibility := t.string_of(node, .accessibility) or { '' }
	data := {
		'name': name
		'type': node_type
	}
	if check == 'no-public' && accessibility == 'public' {
		keyword_start, keyword_end, remove_end := c.ema_find_public_keyword(t, tokens, node)
		findings << Finding{
			stmt:       c.position_range(keyword_start, keyword_end)
			message_id: 'unwantedPublicAccessibility'
			data:       data
			has_fix:    true
			fix:        fix_remove_range(keyword_start, remove_end)
		}
	} else if check == 'explicit' && accessibility == '' {
		findings << Finding{
			stmt:        c.tsm_member_head(t, tokens, node)
			message_id:  'missingAccessibility'
			data:        data
			suggestions: ema_missing_accessibility_suggestions(t, tokens, node)
		}
	}
}

// ema_check_parameter_property ports checkParameterPropertyAccessibilityModifier.
fn (mut c Checker) ema_check_parameter_property(t &estree.EsTree, tokens &SourceTokens, node int, o EmaOptions, mut findings []Finding) {
	parameter := t.node(node, .parameter) or { return }
	name_node := if t.typ(parameter) == .identifier {
		parameter
	} else {
		t.node(parameter, .left) or { -1 }
	}
	node_name := if name_node >= 0 { t.string_of(name_node, .name) or { '' } } else { '' }
	data := {
		'name': node_name
		'type': 'parameter property'
	}
	accessibility := t.string_of(node, .accessibility) or { '' }
	match o.param_prop_check {
		'explicit' {
			if accessibility == '' {
				findings << Finding{
					stmt:        c.tsm_parameter_property_head(t, tokens, node, node_name)
					message_id:  'missingAccessibility'
					data:        data
					suggestions: ema_missing_accessibility_suggestions(t, tokens, node)
				}
			}
		}
		'no-public' {
			if accessibility == 'public' && (t.flag(node, .readonly) or { false }) {
				keyword_start, keyword_end, remove_end := c.ema_find_public_keyword(t, tokens,
					node)
				findings << Finding{
					stmt:       c.position_range(keyword_start, keyword_end)
					message_id: 'unwantedPublicAccessibility'
					data:       data
					has_fix:    true
					fix:        fix_remove_range(keyword_start, remove_end)
				}
			}
		}
		else {}
	}
}

// ema_find_public_keyword ports findPublicKeyword: the range of the `public` keyword of the node,
// and the end of the range to remove with it (the first comment after it, or the next token).
fn (c &Checker) ema_find_public_keyword(t &estree.EsTree, tokens &SourceTokens, node int) (int, int, int) {
	node_tokens := tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
	for i, token in node_tokens {
		if token.kind == .keyword && c.src[token.start..token.end] == 'public' {
			comments := tokens.comments_after(token.end)
			if comments.len > 0 {
				return token.start, token.end, comments[0].start
			}
			next := if i + 1 < node_tokens.len { node_tokens[i + 1].start } else { token.end }
			return token.start, token.end, next
		}
	}
	return t.nodes[node].start, t.nodes[node].start, t.nodes[node].start
}

// ema_missing_accessibility_suggestions ports getMissingAccessibilitySuggestions: insert each
// accessibility before the member (after its decorators).
fn ema_missing_accessibility_suggestions(t &estree.EsTree, tokens &SourceTokens, node int) []Suggestion {
	at := tsm_after_decorators(t, tokens, node)
	return ['public', 'private', 'protected'].map(Suggestion{
		message_id: 'addExplicitAccessibility'
		data:       {
			'type': it
		}
		fix:        fix_insert_at(at, '${it} ')
	})
}
