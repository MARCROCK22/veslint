module rules

import estree
import json2
import time
import treesitter { node_end, node_start }

// Port of the `unicorn/no-immediate-mutation` rule of eslint-plugin-unicorn 79.0.0, with its
// option `checkConditionals`, its fixes and its suggestions. veslint lints TypeScript only, where
// the rule never fixes a conditional mutation (isTypeScriptFile).

const unim_messages = {
	'error':                     'Immediate mutation on {{objectType}} is not allowed.'
	'initialization':            'Combine this initialization with the preceding declaration.'
	'suggestion/initialization': 'Combine the initialization and declaration.'
	'suggestion/array':          '{{operation}} the elements to the {{assignType}}.'
	'suggestion/object':         'Move this property to the {{assignType}}.'
	'suggestion/object-assign':  '{{description}} the {{assignType}}.'
	'suggestion/set':            'Move the element to the {{assignType}}.'
	'suggestion/map':            'Move the entry to the {{assignType}}.'
	'suggestion/conditional':    'Move the conditional mutation to the {{assignType}}.'
}

fn unim_options(options []json2.Any) !bool {
	o := option_object(unicorn_no_immediate_mutation, options, ['checkConditionals'])!
	return o.bool_value('checkConditionals') or { false }
}

// UnimCase is one of the violation cases: array, object with an assignment, object with
// `Object.assign()`, Set and Map.
enum UnimCase {
	array
	object_assignment
	object_assign
	set
	map
}

// UnimInfo is ViolationCaseInformation.
struct UnimInfo {
	variable       int
	value          int
	next_statement int
	assign_type    string
}

