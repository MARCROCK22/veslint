module rules

import estree
import time

// Port of the `unicorn/prefer-array-flat-map` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fixes and suggestions.

const upafm_messages = {
	'prefer-array-flat-map':                            'Prefer `.flatMap(…)` over `.map(…).flat()`.'
	'prefer-array-flat-map/suggestion':                 'Replace `.map(…).flat()` with `.flatMap(…)`.'
	'prefer-array-flat-map/filter-flat-map':            'Prefer a single `.flatMap(…)` over `.filter(…).flatMap(…)`.'
	'prefer-array-flat-map/filter-flat-map-suggestion': 'Replace `.filter(…).flatMap(…)` with a single `.flatMap(…)`.'
}

// upafm_is_simple_callback ports isSimpleUntypedSingleParameterArrowCallback.
fn upafm_is_simple_callback(t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) != .arrow_function_expression || (t.flag(node, .async) or { false })
		|| t.node(node, .return_type) != none || t.node(node, .type_parameters) != none {
		return false
	}
	params := t.list(node, .params) or { return false }
	if params.len != 1 || t.typ(params[0]) != .identifier || (t.flag(params[0], .optional) or { false })
		|| t.node(params[0], .type_annotation) != none {
		return false
	}
	return t.typ(t.node(node, .body) or { return false }) != .block_statement
}

// upafm_is_safe_map_callback ports isSafeMapCallback: a fresh array literal result cannot be
// changed by a later callback, and a body without side effects cannot change an earlier result.
fn upafm_is_safe_map_callback(t &estree.EsTree, node int) bool {
	if node >= 0 && t.typ(node) == .arrow_function_expression
		&& t.typ(t.node(node, .body) or { -1 }) == .array_expression {
		return true
	}
	return unb_is_side_effect_free_function(t, node)
}

// upafm_conditional_test_text ports getConditionalTestText: the text of the test of a conditional.
fn (c &Checker) upafm_conditional_test_text(t &estree.EsTree, tokens &SourceTokens, node int) string {
	if c.un_is_parenthesized(t, tokens, node) {
		return c.un_parenthesized_text(t, tokens, node)
	}
	text := c.un_text(t, node)
	return if t.typ(node) in [.arrow_function_expression, .assignment_expression, .class_expression,
		.conditional_expression, .function_expression, .object_expression, .sequence_expression,
		.ts_as_expression, .ts_non_null_expression, .ts_satisfies_expression, .ts_type_assertion,
		.yield_expression] {
		'(${text})'
	} else {
		text
	}
}

// upafm_filter_flat_map reports `.filter(x => test).flatMap(x => [a, b])`.
fn (mut c Checker) upafm_filter_flat_map(t &estree.EsTree, tokens &SourceTokens, node int, mut ctx UnbTypeContext) ?Finding {
	if !un_is_method_call(t, node,
		methods:          ['flatMap']
		arguments_length: 1
		optional_call:    false
		optional_member:  false
		computed:         false
	) || unb_has_type_arguments(t, node) {
		return none
	}
	callee := t.node(node, .callee)?
	filter := t.node(callee, .object)?
	if !un_is_method_call(t, filter,
		methods:          ['filter']
		arguments_length: 1
		optional_call:    false
		optional_member:  false
		computed:         false
	) || unb_has_type_arguments(t, filter) {
		return none
	}
	array := t.node(t.node(filter, .callee)?, .object)?
	if unb_has_optional_chain_element(t, array)
		|| c.unb_is_known_non_target(t, array, unb_indexed_collection_options(), mut ctx) {
		return none
	}
	filter_callback := (t.list(filter, .arguments)?)[0]
	flat_map_callback := (t.list(node, .arguments)?)[0]
	if !upafm_is_simple_callback(t, filter_callback) || !upafm_is_simple_callback(t, flat_map_callback) {
		return none
	}
	body := t.node(flat_map_callback, .body)?
	if t.typ(body) != .array_expression || (t.list(body, .elements) or { []int{} }).len <= 1 {
		return none
	}
	filter_parameter := (t.list(filter_callback, .params)?)[0]
	flat_map_parameter := (t.list(flat_map_callback, .params)?)[0]
	if t.string_of(filter_parameter, .name)? != t.string_of(flat_map_parameter, .name)? {
		return none
	}
	array_text := c.unb_member_object_text(t, tokens, array, node)
	predicate := c.upafm_conditional_test_text(t, tokens, t.node(filter_callback, .body)?)
	text := '${array_text}.flatMap(${c.un_text(t, filter_parameter)} => ${predicate} ? ${c.un_text(t,
		body)} : [])'
	property := t.node(callee, .property)?
	mut finding := Finding{
		stmt:       c.es_tree_position(t, property)
		message_id: 'prefer-array-flat-map/filter-flat-map'
	}
	// getCommentSafeProblem
	if !c.unb_would_remove_comments(tokens, unb_node_range(t, node), [], false) {
		finding = Finding{
			...finding
			suggestions: [
				Suggestion{
					message_id: 'prefer-array-flat-map/filter-flat-map-suggestion'
					fix:        fix_replace_range(t.nodes[node].start, t.nodes[node].end, text)
				},
			]
		}
	}
	return finding
}

