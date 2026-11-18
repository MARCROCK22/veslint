module rules

import estree
import json2
import jsregexp
import time

// Port of the `vue/sort-keys` rule of eslint-plugin-vue 10.12.1 (options: "asc" or "desc", and
// `{caseSensitive, ignoreChildrenOf, ignoreGrandchildrenOf, minKeys, natural,
// allowLineSeparatedGroups}`): ESLint's sort-keys, but the keys of a Vue object, of the objects
// of `ignoreChildrenOf` options (`model`) and the children of `ignoreGrandchildrenOf` options
// (`computed`, `directives`, `inject`, `props`, `watch`) are not checked.

const vue_sort_keys_messages = {
	'sortKeys': "Expected object keys to be in {{natural}}{{insensitive}}{{order}}ending order. '{{thisName}}' should be before '{{prevName}}'."
}

struct VskOptions {
	order                       string
	ignore_children_of          []string
	ignore_grandchildren_of     []string
	insensitive                 bool
	min_keys                    f64
	natural                     bool
	allow_line_separated_groups bool
}

fn vue_sort_keys_options(options []json2.Any) !VskOptions {
	mut order := 'asc'
	if options.len > 0 {
		if options[0] is string && options[0] as string != '' {
			order = options[0] as string
		}
	}
	rest := if options.len > 1 { options[1..].clone() } else { []json2.Any{} }
	o := option_object(vue_sort_keys, rest, ['caseSensitive', 'ignoreChildrenOf',
		'ignoreGrandchildrenOf', 'minKeys', 'natural', 'allowLineSeparatedGroups']) or {
		option_object(vue_sort_keys, [], [])!
	}
	has_options := options.len > 1
	case_sensitive := o.values['caseSensitive'] or { json2.null }
	return VskOptions{
		order:                       order
		ignore_children_of:          if has_options && 'ignoreChildrenOf' in o.values {
			o.string_list('ignoreChildrenOf')!
		} else {
			['model']
		}
		ignore_grandchildren_of:     if has_options && 'ignoreGrandchildrenOf' in o.values {
			o.string_list('ignoreGrandchildrenOf')!
		} else {
			['computed', 'directives', 'inject', 'props', 'watch']
		}
		insensitive:                 case_sensitive is bool && !case_sensitive
		min_keys:                    if v := o.values['minKeys'] { json_number(v) } else { 2 }
		natural:                     o.bool_value('natural') or { false }
		allow_line_separated_groups: o.bool_value('allowLineSeparatedGroups') or { false }
	}
}

// vsk_valid_order is orderComparators[order + (insensitive ? 'I') + (natural ? 'N')].
fn vsk_valid_order(o &VskOptions, prev string, this string) bool {
	mut a := utf16_units(if o.order == 'desc' { this } else { prev })
	mut b := utf16_units(if o.order == 'desc' { prev } else { this })
	if o.insensitive {
		a = jsregexp.js_to_lower(a)
		b = jsregexp.js_to_lower(b)
	}
	if o.natural {
		return mord_natural_compare(a, b) <= 0
	}
	return vsk_compare_units(a, b) <= 0
}

// vsk_compare_units compares two strings as JavaScript does, by UTF-16 code units.
fn vsk_compare_units(a []u16, b []u16) int {
	n := if a.len < b.len { a.len } else { b.len }
	for i in 0 .. n {
		if a[i] != b[i] {
			return if a[i] < b[i] { -1 } else { 1 }
		}
	}
	return a.len - b.len
}

// VskState is the vueState of an object of the stack.
struct VskState {
mut:
	node             int
	prev_name        ?string
	prev_node        int = -1
	prev_blank_line  bool
	num_keys         int
	current_property int = -1
	is_vue_object    bool
	within           bool
	prop_name        string
	chain_level      int
	ignore           bool
}

