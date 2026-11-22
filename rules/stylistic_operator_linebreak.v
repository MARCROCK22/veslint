module rules

import estree
import json2

// Port of the `operator-linebreak` rule of @stylistic/eslint-plugin 6.0.1 (`"after"`, `"before"`,
// `"none"` or null, and `overrides` per operator, `"ignore"` among them), with its fixes, for
// vue/operator-linebreak (vue_wrap.v), which has it as its base and not as a rule of its own. With
// `c.vue_wrap_core` it gives what ESLint core's operator-linebreak gives: the node types of
// JavaScript only, and its fix, which does not move the operator across a block comment.

const solb_messages = {
	'operatorAtBeginning': "'{{operator}}' should be placed at the beginning of the line."
	'operatorAtEnd':       "'{{operator}}' should be placed at the end of the line."
	'badLinebreak':        "Bad line breaking before and after '{{operator}}'."
	'noLinebreak':         "There should be no line break before or after '{{operator}}'."
}

struct SolbOptions {
	global    string
	overrides map[string]string
}

fn solb_options(given []json2.Any) SolbOptions {
	first := if given.len > 0 { given[0] } else { json2.Any(json2.Null{}) }
	used_default := !(first is string && first != '')
	mut overrides := map[string]string{}
	if given.len > 1 {
		second := given[1]
		if second is map[string]json2.Any {
			if o := second['overrides'] {
				if o is map[string]json2.Any {
					for key, value in o {
						if value is string {
							overrides[key] = value
						}
					}
				}
			}
		}
	}
	if used_default {
		if (overrides['?'] or { '' }) == '' {
			overrides['?'] = 'before'
		}
		if (overrides[':'] or { '' }) == '' {
			overrides[':'] = 'before'
		}
	}
	return SolbOptions{
		global:    if used_default { 'after' } else { first as string }
		overrides: overrides
	}
}

// solb_strip_linebreaks is `text.replace(createGlobalLinebreakMatcher(), '')`.
fn solb_strip_linebreaks(text string) string {
	return text.replace('\r\n', '').replace('\r', '').replace('\n', '').replace(' ',
		'').replace(' ', '')
}

struct SolbCtx {
	t       &estree.EsTree
	tokens  &SourceTokens
	options SolbOptions
	core    bool
}

// solb_fix ports getFixer: none when the fixer returns null.
fn (c &Checker) solb_fix(x SolbCtx, operator SourceToken, desired string) ?Fix {
	before := x.tokens.before(operator.start, false)?
	after := x.tokens.after(operator.end, false)?
	before_any := x.tokens.before(operator.start, true)?
	after_any := x.tokens.after(operator.end, true)?
	has_comment_before := before_any.start != before.start
	has_comment_after := after_any.start != after.start
	mut swap_before := before
	mut swap_after := after
	if !x.core {
		if desired == 'after' && has_comment_before && before_any.kind == .block_comment {
			swap_before = before_any
		}
		if desired == 'before' && has_comment_after && after_any.kind == .block_comment {
			swap_after = after_any
		}
	}
	text_before := c.src[swap_before.end..operator.start]
	text_after := c.src[operator.end..swap_after.start]
	break_before := !sty_same_line(x.t, before, operator)
	break_after := !sty_same_line(x.t, operator, after)
	mut new_before := ''
	mut new_after := ''
	if break_before != break_after && desired != 'none' {
		if has_comment_before && has_comment_after {
			return none
		}
		new_before = text_after
		new_after = text_before
	} else {
		new_before = if desired == 'before' || text_before.trim_space() != '' {
			text_before
		} else {
			solb_strip_linebreaks(text_before)
		}
		new_after = if desired == 'after' || text_after.trim_space() != '' {
			text_after
		} else {
			solb_strip_linebreaks(text_after)
		}
		if new_before == text_before && new_after == text_after {
			return none
		}
	}
	op := c.token_text(operator)
	if new_after == '' && after.kind == .punctuator && op in ['+', '-'] && c.token_text(after) == op {
		new_after += ' '
	}
	return fix_replace_range(swap_before.end, swap_after.start, new_before + op + new_after)
}

