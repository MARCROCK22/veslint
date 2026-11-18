module rules

import estree
import esquery
import jsregexp
import time
import x.json2

// Port of the `@stylistic/no-extra-parens` rule of @stylistic/eslint-plugin 6.0.1, with its
// options (`"all"`, the default, or `"functions"`, and conditionalAssign,
// ternaryOperandBinaryExpressions, nestedBinaryExpressions, returnAssign, ignoreJSX,
// enforceForArrowConditionals, enforceForSequenceExpressions, enforceForNewInMemberExpressions,
// enforceForFunctionPrototypeMethods, allowParensAfterCommentPattern,
// nestedConditionalExpressions, allowNodesInSpreadElement and ignoredNodes) and its fixes.
//
// The rule queues its listeners and runs them at `Program:exit`, skipping the nodes of
// `ignoredNodes`; this port does the same with the traversal's events.

const snep_messages = {
	'unexpected': 'Unnecessary parentheses around expression.'
}

const snep_precedence_assignment = 1
const snep_precedence_update = 17
const snep_precedence_or = 4

struct SnepOptions {
	all_nodes                   bool
	except_cond_assign          bool
	except_cond_ternary         bool
	ignore_nested_binary        bool
	except_return_assign        bool
	ignore_jsx                  string
	ignore_arrow_conditionals   bool
	ignore_sequence_expressions bool
	ignore_new_in_member_expr   bool
	ignore_function_prototype   bool
	allow_parens_after_comment  string
	allow_nested_ternary        bool
	has_allow_nodes_in_spread   bool // `ALL_NODES && options`: a set, even an empty one
	allow_nodes_in_spread       []string
	ignored_nodes               []string
}

fn snep_options(given []json2.Any) !SnepOptions {
	options := sty_options(given, [json2.Any('all')])
	all_nodes := sty_option_string(options, 0, '') != 'functions'
	has_object := options.len > 1 && options[1] is map[string]json2.Any
	object := sty_option_object(options, 1)
	is_false := fn [object, all_nodes] (key string) bool {
		value := sty_option_bool(object, key) or { return false }
		return all_nodes && !value
	}
	string_option := fn [object, all_nodes] (key string) string {
		value := object[key] or { return '' }
		return if all_nodes && value is string { value } else { '' }
	}
	mut allow_in_spread := []string{}
	allow := sls_object(object['allowNodesInSpreadElement'] or { json2.Any(json2.Null{}) })
	for key, value in allow {
		if value is bool && value {
			allow_in_spread << key
		}
	}
	mut ignored := []string{}
	if list := object['ignoredNodes'] {
		if list is []json2.Any {
			for item in list {
				if item is string {
					ignored << item
				}
			}
		}
	}
	return SnepOptions{
		all_nodes:                   all_nodes
		except_cond_assign:          is_false('conditionalAssign')
		except_cond_ternary:         is_false('ternaryOperandBinaryExpressions')
		ignore_nested_binary:        is_false('nestedBinaryExpressions')
		except_return_assign:        is_false('returnAssign')
		ignore_jsx:                  string_option('ignoreJSX')
		ignore_arrow_conditionals:   is_false('enforceForArrowConditionals')
		ignore_sequence_expressions: is_false('enforceForSequenceExpressions')
		ignore_new_in_member_expr:   is_false('enforceForNewInMemberExpressions')
		ignore_function_prototype:   is_false('enforceForFunctionPrototypeMethods')
		allow_parens_after_comment:  string_option('allowParensAfterCommentPattern')
		allow_nested_ternary:        is_false('nestedConditionalExpressions')
		has_allow_nodes_in_spread:   all_nodes && has_object
		allow_nodes_in_spread:       allow_in_spread
		ignored_nodes:               ignored
	}
}

struct SnepBuffered {
	node    int
	finding Finding
}

struct SnepBuffer {
mut:
	in_expression_nodes []int
	reports             []SnepBuffered
}

struct SnepCtx {
	c       &Checker
	t       &estree.EsTree
	tokens  &SourceTokens
	options SnepOptions
	regex   ?jsregexp.JsRegex
mut:
	tokens_to_ignore map[int]bool // by the start of the token
	buffers          []SnepBuffer // reportsBuffer, the innermost last
	findings         []Finding
}

// SnepEvent is a queued call of a listener: entering the node, or the exit of the init of a
// `for` (`ForStatement > *.init:exit`).
struct SnepEvent {
	node      int
	init_exit bool
}

