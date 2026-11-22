module rules

import estree
import json2
import time

// Port of the `vue/order-in-components` rule of eslint-plugin-vue 10.12.1 (option `order`): a
// property of a Vue object (or of defineOptions) that comes after one the order puts later, with
// the fix that moves it above that one, or a suggestion when a property in between may have side
// effects.

const vue_order_in_components_messages = {
	'order':                  'The "{{name}}" property should be above the "{{firstUnorderedPropertyName}}" property on line {{line}}.'
	'reorderWithSideEffects': 'Manually move "{{name}}" property above "{{firstUnorderedPropertyName}}" property on line {{line}} (might break side effects).'
}

const voic_default_order = [['el'], ['name'], ['key'], ['parent'], ['functional'],
	['delimiters', 'comments'], ['components', 'directives', 'filters'], ['extends'], ['mixins'],
	['provide', 'inject'], ['ROUTER_GUARDS'], ['layout'], ['middleware'], ['validate'],
	['scrollToTop'], ['transition'], ['loading'], ['inheritAttrs'], ['model'], ['props', 'propsData'],
	['emits'], ['slots'], ['expose'], ['setup'], ['asyncData'], ['data'], ['fetch'], ['head'],
	['computed'], ['watch'], ['watchQuery'], ['LIFECYCLE_HOOKS'], ['methods'], ['template', 'render'],
	['renderError']]

const voic_lifecycle_hooks = ['beforeCreate', 'created', 'beforeMount', 'mounted', 'beforeUpdate',
	'updated', 'activated', 'deactivated', 'beforeUnmount', 'unmounted', 'beforeDestroy', 'destroyed',
	'renderTracked', 'renderTriggered', 'errorCaptured']
const voic_router_guards = ['beforeRouteEnter', 'beforeRouteUpdate', 'beforeRouteLeave']

// vue_order_in_components_options is the rule's orderMap: the position of each name (a string
// item names one property or a group, an array item several).
fn vue_order_in_components_options(options []json2.Any) !map[string]int {
	o := option_object(vue_order_in_components, options, ['order'])!
	mut order := [][]string{}
	mut is_list := []bool{}
	if value := o.values['order'] {
		if value !is []json2.Any {
			return error('option `order` of `${vue_order_in_components}` must be a list')
		}
		for item in value as []json2.Any {
			if item is string {
				order << [item]
				is_list << false
			} else if item is []json2.Any {
				order << item.filter(it is string).map(it as string)
				is_list << true
			} else {
				return error('an item of `order` of `${vue_order_in_components}` must be a string or a list')
			}
		}
	} else {
		order = voic_default_order.clone()
		is_list = order.map(it.len > 1)
	}
	mut out := map[string]int{}
	for i, group in order {
		mut expanded := group.clone()
		if !is_list[i] && group.len == 1 {
			if group[0] == 'LIFECYCLE_HOOKS' {
				expanded = voic_lifecycle_hooks.clone()
			} else if group[0] == 'ROUTER_GUARDS' {
				expanded = voic_router_guards.clone()
			}
		}
		for name in expanded {
			out[name] = i
		}
	}
	return out
}

struct VoicProperty {
	node int
	name string
}

