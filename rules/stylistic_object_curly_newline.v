module rules

import estree
import time
import x.json2

// Port of the `@stylistic/object-curly-newline` rule of @stylistic/eslint-plugin 5.10.0, with its
// options (`"always"`, `"never"`, an object with `multiline`, `minProperties` and `consistent`, or
// one of those per node type: `ObjectExpression`, `ObjectPattern`, `ImportDeclaration`,
// `ExportDeclaration`, `TSTypeLiteral`, `TSInterfaceBody`, `TSEnumBody`) and its fixes: the line
// breaks after the opening brace and before the closing brace of objects, object patterns,
// imports, exports, type literals, interface bodies and enum bodies.

const socn_messages = {
	'unexpectedLinebreakBeforeClosingBrace': 'Unexpected line break before this closing brace.'
	'unexpectedLinebreakAfterOpeningBrace':  'Unexpected line break after this opening brace.'
	'expectedLinebreakBeforeClosingBrace':   'Expected a line break before this closing brace.'
	'expectedLinebreakAfterOpeningBrace':    'Expected a line break after this opening brace.'
}

// SocnOption is a normalized option value (normalizeOptionValue); `min_properties` is
// `max_int` for `Number.POSITIVE_INFINITY`.
struct SocnOption {
	multiline      bool
	min_properties int
	consistent     bool
}

// SocnOptions are the normalized options per node type (normalizeOptions).
struct SocnOptions {
	object_expression        SocnOption
	object_pattern           SocnOption
	import_declaration       SocnOption
	export_named_declaration SocnOption
	ts_type_literal          SocnOption
	ts_interface_body        SocnOption
	ts_enum_body             SocnOption
}

fn socn_options(given []json2.Any) !SocnOptions {
	value := if given.len > 0 { given[0] } else { json2.Any(json2.Null{}) }
	if value is map[string]json2.Any {
		// `Object.values(options).some(isNodeSpecificOption)`: an object or a string.
		mut node_specific := false
		for _, item in value {
			if item is map[string]json2.Any || item is string || item is []json2.Any {
				node_specific = true
				break
			}
		}
		if node_specific {
			get := fn [value] (key string) json2.Any {
				return value[key] or { json2.Any(json2.Null{}) }
			}
			return SocnOptions{
				object_expression:        socn_option_value(get('ObjectExpression'))
				object_pattern:           socn_option_value(get('ObjectPattern'))
				import_declaration:       socn_option_value(get('ImportDeclaration'))
				export_named_declaration: socn_option_value(get('ExportDeclaration'))
				ts_type_literal:          socn_option_value(get('TSTypeLiteral'))
				ts_interface_body:        socn_option_value(get('TSInterfaceBody'))
				ts_enum_body:             socn_option_value(get('TSEnumBody'))
			}
		}
	}
	option := socn_option_value(value)
	return SocnOptions{
		object_expression:        option
		object_pattern:           option
		import_declaration:       option
		export_named_declaration: option
		ts_type_literal:          option
		ts_interface_body:        option
		ts_enum_body:             option
	}
}

// socn_option_value ports normalizeOptionValue.
fn socn_option_value(value json2.Any) SocnOption {
	if value is string {
		return SocnOption{
			min_properties: if value == 'always' { 0 } else { max_i32 }
		}
	}
	if value is map[string]json2.Any {
		// `value.minProperties || Number.POSITIVE_INFINITY`: 0 is infinity too.
		mut min_properties := max_i32
		if given := value['minProperties'] {
			number := given.int()
			if number != 0 {
				min_properties = number
			}
		}
		return SocnOption{
			multiline:      sty_option_bool(value, 'multiline') or { false }
			min_properties: min_properties
			consistent:     sty_option_bool(value, 'consistent') or { false }
		}
	}
	return SocnOption{
		min_properties: max_i32
		consistent:     true
	}
}

fn (o SocnOptions) of(typ estree.NodeType) SocnOption {
	return match typ {
		.object_expression { o.object_expression }
		.object_pattern { o.object_pattern }
		.import_declaration { o.import_declaration }
		.export_named_declaration { o.export_named_declaration }
		.ts_type_literal { o.ts_type_literal }
		.ts_interface_body { o.ts_interface_body }
		else { o.ts_enum_body }
	}
}

