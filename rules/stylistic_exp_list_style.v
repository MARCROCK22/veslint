module rules

import estree
import time
import x.json2

// Port of the `@stylistic/exp-list-style` rule of @stylistic/eslint-plugin 5.10.0 (experimental,
// rules/list-style), with its options (`singleLine` with `spacing` and `maxItems`, `multiLine` with
// `minItems`, and `overrides` by kind of bracket or by node type, or `"off"`) and its fixes: the
// spaces inside the brackets of a list on one line, and the line breaks between the items of a
// list on several lines. Lists: arrays, array patterns, tuple types, parameters, arguments, the
// test of an `if`, objects, object patterns, import and export specifiers, import attributes, type
// literals, interface bodies, enum bodies, type parameters and type arguments.

const sls_messages = {
	'shouldSpacing':    "Should have space between '{{prev}}' and '{{next}}'"
	'shouldNotSpacing': "Should not have space(s) between '{{prev}}' and '{{next}}'"
	'shouldWrap':       "Should have line break between '{{prev}}' and '{{next}}'"
	'shouldNotWrap':    "Should not have line break(s) between '{{prev}}' and '{{next}}'"
}

// SlsConfig is a resolved option (resolveOption): `max_items` is `max_i32` for
// `Number.POSITIVE_INFINITY`, `min_items` is `max_i32` when it is undefined (`len >= undefined` is
// false).
struct SlsConfig {
	off            bool
	spacing_always bool
	max_items      int
	min_items      int
}

// SlsOptions are the options of the rule as given (merged with the defaults).
struct SlsOptions {
	single_line map[string]json2.Any
	multi_line  map[string]json2.Any
	overrides   map[string]json2.Any
}

fn sls_options(given []json2.Any) !SlsOptions {
	options := sty_options(given, [
		json2.Any({
			'singleLine': json2.Any({
				'spacing':  json2.Any('never')
				'maxItems': json2.Any(json2.Null{})
			})
			'multiLine':  json2.Any({
				'minItems': json2.Any(0)
			})
			'overrides':  json2.Any({
				'{}': json2.Any({
					'singleLine': json2.Any({
						'spacing': json2.Any('always')
					})
				})
			})
		}),
	])
	object := sty_option_object(options, 0)
	return SlsOptions{
		single_line: sls_object(object['singleLine'] or { json2.Any(json2.Null{}) })
		multi_line:  sls_object(object['multiLine'] or { json2.Any(json2.Null{}) })
		overrides:   sls_object(object['overrides'] or { json2.Any(json2.Null{}) })
	}
}

// sls_object is the value when it is an object, else an empty object (what a spread of a value
// that is not an object gives).
fn sls_object(value json2.Any) map[string]json2.Any {
	if value is map[string]json2.Any {
		return value
	}
	return map[string]json2.Any{}
}

// sls_spread is `{ ...a, ...b, ...c }`.
fn sls_spread(objects ...map[string]json2.Any) map[string]json2.Any {
	mut out := map[string]json2.Any{}
	for object in objects {
		for key, value in object {
			out[key] = value
		}
	}
	return out
}

// sls_resolve ports resolveOption.
fn sls_resolve(options SlsOptions, paren_type string, node_type string) SlsConfig {
	by_paren := options.overrides[paren_type] or { json2.Any(json2.Null{}) }
	by_node_value := options.overrides[node_type] or { json2.Any(json2.Null{}) }
	by_node_undefined := node_type !in options.overrides
	if (by_node_value is string && by_node_value == 'off')
		|| (by_node_undefined && by_paren is string && by_paren == 'off') {
		return SlsConfig{
			off: true
		}
	}
	paren := sls_object(by_paren)
	by_node := sls_object(by_node_value)
	single_line := sls_spread(options.single_line, sls_object(paren['singleLine'] or {
		json2.Any(json2.Null{})
	}), sls_object(by_node['singleLine'] or { json2.Any(json2.Null{}) }))
	multiline := sls_spread(options.multi_line, sls_object(paren['multiline'] or {
		json2.Any(json2.Null{})
	}), sls_object(by_node['multiline'] or { json2.Any(json2.Null{}) }))
	mut max_items := max_i32
	if value := single_line['maxItems'] {
		if value !is json2.Null {
			max_items = value.int()
		}
	}
	mut min_items := max_i32
	if value := multiline['minItems'] {
		if value !is json2.Null {
			min_items = value.int()
		}
	}
	spacing := single_line['spacing'] or { json2.Any(json2.Null{}) }
	return SlsConfig{
		spacing_always: spacing is string && spacing == 'always'
		max_items:      max_items
		min_items:      min_items
	}
}

struct SlsCtx {
	t       &estree.EsTree
	tokens  &SourceTokens
	options SlsOptions
mut:
	resolved map[string]SlsConfig
}

