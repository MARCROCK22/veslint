module rules

import estree
import time

// Port of the `unicorn/no-useless-spread` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fixes and suggestions.

const unus_messages = {
	'spread-in-list':                         'Spread an {{argumentType}} literal in {{parentDescription}} is unnecessary.'
	'iterable-to-array':                      "`{{parentDescription}}` accepts an iterable as an argument, it's unnecessary to convert to an array."
	'iterable-to-array-in-for-of':            "`for…of` can iterate over an iterable, it's unnecessary to convert to an array."
	'iterable-to-array-in-yield-star':        "`yield*` can delegate to an iterable, it's unnecessary to convert to an array."
	'spread-in-collection-constructor':       '`{{constructorName}}` accepts a single iterable argument, spreading is misleading.'
	'spread-in-object-assign':                '`Object.assign(…)` source object with only spread properties is unnecessary.'
	'clone-array':                            'Unnecessarily cloning an array.'
	'suggestion/remove-object-assign-spread': 'Remove the object literal wrapper.'
	'suggestion/remove-iterable-array':       'Remove the array conversion.'
}

const unus_collection_constructors = ['Map', 'WeakMap', 'Set', 'WeakSet']
const unus_array_clone_methods = ['flat', 'slice', 'splice', 'toReversed', 'toSorted', 'toSpliced',
	'with']
const unus_type_checked_array_methods = ['flat', 'slice', 'splice', 'toReversed', 'toSorted',
	'toSpliced', 'with', 'filter', 'flatMap', 'map']

// unus_strong_precedence_types are strongPrecedenceNodeTypes of utils/is-strong-precedence-node.js.
const unus_strong_precedence_types = [estree.NodeType.array_expression, .call_expression,
	.chain_expression, .identifier, .import_expression, .literal, .member_expression, .new_expression,
	.super, .tagged_template_expression, .template_literal, .this_expression, .ts_non_null_expression]

