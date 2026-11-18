module rules

import estree
import treesitter { node_kind }

// Port of the `svelte/prefer-writable-derived` rule of eslint-plugin-svelte 3.24.1 (Svelte 5.25.0 or
// later, which veslint's is): a `$effect` (or `$effect.pre`) whose callback only assigns
// `x = expr`, where `x` is a variable initialized with `$state(…)`, is reported on that
// variable's declarator, with a suggestion that initializes it with `$derived(expr)` and removes
// the effect. Its condition is runes mode. It runs on the lint code (the scopes).

const svpwd_messages = {
	'unexpected':     'Prefer using writable \$derived instead of \$state and \$effect'
	'suggestRewrite': 'Rewrite \$state and \$effect to \$derived'
}

// svpwd_is_effect is isEffectOrEffectPre.
fn svpwd_is_effect(t &estree.EsTree, call int) bool {
	callee := t.node(call, .callee) or { return false }
	if t.typ(callee) == .identifier {
		return (t.string_of(callee, .name) or { '' }) == '\$effect'
	}
	if t.typ(callee) == .member_expression {
		object := t.node(callee, .object) or { return false }
		property := t.node(callee, .property) or { return false }
		return t.typ(object) == .identifier && (t.string_of(object, .name) or { '' }) == '\$effect'
			&& t.typ(property) == .identifier && (t.string_of(property, .name) or { '' }) == 'pre'
	}
	return false
}

fn (mut c Checker) lint_svelte_prefer_writable_derived(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.svsc_runes_on(abs_path) || !c.src.contains('\$effect') {
		return []
	}
	t := c.es_tree(root, abs_path) or { return [] }
	tree := c.scope_tree(root)
	mut findings := []Finding{}
	for call in 0 .. t.nodes.len {
		if call in t.foreign || t.typ(call) != .call_expression || !svpwd_is_effect(t, call) {
			continue
		}
		args := t.list(call, .arguments) or { continue }
		if args.len != 1 || args[0] < 0 {
			continue
		}
		argument := args[0]
		if t.typ(argument) !in [.function_expression, .arrow_function_expression]
			|| (t.list(argument, .params) or { [0] }).len != 0 {
			continue
		}
		body := t.node(argument, .body) or { continue }
		statements := t.list(body, .body) or { continue }
		if t.typ(body) != .block_statement || statements.len != 1 {
			continue
		}
		statement := statements[0]
		if t.typ(statement) != .expression_statement {
			continue
		}
		assignment := t.node(statement, .expression) or { continue }
		if t.typ(assignment) != .assignment_expression
			|| (t.string_of(assignment, .operator) or { '' }) != '=' {
			continue
		}
		left := t.node(assignment, .left) or { continue }
		right := t.node(assignment, .right) or { continue }
		if t.typ(left) != .identifier {
			continue
		}
		name := t.string_of(left, .name) or { continue }
		statement_ts := t.ts_node(statement) or { continue }
		scope := tree.get_scope(statement_ts)
		mut reference := -1
		for r in tree.scopes[scope].references {
			if tree.references[r].name == name {
				reference = r
				break
			}
		}
		if reference < 0 || tree.references[reference].resolved < 0 {
			continue
		}
		variable := tree.variables[tree.references[reference].resolved]
		if variable.defs.len == 0 || variable.defs[0].kind != .variable
			|| node_kind(variable.defs[0].node) != 'variable_declarator' {
			continue
		}
		declarator := c.es_index_of(t, variable.defs[0].node) or { continue }
		init := t.node(declarator, .init) or { continue }
		if t.typ(init) != .call_expression {
			continue
		}
		callee := t.node(init, .callee) or { continue }
		if t.typ(callee) != .identifier || (t.string_of(callee, .name) or { '' }) != '\$state' {
			continue
		}
		mut suggestions := []Suggestion{}
		has, fix := c.merge_fixes([
			fix_replace_range(t.nodes[init].start, t.nodes[init].end, '\$derived(${c.src[t.nodes[right].start..t.nodes[right].end]})'),
			fix_replace_range(t.nodes[call].start, t.nodes[call].end, ''),
		]) or { false, Fix{} }
		if has {
			suggestions << Suggestion{
				message_id: 'suggestRewrite'
				fix:        fix
			}
		}
		findings << Finding{
			stmt:        c.es_tree_position(t, declarator)
			message_id:  'unexpected'
			suggestions: suggestions
		}
	}
	return c.svsc_moved(findings)
}
