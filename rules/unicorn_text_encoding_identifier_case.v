module rules

import estree
import json2
import time

// Port of the `unicorn/text-encoding-identifier-case` rule of eslint-plugin-unicorn 64.0.0, with
// its fix and its suggestion.

const uteic_messages = {
	'text-encoding-identifier/error':      'Prefer `{{replacement}}` over `{{value}}`.'
	'text-encoding-identifier/suggestion': 'Replace `{{value}}` with `{{replacement}}`.'
}

fn uteic_options(options []json2.Any) !bool {
	o := option_object(unicorn_text_encoding_identifier_case, options, ['withDash'])!
	return o.bool_value('withDash')!
}

// uteic_replacement ports getReplacement.
fn uteic_replacement(encoding string, with_dash bool) ?string {
	return match encoding.to_lower() {
		'utf-8', 'utf8' { if with_dash { 'utf-8' } else { 'utf8' } }
		'ascii' { 'ascii' }
		else { none }
	}
}

// uteic_jsx_attribute ports isJsxElementAttributes: the value of one of `attributes` of the JSX
// element `element` (names in lower case).
fn uteic_jsx_attribute(t &estree.EsTree, node int, element string, attributes []string) bool {
	attribute := t.nodes[node].parent
	if attribute < 0 || t.typ(attribute) != .jsx_attribute || t.node(attribute, .value) or { -1 } != node {
		return false
	}
	name := t.node(attribute, .name) or { return false }
	if t.typ(name) != .jsx_identifier || (t.string_of(name, .name) or { '' }).to_lower() !in attributes {
		return false
	}
	opening := t.nodes[attribute].parent
	if opening < 0 || t.typ(opening) != .jsx_opening_element
		|| attribute !in (t.list(opening, .attributes) or { []int{} }) {
		return false
	}
	element_name := t.node(opening, .name) or { return false }
	return t.typ(element_name) == .jsx_identifier
		&& (t.string_of(element_name, .name) or { '' }).to_lower() == element
}

// uteic_enforce_dash ports shouldEnforceDash.
fn uteic_enforce_dash(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	return uteic_jsx_attribute(t, node, 'meta', ['charset'])
		|| uteic_jsx_attribute(t, node, 'form', ['acceptcharset', 'accept-charset'])
		|| (un_is_new(t, parent, names: ['TextDecoder'])
		&& uteic_first_argument(t, parent) == node)
}

fn uteic_first_argument(t &estree.EsTree, node int) int {
	arguments := t.list(node, .arguments) or { return -1 }
	return if arguments.len > 0 { arguments[0] } else { -1 }
}

// uteic_value ports getStringLiteralValue.
fn (c &Checker) uteic_value(t &estree.EsTree, node int) ?string {
	if t.typ(node) == .literal {
		if t.get(node, .value) !is string {
			return none
		}
		raw := un_raw(t, node)
		return raw[1..raw.len - 1]
	}
	parent := t.nodes[node].parent
	quasis := t.list(node, .quasis) or { return none }
	if t.typ(node) == .template_literal && (parent < 0 || t.typ(parent) != .tagged_template_expression)
		&& (t.list(node, .expressions) or { []int{} }).len == 0 && quasis.len == 1 {
		return un_template_raw(t, quasis[0])
	}
	return none
}

// uteic_fs_read_file ports isFsReadFileEncoding: the second argument of `readFile` or
// `readFileSync`.
fn uteic_fs_read_file(t &estree.EsTree, node int) bool {
	call := t.nodes[node].parent
	if !un_is_method_call(t, call,
		methods:         ['readFile', 'readFileSync']
		optional_call:   false
		optional_member: false
	) {
		return false
	}
	args := t.list(call, .arguments) or { return false }
	return args.len > 1 && args[1] == node && t.typ(args[0]) != .spread_element
}

fn (mut c Checker) lint_unicorn_text_encoding_identifier_case(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	with_dash_option := uteic_options(c.rule_options(unicorn_text_encoding_identifier_case))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) !in [.literal, .template_literal] {
			continue
		}
		stats.checked++
		value := c.uteic_value(t, node) or { continue }
		if value == '' {
			continue
		}
		with_dash := with_dash_option || uteic_enforce_dash(t, node)
		replacement := uteic_replacement(value, with_dash) or { continue }
		if replacement == value {
			continue
		}
		fix := fix_replace_range(t.nodes[node].start + 1, t.nodes[node].end - 1, replacement)
		data := {
			'value':       value
			'replacement': replacement
		}
		if uteic_fs_read_file(t, node) {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'text-encoding-identifier/error'
				data:       data
				has_fix:    true
				fix:        fix
			}
			continue
		}
		findings << Finding{
			stmt:        c.es_tree_position(t, node)
			message_id:  'text-encoding-identifier/error'
			data:        data
			suggestions: [
				Suggestion{
					message_id: 'text-encoding-identifier/suggestion'
					data:       data
					fix:        fix
				},
			]
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