fn (mut c Checker) lint_stylistic_no_extra_parens(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	options := snep_options(c.rule_options(stylistic_no_extra_parens))!
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut regex := ?jsregexp.JsRegex(none)
	if options.allow_parens_after_comment != '' {
		regex = jsregexp.js_regex_new(options.allow_parens_after_comment, 'u') or { none }
	}
	mut x := SnepCtx{
		c:       c
		t:       t
		tokens:  c.un_tokens(t)
		options: options
		regex:   regex
	}
	mut ignored := map[int]bool{}
	if options.ignored_nodes.len > 0 {
		for m in esquery.run(t, options.ignored_nodes)! {
			ignored[m.node] = true
		}
	}
	mut queue := []SnepEvent{}
	for step in t.steps() {
		node := step.node
		if step.leave {
			parent := t.nodes[node].parent
			if parent >= 0 && t.typ(parent) == .for_statement
				&& (t.node(parent, .init) or { -1 }) == node {
				queue << SnepEvent{node, true}
			}
			continue
		}
		queue << SnepEvent{node, false}
	}
	for event in queue {
		if ignored[event.node] {
			continue
		}
		if event.init_exit {
			x.init_exit(event.node)
		} else if x.listen(event.node) {
			stats.checked++
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return x.findings
}

fn (x &SnepCtx) child(node int, key estree.Key) int {
	return x.t.node(node, key) or { -1 }
}

fn (x &SnepCtx) children(node int, key estree.Key) []int {
	return x.t.list(node, key) or { []int{} }
}

fn (x &SnepCtx) flag(node int, key estree.Key) bool {
	return x.t.flag(node, key) or { false }
}

fn (x &SnepCtx) operator(node int) string {
	return x.t.string_of(node, .operator) or { '' }
}

// is_type_assertion ports isTypeAssertion.
fn (x &SnepCtx) is_type_assertion(node int) bool {
	return node >= 0 && x.t.typ(node) in [.ts_as_expression, .ts_satisfies_expression,
		.ts_type_assertion]
}

// precedence ports getPrecedence (every node type is one of @typescript-eslint/visitor-keys,
// which gives 20 by default).
fn (x &SnepCtx) precedence(node int) int {
	typ := x.t.typ(node)
	match typ {
		.sequence_expression {
			return 0
		}
		.assignment_expression, .arrow_function_expression, .yield_expression, .ts_function_type,
		.ts_constructor_type {
			return 1
		}
		.ts_as_expression, .ts_non_null_expression, .ts_satisfies_expression, .ts_type_assertion {
			return 2
		}
		.conditional_expression, .ts_conditional_type {
			return 3
		}
		.logical_expression, .binary_expression {
			operator := x.operator(node)
			if typ == .logical_expression {
				if operator in ['||', '??'] {
					return 4
				}
				if operator == '&&' {
					return 5
				}
			}
			return match operator {
				'|' { 6 }
				'^' { 7 }
				'&' { 8 }
				'==', '!=', '===', '!==' { 9 }
				'<', '<=', '>', '>=', 'in', 'instanceof' { 10 }
				'<<', '>>', '>>>' { 11 }
				'+', '-' { 12 }
				'*', '/', '%' { 13 }
				'**' { 15 }
				else { 6 }
			}
		}
		.ts_union_type {
			return 6
		}
		.ts_intersection_type {
			return 8
		}
		.ts_type_operator {
			return if x.operator(node) == 'keyof' { 10 } else { 16 }
		}
		// veslint gives `infer` the precedence of the other type operators on purpose (@stylistic
		// 6.0.1 gives it none, the highest): TypeScript reads `infer M[]` as `infer (M[])`, so the
		// parentheses of `(infer M)[]` and `(infer M)['k']` are needed, and removing them breaks the
		// code ("'?' expected").
		.ts_infer_type {
			return 16
		}
		.unary_expression, .await_expression {
			return 16
		}
		.update_expression {
			return 17
		}
		.call_expression, .chain_expression, .import_expression {
			return 18
		}
		.new_expression {
			return 19
		}
		else {
			return 20
		}
	}
}

// layers counts the parentheses around the node (isParenthesized of eslint-utils with growing
// `times`): not those of its parent's syntax.
fn (x &SnepCtx) layers(node int) int {
	t := x.t
	parent := t.nodes[node].parent
	if parent < 0 || (t.typ(parent) == .catch_clause && x.child(parent, .param) == node) {
		return 0
	}
	syntax := x.c.un_parent_syntax_paren(t, x.tokens, node)
	mut head := t.nodes[node].start
	mut tail := t.nodes[node].end
	mut count := 0
	for {
		before := x.tokens.before(head, false) or { break }
		after := x.tokens.after(tail, false) or { break }
		if !x.c.token_is(before, '(') || !x.c.token_is(after, ')') {
			break
		}
		if s := syntax {
			if s.start == before.start {
				break
			}
		}
		count++
		head = before.start
		tail = after.end
	}
	return count
}

fn (x &SnepCtx) is_parenthesised(node int) bool {
	return x.layers(node) >= 1
}

fn (x &SnepCtx) is_parenthesised_twice(node int) bool {
	return x.layers(node) >= 2
}

fn (x &SnepCtx) is_single_line(node int) bool {
	return sty_same_line_offsets(x.t, x.t.nodes[node].start, x.t.nodes[node].end)
}

// skip_chain ports skipChainExpression.
fn (x &SnepCtx) skip_chain(node int) int {
	if node >= 0 && x.t.typ(node) == .chain_expression {
		return x.child(node, .expression)
	}
	return node
}

// is_immediate_function_prototype_method_call ports isImmediateFunctionPrototypeMethodCall.
fn (x &SnepCtx) is_immediate_function_prototype_method_call(node int) bool {
	call := x.skip_chain(node)
	if call < 0 || x.t.typ(call) != .call_expression {
		return false
	}
	callee := x.skip_chain(x.child(call, .callee))
	if callee < 0 || x.t.typ(callee) != .member_expression {
		return false
	}
	object := x.child(callee, .object)
	if object < 0 || x.t.typ(object) != .function_expression {
		return false
	}
	name := es_tree_static_property_name(x.t, callee) or { return false }
	return name in ['call', 'apply']
}

// rule_applies ports ruleApplies.
fn (x &SnepCtx) rule_applies(node int) bool {
	o := x.options
	typ := x.t.typ(node)
	if typ in [.jsx_element, .jsx_fragment] {
		match o.ignore_jsx {
			'all' { return false }
			'multi-line' { return x.is_single_line(node) }
			'single-line' { return !x.is_single_line(node) }
			else {}
		}
	}
	if typ == .sequence_expression && o.ignore_sequence_expressions {
		return false
	}
	if o.ignore_function_prototype && x.is_immediate_function_prototype_method_call(node) {
		return false
	}
	if typ in [.function_expression, .arrow_function_expression] {
		return true
	}
	if x.is_type_assertion(node) {
		return true
	}
	return o.all_nodes
}

fn (x &SnepCtx) has_excess_parens(node int) bool {
	return x.rule_applies(node) && x.is_parenthesised(node)
}

fn (x &SnepCtx) has_double_excess_parens(node int) bool {
	return x.rule_applies(node) && x.is_parenthesised_twice(node)
}

fn (x &SnepCtx) has_excess_parens_with_precedence(node int, lower_limit int) bool {
	if !x.rule_applies(node) {
		return false
	}
	return if x.precedence(node) >= lower_limit {
		x.is_parenthesised(node)
	} else {
		x.is_parenthesised_twice(node)
	}
}

// is_cond_assign_exception ports isCondAssignException with the type of the test.
fn (x &SnepCtx) is_cond_assign_exception(test_typ ?estree.NodeType) bool {
	typ := test_typ or { return false }
	return x.options.except_cond_assign && typ == .assignment_expression
}

fn (x &SnepCtx) test_type(node int) ?estree.NodeType {
	test := x.child(node, .test)
	return if test >= 0 { x.t.typ(test) } else { none }
}

// is_in_return_statement ports isInReturnStatement.
fn (x &SnepCtx) is_in_return_statement(node int) bool {
	mut current := node
	for current >= 0 {
		typ := x.t.typ(current)
		if typ == .return_statement {
			return true
		}
		if typ == .arrow_function_expression {
			body := x.child(current, .body)
			if body >= 0 && x.t.typ(body) != .block_statement {
				return true
			}
		}
		current = x.t.nodes[current].parent
	}
	return false
}

// is_new_expression_with_parens ports isNewExpressionWithParens.
fn (x &SnepCtx) is_new_expression_with_parens(node int) bool {
	t := x.t
	if x.children(node, .arguments).len > 0 {
		return true
	}
	last := un_last_token(t, x.tokens, node) or { return false }
	penultimate := x.tokens.before(last.start, false) or { return false }
	callee := x.child(node, .callee)
	return x.c.token_is(penultimate, '(') && x.c.token_is(last, ')') && callee >= 0
		&& t.nodes[callee].end < t.nodes[node].end
}

// is_member_exp_in_new_callee ports isMemberExpInNewCallee.
fn (x &SnepCtx) is_member_exp_in_new_callee(node int) bool {
	if x.t.typ(node) != .member_expression {
		return false
	}
	parent := x.t.nodes[node].parent
	if parent < 0 {
		return false
	}
	if x.t.typ(parent) == .new_expression && x.child(parent, .callee) == node {
		return true
	}
	return x.child(parent, .object) == node && x.is_member_exp_in_new_callee(parent)
}

// does_member_expression_contain_call_expression ports doesMemberExpressionContainCallExpression.
fn (x &SnepCtx) does_member_expression_contain_call_expression(node int) bool {
	mut current := x.child(node, .object)
	for current >= 0 && x.t.typ(current) == .member_expression {
		current = x.child(current, .object)
	}
	return current >= 0 && x.t.typ(current) == .call_expression
}

// contains_assignment ports containsAssignment.
fn (x &SnepCtx) contains_assignment(node int) bool {
	t := x.t
	typ := t.typ(node)
	if typ == .assignment_expression {
		return true
	}
	if typ == .conditional_expression {
		consequent := x.child(node, .consequent)
		alternate := x.child(node, .alternate)
		if (consequent >= 0 && t.typ(consequent) == .assignment_expression)
			|| (alternate >= 0 && t.typ(alternate) == .assignment_expression) {
			return true
		}
	}
	if typ in [.binary_expression, .logical_expression, .assignment_pattern] {
		left := x.child(node, .left)
		right := x.child(node, .right)
		if (left >= 0 && t.typ(left) == .assignment_expression)
			|| (right >= 0 && t.typ(right) == .assignment_expression) {
			return true
		}
	}
	return false
}

// is_return_assign_exception ports isReturnAssignException.
fn (x &SnepCtx) is_return_assign_exception(node int) bool {
	if !x.options.except_return_assign || !x.is_in_return_statement(node) {
		return false
	}
	typ := x.t.typ(node)
	if typ == .return_statement {
		argument := x.child(node, .argument)
		return argument >= 0 && x.contains_assignment(argument)
	}
	if typ == .arrow_function_expression {
		body := x.child(node, .body)
		if body >= 0 && x.t.typ(body) != .block_statement {
			return x.contains_assignment(body)
		}
	}
	return x.contains_assignment(node)
}

// has_excess_parens_no_line_terminator ports hasExcessParensNoLineTerminator.
fn (x &SnepCtx) has_excess_parens_no_line_terminator(token SourceToken, node int) bool {
	if sty_same_line_offsets(x.t, token.end, x.t.nodes[node].start) {
		return x.has_excess_parens(node)
	}
	return x.has_double_excess_parens(node)
}

// requires_leading_space ports requiresLeadingSpace.
fn (x &SnepCtx) requires_leading_space(node int) bool {
	left := x.tokens.before(x.t.nodes[node].start, false) or { return false }
	before := x.tokens.before(left.start, true) or { return false }
	after := x.tokens.after(left.end, true) or { return false }
	return before.end == left.start && left.end == after.start
		&& !x.c.es_can_tokens_be_adjacent(before, after)
}

// requires_trailing_space ports requiresTrailingSpace.
fn (x &SnepCtx) requires_trailing_space(node int) bool {
	right := x.tokens.after(x.t.nodes[node].end, false) or { return false }
	after := x.tokens.after(right.end, false) or { return false }
	before := un_last_token(x.t, x.tokens, node) or { return false }
	return !x.tokens.is_space_between(right.end, after.start)
		&& !x.c.es_can_tokens_be_adjacent(before, after)
}

// is_iife ports isIIFE.
fn (x &SnepCtx) is_iife(node int) bool {
	call := x.skip_chain(node)
	if call < 0 || x.t.typ(call) != .call_expression {
		return false
	}
	callee := x.child(call, .callee)
	return callee >= 0 && x.t.typ(callee) == .function_expression
}

// can_be_assignment_target ports canBeAssignmentTarget.
fn (x &SnepCtx) can_be_assignment_target(node int) bool {
	return node >= 0 && x.t.typ(node) in [.identifier, .member_expression]
}

fn (x &SnepCtx) is_regexp_literal(node int) bool {
	return x.t.typ(node) == .literal && x.t.prop(node, .regex) != none
}

// is_decimal_integer ports isDecimalInteger: /^(?:0|0[0-7]*[89]\d*|[1-9](?:_?\d)*)$/u on the raw.
fn (x &SnepCtx) is_decimal_integer(node int) bool {
	if x.t.typ(node) != .literal || x.t.get(node, .value) !is f64 {
		return false
	}
	raw := x.t.string_of(node, .raw) or { return false }
	if raw == '0' {
		return true
	}
	if raw.len == 0 || !raw.bytes().all(it.is_digit() || it == `_`) {
		return false
	}
	if raw[0] == `0` {
		// 0[0-7]*[89]\d*
		mut i := 1
		for i < raw.len && raw[i] >= `0` && raw[i] <= `7` {
			i++
		}
		if i >= raw.len || (raw[i] != `8` && raw[i] != `9`) {
			return false
		}
		return raw[i..].bytes().all(it.is_digit())
	}
	// [1-9](?:_?\d)*
	mut i := 1
	for i < raw.len {
		if raw[i] == `_` {
			i++
			if i >= raw.len || !raw[i].is_digit() {
				return false
			}
		}
		i++
	}
	return true
}

// is_fixable ports isFixable.
fn (x &SnepCtx) is_fixable(node int) bool {
	if x.t.typ(node) != .literal || x.t.get(node, .value) !is string {
		return true
	}
	if x.is_parenthesised_twice(node) {
		return true
	}
	// !isTopLevelExpressionStatement(node.parent)
	parent := x.t.nodes[node].parent
	if parent < 0 || x.t.typ(parent) != .expression_statement {
		return true
	}
	grand := x.t.nodes[parent].parent
	if grand < 0 {
		return true
	}
	if x.t.typ(grand) == .program {
		return false
	}
	if x.t.typ(grand) == .block_statement {
		function := x.t.nodes[grand].parent
		if function >= 0 && x.t.typ(function) in [.function_declaration, .function_expression,
			.arrow_function_expression] {
			return false
		}
	}
	return true
}

// snep_jsdoc_type: /@type\s*\{[^}]+\}/ matches the text.
fn snep_jsdoc_type(text string) bool {
	runes := text.runes()
	for start := 0; start + 5 <= runes.len; start++ {
		if runes[start..start + 5].string() != '@type' {
			continue
		}
		mut i := start + 5
		for i < runes.len && is_js_space(runes[i]) {
			i++
		}
		if i >= runes.len || runes[i] != `{` {
			continue
		}
		i++
		mut n := 0
		for i < runes.len && runes[i] != `}` {
			i++
			n++
		}
		if n > 0 && i < runes.len {
			return true
		}
	}
	return false
}

// is_allowed_by_comment_directive ports isAllowedByCommentDirective.
fn (x &SnepCtx) is_allowed_by_comment_directive(left SourceToken) bool {
	comments := x.tokens.comments_before(left.start)
	if comments.len == 0 {
		return false
	}
	last := comments.last()
	value := es_comment_value(x.c.token_text(last))
	if last.kind == .block_comment && value.starts_with('*') && snep_jsdoc_type(value) {
		return true
	}
	if regex := x.regex {
		if regex.test(utf16_units(value)) or { false } {
			return true
		}
	}
	return false
}

// report ports report.
fn (mut x SnepCtx) report(node int) {
	t := x.t
	mut left := x.tokens.before(t.nodes[node].start, false) or { return }
	mut right := x.tokens.after(t.nodes[node].end, false) or { return }
	if !x.is_parenthesised_twice(node) {
		first := un_first_token(t, x.tokens, node, 0) or { return }
		if x.tokens_to_ignore[first.start] {
			return
		}
		if x.is_iife(node) {
			// !("callee" in node && isParenthesised(node.callee))
			callee := if t.typ(node) == .call_expression { x.child(node, .callee) } else { -1 }
			if callee < 0 || !x.is_parenthesised(callee) {
				return
			}
		}
	}
	mut paren_layers := 2
	for x.is_allowed_by_comment_directive(left) {
		if x.layers(node) < paren_layers {
			return
		}
		mut index := source_tokens_index(x.tokens.tokens, left.start) - 1
		for index >= 0 && !x.c.token_is(x.tokens.tokens[index], '(') {
			index--
		}
		if index < 0 {
			return
		}
		left = x.tokens.tokens[index]
		index = source_tokens_index(x.tokens.tokens, right.end)
		for index < x.tokens.tokens.len && !x.c.token_is(x.tokens.tokens[index], ')') {
			index++
		}
		if index >= x.tokens.tokens.len {
			return
		}
		right = x.tokens.tokens[index]
		paren_layers++
	}
	mut has_fix := false
	mut fix := Fix{}
	if x.is_fixable(node) {
		has_fix, fix = x.c.merge_fixes([
			fix_replace_range(left.start, left.end, if x.requires_leading_space(node) {
				' '
			} else {
				''
			}),
			fix_replace_range(right.start, right.end, if x.requires_trailing_space(node) {
				' '
			} else {
				''
			}),
		]) or { false, Fix{} }
	}
	finding := Finding{
		stmt:       x.c.position_range(left.start, left.end)
		message_id: 'unexpected'
		has_fix:    has_fix
		fix:        fix
	}
	if x.buffers.len > 0 {
		x.buffers[x.buffers.len - 1].reports << SnepBuffered{node, finding}
		return
	}
	x.findings << finding
}

// end_current_reports_buffering ports endCurrentReportsBuffering.
fn (mut x SnepCtx) end_current_reports_buffering() {
	if x.buffers.len == 0 {
		return
	}
	top := x.buffers.pop()
	if x.buffers.len > 0 {
		x.buffers[x.buffers.len - 1].in_expression_nodes << top.in_expression_nodes
		x.buffers[x.buffers.len - 1].reports << top.reports
		return
	}
	for report in top.reports {
		x.findings << report.finding
	}
}

fn (x &SnepCtx) is_in_current_reports_buffer(node int) bool {
	if x.buffers.len == 0 {
		return false
	}
	return x.buffers.last().reports.any(it.node == node)
}

// is_safely_enclosing_in_expression ports isSafelyEnclosingInExpression.
fn (x &SnepCtx) is_safely_enclosing_in_expression(node int, child int) bool {
	match x.t.typ(node) {
		.array_expression, .array_pattern, .block_statement, .object_expression, .object_pattern,
		.template_literal {
			return true
		}
		.arrow_function_expression, .function_expression {
			return child in x.children(node, .params)
		}
		.call_expression, .new_expression {
			return child in x.children(node, .arguments)
		}
		.member_expression {
			return x.flag(node, .computed) && x.child(node, .property) == child
		}
		.conditional_expression {
			return x.child(node, .consequent) == child
		}
		else {
			return false
		}
	}
}

// init_exit ports the `ForStatement > *.init:exit` listener.
fn (mut x SnepCtx) init_exit(node int) {
	if x.is_type_assertion(node) {
		return
	}
	if x.buffers.len > 0 && x.buffers.last().reports.len > 0 {
		for in_expression_node in x.buffers.last().in_expression_nodes {
			// pathToDescendant(node, inExpressionNode).
			mut path := [in_expression_node]
			mut current := in_expression_node
			for current != node && current >= 0 {
				current = x.t.nodes[current].parent
				path << current
			}
			if current != node {
				continue
			}
			path = path.reverse()
			mut node_to_exclude := -1
			mut skip := false
			for i, path_node in path {
				if i < path.len - 1 && x.is_safely_enclosing_in_expression(path_node, path[i + 1]) {
					skip = true
					break
				}
				if x.is_parenthesised(path_node) {
					if x.is_in_current_reports_buffer(path_node) {
						if x.is_parenthesised_twice(path_node) {
							skip = true
							break
						}
						if node_to_exclude < 0 {
							node_to_exclude = path_node
						}
					} else {
						skip = true
						break
					}
				}
			}
			if !skip && node_to_exclude >= 0 {
				// removeFromCurrentReportsBuffer.
				last := x.buffers.len - 1
				x.buffers[last].reports = x.buffers[last].reports.filter(it.node != node_to_exclude)
			}
		}
	}
	x.end_current_reports_buffering()
}

// first_token_not_paren is getFirstToken(node, isNotOpeningParenToken).
fn (x &SnepCtx) first_token_not_paren(node int) ?SourceToken {
	for token in x.tokens.inside(x.t.nodes[node].start, x.t.nodes[node].end, false) {
		if !x.c.token_is(token, '(') {
			return token
		}
	}
	return none
}

// token_after_not is getTokenAfter(token, token => token is not that punctuator).
fn (x &SnepCtx) token_after_not(token SourceToken, punctuator string) ?SourceToken {
	for i := source_tokens_index(x.tokens.tokens, token.end); i < x.tokens.tokens.len; i++ {
		if !x.c.token_is(x.tokens.tokens[i], punctuator) {
			return x.tokens.tokens[i]
		}
	}
	return none
}

// ignore_let_bracket: the `let` of a `let[…]` that starts the left side of a `for`.
fn (mut x SnepCtx) ignore_let(node int, needs_bracket bool) {
	first := x.first_token_not_paren(node) or { return }
	if x.c.token_text(first) != 'let' {
		return
	}
	if needs_bracket {
		after := x.token_after_not(first, ')') or { return }
		if !x.c.token_is(after, '[') {
			return
		}
	}
	x.tokens_to_ignore[first.start] = true
}

// check_argument_with_precedence ports checkArgumentWithPrecedence.
fn (mut x SnepCtx) check_argument_with_precedence(node int) {
	argument := x.child(node, .argument)
	if argument >= 0 && x.has_excess_parens_with_precedence(argument, x.precedence(node)) {
		x.report(argument)
	}
}

fn (x &SnepCtx) is_logical(node int) bool {
	return x.t.typ(node) == .logical_expression && x.operator(node) in ['&&', '||']
}

fn (x &SnepCtx) is_coalesce(node int) bool {
	return x.t.typ(node) == .logical_expression && x.operator(node) == '??'
}

// is_mixed_logical_and_coalesce_expressions ports isMixedLogicalAndCoalesceExpressions.
fn (x &SnepCtx) is_mixed_logical_and_coalesce_expressions(left int, right int) bool {
	return (x.is_logical(left) && x.is_coalesce(right))
		|| (x.is_coalesce(left) && x.is_logical(right))
}

// check_binary_logical_should_skip ports shouldSkip of checkBinaryLogical.
fn (x &SnepCtx) check_binary_logical_should_skip(expression int) bool {
	if x.is_type_assertion(expression) {
		return !x.has_double_excess_parens(expression)
	}
	return (x.options.ignore_nested_binary
		&& x.t.typ(expression) in [.binary_expression, .logical_expression])
		|| !x.has_excess_parens(expression)
}

// check_binary_logical ports checkBinaryLogical.
fn (mut x SnepCtx) check_binary_logical(node int) {
	t := x.t
	left := x.child(node, .left)
	right := x.child(node, .right)
	if left < 0 || right < 0 {
		return
	}
	node_precedence := x.precedence(node)
	is_exponentiation := x.operator(node) == '**'
	if !x.check_binary_logical_should_skip(left) {
		left_precedence := x.precedence(left)
		parent := t.nodes[node].parent
		// The parent is a ReturnStatement spanning multiple lines without parentheses.
		return_exception := parent >= 0 && t.typ(parent) == .return_statement
			&& !sty_same_line_offsets(t, t.nodes[parent].start, t.nodes[left].start)
			&& !x.is_parenthesised(node)
		if (!(t.typ(left) in [.await_expression, .unary_expression] && is_exponentiation)
			&& !return_exception && !x.is_mixed_logical_and_coalesce_expressions(left, node)
			&& (left_precedence > node_precedence
				|| (left_precedence == node_precedence && !is_exponentiation)))
			|| x.is_parenthesised_twice(left) {
			x.report(left)
		}
	}
	if !x.check_binary_logical_should_skip(right) {
		right_precedence := x.precedence(right)
		if (!x.is_mixed_logical_and_coalesce_expressions(right, node)
			&& (right_precedence > node_precedence
				|| (right_precedence == node_precedence && is_exponentiation)))
			|| x.is_parenthesised_twice(right) {
			x.report(right)
		}
	}
}

// check_call_new ports checkCallNew.
fn (mut x SnepCtx) check_call_new(node int) {
	t := x.t
	callee := x.child(node, .callee)
	if callee < 0 {
		return
	}
	typ := t.typ(node)
	callee_typ := t.typ(callee)
	if x.has_excess_parens_with_precedence(callee, x.precedence(node)) {
		optional := typ == .call_expression && x.flag(node, .optional)
		if x.has_double_excess_parens(callee) || !(x.is_iife(node)
			|| (callee_typ == .new_expression && !x.is_new_expression_with_parens(callee)
				&& !(typ == .new_expression && !x.is_new_expression_with_parens(node)))
			|| (typ == .new_expression && callee_typ == .member_expression
				&& x.does_member_expression_contain_call_expression(callee))
			|| (!optional && callee_typ == .chain_expression)) {
			x.report(callee)
		}
	}
	for argument in x.children(node, .arguments) {
		if x.has_excess_parens_with_precedence(argument, snep_precedence_assignment) {
			x.report(argument)
		}
	}
}

// check_class ports checkClass.
fn (mut x SnepCtx) check_class(node int) {
	super_class := x.child(node, .super_class)
	if super_class < 0 {
		return
	}
	excess := if x.precedence(super_class) > snep_precedence_update {
		x.has_excess_parens(super_class)
	} else {
		x.has_double_excess_parens(super_class)
	}
	if excess {
		x.report(super_class)
	}
}

// check_expression_or_export_statement ports checkExpressionOrExportStatement.
fn (mut x SnepCtx) check_expression_or_export_statement(node int) {
	if node < 0 {
		return
	}
	t := x.t
	first := if x.is_parenthesised(node) {
		x.tokens.before(t.nodes[node].start, false) or { return }
	} else {
		un_first_token(t, x.tokens, node, 0) or { return }
	}
	second := x.token_after_not(first, '(')
	mut third := ?SourceToken(none)
	mut after_closing := ?SourceToken(none)
	if s := second {
		third = x.tokens.after(s.end, false)
		after_closing = x.token_after_not(s, ')')
	}
	if x.c.token_is(first, '(') {
		if s := second {
			value := x.c.token_text(s)
			mut ignore := x.c.token_is(s, '{')
			if !ignore && s.kind == .keyword {
				if value in ['function', 'class'] {
					ignore = true
				} else if value == 'let' {
					if a := after_closing {
						ignore = x.c.token_is(a, '[') || a.kind == .identifier
					}
				}
			}
			if !ignore && s.kind == .identifier && value == 'async' {
				if th := third {
					ignore = th.kind == .keyword && x.c.token_text(th) == 'function'
				}
			}
			// veslint keeps these parentheses on purpose (@stylistic 6.0.1 removes them): without
			// them, TypeScript parses `type satisfies never;` or `(namespace) as X;` as a declaration.
			if !ignore {
				if a := after_closing {
					ignore = x.starts_declaration(s, a)
				}
			}
			if ignore {
				x.tokens_to_ignore[s.start] = true
			}
		}
	}
	parent := t.nodes[node].parent
	excess := if parent >= 0 && t.typ(parent) == .export_default_declaration {
		x.has_excess_parens_with_precedence(node, snep_precedence_assignment)
	} else {
		x.has_excess_parens(node)
	}
	if excess {
		x.report(node)
	}
}

// snep_reserved_words are the words TypeScript's parser never takes as an identifier.
const snep_reserved_words = ['break', 'case', 'catch', 'class', 'const', 'continue', 'debugger',
	'default', 'delete', 'do', 'else', 'enum', 'export', 'extends', 'false', 'finally', 'for',
	'function', 'if', 'import', 'in', 'instanceof', 'new', 'null', 'return', 'super', 'switch',
	'this', 'throw', 'true', 'try', 'typeof', 'var', 'void', 'while', 'with']

// starts_declaration tells whether a statement that starts with the identifier `word` followed by
// `next` is a declaration for TypeScript's parser (isDeclaration and isUsingDeclaration of
// parser.ts): `type x`, `interface x`, `namespace x`, `module x` or `module 'x'` and `using x` on one
// line, and `global {`, `global x` or `global export`.
fn (x &SnepCtx) starts_declaration(word SourceToken, next SourceToken) bool {
	if word.kind != .identifier && word.kind != .keyword {
		return false
	}
	text := x.c.token_text(next)
	identifier := next.kind == .identifier
		|| (next.kind == .keyword && text !in snep_reserved_words)
	between := x.c.src[word.end..next.start]
	same_line := !between.contains('\n') && !between.contains('\r') && !between.contains(' ')
		&& !between.contains(' ')
	return match x.c.token_text(word) {
		'type', 'interface' { same_line && identifier }
		'namespace', 'module' { same_line && (identifier || next.kind == .string_) }
		'using' { same_line && (identifier || x.c.token_is(next, '{')) }
		'global' { identifier || text == 'export' || x.c.token_is(next, '{') }
		else { false }
	}
}

// check_class_property ports checkClassProperty.
fn (mut x SnepCtx) check_class_property(node int) {
	key := x.child(node, .key)
	if x.flag(node, .computed) && key >= 0
		&& x.has_excess_parens_with_precedence(key, snep_precedence_assignment) {
		x.report(key)
	}
	value := x.child(node, .value)
	if value >= 0 && x.has_excess_parens_with_precedence(value, snep_precedence_assignment) {
		x.report(value)
	}
}

// check_spread ports checkSpread.
fn (mut x SnepCtx) check_spread(node int) {
	o := x.options
	argument := x.child(node, .argument)
	if argument < 0 || x.is_type_assertion(argument) {
		return
	}
	if o.has_allow_nodes_in_spread && x.t.typ(argument).type_name() in o.allow_nodes_in_spread {
		return
	}
	x.report_if_excess_with_precedence(argument, snep_precedence_assignment)
}

// check_ts_binary_type ports checkTSBinaryType.
fn (mut x SnepCtx) check_ts_binary_type(node int) {
	prec := x.precedence(node)
	for typ in x.children(node, .types) {
		excess := if x.options.ignore_nested_binary
			&& x.t.typ(typ) in [.ts_union_type, .ts_intersection_type] {
			x.is_parenthesised_twice(typ)
		} else {
			x.has_excess_parens_with_precedence(typ, prec)
		}
		if excess {
			x.report(typ)
		}
	}
}

// report_if is `if (hasExcessParens(node)) report(node)` for a child that may be missing.
fn (mut x SnepCtx) report_if_excess(node int) {
	if node >= 0 && x.has_excess_parens(node) {
		x.report(node)
	}
}

fn (mut x SnepCtx) report_if_excess_with_precedence(node int, lower_limit int) {
	if node >= 0 && x.has_excess_parens_with_precedence(node, lower_limit) {
		x.report(node)
	}
}

// listen runs the listener of the node's type; false when it has none.
fn (mut x SnepCtx) listen(node int) bool {
	t := x.t
	o := x.options
	match t.typ(node) {
		.array_expression {
			for element in x.children(node, .elements) {
				x.report_if_excess_with_precedence(element, snep_precedence_assignment)
			}
		}
		.array_pattern {
			for element in x.children(node, .elements) {
				if element >= 0 && x.can_be_assignment_target(element) {
					x.report_if_excess(element)
				}
			}
		}
		.arrow_function_expression {
			body := x.child(node, .body)
			if body < 0 {
				return true
			}
			if first := x.first_token_not_paren(body) {
				if before := x.tokens.before(first.start, false) {
					if x.c.token_is(before, '(') && x.c.token_is(first, '{') {
						x.tokens_to_ignore[first.start] = true
					}
				}
			}
			if x.is_type_assertion(body) || x.is_return_assign_exception(node) {
				return true
			}
			if t.typ(body) == .conditional_expression && o.ignore_arrow_conditionals {
				return true
			}
			if t.typ(body) == .block_statement {
				return true
			}
			x.report_if_excess_with_precedence(body, snep_precedence_assignment)
		}
		.assignment_expression {
			left := x.child(node, .left)
			right := x.child(node, .right)
			if x.can_be_assignment_target(left) && x.has_excess_parens(left)
				&& (!x.is_anonymous_function_assignment_exception(node, left, right)
					|| x.is_parenthesised_twice(left)) {
				x.report(left)
			}
			if !x.is_return_assign_exception(node) {
				x.report_if_excess_with_precedence(right, x.precedence(node))
			}
		}
		.assignment_pattern {
			left := x.child(node, .left)
			if x.can_be_assignment_target(left) {
				x.report_if_excess(left)
			}
			x.report_if_excess_with_precedence(x.child(node, .right), snep_precedence_assignment)
		}
		.await_expression, .unary_expression {
			x.check_argument_with_precedence(node)
		}
		.binary_expression {
			if x.buffers.len > 0 && x.operator(node) == 'in' {
				x.buffers[x.buffers.len - 1].in_expression_nodes << node
			}
			x.check_binary_logical(node)
		}
		.call_expression, .new_expression {
			x.check_call_new(node)
		}
		.class_declaration, .class_expression {
			x.check_class(node)
		}
		.conditional_expression {
			x.check_conditional(node)
		}
		.do_while_statement, .if_statement, .while_statement {
			if !x.is_cond_assign_exception(x.test_type(node)) {
				x.report_if_excess(x.child(node, .test))
			}
		}
		.export_default_declaration {
			x.check_expression_or_export_statement(x.child(node, .declaration))
		}
		.expression_statement {
			// A template expression of a .svelte file is in no statement for ESLint.
			if !x.c.svelte_wrapper_es_statement(t, node) {
				x.check_expression_or_export_statement(x.child(node, .expression))
			}
		}
		.for_in_statement {
			left := x.child(node, .left)
			right := x.child(node, .right)
			if x.is_type_assertion(right) {
				return true
			}
			if left >= 0 && t.typ(left) != .variable_declaration {
				x.ignore_let(left, true)
			}
			x.report_if_excess(left)
			x.report_if_excess(right)
		}
		.for_of_statement {
			left := x.child(node, .left)
			right := x.child(node, .right)
			if left >= 0 && t.typ(left) != .variable_declaration {
				x.ignore_let(left, false)
			}
			x.report_if_excess(left)
			if !x.is_type_assertion(right) {
				x.report_if_excess_with_precedence(right, snep_precedence_assignment)
			}
		}
		.for_statement {
			test := x.child(node, .test)
			if test >= 0 && x.has_excess_parens(test)
				&& !x.is_cond_assign_exception(x.test_type(node)) && !x.is_type_assertion(test) {
				x.report(test)
			}
			update := x.child(node, .update)
			if update >= 0 && x.has_excess_parens(update) && !x.is_type_assertion(update) {
				x.report(update)
			}
			init := x.child(node, .init)
			if init >= 0 && !x.is_type_assertion(init) {
				if t.typ(init) != .variable_declaration {
					x.ignore_let(init, true)
				}
				x.buffers << SnepBuffer{}
				x.report_if_excess(init)
			}
		}
		.import_expression {
			source := x.child(node, .source)
			if source >= 0 {
				if t.typ(source) == .sequence_expression {
					if x.has_double_excess_parens(source) {
						x.report(source)
					}
				} else {
					x.report_if_excess(source)
				}
			}
		}
		.jsx_spread_attribute, .spread_element {
			x.check_spread(node)
		}
		.logical_expression {
			x.check_binary_logical(node)
		}
		.member_expression {
			x.check_member(node)
		}
		.method_definition {
			if x.flag(node, .computed) {
				x.report_if_excess_with_precedence(x.child(node, .key), snep_precedence_assignment)
			}
		}
		.object_expression {
			for property in x.children(node, .properties) {
				if t.typ(property) == .property {
					x.report_if_excess_with_precedence(x.child(property, .value), snep_precedence_assignment)
				}
			}
		}
		.object_pattern {
			for property in x.children(node, .properties) {
				value := x.child(property, .value)
				if value >= 0 && x.can_be_assignment_target(value) {
					x.report_if_excess(value)
				}
			}
		}
		.property {
			if x.flag(node, .computed) {
				x.report_if_excess_with_precedence(x.child(node, .key), snep_precedence_assignment)
			}
		}
		.property_definition, .accessor_property {
			x.check_class_property(node)
		}
		.rest_element {
			argument := x.child(node, .argument)
			if x.can_be_assignment_target(argument) {
				x.report_if_excess(argument)
			}
		}
		.return_statement {
			return_token := un_first_token(t, x.tokens, node, 0) or { return true }
			if x.is_return_assign_exception(node) {
				return true
			}
			argument := x.child(node, .argument)
			if argument >= 0 && x.has_excess_parens_no_line_terminator(return_token, argument)
				&& !x.is_regexp_literal(argument) {
				x.report(argument)
			}
		}
		.sequence_expression {
			prec := x.precedence(node)
			for expression in x.children(node, .expressions) {
				x.report_if_excess_with_precedence(expression, prec)
			}
		}
		.switch_case {
			test := x.child(node, .test)
			if test >= 0 && !x.is_type_assertion(test) {
				x.report_if_excess(test)
			}
		}
		.switch_statement {
			x.report_if_excess(x.child(node, .discriminant))
		}
		.template_literal {
			for expression in x.children(node, .expressions) {
				x.report_if_excess(expression)
			}
		}
		.throw_statement {
			argument := x.child(node, .argument)
			if argument < 0 || x.is_type_assertion(argument) {
				return true
			}
			throw_token := un_first_token(t, x.tokens, node, 0) or { return true }
			if x.has_excess_parens_no_line_terminator(throw_token, argument) {
				x.report(argument)
			}
		}
		.update_expression {
			argument := x.child(node, .argument)
			if argument < 0 {
				return true
			}
			if x.flag(node, .prefix) {
				x.check_argument_with_precedence(node)
			} else {
				last := un_last_token(t, x.tokens, node) or { return true }
				if sty_same_line_offsets(t, t.nodes[argument].end, last.start) {
					x.check_argument_with_precedence(node)
				} else if x.has_double_excess_parens(argument) {
					x.report(argument)
				}
			}
		}
		.variable_declarator {
			init := x.child(node, .init)
			if init >= 0 && x.has_excess_parens_with_precedence(init, snep_precedence_assignment)
				&& !x.is_regexp_literal(init) {
				x.report(init)
			}
		}
		.with_statement {
			x.report_if_excess(x.child(node, .object))
		}
		.yield_expression {
			argument := x.child(node, .argument)
			if argument < 0 || x.is_type_assertion(argument) {
				return true
			}
			mut matched := false
			if x.precedence(argument) >= x.precedence(node) {
				if yield_token := un_first_token(t, x.tokens, node, 0) {
					matched = x.has_excess_parens_no_line_terminator(yield_token, argument)
				}
			}
			if matched || x.has_double_excess_parens(argument) {
				x.report(argument)
			}
		}
		.ts_array_type {
			x.report_if_excess_with_precedence(x.child(node, .element_type), x.precedence(node))
		}
		.ts_indexed_access_type {
			x.report_if_excess_with_precedence(x.child(node, .object_type), x.precedence(node))
			x.report_if_excess(x.child(node, .index_type))
		}
		.ts_conditional_type {
			// The check type and extends type are not checked, as a nested conditional type needs
			// its parens there.
			x.report_if_excess(x.child(node, .true_type))
			x.report_if_excess(x.child(node, .false_type))
		}
		.ts_type_parameter {
			x.report_if_excess(x.child(node, .constraint))
			x.report_if_excess(x.child(node, .default_))
		}
		.ts_type_parameter_instantiation {
			for param in x.children(node, .params) {
				x.report_if_excess(param)
			}
		}
		.ts_intersection_type, .ts_union_type {
			x.check_ts_binary_type(node)
		}
		.ts_type_annotation, .ts_type_alias_declaration {
			x.report_if_excess(x.child(node, .type_annotation))
		}
		.ts_enum_member {
			x.report_if_excess(x.child(node, .initializer))
		}
		else {
			return false
		}
	}
	return true
}

// is_anonymous_function_assignment_exception ports isAnonymousFunctionAssignmentException.
fn (x &SnepCtx) is_anonymous_function_assignment_exception(node int, left int, right int) bool {
	if left < 0 || right < 0 || x.t.typ(left) != .identifier
		|| x.operator(node) !in ['=', '&&=', '||=', '??='] {
		return false
	}
	typ := x.t.typ(right)
	if typ == .arrow_function_expression {
		return true
	}
	return typ in [.function_expression, .class_expression] && x.child(right, .id) < 0
}

// check_conditional_should_check ports shouldCheck of the ConditionalExpression listener.
fn (x &SnepCtx) check_conditional_should_check(expression int, precedence_limit int) bool {
	return if x.is_type_assertion(expression) {
		x.has_double_excess_parens(expression)
	} else {
		x.has_excess_parens_with_precedence(expression, precedence_limit)
	}
}

// check_conditional ports the ConditionalExpression listener.
fn (mut x SnepCtx) check_conditional(node int) {
	t := x.t
	test := x.child(node, .test)
	consequent := x.child(node, .consequent)
	alternate := x.child(node, .alternate)
	if test < 0 || consequent < 0 || alternate < 0 || x.is_return_assign_exception(node) {
		return
	}
	o := x.options
	binary := [estree.NodeType.binary_expression, .logical_expression]
	if !(o.except_cond_ternary && t.typ(test) in binary)
		&& !(o.allow_nested_ternary && t.typ(test) == .conditional_expression)
		&& !x.is_cond_assign_exception(t.typ(test))
		&& x.check_conditional_should_check(test, snep_precedence_or) {
		x.report(test)
	}
	if !(o.except_cond_ternary && t.typ(consequent) in binary)
		&& !(o.allow_nested_ternary && t.typ(consequent) == .conditional_expression)
		&& x.check_conditional_should_check(consequent, snep_precedence_assignment) {
		x.report(consequent)
	}
	if !(o.except_cond_ternary && t.typ(alternate) in binary)
		&& !(o.allow_nested_ternary && t.typ(alternate) == .conditional_expression)
		&& x.check_conditional_should_check(alternate, snep_precedence_assignment) {
		x.report(alternate)
	}
}

// check_member ports the MemberExpression listener.
fn (mut x SnepCtx) check_member(node int) {
	t := x.t
	object := x.child(node, .object)
	property := x.child(node, .property)
	if object < 0 || property < 0 {
		return
	}
	o := x.options
	computed := x.flag(node, .computed)
	parent := t.nodes[node].parent
	is_object_type_assertion := x.is_type_assertion(object)
	should_allow_wrap_once := is_object_type_assertion
		|| (x.is_member_exp_in_new_callee(node)
			&& x.does_member_expression_contain_call_expression(node))
	has_excess := if should_allow_wrap_once {
		x.has_double_excess_parens(object)
	} else {
		x.has_excess_parens(object) && !(parent >= 0
			&& x.is_immediate_function_prototype_method_call(parent)
			&& x.child(parent, .callee) == node && o.ignore_function_prototype)
	}
	object_typ := t.typ(object)
	if has_excess && x.precedence(object) >= x.precedence(node)
		&& (computed || !(x.is_decimal_integer(object) || x.is_regexp_literal(object))) {
		x.report(object)
	}
	if has_excess && (is_object_type_assertion || object_typ == .call_expression) {
		x.report(object)
	}
	if has_excess && !o.ignore_new_in_member_expr && object_typ == .new_expression
		&& x.is_new_expression_with_parens(object) {
		x.report(object)
	}
	if has_excess && x.flag(node, .optional) && object_typ == .chain_expression {
		x.report(object)
	}
	if computed && x.has_excess_parens(property) {
		x.report(property)
	}
}
