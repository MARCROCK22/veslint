module rules

import json2
import svelte

// Port of the `svelte/mustache-spacing` rule of eslint-plugin-svelte 3.24.1: the spaces inside the
// braces of mustache tags (textExpressions, attributesAndProps, directiveExpressions: "never" by
// default, or "always") and of the tags of blocks and `{@…}` tags (tags.openingBrace,
// tags.closingBrace: "never" by default; the closing one also "always-after-expression"). Fixes.

const smsp_messages = {
	'expectedOpening':   "Expected 1 space after '{', but not found."
	'expectedClosing':   "Expected 1 space before '}', but not found."
	'unexpectedOpening': "Expected no space after '{', but found."
	'unexpectedClosing': "Expected no space before '}', but found."
}

struct SmspOptions {
	text_expressions      string = 'never'
	attributes_and_props  string = 'never'
	directive_expressions string = 'never'
	tags_opening          string = 'never'
	tags_closing          string = 'never'
}

fn smsp_options(options []json2.Any) !SmspOptions {
	o := option_object(svelte_mustache_spacing, options, ['textExpressions', 'attributesAndProps',
		'directiveExpressions', 'tags'])!
	values := ['never', 'always']
	text := o.string_value('textExpressions', values)!
	attributes := o.string_value('attributesAndProps', values)!
	directives := o.string_value('directiveExpressions', values)!
	mut opening := ''
	mut closing := ''
	if tags := o.values['tags'] {
		t := option_object(svelte_mustache_spacing, [tags], ['openingBrace', 'closingBrace'])!
		opening = t.string_value('openingBrace', values)!
		closing = t.string_value('closingBrace', ['never', 'always', 'always-after-expression'])!
	}
	or_never := fn (s string) string {
		return if s == '' { 'never' } else { s }
	}
	return SmspOptions{
		text_expressions:      or_never(text)
		attributes_and_props:  or_never(attributes)
		directive_expressions: or_never(directives)
		tags_opening:          or_never(opening)
		tags_closing:          or_never(closing)
	}
}

// smsp_verify is verifyBraces.
fn (c &Checker) smsp_verify(open svelte.Token, close ?svelte.Token, opening string, closing string, has_expression bool, mut findings []Finding) {
	if first := c.sv_token_after(open.end, true) {
		if opening == 'always' {
			if open.end == first.start {
				findings << Finding{
					...c.sv_report(sv_token_loc_start(open), sv_token_loc_end(open), 'expectedOpening',
						{})
					has_fix: true
					fix:     Fix{
						start: open.end
						end:   open.end
						text:  ' '
					}
				}
			}
		} else if open.end != first.start {
			findings << Finding{
				...c.sv_report(sv_token_loc_start(open), sv_token_loc_start(first), 'unexpectedOpening',
					{})
				has_fix: true
				fix:     Fix{
					start: open.end
					end:   first.start
				}
			}
		}
	}
	close_token := close or { return }
	last := c.sv_token_before(close_token.start, true) or { return }
	if closing == 'always' || (closing == 'always-after-expression' && has_expression) {
		if close_token.start == last.end {
			findings << Finding{
				...c.sv_report(sv_token_loc_start(close_token), sv_token_loc_end(close_token),
					'expectedClosing', {})
				has_fix: true
				fix:     Fix{
					start: close_token.start
					end:   close_token.start
					text:  ' '
				}
			}
		}
	} else if close_token.start != last.end {
		findings << Finding{
			...c.sv_report(sv_token_loc_end(last), sv_token_loc_end(close_token), 'unexpectedClosing',
				{})
			has_fix: true
			fix:     Fix{
				start: last.end
				end:   close_token.start
			}
		}
	}
}

// smsp_verify_expression is verifyExpression.
fn (c &Checker) smsp_verify_expression(i int, option string, mut findings []Finding) {
	open, close := c.sv_mustache_tokens(i) or { return }
	c.smsp_verify(open, close, option, option, false, mut findings)
}

// smsp_verify_close_block checks the `{/…}` that ends a block.
fn (c &Checker) smsp_verify_close_block(i int, options SmspOptions, mut findings []Finding) {
	n := c.svelte.doc.nodes[i]
	close := c.sv_last_token(n.start, n.end) or { return }
	open := c.sv_token_before_value(close.start, '{') or { return }
	c.smsp_verify(open, close, options.tags_opening, options.tags_closing, false, mut findings)
}

