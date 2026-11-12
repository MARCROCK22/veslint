module rules

import json2
import time
import treesitter { node_field, node_kind, node_parent, position_of }

// Port of the `no-extraneous-class` rule of typescript-eslint 8.62.0, with its options
// `allowConstructorOnly`, `allowEmpty`, `allowStaticOnly` and `allowWithDecorator`.

const nec_messages = {
	'empty':           'Unexpected empty class.'
	'onlyConstructor': 'Unexpected class with only a constructor.'
	'onlyStatic':      'Unexpected class with only static properties.'
}

struct NecOptions {
	allow_constructor_only bool
	allow_empty            bool
	allow_static_only      bool
	allow_with_decorator   bool
}

fn nec_options(options []json2.Any) !NecOptions {
	o := option_object(no_extraneous_class, options, ['allowConstructorOnly', 'allowEmpty',
		'allowStaticOnly', 'allowWithDecorator'])!
	return NecOptions{
		allow_constructor_only: o.bool_value('allowConstructorOnly')!
		allow_empty:            o.bool_value('allowEmpty')!
		allow_static_only:      o.bool_value('allowStaticOnly')!
		allow_with_decorator:   o.bool_value('allowWithDecorator')!
	}
}

fn (mut c Checker) lint_no_extraneous_class(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nec_options(c.rule_options(no_extraneous_class))!
	mut findings := []Finding{}
	mut checked := 0
	for body in c.nodes_of_kind(root, c'class_body') {
		class := node_parent(body) or { continue }
		if _ := cm_super_class(class) {
			continue
		}
		if o.allow_with_decorator && cm_class_decorators(class).len > 0 {
			continue
		}
		checked++
		message_id := c.nec_check(body, o) or { continue }
		findings << Finding{
			stmt:       position_of(nec_report_node(class))
			message_id: message_id
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nec_check ports the ClassBody visitor: the message to report, if any.
fn (c &Checker) nec_check(body C.TSNode, o NecOptions) ?string {
	members := cm_members(body)
	if members.len == 0 {
		return if o.allow_empty { none } else { 'empty' }
	}
	mut only_static := true
	mut only_constructor := true
	for member in members {
		kind := cm_type(member)
		if kind == 'MethodDefinition' && c.cm_method_kind(member) == 'constructor' {
			if cm_parameters(member).any(cm_is_parameter_property(it)) {
				only_constructor = false
				only_static = false
			}
		} else {
			only_constructor = false
			// A static block keeps the class static-only.
			if (kind in ['PropertyDefinition', 'MethodDefinition', 'AccessorProperty']
				&& !cm_is_static(member)) || kind in ['TSIndexSignature', 'TSAbstractPropertyDefinition',
				'TSAbstractMethodDefinition', 'TSAbstractAccessorProperty'] {
				only_static = false
			}
		}
		if !(only_static || only_constructor) {
			break
		}
	}
	if only_constructor {
		return if o.allow_constructor_only { none } else { 'onlyConstructor' }
	}
	return if only_static && !o.allow_static_only { 'onlyStatic' } else { none }
}

// nec_report_node is the id of a ClassDeclaration that has one, or the class itself (a
// ClassExpression, or the ClassDeclaration of `export default class {}`, which starts at `class`).
fn nec_report_node(class C.TSNode) C.TSNode {
	is_declaration := node_kind(class) in ['class_declaration', 'abstract_class_declaration']
		|| node_kind(node_parent(class) or { class }) == 'export_statement'
	if is_declaration {
		if id := node_field(class, 'name') {
			return id
		}
	}
	return class
}
