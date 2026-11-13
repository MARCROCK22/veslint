module rules

import json2
import jsregexp
import time
import tsgo { TypeResponse }
import treesitter { Ident, children, named_children, node_end, node_field, node_kind, node_start, nodes_of_kind, position_of }

// Port of the `switch-exhaustiveness-check` rule of typescript-eslint 8.62.0, with all its options
// and its `addMissingCases` suggestion.

const sec_messages = {
	'addMissingCases':       'Add branches for missing cases.'
	'dangerousDefaultCase':  'The switch statement is exhaustive, so the default case is unnecessary.'
	'switchIsNotExhaustive': 'Switch is not exhaustive. Cases not matched: {{missingBranches}}'
}

// TypeFormatFlags AllowUniqueESSymbolType | UseAliasDefinedOutsideCurrentScope |
// UseFullyQualifiedType, with which the rule names the missing cases.
const sec_type_format_flags = 1065024

// TypeFlags of isTypeLiteralLikeType: Literal | Undefined | Null | UniqueESSymbol.
const sec_literal_like_flags = u32(15360 | 4 | 8 | 16384)

struct SecOptions {
	allow_default_case_for_exhaustive_switch bool
	consider_default_exhaustive_for_unions   bool
	require_default_for_non_union            bool
	has_comment_pattern                      bool
	comment_pattern                          jsregexp.RegexpProgram // defaultCaseCommentPattern
}

fn sec_options(options []json2.Any) !SecOptions {
	o := option_object(switch_exhaustiveness_check, options, [
		'allowDefaultCaseForExhaustiveSwitch',
		'considerDefaultExhaustiveForUnions',
		'defaultCaseCommentPattern',
		'requireDefaultForNonUnion',
	])!
	// `new RegExp(defaultCaseCommentPattern, 'u')`; without the option, /^no default$/iu.
	mut has_comment_pattern := false
	mut comment_pattern := jsregexp.RegexpProgram{}
	if pattern := o.values['defaultCaseCommentPattern'] {
		if pattern !is string {
			return error('option `defaultCaseCommentPattern` of `${switch_exhaustiveness_check}` must be a string')
		}
		comment_pattern = jsregexp.regexp_compile(pattern as string) or {
			return error('option `defaultCaseCommentPattern` of `${switch_exhaustiveness_check}`: ${err.msg()}')
		}
		has_comment_pattern = true
	}
	return SecOptions{
		allow_default_case_for_exhaustive_switch: o.bool_value('allowDefaultCaseForExhaustiveSwitch')!
		consider_default_exhaustive_for_unions:   o.bool_value('considerDefaultExhaustiveForUnions')!
		require_default_for_non_union:            o.bool_value('requireDefaultForNonUnion')!
		has_comment_pattern:                      has_comment_pattern
		comment_pattern:                          comment_pattern
	}
}

// SwitchStatement is a switch with its discriminant and the tests of its `case`s without parentheses.
struct SwitchStatement {
	node         C.TSNode
	discriminant C.TSNode
	cases        []C.TSNode // its `case`s and `default`s
	tests        []C.TSNode
	default_case ?Ident // the `default`, or the `no default` comment after the last case
}

