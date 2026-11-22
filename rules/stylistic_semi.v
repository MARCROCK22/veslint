module rules

import estree
import time
import x.json2

// Port of the `@stylistic/semi` rule of @stylistic/eslint-plugin 6.0.1, with its options
// (`"always"`, the default, with `omitLastInOneLineBlock` and `omitLastInOneLineClassBody`, or
// `"never"`, with `beforeStatementContinuationChars`) and its fixes.

const ssemi_messages = {
	'missingSemi': 'Missing semicolon.'
	'extraSemi':   'Extra semicolon.'
}

struct SsemiOptions {
	never                               bool
	except_one_line                     bool
	except_one_line_class_body          bool
	before_statement_continuation_chars string
}

fn ssemi_options(given []json2.Any) !SsemiOptions {
	options := sty_options(given, decoded_default_options(stylistic_semi))
	object := sty_option_object(options, 1)
	continuation := sty_option_string([object['beforeStatementContinuationChars'] or {
		json2.Any(json2.Null{})
	}], 0, '')
	return SsemiOptions{
		never:                               sty_option_string(options, 0, 'always') == 'never'
		except_one_line:                     sty_option_bool(object, 'omitLastInOneLineBlock') or {
			false
		}
		except_one_line_class_body:          sty_option_bool(object, 'omitLastInOneLineClassBody') or {
			false
		}
		before_statement_continuation_chars: if continuation == '' { 'any' } else { continuation }
	}
}

struct SsemiContext {
	t       &estree.EsTree
	tokens  &SourceTokens
	options SsemiOptions
}

