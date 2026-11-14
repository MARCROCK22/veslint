module rules

import estree
import time
import x.json2
import treesitter { node_end, node_start }

// Port of the `unicorn/prefer-object-from-entries` rule of eslint-plugin-unicorn 79.0.0, with its
// `functions` option and its fixes.

const upofe_messages = {
	'reduce':   'Prefer `Object.fromEntries()` over `Array#reduce()`.'
	'function': 'Prefer `Object.fromEntries()` over `{{functionName}}()`.'
	'loop':     'Prefer `Object.fromEntries()` over a `for-of` loop.'
}

// `_.fromPairs(pairs)`
const upofe_lodash_from_pairs_functions = ['_.fromPairs', 'lodash.fromPairs']

fn upofe_options(options []json2.Any) ![]string {
	o := option_object(unicorn_prefer_object_from_entries, options, ['functions'])!
	list := o.values['functions'] or { return []string{} }
	if list is []json2.Any {
		return list.map(it.str())
	}
	return []string{}
}

fn (mut c Checker) lint_unicorn_prefer_object_from_entries(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut functions := upofe_options(c.rule_options(unicorn_prefer_object_from_entries))!
	functions << upofe_lodash_from_pairs_functions
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.variable_declaration {
				stats.checked++
				if finding := c.upofe_for_of_loop_problem(mut ctx, node) {
					findings << finding
				}
			}
			.call_expression {
				stats.checked++
				findings << c.upofe_call_expression(mut ctx, node, functions)
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// upofe_is_arrow_function_callback ports isArrowFunctionCallback.
fn upofe_is_arrow_function_callback(t &estree.EsTree, node int) bool {
	if node < 0 || t.typ(node) != .arrow_function_expression || (t.flag(node, .async) or { false }) {
		return false
	}
	params := t.list(node, .params) or { return false }
	return params.len > 0 && t.typ(params[0]) == .identifier
}

// upofe_is_property ports isProperty: a `Property` of kind `init` that is not a method.
fn upofe_is_property(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .property && (t.string_of(node, .kind) or { '' }) == 'init'
		&& !(t.flag(node, .method) or { false })
}

// upofe_is_prototype_property ports isPrototypeProperty: a non-computed `__proto__: value` (or
// `'__proto__': value`), which sets the prototype in an object literal.
fn upofe_is_prototype_property(t &estree.EsTree, node int) bool {
	if !upofe_is_property(t, node) || (t.flag(node, .computed) or { false }) {
		return false
	}
	key := t.node(node, .key) or { return false }
	if t.typ(key) == .identifier {
		return (t.string_of(key, .name) or { '' }) == '__proto__'
	}
	return un_is_string_literal(t, key) && t.get(key, .value) as string == '__proto__'
}

// upofe_is_same_identifier ports isSameIdentifier.
fn upofe_is_same_identifier(t &estree.EsTree, a int, b int) bool {
	return a >= 0 && b >= 0 && t.typ(a) == .identifier && t.typ(b) == .identifier
		&& t.string_of(a, .name) or { '' } == t.string_of(b, .name) or { '' }
}

// upofe_is_array_reduce_with_empty_object ports isArrayReduceWithEmptyObject: `pairs.reduce(…, {})`.
fn upofe_is_array_reduce_with_empty_object(t &estree.EsTree, node int) bool {
	return un_is_method_call(t, node,
		methods:          ['reduce']
		arguments_length: 2
		optional_call:    false
		optional_member:  false
	) && un_is_empty_object(t, (t.list(node, .arguments) or { return false })[1])
}

// upofe_reduce_property ports the `test` of fixableArrayReduceCases: the property of the callback
// that becomes the entry, -1 if the call is none of the cases.
fn (mut c Checker) upofe_reduce_property(t &estree.EsTree, call int) int {
	if !upofe_is_array_reduce_with_empty_object(t, call) {
		return -1
	}
	callback := (t.list(call, .arguments) or { return -1 })[0]
	if !upofe_is_arrow_function_callback(t, callback) {
		return -1
	}
	first_parameter := (t.list(callback, .params) or { return -1 })[0]
	body := t.node(callback, .body) or { return -1 }
	// `() => Object.assign(object, {key})`
	if un_is_method_call(t, body,
		objects:          ['Object']
		methods:          ['assign']
		arguments_length: 2
		optional_call:    false
		optional_member:  false
	) {
		arguments := t.list(body, .arguments) or { return -1 }
		if t.typ(arguments[1]) == .object_expression {
			properties := t.list(arguments[1], .properties) or { []int{} }
			if properties.len == 1 && upofe_is_property(t, properties[0])
				&& !upofe_is_prototype_property(t, properties[0])
				&& upofe_is_same_identifier(t, first_parameter, arguments[0]) {
				return properties[0]
			}
		}
	}
	// `() => ({...object, key})`
	if t.typ(body) == .object_expression {
		properties := t.list(body, .properties) or { []int{} }
		if properties.len == 2 && t.typ(properties[0]) == .spread_element
			&& upofe_is_property(t, properties[1]) && !upofe_is_prototype_property(t, properties[1])
			&& upofe_is_same_identifier(t, first_parameter, t.node(properties[0], .argument) or {
			-1
		}) {
			return properties[1]
		}
	}
	return -1
}

// upofe_first_parameter_references is the number of references of the variable of the first
// parameter of the callback (the one whose only identifier is that parameter), none without it.
fn (mut c Checker) upofe_first_parameter_references(ctx &UnCtx, callback int) ?int {
	t := ctx.t
	first_parameter := (t.list(callback, .params) or { return none })[0]
	ts := t.ts_node(callback) or { return none }
	tree := c.scope_tree(ctx.root)
	for v in c.es_declared_variables(ctx.root, ts) {
		variable := tree.variables[v]
		if variable.identifiers.len == 1
			&& node_start(variable.identifiers[0]) == t.nodes[first_parameter].start {
			return variable.references.len
		}
	}
	return none
}

fn (mut c Checker) upofe_call_expression(mut ctx UnCtx, call int, functions []string) []Finding {
	t := ctx.t
	tokens := ctx.tokens
	mut findings := []Finding{}
	property := c.upofe_reduce_property(t, call)
	if property >= 0 {
		callee := t.node(call, .callee) or { return findings }
		object := t.node(callee, .object) or { return findings }
		callback := (t.list(call, .arguments) or { return findings })[0]
		// Typed-array `.map()` coerces entries to numeric elements instead of returning pairs.
		if !c.un_is_known_non_array(mut ctx, object) {
			if references := c.upofe_first_parameter_references(ctx, callback) {
				if references == 1 {
					mut finding := Finding{
						stmt:       c.es_tree_position(t, t.node(callee, .property) or { callee })
						message_id: 'reduce'
					}
					if !unb_has_type_arguments(t, call) {
						if fix := c.upofe_fix_reduce(t, tokens, call, property) {
							finding = Finding{
								...finding
								has_fix: true
								fix:     fix
							}
						}
					}
					findings << finding
				}
			}
		}
	}
	if !un_is_call(t, call, arguments_length: 1, optional: false) {
		return findings
	}
	callee := t.node(call, .callee) or { return findings }
	for name_or_path in functions {
		function_name := js_trim(name_or_path)
		if un_node_matches_name_or_path(t, callee, function_name) {
			findings << Finding{
				stmt:       c.es_tree_position(t, callee)
				message_id: 'function'
				data:       {
					'functionName': function_name
				}
				has_fix:    true
				fix:        fix_replace_range(t.nodes[callee].start, t.nodes[callee].end,
					'Object.fromEntries')
			}
		}
	}
	return findings
}

// upofe_fix_reduce ports fixReduceAssignOrSpread; none when the fix aborts.
fn (mut c Checker) upofe_fix_reduce(t &estree.EsTree, tokens &SourceTokens, call int, property int) ?Fix {
	arguments := t.list(call, .arguments)?
	callback := arguments[0]
	init_object := arguments[1]
	// Rebuilding the callback body would drop any comment inside the callback.
	if tokens.comments_inside(t.nodes[callback].start, t.nodes[callback].end).len > 0 {
		return none
	}
	// The initial value, with its parentheses and the comma before it
	_, init_end := c.un_parenthesized_range(t, tokens, init_object)
	parens := c.un_parentheses(t, tokens, init_object)
	init_head := if parens.len > 0 { parens[0].start } else { t.nodes[init_object].start }
	comma := tokens.before(init_head, false)?
	// The initial value is removed along with the comma before it, which would drop a comment
	// placed between them.
	if un_has_comment_in_range(tokens, comma.start, init_end) {
		return none
	}
	callee := t.node(call, .callee)?
	callee_property := t.node(callee, .property)?
	mut fixes := []Fix{}
	// Wrap `array.reduce()` with `Object.fromEntries()`
	fixes << fix_insert_at(t.nodes[call].start, 'Object.fromEntries(')
	fixes << fix_insert_at(t.nodes[call].end, ')')
	// Switch `.reduce` to `.map`
	fixes << fix_replace_range(t.nodes[callee_property].start, t.nodes[callee_property].end, 'map')
	// Remove empty object
	fixes << fix_remove_range(comma.start, init_end)
	// Remove the first parameter
	parameters := t.list(callback, .params)?
	first_parameter := parameters[0]
	token_after := tokens.after(t.nodes[first_parameter].end, false)?
	// Remove the comma and the gap after it, so `fn(a, b)` becomes `fn(b)` rather than `fn( b)`
	if c.token_is(token_after, ',') {
		next := tokens.after(token_after.end, false)?
		fixes << fix_remove_range(token_after.start, next.start)
	}
	mut should_add_parentheses := false
	if parameters.len == 1 {
		mut arrow := tokens.after(t.nodes[first_parameter].end, false)?
		for !c.token_is(arrow, '=>') {
			arrow = tokens.after(arrow.end, false)?
		}
		token_before_arrow := tokens.before(arrow.start, false)?
		if !c.token_is(token_before_arrow, ')') {
			should_add_parentheses = true
		}
	}
	fixes << fix_replace_range(t.nodes[first_parameter].start, t.nodes[first_parameter].end,
		if should_add_parentheses { '()' } else { '' })
	// Replace function body
	key := t.node(property, .key)?
	value := t.node(property, .value)?
	mut key_text := c.un_parenthesized_text(t, tokens, key)
	value_text := c.un_parenthesized_text(t, tokens, value)
	if !(t.flag(property, .computed) or { false }) && t.typ(key) == .identifier {
		key_text = "'${key_text}'"
	}
	body := t.node(callback, .body)?
	fixes << fix_replace_range(t.nodes[body].start, t.nodes[body].end, '[${key_text}, ${value_text}]')
	fixes << c.un_remove_parentheses(t, tokens, body)
	has_fix, fix := c.merge_fixes(fixes) or { return none }
	if !has_fix {
		return none
	}
	return fix
}

// upofe_for_of_pair_pattern ports getForOfPairPattern: the `[key, value]` of
// `for (const [key, value] of …)`, -1 if none.
fn upofe_for_of_pair_pattern(t &estree.EsTree, left int) int {
	if t.typ(left) != .variable_declaration
		|| (t.string_of(left, .kind) or { '' }) !in ['const', 'let'] {
		return -1
	}
	declarations := t.list(left, .declarations) or { return -1 }
	if declarations.len != 1 {
		return -1
	}
	pattern := t.node(declarations[0], .id) or { return -1 }
	if t.typ(pattern) != .array_pattern {
		return -1
	}
	elements := t.list(pattern, .elements) or { return -1 }
	if elements.len != 2 || elements.any(it < 0 || t.typ(it) != .identifier) {
		return -1
	}
	return pattern
}

// upofe_only_loop_assignment ports getOnlyLoopAssignmentExpression, -1 if none.
fn upofe_only_loop_assignment(t &estree.EsTree, loop int) int {
	expression := unim_only_expression(t, t.node(loop, .body) or { -1 })
	if expression >= 0 && t.typ(expression) == .assignment_expression {
		return expression
	}
	return -1
}

// upofe_matches_for_of_loop ports matchesForOfLoop: `object[key] = value`.
fn upofe_matches_for_of_loop(t &estree.EsTree, id int, loop_left int, assignment int) bool {
	left := t.node(assignment, .left) or { return false }
	if (t.string_of(assignment, .operator) or { '' }) != '=' || t.typ(left) != .member_expression
		|| !(t.flag(left, .computed) or { false }) {
		return false
	}
	elements := t.list(loop_left, .elements) or { return false }
	return upofe_is_same_identifier(t, id, t.node(left, .object) or { -1 })
		&& upofe_is_same_identifier(t, elements[0], t.node(left, .property) or { -1 })
		&& upofe_is_same_identifier(t, elements[1], t.node(assignment, .right) or { -1 })
}

// upofe_references_variable ports referencesVariable: an identifier of the variable (a definition
// name or a reference) is inside the node.
fn (mut c Checker) upofe_references_variable(ctx &UnCtx, v int, node int) bool {
	tree := c.scope_tree(ctx.root)
	start := ctx.t.nodes[node].start
	end := ctx.t.nodes[node].end
	variable := tree.variables[v]
	for identifier in variable.identifiers {
		if node_start(identifier) >= start && node_end(identifier) <= end {
			return true
		}
	}
	for r in variable.references {
		identifier := tree.references[r].identifier
		if node_start(identifier) >= start && node_end(identifier) <= end {
			return true
		}
	}
	return false
}

// upofe_for_of_loop_problem ports getForOfLoopProblem: `const object = {}` followed by
// `for (const [key, value] of pairs) object[key] = value;`.
fn (mut c Checker) upofe_for_of_loop_problem(mut ctx UnCtx, declaration int) ?Finding {
	t := ctx.t
	tokens := ctx.tokens
	declarations := t.list(declaration, .declarations)?
	if declarations.len != 1 {
		return none
	}
	declarator := declarations[0]
	id := t.node(declarator, .id)?
	init := t.node(declarator, .init) or { return none }
	// Only `{}`, see `isArrayReduceWithEmptyObject`
	if t.typ(id) != .identifier || !un_is_empty_object(t, init) {
		return none
	}
	loop := unb_sibling(t, declaration, 1)
	if loop < 0 || t.typ(loop) != .for_of_statement || (t.flag(loop, .await_) or { false }) {
		return none
	}
	loop_left := upofe_for_of_pair_pattern(t, t.node(loop, .left)?)
	if loop_left < 0 {
		return none
	}
	if (t.list(loop_left, .elements) or { []int{} }).any(upofe_is_same_identifier(t, it, id)) {
		return none
	}
	right := t.node(loop, .right)?
	v := c.upofe_declared_variable(ctx, declarator)
	if v >= 0 && c.upofe_references_variable(ctx, v, right) {
		return none
	}
	assignment := upofe_only_loop_assignment(t, loop)
	if assignment < 0 || !upofe_matches_for_of_loop(t, id, loop_left, assignment) {
		return none
	}
	mut finding := Finding{
		stmt:       c.es_tree_position(t, loop)
		message_id: 'loop'
	}
	end := if next := tokens.after(t.nodes[loop].end, false) { next.start } else { c.src.len }
	if !un_has_comment_in_range(tokens, t.nodes[declaration].start, end) {
		// The `for…of` statement disappears, so the declaration becomes an expression statement
		// the next statement could continue
		fixes := [
			fix_replace_range(t.nodes[init].start, t.nodes[init].end, 'Object.fromEntries(${c.un_parenthesized_text(t,
				tokens, right)})'),
			c.upofe_remove_statement(t, tokens, loop),
		]
		if has_fix, fix := c.merge_fixes(fixes) {
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		}
	}
	return finding
}