fn (mut c Checker) lint_unicorn_no_useless_spread(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for node in 0 .. t.nodes.len {
		typ := t.typ(node)
		if typ !in [.array_expression, .object_expression, .new_expression] {
			continue
		}
		stats.checked++
		if typ in [.array_expression, .object_expression] {
			if f := c.unus_spread_in_list(t, tokens, node) {
				findings << f
			}
		}
		if typ == .object_expression {
			if f := c.unus_object_assign(t, tokens, node) {
				findings << f
			}
		}
		if typ == .new_expression {
			if f := c.unus_collection_constructor(t, node) {
				findings << f
			}
		}
		if typ == .array_expression {
			if f := c.unus_iterable_to_array(t, tokens, node) {
				findings << f
			}
			if f := c.unus_clone_array(mut ctx, node) {
				findings << f
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unus_is_single_array_spread ports isSingleArraySpread: `[...value]`.
fn unus_is_single_array_spread(t &estree.EsTree, node int) bool {
	if t.typ(node) != .array_expression {
		return false
	}
	elements := t.list(node, .elements) or { return false }
	return elements.len == 1 && elements[0] >= 0 && t.typ(elements[0]) == .spread_element
}

// unus_is_prototype_setter ports isPrototypeSetterProperty: `__proto__: value`.
fn unus_is_prototype_setter(t &estree.EsTree, property int) bool {
	if t.typ(property) != .property || (t.flag(property, .computed) or { false })
		|| (t.flag(property, .shorthand) or { false }) {
		return false
	}
	key := t.node(property, .key) or { return false }
	name := if t.typ(key) == .identifier {
		t.string_of(key, .name) or { '' }
	} else if t.typ(key) == .literal {
		es_tree_static_string_value(t, key) or { '' }
	} else {
		''
	}
	return name == '__proto__'
}

// unus_contains_super ports containsNode(node, context, node => node.type === 'Super').
fn unus_contains_super(t &estree.EsTree, node int) bool {
	if t.typ(node) == .super {
		return true
	}
	return t.children(node).any(unus_contains_super(t, it))
}

// unus_spread_in_list is the "useless spread in list" listener: `[...[a]]`, `f(...[a])`,
// `{...{a}}`.
fn (c &Checker) unus_spread_in_list(t &estree.EsTree, tokens &SourceTokens, node int) ?Finding {
	spread := t.nodes[node].parent
	if spread < 0 || t.typ(spread) != .spread_element || (t.node(spread, .argument) or { -1 }) != node {
		return none
	}
	container := t.nodes[spread].parent
	if container < 0 {
		return none
	}
	parent_type := t.typ(container)
	ok := if t.typ(node) == .object_expression {
		parent_type == .object_expression && spread in (t.list(container, .properties) or { []int{} })
	} else {
		(parent_type == .array_expression && spread in (t.list(container, .elements) or { []int{} }))
			|| (parent_type in [.call_expression, .new_expression]
				&& spread in (t.list(container, .arguments) or { []int{} }))
	}
	if !ok {
		return none
	}
	if t.typ(node) == .object_expression {
		properties := t.list(node, .properties) or { []int{} }
		// Flattening a method changes its home object, which determines `super` lookup.
		if properties.any(unus_is_prototype_setter(t, it)) || unus_contains_super(t, node) {
			return none
		}
	}
	spread_token := un_first_token(t, tokens, spread, 0)?
	description := match parent_type {
		.array_expression { 'array literal' }
		.object_expression { 'object literal' }
		else { 'arguments' }
	}
	mut finding := Finding{
		stmt:       c.position_range(spread_token.start, spread_token.end)
		message_id: 'spread-in-list'
		data:       {
			'argumentType':      if t.typ(node) == .array_expression { 'array' } else { 'object' }
			'parentDescription': description
		}
	}
	if parent_type == .new_expression && unus_is_single_array_spread(t, node)
		&& un_is_new(t, container,
			names:            unus_collection_constructors
			arguments_length: 1
			allow_spread:     true
		) {
		return finding
	}
	mut fixes := [fix_remove_range(spread_token.start, spread_token.end)]
	fixes << c.un_remove_parentheses(t, tokens, node)
	first := un_first_token(t, tokens, node, 0)?
	fixes << fix_remove_range(first.start, first.end)
	inside := tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
	last := inside.last()
	fixes << fix_remove_range(last.start, last.end)
	if inside.len >= 2 {
		penultimate := inside[inside.len - 2]
		if c.token_is(penultimate, ',') {
			fixes << fix_remove_range(penultimate.start, penultimate.end)
		}
	}
	// `[...[], 1]`
	if un_is_empty_array(t, node) || un_is_empty_object(t, node) {
		if next := tokens.after(t.nodes[spread].end, false) {
			if c.token_is(next, ',') {
				fixes << fix_remove_range(next.start, next.end)
			}
		}
	}
	if parent_type in [.call_expression, .new_expression] {
		// `call(...[foo, , bar])`: the holes become `undefined`.
		elements := t.list(node, .elements) or { []int{} }
		commas := c.unus_comma_tokens(t, tokens, node)
		for index, comma in commas {
			if elements[index] >= 0 {
				continue
			}
			if token := comma {
				fixes << fix_insert_at(token.start, 'undefined')
			}
		}
	}
	has_fix, fix := c.merge_fixes(fixes) or { return finding }
	finding = Finding{
		...finding
		has_fix: has_fix
		fix:     fix
	}
	return finding
}

// unus_comma_tokens ports getCommaTokens: the comma after each element (for the last one, a
// trailing comma or none).
fn (c &Checker) unus_comma_tokens(t &estree.EsTree, tokens &SourceTokens, array int) []?SourceToken {
	elements := t.list(array, .elements) or { return [] }
	inside := tokens.inside(t.nodes[array].start, t.nodes[array].end, false)
	mut out := []?SourceToken{}
	mut at := if inside.len > 0 { inside[0].end } else { t.nodes[array].start }
	for index, element in elements {
		if index == elements.len - 1 {
			if inside.len >= 2 && c.token_is(inside[inside.len - 2], ',') {
				out << inside[inside.len - 2]
			} else {
				out << none
			}
			continue
		}
		from := if element >= 0 { t.nodes[element].end } else { at }
		mut comma := ?SourceToken(none)
		mut position := from
		for {
			token := tokens.after(position, false) or { break }
			if c.token_is(token, ',') {
				comma = token
				break
			}
			position = token.end
		}
		out << comma
		if found := comma {
			at = found.end
		}
	}
	return out
}

// unus_unwrap_single_array_spread ports unwrapSingleArraySpread: `[...value]` becomes `value`.
fn (c &Checker) unus_unwrap_single_array_spread(t &estree.EsTree, tokens &SourceTokens, array int) []Fix {
	first_tokens := tokens.inside(t.nodes[array].start, t.nodes[array].end, false)
	if first_tokens.len < 3 {
		return []
	}
	opening := first_tokens[0]
	spread_token := first_tokens[1]
	third := first_tokens[2]
	keyword_parent := c.un_unparenthesized_keyword_argument_parent(t, tokens, array)
	keyword_type := if p := keyword_parent { t.typ(p) } else { estree.NodeType.program }
	if keyword_parent != none && keyword_type == .yield_expression
		&& !un_same_line(t, opening.start, third.start) {
		return []
	}
	mut fixes := [fix_remove_range(opening.start, opening.end)]
	elements := t.list(array, .elements) or { return [] }
	argument := t.node(elements[0], .argument) or { return [] }
	should_add_parentheses := !c.un_is_parenthesized(t, tokens, argument)
		&& (c.un_is_in_unparenthesized_new_callee(t, tokens, array)
			|| c.un_expression_start_needs_parens(t, tokens, argument, array)
			|| (t.typ(argument) !in unus_strong_precedence_types
				&& t.typ(un_unwrap_ts_expression(t, argument)) !in unus_strong_precedence_types))
	if should_add_parentheses {
		fixes << fix_insert_at(opening.end, '(')
	}
	fixes << fix_remove_range(spread_token.start, spread_token.end)
	closing := first_tokens.last()
	comma := first_tokens[first_tokens.len - 2]
	fixes << fix_remove_range(closing.start, closing.end)
	if should_add_parentheses {
		fixes << fix_insert_at(closing.start, ')')
	}
	if c.token_is(comma, ',') {
		fixes << fix_remove_range(comma.start, comma.end)
	}
	if keyword_parent != none && keyword_type in [.return_statement, .throw_statement]
		&& !un_same_line(t, opening.start, third.start) {
		fixes << c.un_add_parens_to_return_or_throw(t, tokens, keyword_parent)
		return fixes
	}
	fixes << c.un_fix_space_around_keyword(t, tokens, array)
	return fixes
}

// unus_object_assign is the `Object.assign()` listener: a source object with only spreads.
fn (c &Checker) unus_object_assign(t &estree.EsTree, tokens &SourceTokens, object int) ?Finding {
	properties := t.list(object, .properties) or { return none }
	if properties.len == 0 || !properties.all(t.typ(it) == .spread_element
		&& t.typ(t.node(it, .argument) or { -1 }) != .object_expression) {
		return none
	}
	call := t.nodes[object].parent
	if !un_is_method_call(t, call,
		objects:           ['Object']
		methods:           ['assign']
		minimum_arguments: 2
		optional_member:   false
		optional_call:     false
	) {
		return none
	}
	arguments := t.list(call, .arguments)?
	index := arguments.index(object)
	if index <= 0 || !arguments[..index].any(t.typ(it) != .spread_element) {
		return none
	}
	first := un_first_token(t, tokens, properties[0], 0)?
	mut finding := Finding{
		stmt:       c.position_range(first.start, first.end)
		message_id: 'spread-in-object-assign'
	}
	if tokens.comments_inside(t.nodes[object].start, t.nodes[object].end).len > 0 {
		return finding
	}
	text := properties.map(c.un_parenthesized_text(t, tokens, t.node(it, .argument) or { -1 })).join(', ')
	return Finding{
		...finding
		suggestions: [
			Suggestion{
				message_id: 'suggestion/remove-object-assign-spread'
				fix:        fix_replace_range(t.nodes[object].start, t.nodes[object].end, text)
			},
		]
	}
}

// unus_collection_constructor is the listener of a spread in a collection constructor:
// `new Set(...items)`.
fn (c &Checker) unus_collection_constructor(t &estree.EsTree, node int) ?Finding {
	if !un_is_new(t, node,
		names:            unus_collection_constructors
		arguments_length: 1
		allow_spread:     true
	) {
		return none
	}
	argument := (t.list(node, .arguments)?)[0]
	if t.typ(argument) != .spread_element
		|| t.typ(t.node(argument, .argument)?) == .array_expression {
		return none
	}
	callee := t.node(node, .callee)?
	return Finding{
		stmt:       c.es_tree_position(t, argument)
		message_id: 'spread-in-collection-constructor'
		data:       {
			'constructorName': 'new ${t.string_of(callee, .name) or { '' }}(…)'
		}
	}
}

// unus_iterable_to_array is the "useless iterable to array" listener: `new Set([...set])`,
// `for (const x of [...set])`, `yield* [...set]`.
fn (c &Checker) unus_iterable_to_array(t &estree.EsTree, tokens &SourceTokens, array int) ?Finding {
	if !unus_is_single_array_spread(t, array) {
		return none
	}
	parent := t.nodes[array].parent
	if parent < 0 {
		return none
	}
	ptyp := t.typ(parent)
	mut array_from := ['Array']
	array_from << un_typed_arrays
	is_target := (ptyp == .for_of_statement && (t.node(parent, .right) or { -1 }) == array)
		|| (ptyp == .yield_expression && (t.flag(parent, .delegate) or { false })
			&& (t.node(parent, .argument) or { -1 }) == array)
		|| ((un_is_new(t, parent, names: unus_collection_constructors, arguments_length: 1)
			|| un_is_method_call(t, parent,
				objects:          ['Promise']
				methods:          ['all', 'allSettled', 'any', 'race']
				arguments_length: 1
				optional_call:    false
				optional_member:  false
			) || un_is_method_call(t, parent,
			objects:          array_from
			methods:          ['from']
			arguments_length: 1
			optional_call:    false
			optional_member:  false
		) || un_is_method_call(t, parent,
			objects:          ['Object']
			methods:          ['fromEntries']
			arguments_length: 1
			optional_call:    false
			optional_member:  false
		)) && (t.list(parent, .arguments) or { []int{} })[0] == array)
	if !is_target {
		return none
	}
	mut description := ''
	mut message_id := 'iterable-to-array'
	match ptyp {
		.for_of_statement {
			message_id = 'iterable-to-array-in-for-of'
		}
		.yield_expression {
			message_id = 'iterable-to-array-in-yield-star'
		}
		.new_expression {
			callee := t.node(parent, .callee)?
			description = 'new ${t.string_of(callee, .name) or { '' }}(…)'
		}
		.call_expression {
			callee := t.node(parent, .callee)?
			object := t.node(callee, .object)?
			property := t.node(callee, .property)?
			description = '${t.string_of(object, .name) or { '' }}.${t.string_of(property, .name) or {
				''
			}}(…)'
		}
		else {}
	}
	mut finding := Finding{
		stmt:       c.es_tree_position(t, array)
		message_id: message_id
		data:       {
			'parentDescription': description
		}
	}
	fixes := c.unus_unwrap_single_array_spread(t, tokens, array)
	if fixes.len == 0 {
		return finding
	}
	has_fix, fix := c.merge_fixes(fixes) or { return finding }
	if !has_fix {
		return finding
	}
	// A `for…of` body can change the collection, and `yield*` forwards `next()` and `return()`:
	// only a suggestion there.
	if ptyp !in [.for_of_statement, .yield_expression] {
		return Finding{
			...finding
			has_fix: true
			fix:     fix
		}
	}
	return Finding{
		...finding
		suggestions: [Suggestion{
			message_id: 'suggestion/remove-iterable-array'
			fix:        fix
		}]
	}
}

// unus_is_known_non_array_receiver ports isKnownNonArrayMethodReceiver.
fn (mut c Checker) unus_is_known_non_array_receiver(mut ctx UnCtx, node int) bool {
	t := ctx.t
	if t.typ(node) != .call_expression {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	if t.typ(callee) != .member_expression {
		return false
	}
	return c.un_is_known_non_array(mut ctx, t.node(callee, .object) or { return false })
}

// unus_is_slice_call ports isSliceCall.
fn unus_is_slice_call(t &estree.EsTree, node int) bool {
	return un_is_method_call(t, node,
		methods:         ['slice']
		optional_call:   false
		optional_member: false
	)
}

// unus_is_known_array_method_clone ports isKnownArrayMethodClone: the types say an array method
// of an array.
fn (mut c Checker) unus_is_known_array_method_clone(mut ctx UnCtx, node int) bool {
	t := ctx.t
	if !un_is_method_call(t, node,
		methods:         unus_type_checked_array_methods
		optional_call:   false
		optional_member: false
	) {
		return false
	}
	callee := t.node(node, .callee) or { return false }
	return c.un_is_array(mut ctx, t.node(callee, .object) or { return false })
		&& c.un_is_array(mut ctx, node)
}

// unus_is_heuristic_array_clone ports isHeuristicArrayClone.
fn (mut c Checker) unus_is_heuristic_array_clone(mut ctx UnCtx, node int) bool {
	t := ctx.t
	if c.un_is_known_non_array(mut ctx, node) {
		return false
	}
	if un_is_method_call(t, node,
		methods:         unus_array_clone_methods
		optional_call:   false
		optional_member: false
	) {
		return !c.unus_is_known_non_array_receiver(mut ctx, node)
	}
	if un_is_method_call(t, node, methods: ['concat'], optional_call: false, optional_member: false) {
		callee := t.node(node, .callee) or { return false }
		object := t.node(callee, .object) or { return false }
		return !((t.typ(object) == .identifier && (t.string_of(object, .name) or { '' }) == 'Iterator')
			|| c.unus_is_known_non_array_receiver(mut ctx, node))
	}
	return un_is_method_call(t, node,
		methods:         ['split']
		optional_call:   false
		optional_member: false
	)
		|| un_is_method_call(t, node,
			objects:          ['Object']
			methods:          ['keys', 'values']
			arguments_length: 1
			optional_call:    false
			optional_member:  false
		) || (t.typ(node) == .await_expression && un_is_method_call(t,
		t.node(node, .argument) or { -1 },
		objects:          ['Promise']
		methods:          ['all', 'allSettled']
		arguments_length: 1
		optional_call:    false
		optional_member:  false
	)) || un_is_method_call(t, node,
		objects:         ['Array']
		methods:         ['from', 'of']
		optional_call:   false
		optional_member: false
	) || un_is_new(t, node, names: ['Array'])
}

// unus_clone_array is the "useless array clone" listener: `[...array.slice()]`.
fn (mut c Checker) unus_clone_array(mut ctx UnCtx, array int) ?Finding {
	t := ctx.t
	if !unus_is_single_array_spread(t, array) {
		return none
	}
	node := t.node((t.list(array, .elements)?)[0], .argument)?
	known := c.unus_is_known_array_method_clone(mut ctx, node)
	if !known && !c.unus_is_heuristic_array_clone(mut ctx, node) {
		return none
	}
	finding := Finding{
		stmt:       c.es_tree_position(t, array)
		message_id: 'clone-array'
	}
	// `[...new Array(1)]` has holes; `[...foo.slice(1)]` is safe only for an array.
	if un_is_new(t, node, names: ['Array']) || (unus_is_slice_call(t, node) && !known) {
		return finding
	}
	fixes := c.unus_unwrap_single_array_spread(t, ctx.tokens, array)
	if fixes.len == 0 {
		return finding
	}
	has_fix, fix := c.merge_fixes(fixes) or { return finding }
	return Finding{
		...finding
		has_fix: has_fix
		fix:     fix
	}
}
