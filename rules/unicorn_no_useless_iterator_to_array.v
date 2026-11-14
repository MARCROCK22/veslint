module rules

import estree
import time

// Port of the `unicorn/no-useless-iterator-to-array` rule of eslint-plugin-unicorn 79.0.0 (it has
// no options), with its fixes and suggestions.

const unuita_messages = {
	'iterable-accepting':            '`{{description}}` accepts an iterable, `.toArray()` is unnecessary.'
	'for-of':                        '`for…of`/`for await…of` can iterate over an iterable, `.toArray()` is unnecessary.'
	'yield-star':                    '`yield*` can delegate to an iterable, `.toArray()` is unnecessary.'
	'spread':                        'Spread works on iterables, `.toArray()` is unnecessary.'
	'iterator-method':               '`Iterator` has a `.{{method}}()` method, `.toArray()` is unnecessary.'
	'iterable-accepting/suggestion': 'Remove `.toArray()`.'
	'iterator-method/suggestion':    'Remove `.toArray()` and use `Iterator#{{method}}()`.'
}

// unuita_non_iterator_types are nonIteratorNodeTypes.
const unuita_non_iterator_types = [estree.NodeType.object_expression, .array_expression, .literal,
	.template_literal, .function_expression, .arrow_function_expression, .class_expression]

