module rules

import estree
import json2
import time

// Port of the `perfectionist/sort-array-includes` rule of eslint-plugin-perfectionist 5.13.0: the
// elements of an array (or of `new Array(…)`) whose `includes` is called, sorted with the shared
// engine (perfectionist_utils*.v, perfectionist_sort_arrays_common.v), with all its options
// (type, order, fallbackSort, alphabet, ignoreCase, specialCharacters, locales, groups,
// customGroups, newlinesBetween, newlinesInside, partitionByComment, partitionByNewLine,
// useConfigurationIf), the `perfectionist` settings and the fixes.

const pfai_messages = {
	'unexpectedArrayIncludesOrder':             'Expected "{{right}}" to come before "{{left}}".'
	'unexpectedArrayIncludesGroupOrder':        'Expected "{{right}}" ({{rightGroup}}) to come before "{{left}}" ({{leftGroup}}).'
	'extraSpacingBetweenArrayIncludesMembers':  'Extra spacing between "{{left}}" and "{{right}}".'
	'missedSpacingBetweenArrayIncludesMembers': 'Missed spacing between "{{left}}" and "{{right}}".'
}

const pfai_message_ids = PfMessageIds{
	missed_spacing:         'missedSpacingBetweenArrayIncludesMembers'
	extra_spacing:          'extraSpacingBetweenArrayIncludesMembers'
	unexpected_group_order: 'unexpectedArrayIncludesGroupOrder'
	unexpected_order:       'unexpectedArrayIncludesOrder'
}

// pfai_default_options is the rule's defaultOptions (also those of sort-sets).
const pfai_default_options = '{"fallbackSort":{"type":"unsorted"},"newlinesInside":"newlinesBetween","specialCharacters":"keep","partitionByComment":false,"partitionByNewLine":false,"newlinesBetween":"ignore","useConfigurationIf":{},"type":"alphabetical","groups":["literal"],"ignoreCase":true,"locales":"en-US","customGroups":[],"alphabet":"","order":"asc"}'

// pf_options checks the options of a rule of perfectionist: a list of objects (its JSON schema
// tells the rest).
fn pf_options(options []json2.Any) ! {
	for option in options {
		if option !is map[string]json2.Any {
			return error('an option must be an object')
		}
	}
}

fn (mut c Checker) lint_perfectionist_sort_array_includes(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	t := c.es_tree(root, abs_path) or { return []Finding{} }
	mut ctx := c.pf_context(t, perfectionist_sort_array_includes)
	ctx.pf_sorters([.new_expression, .array_expression], fn (mut ctx PfContext, node int, matched []string) ! {
		if !pfai_is_valid_array(ctx.t, node) {
			return
		}
		ctx.pfsa_sort_array(node, matched, pf_decode_defaults(pfai_default_options), pfai_message_ids,
			false)!
	})!
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return ctx.findings
}

// pfai_is_valid_array ports isValidArray: the array is the object of `.includes` that is called.
fn pfai_is_valid_array(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .member_expression {
		return false
	}
	property := t.node(parent, .property) or { return false }
	if t.typ(property) != .identifier || (t.string_of(property, .name) or { '' }) != 'includes' {
		return false
	}
	grandparent := t.nodes[parent].parent
	if grandparent < 0 || t.typ(grandparent) != .call_expression {
		return false
	}
	return (t.node(grandparent, .callee) or { -1 }) == parent
}
