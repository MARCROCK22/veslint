module rules

import estree
import time
import x.json2

// Port of the `@stylistic/exp-jsx-props-style` rule of @stylistic/eslint-plugin 5.10.0
// (experimental, rules/jsx-props-style), with its options (`singleLine.maxItems`,
// `multiLine.minItems` and `multiLine.maxItemsPerLine`) and its fixes: the line breaks between the
// attributes of a JSX opening element.

const sjps_messages = {
	'shouldWrap':    'Prop `{{prop}}` must be placed on a new line'
	'shouldNotWrap': 'Prop `{{prop}}` should not be placed on a new line'
}

// SjpsOptions: `max_items` is `max_i32` for `Number.POSITIVE_INFINITY`.
struct SjpsOptions {
	max_items          int
	min_items          int
	max_items_per_line int
}

fn sjps_options(given []json2.Any) !SjpsOptions {
	options := sty_options(given, [
		json2.Any({
			'singleLine': json2.Any({
				'maxItems': json2.Any(json2.Null{})
			})
			'multiLine':  json2.Any({
				'minItems':        json2.Any(0)
				'maxItemsPerLine': json2.Any(1)
			})
		}),
	])
	object := sty_option_object(options, 0)
	single_line := sls_object(object['singleLine'] or { json2.Any(json2.Null{}) })
	multi_line := sls_object(object['multiLine'] or { json2.Any(json2.Null{}) })
	number := fn (object map[string]json2.Any, key string) int {
		value := object[key] or { return max_i32 }
		return if value is json2.Null { max_i32 } else { value.int() }
	}
	return SjpsOptions{
		max_items:          number(single_line, 'maxItems')
		min_items:          number(multi_line, 'minItems')
		max_items_per_line: number(multi_line, 'maxItemsPerLine')
	}
}

fn (mut c Checker) lint_stylistic_exp_jsx_props_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := sjps_options(c.rule_options(stylistic_exp_jsx_props_style))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave || t.typ(step.node) != .jsx_opening_element {
			continue
		}
		stats.checked++
		c.sjps_check(t, tokens, step.node, options, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sjps_check ports the JSXOpeningElement listener.
fn (c &Checker) sjps_check(t &estree.EsTree, tokens &SourceTokens, node int, options SjpsOptions, mut findings []Finding) {
	attrs := t.list(node, .attributes) or { return }
	if attrs.len == 0 {
		return
	}
	need_wrap := if sty_same_line_offsets(t, t.nodes[node].start, t.nodes[node].end) {
		attrs.len > options.max_items
	} else {
		attrs.len >= options.min_items
			&& !sty_same_line_offsets(t, t.nodes[node].start, t.nodes[attrs[0]].start)
	}
	max_per_line := if need_wrap { options.max_items_per_line } else { max_i32 }
	mut items_on_current_line := 0
	for i, current in attrs {
		prev := if i == 0 {
			t.node(node, .type_arguments) or { t.node(node, .name) or { return } }
		} else {
			attrs[i - 1]
		}
		if sty_same_line_offsets(t, t.nodes[prev].end, t.nodes[current].start) {
			items_on_current_line++
			if !need_wrap {
				continue
			}
			if i == 0 {
				findings << c.sjps_report(t, tokens, node, current, prev, i, 'shouldWrap', '\n')
			} else if items_on_current_line > max_per_line {
				findings << c.sjps_report(t, tokens, node, current, prev, i, 'shouldWrap', '\n')
				items_on_current_line = 1
			}
		} else {
			items_on_current_line = 1
			if need_wrap {
				continue
			}
			findings << c.sjps_report(t, tokens, node, current, prev, i, 'shouldNotWrap', ' ')
		}
	}
}

// sjps_report ports reportShouldWrap and reportShouldNotWrap: the fix replaces what is between the
// token before the attribute (getPrevToken) and the attribute, unless there are comments.
fn (c &Checker) sjps_report(t &estree.EsTree, tokens &SourceTokens, node int, current int, prev int, i int, message_id string, text string) Finding {
	prev_end := if i == 0 {
		(tokens.before(t.nodes[current].start, false) or { SourceToken{} }).end
	} else {
		(un_last_token(t, tokens, prev) or { SourceToken{} }).end
	}
	has_fix := !tokens.comments_exist_between(prev_end, t.nodes[current].start)
	return Finding{
		stmt:       c.position_range(t.nodes[current].start, t.nodes[current].end)
		message_id: message_id
		data:       {
			'prop': c.sjps_prop_name(t, current)
		}
		has_fix:    has_fix
		fix:        if has_fix {
			fix_replace_range(prev_end, t.nodes[current].start, text)
		} else {
			Fix{}
		}
	}
}

// sjps_prop_name ports getPropName.
fn (c &Checker) sjps_prop_name(t &estree.EsTree, prop int) string {
	if t.typ(prop) == .jsx_spread_attribute {
		argument := t.node(prop, .argument) or { return '' }
		return c.src[t.nodes[argument].start..t.nodes[argument].end]
	}
	name := t.node(prop, .name) or { return '' }
	if t.typ(name) == .jsx_namespaced_name {
		namespace := t.node(name, .namespace) or { return '' }
		local := t.node(name, .name) or { return '' }
		return '${t.string_of(namespace, .name) or { '' }}:${t.string_of(local, .name) or { '' }}'
	}
	return t.string_of(name, .name) or { '' }
}
