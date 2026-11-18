module rules

import estree

// Port of the `svelte/prefer-derived-over-derived-by` rule of eslint-plugin-svelte 3.24.1:
// `$derived.by(() => expr)` (or a function whose body only returns an expression) is reported;
// the fix makes it `$derived(expr)`, keeping a return type as the type argument, unless that
// would lose a comment, a type parameter, a type predicate or the function's own `this`,
// `new.target`, `arguments` or name. Its condition is runes mode (a component in runes mode or
// a `.svelte.[js|ts]` module). It runs on the lint code (it needs the scopes).

const svpdodb_messages = {
	'unnecessary': 'Unnecessary use of `$derived.by()`. Use `$derived()` directly for simple expressions.'
}

// svpdodb_parenthesized_range is getParenthesizedRange: the range of `target` with the parentheses
// around it that start inside its parent.
fn (mut c Checker) svpdodb_parenthesized_range(root C.TSNode, t &estree.EsTree, target int) (int, int) {
	tokens := c.source_tokens(root)
	mut start := t.nodes[target].start
	mut end := t.nodes[target].end
	parent := t.nodes[target].parent
	for {
		before := tokens.before(start, false) or { break }
		after := tokens.after(end, false) or { break }
		if !c.token_is(before, '(') || !c.token_is(after, ')') || parent < 0
			|| before.start < t.nodes[parent].start {
			break
		}
		start = before.start
		end = after.end
	}
	return start, end
}

// svpdodb_uses_this_or_new_target: `this` or `new.target` in the node, but in a function of its
// own (not an arrow function).
fn svpdodb_uses_this_or_new_target(t &estree.EsTree, node int) bool {
	match t.typ(node) {
		.this_expression {
			return true
		}
		.meta_property {
			meta := t.node(node, .meta) or { -1 }
			if meta >= 0 && (t.string_of(meta, .name) or { '' }) == 'new' {
				return true
			}
		}
		.function_expression, .function_declaration {
			return false
		}
		else {}
	}
	for child in t.children(node) {
		if svpdodb_uses_this_or_new_target(t, child) {
			return true
		}
	}
	return false
}

// svpdodb_uses_own_bindings: the function expression uses its `arguments`, its own name, `this` or
// `new.target`.
fn (mut c Checker) svpdodb_uses_own_bindings(root C.TSNode, t &estree.EsTree, fn_node int) bool {
	tree := c.scope_tree(root)
	if ts := t.ts_node(fn_node) {
		scope := tree.function_scope_of(ts)
		if scope >= 0 {
			if v := tree.scopes[scope].set['arguments'] {
				if tree.variables[v].references.len > 0 {
					return true
				}
			}
		}
	}
	if id := t.node(fn_node, .id) {
		if id_ts := t.ts_node(id) {
			v := tree.declared_variable(id_ts)
			if v >= 0 && tree.variables[v].references.len > 0 {
				return true
			}
		}
	}
	body := t.node(fn_node, .body) or { return false }
	return svpdodb_uses_this_or_new_target(t, body)
}