// smsp_verify_open_block checks the `{#…}` (or `{:…}`) that starts a block, whose `}` is the
// first after `after`.
fn (c &Checker) smsp_verify_open_block(i int, after int, has_expression bool, options SmspOptions, mut findings []Finding) {
	n := c.svelte.doc.nodes[i]
	open := c.sv_first_token(n.start, n.end) or { return }
	close := c.sv_token_after_value(after, '}')
	c.smsp_verify(open, close, options.tags_opening, options.tags_closing, has_expression, mut
		findings)
}

fn (mut c Checker) lint_svelte_mustache_spacing(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	options := smsp_options(c.rule_options(svelte_mustache_spacing))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes() {
		n := doc.nodes[i]
		match n.typ {
			.mustache_tag {
				if n.kind == 'raw' {
					open, close := c.sv_mustache_tokens(i) or { continue }
					c.smsp_verify(open, close, options.tags_opening, options.tags_closing,
						true, mut findings)
					continue
				}
				parent := if n.parent >= 0 { doc.nodes[n.parent].typ } else { svelte.SType.program }
				option := match parent {
					.attribute { options.attributes_and_props }
					.style_directive { options.directive_expressions }
					else { options.text_expressions }
				}
				c.smsp_verify_expression(i, option, mut findings)
			}
			.shorthand_attribute, .spread_attribute {
				c.smsp_verify_expression(i, options.attributes_and_props, mut findings)
			}
			.directive, .special_directive {
				c.smsp_verify_expression(i, options.directive_expressions, mut findings)
			}
			.debug_tag, .declaration_tag, .render_tag {
				open, close := c.sv_mustache_tokens(i) or { continue }
				c.smsp_verify(open, close, options.tags_opening, options.tags_closing, true, mut
					findings)
			}
			.if_block {
				_, ex_end := c.sv_ref_range(n.expression)
				c.smsp_verify_open_block(i, ex_end, true, options, mut findings)
				if !n.elseif {
					c.smsp_verify_close_block(i, options, mut findings)
				}
			}
			.else_block {
				if n.elseif {
					continue
				}
				open := c.sv_first_token(n.start, n.end) or { continue }
				close := c.sv_token_after_value(open.end, '}')
				c.smsp_verify(open, close, options.tags_opening, options.tags_closing, false, mut
					findings)
			}
			.each_block {
				last := if n.key_expr.idx >= 0 {
					n.key_expr
				} else if n.index_ref.idx >= 0 {
					n.index_ref
				} else if n.context.idx >= 0 {
					n.context
				} else {
					n.expression
				}
				_, last_end := c.sv_ref_range(last)
				c.smsp_verify_open_block(i, last_end, true, options, mut findings)
				c.smsp_verify_close_block(i, options, mut findings)
			}
			.key_block {
				_, ex_end := c.sv_ref_range(n.expression)
				c.smsp_verify_open_block(i, ex_end, true, options, mut findings)
				c.smsp_verify_close_block(i, options, mut findings)
			}
			.await_block {
				c.smsp_verify_close_block(i, options, mut findings)
			}
			.await_pending_block {
				_, ex_end := c.sv_ref_range(doc.nodes[n.parent].expression)
				c.smsp_verify_open_block(i, ex_end, true, options, mut findings)
			}
			.await_then_block, .await_catch_block {
				value := if n.typ == .await_then_block { n.value_es } else { n.error_es }
				flag := if n.typ == .await_then_block { n.await_then } else { n.await_catch }
				last := if value.idx >= 0 {
					value
				} else if flag {
					doc.nodes[n.parent].expression
				} else {
					svelte.Ref{}
				}
				open := c.sv_first_token(n.start, n.end) or { continue }
				if last.idx < 0 {
					c.smsp_verify(open, none, options.tags_opening, options.tags_closing,
						false, mut findings)
					continue
				}
				_, last_end := c.sv_ref_range(last)
				close := c.sv_token_after_value(last_end, '}')
				mut has_expression := false
				if close_token := close {
					if next := c.sv_token_after(last_end, false) {
						has_expression = next.start == close_token.start
					}
				}
				c.smsp_verify(open, close, options.tags_opening, options.tags_closing, has_expression, mut
					findings)
			}
			.snippet_block {
				last := if n.params.len > 0 { sv_es_ref(n.params.last()) } else { n.id }
				_, last_end := c.sv_ref_range(last)
				c.smsp_verify_open_block(i, last_end, true, options, mut findings)
				c.smsp_verify_close_block(i, options, mut findings)
			}
			else {}
		}
	}
	return findings
}