fn (mut c Checker) lint_stylistic_exp_list_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := sls_options(c.rule_options(stylistic_exp_list_style))!
	t := c.es_tree(root, abs_path) or { return findings }
	mut ctx := SlsCtx{
		t:       t
		tokens:  c.un_tokens(t)
		options: options
	}
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.array_expression, .array_pattern {
				c.sls_check(mut ctx, '[]', node, t.list(node, .elements) or { []int{} }, mut
					findings)
			}
			.arrow_function_expression, .function_declaration, .function_expression,
			.ts_declare_function, .ts_function_type {
				c.sls_check(mut ctx, '()', node, t.list(node, .params) or { []int{} }, mut
					findings)
			}
			.call_expression, .new_expression {
				c.sls_check(mut ctx, '()', node, t.list(node, .arguments) or { []int{} }, mut
					findings)
			}
			.export_all_declaration {
				if attributes := t.list(node, .attributes) {
					c.sls_check(mut ctx, '{}', node, attributes, mut findings)
				}
			}
			.export_named_declaration {
				c.sls_check(mut ctx, '{}', node, t.list(node, .specifiers) or { []int{} }, mut
					findings)
				if attributes := t.list(node, .attributes) {
					c.sls_check(mut ctx, '{}', node, attributes, mut findings)
				}
			}
			.if_statement {
				test := t.node(node, .test) or { continue }
				c.sls_check(mut ctx, '()', node, [test], mut findings)
			}
			.import_declaration {
				specifiers := (t.list(node, .specifiers) or { []int{} }).filter(t.typ(it) == .import_specifier)
				c.sls_check(mut ctx, '{}', node, specifiers, mut findings)
				if attributes := t.list(node, .attributes) {
					c.sls_check(mut ctx, '{}', node, attributes, mut findings)
				}
			}
			.object_expression, .object_pattern {
				c.sls_check(mut ctx, '{}', node, t.list(node, .properties) or { []int{} }, mut
					findings)
			}
			.ts_enum_body, .ts_type_literal {
				c.sls_check(mut ctx, '{}', node, t.list(node, .members) or { []int{} }, mut
					findings)
			}
			.ts_interface_body {
				c.sls_check(mut ctx, '{}', node, t.list(node, .body) or { []int{} }, mut findings)
			}
			.ts_tuple_type {
				c.sls_check(mut ctx, '[]', node, t.list(node, .element_types) or { []int{} }, mut
					findings)
			}
			.ts_type_parameter_declaration, .ts_type_parameter_instantiation {
				c.sls_check(mut ctx, '<>', node, t.list(node, .params) or { []int{} }, mut
					findings)
			}
			else {
				continue
			}
		}
		stats.checked++
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// sls_paren_matches ports the matchers of parenMatchers.
fn (c &Checker) sls_paren_matches(token SourceToken, paren_type string, left bool) bool {
	return match paren_type {
		'[]' { c.token_is(token, if left { '[' } else { ']' }) }
		'{}' { c.token_is(token, if left { '{' } else { '}' }) }
		'()' { c.token_is(token, if left { '(' } else { ')' }) }
		else { c.token_text(token) == if left { '<' } else { '>' } }
	}
}

// sls_left_paren ports getLeftParen.
fn (c &Checker) sls_left_paren(ctx SlsCtx, node int, items []int, paren_type string) ?SourceToken {
	t := ctx.t
	match t.typ(node) {
		.call_expression, .new_expression {
			before := t.node(node, .type_arguments) or { t.node(node, .callee)? }
			return c.un_token_after_punctuator(ctx.tokens, t.nodes[before].end, '(')
		}
		.array_expression, .array_pattern {
			return un_first_token(t, ctx.tokens, node, 0)
		}
		else {
			if items[0] < 0 {
				return none
			}
			maybe_left := ctx.tokens.before(t.nodes[items[0]].start, false)?
			return if c.sls_paren_matches(maybe_left, paren_type, true) { maybe_left } else { none }
		}
	}
}

// sls_right_paren ports getRightParen.
fn (c &Checker) sls_right_paren(ctx SlsCtx, node int, items []int, paren_type string) ?SourceToken {
	t := ctx.t
	match t.typ(node) {
		.array_expression, .array_pattern {
			return un_last_token(t, ctx.tokens, node)
		}
		else {
			last := items.last()
			if last < 0 {
				return none
			}
			// getTokenAfter(items.at(-1), isNotCommaToken).
			for i := source_tokens_index(ctx.tokens.tokens, t.nodes[last].end); i < ctx.tokens.tokens.len; i++ {
				token := ctx.tokens.tokens[i]
				if c.token_is(token, ',') {
					continue
				}
				return if c.sls_paren_matches(token, paren_type, false) { token } else { none }
			}
			return none
		}
	}
}