fn (mut c Checker) lint_unicorn_prefer_array_flat_map(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := &UnbTypeContext{
		root:     root
		abs_path: abs_path
		stats:    unsafe { &stats }
	}
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if finding := c.upafm_filter_flat_map(t, tokens, node, mut ctx) {
			findings << finding
			continue
		}
		if !un_is_method_call(t, node, methods: ['flat'], optional_call: false, optional_member: false) {
			continue
		}
		arguments := t.list(node, .arguments) or { []int{} }
		if !(arguments.len == 0 || (arguments.len == 1 && t.typ(arguments[0]) == .literal
			&& un_raw(t, arguments[0]) == '1')) {
			continue
		}
		map_call := t.node(t.node(node, .callee) or { continue }, .object) or { continue }
		if !un_is_method_call(t, map_call, methods: ['map'], optional_call: false) {
			continue
		}
		map_callee := t.node(map_call, .callee) or { continue }
		receiver := t.node(map_callee, .object) or { continue }
		if un_is_node_matches(t, receiver, ['React.Children', 'Children'])
			|| c.unb_should_skip_known_non_array_receiver(t, receiver, mut ctx) {
			continue
		}
		map_property := t.node(map_callee, .property) or { continue }
		mut finding := Finding{
			stmt:       c.position_range(t.nodes[map_property].start, t.nodes[node].end)
			message_id: 'prefer-array-flat-map'
		}
		// The type arguments of `.map` would be wrong for `flatMap`, and those of `.flat()` would
		// be lost.
		if !c.unb_would_remove_comments(tokens, unb_node_range(t, node), [
			unb_node_range(t, map_call),
		], false) && !unb_has_type_arguments(t, node) && !unb_has_type_arguments(t, map_call) {
			mut fixes := c.un_remove_method_call(t, tokens, node)
			fixes << fix_replace_range(t.nodes[map_property].start, t.nodes[map_property].end,
				'flatMap')
			has_fix, fix := c.merge_fixes(fixes)!
			// `flatMap()` flattens each result at once while `.map().flat()` waits for every
			// callback, so a callback with side effects only gets a suggestion.
			map_arguments := t.list(map_call, .arguments) or { []int{} }
			if upafm_is_safe_map_callback(t, if map_arguments.len > 0 { map_arguments[0] } else { -1 }) {
				finding = Finding{
					...finding
					has_fix: has_fix
					fix:     fix
				}
			} else {
				finding = Finding{
					...finding
					suggestions: [
						Suggestion{
							message_id: 'prefer-array-flat-map/suggestion'
							fix:        fix
						},
					]
				}
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