// upofe_declared_variable is `sourceCode.getDeclaredVariables(declarator)[0]`, -1 if none.
fn (mut c Checker) upofe_declared_variable(ctx &UnCtx, declarator int) int {
	ts := ctx.t.ts_node(declarator) or { return -1 }
	variables := c.es_declared_variables(ctx.root, ts)
	return if variables.len > 0 { variables[0] } else { -1 }
}

// upofe_remove_statement ports removeStatement (fix/remove-statement.js) of one statement, without
// preserveSemiColon.
fn (c &Checker) upofe_remove_statement(t &estree.EsTree, tokens &SourceTokens, statement int) Fix {
	if c.unb_needs_semicolon(t, tokens, tokens.before(t.nodes[statement].start, false), none) {
		return fix_replace_range(t.nodes[statement].start, t.nodes[statement].end, ';')
	}
	mut start := t.nodes[statement].start
	mut end := t.nodes[statement].end
	line_start := c.unim_line_start(start)
	line_end := c.unim_line_end(end)
	if js_trim(c.src[line_start..start]) == '' && js_trim(c.src[end..line_end]) == '' {
		end = line_end
		start = line_start
		if start == 0 {
			// On the first line there is no preceding line terminator to absorb, so take the
			// trailing one instead, unless it is the end of the file.
			end += c.unim_terminator_length(end)
		} else if start >= 2 && c.src[start - 2] == `\r` && c.src[start - 1] == `\n` {
			start -= 2
		} else if start >= 3 && c.src[start - 3] == 0xe2 && c.src[start - 2] == 0x80 {
			start -= 3
		} else {
			start--
		}
	}
	return fix_remove_range(start, end)
}
