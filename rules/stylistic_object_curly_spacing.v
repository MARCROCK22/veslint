module rules

import estree
import time
import x.json2

// Port of the `@stylistic/object-curly-spacing` rule of @stylistic/eslint-plugin 6.0.1, with its
// options (`"always"` or `"never"`, the default, and `arraysInObjects`, `objectsInObjects`,
// `overrides` and `emptyObjects`) and its fixes: the spaces inside the braces of objects, object
// patterns, imports, exports, import attributes, mapped types, type literals, interface bodies and
// enum bodies.

const socsp_messages = {
	'requireSpaceBefore':           "A space is required before '{{token}}'."
	'requireSpaceAfter':            "A space is required after '{{token}}'."
	'unexpectedSpaceBefore':        "There should be no space before '{{token}}'."
	'unexpectedSpaceAfter':         "There should be no space after '{{token}}'."
	'requiredSpaceInEmptyObject':   "A space is required in empty '{{node}}'."
	'unexpectedSpaceInEmptyObject': "There should be no space in empty '{{node}}'."
}

struct SocspOptions {
	spaced                       bool
	arrays_in_objects_exception  bool
	objects_in_objects_exception bool
	overrides                    map[string]string
	empty_objects                string
}

fn socsp_options(given []json2.Any) !SocspOptions {
	options := sty_options(given, [json2.Any('never')])
	spaced := sty_option_string(options, 0, '') == 'always'
	// isOptionSet: `secondOption[option] === !spaced`.
	second := sty_option_object(options, 1)
	is_set := fn [second, spaced] (option string) bool {
		value := sty_option_bool(second, option) or { return false }
		return value == !spaced
	}
	mut overrides := map[string]string{}
	if given_overrides := second['overrides'] {
		if given_overrides is map[string]json2.Any {
			for key, value in given_overrides {
				if value is string {
					overrides[key] = value
				}
			}
		}
	}
	mut empty_objects := 'ignore'
	if value := second['emptyObjects'] {
		if value is string {
			empty_objects = value
		}
	}
	return SocspOptions{
		spaced:                       spaced
		arrays_in_objects_exception:  is_set('arraysInObjects')
		objects_in_objects_exception: is_set('objectsInObjects')
		overrides:                    overrides
		empty_objects:                empty_objects
	}
}

struct SocspCtx {
	t       &estree.EsTree
	tokens  &SourceTokens
	options SocspOptions
}