// svpdodb_fix is the fix of a report (none when it would lose something).
fn (mut c Checker) svpdodb_fix(root C.TSNode, t &estree.EsTree, call int, callee int, arg int, expression int) ?Fix {
	tokens := c.source_tokens(root)
	type_arguments := t.node(call, .type_arguments) or { -1 }
	mut return_type := -1
	if annotation := t.node(arg, .return_type) {
		return_type = t.node(annotation, .type_annotation) or { -1 }
	}
	if _ := t.node(arg, .type_parameters) {
		return none
	}
	if return_type >= 0 && t.typ(return_type) == .ts_type_predicate {
		return none
	}
	text := fn [c, t] (i int) string {
		return c.src[t.nodes[i].start..t.nodes[i].end]
	}
	if type_arguments >= 0 && return_type >= 0
		&& text(type_arguments) != '<${text(return_type)}>' {
		return none
	}
	if t.typ(arg) == .function_expression && c.svpdodb_uses_own_bindings(root, t, arg) {
		return none
	}
	body := t.node(arg, .body)?
	block := t.typ(body) == .block_statement
	mut before_expression := SourceToken{}
	if block {
		statement := t.nodes[expression].parent
		before_expression = tokens.after(t.nodes[statement].start, false)?
	} else {
		mut at := t.nodes[body].start
		for {
			token := tokens.before(at, false)?
			if c.token_is(token, '=>') {
				before_expression = token
				break
			}
			at = token.start
		}
	}
	kept_start := (tokens.after(before_expression.end, true)?).start
	kept_end := if block {
		_, end := c.svpdodb_parenthesized_range(root, t, expression)
		end
	} else {
		t.nodes[arg].end
	}
	type_text := if type_arguments < 0 && return_type >= 0 { '<${text(return_type)}>' } else { '' }
	object := t.node(callee, .object)?
	removed := [[t.nodes[object].end, t.nodes[callee].end], [t.nodes[arg].start, kept_start],
		[kept_end, t.nodes[arg].end]]
	for comment in tokens.comments_inside(t.nodes[call].start, t.nodes[call].end) {
		if type_text != '' && t.nodes[return_type].start <= comment.start
			&& comment.end <= t.nodes[return_type].end {
			continue
		}
		if removed.any(it[0] <= comment.start && comment.end <= it[1]) {
			return none
		}
	}
	mut needs_parens := false
	if t.typ(expression) == .sequence_expression {
		start, _ := c.svpdodb_parenthesized_range(root, t, expression)
		needs_parens = start == t.nodes[expression].start
	}
	has, fix := c.merge_fixes([
		fix_replace_range(removed[0][0], removed[0][1], type_text),
		fix_replace_range(removed[1][0], removed[1][1], if needs_parens { '(' } else { '' }),
		fix_replace_range(removed[2][0], removed[2][1], if needs_parens { ')' } else { '' }),
	]) or { return none }
	return if has { fix } else { none }
}

fn (mut c Checker) lint_svelte_prefer_derived_over_derived_by(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.svsc_runes_on(abs_path) || !c.src.contains('\$derived') {
		return []
	}
	t := c.es_tree(root, abs_path) or { return [] }
	mut findings := []Finding{}
	for i in 0 .. t.nodes.len {
		if t.typ(i) != .call_expression || i in t.foreign {
			continue
		}
		callee := t.node(i, .callee) or { continue }
		if t.typ(callee) != .member_expression || (t.flag(callee, .computed) or { false }) {
			continue
		}
		object := t.node(callee, .object) or { continue }
		property := t.node(callee, .property) or { continue }
		if t.typ(object) != .identifier || (t.string_of(object, .name) or { '' }) != '\$derived'
			|| t.typ(property) != .identifier || (t.string_of(property, .name) or { '' }) != 'by' {
			continue
		}
		args := t.list(i, .arguments) or { continue }
		if args.len != 1 || args[0] < 0 {
			continue
		}
		arg := args[0]
		if t.typ(arg) !in [.arrow_function_expression, .function_expression] {
			continue
		}
		if (t.list(arg, .params) or { []int{} }).len != 0 || (t.flag(arg, .async) or { false })
			|| (t.flag(arg, .generator) or { false }) {
			continue
		}
		body := t.node(arg, .body) or { continue }
		mut expression := -1
		if t.typ(arg) == .arrow_function_expression && t.typ(body) != .block_statement {
			expression = body
		} else if t.typ(body) == .block_statement {
			statements := t.list(body, .body) or { []int{} }
			if statements.len == 1 && t.typ(statements[0]) == .return_statement {
				expression = t.node(statements[0], .argument) or { -1 }
			}
		}
		if expression < 0 {
			continue
		}
		mut finding := Finding{
			stmt:       c.es_tree_position(t, i)
			message_id: 'unnecessary'
		}
		if fix := c.svpdodb_fix(root, t, i, callee, arg, expression) {
			finding = Finding{
				...finding
				has_fix: true
				fix:     fix
			}
		}
		findings << finding
	}
	return c.svsc_moved(findings)
}
