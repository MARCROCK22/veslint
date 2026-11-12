module rules

import json2
import time
import tsgo { TypeResponse }
import treesitter { first_named_child, named_children, node_field, node_kind, node_parent, nodes_of_kind, position_of }

// Port of the `restrict-template-expressions` rule of typescript-eslint 8.62.0, with its options
// (of `allow`, bare names and `from: "lib"` ones).

const rte_messages = {
	'invalidType': 'Invalid type "{{type}}" of template literal expression.'
}

struct RteOptions {
	allow_any     bool
	allow_array   bool
	allow_boolean bool
	allow_nullish bool
	allow_number  bool
	allow_regexp  bool
	allow_never   bool
	allow         []TypeSpecifier
}

fn rte_options(options []json2.Any) !RteOptions {
	o := option_object(restrict_template_expressions, options, ['allowAny', 'allowArray', 'allowBoolean',
		'allowNullish', 'allowNumber', 'allowRegExp', 'allowNever', 'allow'])!
	return RteOptions{
		allow_any:     o.bool_value('allowAny')!
		allow_array:   o.bool_value('allowArray')!
		allow_boolean: o.bool_value('allowBoolean')!
		allow_nullish: o.bool_value('allowNullish')!
		allow_number:  o.bool_value('allowNumber')!
		allow_regexp:  o.bool_value('allowRegExp')!
		allow_never:   o.bool_value('allowNever')!
		allow:         o.specifiers('allow')!
	}
}

fn (mut c Checker) lint_restrict_template_expressions(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	options := rte_options(c.rule_options(restrict_template_expressions))!
	mut expressions := []C.TSNode{}
	mut awaited := []C.TSNode{} // templates after an `await`, which TypeScript may read as tagged
	mut spans := []Span{}
	for template in c.nodes_of_kind(root, c'template_string') {
		// Tagged templates are not checked.
		if parent := node_parent(template) {
			kind := node_kind(parent)
			if kind == 'call_expression' {
				if args := node_field(parent, 'arguments') {
					if node_key(args) == node_key(template) {
						continue
					}
				}
			} else if kind == 'await_expression' {
				awaited << parent
				spans << node_span(parent)
			}
		}
		for sub in named_children(template) {
			if node_kind(sub) != 'template_substitution' {
				continue
			}
			expression := unwrap_parens(first_named_child(sub) or { continue })
			expressions << expression
			spans << node_span(expression)
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut tagged := map[u64]bool{}
	for a in awaited {
		if c.await_reading(a) == .tagged_template {
			tagged[node_key(a)] = true
		}
	}
	mut findings := []Finding{}
	for expression in expressions {
		if tagged.len > 0 {
			template := node_parent(node_parent(expression) or { continue }) or { continue }
			await := node_parent(template) or { template }
			if node_key(await) in tagged {
				continue
			}
		}
		t := c.node_type(expression) or { continue }
		constrained := c.constrained(t)!
		if !c.rte_valid(constrained, options, 0)! {
			findings << Finding{
				stmt:       position_of(expression)
				message_id: 'invalidType'
				data:       {
					'type': c.type_string(constrained)!
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += expressions.len
	return findings
}

// rte_valid ports recursivelyCheckType: a union is valid if all its parts are; an intersection, if
// any part is.
fn (mut c Checker) rte_valid(t TypeResponse, o RteOptions, depth int) !bool {
	if depth > max_rte_depth {
		return true
	}
	if t.flags & type_flag_union != 0 {
		for part in c.members_of(t)! {
			if !c.rte_valid(part, o, depth + 1)! {
				return false
			}
		}
		return true
	}
	if t.flags & type_flag_intersection != 0 {
		for part in c.members_of(t)! {
			if c.rte_valid(part, o, depth + 1)! {
				return true
			}
		}
		return false
	}
	flags := t.flags
	if flags & type_flag_string_like != 0 || (o.allow_any && flags & type_flag_any != 0)
		|| (o.allow_boolean && flags & type_flag_boolean_like != 0)
		|| (o.allow_nullish && flags & (type_flag_null | type_flag_undefined) != 0)
		|| (o.allow_number && flags & (type_flag_number_like | type_flag_bigint_like) != 0)
		|| (o.allow_never && flags & type_flag_never != 0) {
		return true
	}
	if o.allow_array && (c.is_array(t)! || c.is_tuple(t)!) {
		element := c.number_index_type(t)!
		if !element.is_null() && c.rte_valid(element, o, depth + 1)! {
			return true
		}
	}
	if o.allow_regexp && c.type_name(t, 0)! == 'RegExp' {
		return true
	}
	mut seen := map[int]bool{}
	return c.matches_type_or_base_type(t, o.allow, mut seen)!
}

// max_rte_depth cuts recursive types (`type R = R[]` with allowArray), on which typescript-eslint
// does not terminate.
const max_rte_depth = 100
