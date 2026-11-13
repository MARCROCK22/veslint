module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-implied-eval` rule of ESLint 10.6.0 (it has no options); typescript-eslint's
// rule of the same name is in no_implied_eval.v.

const niec_messages = {
	'impliedEval': 'Implied eval. Consider passing a function instead of a string.'
	'execScript':  'Implied eval. Do not use execScript().'
}

const niec_eval_like = ['setInterval', 'setTimeout', 'execScript']

fn (mut c Checker) lint_core_no_implied_eval(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut reported := map[u64]bool{}
	for node in c.nodes_of_kinds(root, ['call_expression'], []) {
		callee := unwrap_parens(node_field(node, 'function') or { continue })
		if node_kind(callee) != 'identifier' || c.text(callee) !in niec_eval_like
			|| !c.es_is_global_reference(root, callee) {
			continue
		}
		stats.checked++
		c.niec_report(root, node, mut findings, mut reported)
	}
	// Through `window`, `global`, `globalThis` and `self` (`window.window.setTimeout`).
	tree := c.scope_tree(root)
	for name in ['global', 'window', 'globalThis', 'self'] {
		v := tree.find_variable(0, name, -1)
		if v < 0 || tree.variables[v].defs.len > 0 {
			continue
		}
		for r in tree.variables[v].references {
			mut node := cti_estree_parent(tree.references[r].identifier) or { continue }
			for c.es_is_specific_member_access(node, '', name) {
				node = cti_estree_parent(node) or { break }
			}
			property := c.es_static_property_name(node) or { continue }
			if node_kind(node) !in ['member_expression', 'subscript_expression']
				|| property !in niec_eval_like {
				continue
			}
			call := es_callee_of(node) or { continue }
			if node_kind(call) == 'call_expression' {
				stats.checked++
				c.niec_report(root, call, mut findings, mut reported)
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// niec_is_evaluated_string ports isEvaluatedString: a string, a template, or a `+` with one.
fn niec_is_evaluated_string(n C.TSNode) bool {
	node := unwrap_parens(n)
	if node_kind(node) in ['string', 'template_string'] {
		return true
	}
	if node_kind(node) == 'binary_expression' && operator_of(node) == '+' {
		return niec_is_evaluated_string(node_field(node, 'left') or { return false })
			|| niec_is_evaluated_string(node_field(node, 'right') or { return false })
	}
	return false
}

// niec_report ports reportImpliedEvalCallExpression: a first argument that is a string.
fn (mut c Checker) niec_report(root C.TSNode, call C.TSNode, mut findings []Finding, mut reported map[u64]bool) {
	args := (call_arguments(call) or { return }).filter(node_kind(it) != 'comment')
	if args.len == 0 {
		return
	}
	value := c.get_static_value(args[0])
	if !((value.found && value.value.kind == .string_) || niec_is_evaluated_string(args[0])) {
		return
	}
	key := node_key(call)
	if key in reported {
		return
	}
	reported[key] = true
	callee := unwrap_parens(node_field(call, 'function') or { return })
	name := if node_kind(callee) == 'identifier' {
		c.text(callee)
	} else {
		c.es_static_property_name(callee) or { '' }
	}
	findings << Finding{
		stmt:       position_of(call)
		message_id: if name == 'execScript' { 'execScript' } else { 'impliedEval' }
	}
}