fn (mut c Checker) lint_stylistic_object_curly_spacing(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := socsp_options(c.rule_options(stylistic_object_curly_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	ctx := SocspCtx{
		t:       t
		tokens:  c.un_tokens(t)
		options: options
	}
	for node in 0 .. t.nodes.len {
		typ := t.typ(node)
		match typ {
			.object_pattern, .object_expression {
				c.socsp_check_object_like(ctx, node, t.list(node, .properties) or { []int{} }.len,
					socsp_type_name(typ), mut findings)
			}
			.import_declaration {
				if attributes := t.list(node, .attributes) {
					c.socsp_check_object_like(ctx, node, attributes.len, 'ImportAttributes', mut
						findings)
				}
				specifiers := t.list(node, .specifiers) or { []int{} }
				mut first_specifier := -1
				for i, specifier in specifiers {
					if t.typ(specifier) == .import_specifier {
						first_specifier = i
						break
					}
				}
				if first_specifier == -1 {
					c.socsp_check_object_like(ctx, node, 0, 'ImportDeclaration', mut findings)
				} else {
					c.socsp_check_object_like(ctx, node, specifiers.len - first_specifier,
						'ImportDeclaration', mut findings)
				}
			}
			.export_named_declaration {
				c.socsp_check_object_like(ctx, node, t.list(node, .specifiers) or { []int{} }.len,
					'ExportNamedDeclaration', mut findings)
				if attributes := t.list(node, .attributes) {
					c.socsp_check_object_like(ctx, node, attributes.len, 'ImportAttributes', mut
						findings)
				}
			}
			.export_all_declaration {
				if attributes := t.list(node, .attributes) {
					c.socsp_check_object_like(ctx, node, attributes.len, 'ImportAttributes', mut
						findings)
				}
			}
			.ts_mapped_type {
				first := un_first_token(t, ctx.tokens, node, 0) or { continue }
				last := un_last_token(t, ctx.tokens, node) or { continue }
				c.socsp_validate(ctx, first, last, 'TSMappedType', mut findings)
			}
			.ts_type_literal {
				c.socsp_check_object_like(ctx, node, t.list(node, .members) or { []int{} }.len,
					'TSTypeLiteral', mut findings)
			}
			.ts_interface_body {
				c.socsp_check_object_like(ctx, node, t.list(node, .body) or { []int{} }.len,
					'TSInterfaceBody', mut findings)
			}
			.ts_enum_body {
				c.socsp_check_object_like(ctx, node, t.list(node, .members) or { []int{} }.len,
					'TSEnumBody', mut findings)
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

fn socsp_type_name(typ estree.NodeType) string {
	return if typ == .object_pattern { 'ObjectPattern' } else { 'ObjectExpression' }
}

// socsp_check_object_like ports checkForObjectLike, with the number of properties.
fn (c &Checker) socsp_check_object_like(ctx SocspCtx, node int, properties int, node_type string, mut findings []Finding) {
	opening, closing := c.socsp_brace_tokens(ctx, node, node_type) or { return }
	if properties == 0 {
		c.socsp_check_empty(ctx, opening, closing, node_type, mut findings)
		return
	}
	c.socsp_validate(ctx, opening, closing, node_type, mut findings)
}

// socsp_brace_tokens ports getBraceToken.
fn (c &Checker) socsp_brace_tokens(ctx SocspCtx, node int, node_type string) ?(SourceToken, SourceToken) {
	t := ctx.t
	node_tokens := ctx.tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
	match node_type {
		'ImportDeclaration', 'ExportNamedDeclaration', 'ExportAllDeclaration' {
			opening := socsp_find(c, node_tokens, '{', false)?
			closing := socsp_find(c, node_tokens, '}', false)?
			return opening, closing
		}
		'ImportAttributes' {
			opening := socsp_find(c, node_tokens, '{', true)?
			closing := socsp_find(c, node_tokens, '}', true)?
			source := t.node(node, .source)?
			if opening.start < t.nodes[source].start {
				return none
			}
			return opening, closing
		}
		else {
			opening := socsp_find(c, node_tokens, '{', false)?
			if t.typ(node) == .object_pattern {
				if annotation := t.node(node, .type_annotation) {
					// getTokenBefore(node.typeAnnotation, isClosingBraceToken): the `}` before an
					// optional pattern's `?` too, as `({ a }?: T) => void`.
					mut before := ctx.tokens.before(t.nodes[annotation].start, false)?
					for !c.token_is(before, '}') {
						before = ctx.tokens.before(before.start, false)?
					}
					return opening, before
				}
			}
			return opening, socsp_find(c, node_tokens, '}', true)?
		}
	}
}

// socsp_find is `tokens.find` (or `findLast`) of the punctuator.
fn socsp_find(c &Checker, tokens []SourceToken, punctuator string, last bool) ?SourceToken {
	if last {
		for i := tokens.len - 1; i >= 0; i-- {
			if c.token_is(tokens[i], punctuator) {
				return tokens[i]
			}
		}
	} else {
		for token in tokens {
			if c.token_is(token, punctuator) {
				return token
			}
		}
	}
	return none
}

// socsp_validate ports validateBraceSpacing.
fn (c &Checker) socsp_validate(ctx SocspCtx, opening SourceToken, closing SourceToken, node_type string, mut findings []Finding) {
	t := ctx.t
	options := ctx.options
	after_opening := ctx.tokens.after(opening.end, true) or { return }
	spaced := if override := options.overrides[node_type] {
		if override != '' { override == 'always' } else { options.spaced }
	} else {
		options.spaced
	}
	if sty_same_line(t, opening, after_opening) {
		first_spaced := ctx.tokens.is_space_between(opening.end, after_opening.start)
		second := sty_node_by_range_index(t, after_opening.start)
		second_type := if second >= 0 { t.typ(second) } else { estree.NodeType.program }
		opening_must_be_spaced := if options.arrays_in_objects_exception
			&& second_type in [.ts_mapped_type, .ts_index_signature] {
			!spaced
		} else {
			spaced
		}
		if opening_must_be_spaced && !first_spaced {
			findings << c.socsp_report(opening.start, opening.end, 'requireSpaceAfter',
				'token', c.token_text(opening), fix_insert_at(opening.end, ' '))
		}
		if !opening_must_be_spaced && first_spaced
			&& !(after_opening.is_comment() && !sty_same_line(t, opening, closing)) {
			findings << c.socsp_report(opening.end, after_opening.start, 'unexpectedSpaceAfter',
				'token', c.token_text(opening), fix_remove_range(opening.end, after_opening.start))
		}
	}
	before_closing := ctx.tokens.before(closing.start, true) or { return }
	if sty_same_line(t, before_closing, closing) {
		mut penultimate_type := ?estree.NodeType(none)
		if (options.arrays_in_objects_exception && c.token_is(before_closing, ']'))
			|| (options.objects_in_objects_exception && c.token_is(before_closing, '}')) {
			penultimate := sty_node_by_range_index(t, before_closing.start)
			if penultimate >= 0 {
				penultimate_type = t.typ(penultimate)
			}
		}
		mut exception := false
		if typ := penultimate_type {
			exception = (options.arrays_in_objects_exception
				&& typ in [.array_expression, .ts_tuple_type])
				|| (options.objects_in_objects_exception
				&& typ in [.object_expression, .object_pattern, .ts_mapped_type, .ts_type_literal])
		}
		closing_must_be_spaced := if exception { !spaced } else { spaced }
		last_spaced := ctx.tokens.is_space_between(before_closing.end, closing.start)
		if closing_must_be_spaced && !last_spaced {
			findings << c.socsp_report(closing.start, closing.end, 'requireSpaceBefore',
				'token', c.token_text(closing), fix_insert_at(closing.start, ' '))
		}
		if !closing_must_be_spaced && last_spaced {
			findings << c.socsp_report(before_closing.end, closing.start, 'unexpectedSpaceBefore',
				'token', c.token_text(closing), fix_remove_range(before_closing.end, closing.start))
		}
	}
}

// socsp_check_empty ports checkSpaceInEmptyObjectLike.
fn (c &Checker) socsp_check_empty(ctx SocspCtx, opening SourceToken, closing SourceToken, node_type string, mut findings []Finding) {
	empty_objects := ctx.options.empty_objects
	if empty_objects == 'ignore' || !sty_same_line(ctx.t, opening, closing)
		|| ctx.tokens.comments_exist_between(opening.end, closing.start) {
		return
	}
	between := if opening.start + 1 <= closing.end - 1 {
		c.src[opening.start + 1..closing.end - 1]
	} else {
		''
	}
	if js_trim(between) != '' {
		return
	}
	if empty_objects == 'always' {
		if between == ' ' {
			return
		}
		findings << c.socsp_report(opening.end, closing.start, 'requiredSpaceInEmptyObject',
			'node', node_type, fix_replace_range(opening.end, closing.start, ' '))
	} else if empty_objects == 'never' {
		if between == '' {
			return
		}
		findings << c.socsp_report(opening.end, closing.start, 'unexpectedSpaceInEmptyObject',
			'node', node_type, fix_remove_range(opening.end, closing.start))
	}
}

fn (c &Checker) socsp_report(start int, end int, message_id string, key string, value string, fix Fix) Finding {
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
		data:       {
			key: value
		}
		has_fix:    true
		fix:        fix
	}
}
