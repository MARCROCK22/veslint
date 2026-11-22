module rules

import estree
import time

// Port of the `vue/no-shared-component-data` rule of eslint-plugin-vue 10.12.1 (no options): the
// `data` of a component that is not a function (or an identifier), with the fix that wraps it in
// one.

const vue_no_shared_component_data_messages = {
	'dataPropertyMustBeFunction': '`data` property in component must be a function.'
}

fn (mut c Checker) lint_vue_no_shared_component_data(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for obj in s.objects_of(vue_component_object_types) {
		stats.checked++
		finding := c.vue_data_function_finding(t, obj, 'dataPropertyMustBeFunction') or { continue }
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_data_function_finding is the report of no-shared-component-data and
// no-deprecated-data-object-declaration: the first `data` property whose value is not a function
// or an identifier, with the fix `function() {\nreturn …;\n}` around the value and the
// parentheses around it.
fn (mut c Checker) vue_data_function_finding(t &estree.EsTree, obj int, message_id string) ?Finding {
	invalid := vue_find_property(t, obj, 'data', fn [t] (p int) bool {
		return t.typ(vue_property_value(t, p)) !in [.function_expression, .arrow_function_expression,
			.identifier]
	})
	if invalid < 0 {
		return none
	}
	value := vue_property_value(t, invalid)
	tokens := c.un_tokens(t)
	mut first := un_first_token(t, tokens, value, 0) or { return none }
	mut last := un_last_token(t, tokens, value) or { return none }
	for {
		prev := tokens.before(first.start, false) or { break }
		next := tokens.after(last.end, false) or { break }
		if c.src[prev.start..prev.end] == '(' && c.src[next.start..next.end] == ')' {
			first = prev
			last = next
		} else {
			break
		}
	}
	return c.with_fixes(Finding{
		stmt:       c.es_tree_position(t, invalid)
		message_id: message_id
	}, [fix_insert_at(first.start, 'function() {\nreturn '), fix_insert_at(last.end, ';\n}')]) or {
		return none
	}
}