fn (mut c Checker) lint_unicorn_no_useless_iterator_to_array(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for node in 0 .. t.nodes.len {
		f := match t.typ(node) {
			.new_expression { c.unuita_new(mut ctx, node) }
			.call_expression { c.unuita_call(mut ctx, node) }
			.for_of_statement { c.unuita_for_of(mut ctx, node) }
			.yield_expression { c.unuita_yield(mut ctx, node) }
			.spread_element { c.unuita_spread(mut ctx, node) }
			else { continue }
		}
		stats.checked++
		if finding := f {
			findings << finding
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unuita_unwrap ports unwrapExpression of shared/iterator-helpers.js.
fn unuita_unwrap(t &estree.EsTree, from int) int {
	mut node := from
	for node >= 0 && (un_is_ts_expression_wrapper(t, node) || t.typ(node) == .chain_expression) {
		node = t.node(node, .expression) or { return node }
	}
	return node
}

// unuita_is_known_non_iterator_value ports isKnownNonIteratorValue: a literal, a function, a class,
// or an instance of a local class.
fn (mut c Checker) unuita_is_known_non_iterator_value(mut ctx UnCtx, from int) bool {
	t := ctx.t
	node := unuita_unwrap(t, from)
	if node < 0 {
		return false
	}
	if t.typ(node) in unuita_non_iterator_types {
		return true
	}
	if t.typ(node) != .new_expression {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	if t.typ(callee) != .identifier {
		return false
	}
	v := c.un_find_variable(ctx, callee)
	if v < 0 {
		return false
	}
	return c.scope_tree(ctx.root).variables[v].defs.any(it.kind == .class_name)
}

// unuita_is_known_non_iterator ports isKnownNonIterator: such a value, or a `const` binding
// initialized with one or with a call that returns an array or a string.
fn (mut c Checker) unuita_is_known_non_iterator(mut ctx UnCtx, from int) bool {
	if c.unuita_is_known_non_iterator_value(mut ctx, from) {
		return true
	}
	t := ctx.t
	node := unuita_unwrap(t, from)
	if node < 0 || t.typ(node) != .identifier {
		return false
	}
	initializer := c.un_const_initializer(ctx.root, t, node) or { return false }
	return c.unuita_is_known_non_iterator_value(mut ctx, initializer)
		|| un_is_method_call(t, initializer,
			methods:         ['toArray', 'slice', 'concat', 'split']
			optional_call:   false
			optional_member: false
		)
}

// unuita_is_to_array_call ports isToArrayCall.
fn (mut c Checker) unuita_is_to_array_call(mut ctx UnCtx, node int) bool {
	t := ctx.t
	if !un_is_method_call(t, node,
		methods:          ['toArray']
		arguments_length: 0
		optional_call:    false
		optional_member:  false
	) {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	return !c.unuita_is_known_non_iterator(mut ctx, t.node(callee, .object) or { return false })
}

// unuita_remove_fix ports getRemoveToArrayFix: none when a comment would go.
fn (c &Checker) unuita_remove_fix(ctx &UnCtx, call int) ?Fix {
	t := ctx.t
	callee := t.node(call, .callee)?
	object := t.node(callee, .object)?
	start, end := c.un_parenthesized_range(t, ctx.tokens, object)
	if un_would_remove_comments(ctx.tokens, t.nodes[call].start, t.nodes[call].end, [
		UnRange{start, end},
	]) {
		return none
	}
	_, fix := c.merge_fixes(c.un_remove_method_call(t, ctx.tokens, call)) or { return none }
	return fix
}

// unuita_suggestion ports getRemoveToArraySuggestion.
fn (c &Checker) unuita_suggestion(ctx &UnCtx, call int, message_id string, data map[string]string) []Suggestion {
	fix := c.unuita_remove_fix(ctx, call) or { return [] }
	return [Suggestion{
		message_id: message_id
		data:       data
		fix:        fix
	}]
}

// unuita_problem is the problem at the `toArray` of the call.
fn (c &Checker) unuita_problem(ctx &UnCtx, call int, message_id string, data map[string]string, fix ?Fix, suggestions []Suggestion) ?Finding {
	t := ctx.t
	callee := t.node(call, .callee)?
	property := t.node(callee, .property)?
	mut finding := Finding{
		stmt:        c.es_tree_position(t, property)
		message_id:  message_id
		data:        data
		suggestions: suggestions
	}
	if f := fix {
		finding = Finding{
			...finding
			has_fix: true
			fix:     f
		}
	}
	return finding
}

// unuita_iterable_argument is the problem of a call or `new` whose first argument is a `toArray()`
// call: fixed when it is the only argument, suggested otherwise (or always, `suggest_only`).
fn (mut c Checker) unuita_iterable_argument(mut ctx UnCtx, node int, description string, suggest_only bool) ?Finding {
	t := ctx.t
	arguments := t.list(node, .arguments) or { return none }
	call := arguments[0]
	if !c.unuita_is_to_array_call(mut ctx, call) {
		return none
	}
	fix := if arguments.len == 1 && !suggest_only { c.unuita_remove_fix(ctx, call) } else { none }
	suggestions := if arguments.len > 1 || suggest_only {
		c.unuita_suggestion(ctx, call, 'iterable-accepting/suggestion', map[string]string{})
	} else {
		[]Suggestion{}
	}
	return c.unuita_problem(ctx, call, 'iterable-accepting', {
		'description': description
	}, fix, suggestions)
}

// unuita_new is case 1: `new Set(iterator.toArray())`, `new Uint8Array(iterator.toArray())`.
fn (mut c Checker) unuita_new(mut ctx UnCtx, node int) ?Finding {
	t := ctx.t
	if !(un_is_new(t, node, names: ['Map', 'WeakMap', 'Set', 'WeakSet'], arguments_length: 1)
		|| un_is_new(t, node, names: un_typed_arrays, minimum_arguments: 1)) {
		return none
	}
	callee := t.node(node, .callee)?
	return c.unuita_iterable_argument(mut ctx, node, 'new ${t.string_of(callee, .name)?}(…)',
		false)
}

// unuita_static_description is `${node.callee.object.name}.${node.callee.property.name}(…)`.
fn unuita_static_description(t &estree.EsTree, node int) string {
	callee := t.node(node, .callee) or { return '' }
	object := t.node(callee, .object) or { return '' }
	property := t.node(callee, .property) or { return '' }
	return '${t.string_of(object, .name) or { '' }}.${t.string_of(property, .name) or { '' }}(…)'
}

// unuita_call is case 2: static methods (Array.from, Object.fromEntries, Promise.all…) and the
// methods an iterator has too.
fn (mut c Checker) unuita_call(mut ctx UnCtx, node int) ?Finding {
	t := ctx.t
	mut array_from := ['Array']
	array_from << un_typed_arrays
	if un_is_method_call(t, node,
		objects:           array_from
		methods:           ['from']
		minimum_arguments: 1
		optional_call:     false
		optional_member:   false
	) {
		if f := c.unuita_iterable_argument(mut ctx, node, unuita_static_description(t, node), false) {
			return f
		}
	}
	if un_is_method_call(t, node,
		objects:           ['Object']
		methods:           ['fromEntries']
		minimum_arguments: 1
		optional_call:     false
		optional_member:   false
	) {
		if f := c.unuita_iterable_argument(mut ctx, node, unuita_static_description(t, node), false) {
			return f
		}
	}
	// Suggestion only: passing an iterator can change a sync throw into an async rejection.
	if un_is_method_call(t, node,
		objects:          ['Promise']
		methods:          ['all', 'allSettled', 'any', 'race']
		arguments_length: 1
		optional_call:    false
		optional_member:  false
	) {
		if f := c.unuita_iterable_argument(mut ctx, node, unuita_static_description(t, node), true) {
			return f
		}
	}
	return c.unuita_iterator_method(mut ctx, node)
}

// unuita_can_observe_array_argument ports canObserveArrayArgument.
fn (c &Checker) unuita_can_observe_array_argument(ctx &UnCtx, from int, array_parameter_index int) bool {
	if from < 0 {
		return false
	}
	t := ctx.t
	callback := unuita_unwrap(t, from)
	if t.typ(callback) !in [.arrow_function_expression, .function_expression] {
		// A named callback is opaque here.
		return true
	}
	params := t.list(callback, .params) or { []int{} }
	if params.len > array_parameter_index
		|| (params.len > 0 && t.typ(params.last()) == .rest_element) {
		return true
	}
	return t.typ(callback) == .function_expression
		&& ctx.tokens.inside(t.nodes[callback].start, t.nodes[callback].end, false).any(it.kind == .identifier
			&& c.src[it.start..it.end] == 'arguments')
}

// unuita_iterator_method ports getIteratorMethodProblem.
fn (mut c Checker) unuita_iterator_method(mut ctx UnCtx, node int) ?Finding {
	t := ctx.t
	if !(un_is_method_call(t, node,
		methods:           ['every', 'find', 'forEach', 'some']
		maximum_arguments: 1
		optional_call:     false
		optional_member:   false
	) || un_is_method_call(t, node,
		methods:           ['reduce']
		minimum_arguments: 1
		maximum_arguments: 2
		optional_call:     false
		optional_member:   false
	)) {
		return none
	}
	callee := t.node(node, .callee)?
	to_array := t.node(callee, .object)?
	if !c.unuita_is_to_array_call(mut ctx, to_array) {
		return none
	}
	arguments := t.list(node, .arguments) or { []int{} }
	method := t.string_of(t.node(callee, .property)?, .name)?
	index := if method == 'reduce' { 3 } else { 2 }
	if c.unuita_can_observe_array_argument(ctx, if arguments.len > 0 { arguments[0] } else { -1 },
		index) {
		return none
	}
	data := {
		'method': method
	}
	return c.unuita_problem(ctx, to_array, 'iterator-method', data, none, c.unuita_suggestion(ctx,
		to_array, 'iterator-method/suggestion', data))
}

// unuita_for_of is case 3: `for (const x of iterator.toArray())`, a suggestion only.
fn (mut c Checker) unuita_for_of(mut ctx UnCtx, node int) ?Finding {
	right := ctx.t.node(node, .right)?
	if !c.unuita_is_to_array_call(mut ctx, right) {
		return none
	}
	return c.unuita_problem(ctx, right, 'for-of', map[string]string{}, none, c.unuita_suggestion(ctx,
		right, 'iterable-accepting/suggestion', map[string]string{}))
}

// unuita_yield is case 4: `yield* iterator.toArray()`, a suggestion only.
fn (mut c Checker) unuita_yield(mut ctx UnCtx, node int) ?Finding {
	t := ctx.t
	if !(t.flag(node, .delegate) or { false }) {
		return none
	}
	argument := t.node(node, .argument)?
	if !c.unuita_is_to_array_call(mut ctx, argument) {
		return none
	}
	return c.unuita_problem(ctx, argument, 'yield-star', map[string]string{}, none, c.unuita_suggestion(ctx,
		argument, 'iterable-accepting/suggestion', map[string]string{}))
}

// unuita_spread is case 5: `[...iterator.toArray()]`, `call(...iterator.toArray())`.
fn (mut c Checker) unuita_spread(mut ctx UnCtx, node int) ?Finding {
	t := ctx.t
	argument := t.node(node, .argument)?
	if !c.unuita_is_to_array_call(mut ctx, argument) {
		return none
	}
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) !in [.array_expression, .call_expression, .new_expression] {
		return none
	}
	return c.unuita_problem(ctx, argument, 'spread', map[string]string{}, c.unuita_remove_fix(ctx,
		argument), []Suggestion{})
}
