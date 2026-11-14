module rules

import estree
import json2
import time

// Port of the `unicorn/no-keyword-prefix` rule of eslint-plugin-unicorn 79.0.0, with its options
// (`disallowedPrefixes`, `checkProperties`, `onlyCamelCase`).

const unkp_messages = {
	'noKeywordPrefix': 'Do not prefix identifiers with keyword `{{keyword}}`.'
}

// UnkpOptions are the options of prepareOptions.
struct UnkpOptions {
	disallowed_prefixes []string
	prefix_units        [][]u16
	check_properties    bool
	only_camel_case     bool
}

fn unkp_options(options []json2.Any) !UnkpOptions {
	o := option_object(unicorn_no_keyword_prefix, options, ['disallowedPrefixes', 'checkProperties',
		'onlyCamelCase'])!
	// `disallowedPrefixes || ['new', 'class']`: an empty list stays empty.
	mut prefixes := ['new', 'class']
	if 'disallowedPrefixes' in o.values {
		prefixes = o.string_list('disallowedPrefixes')!
		for i, prefix in prefixes {
			if prefix in prefixes[..i] {
				return error('option `disallowedPrefixes` of `${unicorn_no_keyword_prefix}` must have unique items')
			}
		}
	}
	return UnkpOptions{
		disallowed_prefixes: prefixes
		prefix_units:        prefixes.map(utf16_units(it))
		check_properties:    if 'checkProperties' in o.values {
			o.bool_value('checkProperties')!
		} else {
			true
		}
		only_camel_case:     if 'onlyCamelCase' in o.values {
			o.bool_value('onlyCamelCase')!
		} else {
			true
		}
	}
}

// unkp_find_keyword_prefix ports findKeywordPrefix: the first disallowed prefix the name starts
// with, followed by a character (an upper case ASCII letter with onlyCamelCase), on UTF-16 units.
fn unkp_find_keyword_prefix(name string, options &UnkpOptions) ?string {
	units := utf16_units(name)
	for i, keyword in options.prefix_units {
		if units.len < keyword.len || units[..keyword.len] != keyword {
			continue
		}
		if units.len == keyword.len {
			continue
		}
		next := units[keyword.len]
		if !options.only_camel_case || (next >= `A` && next <= `Z`) {
			return options.disallowed_prefixes[i]
		}
	}
	return none
}

// UnkpReporter is `report` of the rule: one problem per start position (a shorthand property has a
// separate node for its key and its value at the same position).
struct UnkpReporter {
mut:
	reported map[int]bool
	findings []Finding
}

fn (mut r UnkpReporter) report(c &Checker, t &estree.EsTree, node int, keyword string) {
	start := t.nodes[node].start
	if start in r.reported {
		return
	}
	r.reported[start] = true
	r.findings << Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: 'noKeywordPrefix'
		data:       {
			'name':    t.string_of(node, .name) or { '' }
			'keyword': keyword
		}
	}
}

fn (mut c Checker) lint_unicorn_no_keyword_prefix(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	options := unkp_options(c.rule_options(unicorn_no_keyword_prefix))!
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut r := UnkpReporter{}
	for node in un_enter_order(t) {
		if t.typ(node) != .identifier {
			continue
		}
		stats.checked++
		c.unkp_identifier(t, node, &options, mut r)
	}
	stats.eval_ms += ms(sw.elapsed())
	return r.findings
}

// unkp_property_name is `.property.name`: the name of an identifier or a private identifier.
fn unkp_property_name(t &estree.EsTree, member int) ?string {
	property := t.node(member, .property)?
	if t.typ(property) in [.identifier, .private_identifier] {
		return t.string_of(property, .name)
	}
	return none
}

// unkp_member_expression ports reportMemberExpression.
fn (c &Checker) unkp_member_expression(t &estree.EsTree, node int, options &UnkpOptions, mut r UnkpReporter) {
	if !options.check_properties {
		return
	}
	name := t.string_of(node, .name) or { '' }
	keyword := unkp_find_keyword_prefix(name, options) or { return }
	parent := t.nodes[node].parent
	object := t.node(parent, .object) or { -1 }
	if object >= 0 && t.typ(object) == .identifier && (t.string_of(object, .name) or { '' }) == name {
		r.report(c, t, node, keyword)
		return
	}
	// `parent` is always a `MemberExpression` here.
	effective_parent := t.nodes[parent].parent
	if effective_parent < 0 || t.typ(effective_parent) != .assignment_expression {
		return
	}
	left := t.node(effective_parent, .left) or { return }
	right := t.node(effective_parent, .right) or { return }
	if (t.typ(right) != .member_expression || t.typ(left) == .member_expression)
		&& (unkp_property_name(t, left) or { return }) == name {
		r.report(c, t, node, keyword)
	}
}

// unkp_object_pattern ports reportObjectPatternAndShouldSkipPropertyCheck.
fn (c &Checker) unkp_object_pattern(t &estree.EsTree, node int, options &UnkpOptions, property int, mut r UnkpReporter) bool {
	name := t.string_of(node, .name) or { '' }
	keyword := unkp_find_keyword_prefix(name, options)
	if k := keyword {
		if t.flag(property, .computed) or { false } {
			r.report(c, t, node, k)
		}
	}
	key := t.node(property, .key) or { -1 }
	// The property name, only the binding is checked here.
	if key == node {
		return true
	}
	// A same-name binding, like `{newFoo}`, is checked as a property.
	if key >= 0 && t.typ(key) == .identifier && (t.string_of(key, .name) or { '' }) == name {
		return false
	}
	// A renamed binding declares a new local variable, that is not a property.
	if k := keyword {
		r.report(c, t, node, k)
	}
	return true
}

fn (c &Checker) unkp_identifier(t &estree.EsTree, node int, options &UnkpOptions, mut r UnkpReporter) {
	name := t.string_of(node, .name) or { '' }
	parent := t.nodes[node].parent
	if parent < 0 {
		return
	}
	keyword := unkp_find_keyword_prefix(name, options)
	parent_type := t.typ(parent)
	effective_parent := if parent_type == .member_expression { t.nodes[parent].parent } else { parent }
	allowed_parent := effective_parent >= 0
		&& t.typ(effective_parent) in [.call_expression, .new_expression]
	if parent_type == .member_expression {
		c.unkp_member_expression(t, node, options, mut r)
	} else if parent_type in [.property, .assignment_pattern] {
		// `const {newFoo = 1} = object` puts the binding in an `AssignmentPattern` inside the
		// shorthand `Property`.
		property := if parent_type == .assignment_pattern && t.node(parent, .left) or { -1 } == node {
			t.nodes[parent].parent
		} else {
			parent
		}
		if property >= 0 && t.typ(property) == .property && t.nodes[property].parent >= 0
			&& t.typ(t.nodes[property].parent) == .object_pattern {
			if c.unkp_object_pattern(t, node, options, property, mut r) {
				return
			}
		}
		if !options.check_properties {
			return
		}
		// Not the right hand side of an AssignmentPattern.
		if k := keyword {
			if !allowed_parent && t.node(parent, .right) or { -1 } != node {
				r.report(c, t, node, k)
			}
		}
	} else if parent_type in [.import_specifier, .import_namespace_specifier, .import_default_specifier] {
		// Only the local name of an import.
		if k := keyword {
			local := t.node(parent, .local) or { -1 }
			if local >= 0 && (t.string_of(local, .name) or { '' }) == name {
				r.report(c, t, node, k)
			}
		}
	} else if k := keyword {
		if !allowed_parent {
			r.report(c, t, node, k)
		}
	}
}
