module rules

import json2
import time
import treesitter { Ident }

// Port of the `vue/block-order` rule of eslint-plugin-vue 10.12.1 (option `order`: selectors of
// top-level elements, by default [["script", "template"], "style"]): a top-level element that
// comes after one the order puts later, with the fix that moves it above that one.

const vue_block_order_messages = {
	'unexpected': "'<{{elementName}}{{elementAttributes}}>' should be above '<{{firstUnorderedName}}{{firstUnorderedAttributes}}>' on line {{line}}."
}

struct VboOrder {
	selector VselSelector
	index    int
}

fn vue_block_order_options(options []json2.Any) ![]VboOrder {
	o := option_object(vue_block_order, options, ['order'])!
	mut items := [][]string{}
	if value := o.values['order'] {
		if value !is []json2.Any {
			return error('option `order` of `${vue_block_order}` must be a list')
		}
		for item in value as []json2.Any {
			if item is string {
				items << [item]
			} else if item is []json2.Any {
				items << item.filter(it is string).map(it as string)
			}
		}
	} else {
		items = [['script', 'template'], ['style']]
	}
	mut out := []VboOrder{}
	for index, selectors in items {
		for selector in selectors {
			out << VboOrder{
				selector: vsel_parse(selector)
				index:    index
			}
		}
	}
	return out
}

struct VboElement {
	element int
	order   int // index in the orders
}

fn (mut c Checker) lint_vue_block_order(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	orders := vue_block_order_options(c.rule_options(vue_block_order))!
	mut findings := []Finding{}
	// parseSelector reports the selectors it cannot use, at line 0.
	for order in orders {
		if order.selector.error != '' {
			findings << Finding{
				stmt:       Ident{
					row:      -1
					end_byte: -1
				}
				message_id: 'error'
				text:       order.selector.error
				no_end:     true
			}
		}
	}
	if c.vue_has_invalid_eof() {
		return findings
	}
	doc := c.vue.doc
	elements := doc.nodes[0].children.filter(doc.nodes[it].typ == .v_element)
	mut with_order := []VboElement{}
	for element in elements {
		for k, order in orders {
			if c.vsel_test(&order.selector, element) {
				with_order << VboElement{element, k}
				break
			}
		}
	}
	for index, item in with_order {
		stats.checked++
		expected := orders[item.order].index
		mut first := -1
		for k in 0 .. index {
			other := with_order[k]
			if expected < orders[other.order].index
				&& (first < 0 || orders[other.order].index < orders[with_order[first].order].index) {
				first = k
			}
		}
		if first < 0 {
			continue
		}
		first_element := with_order[first].element
		element := item.element
		first_attributes := c.vbo_attribute_string(first_element)
		attributes := c.vbo_attribute_string(element)
		mut fixed := []int{}
		for it in elements {
			if it == first_element {
				fixed << element
				fixed << it
			} else if it != element {
				fixed << it
			}
		}
		mut fixes := []Fix{}
		for i := elements.len - 1; i >= 0; i-- {
			if elements[i] != fixed[i] {
				fixes << fix_replace_range(doc.nodes[elements[i]].start, doc.nodes[elements[i]].end,
					c.vue_vnode_text(fixed[i]))
			}
		}
		findings << c.with_fixes(c.vue_report_vnode(element, 'unexpected', {
			'elementName':              doc.nodes[element].name
			'elementAttributes':        if attributes != '' { ' ${attributes}' } else { '' }
			'firstUnorderedName':       doc.nodes[first_element].name
			'firstUnorderedAttributes': if first_attributes != '' {
				' ${first_attributes}'
			} else {
				''
			}
			'line':                     doc.loc(doc.nodes[first_element].start).line.str()
		}), fixes)!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vbo_attribute_string is getAttributeString: `name=value` of the attributes without an
// expression, separated by spaces.
fn (c &Checker) vbo_attribute_string(element int) string {
	doc := c.vue.doc
	mut parts := []string{}
	for a in doc.nodes[doc.nodes[element].start_tag].attributes {
		attr := &doc.nodes[a]
		if attr.value >= 0 && doc.nodes[attr.value].typ != .v_literal {
			parts << ''
			continue
		}
		name := if attr.directive { '[object Object]' } else { doc.nodes[attr.key].name }
		value := if attr.value >= 0 { doc.nodes[attr.value].text } else { '' }
		parts << if value != '' { '${name}=${value}' } else { name }
	}
	return parts.join(' ')
}
