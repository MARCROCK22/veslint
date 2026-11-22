module rules

import json2
import jsregexp
import time
import treesitter { node_kind, node_start }

// Port of the `no-empty-object-type` rule of typescript-eslint 8.72.2, with its options
// `allowInterfaces`, `allowObjectTypes` and `allowWithName`, and its suggestions, on the ESTree
// (the scope of an interface from the scope tree).

const neot_messages = {
	'noEmptyInterface':               'An empty interface declaration allows any non-nullish value, including literals like `0` and `""`.\n- If that\'s what you want, disable this lint rule with an inline comment or configure the \'{{ option }}\' rule option.\n- If you want a type meaning "any object", you probably want `object` instead.\n- If you want a type meaning "any value", you probably want `unknown` instead.'
	'noEmptyInterfaceWithSuper':      'An interface declaring no members is equivalent to its supertype.'
	'noEmptyObject':                  'The `{}` ("empty object") type allows any non-nullish value, including literals like `0` and `""`.\n- If that\'s what you want, disable this lint rule with an inline comment or configure the \'{{ option }}\' rule option.\n- If you want a type meaning "any object", you probably want `object` instead.\n- If you want a type meaning "any value", you probably want `unknown` instead.'
	'replaceEmptyInterface':          'Replace empty interface with `{{replacement}}`.'
	'replaceEmptyInterfaceWithSuper': 'Replace empty interface with a type alias.'
	'replaceEmptyObjectType':         'Replace `{}` with `{{replacement}}`.'
}

struct NeotOptions {
	allow_interfaces   string
	allow_object_types string
	allow_with_name    ?jsregexp.JsRegex
}

fn neot_options(options []json2.Any) !NeotOptions {
	o := option_object(no_empty_object_type, options, ['allowInterfaces', 'allowObjectTypes',
		'allowWithName'])!
	mut allow_with_name := ?jsregexp.JsRegex(none)
	if value := o.values['allowWithName'] {
		if value !is string {
			return error('option `allowWithName` of `${no_empty_object_type}` must be a string')
		}
		pattern := value as string
		if pattern != '' {
			allow_with_name = jsregexp.js_regex_new(pattern, 'u')!
		}
	}
	return NeotOptions{
		allow_interfaces:   o.string_value('allowInterfaces', ['always', 'never', 'with-single-extends'])!
		allow_object_types: o.string_value('allowObjectTypes', ['always', 'never'])!
		allow_with_name:    allow_with_name
	}
}

fn (o &NeotOptions) allowed_name(name string) !bool {
	tester := o.allow_with_name or { return false }
	return tester.test(utf16_units(name))!
}

fn (mut c Checker) lint_no_empty_object_type(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := neot_options(c.rule_options(no_empty_object_type))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	mut checked := 0
	for i, node in t.nodes {
		if node.typ == .ts_interface_declaration && o.allow_interfaces != 'always' {
			checked++
			id := t.node(i, .id) or { continue }
			name := t.string_of(id, .name) or { '' }
			if o.allowed_name(name)! {
				continue
			}
			extend := t.list(i, .extends_) or { []int{} }
			members := if body := t.node(i, .body) { t.list(body, .body) or { []int{} } } else { []int{} }
			if members.len != 0 || (extend.len == 1 && o.allow_interfaces == 'with-single-extends')
				|| extend.len > 1 {
				continue
			}
			// Merged with a class or another interface of its scope.
			tree := c.scope_tree(root)
			mut merged := false
			if node.has_ts {
				variable := tree.own_variable(tree.get_scope(node.ts), name)
				if variable >= 0 {
					merged = tree.variables[variable].defs.any(node_start(it.node) != node_start(node.ts)
						&& ((it.kind == .class_name
						&& node_kind(it.node) in ['class_declaration', 'abstract_class_declaration'])
						|| (it.kind == .type_definition && node_kind(it.node) == 'interface_declaration')))
				}
			}
			is_default_export := node.parent >= 0 && t.typ(node.parent) == .export_default_declaration
			should_suggest := !merged && !is_default_export
			id_text := c.src[t.nodes[id].start..t.nodes[id].end]
			type_param := if type_parameters := t.node(i, .type_parameters) {
				c.src[t.nodes[type_parameters].start..t.nodes[type_parameters].end]
			} else {
				''
			}
			position := c.position_range(t.nodes[id].start, t.nodes[id].end)
			if extend.len == 0 {
				mut suggestions := []Suggestion{}
				if should_suggest {
					for replacement in ['object', 'unknown'] {
						_, suggestion := c.suggestion('replaceEmptyInterface', {
							'replacement': replacement
						}, [
							fix_replace_range(node.start, node.end, 'type ${id_text}${type_param} = ${replacement}'),
						])!
						suggestions << suggestion
					}
				}
				findings << Finding{
					stmt:        position
					message_id:  'noEmptyInterface'
					data:        {
						'option': 'allowInterfaces'
					}
					suggestions: suggestions
				}
				continue
			}
			mut suggestions := []Suggestion{}
			if should_suggest {
				extended := c.src[t.nodes[extend[0]].start..t.nodes[extend[0]].end]
				_, suggestion := c.suggestion('replaceEmptyInterfaceWithSuper', map[string]string{},
					[
					fix_replace_range(node.start, node.end, 'type ${id_text}${type_param} = ${extended}'),
				])!
				suggestions << suggestion
			}
			findings << Finding{
				stmt:        position
				message_id:  'noEmptyInterfaceWithSuper'
				suggestions: suggestions
			}
		} else if node.typ == .ts_type_literal && o.allow_object_types != 'always' {
			checked++
			members := t.list(i, .members) or { []int{} }
			parent := node.parent
			if members.len > 0 || (parent >= 0 && t.typ(parent) == .ts_intersection_type) {
				continue
			}
			if parent >= 0 && t.typ(parent) == .ts_type_alias_declaration {
				if id := t.node(parent, .id) {
					if o.allowed_name(t.string_of(id, .name) or { '' })! {
						continue
					}
				}
			}
			mut suggestions := []Suggestion{}
			for replacement in ['object', 'unknown'] {
				_, suggestion := c.suggestion('replaceEmptyObjectType', {
					'replacement': replacement
				}, [fix_replace_range(node.start, node.end, replacement)])!
				suggestions << suggestion
			}
			findings << Finding{
				stmt:        c.position_range(node.start, node.end)
				message_id:  'noEmptyObject'
				data:        {
					'option': 'allowObjectTypes'
				}
				suggestions: suggestions
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}
