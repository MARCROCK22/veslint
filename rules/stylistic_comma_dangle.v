module rules

import estree
import time
import x.json2

// Port of the `@stylistic/comma-dangle` rule of @stylistic/eslint-plugin 5.10.0, with its options
// (`"never"`, the default, `"always"`, `"always-multiline"`, `"only-multiline"`, or one of those or
// `"ignore"` per kind: `arrays`, `objects`, `imports`, `exports`, `functions`, `importAttributes`,
// `dynamicImports`, `enums`, `generics`, `tuples`) and its fixes: the trailing commas of lists.

const scd_messages = {
	'unexpected': 'Unexpected trailing comma.'
	'missing':    'Missing trailing comma.'
}

// ScdOptions are the normalized options (normalizeOptions), one value per kind.
struct ScdOptions {
	arrays            string
	objects           string
	imports           string
	exports           string
	functions         string
	import_attributes string
	dynamic_imports   string
	enums             string
	generics          string
	tuples            string
}

fn scd_options(given []json2.Any) !ScdOptions {
	return scd_normalize(sty_options(given, [json2.Any('never')]), 0)
}

// scd_normalize ports normalizeOptions with the normalized ecmaVersion of the file (0 when it is
// not known, which keeps the options as they are).
fn scd_normalize(options []json2.Any, ecma_version int) ScdOptions {
	value := if options.len > 0 { options[0] } else { json2.Any(json2.Null{}) }
	if value is string {
		return ScdOptions{
			arrays:            value
			objects:           value
			imports:           value
			exports:           value
			functions:         if ecma_version == 0 || ecma_version >= 2017 { value } else { 'ignore' }
			import_attributes: value
			dynamic_imports:   if ecma_version == 0 || ecma_version >= 2025 { value } else { 'ignore' }
			enums:             value
			generics:          value
			tuples:            value
		}
	}
	object := sls_object(value)
	get := fn [object] (key string) string {
		item := object[key] or { return 'never' }
		return if item is string { item } else { 'never' }
	}
	return ScdOptions{
		arrays:            get('arrays')
		objects:           get('objects')
		imports:           get('imports')
		exports:           get('exports')
		functions:         get('functions')
		import_attributes: get('importAttributes')
		dynamic_imports:   get('dynamicImports')
		enums:             get('enums')
		generics:          get('generics')
		tuples:            get('tuples')
	}
}

struct ScdCtx {
	t      &estree.EsTree
	tokens &SourceTokens
	is_tsx bool
}