// sls_check ports check.
fn (c &Checker) sls_check(mut ctx SlsCtx, paren_type string, node int, items []int, mut findings []Finding) {
	if items.len == 0 {
		return
	}
	t := ctx.t
	left := c.sls_left_paren(ctx, node, items, paren_type) or { return }
	right := c.sls_right_paren(ctx, node, items, paren_type) or { return }
	node_type := if items[0] >= 0 && t.typ(items[0]) == .import_attribute {
		'ImportAttributes'
	} else {
		t.typ(node).type_name()
	}
	config := ctx.resolved[node_type] or {
		resolved := sls_resolve(ctx.options, paren_type, node_type)
		ctx.resolved[node_type] = resolved
		resolved
	}
	if config.off {
		return
	}
	if sty_same_line(t, left, right) && items.len <= config.max_items {
		c.sls_check_spacing(ctx, left, right, config, mut findings)
	} else {
		c.sls_check_wrap(ctx, node, items, left, right, config, mut findings)
	}
}

// sls_value is the `value` of a token or of a comment.
fn (c &Checker) sls_value(token SourceToken) string {
	text := c.token_text(token)
	return if token.is_comment() { es_comment_value(text) } else { text }
}

fn (c &Checker) sls_report(prev SourceToken, next SourceToken, message_id string, has_fix bool, fix Fix) Finding {
	return Finding{
		stmt:       c.position_range(prev.end, next.start)
		message_id: message_id
		data:       {
			'prev': c.sls_value(prev)
			'next': c.sls_value(next)
		}
		has_fix:    has_fix
		fix:        if has_fix { fix } else { Fix{} }
	}
}

// sls_check_spacing ports checkSpacing.
fn (c &Checker) sls_check_spacing(ctx SlsCtx, left SourceToken, right SourceToken, config SlsConfig, mut findings []Finding) {
	first := ctx.tokens.after(left.end, true) or { return }
	last := ctx.tokens.before(right.start, true) or { return }
	for pair in [[left, first], [last, right]] {
		prev, next := pair[0], pair[1]
		spaced := ctx.tokens.is_space_between(prev.end, next.start)
		if !spaced && config.spacing_always {
			findings << c.sls_report(prev, next, 'shouldSpacing', true, fix_insert_at(prev.end,
				' '))
		} else if spaced && !config.spacing_always {
			findings << c.sls_report(prev, next, 'shouldNotSpacing', true, fix_remove_range(prev.end,
				next.start))
		}
	}
}

// sls_check_wrap ports checkWrap.
fn (c &Checker) sls_check_wrap(ctx SlsCtx, node int, items []int, left SourceToken, right SourceToken, config SlsConfig, mut findings []Finding) {
	t := ctx.t
	len := items.len
	need_wrap := if sty_same_line_offsets(t, t.nodes[node].start, t.nodes[node].end) {
		len > config.max_items
	} else {
		mut first_start := 0
		if items[0] >= 0 {
			first_start = t.nodes[items[0]].start
		} else {
			first_start = (ctx.tokens.after(left.end, false) or { return }).start
		}
		len >= config.min_items && !sty_same_line_offsets(t, left.end, first_start)
	}
	is_member_list := t.typ(node) in [.ts_interface_body, .ts_type_literal]
	do_check := fn [c, ctx, t, need_wrap, items, is_member_list] (prev SourceToken, next SourceToken, mut findings []Finding) {
		if sty_same_line(t, prev, next) {
			if !need_wrap {
				return
			}
			has_fix := !ctx.tokens.comments_exist_between(prev.end, next.start)
			findings << c.sls_report(prev, next, 'shouldWrap', has_fix, fix_insert_at(next.start,
				'\n'))
		} else {
			if need_wrap {
				return
			}
			// safeReplaceTextBetween with getDelimiter.
			has_fix := !ctx.tokens.comments_exist_between(prev.end, next.start)
			mut replacement := ''
			if items.len != 1 && is_member_list {
				value := c.token_text(prev)
				if !(value.ends_with(',') || value.ends_with(';')) {
					replacement = ','
				}
			}
			findings << c.sls_report(prev, next, 'shouldNotWrap', has_fix, fix_replace_range(prev.end,
				next.start, replacement))
		}
	}
	token_after_left := ctx.tokens.after(left.end, false) or { return }
	do_check(left, token_after_left, mut findings)
	for i, item in items {
		if item < 0 {
			continue
		}
		current_first := un_first_token(t, ctx.tokens, item, 0) or { continue }
		if i == 0 && token_after_left.start == current_first.start {
			continue
		}
		// getTokenBefore(currentItem, { filter: isNotOpeningParenToken || token === left }).
		mut index := source_tokens_index(ctx.tokens.tokens, t.nodes[item].start) - 1
		for index >= 0 {
			token := ctx.tokens.tokens[index]
			if !c.token_is(token, '(') || token.start == left.start {
				break
			}
			index--
		}
		if index < 0 {
			continue
		}
		do_check(ctx.tokens.tokens[index], current_first, mut findings)
	}
	before_right := ctx.tokens.before(right.start, false) or { return }
	do_check(before_right, right, mut findings)
}
