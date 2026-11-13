module rules

import time
import treesitter { node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-unused-labels` rule of ESLint 10.6.0, with its fix (it has no options).

const nul_messages = {
	'unused': "'{{name}}:' is defined but never used."
}

const nul_function_kinds = ['function_declaration', 'function_expression', 'generator_function',
	'generator_function_declaration', 'arrow_function', 'method_definition']

fn (mut c Checker) lint_no_unused_labels(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	// The labeled statements some `break` or `continue` uses: the closest one with its label.
	mut used := map[u64]bool{}
	for node in c.nodes_of_kinds(root, ['break_statement', 'continue_statement'], []) {
		label := node_field(node, 'label') or { continue }
		name := c.text(label)
		mut current := node
		for {
			current = node_parent(current) or { break }
			if node_kind(current) == 'labeled_statement'
				&& c.text(node_field(current, 'label') or { continue }) == name {
				used[node_key(current)] = true
				break
			}
		}
	}
	for node in c.nodes_of_kinds(root, ['labeled_statement'], []) {
		stats.checked++
		if node_key(node) in used {
			continue
		}
		label := node_field(node, 'label') or { continue }
		body := node_field(node, 'body') or { continue }
		findings << Finding{
			stmt:       position_of(label)
			message_id: 'unused'
			data:       {
				'name': c.text(label)
			}
			has_fix:    c.nul_is_fixable(node, label, body)
			fix:        fix_remove_range(node_start(node), node_start(body))
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nul_is_fixable ports isFixable: only the `:` between the label and the body (no comment), and
// the body is not a string expression statement where it could become a directive.
fn (c &Checker) nul_is_fixable(node C.TSNode, label C.TSNode, body C.TSNode) bool {
	if c.src[node_end(label)..node_start(body)].trim_space() != ':' {
		return false
	}
	mut ancestor := node_parent(node) or { return true }
	for node_kind(ancestor) == 'labeled_statement' {
		ancestor = node_parent(ancestor) or { return true }
	}
	mut directive_place := node_kind(ancestor) == 'program'
	if node_kind(ancestor) == 'statement_block' {
		if parent := node_parent(ancestor) {
			directive_place = node_kind(parent) in nul_function_kinds
		}
	}
	if directive_place && node_kind(body) == 'expression_statement' {
		expression := unwrap_parens(first_named(body) or { return true })
		if node_kind(expression) == 'string' {
			return false
		}
		if node_kind(expression) == 'template_string' {
			expressions, _ := c.es_template_parts(expression)
			return expressions.len > 0
		}
	}
	return true
}
