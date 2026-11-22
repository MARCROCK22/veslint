module rules

import estree
import time

// Port of the `default-param-last` rule of typescript-eslint 8.72.2 (its own version of ESLint's
// rule, which also knows optional parameters and parameter properties), on the ESTree.

const dpl_messages = {
	'shouldBeLast': 'Default parameters should be last.'
}

fn (mut c Checker) lint_default_param_last(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	mut checked := 0
	for i, node in t.nodes {
		if node.typ !in [.arrow_function_expression, .function_declaration, .function_expression] {
			continue
		}
		checked++
		// checkDefaultParamLast.
		params := t.list(i, .params) or { continue }
		mut has_seen_plain_param := false
		for j := params.len - 1; j >= 0; j-- {
			current := params[j]
			param := if t.typ(current) == .ts_parameter_property {
				t.node(current, .parameter) or { current }
			} else {
				current
			}
			if dpl_is_plain_param(t, param) {
				has_seen_plain_param = true
				continue
			}
			if has_seen_plain_param
				&& (dpl_is_optional_param(t, param) || t.typ(param) == .assignment_pattern) {
				findings << Finding{
					stmt:       c.position_range(t.nodes[current].start, t.nodes[current].end)
					message_id: 'shouldBeLast'
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// dpl_is_optional_param ports isOptionalParam.
fn dpl_is_optional_param(t &estree.EsTree, node int) bool {
	return t.typ(node) in [.array_pattern, .assignment_pattern, .identifier, .object_pattern,
		.rest_element] && (t.flag(node, .optional) or { false })
}

// dpl_is_plain_param ports isPlainParam.
fn dpl_is_plain_param(t &estree.EsTree, node int) bool {
	return !(t.typ(node) in [.assignment_pattern, .rest_element] || dpl_is_optional_param(t, node))
}