fn (mut c Checker) lint_stylistic_semi(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := ssemi_options(c.rule_options(stylistic_semi))!
	t := c.es_tree(root, abs_path) or { return findings }
	ctx := SsemiContext{
		t:       t
		tokens:  c.un_tokens(t)
		options: options
	}
	for step in t.steps() {
		node := step.node
		if step.leave {
			continue
		}
		match t.typ(node) {
			.variable_declaration {
				stats.checked++
				parent := t.nodes[node].parent
				if parent >= 0 {
					if t.typ(parent) == .for_statement && (t.node(parent, .init) or { -1 }) == node {
						continue
					}
					if t.typ(parent) in [.for_in_statement, .for_of_statement]
						&& (t.node(parent, .left) or { -1 }) == node {
						continue
					}
				}
				c.ssemi_check_for_semicolon(ctx, node, mut findings)
			}
			.expression_statement, .return_statement, .throw_statement, .do_while_statement,
			.debugger_statement, .break_statement, .continue_statement, .import_declaration,
			.export_all_declaration, .property_definition, .accessor_property,
			.ts_abstract_property_definition, .ts_declare_function, .ts_export_assignment,
			.ts_import_equals_declaration, .ts_type_alias_declaration,
			.ts_empty_body_function_expression {
				stats.checked++
				c.ssemi_check_for_semicolon(ctx, node, mut findings)
			}
			.export_named_declaration {
				stats.checked++
				if t.node(node, .declaration) == none {
					c.ssemi_check_for_semicolon(ctx, node, mut findings)
				}
			}
			.export_default_declaration {
				stats.checked++
				declaration := t.node(node, .declaration) or { continue }
				typ := t.typ(declaration)
				if typ == .ts_interface_declaration {
					continue
				}
				name := typ.type_name()
				if !name.contains('ClassDeclaration') && !name.contains('FunctionDeclaration') {
					c.ssemi_check_for_semicolon(ctx, node, mut findings)
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ssemi_last_token ports getLastToken(node, skip): the token `skip` tokens before the last one of
// the node.
fn ssemi_last_token(ctx SsemiContext, node int, skip int) ?SourceToken {
	inside := ctx.tokens.inside(ctx.t.nodes[node].start, ctx.t.nodes[node].end, false)
	if skip >= inside.len {
		return none
	}
	return inside[inside.len - 1 - skip]
}

// ssemi_report ports report: a missing semicolon after the last token of the node, or with
// `missing` (an extra one) the last token itself.
fn (c &Checker) ssemi_report(ctx SsemiContext, node int, missing bool) ?Finding {
	last_token := ssemi_last_token(ctx, node, 0)?
	if !missing {
		// From the end of the last token to getNextLocation: the next character of its line, the
		// start of the next line, or no end at the end of the file.
		line, _ := ctx.t.line_column(last_token.end)
		line_start := if ctx.t.line_starts.len >= line { ctx.t.line_starts[line - 1] } else { 0 }
		line_end, next_start := sntr_line_end(c.src, line_start)
		end := if last_token.end < line_end {
			last_token.end + utf8_char_len(c.src[last_token.end])
		} else if next_start >= 0 {
			next_start
		} else {
			-1
		}
		return Finding{
			stmt:       c.position_range(last_token.end, end)
			message_id: 'missingSemi'
			has_fix:    true
			fix:        fix_insert_at(last_token.end, ';')
		}
	}
	return Finding{
		stmt:       c.position_range(last_token.start, last_token.end)
		message_id: 'extraSemi'
		has_fix:    true
		fix:        c.sty_retain_surrounding_remove(ctx.tokens, last_token.start, last_token.end)
	}
}

// ssemi_is_redundant_semi ports isRedundantSemi: the next token is `;` or `}`, or there is none.
fn (c &Checker) ssemi_is_redundant_semi(ctx SsemiContext, semi SourceToken) bool {
	next := ctx.tokens.after(semi.end, false) or { return true }
	return c.token_is(next, '}') || c.token_is(next, ';')
}

// ssemi_is_end_of_arrow_block ports isEndOfArrowBlock.
fn (c &Checker) ssemi_is_end_of_arrow_block(ctx SsemiContext, last_token SourceToken) bool {
	if !c.token_is(last_token, '}') {
		return false
	}
	node := sty_node_by_range_index(ctx.t, last_token.start)
	if node < 0 || ctx.t.typ(node) != .block_statement {
		return false
	}
	parent := ctx.t.nodes[node].parent
	return parent >= 0 && ctx.t.typ(parent) == .arrow_function_expression
}

// ssemi_maybe_class_field_asi_hazard ports maybeClassFieldAsiHazard.
fn (c &Checker) ssemi_maybe_class_field_asi_hazard(ctx SsemiContext, node int) bool {
	t := ctx.t
	if t.typ(node) != .property_definition {
		return false
	}
	key := t.node(node, .key) or { -1 }
	computed := t.flag(node, .computed) or { false }
	needs_name_check := !computed && key >= 0 && t.typ(key) == .identifier
	if needs_name_check {
		name := t.string_of(key, .name) or { '' }
		if name in ['get', 'set', 'static'] {
			is_static_static := (t.flag(node, .static_) or { false }) && name == 'static'
			if !is_static_static && t.node(node, .value) == none {
				return true
			}
		}
	}
	following := ctx.tokens.after(t.nodes[node].end, false) or { return false }
	return c.sty_token_value(following) in ['*', 'in', 'instanceof']
}

// ssemi_is_on_same_line_with_next_token ports isOnSameLineWithNextToken.
fn ssemi_is_on_same_line_with_next_token(ctx SsemiContext, node int) bool {
	prev := ssemi_last_token(ctx, node, 1) or { return false }
	next := ctx.tokens.after(ctx.t.nodes[node].end, false) or { return false }
	return sty_same_line(ctx.t, prev, next)
}

// ssemi_maybe_asi_hazard_after ports maybeAsiHazardAfter.
fn (c &Checker) ssemi_maybe_asi_hazard_after(ctx SsemiContext, node int) bool {
	t := ctx.t
	match t.typ(node) {
		.do_while_statement, .break_statement, .continue_statement, .debugger_statement,
		.import_declaration, .export_all_declaration {
			return false
		}
		.return_statement {
			return t.node(node, .argument) != none
		}
		.export_named_declaration {
			return t.node(node, .declaration) != none
		}
		else {}
	}
	last_token := ssemi_last_token(ctx, node, 1) or { return true }
	return !c.ssemi_is_end_of_arrow_block(ctx, last_token)
}

// ssemi_maybe_asi_hazard_before ports maybeAsiHazardBefore: the token is one of `[`, `(`, `/`,
// `+`, `-` and a template (OPT_OUT_PATTERN), but `++` and `--`.
fn (c &Checker) ssemi_maybe_asi_hazard_before(token ?SourceToken) bool {
	tok := token or { return false }
	value := c.sty_token_value(tok)
	return value.len > 0 && value[0] in [`-`, `[`, `(`, `/`, `+`, `\``] && value != '++'
		&& value != '--'
}

// ssemi_can_remove_semicolon ports canRemoveSemicolon.
fn (c &Checker) ssemi_can_remove_semicolon(ctx SsemiContext, node int) bool {
	last_token := ssemi_last_token(ctx, node, 0) or { return false }
	if c.ssemi_is_redundant_semi(ctx, last_token) {
		return true
	}
	if c.ssemi_maybe_class_field_asi_hazard(ctx, node) {
		return false
	}
	if ssemi_is_on_same_line_with_next_token(ctx, node) {
		return false
	}
	// Continuation characters should not apply to class fields.
	if ctx.t.typ(node) != .property_definition
		&& ctx.options.before_statement_continuation_chars == 'never'
		&& !c.ssemi_maybe_asi_hazard_after(ctx, node) {
		return true
	}
	return !c.ssemi_maybe_asi_hazard_before(ctx.tokens.after(ctx.t.nodes[node].end, false))
}

// ssemi_is_single_line ports isSingleLine.
fn ssemi_is_single_line(t &estree.EsTree, node int) bool {
	return sty_same_line_offsets(t, t.nodes[node].start, t.nodes[node].end)
}

// ssemi_is_last_in_one_liner_block ports isLastInOneLinerBlock.
fn (c &Checker) ssemi_is_last_in_one_liner_block(ctx SsemiContext, node int) bool {
	t := ctx.t
	parent := t.nodes[node].parent
	next := ctx.tokens.after(t.nodes[node].end, false) or { return false }
	if c.sty_token_value(next) != '}' || parent < 0 {
		return false
	}
	if t.typ(parent) == .block_statement {
		return ssemi_is_single_line(t, parent)
	}
	if t.typ(parent) == .static_block {
		opening_brace := un_first_token(t, ctx.tokens, parent, 1) or { return false }
		return sty_same_line_offsets(t, t.nodes[parent].end, opening_brace.start)
	}
	return false
}

// ssemi_is_last_in_one_liner_class_body ports isLastInOneLinerClassBody.
fn (c &Checker) ssemi_is_last_in_one_liner_class_body(ctx SsemiContext, node int) bool {
	t := ctx.t
	parent := t.nodes[node].parent
	next := ctx.tokens.after(t.nodes[node].end, false) or { return false }
	if c.sty_token_value(next) != '}' || parent < 0 {
		return false
	}
	return t.typ(parent) == .class_body && ssemi_is_single_line(t, parent)
}

// ssemi_check_for_semicolon ports checkForSemicolon.
fn (c &Checker) ssemi_check_for_semicolon(ctx SsemiContext, node int, mut findings []Finding) {
	last_token := ssemi_last_token(ctx, node, 0) or { return }
	is_semi := c.token_is(last_token, ';')
	options := ctx.options
	if options.never {
		next := ctx.tokens.after(ctx.t.nodes[node].end, false)
		if is_semi && c.ssemi_can_remove_semicolon(ctx, node) {
			findings << c.ssemi_report(ctx, node, true) or { return }
		} else if !is_semi && options.before_statement_continuation_chars == 'always'
			&& ctx.t.typ(node) != .property_definition && c.ssemi_maybe_asi_hazard_before(next) {
			findings << c.ssemi_report(ctx, node, false) or { return }
		}
		return
	}
	one_liner_block := options.except_one_line && c.ssemi_is_last_in_one_liner_block(ctx, node)
	one_liner_class_body := options.except_one_line_class_body
		&& c.ssemi_is_last_in_one_liner_class_body(ctx, node)
	one_liner := one_liner_block || one_liner_class_body
	if is_semi && one_liner {
		findings << c.ssemi_report(ctx, node, true) or { return }
	} else if !is_semi && !one_liner {
		findings << c.ssemi_report(ctx, node, false) or { return }
	}
}