fn (mut c Checker) lint_unicorn_no_immediate_mutation(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	check_conditionals := unim_options(c.rule_options(unicorn_no_immediate_mutation))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.variable_declaration {
				stats.checked++
				if f := c.unim_initialization_problem(mut ctx, node) {
					findings << f
				}
			}
			.variable_declarator, .assignment_expression {
				stats.checked++
				for case in [UnimCase.array, .object_assignment, .object_assign, .set, .map] {
					if f := c.unim_case_problem(mut ctx, node, case, check_conditionals) {
						findings << f
					}
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ---- helpers

// unim_args_range ports getCallExpressionArgumentsRange: the text of the arguments without the
// trailing comma.
fn (c &Checker) unim_args_range(t &estree.EsTree, tokens &SourceTokens, call int) ?UnRange {
	call_tokens := c.un_call_tokens(t, tokens, call)?
	end := (call_tokens.trailing or { call_tokens.closing }).start
	return UnRange{call_tokens.opening.end, end}
}

// unim_has_comment_outside_arguments ports hasCommentOutsideArguments.
fn (c &Checker) unim_has_comment_outside_arguments(t &estree.EsTree, tokens &SourceTokens, call int, statement int) bool {
	arguments := c.unim_args_range(t, tokens, call) or { return true }
	return un_would_remove_comments(tokens, t.nodes[statement].start, t.nodes[statement].end, [
		arguments,
	])
}

// unim_has_variable_in_nodes ports hasVariableInNodes: an identifier or reference of the variable
// is inside one of the nodes.
fn (mut c Checker) unim_has_variable_in_nodes(ctx &UnCtx, variable int, nodes []int) bool {
	t := ctx.t
	tree := c.scope_tree(ctx.root)
	v := tree.variables[variable]
	mut identifiers := v.identifiers.clone()
	for r in v.references {
		identifiers << tree.references[r].identifier
	}
	for node in nodes {
		if node < 0 {
			continue
		}
		start, end := t.nodes[node].start, t.nodes[node].end
		for id in identifiers {
			if node_start(id) >= start && node_end(id) <= end {
				return true
			}
		}
	}
	return false
}

// unim_is_new_with_optional_array ports isCallExpressionWithOptionalArrayExpression: `new Set()`
// or `new Set([…])`.
fn unim_is_new_with_optional_array(t &estree.EsTree, node int, constructors []string) bool {
	if node < 0 || !un_is_new(t, node, names: constructors, maximum_arguments: 1) {
		return false
	}
	arguments := t.list(node, .arguments) or { []int{} }
	return arguments.len == 0 || t.typ(arguments[0]) == .array_expression
}

// unim_line_start is the offset where the line of `offset` starts.
fn (c &Checker) unim_line_start(offset int) int {
	mut i := offset
	for i > 0 {
		b := c.src[i - 1]
		if b == `\n` || b == `\r` {
			return i
		}
		// U+2028 and U+2029: E2 80 A8 and E2 80 A9.
		if i >= 3 && c.src[i - 3] == 0xe2 && c.src[i - 2] == 0x80 && c.src[i - 1] in [
			u8(0xa8),
			0xa9,
		] {
			return i
		}
		i--
	}
	return 0
}

// unim_line_end is the offset where the line of `offset` ends (its line terminator, or the end).
fn (c &Checker) unim_line_end(offset int) int {
	mut i := offset
	for i < c.src.len {
		b := c.src[i]
		if b == `\n` || b == `\r` {
			return i
		}
		if i + 2 < c.src.len && b == 0xe2 && c.src[i + 1] == 0x80 && c.src[i + 2] in [
			u8(0xa8),
			0xa9,
		] {
			return i
		}
		i++
	}
	return c.src.len
}

// unim_terminator_length is the length of the line terminator at `offset` (\r\n, \r, \n, U+2028,
// U+2029), 0 for none.
fn (c &Checker) unim_terminator_length(offset int) int {
	if offset >= c.src.len {
		return 0
	}
	if c.src[offset] == `\r` {
		return if offset + 1 < c.src.len && c.src[offset + 1] == `\n` { 2 } else { 1 }
	}
	if c.src[offset] == `\n` {
		return 1
	}
	if offset + 2 < c.src.len && c.src[offset] == 0xe2 && c.src[offset + 1] == 0x80
		&& c.src[offset + 2] in [u8(0xa8), 0xa9] {
		return 3
	}
	return 0
}

// unim_remove_statement ports removeStatement (fix/remove-statement.js): removes the statements
// from `first` to `last` with the whitespace of their own line, or replaces them with `;` when the
// expression before them needs a boundary.
fn (c &Checker) unim_remove_statement(t &estree.EsTree, tokens &SourceTokens, first int, last int, preserve_semicolon bool) Fix {
	if c.un_needs_semicolon(t, tokens, tokens.before(t.nodes[first].start, false), none) {
		return fix_replace_range(t.nodes[first].start, t.nodes[last].end, ';')
	}
	mut end := t.nodes[last].end
	if preserve_semicolon {
		inside := tokens.inside(t.nodes[last].start, t.nodes[last].end, false)
		if inside.len >= 2 && c.token_is(inside.last(), ';') {
			end = inside[inside.len - 2].end
		}
	}
	mut start := t.nodes[first].start
	line_start := c.unim_line_start(start)
	line_end := c.unim_line_end(end)
	if js_trim(c.src[line_start..start]) == '' && js_trim(c.src[end..line_end]) == '' {
		end = line_end
		start = line_start
		if start == 0 {
			// No preceding line terminator: the trailing one, unless it is the end of the file.
			end += c.unim_terminator_length(end)
		} else {
			// The line terminator before the line.
			if start >= 2 && c.src[start - 2] == `\r` && c.src[start - 1] == `\n` {
				start -= 2
			} else if start >= 3 && c.src[start - 3] == 0xe2 && c.src[start - 2] == 0x80 {
				start -= 3
			} else {
				start--
			}
		}
	}
	return fix_remove_range(start, end)
}

// unim_remove_statement_after_assign ports removeStatementAfterAssign.
fn (c &Checker) unim_remove_statement_after_assign(t &estree.EsTree, tokens &SourceTokens, statement int) Fix {
	before := tokens.before(t.nodes[statement].start, false)
	preserve := if token := before { !c.token_is(token, ';') } else { true }
	return c.unim_remove_statement(t, tokens, statement, statement, preserve)
}

// unim_append_list ports appendListTextToArrayExpressionOrObjectExpression.
fn (c &Checker) unim_append_list(t &estree.EsTree, tokens &SourceTokens, node int, list_text string) ?Fix {
	inside := tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
	if inside.len < 2 {
		return none
	}
	penultimate := inside[inside.len - 2]
	closing := inside.last()
	list := if t.typ(node) == .array_expression {
		t.list(node, .elements) or { []int{} }
	} else {
		t.list(node, .properties) or { []int{} }
	}
	comma := if list.len > 0 && !c.token_is(penultimate, ',') { ',' } else { '' }
	return fix_insert_at(closing.start, '${comma} ${list_text}')
}

// unim_append_to_constructor ports appendElementsTextToSetConstructor.
fn (c &Checker) unim_append_to_constructor(t &estree.EsTree, tokens &SourceTokens, new_expression int, elements_text string, next_statement int) ?[]Fix {
	mut fixes := []Fix{}
	if c.un_new_with_parentheses(t, tokens, new_expression) {
		arguments := t.list(new_expression, .arguments) or { []int{} }
		if arguments.len > 0 {
			fixes << c.unim_append_list(t, tokens, arguments[0], elements_text)?
		} else {
			call_tokens := c.un_call_tokens(t, tokens, new_expression)?
			fixes << fix_insert_at(call_tokens.opening.end, '[${elements_text}]')
		}
	} else {
		fixes << fix_insert_at(t.nodes[new_expression].end, '([${elements_text}])')
	}
	fixes << c.unim_remove_statement_after_assign(t, tokens, next_statement)
	return fixes
}

// unim_properties_range ports getObjectExpressionPropertiesRange: inside the braces, without a
// trailing comma.
fn (c &Checker) unim_properties_range(t &estree.EsTree, tokens &SourceTokens, object int) ?UnRange {
	inside := tokens.inside(t.nodes[object].start, t.nodes[object].end, false)
	if inside.len < 2 {
		return none
	}
	penultimate := inside[inside.len - 2]
	end := if c.token_is(penultimate, ',') { penultimate.start } else { inside.last().start }
	return UnRange{inside[0].end, end}
}

// unim_property_name ports getPropertyName(node, scope) of eslint-utils for a member expression or
// a property ('' when it has none).
fn (mut c Checker) unim_property_name(t &estree.EsTree, node int) string {
	key := if t.typ(node) == .member_expression {
		t.node(node, .property) or { return '' }
	} else {
		t.node(node, .key) or { return '' }
	}
	if t.flag(node, .computed) or { false } {
		return c.string_if_constant(t.ts_node(key) or { return '' }) or { '' }
	}
	if t.typ(key) == .private_identifier {
		return ''
	}
	if t.typ(key) == .literal {
		return es_tree_static_string_value(t, key) or { '' }
	}
	return t.string_of(key, .name) or { '' }
}

// unim_has_prototype_property ports hasPrototypeProperty: a `__proto__` key in the literal.
fn (mut c Checker) unim_has_prototype_property(t &estree.EsTree, object int) bool {
	for property in t.list(object, .properties) or { []int{} } {
		if t.typ(property) == .property && c.unim_property_name(t, property) == '__proto__' {
			return true
		}
	}
	return false
}

// unim_has_accessor_property ports hasAccessorProperty: a getter or a setter in the literal.
fn unim_has_accessor_property(t &estree.EsTree, object int) bool {
	return (t.list(object, .properties) or { []int{} }).any(t.typ(it) == .property
		&& (t.string_of(it, .kind) or { 'init' }) != 'init')
}

fn unim_side_effect(t &estree.EsTree, node int) bool {
	return un_has_side_effect(t, node, UnSideEffect{})
}

// unim_object_type is the `objectType` of the message for a value.
fn unim_object_type(t &estree.EsTree, value int) string {
	return match t.typ(value) {
		.object_expression {
			'object'
		}
		.new_expression {
			callee := t.node(value, .callee) or { return '' }
			'`${t.string_of(callee, .name) or { '' }}`'
		}
		else {
			'array'
		}
	}
}

// ---- the cases

// unim_test_value is the `testValue` of each case.
fn unim_test_value(t &estree.EsTree, case UnimCase, value int) bool {
	if value < 0 {
		return false
	}
	return match case {
		.array { t.typ(value) == .array_expression }
		.object_assignment, .object_assign { t.typ(value) == .object_expression }
		.set { unim_is_new_with_optional_array(t, value, ['Set', 'WeakSet']) }
		.map { unim_is_new_with_optional_array(t, value, ['Map', 'WeakMap']) }
	}
}

// unim_problematic_node is the `getProblematicNode` of each case: the mutation in `expression`,
// -1 for none.
fn (mut c Checker) unim_problematic_node(ctx &UnCtx, case UnimCase, info UnimInfo, from int) int {
	t := ctx.t
	if from < 0 {
		return -1
	}
	name := c.scope_tree(ctx.root).variables[info.variable].name
	match case {
		.array {
			if !(un_is_method_call(t, from,
				objects:         [name]
				methods:         ['push', 'unshift']
				optional_member: false
				optional_call:   false
			) && (t.list(from, .arguments) or { []int{} }).len > 0) {
				return -1
			}
			if c.unim_has_variable_in_nodes(ctx, info.variable, t.list(from, .arguments) or { []int{} }) {
				return -1
			}
			return from
		}
		.object_assignment {
			if !(t.typ(from) == .assignment_expression
				&& (t.string_of(from, .operator) or { '' }) == '='
				&& un_is_member(t, t.node(from, .left) or { -1 }, UnMember{
					objects:  [name]
					optional: false
				})) {
				return -1
			}
			value := t.node(from, .right) or { return -1 }
			member := t.node(from, .left) or { return -1 }
			property := t.node(member, .property) or { return -1 }
			computed := t.flag(member, .computed) or { false }
			if t.typ(property) == .private_identifier || c.unim_has_variable_in_nodes(ctx, info.variable,
				if computed { [property, value] } else { [value] }) {
				return -1
			}
			return from
		}
		.object_assign {
			if !un_is_method_call(t, from,
				objects:           ['Object']
				methods:           ['assign']
				minimum_arguments: 2
				optional_member:   false
				optional_call:     false
			) {
				return -1
			}
			arguments := t.list(from, .arguments) or { return -1 }
			object, first_value := arguments[0], arguments[1]
			if !(t.typ(object) == .identifier && (t.string_of(object, .name) or { '' }) == name)
				|| t.typ(first_value) == .spread_element
				|| c.unim_has_variable_in_nodes(ctx, info.variable, [first_value]) {
				return -1
			}
			return from
		}
		.set {
			mut call := from
			if t.typ(call) == .chain_expression {
				call = t.node(call, .expression) or { return -1 }
			}
			if !un_is_method_call(t, call,
				objects:          [name]
				methods:          ['add']
				arguments_length: 1
				optional_member:  false
				optional_call:    false
			) || c.unim_has_variable_in_nodes(ctx, info.variable, t.list(call, .arguments) or { []int{} }) {
				return -1
			}
			return call
		}
		.map {
			if !un_is_method_call(t, from,
				objects:          [name]
				methods:          ['set']
				arguments_length: 2
				optional_call:    false
			) || c.unim_has_variable_in_nodes(ctx, info.variable, t.list(from, .arguments) or { []int{} }) {
				return -1
			}
			return from
		}
	}
}

// unim_finding makes a problem with its fix, or its suggestion when `suggest` (none of them when
// the fixes do not merge).
fn (c &Checker) unim_finding(base Finding, fixes []Fix, suggest bool, suggestion Suggestion) Finding {
	fix := c.unim_merge(fixes) or { return base }
	if suggest {
		return Finding{
			...base
			suggestions: [Suggestion{
				...suggestion
				fix: fix
			}]
		}
	}
	return Finding{
		...base
		has_fix: true
		fix:     fix
	}
}

// unim_merge merges the fixes of one problem.
fn (c &Checker) unim_merge(fixes []Fix) ?Fix {
	has_fix, fix := c.merge_fixes(fixes) or { return none }
	return if has_fix { fix } else { none }
}

// unim_problem is the `getProblem` of each case.
fn (mut c Checker) unim_problem(ctx &UnCtx, case UnimCase, info UnimInfo, node int) ?Finding {
	t := ctx.t
	tokens := ctx.tokens
	match case {
		.array {
			member := t.node(node, .callee)?
			method := t.string_of(t.node(member, .property)?, .name)?
			base := Finding{
				stmt:       c.es_tree_position(t, member)
				message_id: 'error'
				data:       {
					'objectType': 'array'
				}
			}
			is_prepend := method == 'unshift'
			elements := t.list(info.value, .elements) or { []int{} }
			if (is_prepend && elements.any(it >= 0 && unim_side_effect(t, it)))
				|| c.unim_has_comment_outside_arguments(t, tokens, node, info.next_statement) {
				return base
			}
			mut fixes := []Fix{}
			text := c.unb_call_arguments_text(t, tokens, node, false)?
			if is_prepend {
				first := un_first_token(t, tokens, info.value, 0)?
				fixes << fix_insert_at(first.end, '${text}, ')
			} else {
				fixes << c.unim_append_list(t, tokens, info.value, text)?
			}
			fixes << c.unim_remove_statement_after_assign(t, tokens, info.next_statement)
			suggest := (t.list(node, .arguments) or { []int{} }).any(unim_side_effect(t, it))
			return c.unim_finding(base, fixes, suggest, Suggestion{
				message_id: 'suggestion/array'
				data:       {
					'operation':  if is_prepend { 'Prepend' } else { 'Append' }
					'assignType': info.assign_type
				}
			})
		}
		.object_assignment {
			member := t.node(node, .left)?
			value := t.node(node, .right)?
			property := t.node(member, .property)?
			operator := c.un_token_after_punctuator(tokens, t.nodes[member].end, '=')?
			base := Finding{
				stmt:       c.position_range(t.nodes[node].start, operator.end)
				message_id: 'error'
				data:       {
					'objectType': 'object'
				}
			}
			property_start, property_end := c.un_parenthesized_range(t, tokens, property)
			value_start, value_end := c.un_parenthesized_range(t, tokens, value)
			if un_would_remove_comments(tokens, t.nodes[info.next_statement].start, t.nodes[info.next_statement].end,
				[UnRange{property_start, property_end}, UnRange{value_start, value_end}]) {
				return base
			}
			if c.unim_property_name(t, member) == '__proto__'
				|| unim_has_accessor_property(t, info.value) {
				return base
			}
			computed := t.flag(member, .computed) or { false }
			mut property_text := c.un_parenthesized_text(t, tokens, property)
			if computed {
				property_text = '[${property_text}]'
			}
			text := '${property_text}: ${c.un_parenthesized_text(t, tokens, value)},'
			inside := tokens.inside(t.nodes[info.value].start, t.nodes[info.value].end, false)
			penultimate := inside[inside.len - 2]
			closing := inside.last()
			comma := if (t.list(info.value, .properties) or { []int{} }).len > 0
				&& !c.token_is(penultimate, ',') {
				','
			} else {
				''
			}
			fixes := [fix_insert_at(closing.start, '${comma} ${text}'),
				c.unim_remove_statement_after_assign(t, tokens, info.next_statement)]
			suggest := (computed && unim_side_effect(t, property)) || unim_side_effect(t, value)
			return c.unim_finding(base, fixes, suggest, Suggestion{
				message_id: 'suggestion/object'
				data:       {
					'assignType': info.assign_type
				}
			})
		}
		.object_assign {
			arguments := t.list(node, .arguments)?
			first_value := arguments[1]
			base := Finding{
				stmt:       c.es_tree_position(t, t.node(node, .callee)?)
				message_id: 'error'
				data:       {
					'objectType': 'object'
				}
			}
			is_object := t.typ(first_value) == .object_expression
			if unim_has_accessor_property(t, info.value) || (is_object
				&& (unim_has_accessor_property(t, first_value) || c.unim_has_prototype_property(t, first_value))) {
				return base
			}
			copied := if is_object {
				c.unim_properties_range(t, tokens, first_value)?
			} else {
				start, end := c.un_parenthesized_range(t, tokens, first_value)
				UnRange{start, end}
			}
			if un_would_remove_comments(tokens, t.nodes[info.next_statement].start, t.nodes[info.next_statement].end,
				[copied]) {
				return base
			}
			// The copied text keeps the comments inside it, like those of an empty `{/* c */}`.
			text := if is_object {
				c.src[copied.start..copied.end]
			} else {
				'...${c.un_parenthesized_text(t, tokens, first_value)}'
			}
			mut fixes := []Fix{}
			if js_trim(text) != '' {
				fixes << c.unim_append_list(t, tokens, info.value, text)?
			}
			if arguments.len != 2 {
				removal := c.un_argument_removal_range(t, tokens, first_value)?
				fixes << fix_remove_range(removal.start, removal.end)
			} else {
				fixes << c.unim_remove_statement_after_assign(t, tokens, info.next_statement)
			}
			return c.unim_finding(base, fixes, unim_side_effect(t, first_value), Suggestion{
				message_id: 'suggestion/object-assign'
				data:       {
					'description': if is_object {
						'Move properties to'
					} else {
						'Spread properties in'
					}
					'assignType':  info.assign_type
				}
			})
		}
		.set, .map {
			member := t.node(node, .callee)?
			base := Finding{
				stmt:       c.es_tree_position(t, member)
				message_id: 'error'
				data:       {
					'objectType': unim_object_type(t, info.value)
				}
			}
			if c.unim_has_comment_outside_arguments(t, tokens, node, info.next_statement) {
				return base
			}
			arguments_text := c.unb_call_arguments_text(t, tokens, node, false)?
			elements_text := if case == .map { '[${arguments_text}]' } else { arguments_text }
			fixes := c.unim_append_to_constructor(t, tokens, info.value, elements_text, info.next_statement) or {
				return base
			}
			suggest := (t.list(node, .arguments) or { []int{} }).any(unim_side_effect(t, it))
			return c.unim_finding(base, fixes, suggest, Suggestion{
				message_id: if case == .map { 'suggestion/map' } else { 'suggestion/set' }
				data:       {
					'assignType': info.assign_type
				}
			})
		}
	}
}

// ---- conditional mutations

// UnimConditional is the test and the branches of a conditional mutation.
struct UnimConditional {
	test       int
	consequent int
	alternate  int // -1 for none
}

// unim_only_expression ports getOnlyExpression: the expression of the only expression statement
// of a statement position, -1 for none.
fn unim_only_expression(t &estree.EsTree, node int) int {
	if node < 0 {
		return -1
	}
	mut statement := node
	if t.typ(node) == .block_statement {
		body := t.list(node, .body) or { return -1 }
		if body.len != 1 {
			return -1
		}
		statement = body[0]
	}
	if t.typ(statement) != .expression_statement {
		return -1
	}
	return t.node(statement, .expression) or { -1 }
}

// unim_conditional_mutation ports getConditionalMutation.
fn unim_conditional_mutation(t &estree.EsTree, statement int) ?UnimConditional {
	if t.typ(statement) == .if_statement {
		alternate_statement := t.node(statement, .alternate) or { -1 }
		consequent := unim_only_expression(t, t.node(statement, .consequent) or { -1 })
		alternate := unim_only_expression(t, alternate_statement)
		if consequent >= 0 && (alternate_statement < 0 || alternate >= 0) {
			return UnimConditional{
				test:       t.node(statement, .test)?
				consequent: consequent
				alternate:  alternate
			}
		}
		return none
	}
	expression := t.node(statement, .expression) or { return none }
	if t.typ(expression) == .conditional_expression {
		return UnimConditional{
			test:       t.node(expression, .test)?
			consequent: t.node(expression, .consequent)?
			alternate:  t.node(expression, .alternate)?
		}
	}
	if t.typ(expression) == .logical_expression
		&& (t.string_of(expression, .operator) or { '' }) == '&&' {
		return UnimConditional{
			test:       t.node(expression, .left)?
			consequent: t.node(expression, .right)?
			alternate:  -1
		}
	}
	return none
}

// unim_conditional_branch ports getConditionalBranch, as far as the problem needs it: whether the
// branch is a mutation of the case, and its method.
fn (mut c Checker) unim_conditional_branch(ctx &UnCtx, case UnimCase, info UnimInfo, node int) ?string {
	t := ctx.t
	problematic := c.unim_problematic_node(ctx, case, info, node)
	if problematic < 0 {
		return none
	}
	match case {
		.object_assignment {
			return ''
		}
		.object_assign {
			if (t.list(problematic, .arguments) or { []int{} }).len != 2 {
				return none
			}
			return ''
		}
		else {
			callee := t.node(problematic, .callee) or { return none }
			return t.string_of(t.node(callee, .property) or { return none }, .name) or { '' }
		}
	}
}

// unim_conditional_problem ports getConditionalProblem; in TypeScript it never fixes.
fn (mut c Checker) unim_conditional_problem(ctx &UnCtx, case UnimCase, info UnimInfo, conditional UnimConditional) ?Finding {
	t := ctx.t
	if c.unim_has_variable_in_nodes(ctx, info.variable, [conditional.test]) {
		return none
	}
	consequent := c.unim_conditional_branch(ctx, case, info, conditional.consequent)?
	if conditional.alternate >= 0 {
		alternate := c.unim_conditional_branch(ctx, case, info, conditional.alternate)?
		if alternate != consequent {
			return none
		}
	}
	return Finding{
		stmt:       c.es_tree_position(t, info.next_statement)
		message_id: 'error'
		data:       {
			'objectType': unim_object_type(t, info.value)
		}
	}
}

// ---- getCaseProblem

// unim_is_last_declarator ports isLastDeclarator.
fn unim_is_last_declarator(t &estree.EsTree, declarator int) bool {
	declaration := t.nodes[declarator].parent
	if declaration < 0 || t.typ(declaration) != .variable_declaration {
		return false
	}
	declarations := t.list(declaration, .declarations) or { return false }
	return declarations.len > 0 && declarations.last() == declarator
}

// unim_variable ports getVariable: the variable a declarator declares (with one definition), or
// the one an assignment's identifier refers to; -1 for none.
fn (mut c Checker) unim_variable(ctx &UnCtx, node int) int {
	t := ctx.t
	tree := c.scope_tree(ctx.root)
	if t.typ(node) == .variable_declarator {
		id := t.node(node, .id) or { return -1 }
		ts := t.ts_node(id) or { return -1 }
		v := tree.declared_variable(ts)
		if v < 0 || tree.variables[v].defs.len != 1
			|| node_key(tree.variables[v].defs[0].name) != node_key(ts) {
			return -1
		}
		return v
	}
	return c.un_find_variable(ctx, t.node(node, .left) or { return -1 })
}

// unim_case_problem ports getCaseProblem.
fn (mut c Checker) unim_case_problem(mut ctx UnCtx, node int, case UnimCase, check_conditionals bool) ?Finding {
	t := ctx.t
	is_assignment := t.typ(node) == .assignment_expression
	variable_node := t.node(node, if is_assignment { estree.Key.left } else { estree.Key.id })?
	value := t.node(node, if is_assignment { estree.Key.right } else { estree.Key.init }) or { -1 }
	if t.typ(variable_node) != .identifier || !unim_test_value(t, case, value) {
		return none
	}
	statement := t.nodes[node].parent
	if statement < 0 {
		return none
	}
	if !((is_assignment && (t.string_of(node, .operator) or { '' }) == '='
		&& t.typ(statement) == .expression_statement
		&& (t.node(statement, .expression) or { -1 }) == node)
		|| (!is_assignment && unim_is_last_declarator(t, node))) {
		return none
	}
	next_statement := unb_sibling(t, statement, 1)
	if next_statement < 0 || t.typ(next_statement) !in [.expression_statement, .if_statement] {
		return none
	}
	variable := c.unim_variable(ctx, node)
	if variable < 0 {
		return none
	}
	info := UnimInfo{
		variable:       variable
		value:          value
		next_statement: next_statement
		assign_type:    if is_assignment { 'assignment' } else { 'declaration' }
	}
	if conditional := unim_conditional_mutation(t, next_statement) {
		if !check_conditionals {
			return none
		}
		return c.unim_conditional_problem(ctx, case, info, conditional)
	}
	if t.typ(next_statement) != .expression_statement {
		return none
	}
	problematic := c.unim_problematic_node(ctx, case, info, t.node(next_statement, .expression) or {
		-1
	})
	if problematic < 0 {
		return none
	}
	return c.unim_problem(ctx, case, info, problematic)
}

// ---- initialization

// unim_initialization_targets ports getInitializationTargetNames: the identifiers an assignment
// target names (an identifier, or an array pattern of distinct unparenthesized identifiers).
fn (c &Checker) unim_initialization_targets(t &estree.EsTree, tokens &SourceTokens, node int) ?[]string {
	targets := if t.typ(node) == .array_pattern {
		(t.list(node, .elements) or { []int{} }).filter(it >= 0)
	} else {
		[node]
	}
	if targets.len == 0 || targets.any(t.typ(it) != .identifier)
		|| (t.typ(node) == .array_pattern && targets.any(c.un_is_parenthesized(t, tokens, it))) {
		return none
	}
	mut found := []string{}
	for target in targets {
		name := t.string_of(target, .name) or { return none }
		if name in found {
			return none
		}
		found << name
	}
	return found
}

// unim_is_simple_value ports isSimpleInitializationValue.
fn unim_is_simple_value(t &estree.EsTree, from int) bool {
	node := un_unwrap_ts_expression(t, from)
	if node < 0 {
		return false
	}
	match t.typ(node) {
		.identifier, .literal, .function_expression, .arrow_function_expression {
			return true
		}
		.template_literal {
			return (t.list(node, .expressions) or { []int{} }).len == 0
		}
		.unary_expression {
			argument := un_unwrap_ts_expression(t, t.node(node, .argument) or { return false })
			if argument < 0 || (t.string_of(node, .operator) or { '' }) != '-'
				|| t.typ(argument) != .literal {
				return false
			}
			v := t.get(argument, .value)
			return v is f64 || t.prop(argument, .bigint) != none
		}
		.array_expression {
			return (t.list(node, .elements) or { []int{} }).all(it < 0 || unim_is_simple_value(t, it))
		}
		.object_expression {
			return (t.list(node, .properties) or { []int{} }).all(t.typ(it) == .property
				&& !(t.flag(it, .computed) or { false })
				&& unim_is_simple_value(t, t.node(it, .value) or { -1 }))
		}
		else {
			return false
		}
	}
}

// unim_initialization_problem ports getInitializationProblem: `let a; a = 1;`.
fn (mut c Checker) unim_initialization_problem(mut ctx UnCtx, declaration int) ?Finding {
	t := ctx.t
	tokens := ctx.tokens
	kind := t.string_of(declaration, .kind)?
	declarations := t.list(declaration, .declarations)?
	if kind !in ['let', 'var'] || (t.flag(declaration, .declare_) or { false })
		|| declarations.any(t.node(it, .init) != none
			|| t.typ(t.node(it, .id) or { -1 }) != .identifier) {
		return none
	}
	next_statement := unb_sibling(t, declaration, 1)
	if next_statement < 0 || t.typ(next_statement) != .expression_statement {
		return none
	}
	assignment := t.node(next_statement, .expression)?
	if t.typ(assignment) != .assignment_expression
		|| (t.string_of(assignment, .operator) or { '' }) != '=' {
		return none
	}
	left := t.node(assignment, .left)?
	right := t.node(assignment, .right)?
	target_names := c.unim_initialization_targets(t, tokens, left)?
	declarators := declarations.filter((t.string_of(t.node(it, .id) or { -1 }, .name) or { '' }) in target_names)
	if declarators.len != target_names.len {
		return none
	}
	for declarator in declarators {
		v := c.unim_variable(ctx, declarator)
		if v < 0 || c.unim_has_variable_in_nodes(ctx, v, [right]) {
			return none
		}
	}
	base := Finding{
		stmt:       c.es_tree_position(t, assignment)
		message_id: 'initialization'
	}
	right_start, right_end := c.un_parenthesized_range(t, tokens, right)
	if un_would_remove_comments(tokens, t.nodes[declaration].start, t.nodes[declaration].end,
		declarations.map(un_range(t, it)))
		|| un_would_remove_comments(tokens, t.nodes[next_statement].start, t.nodes[next_statement].end,
			[un_range(t, left), UnRange{right_start, right_end}])
		|| declarators.any((t.flag(it, .definite) or { false }) || (t.typ(left) == .array_pattern
			&& t.node(t.node(it, .id) or { -1 }, .type_annotation) != none)) {
		return base
	}
	mut fixes := []Fix{}
	remaining := declarations.filter((t.string_of(t.node(it, .id) or { -1 }, .name) or { '' }) !in target_names)
	if remaining.len > 0 {
		texts := remaining.map(c.src[t.nodes[it].start..t.nodes[it].end])
		fixes << fix_replace_range(t.nodes[declaration].start, t.nodes[declaration].end, '${kind} ${texts.join(', ')};')
	} else {
		fixes << c.unim_remove_statement(t, tokens, declaration, declaration, false)
	}
	target := if t.typ(left) == .identifier { t.node(declarators[0], .id)? } else { left }
	target_text := c.src[t.nodes[target].start..t.nodes[target].end]
	fixes << fix_replace_range(t.nodes[next_statement].start, t.nodes[next_statement].end,
		'${kind} ${target_text} = ${c.un_parenthesized_text(t, tokens, right)};')
	// In TypeScript an unannotated variable would narrow its inferred type; destructuring and
	// other initializers can run user code.
	suggest := t.typ(left) == .array_pattern || c.un_is_parenthesized(t, tokens, left)
		|| !unim_is_simple_value(t, right)
		|| declarators.any(t.node(t.node(it, .id) or { -1 }, .type_annotation) == none)
	return c.unim_finding(base, fixes, suggest, Suggestion{
		message_id: 'suggestion/initialization'
	})
}
