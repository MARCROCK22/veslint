module rules

import estree
import time

// Port of the `perfectionist/sort-sets` rule of eslint-plugin-perfectionist 5.13.0: the elements
// of the array (or of `new Array(…)`) a `new Set(…)` is made from, sorted as sort-array-includes
// sorts them (perfectionist_sort_arrays_common.v), with the same options and defaults.

const pfss_messages = {
	'unexpectedSetsOrder':             'Expected "{{right}}" to come before "{{left}}".'
	'unexpectedSetsGroupOrder':        'Expected "{{right}}" ({{rightGroup}}) to come before "{{left}}" ({{leftGroup}}).'
	'extraSpacingBetweenSetsMembers':  'Extra spacing between "{{left}}" and "{{right}}".'
	'missedSpacingBetweenSetsMembers': 'Missed spacing between "{{left}}" and "{{right}}".'
}

const pfss_message_ids = PfMessageIds{
	missed_spacing:         'missedSpacingBetweenSetsMembers'
	extra_spacing:          'extraSpacingBetweenSetsMembers'
	unexpected_group_order: 'unexpectedSetsGroupOrder'
	unexpected_order:       'unexpectedSetsOrder'
}

fn (mut c Checker) lint_perfectionist_sort_sets(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut ctx := c.pf_context(t, perfectionist_sort_sets)
	ctx.pf_sorters([.new_expression, .array_expression], fn (mut ctx PfContext, node int, matched []string) ! {
		if !pfss_is_valid_array(ctx.t, node) {
			return
		}
		ctx.pfsa_sort_array(node, matched, pf_decode_defaults(pfai_default_options), pfss_message_ids,
			false)!
	})!
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return ctx.findings
}

// pfss_is_valid_array ports isValidArray: the array is the first argument of `new Set(…)`.
fn pfss_is_valid_array(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .new_expression {
		return false
	}
	callee := t.node(parent, .callee) or { return false }
	if t.typ(callee) != .identifier || (t.string_of(callee, .name) or { '' }) != 'Set' {
		return false
	}
	arguments := t.list(parent, .arguments) or { return false }
	return arguments.len > 0 && arguments[0] == node
}