fn (mut c Checker) lint_vue_order_in_components(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	order := vue_order_in_components_options(c.rule_options(vue_order_in_components))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut objects := s.objects_of(vue_all_object_types)
	for call in c.vue_macros_named(t, 'defineOptions') {
		args := t.list(call, .arguments) or { []int{} }
		if args.len > 0 && t.typ(args[0]) == .object_expression {
			objects << args[0]
		}
	}
	tokens := c.un_tokens(t)
	for obj in objects {
		stats.checked++
		c.voic_check_order(t, tokens, t.list(obj, .properties) or { []int{} }, order, mut
			findings)!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) voic_check_order(t &estree.EsTree, tokens &SourceTokens, nodes []int, order map[string]int, mut findings []Finding) ! {
	mut properties := []VoicProperty{}
	for p in nodes {
		if !vue_is_property(t, p) {
			continue
		}
		mut name := vue_static_property_name(t, p) or { '' }
		if name == '' {
			key := t.node(p, .key) or { -1 }
			if key >= 0 && t.typ(key) == .identifier {
				name = t.string_of(key, .name) or { '' }
			}
		}
		properties << VoicProperty{p, name}
	}
	position := fn [order] (name string) int {
		return order[name] or { -1 }
	}
	for i, property in properties {
		pos := position(property.name)
		if pos < 0 {
			continue
		}
		unordered := properties[..i].filter(position(it.name) > pos)
		if unordered.len == 0 {
			continue
		}
		sorted := vx6_v8_sort(unordered.len, fn [unordered, position] (a int, b int) int {
			return if position(unordered[a].name) > position(unordered[b].name) { 1 } else { -1 }
		})
		first := unordered[sorted[0]]
		line, _ := t.line_column(t.nodes[first.node].start)
		first_index := nodes.index(first.node)
		property_index := nodes.index(property.node)
		mut side_effects := false
		for k in first_index .. property_index + 1 {
			if !voic_is_not_side_effects_node(t, nodes[k]) {
				side_effects = true
				break
			}
		}
		data := {
			'name':                       property.name
			'firstUnorderedPropertyName': first.name
			'line':                       line.str()
		}
		fixes := c.voic_fix(t, tokens, property.node, first.node)
		finding := Finding{
			stmt:       c.es_tree_position(t, property.node)
			message_id: 'order'
			data:       data
		}
		if side_effects {
			ok, suggestion := c.suggestion('reorderWithSideEffects', data, fixes)!
			findings << Finding{
				...finding
				suggestions: if ok { [suggestion] } else { []Suggestion{} }
			}
		} else {
			findings << c.with_fixes(finding, fixes)!
		}
	}
}

// voic_fix is handleFix: remove the property (with its comma, or the comma before it) and write
// it after the token before the first unordered property.
fn (c &Checker) voic_fix(t &estree.EsTree, tokens &SourceTokens, property int, unordered int) []Fix {
	after := tokens.after(t.nodes[property].end, false) or { return [] }
	has_after_comma := c.src[after.start..after.end] == ','
	before := tokens.before(t.nodes[property].start, false) or { return [] }
	code_start := before.end
	code_end := if has_after_comma { after.end } else { t.nodes[property].end }
	remove_start := if has_after_comma { code_start } else { before.start }
	code := c.src[code_start..code_end] + if has_after_comma { '' } else { ',' }
	insert_target := tokens.before(t.nodes[unordered].start, false) or { return [] }
	return [fix_remove_range(remove_start, code_end), fix_insert_at(insert_target.end, code)]
}

const voic_binary_operators = ['+', '-', '*', '/', '%', '**', '&', '|', '^', '~', '<<', '>>', '>>>',
	'==', '!=', '===', '!==', '>', '>=', '<', '<=', 'in', 'instanceof']

// voic_is_not_side_effects_node ports isNotSideEffectsNode: every node under `node` is of a kind
// known to have no side effects (functions, identifiers, literals and `as` expressions end the
// walk of their branch).
fn voic_is_not_side_effects_node(t &estree.EsTree, node int) bool {
	match t.typ(node) {
		.function_expression, .identifier, .literal, .arrow_function_expression, .template_element,
		.ts_as_expression {
			return true
		}
		.property, .object_expression, .array_expression, .member_expression,
		.conditional_expression, .spread_element, .template_literal, .chain_expression {
		}
		.unary_expression {
			if (t.string_of(node, .operator) or { '' }) !in ['!', '~', '+', '-', 'typeof'] {
				return false
			}
		}
		.binary_expression {
			if (t.string_of(node, .operator) or { '' }) !in voic_binary_operators {
				return false
			}
		}
		.logical_expression {
			if (t.string_of(node, .operator) or { '' }) !in ['&&', '||', '??'] {
				return false
			}
		}
		else {
			return false
		}
	}
	for child in t.children(node) {
		if !voic_is_not_side_effects_node(t, child) {
			return false
		}
	}
	return true
}