fn (mut c Checker) lint_switch_exhaustiveness_check(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	options := sec_options(c.rule_options(switch_exhaustiveness_check))!
	mut switches := []SwitchStatement{}
	mut spans := []Span{}
	for node in c.nodes_of_kind(root, c'switch_statement') {
		discriminant := unwrap_parens(node_field(node, 'value') or { continue })
		body := node_field(node, 'body') or { continue }
		cases := named_children(body).filter(node_kind(it) in ['switch_case', 'switch_default'])
		mut tests := []C.TSNode{}
		mut default_case := ?Ident(none)
		for case in cases {
			if node_kind(case) == 'switch_default' {
				if default_case == none {
					default_case = position_of(case)
				}
				continue
			}
			tests << unwrap_parens(node_field(case, 'value') or { continue })
		}
		if default_case == none && cases.len > 0 {
			if comment := c.default_comment(body, cases.last()) {
				text := c.text(comment)
				value := js_trim(if text.starts_with('//') {
					text[2..]
				} else {
					text[2..text.len - 2]
				})
				is_default := if options.has_comment_pattern {
					jsregexp.regexp_test(options.comment_pattern, value) or {
						return error('option `defaultCaseCommentPattern` of `${switch_exhaustiveness_check}`: ${err.msg()}')
					}
				} else {
					value.to_lower() == 'no default'
				}
				if is_default {
					default_case = position_of(comment)
				}
			}
		}
		spans << node_span(discriminant)
		spans << tests.map(node_span(it))
		switches << SwitchStatement{
			node:         node
			discriminant: discriminant
			cases:        cases
			tests:        tests
			default_case: default_case
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for s in switches {
		c.check_switch(s, options, mut findings)!
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += switches.len
	return findings
}

// default_comment ports getCommentDefaultCase: the last comment after the last case. The caller
// tests its trimmed text with the pattern (`no default`, case-insensitive, by default).
fn (c &Checker) default_comment(body C.TSNode, last_case C.TSNode) ?C.TSNode {
	// The end of the case in ESTree: its last token, without comments tree-sitter may attach.
	mut end := node_end(last_case)
	for child in children(last_case).reverse() {
		if node_kind(child) != 'comment' {
			end = node_end(child)
			break
		}
	}
	mut last := ?C.TSNode(none)
	for comment in nodes_of_kind(body, c'comment') {
		if node_start(comment) >= end {
			last = comment
		}
	}
	return last
}

fn (mut c Checker) check_switch(s SwitchStatement, o SecOptions, mut findings []Finding) ! {
	discriminant := c.node_type(s.discriminant) or { return }
	mut case_types := map[int]bool{}
	mut undefined_case := false
	for test in s.tests {
		// Without the type of some case it is unknown what is missing.
		t := c.node_type(test) or { return }
		constrained := c.constrained(t)!
		case_types[constrained.id] = true
		// tsutils.isIntrinsicUndefinedType: the type's own flags, so not `string | undefined`.
		if constrained.flags & type_flag_undefined != 0 {
			undefined_case = true
		}
	}
	switch_type := c.constrained(discriminant)!
	mut missing := []TypeResponse{}
	mut contains_non_literal := false
	for union_part in c.constituents(switch_type)! {
		parts := c.intersection_parts(union_part)!
		if parts.all(it.flags & sec_literal_like_flags == 0) {
			contains_non_literal = true
		}
		for part in parts {
			if part.id in case_types || part.flags & sec_literal_like_flags == 0 {
				continue
			}
			// "missing", "optional" and "undefined" are different types, all with TypeFlags.Undefined.
			if undefined_case && part.flags & type_flag_undefined != 0 {
				continue
			}
			missing << part
		}
	}
	has_default := s.default_case != none
	if !(o.consider_default_exhaustive_for_unions && has_default) && missing.len > 0 {
		mut branches := []string{}
		mut missing_cases := []string{}
		// `discriminantType.getSymbol()?.escapedName`: the name of an enum, for instance. Like
		// TypeScript 6's escapedName, the name tsgo gives has a third underscore if it starts with two.
		switch_symbol := c.symbol_of(switch_type)!
		symbol_name := if switch_symbol.is_null() { '' } else { switch_symbol.name }
		for t in missing {
			symbol := c.symbol_of(t)!
			branch_name := symbol.name
			mut case_test := ''
			if t.flags & type_flag_es_symbol_like != 0 {
				branches << 'typeof ${branch_name}'
				case_test = branch_name
			} else {
				case_test = c.client.type_to_string_flags(c.snapshot, c.project, t.id,
					sec_type_format_flags)!
				branches << case_test
			}
			// A member of the switch's enum whose name is not an identifier: `Enum['a-b']`.
			if symbol_name != '' && !symbol.is_null() && requires_quoting(branch_name) {
				escaped := branch_name.replace("'", "\\'").replace('\n', '\\n').replace('\r',
					'\\r')
				case_test = symbol_name + "['" + escaped + "']"
			}
			quoted := case_test.replace('\\', '\\\\').replace("'", "\\'")
			missing_cases << "case ${case_test}: { throw new Error('Not implemented yet: ${quoted} case') }"
		}
		findings << Finding{
			stmt:        position_of(s.discriminant)
			message_id:  'switchIsNotExhaustive'
			data:        {
				'missingBranches': branches.join(' | ')
			}
			suggestions: c.sec_add_missing_cases(s, missing_cases)!
		}
	}
	if !o.allow_default_case_for_exhaustive_switch && missing.len == 0 && !contains_non_literal {
		if default_case := s.default_case {
			findings << Finding{
				stmt:       default_case
				message_id: 'dangerousDefaultCase'
			}
		}
	}
	if o.require_default_for_non_union && contains_non_literal && !has_default {
		findings << Finding{
			stmt:        position_of(s.discriminant)
			message_id:  'switchIsNotExhaustive'
			data:        {
				'missingBranches': 'default'
			}
			suggestions: c.sec_add_missing_cases(s, ["default: { throw new Error('default case') }"])!
		}
	}
}

// sec_add_missing_cases is the `addMissingCases` suggestion with those cases.
fn (mut c Checker) sec_add_missing_cases(s SwitchStatement, missing_cases []string) ![]Suggestion {
	fixes := c.sec_fix_switch(s, missing_cases)
	ok, suggestion := c.suggestion('addMissingCases', map[string]string{}, fixes)!
	return if ok { [suggestion] } else { []Suggestion{} }
}

// sec_fix_switch ports fixSwitch: the missing cases go before the default case (or the comment that
// stands for it), else after the last case, else in a new body, each one with the indentation of
// the last case (of the switch, if it has none).
fn (mut c Checker) sec_fix_switch(s SwitchStatement, missing_cases []string) []Fix {
	if s.cases.len > 0 {
		last_case := s.cases.last()
		case_indent := ' '.repeat(utf16_column(c.src, node_start(last_case)))
		if default_case := s.default_case {
			return [
				fix_insert_at(default_case.start_byte, missing_cases.map('${it}\n${case_indent}').join('')),
			]
		}
		// The end of the case in ESTree: its last token, not a comment tree-sitter leaves in it.
		end := if token := c.last_token(last_case) { token.end } else { node_end(last_case) }
		return [
			fix_insert_at(end, '\n' + missing_cases.map('${case_indent}${it}').join('\n')),
		]
	}
	// There are no cases: a new body, from the first `{` to the first `}` after the discriminant.
	case_indent := ' '.repeat(utf16_column(c.src, node_start(s.node)))
	opening := c.source_token_after(s.discriminant, '{') or { return []Fix{} }
	closing := c.source_token_after(s.discriminant, '}') or { return []Fix{} }
	body := ['{', missing_cases.map('${case_indent}${it}').join('\n'), '${case_indent}}']
	return [fix_replace_range(opening.start, closing.end, body.join('\n'))]
}