// solb_validate ports validateNode.
fn (c &Checker) solb_validate(x SolbCtx, node int, right_side int, operator string, mut findings []Finding) {
	t := x.t
	if right_side < 0 {
		return
	}
	// getTokenBefore(rightSide, token => token.value === operator)
	mut at := t.nodes[right_side].start
	mut op_token := SourceToken{}
	for {
		token := x.tokens.before(at, false) or { return }
		if c.token_text(token) == operator {
			op_token = token
			break
		}
		at = token.start
	}
	left := x.tokens.before(op_token.start, false) or { return }
	right := x.tokens.after(op_token.end, false) or { return }
	override := x.options.overrides[operator] or { '' }
	mut style := if override != '' { override } else { x.options.global }
	if !x.core && style != 'ignore' && t.typ(node) == .ts_type_alias_declaration
		&& c.token_text(right) in ['|', '&'] {
		style = 'after'
	}
	same_left := sty_same_line(t, left, op_token)
	same_right := sty_same_line(t, op_token, right)
	message_id := if same_left && same_right {
		''
	} else if override != 'ignore' && !same_left && !same_right {
		'badLinebreak'
	} else if style == 'before' && same_left {
		'operatorAtBeginning'
	} else if style == 'after' && same_right {
		'operatorAtEnd'
	} else if style == 'none' {
		'noLinebreak'
	} else {
		''
	}
	if message_id == '' {
		return
	}
	fix := c.solb_fix(x, op_token, style)
	findings << Finding{
		stmt:       c.position_range(op_token.start, op_token.end)
		message_id: message_id
		data:       {
			'operator': operator
		}
		has_fix:    fix != none
		fix:        fix or { Fix{} }
	}
}

fn (mut c Checker) lint_stylistic_operator_linebreak(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	mut findings := []Finding{}
	options := solb_options(c.rule_options(vue_wrap_operator_linebreak))
	t := c.es_tree(root, abs_path) or { return findings }
	x := SolbCtx{
		t:       t
		tokens:  c.un_tokens(t)
		options: options
		core:    c.vue_wrap_core
	}
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		typ := t.typ(node)
		if x.core && typ !in [.binary_expression, .logical_expression, .assignment_expression,
			.variable_declarator, .property_definition, .conditional_expression] {
			continue
		}
		match typ {
			.binary_expression, .logical_expression, .assignment_expression {
				stats.checked++
				c.solb_validate(x, node, t.node(node, .right) or { -1 }, t.string_of(node,
					.operator) or { '' }, mut findings)
			}
			.variable_declarator {
				c.solb_validate(x, node, t.node(node, .init) or { -1 }, '=', mut findings)
			}
			.property_definition, .accessor_property {
				c.solb_validate(x, node, t.node(node, .value) or { -1 }, '=', mut findings)
			}
			.conditional_expression {
				stats.checked++
				c.solb_validate(x, node, t.node(node, .consequent) or { -1 }, '?', mut findings)
				c.solb_validate(x, node, t.node(node, .alternate) or { -1 }, ':', mut findings)
			}
			.ts_import_equals_declaration {
				c.solb_validate(x, node, t.node(node, .module_reference) or { -1 }, '=', mut
					findings)
			}
			.ts_type_alias_declaration {
				c.solb_validate(x, node, t.node(node, .type_annotation) or { -1 }, '=', mut
					findings)
			}
			.ts_conditional_type {
				c.solb_validate(x, node, t.node(node, .true_type) or { -1 }, '?', mut findings)
				c.solb_validate(x, node, t.node(node, .false_type) or { -1 }, ':', mut findings)
			}
			.ts_intersection_type, .ts_union_type {
				types := t.list(node, .types) or { []int{} }
				operator := if typ == .ts_union_type { '|' } else { '&' }
				for i := 0; i + 1 < types.len; i++ {
					c.solb_validate(x, types[i], types[i + 1], operator, mut findings)
				}
			}
			.ts_type_parameter {
				c.solb_validate(x, node, t.node(node, .default_) or { -1 }, '=', mut findings)
			}
			.ts_enum_member {
				c.solb_validate(x, node, t.node(node, .initializer) or { -1 }, '=', mut findings)
			}
			else {}
		}
	}
	return findings
}