fn (mut c Checker) lint_stylistic_comma_dangle(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := scd_normalize(sty_options(c.rule_options(stylistic_comma_dangle), [
		json2.Any('never'),
	]), c.ecma_version)
	t := c.es_tree(root, abs_path) or { return findings }
	ctx := ScdCtx{
		t:      t
		tokens: c.un_tokens(t)
		is_tsx: c.language.jsx && abs_path.ends_with('.tsx')
	}
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.object_expression, .object_pattern {
				c.scd_predicate(ctx, options.objects, node, scd_last(t.list(node, .properties)), mut
					findings)!
			}
			.array_expression, .array_pattern {
				c.scd_predicate(ctx, options.arrays, node, scd_last(t.list(node, .elements)), mut
					findings)!
			}
			.import_declaration {
				last_specifier := scd_last(t.list(node, .specifiers))
				if last_specifier >= 0 && t.typ(last_specifier) == .import_specifier {
					c.scd_predicate(ctx, options.imports, node, last_specifier, mut findings)!
				}
				c.scd_predicate(ctx, options.import_attributes, node, scd_last(t.list(node,
					.attributes)), mut findings)!
			}
			.export_named_declaration {
				c.scd_predicate(ctx, options.exports, node, scd_last(t.list(node, .specifiers)), mut
					findings)!
				c.scd_predicate(ctx, options.import_attributes, node, scd_last(t.list(node,
					.attributes)), mut findings)!
			}
			.export_all_declaration {
				c.scd_predicate(ctx, options.import_attributes, node, scd_last(t.list(node,
					.attributes)), mut findings)!
			}
			.function_declaration, .function_expression, .arrow_function_expression,
			.ts_declare_function, .ts_function_type {
				c.scd_predicate(ctx, options.functions, node, scd_last(t.list(node, .params)), mut
					findings)!
			}
			.call_expression, .new_expression {
				c.scd_predicate(ctx, options.functions, node, scd_last(t.list(node, .arguments)), mut
					findings)!
			}
			.import_expression {
				last_item := t.node(node, .options) or { t.node(node, .source) or { -1 } }
				c.scd_predicate(ctx, options.dynamic_imports, node, last_item, mut findings)!
			}
			.ts_enum_declaration {
				members := if body := t.node(node, .body) {
					t.list(body, .members)
				} else {
					t.list(node, .members)
				}
				c.scd_predicate(ctx, options.enums, node, scd_last(members), mut findings)!
			}
			.ts_type_parameter_declaration {
				c.scd_predicate(ctx, options.generics, node, scd_last(t.list(node, .params)), mut
					findings)!
			}
			.ts_type_parameter_instantiation {
				c.scd_predicate(ctx, 'never', node, scd_last(t.list(node, .params)), mut findings)!
			}
			.ts_tuple_type {
				c.scd_predicate(ctx, options.tuples, node, scd_last(t.list(node, .element_types)), mut
					findings)!
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

// scd_last ports last(): the last item, -1 (null) for none or a hole.
fn scd_last(nodes ?[]int) int {
	list := nodes or { return -1 }
	return if list.len > 0 { list.last() } else { -1 }
}

// scd_predicate runs the check of the option value.
fn (c &Checker) scd_predicate(ctx ScdCtx, value string, node int, last_item int, mut findings []Finding) ! {
	match value {
		'always' {
			c.scd_force(ctx, node, last_item, mut findings)!
		}
		'always-multiline' {
			if c.scd_is_multiline(ctx, node, last_item) {
				c.scd_force(ctx, node, last_item, mut findings)!
			} else {
				c.scd_forbid(ctx, node, last_item, mut findings)!
			}
		}
		'only-multiline' {
			if !c.scd_is_multiline(ctx, node, last_item) {
				c.scd_forbid(ctx, node, last_item, mut findings)!
			}
		}
		'never' {
			c.scd_forbid(ctx, node, last_item, mut findings)!
		}
		else {}
	}
}

// scd_trailing_token ports getTrailingToken.
fn (c &Checker) scd_trailing_token(ctx ScdCtx, node int, last_item int) ?SourceToken {
	t := ctx.t
	match t.typ(node) {
		.object_expression, .array_expression, .call_expression, .new_expression, .import_expression {
			inside := ctx.tokens.inside(t.nodes[node].start, t.nodes[node].end, false)
			return if inside.len >= 2 { inside[inside.len - 2] } else { none }
		}
		else {
			if last_item < 0 {
				return none
			}
			next := ctx.tokens.after(t.nodes[last_item].end, false)?
			if c.token_is(next, ',') {
				return next
			}
			return un_last_token(t, ctx.tokens, last_item)
		}
	}
}

// scd_is_multiline ports isMultiline.
fn (c &Checker) scd_is_multiline(ctx ScdCtx, node int, last_item int) bool {
	if last_item < 0 {
		return false
	}
	penultimate := c.scd_trailing_token(ctx, node, last_item) or { return false }
	last := ctx.tokens.after(penultimate.end, false) or { return false }
	return !sty_same_line_offsets(ctx.t, last.end, penultimate.end)
}

// scd_forbid ports forbidTrailingComma.
fn (c &Checker) scd_forbid(ctx ScdCtx, node int, last_item int, mut findings []Finding) ! {
	t := ctx.t
	if ctx.is_tsx && t.typ(node) == .ts_type_parameter_declaration
		&& (t.list(node, .params) or { []int{} }).len == 1 {
		return
	}
	if last_item < 0 {
		return
	}
	trailing := c.scd_trailing_token(ctx, node, last_item) or { return }
	if !c.token_is(trailing, ',') {
		return
	}
	before := ctx.tokens.before(trailing.start, false) or { return }
	after := ctx.tokens.after(trailing.end, false) or { return }
	has_fix, fix := c.merge_fixes([fix_remove_range(trailing.start, trailing.end),
		fix_insert_at(before.start, ''), fix_insert_at(after.end, '')])!
	findings << Finding{
		stmt:       c.position_range(trailing.start, trailing.end)
		message_id: 'unexpected'
		has_fix:    has_fix
		fix:        fix
	}
}

// scd_force ports forceTrailingComma.
fn (c &Checker) scd_force(ctx ScdCtx, node int, last_item int, mut findings []Finding) ! {
	t := ctx.t
	if last_item < 0 {
		return
	}
	// isTrailingCommaAllowed.
	if t.typ(last_item) == .rest_element {
		c.scd_forbid(ctx, node, last_item, mut findings)!
		return
	}
	trailing := c.scd_trailing_token(ctx, node, last_item) or { return }
	if c.token_text(trailing) == ',' {
		return
	}
	next := ctx.tokens.after(trailing.end, false) or { return }
	if c.token_text(next) !in ['}', ']', ')', '>'] {
		return
	}
	has_fix, fix := c.merge_fixes([fix_insert_at(trailing.end, ','),
		fix_insert_at(trailing.start, ''), fix_insert_at(next.end, '')])!
	findings << Finding{
		stmt:       c.position_range(trailing.end, sty_next_location(t, trailing.end))
		message_id: 'missing'
		has_fix:    has_fix
		fix:        fix
	}
}
