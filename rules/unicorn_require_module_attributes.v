module rules

import estree
import time

// Port of the `unicorn/require-module-attributes` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fix.

const urma_messages = {
	'require-module-attributes': '{{type}} with empty attribute list is not allowed.'
}

fn (mut c Checker) lint_unicorn_require_module_attributes(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.import_declaration, .export_named_declaration, .export_all_declaration {
				stats.checked++
				if f := c.urma_declaration(t, tokens, node) {
					findings << f
				}
			}
			.import_expression {
				stats.checked++
				if f := c.urma_import_expression(t, tokens, node) {
					findings << f
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) urma_declaration(t &estree.EsTree, tokens &SourceTokens, declaration int) ?Finding {
	source := t.node(declaration, .source)?
	if (t.list(declaration, .attributes) or { []int{} }).len > 0 {
		return none
	}
	with := tokens.after(t.nodes[source].end, false)?
	if !(with.kind == .keyword && c.src[with.start..with.end] == 'with') {
		return none
	}
	// A `with` statement is not possible in a module: these are the attributes.
	opening := tokens.after(with.end, false)?
	closing := tokens.after(opening.end, false)?
	mut finding := Finding{
		stmt:       c.position_range(opening.start, closing.end)
		message_id: 'require-module-attributes'
		data:       {
			'type': if t.typ(declaration) == .import_declaration {
				'import statement'
			} else {
				'export statement'
			}
		}
	}
	if !tokens.comments_exist_between(with.end, closing.start) {
		has_fix, fix := c.merge_fixes([fix_remove_range(with.start, with.end),
			fix_remove_range(closing.start, closing.end), fix_remove_range(opening.start, opening.end)]) or {
			return finding
		}
		finding = Finding{
			...finding
			has_fix: has_fix
			fix:     fix
		}
	}
	return finding
}

// urma_is_empty_with: a `with: {}` property.
fn urma_is_empty_with(t &estree.EsTree, property int) bool {
	if t.typ(property) != .property || (t.flag(property, .method) or { false })
		|| (t.flag(property, .shorthand) or { false }) || (t.flag(property, .computed) or { false })
		|| (t.string_of(property, .kind) or { '' }) != 'init' {
		return false
	}
	key := t.node(property, .key) or { return false }
	named := (t.typ(key) == .identifier && (t.string_of(key, .name) or { '' }) == 'with')
		|| (t.typ(key) == .literal && t.get(key, .value) is string && t.get(key, .value) as string == 'with')
	return named && un_is_empty_object(t, t.node(property, .value) or { -1 })
}

fn (c &Checker) urma_import_expression(t &estree.EsTree, tokens &SourceTokens, expression int) ?Finding {
	options := t.node(expression, .options)?
	if t.typ(options) != .object_expression {
		return none
	}
	properties := t.list(options, .properties) or { []int{} }
	mut empty_with := -1
	for property in properties {
		if urma_is_empty_with(t, property) {
			empty_with = property
			break
		}
	}
	to_remove := if properties.len == 0 || (empty_with >= 0 && properties.len == 1) {
		options
	} else {
		empty_with
	}
	if to_remove < 0 {
		return none
	}
	report := if empty_with >= 0 { t.node(empty_with, .value)? } else { to_remove }
	mut finding := Finding{
		stmt:       c.es_tree_position(t, report)
		message_id: 'require-module-attributes'
		data:       {
			'type': 'import expression'
		}
	}
	if tokens.comments_inside(t.nodes[to_remove].start, t.nodes[to_remove].end).len > 0 {
		return finding
	}
	mut fixes := []Fix{}
	if t.typ(to_remove) == .property {
		// removeObjectProperty
		for token in tokens.inside(t.nodes[to_remove].start, t.nodes[to_remove].end, false) {
			fixes << fix_remove_range(token.start, token.end)
		}
		after := tokens.after(t.nodes[to_remove].end, false)
		if a := after {
			if c.token_is(a, ',') {
				fixes << fix_remove_range(a.start, a.end)
			} else if properties.len > 1 && properties.last() == to_remove {
				comma := tokens.before(t.nodes[to_remove].start, false)?
				fixes << fix_remove_range(comma.start, comma.end)
			}
		}
	} else {
		mut at := t.nodes[to_remove].start
		for {
			token := tokens.before(at, false)?
			if c.token_is(token, ',') {
				fixes << fix_remove_range(token.start, token.end)
				break
			}
			at = token.start
		}
		for token in tokens.inside(t.nodes[to_remove].start, t.nodes[to_remove].end, false) {
			fixes << fix_remove_range(token.start, token.end)
		}
		for token in c.un_parentheses(t, tokens, to_remove) {
			fixes << fix_remove_range(token.start, token.end)
		}
	}
	has_fix, fix := c.merge_fixes(fixes) or { return finding }
	return Finding{
		...finding
		has_fix: has_fix
		fix:     fix
	}
}