fn (mut c Checker) lint_stylistic_object_curly_newline(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := socn_options(c.rule_options(stylistic_object_curly_newline))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		if t.typ(node) !in [.object_expression, .object_pattern, .import_declaration,
			.export_named_declaration, .ts_type_literal, .ts_interface_body, .ts_enum_body] {
			continue
		}
		stats.checked++
		c.socn_check(t, tokens, node, options.of(t.typ(node)), mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// socn_properties are the properties areLineBreaksRequired counts.
fn socn_properties(t &estree.EsTree, node int) int {
	return match t.typ(node) {
		.object_expression, .object_pattern {
			(t.list(node, .properties) or { []int{} }).len
		}
		.ts_type_literal, .ts_enum_body {
			(t.list(node, .members) or { []int{} }).len
		}
		.ts_interface_body {
			(t.list(node, .body) or { []int{} }).len
		}
		else {
			(t.list(node, .specifiers) or { []int{} }).filter(t.typ(it) in [.import_specifier,
				.export_specifier]).len
		}
	}
}

// socn_check ports check.
fn (c &Checker) socn_check(t &estree.EsTree, tokens &SourceTokens, node int, options SocnOption, mut findings []Finding) {
	typ := t.typ(node)
	if typ in [.import_declaration, .export_named_declaration] {
		wanted := if typ == .import_declaration {
			estree.NodeType.import_specifier
		} else {
			estree.NodeType.export_specifier
		}
		specifiers := t.list(node, .specifiers) or { []int{} }
		if !specifiers.any(t.typ(it) == wanted) {
			return
		}
	}
	inside := tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
	mut open_brace := SourceToken{}
	mut found_open := false
	for token in inside {
		if c.token_text(token) == '{' {
			open_brace = token
			found_open = true
			break
		}
	}
	if !found_open {
		return
	}
	mut close_brace := SourceToken{}
	mut found_close := false
	if typ == .object_pattern && t.node(node, .type_annotation) != none {
		annotation := t.node(node, .type_annotation) or { return }
		close_brace = tokens.before(t.nodes[annotation].start, false) or { return }
		found_close = true
	} else {
		for i := inside.len - 1; i >= 0; i-- {
			if c.token_text(inside[i]) == '}' {
				close_brace = inside[i]
				found_close = true
				break
			}
		}
	}
	if !found_close {
		return
	}
	first_any := tokens.after(open_brace.end, true) or { return }
	last_any := tokens.before(close_brace.start, true) or { return }
	properties := socn_properties(t, node)
	needs_line_breaks := properties >= options.min_properties
		|| (options.multiline && properties > 0 && !sty_same_line(t, last_any, first_any))
	has_comments_first_token := first_any.is_comment()
	has_comments_last_token := last_any.is_comment()
	first := tokens.after(open_brace.end, false) or { return }
	last := tokens.before(close_brace.start, false) or { return }
	if needs_line_breaks {
		if sty_same_line(t, open_brace, first) {
			findings << socn_report(c, open_brace, 'expectedLinebreakAfterOpeningBrace',
				!has_comments_first_token, fix_insert_at(open_brace.end, '\n'))
		}
		if sty_same_line(t, last, close_brace) {
			findings << socn_report(c, close_brace, 'expectedLinebreakBeforeClosingBrace',
				!has_comments_last_token, fix_insert_at(close_brace.start, '\n'))
		}
	} else {
		consistent := options.consistent
		break_after_open := !sty_same_line(t, open_brace, first)
		break_before_close := !sty_same_line(t, last, close_brace)
		if (!consistent && break_after_open)
			|| (consistent && break_after_open && !break_before_close) {
			findings << socn_report(c, open_brace, 'unexpectedLinebreakAfterOpeningBrace',
				!has_comments_first_token, fix_remove_range(open_brace.end, first.start))
		}
		if (!consistent && break_before_close)
			|| (consistent && !break_after_open && break_before_close) {
			findings << socn_report(c, close_brace, 'unexpectedLinebreakBeforeClosingBrace',
				!has_comments_last_token, fix_remove_range(last.end, close_brace.start))
		}
	}
}

fn socn_report(c &Checker, brace SourceToken, message_id string, has_fix bool, fix Fix) Finding {
	return Finding{
		stmt:       c.position_range(brace.start, brace.end)
		message_id: message_id
		has_fix:    has_fix
		fix:        if has_fix { fix } else { Fix{} }
	}
}