fn (mut c Checker) lint_vue_sort_keys(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := vue_sort_keys_options(c.rule_options(vue_sort_keys))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut stack := []VskState{}
	for step in t.steps() {
		node := step.node
		typ := t.typ(node)
		if step.leave {
			if typ == .object_expression && stack.len > 0 {
				stack.pop()
			}
			continue
		}
		if typ == .object_expression {
			mut state := VskState{
				node:     node
				num_keys: (t.list(node, .properties) or { []int{} }).len
			}
			state.is_vue_object = s.object_type(node) != .none_
			if state.is_vue_object {
				state.within = true
				state.ignore = true
			} else if stack.len > 0 && stack.last().within && stack.last().current_property >= 0 {
				upper := stack.last()
				if vsk_is_property_chain(t, upper.current_property, node) {
					if upper.is_vue_object {
						state.prop_name = vue_static_property_name(t, upper.current_property) or {
							''
						}
						state.chain_level = 1
					} else {
						state.prop_name = upper.prop_name
						state.chain_level = upper.chain_level + 1
					}
					state.within = true
					if (state.chain_level == 1 && state.prop_name in o.ignore_children_of)
						|| (state.chain_level == 2 && state.prop_name in o.ignore_grandchildren_of) {
						state.ignore = true
					}
				}
			}
			stack << state
			continue
		}
		parent := t.nodes[node].parent
		if typ == .spread_element {
			if stack.len > 0 && parent >= 0 && t.typ(parent) == .object_expression {
				stack[stack.len - 1].prev_name = none
			}
			continue
		}
		if typ != .property || parent < 0 || t.typ(parent) != .object_expression || stack.len == 0 {
			continue
		}
		stats.checked++
		ti := stack.len - 1
		stack[ti].current_property = node
		if stack[ti].ignore {
			continue
		}
		prev_name := stack[ti].prev_name
		this_name := vsk_property_name(t, node)
		prev_node := stack[ti].prev_node
		mut blank := stack[ti].prev_blank_line
		if prev_node >= 0 && !blank {
			mut ends := [t.nodes[prev_node].end]
			mut starts := []int{}
			for token in tokens.inside(t.nodes[prev_node].end, t.nodes[node].start, true) {
				starts << token.start
				ends << token.end
			}
			starts << t.nodes[node].start
			for k, start in starts {
				start_line, _ := t.line_column(start)
				end_line, _ := t.line_column(ends[k])
				if start_line - end_line > 1 {
					blank = true
					break
				}
			}
		}
		stack[ti].prev_node = node
		mut has_name := false
		if name := this_name {
			stack[ti].prev_name = name
			has_name = true
		}
		if o.allow_line_separated_groups && blank {
			// A key without a name does not end the group: the blank line carries over.
			stack[ti].prev_blank_line = !has_name
			continue
		}
		prev := prev_name or { continue }
		this := this_name or { continue }
		if f64(stack[ti].num_keys) < o.min_keys {
			continue
		}
		if !vsk_valid_order(o, prev, this) {
			key := t.node(node, .key) or { node }
			findings << Finding{
				stmt:       c.es_tree_position(t, key)
				message_id: 'sortKeys'
				data:       {
					'thisName':    this
					'prevName':    prev
					'order':       o.order
					'insensitive': if o.insensitive { 'insensitive ' } else { '' }
					'natural':     if o.natural { 'natural ' } else { '' }
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vsk_property_name is getPropertyName: the static name, or the name of an Identifier key.
fn vsk_property_name(t &estree.EsTree, node int) ?string {
	if name := vue_static_property_name(t, node) {
		return name
	}
	key := t.node(node, .key) or { return none }
	return if t.typ(key) == .identifier { t.string_of(key, .name) } else { none }
}

// vsk_is_property_chain ports isPropertyChain: the object (through `as`) is the value of the
// property.
fn vsk_is_property_chain(t &estree.EsTree, prop int, node int) bool {
	mut value := node
	for t.nodes[value].parent >= 0 && t.typ(t.nodes[value].parent) == .ts_as_expression {
		value = t.nodes[value].parent
	}
	return t.nodes[value].parent == prop && vue_property_value(t, prop) == value
}
